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

    # purs-nix for PureScript
    purs-nix.url = "github:purs-nix/purs-nix";
    ps-tools.follows = "purs-nix/ps-tools";

    # Git packages for PureScript
    purescript-money = {
      url = "github:harryprayiv/purescript-money/338d7cce83af935f078839d88b2ffc72de432b73";
      flake = false;
    };

    purescript-linear-algebra = {
      url = "github:harryprayiv/purescript-linear-algebra/d7b640afab25a3abdc6b9e8d55a2f9389d6a40eb";
      flake = false;
    };

    purescript-vector = {
      url = "github:harryprayiv/purescript-vector/086268b7e60b570b2be7c104159e021259de98df";
      flake = false;
    };

    purescript-hyrule = {
      url = "github:mikesol/purescript-hyrule/a2a32e02a0d8518d906ec5fb3192261f63667338";
      flake = false;
    };

    purescript-deku = {
      url = "github:mikesol/purescript-deku/276f48adde3d9354f61917f7e9ae2ae7b43df6b2";
      flake = false;
    };

    # deku-css has a different ref
    purescript-deku-css = {
      url = "github:mikesol/purescript-deku/06a06a2908b2a400a0ab9224c8128aa5988e674d";
      flake = false;
    };

    purescript-dodo-printer = {
      url = "github:natefaubion/purescript-dodo-printer";
      flake = false;
    };

    purescript-tidy = {
      url = "github:natefaubion/purescript-tidy/v0.10.0";
      flake = false;
    };

    purescript-tidy-codegen = {
      url = "github:natefaubion/purescript-tidy-codegen";
      flake = false;
    };

    purescript-overlay.url = "github:harryprayiv/purescript-overlay";

    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, iohkNix, CHaP, iogx, haskellNix, purescript-overlay, purs-nix, ... }@inputs:
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
        ];
      };

      # === Haskell backend via haskell.nix ===
      haskellProject = pkgs.haskell-nix.project' {
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

      backendFlake = haskellProject.flake {};

      # === PureScript frontend via purs-nix ===
      purs-nix-instance = purs-nix { inherit system; };
      
      inherit (inputs.ps-tools.legacyPackages.${system}.for-0_15) 
        purescript purs-tidy purescript-language-server;

      ps-pkgs = purs-nix-instance.ps-pkgs;

      # Build git packages
      money = purs-nix-instance.build {
        name = "money";
        src.path = inputs.purescript-money;
        info.dependencies = with ps-pkgs; [
          console effect foldable-traversable integers lists newtype prelude rationals
        ];
      };

      linear-algebra = purs-nix-instance.build {
        name = "linear-algebra";
        src.path = inputs.purescript-linear-algebra;
        info.dependencies = with ps-pkgs; [
          arrays console effect numbers prelude tuples
        ];
      };

      vector = purs-nix-instance.build {
        name = "vector";
        src.path = inputs.purescript-vector;
        info.dependencies = with ps-pkgs; [
          arrays effect either exceptions foldable-traversable numbers prelude
        ];
      };

      hyrule = purs-nix-instance.build {
        name = "hyrule";
        src.path = inputs.purescript-hyrule;
        info.dependencies = with ps-pkgs; [
          avar effect filterable free js-timers random web-html unsafe-reference web-uievents
        ];
      };

      deku-core = purs-nix-instance.build {
        name = "deku-core";
        src.path = inputs.purescript-deku + "/deku-core";
        info.dependencies = with ps-pkgs; [
          untagged-union
        ] ++ [ hyrule ];
      };

      deku-dom = purs-nix-instance.build {
        name = "deku-dom";
        src.path = inputs.purescript-deku + "/deku-dom";
        info.dependencies = with ps-pkgs; [
          web-touchevents web-pointerevents untagged-union
        ] ++ [ hyrule ];
      };

      deku-css = purs-nix-instance.build {
        name = "deku-css";
        src.path = inputs.purescript-deku-css + "/deku-css";
        info.dependencies = with ps-pkgs; [
          css
        ] ++ [ deku-core hyrule ];
      };

      dodo-printer = purs-nix-instance.build {
        name = "dodo-printer";
        src.path = inputs.purescript-dodo-printer;
        info.dependencies = with ps-pkgs; [
          ansi arrays avar console control effect either exceptions
          foldable-traversable integers lists maybe minibench newtype
          node-buffer node-child-process node-fs node-os node-path
          node-process node-streams parallel partial prelude safe-coerce
          strings tuples
        ];
      };

      tidy = purs-nix-instance.build {
        name = "tidy";
        src.path = inputs.purescript-tidy;
        info.dependencies = with ps-pkgs; [
          arrays foldable-traversable lists maybe ordered-collections
          partial prelude language-cst-parser strings tuples
        ] ++ [ dodo-printer ];
      };

      tidy-codegen = purs-nix-instance.build {
        name = "tidy-codegen";
        src.path = inputs.purescript-tidy-codegen;
        info.dependencies = with ps-pkgs; [
          aff ansi arrays avar bifunctors console control effect either
          enums exceptions filterable foldable-traversable free identity
          integers language-cst-parser lazy lists maybe newtype node-buffer
          node-child-process node-fs node-path node-process node-streams
          ordered-collections parallel partial posix-types prelude record
          safe-coerce st strings transformers tuples type-equality unicode
        ] ++ [ dodo-printer tidy ];
      };

      # All dependencies for the frontend
      psDependencies = with ps-pkgs; [
        # Registry packages
        aff
        aff-promise
        affjax
        affjax-web
        arraybuffer
        arraybuffer-types
        arrays
        console
        css
        datetime
        debug
        effect
        either
        encoding
        enums
        fetch
        fetch-yoga-json
        lists
        maybe
        newtype
        node-fs
        numbers
        parsing
        prelude
        routing
        routing-duplex
        stringutils
        transformers
        tuples
        uuid
        validation
        web-html
        yoga-json
      ] ++ [
        # Git packages
        money
        linear-algebra
        vector
        deku-core
        deku-dom
        deku-css
      ];

      frontendProject = purs-nix-instance.build {
        name = "cheeblr-frontend";
        src.path = ./frontend;
        info.dependencies = psDependencies;
      };

      ps = purs-nix-instance.purs {
        dir = ./frontend;
        dependencies = psDependencies;
        inherit purescript;
        nodejs = pkgs.nodejs_20;
      };

      # Import your existing devshell module
      devshellModule = import ./nix/devShell.nix {
        inherit pkgs name lib system;
      };

    in {
      legacyPackages = pkgs;

      packages = backendFlake.packages // {
        default = backendFlake.packages."cheeblr-backend:exe:cheeblr-backend";
        backend = backendFlake.packages."cheeblr-backend:exe:cheeblr-backend";
        frontend = frontendProject;
      };

      devShells.default = pkgs.mkShell {
        inherit name;
        
        inputsFrom = [
          backendFlake.devShells.default
          devshellModule.devShell
        ];

        buildInputs = [
          (ps.command {})
          purescript-language-server
          purs-tidy
        ];
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