{ pkgs, name, lib, backendPath ? null, frontendPath ? null, hsDirs ? null, psDirs ? null, hsTestDirs ? [], psTestDirs ? [], hsConfig ? null }:

let

  appConfig = import ./app-config.nix { inherit name; };


  effectiveBackendPath = if backendPath != null then backendPath else "backend";
  effectiveFrontendPath = if frontendPath != null then frontendPath else "frontend";


  effectiveHsDirs = if hsDirs != null then hsDirs else
    map (path: builtins.replaceStrings ["./backend/"] [""] path) appConfig.haskell.codeDirs;

  effectivePsDirs = if psDirs != null then psDirs else
    map (path: builtins.replaceStrings ["./frontend/"] [""] path) appConfig.purescript.codeDirs;

  # Test dirs: fall back to config.tests if not provided
  effectiveHsTestDirs = if hsTestDirs != [] then hsTestDirs else
    let testPath = appConfig.haskell.tests or null;
    in if testPath != null
       then [ (builtins.replaceStrings ["./backend/"] [""] testPath) ]
       else [];

  effectivePsTestDirs = if psTestDirs != [] then psTestDirs else
    let testPath = appConfig.purescript.tests or null;
    in if testPath != null
       then [ (builtins.replaceStrings ["./frontend/"] [""] testPath) ]
       else [];

  effectiveHsConfig = if hsConfig != null then hsConfig else { };


  manifestModule = import ./manifest.nix {
    inherit pkgs lib;
    config = {
      backendPath = effectiveBackendPath;
      frontendPath = effectiveFrontendPath;
      hsDirs = effectiveHsDirs;
      psDirs = effectivePsDirs;
      hsTestDirs = effectiveHsTestDirs;
      psTestDirs = effectivePsTestDirs;
      hsConfig = effectiveHsConfig;
    };
  };


  devScriptsModule = import ./devScripts.nix {
    inherit pkgs name lib;
    backendPath = effectiveBackendPath;
    frontendPath = effectiveFrontendPath;
    hsDirs = effectiveHsDirs;
    psDirs = effectivePsDirs;
    hsTestDirs = effectiveHsTestDirs;
    psTestDirs = effectivePsTestDirs;
    hsConfig = effectiveHsConfig;
  };

  tuiModule = import ./manifest-tui.nix {
    inherit pkgs lib name;
    backendPath  = effectiveBackendPath;
    frontendPath = effectiveFrontendPath;
    hsDirs       = effectiveHsDirs;
    psDirs       = effectivePsDirs;
    hsTestDirs   = effectiveHsTestDirs;
    psTestDirs   = effectivePsTestDirs;
  };

in {

  inherit (devScriptsModule) compile-manifest compile-archive run-codegen llm-context;

  manifest-tui = tuiModule.manifest-tui;

  generate-manifest = manifestModule.generateScript;

  tools = [
    devScriptsModule.compile-manifest
    devScriptsModule.compile-archive
    devScriptsModule.run-codegen
    devScriptsModule.llm-context
    tuiModule.manifest-tui
    manifestModule.generateScript
  ];

  debug = manifestModule.debug;

  config = {
    backendPath = effectiveBackendPath;
    frontendPath = effectiveFrontendPath;
    hsDirs = effectiveHsDirs;
    psDirs = effectivePsDirs;
    hsTestDirs = effectiveHsTestDirs;
    psTestDirs = effectivePsTestDirs;
  };
}