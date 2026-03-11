# Minimal devShell for CI.  Contains only what the three test commands
# (test-unit, test-integration, test-integration-tls) actually invoke at
# runtime.  Nothing GUI, nothing deployment-related, nothing sops/secrets.
#
# Usage in CI:
#   nix develop .#ci --command test-unit
#   nix develop .#ci --command test-integration
#   nix develop .#ci --command test-integration-tls

{ pkgs
, lib ? pkgs.lib
, name
, backendFlake
, purs-nix-instance
, purescript
, psDependencies
, system ? builtins.currentSystem
}:

let
  appConfig   = import ./config.nix { inherit name; };
  backendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head appConfig.haskell.codeDirs));

  # ── test suite scripts (test-unit / test-integration / test-integration-tls) ──
  testSuiteModule = import ./test-suite.nix { inherit pkgs name; };

  # ── tls-setup (required by test-integration-tls) ────────────────────────────
  tlsModule = import ./tls.nix { inherit pkgs name; };

  # ── PureScript toolchain ─────────────────────────────────────────────────────
  ps = purs-nix-instance.purs {
    dir          = ../${backendPath}/../frontend; # resolves to ./frontend
    dependencies = psDependencies;
    inherit purescript;
    nodejs = pkgs.nodejs_20;
  };

in pkgs.mkShell {
  name = "${name}-ci";

  # Pull in cabal + GHC from the Haskell project shell, but nothing else from
  # the full dev shell (no HLS, no fourmolu, no GUI packages).
  inputsFrom = [ backendFlake.devShells.default ];

  buildInputs = [
    # ── test entry-points ─────────────────────────────────────────
    testSuiteModule.test-unit
    testSuiteModule.test-integration
    testSuiteModule.test-integration-tls

    # ── TLS cert generation (test-integration-tls calls tls-setup) ─
    tlsModule.tls-setup
    pkgs.mkcert

    # ── PureScript (spago test / spago build) ─────────────────────
    (ps.command { })
    purescript
    pkgs.spago-unstable
    pkgs.nodejs_20

    # ── PostgreSQL CLI tools (initdb / pg_ctl / psql / pg_isready) ─
    pkgs.postgresql

    # ── HTTP / TLS utilities used inside test scripts ──────────────
    pkgs.curl
    pkgs.openssl

    # ── process / port helpers used inside test scripts ───────────
    pkgs.lsof
    pkgs.gettext      # envsubst (certDir expansion)

    # ── standard shell utilities (paranoia — usually available anyway)
    pkgs.coreutils
    pkgs.bash
    pkgs.gnused
    pkgs.gnugrep
    pkgs.jq
  ];

  # Minimal env vars the test scripts depend on.
  # PGDATA is intentionally left unset here; test-integration sets it to a
  # per-run temp directory internally ($TMPDIR/cheeblr-test-$$).
  shellHook = ''
    export PGPORT="${toString appConfig.database.port}"
    export PGUSER="$(whoami)"
    export PGDATABASE="${appConfig.database.name}"
    export PKG_CONFIG_PATH="${pkgs.postgresql.lib}/lib/pkgconfig:$PKG_CONFIG_PATH"
  '';
}
