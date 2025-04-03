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

    echo "Creating database backup..."
    pg-backup
    # sleep 10
    
    echo "Stopping database..."
    pg-stop || { echo "Failed to stop PostgreSQL completely"; exit 1; }
    
    echo "Stopping vite..."
    vite-cleanup
    # sleep 2

    echo "Stopping services..."
    tmux kill-session -t ${name} 2>/dev/null || true

    echo "All services stopped."
  '';

in {
  inherit deploy stop;
}