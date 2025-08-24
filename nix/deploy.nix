{ pkgs, lib ? pkgs.lib, name }:

let
  deploy = pkgs.writeShellScriptBin "deploy" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Building projects..."
    (cd backend && cabal build) || { echo "Backend build failed"; exit 1; }
    (cd frontend && spago build) || { echo "Frontend build failed"; exit 1; }
    
    # Check for and handle database backup
    BACKUP_DIR="$HOME/.local/share/${name}/backups"
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

    # Start completely fresh
    tmux kill-session -t ${name} 2>/dev/null || true

    # Create a new session with a single pane (this will be the interactive shell)
    tmux new-session -d -s ${name} -n "Services" -x 120 -y 42
    
    # Create three small panes at the top - 12 lines tall (splitting the difference)
    # First create one small pane at the top
    tmux split-window -v -b -l 12
    
    # Now split this top pane horizontally into three parts
    tmux split-window -h -t ${name}:Services.0 -p 66
    tmux split-window -h -t ${name}:Services.1 -p 50
    
    # At this point we should have:
    # Pane 0: Top-left (backend)
    # Pane 1: Top-middle (frontend)
    # Pane 2: Top-right (stats)
    # Pane 3: Bottom (interactive shell, taking most of the screen)
    
    # Make absolutely sure our panes are correctly sized
    tmux resize-pane -t ${name}:Services.0 -y 12
    tmux resize-pane -t ${name}:Services.1 -y 12
    tmux resize-pane -t ${name}:Services.2 -y 12
    
    # Send commands to each pane
    tmux send-keys -t ${name}:Services.0 'cd backend && cabal run ${name}-backend' C-m
    tmux send-keys -t ${name}:Services.1 'cd frontend && vite --open' C-m
    tmux send-keys -t ${name}:Services.2 'watch -n 5 pg-stats' C-m
    tmux send-keys -t ${name}:Services.3 'echo "Interactive shell ready for use"; echo' C-m
    
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
    # Get vite PIDs but exclude our script and its parent
    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" || echo "")
    if [ -n "$VITE_PIDS" ]; then
      echo "Found remaining vite processes: $VITE_PIDS"
      for pid in $VITE_PIDS; do
        echo "Killing vite process $pid"
        kill -9 "$pid" 2>/dev/null || true
      done
    fi
    
    # Check port 5173 but protect our process
    PORT_PIDS=$(lsof -i :5173 -t | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$PORT_PIDS" ]; then
      echo "Found processes still using port 5173: $PORT_PIDS"
      for pid in $PORT_PIDS; do
        echo "Killing process $pid on port 5173"
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
      # Use a subshell for the kill operation to prevent killing our own script
      (
        tmux kill-session -t ${name} 2>/dev/null || true
        sleep 1
      ) &
      
      # Wait for the subshell to complete
      wait
      
      # Check if the session still exists
      if tmux has-session -t ${name} 2>/dev/null; then
        echo "Session still exists, using last resort measures..."
        (
          # Run kill-server in a subshell to prevent it from killing our script
          tmux kill-server 2>/dev/null || true
        ) &
        wait
      fi
    fi

    # Final verification that doesn't kill our script
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

  # Individual Database start script
  db-start = pkgs.writeShellScriptBin "db-start" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Starting database service..."
    
    # Check for and handle database backup
    BACKUP_DIR="$HOME/.local/share/${name}/backups"
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
    
    echo "Database started successfully."
    echo ""
    echo "You can monitor database stats with: watch -n 5 pg-stats"
    echo "You can backup the database with: pg-backup"
    echo "You can stop the database with: pg-stop"
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
    if [ ! -f "backend/cabal.project" ] && [ ! -f "backend/${name}.cabal" ]; then
      if [ -f "cabal.project" ] || [ -f "${name}.cabal" ]; then
        # We're already in the backend directory
        BACKEND_DIR="."
      else
        echo "Error: Cannot find backend directory. Please run from project root or backend directory."
        exit 1
      fi
    else
      BACKEND_DIR="backend"
    fi
    
    # Build the backend
    echo "Building backend..."
    (cd "$BACKEND_DIR" && cabal build) || { 
      echo "Backend build failed"
      exit 1
    }
    
    # Run the backend
    echo "Starting backend server..."
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
    
    # Find and stop backend processes
    BACKEND_PIDS=$(pgrep -f "${name}-backend" 2>/dev/null || echo "")
    if [ -n "$BACKEND_PIDS" ]; then
      echo "Found backend processes: $BACKEND_PIDS"
      for pid in $BACKEND_PIDS; do
        echo "Stopping backend process $pid"
        kill -TERM "$pid" 2>/dev/null || true
      done
      
      # Give processes time to stop gracefully
      sleep 2
      
      # Force kill if still running
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
    if [ ! -f "frontend/spago.yaml" ] && [ ! -f "frontend/spago.dhall" ] && [ ! -f "frontend/package.json" ]; then
      if [ -f "spago.yaml" ] || [ -f "spago.dhall" ] || [ -f "package.json" ]; then
        # We're already in the frontend directory
        FRONTEND_DIR="."
      else
        echo "Error: Cannot find frontend directory. Please run from project root or frontend directory."
        exit 1
      fi
    else
      FRONTEND_DIR="frontend"
    fi
    
    # Clean up any existing vite processes first
    echo "Checking for existing vite processes..."
    VITE_PIDS=$(pgrep -f "vite" 2>/dev/null || echo "")
    if [ -n "$VITE_PIDS" ]; then
      echo "Found existing vite processes, cleaning up..."
      for pid in $VITE_PIDS; do
        kill -TERM "$pid" 2>/dev/null || true
      done
      sleep 1
    fi
    
    # Check if port 5173 is in use
    if lsof -i :5173 &>/dev/null; then
      echo "Warning: Port 5173 is already in use. Attempting to free it..."
      PORT_PIDS=$(lsof -i :5173 -t 2>/dev/null || echo "")
      for pid in $PORT_PIDS; do
        kill -TERM "$pid" 2>/dev/null || true
      done
      sleep 1
    fi
    
    # Build the frontend
    echo "Building frontend..."
    (cd "$FRONTEND_DIR" && spago build) || { 
      echo "Frontend build failed"
      exit 1
    }
    
    # Start vite
    echo "Starting Vite development server..."
    echo "Press Ctrl+C to stop the frontend"
    echo ""
    
    cd "$FRONTEND_DIR"
    exec vite --open
  ''; 

  # Frontend stop script
  frontend-stop = pkgs.writeShellScriptBin "frontend-stop" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    echo "Stopping frontend..."
    
    # Store our own PID so we don't kill ourselves
    OUR_PID=$$
    PARENT_PID=$PPID
    
    echo "Stopping vite..."
    vite-cleanup 2>/dev/null || true
    
    echo "Ensuring all vite processes are stopped..."
    # Get vite PIDs but exclude our script and its parent
    VITE_PIDS=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$VITE_PIDS" ]; then
      echo "Found remaining vite processes: $VITE_PIDS"
      for pid in $VITE_PIDS; do
        echo "Stopping vite process $pid"
        kill -TERM "$pid" 2>/dev/null || true
      done
      
      sleep 1
      
      # Force kill if still running
      REMAINING_VITE=$(pgrep -f "vite" | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
      if [ -n "$REMAINING_VITE" ]; then
        echo "Force stopping remaining vite processes..."
        for pid in $REMAINING_VITE; do
          kill -9 "$pid" 2>/dev/null || true
        done
      fi
    fi
    
    # Check port 5173 but protect our process
    PORT_PIDS=$(lsof -i :5173 -t | grep -v "^$OUR_PID$" | grep -v "^$PARENT_PID$" 2>/dev/null || echo "")
    if [ -n "$PORT_PIDS" ]; then
      echo "Found processes still using port 5173: $PORT_PIDS"
      for pid in $PORT_PIDS; do
        echo "Killing process $pid on port 5173"
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