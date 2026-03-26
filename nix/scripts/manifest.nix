{ lib, pkgs, config ? { } }:

let

  defaultConfig = {
    projectRoot = ".";
    backendPath = "backend";
    frontendPath = "frontend";
    hsDirs = [ "src" "app" ];
    psDirs = [ "src" ];
    hsTestDirs = [ "test" ];
    psTestDirs = [ "test" ];
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

  cfg = lib.recursiveUpdate defaultConfig config;

  excludePatternStr = lib.concatMapStringsSep "\\|" (p: p) cfg.excludePatterns;

  emitJsonArray = varName: ''
    if [ ''${#${varName}[@]} -gt 0 ]; then
      for i in "''${!${varName}[@]}"; do
        if [ $i -eq $(( ''${#${varName}[@]} - 1 )) ]; then
          echo "      \"''${${varName}[$i]}\""
        else
          echo "      \"''${${varName}[$i]}\","
        fi
      done
    fi
  '';

  generateManifestScript = pkgs.writeShellScriptBin "generate-manifest" ''
    set -euo pipefail

    PROJECT_ROOT="$(pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/script"
    MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
    mkdir -p "$SCRIPT_DIR"

    echo "Generating manifest..."

    BACKEND_PATH="${cfg.backendPath}"
    FRONTEND_PATH="${cfg.frontendPath}"
    GENERATED_DIR="${cfg.generatedDir}"

    HASKELL_DIRS=()
    for dir in ${lib.concatStringsSep " " cfg.hsDirs}; do
      HASKELL_DIRS+=("$PROJECT_ROOT/$BACKEND_PATH/$dir")
    done

    PURESCRIPT_DIRS=()
    for dir in ${lib.concatStringsSep " " cfg.psDirs}; do
      PURESCRIPT_DIRS+=("$PROJECT_ROOT/$FRONTEND_PATH/$dir")
    done

    HS_TEST_DIRS=()
    ${if cfg.hsTestDirs != [] then ''
    for dir in ${lib.concatStringsSep " " cfg.hsTestDirs}; do
      HS_TEST_DIRS+=("$PROJECT_ROOT/$BACKEND_PATH/$dir")
    done
    '' else ""}

    PS_TEST_DIRS=()
    ${if cfg.psTestDirs != [] then ''
    for dir in ${lib.concatStringsSep " " cfg.psTestDirs}; do
      PS_TEST_DIRS+=("$PROJECT_ROOT/$FRONTEND_PATH/$dir")
    done
    '' else ""}

    echo "Finding Haskell source files..."
    HS_FILES=()
    for dir in "''${HASKELL_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "  Scanning $dir"
        while IFS= read -r file; do
          [ -n "$file" ] && HS_FILES+=("''${file#$PROJECT_ROOT/}")
        done < <(find "$dir" -type f -name "*.hs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done

    echo "Finding Haskell test files..."
    HS_TEST_FILES=()
    for dir in "''${HS_TEST_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "  Scanning $dir"
        while IFS= read -r file; do
          [ -n "$file" ] && HS_TEST_FILES+=("''${file#$PROJECT_ROOT/}")
        done < <(find "$dir" -type f -name "*.hs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done

    echo "Finding PureScript source files..."
    PS_FILES=()
    PS_GENERATED_FILES=()
    for dir in "''${PURESCRIPT_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "  Scanning $dir"
        while IFS= read -r file; do
          if [ -n "$file" ]; then
            _rel="''${file#$PROJECT_ROOT/}"
            if [[ "$_rel" == *"/Generated/"* ]] || [[ "$_rel" == *"/$GENERATED_DIR/"* ]]; then
              PS_GENERATED_FILES+=("$_rel")
            else
              PS_FILES+=("$_rel")
            fi
          fi
        done < <(find "$dir" -type f -name "*.purs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done
    ALL_PS_FILES=("''${PS_GENERATED_FILES[@]+"''${PS_GENERATED_FILES[@]}"}" "''${PS_FILES[@]+"''${PS_FILES[@]}"}")

    echo "Finding PureScript test files..."
    PS_TEST_FILES=()
    for dir in "''${PS_TEST_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "  Scanning $dir"
        while IFS= read -r file; do
          [ -n "$file" ] && PS_TEST_FILES+=("''${file#$PROJECT_ROOT/}")
        done < <(find "$dir" -type f -name "*.purs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done

    echo "Finding Nix files..."
    NIX_FILES=()
    while IFS= read -r file; do
      [[ "$file" != *"/script/concat_archive/"* ]] && NIX_FILES+=("''${file#$PROJECT_ROOT/}")
    done < <(find "$PROJECT_ROOT" -maxdepth 1 -type f -name "*.nix" 2>/dev/null | sort)
    if [ -d "$PROJECT_ROOT/nix" ]; then
      while IFS= read -r file; do
        NIX_FILES+=("''${file#$PROJECT_ROOT/}")
      done < <(find "$PROJECT_ROOT/nix" -type f -name "*.nix" 2>/dev/null | sort)
    fi

    {
      echo "{"
      echo "  \"meta\": {"
      echo "    \"generated\": \"$(date '+%s')\","
      echo "    \"humanTime\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
      echo "    \"projectRoot\": \"$PROJECT_ROOT\","
      echo "    \"backendPath\": \"$BACKEND_PATH\","
      echo "    \"frontendPath\": \"$FRONTEND_PATH\""
      echo "  },"

      echo "  \"haskell\": {"
      echo "    \"include\": ["
      ${emitJsonArray "HS_FILES"}
      echo "    ],"
      echo "    \"exclude\": [],"
      echo "    \"count\": ''${#HS_FILES[@]}"
      echo "  },"

      echo "  \"haskellTests\": {"
      echo "    \"include\": ["
      ${emitJsonArray "HS_TEST_FILES"}
      echo "    ],"
      echo "    \"exclude\": [],"
      echo "    \"count\": ''${#HS_TEST_FILES[@]}"
      echo "  },"

      echo "  \"purescript\": {"
      echo "    \"include\": ["
      ${emitJsonArray "ALL_PS_FILES"}
      echo "    ],"
      echo "    \"exclude\": [],"
      echo "    \"generated\": ["
      ${emitJsonArray "PS_GENERATED_FILES"}
      echo "    ],"
      echo "    \"count\": ''${#ALL_PS_FILES[@]},"
      echo "    \"generatedCount\": ''${#PS_GENERATED_FILES[@]}"
      echo "  },"

      echo "  \"purescriptTests\": {"
      echo "    \"include\": ["
      ${emitJsonArray "PS_TEST_FILES"}
      echo "    ],"
      echo "    \"exclude\": [],"
      echo "    \"count\": ''${#PS_TEST_FILES[@]}"
      echo "  },"

      echo "  \"nix\": {"
      echo "    \"include\": ["
      ${emitJsonArray "NIX_FILES"}
      echo "    ],"
      echo "    \"exclude\": [],"
      echo "    \"count\": ''${#NIX_FILES[@]}"
      echo "  }"
      echo "}"
    } > "$MANIFEST_FILE"

    ${pkgs.jq}/bin/jq . "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp" \
      && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"

    BACKUP_TIME=$(date '+%Y%m%d_%H%M%S')
    cp "$MANIFEST_FILE" "$MANIFEST_FILE.$BACKUP_TIME"

    echo ""
    echo "Manifest generated: $MANIFEST_FILE"
    echo "Backup:             $MANIFEST_FILE.$BACKUP_TIME"
    echo ""
    echo "File counts:"
    echo "  Haskell src:      ''${#HS_FILES[@]}"
    echo "  Haskell tests:    ''${#HS_TEST_FILES[@]}"
    echo "  PureScript src:   ''${#ALL_PS_FILES[@]} (''${#PS_GENERATED_FILES[@]} generated)"
    echo "  PureScript tests: ''${#PS_TEST_FILES[@]}"
    echo "  Nix:              ''${#NIX_FILES[@]}"
    echo ""
    echo "Scanned directories:"
    echo "  Haskell source:"
    for dir in "''${HASKELL_DIRS[@]}"; do
      [ -d "$dir" ] && echo "    + $dir" || echo "    - $dir  (not found)"
    done
    echo "  Haskell tests:"
    for dir in "''${HS_TEST_DIRS[@]+"''${HS_TEST_DIRS[@]}"}"; do
      [ -d "$dir" ] && echo "    + $dir" || echo "    - $dir  (not found)"
    done
    echo "  PureScript source:"
    for dir in "''${PURESCRIPT_DIRS[@]}"; do
      [ -d "$dir" ] && echo "    + $dir" || echo "    - $dir  (not found)"
    done
    echo "  PureScript tests:"
    for dir in "''${PS_TEST_DIRS[@]+"''${PS_TEST_DIRS[@]}"}"; do
      [ -d "$dir" ] && echo "    + $dir" || echo "    - $dir  (not found)"
    done
  '';

  manifestData = {
    meta = {
      projectRoot = cfg.projectRoot;
      backendPath = cfg.backendPath;
      frontendPath = cfg.frontendPath;
    };
    haskell         = { include = []; exclude = []; count = 0; };
    haskellTests    = { include = []; exclude = []; count = 0; };
    purescript      = { include = []; exclude = []; generated = []; count = 0; generatedCount = 0; };
    purescriptTests = { include = []; exclude = []; count = 0; };
    nix             = { include = []; exclude = []; count = 0; };
  };

in {
  data           = manifestData;
  json           = builtins.toJSON manifestData;
  generateScript = generateManifestScript;
  debug          = { config = cfg; excludePattern = excludePatternStr; };
}