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

  deploy = pkgs.writeShellScriptBin "deploy" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Building projects..."
    (cd ${backendDir} && cabal build) || { echo "Backend build failed"; exit 1; }
    (cd ${frontendDir} && spago build) || { echo "Frontend build failed"; exit 1; }
    
    # Check for and handle database backup
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
    
    # Display tmux instructions
    echo "TMux Commands:"
    echo "-------------"
    echo "Ctrl-b d    - Detach (safe exit)"
    echo "Ctrl-b o    - Switch between panes"
    echo "Ctrl-b z    - Zoom/unzoom current pane"
    echo "Arrow keys  - Navigate panes (with Ctrl-b)"
    echo "Ctrl-b [    - Scroll mode (q to exit)"
    echo ""
    echo "Starting services..."
    echo "  Backend:  http://${host}:${backendPort}"
    echo "  Frontend: http://${host}:${frontendPort}"
    echo "  Postgres: ${host}:${dbPort}"
    echo ""

    # Start completely fresh
    tmux kill-session -t ${name} 2>/dev/null || true

    # Create a new session with a single pane (this will be the interactive shell)
    tmux new-session -d -s ${name} -n "Services" -x 120 -y 42
    
    # Create three small panes at the top - 12 lines tall
    tmux split-window -v -b -l 12
    
    # Now split this top pane horizontally into three parts
    tmux split-window -h -t ${name}:Services.0 -p 66
    tmux split-window -h -t ${name}:Services.1 -p 50
    
    # Make absolutely sure our panes are correctly sized
    tmux resize-pane -t ${name}:Services.0 -y 12
    tmux resize-pane -t ${name}:Services.1 -y 12
    tmux resize-pane -t ${name}:Services.2 -y 12
    
    # Send commands to each pane
    tmux send-keys -t ${name}:Services.0 'cd ${backendDir} && cabal run ${name}-backend' C-m
    tmux send-keys -t ${name}:Services.1 'cd ${frontendDir} && vite --host ${bindAddress} --port ${frontendPort} --open' C-m
    tmux send-keys -t ${name}:Services.2 'watch -n 5 pg-stats' C-m
    tmux send-keys -t ${name}:Services.3 'echo "Backend: http://${host}:${backendPort}"; echo "Frontend: http://${host}:${frontendPort}"; echo "Postgres: ${host}:${dbPort}"; echo' C-m
    
    # Make sure the layout is maintained when resizing
    tmux set-hook -t ${name} client-resized 'resize-pane -t ${name}:Services.0 -y 12; resize-pane -t ${name}:Services.1 -y 12; resize-pane -t ${name}:Services.2 -y 12'
    
    # Select the interactive shell pane
    tmux select-pane -t ${name}:Services.3
    
    # Attach to the session
    tmux attach-session -t ${name}
  '';

  stop = pkgs.writeShellScriptBin "stop" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Store our own PID so we don't kill ourselves
    OUR_PID=$$
    PARENT_PID=$PPID
    
    echo "Creating database backup..."
    pg-backup
    echo "Database backup completed."
    
    echo "Stopping database..."
    pg-stop || { echo "Failed to stop PostgreSQL completely"; exit 1; }
    echo "Database stopped successfully."
    
    echo "Stopping vite..."
    vite-cleanup || true
    
    echo "Ensuring all vite processes are stopped..."
    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" || echo "")
    if [ -n "$VITE_PIDS" ]; then
      echo "Found remaining vite processes: $VITE_PIDS"
      for pid in $VITE_PIDS; do
        echo "Killing vite process $pid"
        kill -9 "$pid" 2>/dev/null || true
      done
    fi
    
    # Check frontend port but protect our process
    PORT_PIDS=$(${pkgs.lsof}/bin/lsof -i :${frontendPort} -t | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$PORT_PIDS" ]; then
      echo "Found processes still using port ${frontendPort}: $PORT_PIDS"
      for pid in $PORT_PIDS; do
        echo "Killing process $pid on port ${frontendPort}"
        kill -9 "$pid" 2>/dev/null || true
      done
    fi

    echo "Stopping tmux services..."
    if tmux has-session -t ${name} 2>/dev/null; then
      echo "Sending interrupt signal to tmux panes..."
      for pane_index in 0 1 2 3; do
        tmux send-keys -t ${name}:Services.$pane_index C-c 2>/dev/null || true
      done
      
      sleep 2
      
      echo "Detaching all clients from tmux session..."
      tmux detach-client -s ${name} 2>/dev/null || true
      
      echo "Killing tmux session..."
      (
        tmux kill-session -t ${name} 2>/dev/null || true
        sleep 1
      ) &
      wait
      
      if tmux has-session -t ${name} 2>/dev/null; then
        echo "Session still exists, using last resort measures..."
        (
          tmux kill-server 2>/dev/null || true
        ) &
        wait
      fi
    fi

    # Final verification
    BACKEND_PIDS=$(pgrep -f "${name}-backend" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" || echo "")
    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" || echo "")
    
    if [ -n "$BACKEND_PIDS" ] || [ -n "$VITE_PIDS" ]; then
      echo "Final cleanup of remaining processes..."
      for pid in $BACKEND_PIDS $VITE_PIDS; do
        echo "Force killing process $pid"
        kill -9 "$pid" 2>/dev/null || true
      done
    fi

    echo "All services stopped."
  '';

  # Database start script
  db-start = pkgs.writeShellScriptBin "db-start" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Starting database service on port ${dbPort}..."
    
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
    
    echo "Database started successfully at ${host}:${dbPort}"
    echo ""
    echo "You can monitor database stats with: watch -n 5 pg-stats"
    echo "You can backup the database with: pg-backup"
    echo "You can stop the database with: pg-stop"
    watch -n 5 pg-stats
  '';

  # Database stop script
  db-stop = pkgs.writeShellScriptBin "db-stop" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "Creating database backup..."
    pg-backup
    echo "Database backup completed."
    
    echo "Stopping database..."
    pg-stop || { echo "Failed to stop PostgreSQL completely"; exit 1; }
    echo "Database stopped successfully."
  '';

  # Backend start script  
  backend-start = pkgs.writeShellScriptBin "backend-start" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Building and starting Haskell backend..."
    
    # Check if we're in the right directory
    if [ ! -f "${backendDir}/cabal.project" ] && [ ! -f "${backendDir}/${name}-backend.cabal" ]; then
      if [ -f "cabal.project" ] || [ -f "${name}-backend.cabal" ]; then
        BACKEND_DIR="."
      else
        echo "Error: Cannot find backend directory. Please run from project root or backend directory."
        exit 1
      fi
    else
      BACKEND_DIR="${backendDir}"
    fi
    
    echo "Building backend..."
    (cd "$BACKEND_DIR" && cabal build) || { 
      echo "Backend build failed"
      exit 1
    }
    
    echo "Starting backend server on ${host}:${backendPort}..."
    echo "Press Ctrl+C to stop the backend"
    echo ""
    
    cd "$BACKEND_DIR"
    exec cabal run ${name}-backend
  '';

  # Backend stop script  
  backend-stop = pkgs.writeShellScriptBin "backend-stop" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "Stopping backend..."
    
    BACKEND_PIDS=$(pgrep -f "${name}-backend" 2>/dev/null || echo "")
    if [ -n "$BACKEND_PIDS" ]; then
      echo "Found backend processes: $BACKEND_PIDS"
      for pid in $BACKEND_PIDS; do
        echo "Stopping backend process $pid"
        kill -TERM "$pid" 2>/dev/null || true
      done
      
      sleep 2
      
      REMAINING_PIDS=$(pgrep -f "${name}-backend" 2>/dev/null || echo "")
      if [ -n "$REMAINING_PIDS" ]; then
        echo "Force stopping remaining backend processes..."
        for pid in $REMAINING_PIDS; do
          kill -9 "$pid" 2>/dev/null || true
        done
      fi
    fi
    
    echo "Backend stopped."
  '';

  # Frontend start script
  frontend-start = pkgs.writeShellScriptBin "frontend-start" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Building and starting PureScript frontend..."
    
    # Check if we're in the right directory
    if [ ! -f "${frontendDir}/spago.yaml" ] && [ ! -f "${frontendDir}/spago.dhall" ] && [ ! -f "${frontendDir}/package.json" ]; then
      if [ -f "spago.yaml" ] || [ -f "spago.dhall" ] || [ -f "package.json" ]; then
        FRONTEND_DIR="."
      else
        echo "Error: Cannot find frontend directory. Please run from project root or frontend directory."
        exit 1
      fi
    else
      FRONTEND_DIR="${frontendDir}"
    fi
    
    echo "Checking for existing vite processes..."
    VITE_PIDS=$(pgrep -f "vite" 2>/dev/null || echo "")
    if [ -n "$VITE_PIDS" ]; then
      echo "Found existing vite processes, cleaning up..."
      for pid in $VITE_PIDS; do
        kill -TERM "$pid" 2>/dev/null || true
      done
      sleep 1
    fi
    
    # Check if frontend port is in use
    if ${pkgs.lsof}/bin/lsof -i :${frontendPort} &>/dev/null; then
      echo "Warning: Port ${frontendPort} is already in use. Attempting to free it..."
      PORT_PIDS=$(${pkgs.lsof}/bin/lsof -i :${frontendPort} -t 2>/dev/null || echo "")
      for pid in $PORT_PIDS; do
        kill -TERM "$pid" 2>/dev/null || true
      done
      sleep 1
    fi
    
    echo "Building frontend..."
    (cd "$FRONTEND_DIR" && spago build) || { 
      echo "Frontend build failed"
      exit 1
    }
    
    echo "Starting Vite development server on ${host}:${frontendPort}..."
    echo "Press Ctrl+C to stop the frontend"
    echo ""
    
    cd "$FRONTEND_DIR"
    exec vite --host ${bindAddress} --port ${frontendPort} --open
  ''; 

  # Frontend stop script
  frontend-stop = pkgs.writeShellScriptBin "frontend-stop" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "Stopping frontend..."
    
    OUR_PID=$$
    PARENT_PID=$PPID
    
    echo "Stopping vite..."
    vite-cleanup 2>/dev/null || true
    
    echo "Ensuring all vite processes are stopped..."
    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$VITE_PIDS" ]; then
      echo "Found remaining vite processes: $VITE_PIDS"
      for pid in $VITE_PIDS; do
        echo "Stopping vite process $pid"
        kill -TERM "$pid" 2>/dev/null || true
      done
      
      sleep 1
      
      REMAINING_VITE=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
      if [ -n "$REMAINING_VITE" ]; then
        echo "Force stopping remaining vite processes..."
        for pid in $REMAINING_VITE; do
          kill -9 "$pid" 2>/dev/null || true
        done
      fi
    fi
    
    PORT_PIDS=$(${pkgs.lsof}/bin/lsof -i :${frontendPort} -t | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$PORT_PIDS" ]; then
      echo "Found processes still using port ${frontendPort}: $PORT_PIDS"
      for pid in $PORT_PIDS; do
        echo "Killing process $pid on port ${frontendPort}"
        kill -9 "$pid" 2>/dev/null || true
      done
    fi
    
    echo "Frontend stopped."
  '';

in {
  inherit deploy stop;
  inherit db-start db-stop; 
  inherit frontend-start frontend-stop;
  inherit backend-start backend-stop;
}