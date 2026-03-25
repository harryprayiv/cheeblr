{ inputs, purs-nix-instance, ps-pkgs }:

let
  build = purs-nix-instance.build;

  # Custom packages from flake inputs
  money = build {
    name = "money";
    src.path = inputs.purescript-money;
    info.dependencies = with ps-pkgs; [
      console effect foldable-traversable integers lists newtype prelude rationals
    ];
  };

  linear-algebra = build {
    name = "linear-algebra";
    src.path = inputs.purescript-linear-algebra;
    info.dependencies = with ps-pkgs; [
      arrays console effect numbers prelude tuples
    ];
  };

  vector = build {
    name = "vector";
    src.path = inputs.purescript-vector;
    info.dependencies = with ps-pkgs; [
      arrays effect either exceptions foldable-traversable numbers prelude
    ];
  };

  hyrule = build {
    name = "hyrule";
    src.path = inputs.purescript-hyrule;
    info.dependencies = with ps-pkgs; [
      avar effect filterable free js-timers random web-html unsafe-reference web-uievents
    ];
  };

  deku-core = build {
    name = "deku-core";
    src.path = inputs.purescript-deku + "/deku-core";
    info.dependencies = with ps-pkgs; [ untagged-union ] ++ [ hyrule ];
  };

  deku-dom = build {
    name = "deku-dom";
    src.path = inputs.purescript-deku + "/deku-dom";
    info.dependencies = with ps-pkgs; [ web-touchevents web-pointerevents untagged-union ] ++ [ hyrule ];
  };

  deku-css = build {
    name = "deku-css";
    src.path = inputs.purescript-deku-css + "/deku-css";
    info.dependencies = with ps-pkgs; [ css ] ++ [ deku-core hyrule ];
  };

  # Codegen dependencies - these are the key additions
  dodo-printer = build {
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

  tidy = build {
    name = "tidy";
    src.path = inputs.purescript-tidy;
    info.dependencies = with ps-pkgs; [
      arrays foldable-traversable lists maybe ordered-collections
      partial prelude language-cst-parser strings tuples
    ] ++ [ dodo-printer ];
  };

  tidy-codegen = build {
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

in with ps-pkgs; [
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
  node-path
  node-buffer
  now
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
  
  # Additional dependencies for codegen
  language-cst-parser
  ansi
  node-child-process
  node-process
  node-streams
  node-os
  ordered-collections
  lazy
  identity
  bifunctors
  free
  filterable
  parallel
  posix-types
  record
  safe-coerce
  st
  type-equality
  unicode
  minibench
  control
  exceptions
] ++ [
  money
  linear-algebra
  vector
  hyrule
  deku-core
  deku-dom
  deku-css
  
  dodo-printer
  tidy
  tidy-codegen
]
