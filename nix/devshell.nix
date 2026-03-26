# nix/devshell.nix
{ pkgs, name, lib, system ? builtins.currentSystem
  # containersModule is passed in from build.nix; null omits the container
  # section from the shell entirely (used by ci-shell.nix).
, containersModule ? null
}:

let
  appConfig = import ./config.nix { inherit name; };

  psConfig   = appConfig.purescript;
  hsConfig   = appConfig.haskell;
  dbConfig   = appConfig.database;
  viteConfig = appConfig.vite;

  frontendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head psConfig.codeDirs));
  backendPath  = builtins.head (builtins.split "/[^/]*$" (builtins.head hsConfig.codeDirs));

  stripBackendPrefix  = path: builtins.replaceStrings [ "${backendPath}/"  ] [ "" ] path;
  stripFrontendPrefix = path: builtins.replaceStrings [ "${frontendPath}/" ] [ "" ] path;

  hsTestDirs =
    let testPath = hsConfig.tests or null;
    in if testPath != null then [ (stripBackendPrefix testPath) ] else [];

  psTestDirs =
    let testPath = psConfig.tests or null;
    in if testPath != null then [ (stripFrontendPrefix testPath) ] else [];

  postgresModule = import ./postgres-utils.nix {
    inherit pkgs name;
    database = dbConfig;
  };

  frontendModule = import ./frontend.nix {
    inherit pkgs name;
    frontend = {
      inherit (viteConfig) viteport settings;
      inherit (psConfig) codeDirs spagoFile;
    };
  };

  deployModule    = import ./deploy.nix            { inherit pkgs name; };
  tlsModule       = import ./tls.nix               { inherit pkgs name; };
  testSuiteModule = import ./test-suite.nix        { inherit pkgs name; };
  sopsModule      = import ./sops-dev.nix          { inherit pkgs lib name; };
  bootstrapModule = import ./bootstrap-admin-tool.nix { inherit pkgs lib name; };

  manifestModule = import ./scripts/manifest.nix {
    inherit pkgs lib;
    config = {
      backendPath  = backendPath;
      frontendPath = frontendPath;
      hsDirs = map (d: builtins.replaceStrings ["${backendPath}/"]  [""] d) hsConfig.codeDirs;
      psDirs = map (d: builtins.replaceStrings ["${frontendPath}/"] [""] d) psConfig.codeDirs;
      inherit hsTestDirs psTestDirs;
      hsConfig = { cabalFile = hsConfig.cabalFile; };
    };
  };

  devScripts = import ./scripts/file-tools.nix {
    inherit pkgs name lib;
    backendPath  = backendPath;
    frontendPath = frontendPath;
    hsDirs = map (d: builtins.replaceStrings ["${backendPath}/"]  [""] d) hsConfig.codeDirs;
    psDirs = map (d: builtins.replaceStrings ["${frontendPath}/"] [""] d) psConfig.codeDirs;
    inherit hsTestDirs psTestDirs;
    hsConfig = hsConfig;
  };

  open-firewall = pkgs.writeShellScriptBin "open-firewall" ''
    set -euo pipefail
    echo "Opening firewall for dev ports..."
    sudo iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || \
      sudo iptables -I INPUT -p tcp --dport 8080 -j ACCEPT
    sudo iptables -C INPUT -p tcp --dport 5173 -j ACCEPT 2>/dev/null || \
      sudo iptables -I INPUT -p tcp --dport 5173 -j ACCEPT
    echo "Ports 8080 and 5173 open (until reboot)"
  '';

  extensions = (with pkgs.vscode-extensions; [
    mkhl.direnv
    bbenoist.nix
    haskell.haskell
    justusadam.language-haskell
    arrterian.nix-env-selector
    jnoortheen.nix-ide
    gruntfuggly.todo-tree
  ]) ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
    {
      publisher = "cab404"; name = "vscode-direnv"; version = "1.0.0";
      sha256 = "sha256-+nLH+T9v6TQCqKZw6HPN/ZevQ65FVm2SAo2V9RecM3Y=";
    }
    {
      publisher = "nwolverson"; name = "language-purescript"; version = "0.2.9";
      sha256 = "sha256-9LBdo6lj+hz2NsvPmMV73nCT7uk6Q/ViguiilngOsGc=";
    }
    {
      publisher = "nwolverson"; name = "ide-purescript"; version = "0.26.6";
      sha256 = "sha256-zYLAcPgvfouMQj3NJlNJA0DNeayKxQhOYNloRN2YuU8=";
    }
    {
      publisher = "hoovercj"; name = "haskell-linter"; version = "0.0.6";
      sha256 = "sha256-MjgqR547GC0tMnBJDMsiB60hJE9iqhKhzP6GLhcLZzk=";
    }
    {
      publisher = "justusadam"; name = "language-haskell"; version = "3.6.0";
      sha256 = "sha256-rZXRzPmu7IYmyRWANtpJp3wp0r/RwB7eGHEJa7hBvoQ=";
    }
  ];

  vscodiumWithExtensions = pkgs.vscode-with-extensions.override {
    vscode           = pkgs.vscodium;
    vscodeExtensions = extensions;
  };

  workspaceModule = {
    code-workspace = pkgs.writeShellApplication {
      name          = "code-workspace";
      runtimeInputs = [ vscodiumWithExtensions ];
      text = ''
        if [ ! -f "${name}.code-workspace" ]; then
          cat > ${name}.code-workspace <<EOF
        {
          "folders": [
            { "name": "PS_frontend", "path": "frontend" },
            { "name": "HS_backend",  "path": "backend" },
            { "name": "nix",         "path": "nix" },
            { "name": "Helpers",     "path": "script" },
            { "name": "Root",        "path": "./" }
          ],
          "settings": {
            "[purescript]": {
              "editor.defaultFormatter": "nwolverson.ide-purescript",
              "editor.fontFamily": "Hasklig",
              "editor.fontSize": 14
            },
            "[haskell]": {
              "editor.defaultFormatter": "haskell.haskell",
              "haskell.formattingProvider": "fourmolu",
              "editor.fontFamily": "Hasklig",
              "editor.fontSize": 14
            },
            "purescript.addSpagoSources": true,
            "haskell.checkProject": true
          }
        }
        EOF
          echo "Created ${name}.code-workspace"
        fi
        codium ${name}.code-workspace
      '';
    };

    backup-project = pkgs.writeShellApplication {
      name          = "backup-project";
      runtimeInputs = [ pkgs.rsync ];
      text = ''
        rsync -va --delete --exclude-from='.gitignore' --exclude='.git/' \
          ~/NAS/plutus/workdir/${name}/ ~/NAS/plutus/workspace/scdWs/${name}/
        rsync -va ~/.local/share/${name}/backups/ ~/NAS/plutus/${name}DB/
        rsync -va script/concat_archive/ \
          ~/NAS/plutus/workspace/scdWs/${name}/script/concat_archive/
      '';
    };

    project-cleanup = pkgs.writeShellApplication {
      name = "project-cleanup";
      text = ''
        set -euo pipefail
        PROJECT_ROOT="$(pwd)"
        echo "Cleaning compiled artifacts for ${name}..."
        echo "  Project root: $PROJECT_ROOT"
        echo ""

        remove() {
          local target="$1"
          local prefix="$PROJECT_ROOT/"
          if [ -e "$target" ]; then
            rm -rf "$target"
            echo "  + removed ''${target#"$prefix"}"
          else
            echo "  - skipped ''${target#"$prefix"}"
          fi
        }

        echo "Frontend (${frontendPath}):"
        remove "$PROJECT_ROOT/${frontendPath}/.spago"
        remove "$PROJECT_ROOT/${frontendPath}/.vite"
        remove "$PROJECT_ROOT/${frontendPath}/output"
        remove "$PROJECT_ROOT/${frontendPath}/.spec-results"

        echo ""
        echo "Backend (${backendPath}):"
        remove "$PROJECT_ROOT/${backendPath}/dist-newstyle"
        remove "$PROJECT_ROOT/${backendPath}/output"
        remove "$PROJECT_ROOT/${backendPath}/${name}-compliance.log"

        echo ""
        echo "Project root:"
        remove "$PROJECT_ROOT/.direnv"
        remove "$PROJECT_ROOT/.vscode"

        echo ""
        echo "Done. Run 'nix develop' to re-enter the dev shell."
      '';
    };
  };

  containerTools   = if containersModule != null then containersModule.tools else [];
  hasContainerTools = containersModule != null;

  commonBuildInputs = with pkgs; [

    deployModule.build-all
    deployModule.deploy-nix
    deployModule.deploy-nix-interactive
    deployModule.stop-nix
    deployModule.status-nix
    deployModule.tui
    deployModule.deploy
    deployModule.stop
    deployModule.launch-dev
    deployModule.db-start
    deployModule.db-stop
    deployModule.backend-start
    deployModule.backend-stop
    deployModule.frontend-start
    deployModule.frontend-stop
    gum

    esbuild
    nodejs_20
    nixpkgs-fmt
    purs
    purs-tidy
    purs-backend-es
    purescript-language-server
    spago-unstable
    frontendModule.vite
    frontendModule.vite-cleanup
    frontendModule.spago-watch
    frontendModule.concurrent
    frontendModule.codegen
    frontendModule.dev

    zlib 
    pgcli 
    pkg-config 
    openssl.dev 
    libiconv 
    openssl

    tlsModule.tls-setup
    tlsModule.tls-info
    tlsModule.tls-clean
    tlsModule.tls-sops-update
    tlsModule.tls-sops-extract
    pkgs.mkcert

    sopsModule.sops-init-key
    sopsModule.sops-pubkey
    sopsModule.sops-bootstrap
    sopsModule.sops-get
    sopsModule.sops-exec
    sopsModule.sops-status
    pkgs.sops
    pkgs.age
    pkgs.ssh-to-age

    bootstrapModule.bootstrap-admin
    bootstrapModule.admin-password-info

    open-firewall

    postgresModule.pg-start
    postgresModule.pg-connect
    postgresModule.pg-stop
    postgresModule.pg-cleanup
    postgresModule.pg-backup
    postgresModule.pg-restore
    postgresModule.pg-rotate-credentials
    postgresModule.pg-create-schema
    postgresModule.pg-stats
    pgadmin4
    gettext

    toilet rsync tmux
    vscodiumWithExtensions
    workspaceModule.backup-project
    workspaceModule.code-workspace
    workspaceModule.project-cleanup
    manifestModule.generateScript
    devScripts.compile-manifest
    devScripts.compile-archive
    devScripts.llm-context

    testSuiteModule.test-unit
    testSuiteModule.test-integration
    testSuiteModule.test-integration-tls
    testSuiteModule.test-suite
    testSuiteModule.test-smoke

    coreutils bash gnused gnugrep jq perl findutils
  ] ++ containerTools;

  nativeBuildInputs = with pkgs; [
    pkg-config postgresql postgresql.lib zlib openssl.dev libiconv openssl
    lsof tmux alacritty direnv
  ];

  darwinInputs =
    if (system == "aarch64-darwin" || system == "x86_64-darwin") then
      (with pkgs.darwin.apple_sdk.frameworks; [ Cocoa CoreServices ])
    else [];

  # Container help text is conditional on containersModule being provided.
  containerHelpText = if hasContainerTools then ''
      echo "  OCI Containers (nix2container / podman):"
      echo "    container-run  [podman]         - run locally (native arch)"
      echo "    container-stop [podman]         - stop and remove"
      echo "    container-load [podman]         - load pre-built images"
      echo "    container-push-pi <registry>    - push aarch64 images to registry"
      echo "    container-k8s-manifests <reg>   - write Kubernetes / Talos YAML"
      echo ""
      echo "  Build Pi 5 images (requires binfmt or remote builder):"
      echo "    nix build .#packages.aarch64-linux.backendImage"
      echo "    nix build .#packages.aarch64-linux.frontendImage"
      echo ""
      echo "  Push directly (skips already-pushed layers):"
      echo "    nix run .#packages.aarch64-linux.backendImage.copyToRegistry -- \\"
      echo "        docker://myregistry.io/${name}-backend:latest"
      echo ""
      echo "  Enable cross-compilation in your NixOS config:"
      echo "    boot.binfmt.emulatedSystems = [ \"aarch64-linux\" ];"
  '' else "";

  devShell = pkgs.mkShell {
    inherit name;
    inherit nativeBuildInputs;
    buildInputs = commonBuildInputs ++ darwinInputs;

    shellHook = ''
      export PGDATA="${dbConfig.dataDir}"
      export PGPORT="${toString dbConfig.port}"
      export PGUSER="${dbConfig.user}"
      export PGDATABASE="${dbConfig.name}"
      export PKG_CONFIG_PATH="${pkgs.postgresql.lib}/lib/pkgconfig:$PKG_CONFIG_PATH"

      mkdir -p "$(pwd)/script/concat_archive/output" \
               "$(pwd)/script/concat_archive/archive" \
               "$(pwd)/script/concat_archive/.hashes"
      mkdir -p "$(pwd)/.vscode"

      cat > "$(pwd)/.vscode/argv.json" <<EOF
      {
        "disable-hardware-acceleration": true,
        "enable-crash-reporter": true,
        "crash-reporter-id": "4e77d7bd-2f26-4723-9757-4f86cefd7010",
        "password-store": "gnome"
      }
      EOF

      echo "Welcome to the ${lib.toSentenceCase name} dev environment!"
      echo ""
      echo "Secrets:"
      ${sopsModule.loadSecretsHook}
      echo ""
      echo "Available commands:"
      echo "  Secrets / TLS:"
      echo "    sops-init-key          - Derive age key from ~/.ssh/id_ed25519"
      echo "    sops-pubkey            - Print this machine's age public key"
      echo "    sops-bootstrap         - Create secrets/${name}.yaml (first-time)"
      echo "    sops-get <key>         - Decrypt a single value to stdout"
      echo "    sops-exec <cmd ...>    - Run command with all secrets as env vars"
      echo "    sops-status            - Verify sops setup end-to-end"
      echo "    tls-setup              - Generate/refresh local mkcert TLS certs"
      echo "    tls-sops-update        - Encrypt local certs into sops secrets"
      echo "    tls-sops-extract       - Extract sops certs to local cert path"
      echo "    tls-info               - Show certificate details"
      echo "    sops secrets/${name}.yaml - Edit secrets directly"
      echo ""
      echo "  Auth Bootstrap (run once after first pg-start):"
      echo "    bootstrap-admin        - Create admin user, store password in sops"
      echo "    admin-password-info    - Check whether admin_password is in sops"
      echo "    sops-get admin_password - Reveal stored admin password"
      echo ""
      echo "  Database:"
      echo "    pg-start               - Start PostgreSQL"
      echo "    pg-connect             - Connect to PostgreSQL"
      echo "    pg-stop                - Stop PostgreSQL"
      echo "    pg-backup / pg-restore - Backup / restore"
      echo "    pg-rotate-credentials  - Rotate password + update sops hint"
      echo "    pg-stats               - Database statistics"
      echo ""
      echo "  Nix Deployment:"
      echo "    build-all              - nix build ."
      echo "    deploy-nix             - Headless (Nix artifacts)"
      echo "    deploy-nix-interactive - tmux (Nix artifacts)"
      echo "    stop-nix / status-nix  - Stop / status"
      echo "    ${name}-tui            - Interactive TUI menu"
      echo ""
      echo "  Source Deployment:"
      echo "    deploy / stop          - tmux (cabal/spago)"
      echo "    launch-dev             - Alacritty windows"
      echo "    backend-start/stop     - Haskell backend"
      echo "    frontend-start/stop    - PureScript frontend"
      echo ""
      echo "  Frontend:  vite  spago-watch  codegen  dev"
      echo "  Testing:   test-unit  test-integration  test-integration-tls  test-suite  test-smoke"
      echo ""
      ${containerHelpText}
      toilet ${lib.toSentenceCase name} -t --metal
    '';
  };

in {
  inherit devShell workspaceModule;
}
