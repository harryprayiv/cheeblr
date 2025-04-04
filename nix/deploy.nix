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

in {
  inherit deploy stop;
}