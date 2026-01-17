{ pkgs, lib ? pkgs.lib, name }:

let
  config = import ./config.nix { inherit name; };
  
  # Network
  host = config.network.host;
  bindAddress = config.network.bindAddress;
  
  # Ports
  frontendPort = toString config.vite.port;
  backendPort = toString config.haskell.port;
  dbPort = toString config.database.port;
  
  # Directories
  backendDir = builtins.head (builtins.split "/[^/]*$" (builtins.head config.haskell.codeDirs));
  frontendDir = builtins.head (builtins.split "/[^/]*$" (builtins.head config.purescript.codeDirs));
  dataDir = config.dataDir;

  # Build script - creates deterministic artifacts via nix build
  build-all = pkgs.writeShellScriptBin "build-all" ''
    set -euo pipefail
    
    echo "Building ${name} backend..."
    nix build .#backend --show-trace --accept-flake-config
    
    echo "Building ${name} frontend..."
    nix build .#frontend --show-trace --accept-flake-config -o result-frontend
    
    echo ""
    echo "Build complete."
    echo "  Backend:  ./result/bin/${name}-backend"
    echo "  Frontend: ./result-frontend"
  '';

  # Headless deploy - runs Nix-built artifacts
  deploy-nix = pkgs.writeShellScriptBin "deploy-nix" ''
    set -euo pipefail
    
    LOGDIR="${dataDir}/logs"
    PIDDIR="${dataDir}/pids"
    BACKUP_DIR="${dataDir}/backups"
    mkdir -p "$LOGDIR" "$PIDDIR" "$BACKUP_DIR"
    
    # Build if artifacts don't exist
    if [ ! -f "./result/bin/${name}-backend" ]; then
      echo "Backend not built, building..."
      nix build .#backend --show-trace --accept-flake-config
    fi
    
    if [ ! -d "./result-frontend" ]; then
      echo "Frontend not built, building..."
      nix build .#frontend --show-trace --accept-flake-config -o result-frontend
    fi
    
    # Start postgres
    echo "Starting PostgreSQL on port ${dbPort}..."
    LATEST_BACKUP="$(find "$BACKUP_DIR" -type f -name '*.sql' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
    
    pg-start
    
    if [ -n "$LATEST_BACKUP" ]; then
      echo "Restoring from backup: $LATEST_BACKUP"
      pg-restore "$LATEST_BACKUP"
    fi
    
    # Start backend (Nix-built binary)
    echo "Starting backend on ${bindAddress}:${backendPort}..."
    ./result/bin/${name}-backend > "$LOGDIR/backend.log" 2>&1 &
    echo $! > "$PIDDIR/backend.pid"
    
    # Wait for backend to be ready
    echo "Waiting for backend..."
    for i in $(seq 1 30); do
      if curl -s http://${host}:${backendPort}/health > /dev/null 2>&1; then
        echo "Backend ready."
        break
      fi
      sleep 1
    done
    
    # Start frontend
    echo "Starting frontend on ${bindAddress}:${frontendPort}..."
    cd ${frontendDir}
    ${pkgs.nodejs}/bin/npx vite --host ${bindAddress} --port ${frontendPort} > "$LOGDIR/frontend.log" 2>&1 &
    echo $! > "$PIDDIR/frontend.pid"
    cd ..
    
    echo ""
    echo "All services started."
    echo "  Backend:  http://${host}:${backendPort} (PID: $(cat $PIDDIR/backend.pid))"
    echo "  Frontend: http://${host}:${frontendPort} (PID: $(cat $PIDDIR/frontend.pid))"
    echo "  Postgres: ${host}:${dbPort}"
    echo "  Logs: $LOGDIR/"
  '';

  # Interactive deploy with tmux (uses Nix-built artifacts)
  deploy-nix-interactive = pkgs.writeShellScriptBin "deploy-nix-interactive" ''
    set -euo pipefail
    
    BACKUP_DIR="${dataDir}/backups"
    mkdir -p "$BACKUP_DIR"
    
    # Build if needed
    if [ ! -f "./result/bin/${name}-backend" ]; then
      echo "Backend not built, building..."
      nix build .#backend --show-trace --accept-flake-config
    fi
    
    # Database setup
    LATEST_BACKUP="$(find "$BACKUP_DIR" -type f -name '*.sql' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
    
    pg-start
    
    if [ -n "$LATEST_BACKUP" ]; then
      echo "Restoring from backup: $LATEST_BACKUP"
      pg-restore "$LATEST_BACKUP"
    fi
    
    # TMux layout
    tmux kill-session -t ${name} 2>/dev/null || true
    tmux new-session -d -s ${name} -n "Services" -x 120 -y 42
    
    tmux split-window -v -b -l 12
    tmux split-window -h -t ${name}:Services.0 -p 66
    tmux split-window -h -t ${name}:Services.1 -p 50
    
    tmux resize-pane -t ${name}:Services.0 -y 12
    tmux resize-pane -t ${name}:Services.1 -y 12
    tmux resize-pane -t ${name}:Services.2 -y 12
    
    # Run Nix-built backend binary directly
    tmux send-keys -t ${name}:Services.0 './result/bin/${name}-backend' C-m
    tmux send-keys -t ${name}:Services.1 'cd ${frontendDir} && vite --host ${bindAddress} --port ${frontendPort} --open' C-m
    tmux send-keys -t ${name}:Services.2 'watch -n 5 pg-stats' C-m
    tmux send-keys -t ${name}:Services.3 'echo "Backend: http://${host}:${backendPort}"; echo "Frontend: http://${host}:${frontendPort}"; echo "Postgres: ${host}:${dbPort}"; echo' C-m
    
    tmux set-hook -t ${name} client-resized 'resize-pane -t ${name}:Services.0 -y 12; resize-pane -t ${name}:Services.1 -y 12; resize-pane -t ${name}:Services.2 -y 12'
    tmux select-pane -t ${name}:Services.3
    tmux attach-session -t ${name}
  '';

  # Stop all services
  stop-nix = pkgs.writeShellScriptBin "stop-nix" ''
    set -euo pipefail
    
    PIDDIR="${dataDir}/pids"
    
    echo "Backing up database..."
    pg-backup || true
    
    echo "Stopping services..."
    
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
    
    # Kill anything on the frontend port
    ${pkgs.lsof}/bin/lsof -ti :${frontendPort} | xargs -r kill -9 2>/dev/null || true
    
    # Stop tmux session if exists
    tmux kill-session -t ${name} 2>/dev/null || true
    
    # Stop postgres
    pg-stop || true
    
    echo "All services stopped."
  '';

  # Status
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
    echo "  Backend:  http://${host}:${backendPort}"
    echo "  Frontend: http://${host}:${frontendPort}"
    echo "  Postgres: ${host}:${dbPort}"
    echo ""
    pg-stats 2>/dev/null || echo "postgres: stopped"
  '';

  # TUI menu
  tui = pkgs.writeShellScriptBin "${name}-tui" ''
    set -euo pipefail
    
    build_backend() {
      echo "Building backend..."
      nix build .#backend --show-trace --accept-flake-config
    }
    
    build_frontend() {
      echo "Building frontend..."
      nix build .#frontend --show-trace --accept-flake-config -o result-frontend
    }
    
    build_all() {
      build_backend
      build_frontend
    }
    
    run_backend() {
      if [ ! -f "./result/bin/${name}-backend" ]; then
        build_backend
      fi
      ./result/bin/${name}-backend
    }
    
    collect_garbage() {
      echo "Collecting garbage..."
      nix-collect-garbage -d
      echo "Done."
    }
    
    update_flake() {
      echo "Updating flake..."
      nix flake update
      echo "Done."
    }
    
    show_config() {
      echo ""
      echo "${name} Configuration"
      echo "===================="
      echo ""
      echo "Network:"
      echo "  Host:         ${host}"
      echo "  Bind address: ${bindAddress}"
      echo ""
      echo "Services:"
      echo "  Backend:  http://${host}:${backendPort}"
      echo "  Frontend: http://${host}:${frontendPort}"
      echo "  Postgres: ${host}:${dbPort}"
      echo ""
      echo "Directories:"
      echo "  Backend:  ${backendDir}"
      echo "  Frontend: ${frontendDir}"
      echo "  Data:     ${dataDir}"
      echo ""
    }
    
    # Check for CLI args
    case "''${1:-}" in
      --build-all)         build_all; exit 0 ;;
      --build-backend)     build_backend; exit 0 ;;
      --build-frontend)    build_frontend; exit 0 ;;
      --run-backend)       run_backend; exit 0 ;;
      --deploy)            deploy-nix; exit 0 ;;
      --deploy-interactive) deploy-nix-interactive; exit 0 ;;
      --stop)              stop-nix; exit 0 ;;
      --status)            status-nix; exit 0 ;;
      --config)            show_config; exit 0 ;;
      --gc)                collect_garbage; exit 0 ;;
      --update)            update_flake; exit 0 ;;
      --help)
        echo "Usage: ${name}-tui [OPTION]"
        echo ""
        echo "Options:"
        echo "  --build-all          Build backend and frontend"
        echo "  --build-backend      Build backend only"
        echo "  --build-frontend     Build frontend only"
        echo "  --run-backend        Run backend (builds if needed)"
        echo "  --deploy             Deploy headless"
        echo "  --deploy-interactive Deploy with tmux"
        echo "  --stop               Stop all services"
        echo "  --status             Show service status"
        echo "  --config             Show configuration"
        echo "  --gc                 Garbage collect Nix store"
        echo "  --update             Update flake inputs"
        echo ""
        exit 0
        ;;
    esac
    
    # Interactive menu
    PS3='Choice: '
    options=(
      "Build all"
      "Build backend"
      "Build frontend"
      "Deploy (headless)"
      "Deploy (tmux)"
      "Stop services"
      "Status"
      "Show config"
      "Collect garbage"
      "Update flake"
      "Quit"
    )
    
    select opt in "''${options[@]}"; do
      case $opt in
        "Build all")      build_all ;;
        "Build backend")  build_backend ;;
        "Build frontend") build_frontend ;;
        "Deploy (headless)") deploy-nix; break ;;
        "Deploy (tmux)")  deploy-nix-interactive; break ;;
        "Stop services")  stop-nix ;;
        "Status")         status-nix ;;
        "Show config")    show_config ;;
        "Collect garbage") collect_garbage ;;
        "Update flake")   update_flake ;;
        "Quit")           break ;;
        *)                echo "Invalid option" ;;
      esac
    done
  '';

in {
  inherit build-all deploy-nix deploy-nix-interactive stop-nix status-nix tui;
}