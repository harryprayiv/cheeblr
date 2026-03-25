{
  description = "cheeblr";

  inputs = {

    # Haskell infrastructure
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

    # PureScript ecosystem
    purs-nix.url = "github:purs-nix/purs-nix";
    ps-tools.follows = "purs-nix/ps-tools";
    purescript-overlay.url = "github:harryprayiv/purescript-overlay";

    # PureScript packages
    purescript-money = {
      url = "github:rowtype-yoga/purescript-money/338d7cce83af935f078839d88b2ffc72de432b73";
      flake = false;
    };
    purescript-linear-algebra = {
      url = "github:rowtype-yoga/purescript-linear-algebra/d7b640afab25a3abdc6b9e8d55a2f9389d6a40eb";
      flake = false;
    };
    purescript-vector = {
      url = "github:mgmeier/purescript-vector/31f9867a7155852bb6ddada1818adf03113a250e";
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

    # Nix Utils
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    sops-nix.url = "github:Mic92/sops-nix";
    
    sops-nix.inputs.nixpkgs.follows = "nixpkgs"; 
 
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";

  };

  outputs = inputs@{ self, flake-utils, ... }:
    let
      build = import ./nix/build.nix { inherit inputs; };
    in
    {
      nixosModules = build.nixosModules;
    }
    // flake-utils.lib.eachSystem build.systems (system: build.perSystem system);

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