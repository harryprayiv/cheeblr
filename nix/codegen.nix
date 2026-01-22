{ pkgs, purs-nix-instance, psDependencies, frontendSrc }:

let
  # Build the PureScript project with all dependencies including tidy-codegen
  codegenBuild = purs-nix-instance.purs {
    dir = frontendSrc;
    dependencies = psDependencies;
  };

  # Generate types at build time by running the Codegen.Run module
  generatedSources = pkgs.runCommand "generated-purescript-types" {
    buildInputs = [
      pkgs.nodejs_20
      (codegenBuild.command { })
    ];
    src = frontendSrc;
  } ''
    set -e
    
    # Copy source to writable directory
    cp -r $src work
    chmod -R +w work
    cd work

    echo "=== Compiling PureScript project ==="
    purs-nix compile
    
    # Create output directories for generated code
    mkdir -p $out/src/Generated/Types
    mkdir -p $out/src/Generated/Config
    mkdir -p $out/src/Generated/Utils

    echo "=== Running codegen ==="
    # Run the codegen main module
    if [ -f "output/Codegen.Run/index.js" ]; then
      node -e "require('./output/Codegen.Run/index.js').main()"
      echo "Codegen completed successfully"
    else
      echo "Warning: Codegen.Run module not found, skipping code generation"
    fi

    # Copy generated files to output
    if [ -d "src/Generated" ]; then
      echo "=== Copying generated files ==="
      cp -r src/Generated/* $out/src/Generated/ 2>/dev/null || true
      find $out/src/Generated -name "*.purs" -type f | head -20
    fi

    # Create manifest of generated files
    find $out -name "*.purs" > $out/generated-manifest.txt
    echo "Generated $(wc -l < $out/generated-manifest.txt) PureScript files"
  '';

  # Combine frontend source with generated code for the final build
  frontendWithGenerated = pkgs.runCommand "frontend-with-generated" { } ''
    mkdir -p $out

    # Copy original frontend source
    cp -r ${frontendSrc}/* $out/
    chmod -R +w $out

    # Overlay generated files
    if [ -d "${generatedSources}/src/Generated" ]; then
      mkdir -p $out/src/Generated
      cp -r ${generatedSources}/src/Generated/* $out/src/Generated/
      echo "Merged generated code into frontend source"
    fi
  '';

in {
  inherit generatedSources frontendWithGenerated;
  
  # Export the command for development use
  codegenCommand = codegenBuild.command { };
}
