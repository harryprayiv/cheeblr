{ pkgs, name, lib, system ? builtins.currentSystem }:

let

  appConfig = import ./config.nix {
    inherit name;
  };


  psConfig  = appConfig.purescript;
  hsConfig  = appConfig.haskell;
  dbConfig  = appConfig.database;
  viteConfig = appConfig.vite;


  dirsToString = dirs: lib.concatStringsSep " " dirs;


  psDirs = psConfig.codeDirs;
  hsDirs = hsConfig.codeDirs;

  frontendDir  = builtins.match "(.*)/.*" (builtins.elemAt psConfig.codeDirs 0);
  frontendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head psConfig.codeDirs));

  backendDir  = builtins.match "(.*)/.*" (builtins.elemAt hsConfig.codeDirs 0);
  backendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head hsConfig.codeDirs));


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

  # Single merged deploy module — covers both source-based and nix-build workflows.
  deployModule = import ./deploy.nix {
    inherit pkgs name;
  };

  tlsModule = import ./tls.nix {
    inherit pkgs name;
  };

  testSuiteModule = import ./test-suite.nix {
    inherit pkgs name;
  };

  manifestModule = import ./scripts/manifest.nix {
    inherit pkgs lib;
    config = {
      backendPath  = backendPath;
      frontendPath = frontendPath;
      hsDirs = map (dir: builtins.replaceStrings ["${backendPath}/"] [""] dir) hsConfig.codeDirs;
      psDirs = map (dir: builtins.replaceStrings ["${frontendPath}/"] [""] dir) psConfig.codeDirs;
      hsConfig = {
        cabalFile = hsConfig.cabalFile;
      };
    };
  };

  devScripts = import ./scripts/file-tools.nix {
    inherit pkgs name lib;
    backendPath  = backendPath;
    frontendPath = frontendPath;
    hsDirs = map (dir: builtins.replaceStrings ["${backendPath}/"] [""] dir) hsConfig.codeDirs;
    psDirs = map (dir: builtins.replaceStrings ["${frontendPath}/"] [""] dir) psConfig.codeDirs;
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
      publisher = "cab404";
      name      = "vscode-direnv";
      version   = "1.0.0";
      sha256    = "sha256-+nLH+T9v6TQCqKZw6HPN/ZevQ65FVm2SAo2V9RecM3Y=";
    }
    {
      publisher = "nwolverson";
      name      = "language-purescript";
      version   = "0.2.9";
      sha256    = "sha256-9LBdo6lj+hz2NsvPmMV73nCT7uk6Q/ViguiilngOsGc=";
    }
    {
      publisher = "nwolverson";
      name      = "ide-purescript";
      version   = "0.26.6";
      sha256    = "sha256-zYLAcPgvfouMQj3NJlNJA0DNeayKxQhOYNloRN2YuU8=";
    }
    {
      publisher = "hoovercj";
      name      = "haskell-linter";
      version   = "0.0.6";
      sha256    = "sha256-MjgqR547GC0tMnBJDMsiB60hJE9iqhKhzP6GLhcLZzk=";
    }
    {
      publisher = "justusadam";
      name      = "language-haskell";
      version   = "3.6.0";
      sha256    = "sha256-rZXRzPmu7IYmyRWANtpJp3wp0r/RwB7eGHEJa7hBvoQ=";
    }
  ];


  vscodiumWithExtensions = pkgs.vscode-with-extensions.override {
    vscode           = pkgs.vscodium;
    vscodeExtensions = extensions;
  };


  workspaceModule = {
    code-workspace = pkgs.writeShellApplication {
      name            = "code-workspace";
      runtimeInputs   = with pkgs; [ vscodiumWithExtensions ];
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
            "files.exclude": {
              "frontend": false,
              "backend":  false,
              "nix":      false
            },
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
            "purescript.workspace.multiRootMode": true,
            "purescript.sourcePath": "src",
            "haskell.checkProject": true,
            "files.watcherExclude": {
              "**/distdist-newstyle.spagooutput.psci_modules/**": true
            }
          },
          "extensions": {
            "recommendations": [
              "nwolverson.ide-purescript",
              "nwolverson.language-purescript",
              "haskell.haskell",
              "justusadam.language-haskell"
            ]
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
      runtimeInputs = with pkgs; [ rsync ];
      text = ''
        rsync -va --delete --exclude-from='.gitignore' --exclude='.git/' ~/NAS/plutus/workdir/${name}/ ~/NAS/plutus/workspace/scdWs/${name}/
        rsync -va ~/.local/share/${name}/backups/ ~/NAS/plutus/${name}DB/
        rsync -va script/concat_archive/ ~/NAS/plutus/workspace/scdWs/${name}/script/concat_archive/
      '';
    };
  };


  commonBuildInputs = with pkgs; [

    # ── Nix-build artifact workflows ──────────────────────────────────────
    deployModule.build-all
    deployModule.deploy-nix
    deployModule.deploy-nix-interactive
    deployModule.stop-nix
    deployModule.status-nix
    deployModule.tui

    # ── Source workflows (cabal / spago / vite) ───────────────────────────
    deployModule.deploy
    deployModule.stop
    deployModule.launch-dev
    deployModule.db-start
    deployModule.db-stop
    deployModule.backend-start
    deployModule.backend-stop
    deployModule.frontend-start
    deployModule.frontend-stop

    # ── Frontend toolchain ────────────────────────────────────────────────
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

    # ── Native / crypto libs ──────────────────────────────────────────────
    zlib
    pgcli
    pkg-config
    openssl.dev
    libiconv
    openssl

    # ── TLS ───────────────────────────────────────────────────────────────
    tlsModule.tls-setup
    tlsModule.tls-info
    tlsModule.tls-clean
    pkgs.mkcert
    open-firewall

    # ── PostgreSQL utils ──────────────────────────────────────────────────
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

    # ── Project tooling ───────────────────────────────────────────────────
    toilet
    rsync
    tmux
    vscodiumWithExtensions
    workspaceModule.backup-project
    workspaceModule.code-workspace
    manifestModule.generateScript
    devScripts.compile-manifest
    devScripts.compile-archive

    # ── Test suite ────────────────────────────────────────────────────────
    testSuiteModule.test-unit
    testSuiteModule.test-integration
    testSuiteModule.test-integration-tls
    testSuiteModule.test-suite
    testSuiteModule.test-smoke

    # ── Shell utils ───────────────────────────────────────────────────────
    coreutils
    bash
    gnused
    gnugrep
    jq
    perl
    findutils
  ];


  nativeBuildInputs = with pkgs; [
    pkg-config
    postgresql
    postgresql.lib
    zlib
    openssl.dev
    libiconv
    openssl
    lsof
    tmux
    alacritty
    direnv
  ];


  darwinInputs = if (system == "aarch64-darwin" || system == "x86_64-darwin") then
    (with pkgs.darwin.apple_sdk.frameworks; [
      Cocoa
      CoreServices
    ])
  else [];


  devShell = pkgs.mkShell {
    inherit name;
    inherit nativeBuildInputs;
    buildInputs = commonBuildInputs ++ darwinInputs;

    shellHook = ''
      export PGDATA="${dbConfig.dataDir}"
      export PGPORT="${toString dbConfig.port}"
      export PGUSER="${dbConfig.user}"
      export PGPASSWORD="${dbConfig.password}"
      export PGDATABASE="${dbConfig.name}"
      export PKG_CONFIG_PATH="${pkgs.postgresql.lib}/lib/pkgconfig:$PKG_CONFIG_PATH"

      mkdir -p "$(pwd)/script/concat_archive/output" "$(pwd)/script/concat_archive/archive" "$(pwd)/script/concat_archive/.hashes"
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

      echo "Available commands:"
      echo "  Database:"
      echo "    pg-start               - Start PostgreSQL server"
      echo "    pg-connect             - Connect to PostgreSQL server"
      echo "    pg-stop                - Stop PostgreSQL server"
      echo "    pg-cleanup             - Remove PostgreSQL data directory"
      echo "    pg-backup              - Backup PostgreSQL database"
      echo "    pg-restore <file>      - Restore PostgreSQL database from backup"
      echo "    pg-rotate-credentials  - Generate new PostgreSQL password"
      echo "    pg-create-schema <n>   - Create new schema"
      echo "    pg-stats               - Show PostgreSQL statistics"
      echo ""
      echo "  Nix Deployment (artifact-based):"
      echo "    build-all              - nix build ."
      echo "    deploy-nix             - Deploy headless (Nix artifacts)"
      echo "    deploy-nix-interactive - Deploy with tmux (Nix artifacts)"
      echo "    stop-nix               - Stop Nix deployment"
      echo "    status-nix             - Show service status"
      echo "    ${name}-tui            - Interactive TUI menu"
      echo ""
      echo "  Source Deployment (cabal/spago):"
      echo "    deploy                 - Deploy with tmux (cabal run / spago)"
      echo "    stop                   - Stop source deployment"
      echo "    launch-dev             - Launch in Alacritty windows"
      echo "    db-start               - Start database"
      echo "    db-stop                - Stop database"
      echo "    backend-start          - Start Haskell backend"
      echo "    backend-stop           - Stop Haskell backend"
      echo "    frontend-start         - Start PureScript frontend"
      echo "    frontend-stop          - Stop PureScript frontend"
      echo ""
      echo "  Frontend:"
      echo "    vite                   - Start Vite development server"
      echo "    vite-cleanup           - Clean up vite processes"
      echo "    spago-watch            - Watch PureScript files for changes"
      echo "    codegen                - Generate types from schema"
      echo "    concurrent             - Run concurrent development tasks"
      echo "    dev                    - Start all dev services in tmux"
      echo ""
      echo "  TLS:"
      echo "    tls-setup              - Generate/refresh TLS certificates"
      echo "    tls-info               - Show certificate details"
      echo "    tls-clean              - Remove certificates"
      echo ""
      echo "  Project:"
      echo "    code-workspace         - Open VSCodium workspace"
      echo "    backup-project         - Backup project files"
      echo "    compile-manifest       - Concatenate project files"
      echo "    compile-archive        - Full project archive"
      echo ""
      echo "  Testing:"
      echo "    test-unit              - Unit tests (no services needed)"
      echo "    test-integration       - Integration tests (HTTP)"
      echo "    test-integration-tls   - Integration tests (TLS)"
      echo "    test-suite             - Full suite (unit + HTTP + TLS)"
      echo "    test-smoke             - Smoke test against running backend"
      echo ""
      echo ""
      toilet ${lib.toSentenceCase name} -t --metal
    '';
  };

in {
  inherit devShell;
  inherit workspaceModule;
}
