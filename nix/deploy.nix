# ./nix/testbed.nix
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

    # Start new tmux session with the interactive shell as the main pane
    tmux new-session -d -s ${name} -n "Services"
    
    # Split the window for services (creating smaller panes at the top)
    # Create backend pane
    tmux split-window -v -b -p 20
    # Create frontend pane
    tmux split-window -h -p 50
    # Create stats pane
    tmux split-window -h -p 50
    
    # Now we have:
    # Top left (0): Backend (20% height)
    # Top middle (1): Frontend (20% height)
    # Top right (2): pg-stats (20% height)
    # Bottom (3): Interactive shell (80% height)
    
    # Configure each pane
    tmux send-keys -t ${name}.0 'cd backend && cabal run ${name}-backend' C-m
    tmux send-keys -t ${name}.1 'cd frontend && vite --open' C-m
    tmux send-keys -t ${name}.2 'watch -n 5 pg-stats' C-m
    tmux send-keys -t ${name}.3 'echo "Interactive shell ready for use"; echo' C-m
    
    # Ensure the layout is set
    tmux select-layout tiled
    
    # Fine-tune the pane sizes
    # Make top row shorter
    tmux resize-pane -t ${name}.0 -y 10
    tmux resize-pane -t ${name}.1 -y 10
    tmux resize-pane -t ${name}.2 -y 10
    
    # Select the interactive shell pane (bottom)
    tmux select-pane -t ${name}.3
    
    # Attach to the session
    tmux attach-session -t ${name}
  '';

  withdraw = pkgs.writeShellScriptBin "withdraw" ''
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Creating database backup..."
    pg-backup

    echo "Stopping services..."
    tmux kill-session -t ${name} 2>/dev/null || true
    
    echo "Stopping database..."
    pg-stop || { echo "Failed to stop PostgreSQL completely"; exit 1; }
    sleep 10  # Wait for processes to fully terminate

    vite-cleanup
    sleep 10  # Wait for processes to fully terminate

    echo "All services stopped."
  '';

in {
  inherit deploy withdraw;
}