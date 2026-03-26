{ pkgs, lib ? pkgs.lib, name }:

let
  config = import ./config.nix { inherit name; };

  host        = config.network.host;
  bindAddress = config.network.bindAddress;
  tlsConfig   = config.tls;
  logDir  = config.logDir;
  logFile = config.logFile;
  certDir     = tlsConfig.certDir;
  protocol    = if tlsConfig.enable then "https" else "http";

  frontendPort = toString config.vite.port;
  backendPort  = toString config.haskell.port;
  dbPort       = toString config.database.port;

  backendDir  = builtins.head (builtins.split "/[^/]*$" (builtins.head config.haskell.codeDirs));
  frontendDir = builtins.head (builtins.split "/[^/]*$" (builtins.head config.purescript.codeDirs));
  dataDir     = config.dataDir;

  firewallOpen = ''
    echo "Ensuring firewall ports are open..."
    sudo iptables -C INPUT -p tcp --dport ${backendPort} -j ACCEPT 2>/dev/null || \
      sudo iptables -I INPUT -p tcp --dport ${backendPort} -j ACCEPT
    sudo iptables -C INPUT -p tcp --dport ${frontendPort} -j ACCEPT 2>/dev/null || \
      sudo iptables -I INPUT -p tcp --dport ${frontendPort} -j ACCEPT
    echo "  Ports ${backendPort} and ${frontendPort} open"
  '';

  tlsEnvSetup = if tlsConfig.enable then ''
    echo "Setting up TLS certificates..."
    tls-setup
    CERT_DIR="$(echo "${certDir}" | envsubst)"
    export USE_TLS="true"
    export TLS_CERT_FILE="$CERT_DIR/${tlsConfig.certFile}"
    export TLS_KEY_FILE="$CERT_DIR/${tlsConfig.keyFile}"
  '' else ''
    export USE_TLS="false"
  '';

  tlsEnvPrefix = if tlsConfig.enable then
    ''CERT_DIR="$(echo "${certDir}" | envsubst)" USE_TLS=true TLS_CERT_FILE="$CERT_DIR/${tlsConfig.certFile}" TLS_KEY_FILE="$CERT_DIR/${tlsConfig.keyFile}" ''
  else "";

  tlsEnvPrefixNix = if tlsConfig.enable then
    ''USE_TLS=true TLS_CERT_FILE="'"$TLS_CERT_FILE"'" TLS_KEY_FILE="'"$TLS_KEY_FILE"'" ''
  else "";

  pgStartWithBackup = ''
    BACKUP_DIR="${dataDir}/backups"
    mkdir -p "$BACKUP_DIR"
    LATEST_BACKUP="$(find "$BACKUP_DIR" -type f -name '*.sql' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"

    if [ -z "$LATEST_BACKUP" ]; then
      echo "No backup found, starting fresh database..."
      pg-start
    else
      echo "Found backup at $LATEST_BACKUP"
      pg-start
      echo "Restoring from backup..."
      pg-restore "$LATEST_BACKUP"
    fi
  '';

  tmuxLayout = ''
    tmux kill-session -t ${name} 2>/dev/null || true
    tmux new-session -d -s ${name} -n "Services" -x 120 -y 42

    tmux split-window -v -b -l 12
    tmux split-window -h -t ${name}:Services.0 -p 66
    tmux split-window -h -t ${name}:Services.1 -p 50

    tmux resize-pane -t ${name}:Services.0 -y 12
    tmux resize-pane -t ${name}:Services.1 -y 12
    tmux resize-pane -t ${name}:Services.2 -y 12
  '';

  tmuxAttach = ''
    tmux send-keys -t ${name}:Services.2 'watch -n 5 pg-stats' C-m
    tmux send-keys -t ${name}:Services.3 \
      'echo "Backend: ${protocol}://${host}:${backendPort}"; echo "Frontend: ${protocol}://${host}:${frontendPort}"' C-m

    tmux set-hook -t ${name} client-resized \
      'resize-pane -t ${name}:Services.0 -y 12; resize-pane -t ${name}:Services.1 -y 12; resize-pane -t ${name}:Services.2 -y 12'

    tmux select-pane -t ${name}:Services.3
    tmux attach-session -t ${name}
  '';

  stopCore = ''
    echo "Creating database backup..."
    pg-backup
    echo "Database backup completed."

    echo "Stopping database..."
    pg-stop || { echo "Failed to stop PostgreSQL completely"; exit 1; }
    echo "Database stopped."

    echo "Stopping vite..."
    vite-cleanup || true

    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" || echo "")
    if [ -n "$VITE_PIDS" ]; then
      for pid in $VITE_PIDS; do kill -9 "$pid" 2>/dev/null || true; done
    fi

    PORT_PIDS=$(${pkgs.lsof}/bin/lsof -i :${frontendPort} -t \
      | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$PORT_PIDS" ]; then
      for pid in $PORT_PIDS; do kill -9 "$pid" 2>/dev/null || true; done
    fi
  '';

  killTmux = ''
    if tmux has-session -t ${name} 2>/dev/null; then
      for pane_index in 0 1 2 3; do
        tmux send-keys -t ${name}:Services.$pane_index C-c 2>/dev/null || true
      done
      sleep 2
      tmux detach-client -s ${name} 2>/dev/null || true
      ( tmux kill-session -t ${name} 2>/dev/null || true; sleep 1 ) & wait
      if tmux has-session -t ${name} 2>/dev/null; then
        ( tmux kill-server 2>/dev/null || true ) & wait
      fi
    fi
  '';

  deploy = pkgs.writeShellScriptBin "deploy" ''
    set -euo pipefail

    echo "Building projects..."
    (cd ${backendDir} && cabal build) || { echo "Backend build failed"; exit 1; }
    (cd ${frontendDir} && spago build) || { echo "Frontend build failed"; exit 1; }

    ${pgStartWithBackup}
    ${tlsEnvSetup}
    ${firewallOpen}

    LOG_DIR="$(echo "${logDir}" | envsubst)"
    LOG_FILE="$(echo "${logFile}" | envsubst)"
    mkdir -p "$LOG_DIR"

    echo "TMux Commands:"
    echo "  Ctrl-b d  Detach | Ctrl-b o  Switch panes | Ctrl-b z  Zoom"
    echo "  Arrow keys  Navigate (with Ctrl-b) | Ctrl-b [  Scroll mode (q to exit)"
    echo ""
    echo "Starting services..."
    echo "  Backend:  ${protocol}://${host}:${backendPort}"
    echo "  Frontend: ${protocol}://${host}:${frontendPort}"
    echo "  Postgres: ${host}:${dbPort}"
    echo "  Log:      $LOG_FILE"
    echo ""

    ${tmuxLayout}

    echo "Starting backend..."
    tmux send-keys -t ${name}:Services.0 \
      '${tlsEnvPrefix}export USE_REAL_AUTH=true; export LOG_FILE="'"$LOG_FILE"'"; export PGPASSWORD=$(sops-get db_password); export ALLOWED_ORIGIN=$(sops-get allowed_origin 2>/dev/null || true); cd ${backendDir} && cabal run ${name}-backend' C-m

    echo "Waiting for backend..."
    RETRIES=0
    while ! ${pkgs.curl}/bin/curl -sk "${protocol}://${host}:${backendPort}/inventory" > /dev/null 2>&1; do
      RETRIES=$((RETRIES + 1))
      [ $RETRIES -ge 120 ] && { echo "Backend did not start within 120 seconds."; exit 1; }
      sleep 1
    done
    echo "  Backend ready"

    echo "Starting frontend..."
    tmux send-keys -t ${name}:Services.1 \
      '${tlsEnvPrefix}cd ${frontendDir} && vite --host ${bindAddress} --port ${frontendPort} --open' C-m

    ${tmuxAttach}
  '';

  stop = pkgs.writeShellScriptBin "stop" ''
    set -euo pipefail
    OUR_PID=$$
    PARENT_PID=$PPID

    ${stopCore}
    ${killTmux}

    BACKEND_PIDS=$(pgrep -f "${name}-backend" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" || echo "")
    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" || echo "")
    if [ -n "$BACKEND_PIDS" ] || [ -n "$VITE_PIDS" ]; then
      for pid in $BACKEND_PIDS $VITE_PIDS; do kill -9 "$pid" 2>/dev/null || true; done
    fi

    echo "All services stopped."
  '';

  # launch-dev intentionally omits ALLOWED_ORIGIN so CORS stays open for local development.
  launch-dev = pkgs.writeShellScriptBin "launch-dev" ''
    set -euo pipefail
    PROJECT_DIR="$(pwd)"

    ${if tlsConfig.enable then ''
      echo "Setting up TLS certificates..."
      tls-setup
      CERT_DIR="$(echo "${certDir}" | envsubst)"
      TLS_CERT="$CERT_DIR/${tlsConfig.certFile}"
      TLS_KEY="$CERT_DIR/${tlsConfig.keyFile}"
    '' else "true"}

    LOG_DIR="$(echo "${logDir}" | envsubst)"
    LOG_FILE="$(echo "${logFile}" | envsubst)"
    mkdir -p "$LOG_DIR"

    _ENV_FILE="$(mktemp /tmp/${name}-env-XXXXXX.sh)"
    cat > "$_ENV_FILE" <<EOF
export USE_TLS="${if tlsConfig.enable then "true" else "false"}"
${if tlsConfig.enable then ''
export TLS_CERT_FILE="$TLS_CERT"
export TLS_KEY_FILE="$TLS_KEY"
'' else ""}
export USE_REAL_AUTH="true"
export LOG_FILE="$LOG_FILE"
export PGPASSWORD="$(sops-get db_password)"
EOF

    ${firewallOpen}
    echo "Launching ${name} in separate Alacritty windows..."
    echo "Project: $PROJECT_DIR"
    echo "Log:     $LOG_FILE"
    echo "Note: CORS is open in dev mode (ALLOWED_ORIGIN not set)"

    ${pkgs.alacritty}/bin/alacritty \
      --title "${name} - Database" \
      --working-directory "$PROJECT_DIR" \
      -e ${pkgs.bash}/bin/bash -c \
        '${pkgs.direnv}/bin/direnv exec "'"$PROJECT_DIR"'" db-start' &

    echo "Waiting for database..."
    RETRIES=0
    while ! ${pkgs.postgresql}/bin/pg_isready -h "$PGDATA" -p "${dbPort}" -q 2>/dev/null; do
      RETRIES=$((RETRIES + 1))
      [ $RETRIES -ge 30 ] && { echo "Database failed to start within 30 seconds"; exit 1; }
      sleep 1
    done
    echo "  Database ready"

    ${pkgs.alacritty}/bin/alacritty \
      --title "${name} - Backend" \
      --working-directory "$PROJECT_DIR" \
      -e ${pkgs.bash}/bin/bash -c \
        ". $_ENV_FILE && cd $PROJECT_DIR/${backendDir} && cabal run ${name}-backend" &

    echo "Waiting for backend..."
    RETRIES=0
    while ! ${pkgs.curl}/bin/curl -sk "${protocol}://${host}:${backendPort}/inventory" > /dev/null 2>&1; do
      RETRIES=$((RETRIES + 1))
      [ $RETRIES -ge 60 ] && { echo "Backend failed to start within 60 seconds"; exit 1; }
      sleep 1
    done
    echo "  Backend ready"

    ${pkgs.alacritty}/bin/alacritty \
      --title "${name} - Frontend" \
      --working-directory "$PROJECT_DIR" \
      -e ${pkgs.bash}/bin/bash -c \
        ". $_ENV_FILE && cd $PROJECT_DIR/${frontendDir} && npx vite --host ${bindAddress} --port ${frontendPort} --open" &

    echo ""
    echo "All windows launched."
    echo "  Database:  window 1 (port ${dbPort})"
    echo "  Backend:   window 2 (${protocol}://${host}:${backendPort})"
    echo "  Frontend:  window 3 (${protocol}://${host}:${frontendPort})"
    echo "  Log:       $LOG_FILE"
  '';

  db-start = pkgs.writeShellScriptBin "db-start" ''
    set -euo pipefail
    echo "Starting database service on port ${dbPort}..."
    ${pgStartWithBackup}
    echo "Database started at ${host}:${dbPort}"
    echo ""
    echo "Monitor with: watch -n 5 pg-stats  |  Backup: pg-backup  |  Stop: pg-stop"
    watch -n 5 pg-stats
  '';

  db-stop = pkgs.writeShellScriptBin "db-stop" ''
    set -euo pipefail
    echo "Creating database backup..."
    pg-backup
    echo "Database backup completed."
    echo "Stopping database..."
    pg-stop || { echo "Failed to stop PostgreSQL completely"; exit 1; }
    echo "Database stopped successfully."
  '';

  backend-start = pkgs.writeShellScriptBin "backend-start" ''
    set -euo pipefail
    echo "Building and starting Haskell backend..."

    if [ ! -f "${backendDir}/cabal.project" ] && [ ! -f "${backendDir}/${name}-backend.cabal" ]; then
      if [ -f "cabal.project" ] || [ -f "${name}-backend.cabal" ]; then
        BACKEND_DIR="."
      else
        echo "Error: Cannot find backend directory. Run from project root or backend directory."
        exit 1
      fi
    else
      BACKEND_DIR="${backendDir}"
    fi

    (cd "$BACKEND_DIR" && cabal build) || { echo "Backend build failed"; exit 1; }

    LOG_DIR="$(echo "${logDir}" | envsubst)"
    LOG_FILE="$(echo "${logFile}" | envsubst)"
    mkdir -p "$LOG_DIR"

    ${tlsEnvSetup}
    export USE_REAL_AUTH="true"
    export LOG_FILE="$LOG_FILE"
    export PGPASSWORD="$(sops-get db_password)"
    export ALLOWED_ORIGIN="$(sops-get allowed_origin 2>/dev/null || true)"

    echo "Starting backend on ${protocol}://${host}:${backendPort}..."
    echo "  Log: $LOG_FILE"
    cd "$BACKEND_DIR" && exec cabal run ${name}-backend
  '';

  backend-stop = pkgs.writeShellScriptBin "backend-stop" ''
    set -euo pipefail
    BACKEND_PIDS=$(pgrep -f "${name}-backend" 2>/dev/null || echo "")
    if [ -n "$BACKEND_PIDS" ]; then
      for pid in $BACKEND_PIDS; do kill -TERM "$pid" 2>/dev/null || true; done
      sleep 2
      REMAINING=$(pgrep -f "${name}-backend" 2>/dev/null || echo "")
      [ -n "$REMAINING" ] && for pid in $REMAINING; do kill -9 "$pid" 2>/dev/null || true; done
    fi
    echo "Backend stopped."
  '';

  frontend-start = pkgs.writeShellScriptBin "frontend-start" ''
    set -euo pipefail
    if [ ! -f "${frontendDir}/spago.yaml" ] && [ ! -f "${frontendDir}/spago.dhall" ] && [ ! -f "${frontendDir}/package.json" ]; then
      if [ -f "spago.yaml" ] || [ -f "spago.dhall" ] || [ -f "package.json" ]; then
        FRONTEND_DIR="."
      else
        echo "Error: Cannot find frontend directory. Run from project root or frontend directory."
        exit 1
      fi
    else
      FRONTEND_DIR="${frontendDir}"
    fi

    VITE_PIDS=$(pgrep -f "vite" 2>/dev/null || echo "")
    if [ -n "$VITE_PIDS" ]; then
      for pid in $VITE_PIDS; do kill -TERM "$pid" 2>/dev/null || true; done
      sleep 1
    fi

    if ${pkgs.lsof}/bin/lsof -i :${frontendPort} &>/dev/null; then
      PORT_PIDS=$(${pkgs.lsof}/bin/lsof -i :${frontendPort} -t 2>/dev/null || echo "")
      for pid in $PORT_PIDS; do kill -TERM "$pid" 2>/dev/null || true; done
      sleep 1
    fi

    (cd "$FRONTEND_DIR" && spago build) || { echo "Frontend build failed"; exit 1; }
    cd "$FRONTEND_DIR" && exec vite --host ${bindAddress} --port ${frontendPort} --open
  '';

  frontend-stop = pkgs.writeShellScriptBin "frontend-stop" ''
    set -euo pipefail
    OUR_PID=$$
    PARENT_PID=$PPID

    vite-cleanup 2>/dev/null || true

    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$VITE_PIDS" ]; then
      for pid in $VITE_PIDS; do kill -TERM "$pid" 2>/dev/null || true; done
      sleep 1
      REMAINING=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
      [ -n "$REMAINING" ] && for pid in $REMAINING; do kill -9 "$pid" 2>/dev/null || true; done
    fi

    PORT_PIDS=$(${pkgs.lsof}/bin/lsof -i :${frontendPort} -t \
      | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    [ -n "$PORT_PIDS" ] && for pid in $PORT_PIDS; do kill -9 "$pid" 2>/dev/null || true; done

    echo "Frontend stopped."
  '';

  build-all = pkgs.writeShellScriptBin "build-all" ''
    set -euo pipefail
    echo "Building ${name}..."
    nix build .
    echo ""
    echo "Build complete."
    echo "  Binary:   ./result/bin/${name}-backend"
    echo "  Frontend: ./result-frontend"
  '';

  deploy-nix = pkgs.writeShellScriptBin "deploy-nix" ''
    set -euo pipefail
    LOGDIR="$(echo "${logDir}" | envsubst)"
    LOG_FILE="$(echo "${logFile}" | envsubst)"
    PIDDIR="$(echo "${dataDir}" | envsubst)/pids"
    BACKUP_DIR="$(echo "${dataDir}" | envsubst)/backups"
    mkdir -p "$LOGDIR" "$PIDDIR" "$BACKUP_DIR"

    [ ! -f "./result/bin/${name}-backend" ] && { echo "Binary not found, building..."; nix build .; }

    echo "Starting PostgreSQL on port ${dbPort}..."
    LATEST_BACKUP="$(find "$BACKUP_DIR" -type f -name '*.sql' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
    pg-start
    [ -n "$LATEST_BACKUP" ] && { echo "Restoring from backup: $LATEST_BACKUP"; pg-restore "$LATEST_BACKUP"; }

    ${tlsEnvSetup}
    ${firewallOpen}

    _ALLOWED_ORIGIN="$(sops-get allowed_origin 2>/dev/null || true)"

    echo "Starting backend..."
    echo "  Log: $LOG_FILE"
    ${if tlsConfig.enable then ''
      USE_TLS=true TLS_CERT_FILE="$TLS_CERT_FILE" TLS_KEY_FILE="$TLS_KEY_FILE" \
      USE_REAL_AUTH=true \
      LOG_FILE="$LOG_FILE" \
      PGPASSWORD="$(sops-get db_password)" \
      ALLOWED_ORIGIN="$_ALLOWED_ORIGIN" \
      ./result/bin/${name}-backend > "$LOGDIR/stdout.log" 2>&1 &
    '' else ''
      USE_TLS=false \
      USE_REAL_AUTH=true \
      LOG_FILE="$LOG_FILE" \
      PGPASSWORD="$(sops-get db_password)" \
      ALLOWED_ORIGIN="$_ALLOWED_ORIGIN" \
      ./result/bin/${name}-backend > "$LOGDIR/stdout.log" 2>&1 &
    ''}
    echo $! > "$PIDDIR/backend.pid"

    echo "Waiting for backend..."
    for i in $(seq 1 30); do
      ${pkgs.curl}/bin/curl -s ${if tlsConfig.enable then "-k" else ""} \
        ${protocol}://${host}:${backendPort}/inventory > /dev/null 2>&1 && { echo "Backend ready."; break; }
      sleep 1
    done

    echo "Starting frontend..."
    cd ${frontendDir}
    ${pkgs.nodejs}/bin/npx vite --host ${bindAddress} --port ${frontendPort} > "$LOGDIR/vite.log" 2>&1 &
    echo $! > "$PIDDIR/frontend.pid"
    cd ..

    echo ""
    echo "Services started."
    echo "  Backend:  ${protocol}://${host}:${backendPort} (PID: $(cat $PIDDIR/backend.pid))"
    echo "  Frontend: ${protocol}://${host}:${frontendPort} (PID: $(cat $PIDDIR/frontend.pid))"
    echo "  Postgres: ${host}:${dbPort}"
    echo "  Log:      $LOG_FILE"
    echo "  Stdout:   $LOGDIR/stdout.log"
    if [ -n "$_ALLOWED_ORIGIN" ]; then
      echo "  CORS: locked to $_ALLOWED_ORIGIN"
    else
      echo "  CORS: open (set allowed_origin in sops to lock)"
    fi
  '';

  deploy-nix-interactive = pkgs.writeShellScriptBin "deploy-nix-interactive" ''
    set -euo pipefail
    BACKUP_DIR="$(echo "${dataDir}" | envsubst)/backups"
    LOG_FILE="$(echo "${logFile}" | envsubst)"
    LOG_DIR="$(echo "${logDir}" | envsubst)"
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"

    [ ! -f "./result/bin/${name}-backend" ] && { echo "Binary not found, building..."; nix build .; }

    LATEST_BACKUP="$(find "$BACKUP_DIR" -type f -name '*.sql' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
    pg-start
    [ -n "$LATEST_BACKUP" ] && { echo "Restoring from backup: $LATEST_BACKUP"; pg-restore "$LATEST_BACKUP"; }

    ${tlsEnvSetup}
    ${firewallOpen}

    _ALLOWED_ORIGIN="$(sops-get allowed_origin 2>/dev/null || true)"

    ${tmuxLayout}
    tmux send-keys -t ${name}:Services.0 \
      '${tlsEnvPrefixNix}USE_REAL_AUTH=true LOG_FILE="'"$LOG_FILE"'" PGPASSWORD=$(sops-get db_password) ALLOWED_ORIGIN="'"$_ALLOWED_ORIGIN"'" ./result/bin/${name}-backend' C-m
    tmux send-keys -t ${name}:Services.1 \
      'cd ${frontendDir} && vite --host ${bindAddress} --port ${frontendPort} --open' C-m
    ${tmuxAttach}
  '';

  stop-nix = pkgs.writeShellScriptBin "stop-nix" ''
    set -euo pipefail
    PIDDIR="${dataDir}/pids"

    echo "Backing up database..."
    pg-backup || true

    for service in backend frontend; do
      PIDFILE="$PIDDIR/$service.pid"
      if [ -f "$PIDFILE" ]; then
        PID=$(cat "$PIDFILE")
        if kill -0 "$PID" 2>/dev/null; then
          echo "Stopping $service (PID: $PID)..."
          kill -TERM "$PID" 2>/dev/null || true
          sleep 2
          kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
        fi
        rm -f "$PIDFILE"
      fi
    done

    ${pkgs.lsof}/bin/lsof -ti :${frontendPort} | xargs -r kill -9 2>/dev/null || true
    tmux kill-session -t ${name} 2>/dev/null || true
    pg-stop || true

    echo "All services stopped."
  '';

  status-nix = pkgs.writeShellScriptBin "status-nix" ''
    PIDDIR="${dataDir}/pids"

    echo "${name} Service Status"
    echo "===================="
    echo ""

    for service in backend frontend; do
      PIDFILE="$PIDDIR/$service.pid"
      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "$service: running (PID: $(cat "$PIDFILE"))"
      else
        echo "$service: stopped"
      fi
    done

    echo ""
    echo "Configuration:"
    echo "  Host:     ${host}"
    echo "  Bind:     ${bindAddress}"
    echo "  Protocol: ${protocol}"
    echo "  Backend:  ${protocol}://${host}:${backendPort}"
    echo "  Frontend: ${protocol}://${host}:${frontendPort}"
    echo "  Postgres: ${host}:${dbPort}"
    echo "  TLS:      ${if tlsConfig.enable then "enabled" else "disabled"}"
    echo ""
    pg-stats 2>/dev/null || echo "postgres: stopped"
  '';

  tui = pkgs.writeShellScriptBin "${name}-tui" ''
    set -euo pipefail
    _G="${pkgs.gum}/bin/gum"

    show_config() {
      "$_G" style --foreground 10 --bold "  ${name} configuration"
      echo ""
      echo "  Host:         ${host}"
      echo "  Bind:         ${bindAddress}"
      echo "  Protocol:     ${protocol}"
      echo "  Backend:      ${protocol}://${host}:${backendPort}"
      echo "  Frontend:     ${protocol}://${host}:${frontendPort}"
      echo "  Postgres:     ${host}:${dbPort}"
      echo "  TLS:          ${if tlsConfig.enable then "enabled" else "disabled"}"
      echo "  Backend dir:  ${backendDir}"
      echo "  Frontend dir: ${frontendDir}"
      echo "  Data dir:     ${dataDir}"
      ${if tlsConfig.enable then ''
        CERT_DIR="$(echo "${certDir}" | envsubst)"
        echo "  Cert:         $CERT_DIR/${tlsConfig.certFile}"
        echo "  Key:          $CERT_DIR/${tlsConfig.keyFile}"
      '' else ""}
    }

    case "''${1:-}" in
      --build)                nix build .; exit 0 ;;
      --deploy)               deploy-nix; exit 0 ;;
      --deploy-interactive)   deploy-nix-interactive; exit 0 ;;
      --deploy-source)        deploy; exit 0 ;;
      --launch-dev)           launch-dev; exit 0 ;;
      --stop)                 stop-nix; exit 0 ;;
      --stop-source)          stop; exit 0 ;;
      --status)               status-nix; exit 0 ;;
      --config)               show_config; exit 0 ;;
      --gc)                   nix-collect-garbage -d; exit 0 ;;
      --update)               nix flake update; exit 0 ;;
      --tls-setup)            tls-setup; exit 0 ;;
      --tls-info)             tls-info; exit 0 ;;
      --tls-clean)            tls-clean; exit 0 ;;
      --container-load)       container-load; exit 0 ;;
      --container-run)        container-run; exit 0 ;;
      --container-stop)       container-stop; exit 0 ;;
      --db-start)             db-start; exit 0 ;;
      --db-stop)              db-stop; exit 0 ;;
      --db-backup)            pg-backup; exit 0 ;;
      --db-stats)             pg-stats; exit 0 ;;
      --backend-start)        backend-start; exit 0 ;;
      --backend-stop)         backend-stop; exit 0 ;;
      --frontend-start)       frontend-start; exit 0 ;;
      --frontend-stop)        frontend-stop; exit 0 ;;
      --bootstrap-admin)      bootstrap-admin; exit 0 ;;
      --admin-password)       sops-get admin_password; exit 0 ;;
      --sops-status)          sops-status; exit 0 ;;
      --test-unit)            test-unit; exit 0 ;;
      --test-integration)     test-integration; exit 0 ;;
      --test-integration-tls) test-integration-tls; exit 0 ;;
      --test-suite)           test-suite; exit 0 ;;
      --test-smoke)           test-smoke; exit 0 ;;
      --help)
        echo "Usage: ${name}-tui [OPTION]"
        echo "Run without arguments for interactive TUI."
        echo ""
        echo "  --build --deploy --deploy-interactive --deploy-source"
        echo "  --launch-dev --stop --stop-source --status --config"
        echo "  --container-load --container-run --container-stop"
        echo "  --db-start --db-stop --db-backup --db-stats"
        echo "  --backend-start --backend-stop --frontend-start --frontend-stop"
        echo "  --bootstrap-admin --admin-password --sops-status"
        echo "  --test-unit --test-integration --test-integration-tls"
        echo "  --test-suite --test-smoke"
        echo "  --tls-setup --tls-info --tls-clean --gc --update"
        exit 0 ;;
      "")
        ;;
      *)
        echo "Unknown option: ''${1}"
        echo "Run '${name}-tui --help' for usage."
        exit 1 ;;
    esac

    pause() {
      echo ""
      read -r -p "  Press Enter to continue..."
    }

    header() {
      clear
      "$_G" style \
        --foreground 10 --border-foreground 2 --border double \
        --align center --width 54 --margin "1 2" --padding "1 3" \
        "${lib.toUpper name}" "management console"
      echo ""
    }

    section() {
      clear
      "$_G" style \
        --foreground 10 --border-foreground 2 --border normal \
        --align center --width 54 --margin "0 2" --padding "0 3" \
        "$1"
      echo ""
    }

    while true; do
      header
      CATEGORY=$("$_G" choose \
        --cursor "> " \
        --header "  Select a category:" \
        --height 10 \
        "Deploy & Build" \
        "Containers" \
        "Components" \
        "Auth & Secrets" \
        "Testing" \
        "Maintenance" \
        "Quit") || break

      case "$CATEGORY" in

        "Deploy & Build")
          while true; do
            section "Deploy & Build"
            ACTION=$("$_G" choose \
              --cursor "> " \
              --header "  Choose action:" \
              --height 12 \
              "Build (nix build .)" \
              "Deploy headless (nix)" \
              "Deploy tmux (nix)" \
              "Stop nix deployment" \
              "Status" \
              "Deploy tmux (source)" \
              "Launch dev (Alacritty)" \
              "Stop source deployment" \
              "Back") || break
            case "$ACTION" in
              "Build (nix build .)") nix build . ; pause ;;
              "Deploy headless (nix)") deploy-nix ; pause ;;
              "Deploy tmux (nix)") deploy-nix-interactive ; break 2 ;;
              "Stop nix deployment") stop-nix ; pause ;;
              "Status") status-nix ; pause ;;
              "Deploy tmux (source)") deploy ; break 2 ;;
              "Launch dev (Alacritty)") launch-dev ; break 2 ;;
              "Stop source deployment") stop ; pause ;;
              "Back") break ;;
            esac
          done ;;

        "Containers")
          while true; do
            section "Containers"
            ACTION=$("$_G" choose \
              --cursor "> " \
              --header "  Choose action:" \
              --height 6 \
              "Load images into podman" \
              "Run containers" \
              "Stop containers" \
              "Back") || break
            case "$ACTION" in
              "Load images into podman") container-load ; pause ;;
              "Run containers") container-run ; pause ;;
              "Stop containers") container-stop ; pause ;;
              "Back") break ;;
            esac
          done ;;

        "Components")
          while true; do
            section "Components"
            ACTION=$("$_G" choose \
              --cursor "> " \
              --header "  Choose action:" \
              --height 11 \
              "Database start" \
              "Database stop" \
              "Database backup" \
              "Database stats" \
              "Backend start" \
              "Backend stop" \
              "Frontend start" \
              "Frontend stop" \
              "Back") || break
            case "$ACTION" in
              "Database start") db-start ; break 2 ;;
              "Database stop") db-stop ; pause ;;
              "Database backup") pg-backup ; pause ;;
              "Database stats") pg-stats ; pause ;;
              "Backend start") backend-start ; break 2 ;;
              "Backend stop") backend-stop ; pause ;;
              "Frontend start") frontend-start ; break 2 ;;
              "Frontend stop") frontend-stop ; pause ;;
              "Back") break ;;
            esac
          done ;;

        "Auth & Secrets")
          while true; do
            section "Auth & Secrets"
            ACTION=$("$_G" choose \
              --cursor "> " \
              --header "  Choose action:" \
              --height 6 \
              "Bootstrap admin user" \
              "Show admin password" \
              "Sops status" \
              "Back") || break
            case "$ACTION" in
              "Bootstrap admin user") bootstrap-admin ; pause ;;
              "Show admin password") sops-get admin_password ; pause ;;
              "Sops status") sops-status ; pause ;;
              "Back") break ;;
            esac
          done ;;

        "Testing")
          while true; do
            section "Testing"
            ACTION=$("$_G" choose \
              --cursor "> " \
              --header "  Choose action:" \
              --height 9 \
              "Unit tests" \
              "Integration tests (HTTP)" \
              "Integration tests (TLS)" \
              "Full test suite" \
              "Smoke tests" \
              "Back") || break
            case "$ACTION" in
              "Unit tests") test-unit ; pause ;;
              "Integration tests (HTTP)") test-integration ; pause ;;
              "Integration tests (TLS)") test-integration-tls ; pause ;;
              "Full test suite") test-suite ; pause ;;
              "Smoke tests") test-smoke ; pause ;;
              "Back") break ;;
            esac
          done ;;

        "Maintenance")
          while true; do
            section "Maintenance"
            ACTION=$("$_G" choose \
              --cursor "> " \
              --header "  Choose action:" \
              --height 10 \
              "Show config" \
              "Setup TLS" \
              "TLS info" \
              "TLS clean" \
              "Nix garbage collect" \
              "Update flake" \
              "Back") || break
            case "$ACTION" in
              "Show config") show_config ; pause ;;
              "Setup TLS") tls-setup ; pause ;;
              "TLS info") tls-info ; pause ;;
              "TLS clean") tls-clean ; pause ;;
              "Nix garbage collect") nix-collect-garbage -d ; pause ;;
              "Update flake") nix flake update ; pause ;;
              "Back") break ;;
            esac
          done ;;

        "Quit"|*) break ;;

      esac
    done

    clear
    "$_G" style \
      --foreground 2 --align center --width 54 --margin "1 2" \
      "Goodbye from ${name}."
  '';

in {
  inherit deploy stop launch-dev;
  inherit db-start db-stop;
  inherit backend-start backend-stop;
  inherit frontend-start frontend-stop;
  inherit build-all deploy-nix deploy-nix-interactive stop-nix status-nix tui;
}
