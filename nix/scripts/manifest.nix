{ lib, pkgs, config ? {} }:

let
  # Default configuration
  defaultConfig = {
    projectRoot = ".";
    backendPath = "backend";
    frontendPath = "frontend";
    hsDirs = [ "src" "app" "test" ];
    psDirs = [ "src" "test" ];
    
    # Explicitly track generated code directory
    generatedDir = "src/Generated";

    hsConfig = {
      cabalFile = null;
      extensions = [ ".hs" ];
    };
    psConfig = {
      spagoFile = null;
      extensions = [ ".purs" ];
    };
    nixConfig = {
      extensions = [ ".nix" ];
      dirs = [ "." "nix" ];
    };

    excludePatterns = [
      ".spago"
      "node_modules"
      "dist"
      "dist-newstyle"
      "output"
      ".psci_modules"
    ];
  };

  # Merge default config with provided config
  cfg = lib.recursiveUpdate defaultConfig config;
  
  # Build exclude patterns for find command
  excludePatternStr = lib.concatMapStringsSep "\\|" (p: p) cfg.excludePatterns;

  # Generate the manifest script
  generateManifestScript = pkgs.writeShellScriptBin "generate-manifest" ''
    #!/usr/bin/env bash
    set -euo pipefail

    PROJECT_ROOT="$(pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/script"
    MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
    mkdir -p "$SCRIPT_DIR"

    echo "Generating manifest..."

    # Define base directories from configuration
    BACKEND_PATH="${cfg.backendPath}"
    FRONTEND_PATH="${cfg.frontendPath}"
    GENERATED_DIR="${cfg.generatedDir}"
    
    # Define Haskell directories
    HASKELL_DIRS=()
    for dir in ${lib.concatStringsSep " " cfg.hsDirs}; do
      HASKELL_DIRS+=("$PROJECT_ROOT/$BACKEND_PATH/$dir")
    done

    # Define PureScript directories
    PURESCRIPT_DIRS=()
    for dir in ${lib.concatStringsSep " " cfg.psDirs}; do
      PURESCRIPT_DIRS+=("$PROJECT_ROOT/$FRONTEND_PATH/$dir")
    done

    # Find Haskell files
    echo "Finding Haskell files..."
    HS_FILES=()

    for dir in "''${HASKELL_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "Scanning $dir for Haskell files"
        while IFS= read -r file; do
          if [ -n "$file" ]; then
            rel_path="''${file#$PROJECT_ROOT/}"
            HS_FILES+=("$rel_path")
          fi
        done < <(find "$dir" -type f -name "*.hs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done

    # Find PureScript files - separate generated from hand-written
    echo "Finding PureScript files..."
    PS_FILES=()
    PS_GENERATED_FILES=()

    for dir in "''${PURESCRIPT_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "Scanning $dir for PureScript files"
        while IFS= read -r file; do
          if [ -n "$file" ]; then
            rel_path="''${file#$PROJECT_ROOT/}"
            # Separate generated files
            if [[ "$rel_path" == *"/Generated/"* ]] || [[ "$rel_path" == *"/$GENERATED_DIR/"* ]]; then
              PS_GENERATED_FILES+=("$rel_path")
            else
              PS_FILES+=("$rel_path")
            fi
          fi
        done < <(find "$dir" -type f -name "*.purs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done
    
    # Combine: generated files first, then regular files
    ALL_PS_FILES=("''${PS_GENERATED_FILES[@]}" "''${PS_FILES[@]}")

    # Find Nix files in project root and nix directory
    echo "Finding Nix files..."
    NIX_FILES=()

    # Find Nix files in project root
    if [ -d "$PROJECT_ROOT" ]; then
      while IFS= read -r file; do
        rel_path="''${file#$PROJECT_ROOT/}"
        if [ -f "$file" ] && [[ "$file" != *"/script/concat_archive/"* ]]; then
          NIX_FILES+=("$rel_path")
        fi
      done < <(find "$PROJECT_ROOT" -maxdepth 1 -type f -name "*.nix" 2>/dev/null | sort)
    fi

    # Find Nix files in nix directory
    if [ -d "$PROJECT_ROOT/nix" ]; then
      while IFS= read -r file; do
        rel_path="''${file#$PROJECT_ROOT/}"
        NIX_FILES+=("$rel_path")
      done < <(find "$PROJECT_ROOT/nix" -type f -name "*.nix" 2>/dev/null | sort)
    fi

    # Create manifest JSON
    echo "{" > $MANIFEST_FILE
    echo "  \"meta\": {" >> $MANIFEST_FILE
    echo "    \"generated\": \"$(date '+%s')\","  >> $MANIFEST_FILE
    echo "    \"humanTime\": \"$(date '+%Y-%m-%d %H:%M:%S')\","  >> $MANIFEST_FILE
    echo "    \"projectRoot\": \"$PROJECT_ROOT\","  >> $MANIFEST_FILE
    echo "    \"backendPath\": \"$BACKEND_PATH\","  >> $MANIFEST_FILE
    echo "    \"frontendPath\": \"$FRONTEND_PATH\""  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # Add Haskell files section
    echo "  \"haskell\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    if [ ''${#HS_FILES[@]} -gt 0 ]; then
      for i in "''${!HS_FILES[@]}"; do
        if [ $i -eq $((''${#HS_FILES[@]}-1)) ]; then
          echo "      \"''${HS_FILES[$i]}\""  >> $MANIFEST_FILE
        else
          echo "      \"''${HS_FILES[$i]}\","  >> $MANIFEST_FILE
        fi
      done
    fi
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#HS_FILES[@]},"  >> $MANIFEST_FILE
    echo "    \"timestamp\": \"$(date '+%s')\""  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # Add PureScript files section with generated tracking
    echo "  \"purescript\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    if [ ''${#ALL_PS_FILES[@]} -gt 0 ]; then
      for i in "''${!ALL_PS_FILES[@]}"; do
        if [ $i -eq $((''${#ALL_PS_FILES[@]}-1)) ]; then
          echo "      \"''${ALL_PS_FILES[$i]}\""  >> $MANIFEST_FILE
        else
          echo "      \"''${ALL_PS_FILES[$i]}\","  >> $MANIFEST_FILE
        fi
      done
    fi
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"generated\": ["  >> $MANIFEST_FILE
    if [ ''${#PS_GENERATED_FILES[@]} -gt 0 ]; then
      for i in "''${!PS_GENERATED_FILES[@]}"; do
        if [ $i -eq $((''${#PS_GENERATED_FILES[@]}-1)) ]; then
          echo "      \"''${PS_GENERATED_FILES[$i]}\""  >> $MANIFEST_FILE
        else
          echo "      \"''${PS_GENERATED_FILES[$i]}\","  >> $MANIFEST_FILE
        fi
      done
    fi
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#ALL_PS_FILES[@]},"  >> $MANIFEST_FILE
    echo "    \"generatedCount\": ''${#PS_GENERATED_FILES[@]},"  >> $MANIFEST_FILE
    echo "    \"timestamp\": \"$(date '+%s')\""  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # Add Nix files section
    echo "  \"nix\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    if [ ''${#NIX_FILES[@]} -gt 0 ]; then
      for i in "''${!NIX_FILES[@]}"; do
        if [ $i -eq $((''${#NIX_FILES[@]}-1)) ]; then
          echo "      \"''${NIX_FILES[$i]}\""  >> $MANIFEST_FILE
        else
          echo "      \"''${NIX_FILES[$i]}\","  >> $MANIFEST_FILE
        fi
      done
    fi
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#NIX_FILES[@]},"  >> $MANIFEST_FILE
    echo "    \"timestamp\": \"$(date '+%s')\""  >> $MANIFEST_FILE
    echo "  }"  >> $MANIFEST_FILE
    echo "}"  >> $MANIFEST_FILE

    # Format the manifest JSON
    ${pkgs.jq}/bin/jq . "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp" && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"

    # Create backup of manifest
    BACKUP_TIME=$(date '+%Y%m%d_%H%M%S')
    cp "$MANIFEST_FILE" "$MANIFEST_FILE.$BACKUP_TIME"

    echo "Manifest generated at: $MANIFEST_FILE"
    echo "Backup created at: $MANIFEST_FILE.$BACKUP_TIME"
    echo "Found ''${#HS_FILES[@]} Haskell, ''${#ALL_PS_FILES[@]} PureScript (''${#PS_GENERATED_FILES[@]} generated), ''${#NIX_FILES[@]} Nix files"
  '';

  # Manifest data structure
  manifestData = {
    meta = {
      projectRoot = cfg.projectRoot;
      backendPath = cfg.backendPath;
      frontendPath = cfg.frontendPath;
    };
    haskell.include = [];
    haskell.exclude = [];
    haskell.count = 0;
    purescript.include = [];
    purescript.exclude = [];
    purescript.generated = [];
    purescript.count = 0;
    purescript.generatedCount = 0;
    nix.include = [];
    nix.exclude = [];
    nix.count = 0;
  };

in {
  # Export the manifest data
  data = manifestData;

  # Export the manifest as JSON
  json = builtins.toJSON manifestData;

  # Export the manifest generation script
  generateScript = generateManifestScript;
  
  # Debug info
  debug = {
    config = cfg;
    excludePattern = excludePatternStr;
  };
}