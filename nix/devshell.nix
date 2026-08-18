{ pkgs, name, lib, system ? builtins.currentSystem

, containersModule ? null
, hellPkg
}:

let
  appConfig = import ./config.nix { inherit name; };

  psConfig       = appConfig.purescript;
  hsConfig       = appConfig.haskell;
  dbConfig       = appConfig.database;
  viteConfig     = appConfig.vite;
  licenseConfig  = appConfig.license;

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

  deployModule    = import ./deploy.nix               { inherit pkgs name; };
  tlsModule       = import ./tls.nix                  { inherit pkgs name; };
  testSuiteModule = import ./test-suite.nix           { inherit pkgs name; };
  sopsModule      = import ./sops-dev.nix             { inherit pkgs lib name; };
  bootstrapModule = import ./bootstrap-admin-tool.nix { inherit pkgs lib name; };
  ideModule       = import ./ide.nix                  { inherit pkgs lib name; };

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

  containerTools    = if containersModule != null then containersModule.tools else [];
  hasContainerTools = containersModule != null;

  containerHelpText = if hasContainerTools then ''
      echo "  OCI Containers (nix2container / podman):"
      echo "    container-run  [podman]         - run locally (native arch)"
      echo "    container-stop [podman]         - stop and remove"
      echo "    container-load [podman]         - load pre-built images"
      echo "    container-push-pi <registry>    - push aarch64 images to registry"
      echo "    container-k8s-manifests <reg>   - write Kubernetes / Talos YAML"
      echo ""
      echo "  Enable cross-compilation in your NixOS config:"
      echo "    boot.binfmt.emulatedSystems = [ \"aarch64-linux\" ];"
  '' else "";

  # The full command wall lives here, on demand. It does not fire on every
  # `cd` into the project via direnv.
  helpScript = pkgs.writeShellScriptBin "${name}-help" ''
    echo "Copyright (C) ${licenseConfig.years} ${licenseConfig.holder}. Licensed under the ${licenseConfig.name}."
    echo "This is free software with ABSOLUTELY NO WARRANTY; see LICENSE for terms."
    echo ""
    ${containerHelpText}
    echo "  Database:"
    echo "    pg-start               - Start PostgreSQL"
    echo "    pg-connect             - Connect to PostgreSQL"
    echo "    pg-stop                - Stop PostgreSQL"
    echo "    pg-backup / pg-restore - Backup / restore"
    echo "    pg-rotate-credentials  - Rotate password + update sops hint"
    echo "    pg-stats               - Database statistics"
    echo "    with-db <cmd>          - Run command with DB credentials in scope"
    echo ""
    echo "  Nix Deployment:"
    echo "    build-all              - build everything"
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
    echo "  Auth Bootstrap (run once after first pg-start):"
    echo "    bootstrap-admin         - Create admin user, store password in sops"
    echo "    admin-password-info     - Check whether admin_password is in sops"
    echo "    sops-get admin_password - Reveal stored admin password"
    echo ""
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
    echo "  IDE:"
    echo "    ${name}-ide-sync       - Rewrite .vscode/ from nix/ide.nix"
  '';

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
    hellPkg

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
    postgresModule.with-db
    pgadmin4
    gettext

    toilet rsync tmux

    ideModule.sync
    helpScript

    manifestModule.generateScript
    devScripts.compile-manifest
    devScripts.compile-archive
    devScripts.llm-context
    devScripts.manifest-tui

    testSuiteModule.test-unit
    testSuiteModule.test-integration
    testSuiteModule.test-integration-tls
    testSuiteModule.test-suite
    testSuiteModule.test-smoke

    coreutils bash gnused gnugrep jq perl findutils
  ] ++ containerTools ++ ideModule.tools;

  # No editor. No alacritty (deploy.nix references it by store path).
  # No direnv (direnv is what *enters* this shell; putting it inside is circular).
  nativeBuildInputs = with pkgs; [
    pkg-config postgresql postgresql.lib zlib openssl.dev libiconv openssl
    lsof tmux
  ];

  darwinInputs =
    if (system == "aarch64-darwin" || system == "x86_64-darwin") then
      (with pkgs.darwin.apple_sdk.frameworks; [ Cocoa CoreServices ])
    else [];

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
      export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/${name}.txt"

      mkdir -p "$(pwd)/script/concat_archive/output" \
               "$(pwd)/script/concat_archive/archive" \
               "$(pwd)/script/concat_archive/.hashes"

      ${name}-ide-sync

      ${sopsModule.loadSecretsHook}

      echo "${lib.toSentenceCase name} dev shell — '${name}-help' for commands."
    '';
  };

in {
  inherit devShell;
}