{ pkgs, lib ? pkgs.lib, name, frontend ? null }:

let
  appConfig = import ./config.nix { inherit name; };
  frontendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head appConfig.purescript.codeDirs));

  vite-cleanup = pkgs.writeShellApplication {
    name = "vite-cleanup";
    runtimeInputs = with pkgs; [ lsof ];
    text = ''
      VITE_PORT=5173

      if lsof -i :"$VITE_PORT" > /dev/null 2>&1; then
        echo "Found processes on port $VITE_PORT"
        lsof -t -i :"$VITE_PORT" | while read -r pid; do
          if [ -n "$pid" ]; then
            echo "Killing process $pid"
            kill "$pid" 2>/dev/null || true
            RETRIES=0
            while kill -0 "$pid" 2>/dev/null; do
              RETRIES=$((RETRIES+1))
              if [ "$RETRIES" -eq 5 ]; then
                echo "Process $pid not responding, forcing shutdown..."
                kill -9 "$pid" 2>/dev/null || true
                break
              fi
              sleep 1
            done
          fi
        done
        if ! lsof -i :"$VITE_PORT" > /dev/null 2>&1; then
          echo "Successfully cleaned up all processes"
        else
          echo "Failed to clean up some processes"
          exit 1
        fi
      else
        echo "No processes found on port $VITE_PORT"
      fi
    '';
  };

  vite = pkgs.writeShellApplication {
    name = "vite";
    runtimeInputs = with pkgs; [ nodejs-slim lsof ];
    text = ''
      VITE_PORT=5173

      cleanup_port() {
        local port="$1"
        local pids
        pids=$(lsof -t -i :"$port" 2>/dev/null)
        if [ -n "$pids" ]; then
          echo "Found processes using port $port:"
          echo "$pids" | while read -r pid; do
            echo "Killing process $pid"
            kill "$pid" 2>/dev/null || true
          done
          RETRIES=0
          while lsof -i :"$port" > /dev/null 2>&1; do
            RETRIES=$((RETRIES+1))
            if [ "$RETRIES" -eq 10 ]; then
              echo "Some processes not responding, forcing shutdown..."
              echo "$pids" | while read -r pid; do
                kill -9 "$pid" 2>/dev/null || true
              done
              break
            fi
            echo "Waiting for port to be freed... (attempt $RETRIES/10)"
            sleep 1
          done
        fi
      }

      if lsof -i :"$VITE_PORT" > /dev/null 2>&1; then
        echo "Port $VITE_PORT is in use. Attempting to clean up..."
        cleanup_port "$VITE_PORT"
      fi

      export ${lib.toUpper name}_BASE_PATH="${toString ../.}"
      npx vite --port "$VITE_PORT" --host --open
      trap 'cleanup_port "$VITE_PORT"' EXIT
    '';
  };

  concurrent = pkgs.writeShellApplication {
    name = "concurrent";
    runtimeInputs = with pkgs; [ concurrently ];
    text = ''
      concurrently\
        --color "auto"\
        --prefix "[{command}]"\
        --handle-input\
        --restart-tries 10\
        "$@"
    '';
  };

  codegen = pkgs.writeShellApplication {
    name = "codegen";
    runtimeInputs = with pkgs; [ spago-unstable nodejs_20 purs ];
    text = ''
      cd ${frontendPath}
      echo "Running PureScript codegen..."
      spago run --main Codegen.Run
      echo "Codegen complete."
    '';
  };

  spago-watch = pkgs.writeShellApplication {
    name = "spago-watch";
    runtimeInputs = with pkgs; [ entr spago-unstable ];
    text = ''find {src,test} | entr -s "spago $*" '';
  };

  bundle = pkgs.writeShellApplication {
    name = "bundle";
    runtimeInputs = with pkgs; [
      purs
      purs-backend-es
      esbuild
      nodejs_20
      spago-unstable
    ];
    text = ''
      set -euo pipefail

      FRONTEND_DIR="${frontendPath}"
      OUT_DIR="$FRONTEND_DIR/dist"
      MINIFY=true
      MODE=es

      for arg in "$@"; do
        case "$arg" in
          --no-minify)   MINIFY=false ;;
          --mode)        shift; MODE="$1" ;;
          --mode=*)      MODE="''${arg#--mode=}" ;;
          --out)         shift; OUT_DIR="$1" ;;
          --out=*)       OUT_DIR="''${arg#--out=}" ;;
          --help)
            echo "Usage: bundle [--mode es|simple] [--no-minify] [--out <dir>]"
            echo ""
            echo "Modes:"
            echo "  es     (default) spago build -> purs-backend-es DCE -> esbuild --minify"
            echo "  simple           spago build -> entry shim -> esbuild --minify"
            exit 0 ;;
        esac
      done

      cd "$FRONTEND_DIR"
      mkdir -p "$OUT_DIR"

      echo "--- Step 1: spago build (mode: $MODE)..."
      spago build
      echo "    Done."

      if [ "$MODE" = "es" ]; then
        echo "--- Step 2: purs-backend-es bundle-app (DCE)..."
        purs-backend-es bundle-app \
          --main Main \
          --to "$OUT_DIR/bundle-pre-minify.js" \
          --no-source-maps
        PRE_BYTES=$(wc -c < "$OUT_DIR/bundle-pre-minify.js")
        echo "    Pre-minify: $PRE_BYTES bytes"
        INPUT_JS="$OUT_DIR/bundle-pre-minify.js"
      else
        echo "--- Step 2: creating entry shim (mode: simple)..."
        if [ ! -f "output/Main/index.js" ]; then
          echo "ERROR: output/Main/index.js not found after spago build"
          exit 1
        fi
        PRE_BYTES=$(wc -c < output/Main/index.js)
        echo "    Main/index.js: $PRE_BYTES bytes"
        echo 'require("./output/Main/index.js").main()' > "$OUT_DIR/_entry.js"
        INPUT_JS="$OUT_DIR/_entry.js"
      fi

      echo "--- Step 3: esbuild..."
      if [ "$MINIFY" = "true" ]; then
        esbuild "$INPUT_JS" \
          --bundle \
          --outfile="$OUT_DIR/app.js" \
          --format=iife \
          --platform=browser \
          --minify \
          --sourcemap=external
      else
        esbuild "$INPUT_JS" \
          --bundle \
          --outfile="$OUT_DIR/app.js" \
          --format=iife \
          --platform=browser \
          --sourcemap=external
      fi

      rm -f "$OUT_DIR/bundle-pre-minify.js" "$OUT_DIR/_entry.js"

      FINAL_BYTES=$(wc -c < "$OUT_DIR/app.js")
      REDUCTION=$(( (PRE_BYTES - FINAL_BYTES) * 100 / PRE_BYTES ))
      echo "    Final: $FINAL_BYTES bytes  ($REDUCTION% reduction)"
      echo ""
      echo "Output: $OUT_DIR/app.js"
      echo "        $OUT_DIR/app.js.map"
    '';
  };

  dev = pkgs.writeShellApplication {
    name = "dev";
    runtimeInputs = with pkgs; [
      nodejs-slim
      spago-watch
      vite
      concurrent
    ];
    text = ''
      cd ${frontendPath}
      echo "Running initial codegen..."
      spago run --main Codegen.Run || true
      concurrent "spago-watch build" vite
    '';
  };

  get-ip = pkgs.writeShellApplication {
    name = "get-ip";
    text = ''
      ip addr show | grep "inet " | grep -v 127.0.0.1
    '';
  };

  network-dev = pkgs.writeShellApplication {
    name = "network-dev";
    runtimeInputs = with pkgs; [ nodejs_20 esbuild tmux ];
    text = ''
      if [[ "$OSTYPE" == "darwin"* ]]; then
        IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1)
      else
        IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
      fi
      echo "Starting development server on network address: $IP"
      cd frontend
      tmux new-session -d -s dev-session
      tmux send-keys "cd ../backend && cabal run" C-m
      tmux split-window -h
      tmux send-keys "cd ../frontend && npx vite --host $IP" C-m
      tmux attach-session -t dev-session
    '';
  };

in {
  inherit vite vite-cleanup spago-watch concurrent dev network-dev get-ip codegen bundle;

  buildInputs = with pkgs; [
    esbuild
    nodejs_20
    purs
    purs-tidy
    purs-backend-es
    purescript-language-server
    spago-unstable
  ];
}