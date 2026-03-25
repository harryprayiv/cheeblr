# nix/containers.nix
#
# OCI images built with nix2container.
# No tarballs written to the Nix store.  Push skips already-pushed layers.
#
# PRIMARY TARGET: Raspberry Pi 5  (aarch64-linux)
#
# Build images explicitly -- NOT built by `nix develop`:
#   nix build .#packages.aarch64-linux.backendImage
#   nix build .#packages.aarch64-linux.frontendImage
#
# Load into local podman (native arch):
#   nix run .#packages.x86_64-linux.backendImage-copyToPodman
#   nix run .#packages.x86_64-linux.frontendImage-copyToPodman
#
# Push aarch64 images directly to a registry (skips unchanged layers):
#   nix run .#packages.aarch64-linux.backendImage-copyToRegistry -- \
#       docker://myregistry.io/cheeblr-backend:latest
#
# From the devshell (lazy wrappers, no build triggered on shell entry):
#   container-load              -- build + load into podman (native arch)
#   container-run               -- start with podman
#   container-stop              -- stop and remove
#   container-push-pi <reg>     -- build + push aarch64 images to registry
#   container-k8s-manifests <r> -- write Kubernetes / Talos YAML
#
# Frontend bundle modes (controlled by the `bundleMode` argument):
#
#   "es"     (default)
#            purs-nix compile  ->  purs-backend-es bundle-app  ->  esbuild --minify
#            purs-backend-es performs dead-code elimination across the entire
#            PureScript closure before esbuild sees any code.  Produces the
#            smallest possible bundle.  Requires purs-backend-es in the closure.
#
#   "simple"
#            purs-nix compile  ->  esbuild --bundle --minify
#            esbuild bundles directly from the CommonJS output/ tree.
#            No DCE at the PureScript level; every compiled module is included.
#            Simpler pipeline; use this if the "es" mode causes build issues.

{ pkgs
, lib            ? pkgs.lib
, name
, backendPackage
, nix2containerPkgs
  # "es"     -- purs-backend-es DCE + esbuild minify  (default, smaller bundle)
  # "simple" -- esbuild bundle directly from output/  (simpler, proven path)
, bundleMode        ? "es"
  # frontendProject: intentionally optional and NOT the purs-nix-instance.build
  # derivation.  That derivation produces a library dependency manifest, not
  # compiled JavaScript.  Leave null; the from-source path is used instead.
, frontendProject   ? null
, purs-nix-instance ? null
, psDependencies    ? []
, purescript        ? null
}:

let
  appConfig    = import ./config.nix { inherit name; };
  backendPort  = toString appConfig.haskell.port;
  frontendPort = toString appConfig.vite.port;
  thisSystem   = pkgs.stdenv.hostPlatform.system;

  frontendSrc = ../frontend;

  # ── Backend entrypoint factory ────────────────────────────────────────────
  mkBackendEntry = pkg: pkgs.writeShellScript "${name}-backend-entrypoint" ''
    set -euo pipefail
    if [ -f /run/secrets/tls.crt ] && [ -f /run/secrets/tls.key ]; then
      export USE_TLS=true
      export TLS_CERT_FILE=/run/secrets/tls.crt
      export TLS_KEY_FILE=/run/secrets/tls.key
    fi
    if [ -f /run/secrets/db_password ]; then
      export PGPASSWORD
      PGPASSWORD="$(< /run/secrets/db_password)"
    fi
    if [ -f /run/secrets/allowed_origin ]; then
      export ALLOWED_ORIGIN
      ALLOWED_ORIGIN="$(< /run/secrets/allowed_origin)"
    fi
    exec ${pkg}/bin/${name}-backend
  '';

  backendEntry = mkBackendEntry backendPackage;

  # ── Backend filesystem skeleton ───────────────────────────────────────────
  backendRootDirs = pkgs.runCommand "${name}-backend-rootdirs" { } ''
    mkdir -p $out/tmp
    mkdir -p $out/run/secrets
    mkdir -p $out/var/log/${name}
    chmod 1777 $out/tmp
  '';

  # ── Backend image layers ──────────────────────────────────────────────────
  # Layer 1: stable system tools -- rebuilt only when nixpkgs changes.
  # Layer 2: Haskell binary      -- the only layer pushed after a code change.

  backendSystemLayer = nix2containerPkgs.buildLayer {
    deps = [
      pkgs.cacert
      pkgs.openssl
      pkgs.curl
      pkgs.coreutils
      pkgs.bash
    ];
  };

  backendAppLayer = nix2containerPkgs.buildLayer {
    deps   = [ backendPackage backendRootDirs ];
    layers = [ backendSystemLayer ];
  };

  # ── Backend OCI image ─────────────────────────────────────────────────────

  backendImage = nix2containerPkgs.buildImage {
    name = "${name}-backend";
    tag  = "latest";

    copyToRoot = pkgs.buildEnv {
      name        = "${name}-backend-copyToRoot";
      paths       = [ pkgs.cacert pkgs.coreutils pkgs.bash backendRootDirs ];
      pathsToLink = [ "/bin" "/etc" "/tmp" "/run" "/var" ];
    };

    layers = [ backendSystemLayer backendAppLayer ];

    config = {
      entrypoint   = [ "${backendEntry}" ];
      ExposedPorts = { "${backendPort}/tcp" = {}; };
      Env = [
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "PORT=${backendPort}"
        "PGHOST=localhost"
        "PGPORT=5432"
        "PGDATABASE=${name}"
        "PGUSER=${name}"
        "USE_TLS=false"
        "USE_REAL_AUTH=true"
        "LOG_FILE=/var/log/${name}/${name}-compliance.log"
      ];
      Labels = {
        "org.opencontainers.image.title"        = "${name}-backend";
        "org.opencontainers.image.description"  = "Cheeblr Haskell/Servant/Warp backend";
        "org.opencontainers.image.architecture" = pkgs.stdenv.hostPlatform.uname.processor;
      };
    };
  };

  # ── Frontend static build ─────────────────────────────────────────────────
  #
  # Priority (first match wins):
  #
  #   1. purs-nix-instance + purescript available  (normal path)
  #      Delegates to frontendStaticEs or frontendStaticSimple per bundleMode.
  #
  #   2. frontendProject supplied (derivation with $out/Main/index.js)
  #      Skips compilation; goes straight to bundling.
  #      NOTE: purs-nix-instance.build does NOT produce $out/Main/index.js.
  #
  #   3. Neither available  ->  placeholder HTML page.

  # Shared helper: copy static assets and repoint index.html.
  # Used by both from-source derivations via shell fragment interpolation.

  # ── "es" mode: purs-nix compile -> purs-backend-es DCE -> esbuild minify ─
  frontendStaticEs =
    let
      ps = purs-nix-instance.purs {
        dir          = frontendSrc;
        dependencies = psDependencies;
        inherit purescript;
        nodejs = pkgs.nodejs_20;
      };
    in
    pkgs.runCommand "${name}-frontend-static" {
      buildInputs = [
        (ps.command { })
        purescript
        pkgs.purs-backend-es
        pkgs.spago-unstable
        pkgs.nodejs_20
        pkgs.esbuild
      ];
      src = frontendSrc;
    } ''
      set -euo pipefail

      echo "--- Copying frontend source..."
      cp -r "$src/." workdir
      chmod -R +w workdir
      cd workdir

      echo "--- Step 1: purs-nix compile"
      purs-nix compile

      if [ ! -d output ]; then
        echo "ERROR: purs-nix compile produced no output/ directory"
        exit 1
      fi

      echo "--- Step 2: purs-backend-es bundle-app (DCE + ES module output)"
      ${pkgs.purs-backend-es}/bin/purs-backend-es bundle-app \
        --main Main \
        --to bundle.js \
        --no-source-maps

      if [ ! -f bundle.js ]; then
        echo "ERROR: purs-backend-es did not produce bundle.js"
        exit 1
      fi

      BUNDLE_BYTES=$(wc -c < bundle.js)
      echo "    bundle.js: $BUNDLE_BYTES bytes (pre-minify)"

      echo "--- Step 3: esbuild --minify"
      mkdir -p "$out"
      ${pkgs.esbuild}/bin/esbuild bundle.js \
        --bundle \
        --outfile="$out/app.js" \
        --format=iife \
        --global-name=__cheeblrInit \
        --platform=browser \
        --minify \
        --sourcemap=external

      FINAL_BYTES=$(wc -c < "$out/app.js")
      echo "    app.js:    $FINAL_BYTES bytes (minified)"
      echo "    Reduction: $(( (BUNDLE_BYTES - FINAL_BYTES) * 100 / BUNDLE_BYTES ))%"

      [ -f "index.html" ] && cp index.html "$out/"          || true
      [ -d "public"     ] && cp -r public/. "$out/"         || true
      [ -d "css"        ] && cp -r css       "$out/css"     || true
      [ -d "assets"     ] && cp -r assets    "$out/assets"  || true

      if [ -f "$out/index.html" ]; then
        sed -i \
          -e 's|type="module"[^>]*src="[^"]*"|src="/app.js"|g' \
          -e 's|<script[^>]*type="module"[^>]*>|<script>|g' \
          "$out/index.html"
      fi

      echo "--- Frontend static build complete (mode: es)."
      find "$out" -maxdepth 2 -type f
    '';

  # ── "simple" mode: purs-nix compile -> esbuild bundle + minify ───────────
  # The proven path.  esbuild bundles directly from the CommonJS output/ tree.
  frontendStaticSimple =
    let
      ps = purs-nix-instance.purs {
        dir          = frontendSrc;
        dependencies = psDependencies;
        inherit purescript;
        nodejs = pkgs.nodejs_20;
      };
    in
    pkgs.runCommand "${name}-frontend-static" {
      buildInputs = [
        (ps.command { })
        purescript
        pkgs.spago-unstable
        pkgs.nodejs_20
        pkgs.esbuild
      ];
      src = frontendSrc;
    } ''
      set -euo pipefail

      echo "--- Copying frontend source..."
      cp -r "$src/." workdir
      chmod -R +w workdir
      cd workdir

      echo "--- Step 1: purs-nix compile"
      purs-nix compile

      MAIN_JS="output/Main/index.js"
      if [ ! -f "$MAIN_JS" ]; then
        echo "ERROR: purs-nix compile did not produce output/Main/index.js"
        find output -type f | head -20 || echo "  (output/ does not exist)"
        exit 1
      fi

      MAIN_BYTES=$(wc -c < "$MAIN_JS")
      echo "    Main/index.js: $MAIN_BYTES bytes"

      echo "--- Step 2: esbuild --bundle --minify"
      mkdir -p "$out"
      ${pkgs.esbuild}/bin/esbuild "$MAIN_JS" \
        --bundle \
        --outfile="$out/app.js" \
        --format=iife \
        --global-name=__cheeblrInit \
        --platform=browser \
        --minify \
        --sourcemap=external

      FINAL_BYTES=$(wc -c < "$out/app.js")
      echo "    app.js: $FINAL_BYTES bytes (minified)"

      [ -f "index.html" ] && cp index.html "$out/"          || true
      [ -d "public"     ] && cp -r public/. "$out/"         || true
      [ -d "css"        ] && cp -r css       "$out/css"     || true
      [ -d "assets"     ] && cp -r assets    "$out/assets"  || true

      if [ -f "$out/index.html" ]; then
        sed -i \
          -e 's|type="module"[^>]*src="[^"]*"|src="/app.js"|g' \
          -e 's|<script[^>]*type="module"[^>]*>|<script>|g' \
          "$out/index.html"
      fi

      echo "--- Frontend static build complete (mode: simple)."
      find "$out" -maxdepth 2 -type f
    '';

  # Select based on bundleMode.
  frontendStaticFromSource =
    if bundleMode == "es" then frontendStaticEs
    else frontendStaticSimple;

  # Fallback: pre-compiled output/ directory supplied by caller.
  # Requires $frontendProject to be the purs compiler output/ tree
  # (i.e. $frontendProject/Main/index.js exists).
  # Also respects bundleMode.
  frontendStaticWithProject =
    pkgs.runCommand "${name}-frontend-static-precompiled" {
      buildInputs =
        (if bundleMode == "es" then [ pkgs.purs-backend-es ] else [])
        ++ [ pkgs.esbuild ];
      inherit frontendProject;
      src = frontendSrc;
    } ''
      set -euo pipefail

      OUTPUT_DIR="${frontendProject}"
      MAIN_JS="$OUTPUT_DIR/Main/index.js"

      if [ ! -f "$MAIN_JS" ]; then
        echo "ERROR: frontendProject does not contain Main/index.js"
        echo "Contents of frontendProject:"
        find "$OUTPUT_DIR" -type f | head -20
        echo ""
        echo "Hint: purs-nix-instance.build produces a library manifest,"
        echo "not compiled JavaScript.  Pass purs-nix-instance + purescript"
        echo "instead, or a derivation whose \$out IS the purs output/ directory."
        exit 1
      fi

      mkdir -p "$out"

      ${if bundleMode == "es" then ''
        echo "--- purs-backend-es bundle-app (mode: es)"
        mkdir -p workdir
        ln -s "$OUTPUT_DIR" workdir/output
        cd workdir
        ${pkgs.purs-backend-es}/bin/purs-backend-es bundle-app \
          --main Main \
          --to ../bundle.js \
          --no-source-maps
        cd ..
        INPUT_JS=bundle.js
      '' else ''
        echo "--- esbuild direct (mode: simple)"
        INPUT_JS="$MAIN_JS"
      ''}

      ${pkgs.esbuild}/bin/esbuild "$INPUT_JS" \
        --bundle \
        --outfile="$out/app.js" \
        --format=iife \
        --global-name=__cheeblrInit \
        --platform=browser \
        --minify \
        --sourcemap=external

      [ -f "$src/index.html" ] && cp "$src/index.html"  "$out/"          || true
      [ -d "$src/public"     ] && cp -r "$src/public/." "$out/"          || true
      [ -d "$src/css"        ] && cp -r "$src/css"       "$out/css"      || true
      [ -d "$src/assets"     ] && cp -r "$src/assets"    "$out/assets"   || true

      if [ -f "$out/index.html" ]; then
        sed -i \
          -e 's|type="module"[^>]*src="[^"]*"|src="/app.js"|g' \
          -e 's|<script[^>]*type="module"[^>]*>|<script>|g' \
          "$out/index.html"
      fi
    '';

  frontendStaticPlaceholder =
    pkgs.runCommand "${name}-frontend-placeholder" { } ''
      mkdir -p "$out"
      cat > "$out/index.html" <<'HTML'
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>${name}</title>
          <style>
            body { font-family: monospace; background: #0d1117; color: #c9d1d9;
                   display: flex; align-items: center; justify-content: center;
                   height: 100vh; margin: 0; }
            .box { text-align: center; padding: 2.5rem 3rem;
                   border: 1px solid #30363d; border-radius: 6px; }
            h1   { color: #58a6ff; margin-bottom: 1rem; }
            code { background: #161b22; padding: 2px 6px;
                   border-radius: 4px; font-size: 0.9em; }
          </style>
        </head>
        <body>
          <div class="box">
            <h1>${name}</h1>
            <p>Frontend image built without a PureScript compiler.</p>
            <p>Pass <code>purs-nix-instance</code> + <code>purescript</code> to
               enable a full production build.</p>
          </div>
        </body>
      </html>
      HTML
    '';

  frontendStatic =
    if purs-nix-instance != null && purescript != null then frontendStaticFromSource
    else if frontendProject != null                     then frontendStaticWithProject
    else                                                     frontendStaticPlaceholder;

  # ── nginx configuration ───────────────────────────────────────────────────

  nginxConf = pkgs.writeText "${name}-nginx.conf" ''
    user root;
    daemon off;
    error_log /dev/stderr info;
    pid /tmp/nginx.pid;

    events { worker_connections 1024; }

    http {
      include      ${pkgs.nginx}/conf/mime.types;
      default_type application/octet-stream;
      access_log   /dev/stdout;
      sendfile     on;

      client_body_temp_path /tmp/nginx-client;
      proxy_temp_path       /tmp/nginx-proxy;
      fastcgi_temp_path     /tmp/nginx-fastcgi;
      uwsgi_temp_path       /tmp/nginx-uwsgi;
      scgi_temp_path        /tmp/nginx-scgi;

      gzip            on;
      gzip_types      text/plain text/css application/json
                      application/javascript text/xml application/xml;
      gzip_min_length 256;

      server {
        listen ${frontendPort};
        root   /var/www/${name};
        index  index.html;

        location / { try_files $uri $uri/ /index.html; }

        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|map)$ {
          expires 1y;
          add_header Cache-Control "public, immutable";
        }
      }
    }
  '';

  frontendEntrypoint = pkgs.writeShellScript "${name}-frontend-entrypoint" ''
    set -euo pipefail
    mkdir -p /tmp/nginx-client /tmp/nginx-proxy \
             /tmp/nginx-fastcgi /tmp/nginx-uwsgi /tmp/nginx-scgi
    exec ${pkgs.nginx}/bin/nginx -c ${nginxConf}
  '';

  frontendRootDirs = pkgs.runCommand "${name}-frontend-rootdirs" { } ''
    mkdir -p $out/tmp
    mkdir -p $out/var/www/${name}
    cp -r ${frontendStatic}/. $out/var/www/${name}/
    chmod 1777 $out/tmp
  '';

  # ── Frontend image layers ─────────────────────────────────────────────────
  # Layer 1: nginx binary     -- stable, rarely changes.
  # Layer 2: SPA static files -- rebuilt on every frontend code change.

  frontendNginxLayer = nix2containerPkgs.buildLayer {
    deps = [ pkgs.nginx pkgs.coreutils pkgs.bash ];
  };

  frontendStaticLayer = nix2containerPkgs.buildLayer {
    deps   = [ frontendRootDirs ];
    layers = [ frontendNginxLayer ];
  };

  # ── Frontend OCI image ────────────────────────────────────────────────────

  frontendImage = nix2containerPkgs.buildImage {
    name = "${name}-frontend";
    tag  = "latest";

    copyToRoot = pkgs.buildEnv {
      name        = "${name}-frontend-copyToRoot";
      paths       = [ pkgs.coreutils pkgs.bash frontendRootDirs ];
      pathsToLink = [ "/bin" "/tmp" "/var" ];
    };

    layers = [ frontendNginxLayer frontendStaticLayer ];

    config = {
      entrypoint   = [ "${frontendEntrypoint}" ];
      ExposedPorts = { "${frontendPort}/tcp" = {}; };
      Labels = {
        "org.opencontainers.image.title"        = "${name}-frontend";
        "org.opencontainers.image.description"  = "Cheeblr PureScript/Deku frontend (nginx)";
        "org.opencontainers.image.architecture" = pkgs.stdenv.hostPlatform.uname.processor;
      };
    };
  };

  # ── NixOS module (bare-metal / VM / single-node) ──────────────────────────

  nixosModule = { config, pkgs, lib, ... }:
    let cfg = config.services.${name}; in
    {
      options.services.${name} = {
        enable = lib.mkEnableOption "${name} full stack";
        package = lib.mkOption {
          type        = lib.types.package;
          default     = backendPackage;
          description = "Backend package (must provide bin/${name}-backend).";
        };
        backendPort = lib.mkOption {
          type    = lib.types.port;
          default = appConfig.haskell.port;
        };
        frontendPort = lib.mkOption {
          type    = lib.types.port;
          default = appConfig.vite.port;
        };
        dataDir = lib.mkOption {
          type    = lib.types.str;
          default = "/var/lib/${name}";
        };
        pgHost = lib.mkOption {
          type    = lib.types.str;
          default = "127.0.0.1";
        };
        pgPort = lib.mkOption {
          type    = lib.types.port;
          default = 5432;
        };
        environmentFile = lib.mkOption {
          type        = lib.types.nullOr lib.types.path;
          default     = null;
          description = "systemd EnvironmentFile with PGPASSWORD, ALLOWED_ORIGIN, etc.";
        };
        openFirewall = lib.mkOption {
          type    = lib.types.bool;
          default = true;
        };
      };

      config = lib.mkIf cfg.enable {
        users.users.${name} = {
          isSystemUser = true;
          group        = name;
          home         = cfg.dataDir;
          createHome   = true;
        };
        users.groups.${name} = {};

        systemd.services."${name}-backend" = {
          description   = "${name} Haskell backend";
          wantedBy      = [ "multi-user.target" ];
          after         = [ "network.target" ];
          serviceConfig = lib.mkMerge [
            {
              ExecStart        = "${mkBackendEntry cfg.package}";
              User             = name;
              Group            = name;
              WorkingDirectory = cfg.dataDir;
              Restart          = "on-failure";
              RestartSec       = "5s";
              RuntimeDirectory = name;
              LogsDirectory    = name;
            }
            (lib.mkIf (cfg.environmentFile != null) {
              EnvironmentFile = cfg.environmentFile;
            })
          ];
          environment = {
            PORT          = toString cfg.backendPort;
            PGHOST        = cfg.pgHost;
            PGPORT        = toString cfg.pgPort;
            PGDATABASE    = name;
            PGUSER        = name;
            USE_TLS       = "false";
            USE_REAL_AUTH = "true";
            LOG_FILE      = "${cfg.dataDir}/compliance.log";
            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts."${name}" = {
            listen = [{ addr = "0.0.0.0"; port = cfg.frontendPort; }];
            root   = "${frontendStatic}";
            locations."/" = { tryFiles = "$uri $uri/ /index.html"; };
            locations."~* \\.(js|css|png|ico|svg|woff2)$".extraConfig = ''
              expires 1y;
              add_header Cache-Control "public, immutable";
            '';
          };
        };

        networking.firewall.allowedTCPPorts =
          lib.mkIf cfg.openFirewall [ cfg.backendPort cfg.frontendPort ];
      };
    };

  # ── Helper scripts (lazy -- no image derivation paths embedded) ───────────

  containerLoad = pkgs.writeShellScriptBin "container-load" ''
    set -euo pipefail
    SYSTEM="${thisSystem}"
    echo "Building and loading ${name} images ($SYSTEM) ..."
    echo "  (first build includes PureScript compilation, may take a few minutes)"
    echo ""
    echo "  backend..."
    nix run ".#packages.$SYSTEM.backendImage-copyToPodman"
    echo "  frontend..."
    nix run ".#packages.$SYSTEM.frontendImage-copyToPodman"
    echo ""
    echo "Run with:  container-run"
  '';

  containerRun = pkgs.writeShellScriptBin "container-run" ''
    set -euo pipefail
    RUNTIME="''${1:-podman}"
    "$RUNTIME" network create "${name}-net" 2>/dev/null || true

    echo "Starting backend..."
    "$RUNTIME" run -d \
      --name "${name}-backend" \
      --network "${name}-net" \
      -p "${backendPort}:${backendPort}" \
      -e "PGHOST=''${PGHOST:?Set PGHOST to your PostgreSQL host}" \
      -e "PGPORT=''${PGPORT:-5432}" \
      -e "PGDATABASE=''${PGDATABASE:-${name}}" \
      -e "PGUSER=''${PGUSER:-${name}}" \
      -e "PGPASSWORD=''${PGPASSWORD:?Set PGPASSWORD}" \
      -e "USE_TLS=''${USE_TLS:-false}" \
      -e "ALLOWED_ORIGIN=''${ALLOWED_ORIGIN:-}" \
      -e "USE_REAL_AUTH=true" \
      "${name}-backend:latest"

    echo "Starting frontend..."
    "$RUNTIME" run -d \
      --name "${name}-frontend" \
      --network "${name}-net" \
      -p "${frontendPort}:${frontendPort}" \
      "${name}-frontend:latest"

    echo ""
    echo "  Backend:  http://localhost:${backendPort}"
    echo "  Frontend: http://localhost:${frontendPort}"
    echo "Logs:  $RUNTIME logs -f ${name}-backend"
    echo "Stop:  container-stop [$RUNTIME]"
  '';

  containerStop = pkgs.writeShellScriptBin "container-stop" ''
    set -euo pipefail
    RUNTIME="''${1:-podman}"
    for svc in backend frontend; do
      "$RUNTIME" stop "${name}-$svc" 2>/dev/null || true
      "$RUNTIME" rm   "${name}-$svc" 2>/dev/null || true
    done
    "$RUNTIME" network rm "${name}-net" 2>/dev/null || true
    echo "All ${name} containers stopped and removed."
  '';

  containerPushPi = pkgs.writeShellScriptBin "container-push-pi" ''
    set -euo pipefail
    REGISTRY="''${1:?Usage: container-push-pi <registry-prefix>}"
    echo "Building and pushing aarch64 images to $REGISTRY ..."
    echo "  (only changed layers will be transferred)"
    echo ""
    echo "  backend..."
    nix run ".#packages.aarch64-linux.backendImage-copyToRegistry" -- \
      "docker://$REGISTRY/${name}-backend:latest"
    echo "  frontend..."
    nix run ".#packages.aarch64-linux.frontendImage-copyToRegistry" -- \
      "docker://$REGISTRY/${name}-frontend:latest"
    echo ""
    echo "On the Pi 5:"
    echo "  podman pull $REGISTRY/${name}-backend:latest"
    echo "  podman pull $REGISTRY/${name}-frontend:latest"
    echo "  container-run podman"
  '';

  containerK8sManifests = pkgs.writeShellScriptBin "container-k8s-manifests" ''
    set -euo pipefail
    REGISTRY="''${1:?Usage: container-k8s-manifests <registry-prefix> [output-dir]}"
    OUT="''${2:-./${name}-k8s}"
    mkdir -p "$OUT"

    cat > "$OUT/00-namespace.yaml" <<EOF
    apiVersion: v1
    kind: Namespace
    metadata:
      name: ${name}
      labels:
        app.kubernetes.io/name: ${name}
    EOF

    cat > "$OUT/01-db-secret-TEMPLATE.yaml" <<EOF
    apiVersion: v1
    kind: Secret
    metadata:
      name: ${name}-db
      namespace: ${name}
    type: Opaque
    stringData:
      PGHOST:     "your-postgresql-host"
      PGPORT:     "5432"
      PGDATABASE: "${name}"
      PGUSER:     "${name}"
      PGPASSWORD: "CHANGEME"
    EOF

    cat > "$OUT/02-backend.yaml" <<EOF
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: ${name}-backend
      namespace: ${name}
    spec:
      replicas: 2
      selector:
        matchLabels:
          app: ${name}-backend
      template:
        metadata:
          labels:
            app: ${name}-backend
        spec:
          nodeSelector:
            kubernetes.io/arch: arm64
          containers:
          - name: backend
            image: $REGISTRY/${name}-backend:latest
            imagePullPolicy: Always
            ports:
            - containerPort: ${backendPort}
              name: http
            envFrom:
            - secretRef:
                name: ${name}-db
            env:
            - { name: PORT,          value: "${backendPort}" }
            - { name: USE_TLS,       value: "false"          }
            - { name: USE_REAL_AUTH, value: "true"           }
            readinessProbe:
              httpGet: { path: /openapi.json, port: ${backendPort} }
              initialDelaySeconds: 10
              periodSeconds: 5
            livenessProbe:
              httpGet: { path: /openapi.json, port: ${backendPort} }
              initialDelaySeconds: 30
              periodSeconds: 15
            resources:
              requests: { cpu: 100m, memory: 128Mi }
              limits:   { cpu: 1000m, memory: 512Mi }
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: ${name}-backend
      namespace: ${name}
    spec:
      selector:
        app: ${name}-backend
      ports:
      - port: ${backendPort}
        targetPort: ${backendPort}
        name: http
    EOF

    cat > "$OUT/03-frontend.yaml" <<EOF
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: ${name}-frontend
      namespace: ${name}
    spec:
      replicas: 2
      selector:
        matchLabels:
          app: ${name}-frontend
      template:
        metadata:
          labels:
            app: ${name}-frontend
        spec:
          nodeSelector:
            kubernetes.io/arch: arm64
          containers:
          - name: frontend
            image: $REGISTRY/${name}-frontend:latest
            imagePullPolicy: Always
            ports:
            - containerPort: ${frontendPort}
              name: http
            readinessProbe:
              httpGet: { path: /, port: ${frontendPort} }
              initialDelaySeconds: 5
              periodSeconds: 5
            resources:
              requests: { cpu: 50m,  memory: 64Mi  }
              limits:   { cpu: 500m, memory: 128Mi }
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: ${name}-frontend
      namespace: ${name}
    spec:
      selector:
        app: ${name}-frontend
      ports:
      - port: 80
        targetPort: ${frontendPort}
        name: http
      type: LoadBalancer
    EOF

    echo "Manifests written to $OUT/"
    echo ""
    echo "Note: nodeSelector kubernetes.io/arch: arm64 targets Pi 5 nodes."
    echo "Remove it for a mixed-arch cluster."
    echo ""
    echo "Next steps:"
    echo "  1. cp $OUT/01-db-secret-TEMPLATE.yaml $OUT/01-db-secret.yaml"
    echo "     Fill in credentials; add 01-db-secret.yaml to .gitignore"
    echo "  2. kubectl apply -f $OUT/"
  '';

in {
  inherit backendImage frontendImage frontendStatic nixosModule;

  tools = [
    containerLoad
    containerRun
    containerStop
    containerPushPi
    containerK8sManifests
  ];
}
