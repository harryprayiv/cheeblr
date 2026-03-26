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
#            Dead-code elimination at the PureScript level.  Smallest bundle.
#
#   "simple"
#            purs-nix compile  ->  esbuild entry shim  ->  esbuild --minify
#            Entry shim calls main() explicitly before bundling.

{ pkgs
, lib            ? pkgs.lib
, name
, backendPackage
, nix2containerPkgs
, bundleMode        ? "es"
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

  # ── Minimal /etc files ────────────────────────────────────────────────────
  etcFiles = pkgs.runCommand "${name}-etc-files" { } ''
    mkdir -p $out/etc
    cat > $out/etc/passwd <<'EOF'
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/:/bin/sh
EOF
    cat > $out/etc/group <<'EOF'
root:x:0:
nogroup:x:65534:
nobody:x:65534:
EOF
    cat > $out/etc/nsswitch.conf <<'EOF'
passwd: files
group:  files
shadow: files
EOF
  '';

  # ── Backend entrypoint factory ────────────────────────────────────────────
  mkBackendEntry = pkg: pkgs.writeShellScript "${name}-backend-entrypoint" ''
    set -euo pipefail
    mkdir -p /var/log/${name}
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
      paths       = [ pkgs.cacert pkgs.coreutils pkgs.bash etcFiles backendRootDirs ];
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
        "PGHOST=127.0.0.1"
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

  # ── Frontend static build shared helper ───────────────────────────────────
  rewriteAndCopy = outDir: srcDir: ''
    echo "--- Copying static assets..."
    [ -d "${srcDir}/public"  ] && cp -r "${srcDir}/public/." "${outDir}/"        || true
    [ -d "${srcDir}/css"     ] && cp -r "${srcDir}/css"      "${outDir}/css"     || true
    [ -d "${srcDir}/assets"  ] && cp -r "${srcDir}/assets"   "${outDir}/assets"  || true

    find "${srcDir}" -maxdepth 1 -name "*.css" -exec cp {} "${outDir}/" \; 2>/dev/null || true

    if [ -f "${srcDir}/index.html" ]; then
      echo "--- Rewriting index.html..."
      echo "    Original script/link tags:"
      grep -E '<script|<link' "${srcDir}/index.html" || true

      _TMPHTML=$(mktemp)
      cp "${srcDir}/index.html" "$_TMPHTML"
      ${pkgs.nodejs_20}/bin/node ${rewriteIndexScript} "$_TMPHTML"
      cp "$_TMPHTML" "${outDir}/index.html"
      rm "$_TMPHTML"

      echo "    After rewrite:"
      grep -E '<script|<link' "${outDir}/index.html" || true
    fi
  '';

  rewriteIndexScript = pkgs.writeText "rewrite-index.js" ''
    const fs = require("fs");
    const p = process.argv[2];
    let html = fs.readFileSync(p, "utf8");
    html = html.replace(/<script[^>]*\btype\s*=\s*["']module["'][^>]*>[\s\S]*?<\/script>\s*/gi, "");
    html = html.replace(/<\/body>/i, "<script src=\"/app.js\"></script>\n</body>");
    fs.writeFileSync(p, html);
  '';

  mkPs = purs-nix-instance.purs {
    dir          = frontendSrc;
    dependencies = psDependencies;
    inherit purescript;
    nodejs = pkgs.nodejs_20;
  };

  # ── "es" mode ─────────────────────────────────────────────────────────────
  frontendStaticEs =
    pkgs.runCommand "${name}-frontend-static" {
      buildInputs = [
        (mkPs.command { })
        purescript
        pkgs.purs-backend-es
        pkgs.spago-unstable
        pkgs.nodejs_20
        pkgs.esbuild
        pkgs.perl
      ];
      src = frontendSrc;
    } ''
      set -euo pipefail

      cp -r "$src/." workdir
      chmod -R +w workdir
      cd workdir

      echo "--- Step 1: purs-nix compile"
      purs-nix compile

      if [ ! -d output ]; then
        echo "ERROR: purs-nix compile produced no output/ directory"
        exit 1
      fi

      echo "--- Step 2: purs-backend-es bundle-app (DCE)"
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
        --platform=browser \
        --minify \
        --sourcemap=external

      FINAL_BYTES=$(wc -c < "$out/app.js")
      echo "    app.js: $FINAL_BYTES bytes"
      echo "    Reduction: $(( (BUNDLE_BYTES - FINAL_BYTES) * 100 / BUNDLE_BYTES ))%"

      ${rewriteAndCopy "\"$out\"" "\"$src\""}

      echo "--- Complete (mode: es)."
      find "$out" -maxdepth 2 -type f
    '';

  # ── "simple" mode ─────────────────────────────────────────────────────────
  frontendStaticSimple =
    pkgs.runCommand "${name}-frontend-static" {
      buildInputs = [
        (mkPs.command { })
        purescript
        pkgs.spago-unstable
        pkgs.nodejs_20
        pkgs.esbuild
        pkgs.perl
      ];
      src = frontendSrc;
    } ''
      set -euo pipefail

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
      # Entry shim: explicitly call main() so the IIFE actually runs the app.
      echo 'require("./output/Main/index.js").main()' > _entry.js

      mkdir -p "$out"
      ${pkgs.esbuild}/bin/esbuild _entry.js \
        --bundle \
        --outfile="$out/app.js" \
        --format=iife \
        --platform=browser \
        --minify \
        --sourcemap=external

      FINAL_BYTES=$(wc -c < "$out/app.js")
      echo "    app.js: $FINAL_BYTES bytes"

      ${rewriteAndCopy "\"$out\"" "\"$src\""}

      echo "--- Complete (mode: simple)."
      find "$out" -maxdepth 2 -type f
    '';

  frontendStaticFromSource =
    if bundleMode == "es" then frontendStaticEs
    else frontendStaticSimple;

  # ── frontendProject fallback ───────────────────────────────────────────────
  frontendStaticWithProject =
    pkgs.runCommand "${name}-frontend-static-precompiled" {
      buildInputs =
        (if bundleMode == "es" then [ pkgs.purs-backend-es ] else [])
        ++ [ pkgs.esbuild pkgs.perl ];
      inherit frontendProject;
      src = frontendSrc;
    } ''
      set -euo pipefail

      OUTPUT_DIR="${frontendProject}"
      MAIN_JS="$OUTPUT_DIR/Main/index.js"

      if [ ! -f "$MAIN_JS" ]; then
        echo "ERROR: frontendProject does not contain Main/index.js"
        find "$OUTPUT_DIR" -type f | head -20
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
        echo "--- esbuild entry shim (mode: simple)"
        echo "require(\"$MAIN_JS\").main()" > _entry.js
        INPUT_JS=_entry.js
      ''}

      ${pkgs.esbuild}/bin/esbuild "$INPUT_JS" \
        --bundle \
        --outfile="$out/app.js" \
        --format=iife \
        --platform=browser \
        --minify \
        --sourcemap=external

      ${rewriteAndCopy "\"$out\"" "\"$src\""}
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
        listen ${frontendPort} ssl;
        ssl_certificate     /run/secrets/tls.crt;
        ssl_certificate_key /run/secrets/tls.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        root  /var/www/${name};
        index index.html;

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
             /tmp/nginx-fastcgi /tmp/nginx-uwsgi /tmp/nginx-scgi \
             /var/log/nginx /run/nginx /run/secrets
    exec ${pkgs.nginx}/bin/nginx -c ${nginxConf}
  '';

  frontendRootDirs = pkgs.runCommand "${name}-frontend-rootdirs" { } ''
    mkdir -p $out/tmp
    mkdir -p $out/var/www/${name}
    mkdir -p $out/var/log/nginx
    mkdir -p $out/run/nginx
    mkdir -p $out/run/secrets
    cp -r ${frontendStatic}/. $out/var/www/${name}/
    chmod 1777 $out/tmp
  '';

  # ── Frontend image layers ─────────────────────────────────────────────────
  frontendNginxLayer = nix2containerPkgs.buildLayer {
    deps = [ pkgs.nginx pkgs.coreutils pkgs.bash ];
  };

  frontendStaticLayer = nix2containerPkgs.buildLayer {
    deps   = [ frontendRootDirs etcFiles ];
    layers = [ frontendNginxLayer ];
  };

  # ── Frontend OCI image ────────────────────────────────────────────────────
  frontendImage = nix2containerPkgs.buildImage {
    name = "${name}-frontend";
    tag  = "latest";

    copyToRoot = pkgs.buildEnv {
      name        = "${name}-frontend-copyToRoot";
      paths       = [ pkgs.coreutils pkgs.bash etcFiles frontendRootDirs ];
      pathsToLink = [ "/bin" "/etc" "/tmp" "/var" "/run" ];
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

  # ── NixOS module ──────────────────────────────────────────────────────────
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

  # ── Helper scripts ────────────────────────────────────────────────────────

  containerLoad = pkgs.writeShellScriptBin "container-load" ''
    set -euo pipefail
    RUNTIME="''${1:-podman}"
    SYSTEM="${thisSystem}"
    echo "Building and loading ${name} images ($SYSTEM) ..."
    echo "  backend..."
    nix run ".#packages.$SYSTEM.backendImage-copyToPodman"
    echo "  frontend..."
    nix run ".#packages.$SYSTEM.frontendImage-copyToPodman"
    echo ""
    echo "Verifying loaded images..."
    for img in "${name}-backend" "${name}-frontend"; do
      if "$RUNTIME" image inspect "$img:latest" >/dev/null 2>&1; then
        echo "  ok: $img:latest"
      else
        echo "  WARNING: $img:latest not found after load"
      fi
    done
    echo ""
    echo "Run with:  container-run [$RUNTIME]"
  '';

  containerRun = pkgs.writeShellScriptBin "container-run" ''
    set -euo pipefail
    RUNTIME="''${1:-podman}"

    _PGHOST="''${PGHOST:-127.0.0.1}"
    _PGPORT="''${PGPORT:-5432}"
    _PGDATABASE="''${PGDATABASE:-${name}}"
    _PGUSER="''${PGUSER:-$(whoami)}"
    _PGPASSWORD="''${PGPASSWORD:-}"
    _ALLOWED_ORIGIN="''${ALLOWED_ORIGIN:-}"

    _USE_TLS=false
    _TLS_ARGS=""
    CERT_DIR="${appConfig.tls.certDir}"
    CERT_DIR="$(echo "$CERT_DIR" | envsubst 2>/dev/null || echo "$CERT_DIR")"
    if [ -f "$CERT_DIR/${appConfig.tls.certFile}" ] && \
       [ -f "$CERT_DIR/${appConfig.tls.keyFile}" ]; then
      _USE_TLS=true
      _TLS_ARGS="-v $CERT_DIR/${appConfig.tls.certFile}:/run/secrets/tls.crt:ro -v $CERT_DIR/${appConfig.tls.keyFile}:/run/secrets/tls.key:ro"
      echo "TLS: using certs from $CERT_DIR"
    else
      echo "TLS: no certs found -- run tls-setup first for HTTPS"
    fi

    if [ -z "$_PGPASSWORD" ] && command -v sops-get >/dev/null 2>&1; then
      _PGPASSWORD="$(sops-get db_password 2>/dev/null || true)"
    fi
    if [ -z "$_PGPASSWORD" ]; then
      echo "Warning: PGPASSWORD not set -- PostgreSQL trust auth only."
      echo ""
    fi

    if ! ${pkgs.postgresql}/bin/pg_isready -h "$_PGHOST" -p "$_PGPORT" -q 2>/dev/null; then
      echo "Error: PostgreSQL is not accepting connections on $_PGHOST:$_PGPORT"
      echo "  Run pg-start first."
      exit 1
    fi

    image_exists() {
      "$RUNTIME" image inspect "$1:latest" >/dev/null 2>&1
    }
    if ! image_exists "${name}-backend" || ! image_exists "${name}-frontend"; then
      echo "One or more images not found -- running container-load..."
      echo ""
      container-load "$RUNTIME"
    fi

    "$RUNTIME" network create "${name}-net" 2>/dev/null || true

    _PROTOCOL="http"
    [ "$_USE_TLS" = "true" ] && _PROTOCOL="https"

    echo "Starting backend..."
    echo "  PG:       $_PGUSER@$_PGHOST:$_PGPORT/$_PGDATABASE"
    echo "  Protocol: $_PROTOCOL"
    eval "$RUNTIME" run -d \
      --pull=never \
      --network=host \
      --name "${name}-backend" \
      $_TLS_ARGS \
      -e "PGHOST=$_PGHOST" \
      -e "PGPORT=$_PGPORT" \
      -e "PGDATABASE=$_PGDATABASE" \
      -e "PGUSER=$_PGUSER" \
      -e "PGPASSWORD=$_PGPASSWORD" \
      -e "USE_TLS=$_USE_TLS" \
      -e "ALLOWED_ORIGIN=$_ALLOWED_ORIGIN" \
      -e "USE_REAL_AUTH=true" \
      "${name}-backend:latest"

    echo "Starting frontend..."
    eval "$RUNTIME" run -d \
      --pull=never \
      --network=host \
      --name "${name}-frontend" \
      $_TLS_ARGS \
      "${name}-frontend:latest"

    echo ""
    echo "  Backend:  $_PROTOCOL://localhost:${backendPort}"
    echo "  Frontend: $_PROTOCOL://localhost:${frontendPort}"
    echo ""
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
    echo "  1. cp $OUT/01-db-secret-TEMPLATE.yaml $OUT/01-db-secret.yaml"
    echo "     Fill in credentials; add to .gitignore"
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