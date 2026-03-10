{ inputs }:

let
  inherit (inputs) nixpkgs flake-utils haskellNix iohkNix CHaP hackage purescript-overlay purs-nix sops-nix;

  # Project name - single source of truth via config.nix
  appConfig = import ./config.nix {};
  name      = appConfig.name;

  # NixOS modules (system-independent)
  nixosModules = {
    postgresql = import ./services/postgresql-service.nix;
    default = { ... }: {
      imports = [ nixosModules.postgresql ];
    };
  };


  # Per-system build configuration
  mkSystemOutputs = system:
    let
      lib = nixpkgs.lib;

      # Base pkgs with haskell.nix and purescript overlays
      pkgs = import haskellNix.inputs.nixpkgs {
        inherit system;
        inherit (haskellNix) config;
        overlays = [
          haskellNix.overlay
          iohkNix.overlays.crypto
          purescript-overlay.overlays.default
        ];
      };

      # Haskell backend project
      haskellProject = pkgs.haskell-nix.project' {
        src = ../backend;
        compiler-nix-name = "ghc910";

        inputMap = {
          "https://chap.intersectmbo.org/" = CHaP;
          "https://hackage.haskell.org/"   = hackage;
        };

        shell = {
          tools = {
            cabal = { };
            haskell-language-server = { };
            hlint = { };
            fourmolu = { };
          };

          buildInputs = with pkgs; [
            pkg-config
            postgresql.lib
            openssl.dev
            zlib
          ];
        };

        modules = [{
          packages.postgresql-libpq.flags.use-pkg-config = true;
          packages.postgresql-simple.flags.use-pkg-config = true;
        }];
      };

      backendFlake = haskellProject.flake { };

      # PureScript frontend configuration
      purs-nix-instance = purs-nix { inherit system; };

      inherit (inputs.ps-tools.legacyPackages.${system}.for-0_15)
        purescript purs-tidy purescript-language-server;

      ps-pkgs = purs-nix-instance.ps-pkgs;

      # Custom PureScript packages from flake inputs
      psDependencies = import ./purs-nix.nix {
        inherit inputs purs-nix-instance ps-pkgs;
      };

      # Use the combined source (with generated files) for the main build
      frontendProject = purs-nix-instance.build {
        name = "${name}-frontend";
        src.path = ../frontend;
        info.dependencies = psDependencies;
      };

      # Also update ps to use combined source for dev
      ps = purs-nix-instance.purs {
        dir = ../frontend;
        dependencies = psDependencies;
        inherit purescript;
        nodejs = pkgs.nodejs_20;
      };

      # DevShell configuration
      devshellModule = import ./devshell.nix {
        inherit pkgs name lib system;
      };

    in rec {
      legacyPackages = pkgs;

      packages = backendFlake.packages // {
        default  = backendFlake.packages."${name}-backend:exe:${name}-backend";
        backend  = backendFlake.packages."${name}-backend:exe:${name}-backend";
        frontend = frontendProject;
      };

      devShells = let
        shell = pkgs.mkShell {
          inherit name;

          inputsFrom = [
            backendFlake.devShells.default
            devshellModule.devShell
          ];

          buildInputs = [
            (ps.command { })
            purescript-language-server
            purs-tidy
          ];
        };
      in {
        default = shell;
      };


      # Legacy attribute for older nix versions
      devShell = devShells.default;
    };

in {
  # Export nixosModules at top level
  inherit nixosModules;

  # Generate per-system outputs
  perSystem = mkSystemOutputs;

  # Supported systems
  systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
}
