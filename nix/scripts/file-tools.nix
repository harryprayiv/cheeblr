{ pkgs, name, lib, backendPath ? null, frontendPath ? null, hsDirs ? null, psDirs ? null, hsConfig ? null }:

let
  # Import app config
  appConfig = import ./app-config.nix { inherit name; };
  
  # Use values from appConfig or override with provided parameters
  effectiveBackendPath = if backendPath != null then backendPath else "backend";
  effectiveFrontendPath = if frontendPath != null then frontendPath else "frontend";
  
  # Extract code directory paths from appConfig, stripping the leading "./", or use provided values
  effectiveHsDirs = if hsDirs != null then hsDirs else 
    map (path: builtins.replaceStrings ["./backend/"] [""] path) appConfig.haskell.codeDirs;
  
  effectivePsDirs = if psDirs != null then psDirs else 
    map (path: builtins.replaceStrings ["./frontend/"] [""] path) appConfig.purescript.codeDirs;
  
  effectiveHsConfig = if hsConfig != null then hsConfig else {};
  
  # Import the manifest generation module with the effective config
  manifestModule = import ./manifest.nix { 
    inherit pkgs lib; 
    config = {
      backendPath = effectiveBackendPath;
      frontendPath = effectiveFrontendPath;
      hsDirs = effectiveHsDirs;
      psDirs = effectivePsDirs;
      hsConfig = effectiveHsConfig;
    };
  };
  
  # Import the devScripts module which has the actual implementation
  devScriptsModule = import ./devScripts.nix {
    inherit pkgs name lib;
    backendPath = effectiveBackendPath;
    frontendPath = effectiveFrontendPath;
    hsDirs = effectiveHsDirs;
    psDirs = effectivePsDirs;
    hsConfig = effectiveHsConfig;
  };

in {
  # Export tools from devScripts module
  inherit (devScriptsModule) compile-manifest compile-archive run-codegen;
  
  # Export the manifest generator from the manifest module
  generate-manifest = manifestModule.generateScript;
  
  # Define a list of all the tools for use in devShell
  tools = [
    devScriptsModule.compile-manifest
    devScriptsModule.compile-archive
    devScriptsModule.run-codegen
    manifestModule.generateScript
  ];
  
  # Export for debugging/development
  debug = manifestModule.debug;
  
  # Expose effective config for inspection
  config = {
    backendPath = effectiveBackendPath;
    frontendPath = effectiveFrontendPath;
    hsDirs = effectiveHsDirs;
    psDirs = effectivePsDirs;
  };
}