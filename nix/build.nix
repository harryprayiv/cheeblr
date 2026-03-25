# nix/build.nix
{ inputs }:

let
  inherit (inputs) nixpkgs flake-utils haskellNix iohkNix CHaP hackage
                   purescript-overlay purs-nix sops-nix nix2container;

  appConfig = import ./config.nix { };
  name      = appConfig.name;

  nixosModules = {
    postgresql = import ./services/postgresql-service.nix;
    default = { ... }: {
      imports = [ nixosModules.postgresql ];
    };
  };

  mkSystemOutputs = system:
    let
      lib = nixpkgs.lib;

      pkgs = import haskellNix.inputs.nixpkgs {
        inherit system;
        inherit (haskellNix) config;
        overlays = [
          haskellNix.overlay
          iohkNix.overlays.crypto
          purescript-overlay.overlays.default
        ];
      };

      # nix2container.packages.${system}.nix2container.{ buildImage, buildLayer, ... }
      n2cPkgs = nix2container.packages.${system}.nix2container;

      # ── Haskell ───────────────────────────────────────────────────────────
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

      # ── PureScript ───────────────────────────────────────────────────────
      purs-nix-instance = purs-nix { inherit system; };

      inherit (inputs.ps-tools.legacyPackages.${system}.for-0_15)
        purescript purs-tidy purescript-language-server;

      ps-pkgs = purs-nix-instance.ps-pkgs;

      psDependencies = import ./purs-nix.nix {
        inherit inputs purs-nix-instance ps-pkgs;
      };

      frontendProject = purs-nix-instance.build {
        name = "${name}-frontend";
        src.path = ../frontend;
        info.dependencies = psDependencies;
      };

      ps = purs-nix-instance.purs {
        dir = ../frontend;
        dependencies = psDependencies;
        inherit purescript;
        nodejs = pkgs.nodejs_20;
      };

      # ── Containers ───────────────────────────────────────────────────────
      backendPackage =
        backendFlake.packages."${name}-backend:exe:${name}-backend";

      containersModule = import ./containers.nix {
        inherit pkgs lib name backendPackage
                purs-nix-instance psDependencies purescript;
        nix2containerPkgs = n2cPkgs;
        # frontendProject is intentionally NOT passed here.
        # purs-nix-instance.build produces a library dependency manifest,
        # not compiled JavaScript.  containers.nix will use purs-nix-instance
        # to compile from source, which is the correct path.
      };

      # ── Devshell ─────────────────────────────────────────────────────────
      devshellModule = import ./devshell.nix {
        inherit pkgs name lib system containersModule;
      };

    in rec {
      legacyPackages = pkgs;

      packages = backendFlake.packages // {
        default       = backendPackage;
        backend       = backendPackage;
        frontend      = frontendProject;

        # OCI images.  Not built by `nix develop`; build explicitly:
        #   nix build .#packages.aarch64-linux.backendImage
        #   nix build .#packages.aarch64-linux.frontendImage
        backendImage  = containersModule.backendImage;
        frontendImage = containersModule.frontendImage;

        # nix2container passthru packages -- exposed so the lazy devshell
        # scripts can call `nix run .#packages.${s}.backendImage-copyToPodman`
        # etc. without needing to know the store path at eval time.
        "backendImage-copyToPodman"    = containersModule.backendImage.copyToPodman;
        "backendImage-copyToRegistry"  = containersModule.backendImage.copyToRegistry;
        "frontendImage-copyToPodman"   = containersModule.frontendImage.copyToPodman;
        "frontendImage-copyToRegistry" = containersModule.frontendImage.copyToRegistry;
      };

      devShells =
        let
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
            ] ++ containersModule.tools;
          };
          ciShell = import ./ci-shell.nix {
            inherit pkgs lib name system;
            inherit backendFlake purs-nix-instance purescript psDependencies;
          };
        in {
          default = shell;
          ci      = ciShell;
        };

      devShell = devShells.default;

      nixosModuleContainers = containersModule.nixosModule;
    };

in {
  inherit nixosModules;
  perSystem = mkSystemOutputs;

  systems = [
    "x86_64-linux"
    "aarch64-linux"   # Raspberry Pi 5
    "x86_64-darwin"
    "aarch64-darwin"
  ];
}
