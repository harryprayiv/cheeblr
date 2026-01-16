{
  description = "cheeblr";

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    iogx.url = "github:input-output-hk/iogx";

    iohkNix.url = "github:input-output-hk/iohk-nix";

    hackage = {
      url = "github:input-output-hk/hackage.nix";
      flake = false;
    };

    CHaP = {
      url = "github:IntersectMBO/cardano-haskell-packages?rev=4a6ecceb08b7980b0368907537a47215cae2e61f";
      flake = false;
    };

    purescript-overlay.url = "github:harryprayiv/purescript-overlay";

    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, iohkNix, CHaP, iogx, haskellNix, purescript-overlay, ... }:
    {
      nixosModules = {
        postgresql = import ./nix/postgresql-service.nix;
        default = { ... }: {
          imports = [ self.nixosModules.postgresql ];
        };
      };
    } // flake-utils.lib.eachSystem ["x86_64-linux" "x86_64-darwin" "aarch64-darwin"] (system: let

      name = "cheeblr";
      lib = nixpkgs.lib;

      # Use haskell.nix's pinned nixpkgs with all necessary overlays
      pkgs = import haskellNix.inputs.nixpkgs {
        inherit system;
        inherit (haskellNix) config;
        overlays = [
          haskellNix.overlay
          iohkNix.overlays.crypto
          purescript-overlay.overlays.default
          (final: prev: {
            cheeblrProject = final.haskell-nix.project' {
              src = ./backend;
              compiler-nix-name = "ghc910";
              
              inputMap = {
                "https://chap.intersectmbo.org/" = CHaP;
              };
              
              shell = {
                tools = {
                  cabal = {};
                  haskell-language-server = {};
                  hlint = {};
                  fourmolu = {};
                };
                
                buildInputs = with final; [
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
          })
        ];
      };

      # Get the haskell.nix project flake
      backendFlake = pkgs.cheeblrProject.flake {};

      # Import your existing devshell module
      devshellModule = import ./nix/devShell.nix {
        inherit pkgs name lib system;
      };

    in {
      legacyPackages = pkgs;

      # Expose backend packages from haskell.nix
      packages = backendFlake.packages // {
        default = backendFlake.packages."cheeblr-backend:exe:cheeblr-backend";
        backend = backendFlake.packages."cheeblr-backend:exe:cheeblr-backend";
      };

      # Combine your devshell with haskell.nix's shell
      devShells.default = pkgs.mkShell {
        inherit name;
        
        # Pull in haskell.nix's shell (gives us properly configured cabal, HLS, etc.)
        inputsFrom = [
          backendFlake.devShells.default
          devshellModule.devShell
        ];
        
        # Your existing shellHook runs via devshellModule.devShell
      };

      devShell = self.devShells.${system}.default;
    });

  nixConfig = {
    extra-experimental-features = ["nix-command flakes" "ca-derivations"];
    allow-import-from-derivation = "true";
    extra-substituters = [
      "https://cache.iog.io"
      "https://cache.nixos.org"
      "https://hercules-ci.cachix.org"
    ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
    ];
  };
}