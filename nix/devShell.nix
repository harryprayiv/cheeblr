{ pkgs, name, lib, system ? builtins.currentSystem }:

let
  # Import app config to use in all the scripts
  appConfig = import ./app-config.nix {
    inherit name;
  };
  
  # Extract configuration for different components
  psConfig = appConfig.purescript;
  hsConfig = appConfig.haskell;
  dbConfig = appConfig.database;
  viteConfig = appConfig.vite;
  
  # Helper function to convert list of directories to a space-separated string
  dirsToString = dirs: lib.concatStringsSep " " dirs;
  
  # Generate directory strings for scripts
  psDirs = dirsToString psConfig.codeDirs;
  hsDirs = dirsToString hsConfig.codeDirs;
  
  # Get frontend and backend directories
  frontendDir = builtins.match "(.*)/.*" (builtins.elemAt psConfig.codeDirs 0);
  frontendPath = if frontendDir == null then "./frontend" else builtins.elemAt frontendDir 0;
  
  backendDir = builtins.match "(.*)/.*" (builtins.elemAt hsConfig.codeDirs 0);
  backendPath = if backendDir == null then "./backend" else builtins.elemAt backendDir 0;

  # Import modules
  postgresModule = import ./postgres-utils.nix {
    inherit pkgs name;
    # Pass database config to postgres module
    database = dbConfig;
  };

  frontendModule = import ./frontend.nix {
    inherit pkgs name;
    # Pass frontend config to frontend module
    frontend = {
      inherit (viteConfig) viteport settings;
      inherit (psConfig) codeDirs spagoFile;
    };
  };
  
  deployModule = import ./deploy.nix {
    inherit pkgs name;
  };

  # Import the dev scripts from the separate file
  devScripts = import ./devScripts.nix {
    inherit pkgs name lib backendPath frontendPath hsDirs psDirs hsConfig;
  };

  # VSCode extensions list
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
      name = "vscode-direnv";
      version = "1.0.0";
      sha256 = "sha256-+nLH+T9v6TQCqKZw6HPN/ZevQ65FVm2SAo2V9RecM3Y=";
    }
    {
      publisher = "nwolverson";
      name = "language-purescript";
      version = "0.2.9";
      sha256 = "sha256-2uOwCHvnlQQM8s8n7dtvIaMgpW8ROeoUraM02rncH9o=";
    }
    {
      publisher = "nwolverson";
      name = "ide-purescript";
      version = "0.26.6";
      sha256 = "sha256-72DRp+XLPlOowkRqyCWAeU/MNUr01m39IkCHCm5zpVc=";
    }
    {
      publisher = "hoovercj";
      name = "haskell-linter";
      version = "0.0.6";
      sha256 = "sha256-MjgqR547GC0tMnBJDMsiB60hJE9iqhKhzP6GLhcLZzk=";
    }
    {
      publisher = "justusadam";
      name = "language-haskell";
      version = "3.6.0";
      sha256 = "sha256-rZXRzPmu7IYmyRWANtpJp3wp0r/RwB7eGHEJa7hBvoQ=";
    }
  ];

  # Create VSCodium with extensions properly
  vscodiumWithExtensions = pkgs.vscode-with-extensions.override {
    vscode = pkgs.vscodium;
    vscodeExtensions = extensions;
  };

  # Define workspace utilities directly in this file
  workspaceModule = {
    code-workspace = pkgs.writeShellApplication {
      name = "code-workspace";
      runtimeInputs = with pkgs; [ vscodiumWithExtensions ];
      text = ''
        # Create the workspace file if it doesn't exist
        if [ ! -f "${name}.code-workspace" ]; then
          cat > ${name}.code-workspace <<EOF
        {
          "folders": [
            {
              "name": "PS_frontend",
              "path": "frontend"
            },
            {
              "name": "HS_backend",
              "path": "backend"
            },
            {
              "name": "nix",
              "path": "nix"
            },
            {
              "name": "Helpers",
              "path": "script"
            },
            {
              "name": "Root",
              "path": "./"
            }
          ],
          "settings": {
            "files.exclude": {
              "frontend": false,
              "backend": false,
              "nix": false
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
              "**/dist/**": true,
              "**/dist-newstyle/**": true,
              "**/.spago/**": true,
              "**/output/**": true,
              "**/.psci_modules/**": true
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
      name = "backup-project";
      runtimeInputs = with pkgs; [ rsync ];
      text = ''
        rsync -va --delete --exclude-from='.gitignore' --exclude='.git/' ~/workdir/${name}/ ~/plutus/workspace/scdWs/${name}/
        rsync -va ~/.local/share/${name}/backups/ ~/plutus/${name}DB/
      '';
    };
  };

  # Common buildInputs used in development shell
  commonBuildInputs = with pkgs; [
    # Front End tools
    esbuild
    nodejs_20
    nixpkgs-fmt
    purs
    purs-tidy
    purs-backend-es
    purescript-language-server
    spago-unstable

    # Back End tools
    cabal-install
    ghc
    haskellPackages.fourmolu
    haskell-language-server
    hlint
    zlib
    pgcli
    pkg-config
    openssl.dev
    libiconv
    openssl
    
    # VSCode/VSCodium
    vscodiumWithExtensions
    
    # PostgreSQL utilities
    postgresModule.pg-start
    postgresModule.pg-connect
    postgresModule.pg-stop
    postgresModule.pg-cleanup
    postgresModule.pg-backup    
    postgresModule.pg-restore    
    postgresModule.pg-rotate-credentials  
    postgresModule.pg-create-schema      
    postgresModule.pg-stats              
    
    # Database tools
    pgadmin4

    # DevShell tools
    toilet # colorful text
    rsync
    tmux
    workspaceModule.backup-project
    devScripts.compile-manifest
    devScripts.compile-archive

    # Frontend tools
    frontendModule.vite
    frontendModule.vite-cleanup
    frontendModule.spago-watch
    frontendModule.concurrent
    frontendModule.dev

    # Workspace and deployment tools
    workspaceModule.code-workspace
    deployModule.deploy
    deployModule.withdraw
    
    # Additional tools specifically for the scripts
    coreutils
    bash
    gnused
    gnugrep
    jq
    perl
    findutils
  ];

  # Native build inputs
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
  ];

  # Darwin-specific inputs
  darwinInputs = if (system == "aarch64-darwin" || system == "x86_64-darwin") then
    (with pkgs.darwin.apple_sdk.frameworks; [
      Cocoa
      CoreServices
    ])
  else [];

  # Return a shell configuration
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
      
      # Create script directory for compile-with-manifest if it doesn't exist
      mkdir -p "$(pwd)/script/concat_archive/output" "$(pwd)/script/concat_archive/archive" "$(pwd)/script/concat_archive/.hashes"
      
      # Set up VSCode settings directory if needed
      mkdir -p "$(pwd)/.vscode"
      
      # Add custom settings for hardware acceleration
      cat > "$(pwd)/.vscode/argv.json" <<EOF
      {
        "disable-hardware-acceleration": true,
        "enable-crash-reporter": true,
        // Unique id used for correlating crash reports sent from this instance.
        // Do not edit this value.
        "crash-reporter-id": "4e77d7bd-2f26-4723-9757-4f86cefd7010",
        "password-store": "gnome"
      }
      EOF
      
      echo "Welcome to the ${lib.toSentenceCase name} development environment!"

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
      echo "  Frontend:"
      echo "    vite                   - Start Vite development server"
      echo "    vite-cleanup           - Clean frontend build artifacts"
      echo "    spago-watch            - Watch PureScript files for changes"
      echo "    concurrent             - Run concurrent development tasks"
      echo ""
      echo "  Development:"
      echo "    dev                    - Start all development services in tmux"
      echo "    code-workspace         - Open VSCodium workspace that handles a PS-HS project"
      echo "    backup-project         - Backup project files"
      echo "    compile-manifest       - Compile and concatenate project files (formerly cwm)"
      echo "    compile-archive        - Compile and archive project files"
      echo ""
      echo "  Deployment:"
      echo "    deploy                 - Deploy to server"
      echo "    withdraw               - Withdraw deployment"
      echo ""
      echo ""
      toilet ${lib.toSentenceCase name} -t --metal
    '';
  };

in {
  inherit devShell;
  inherit workspaceModule;
}