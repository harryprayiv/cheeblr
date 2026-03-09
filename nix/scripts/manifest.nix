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

  # Helper: emit a JSON array section from a bash array variable name
  emitJsonArray = varName: ''
    if [ ''${#${varName}[@]} -gt 0 ]; then
      for i in "''${!${varName}[@]}"; do
        if [ $i -eq $((''${#${varName}[@]} - 1)) ]; then
          echo "      \"''${${varName}[$i]}\""  >> $MANIFEST_FILE
        else
          echo "      \"''${${varName}[$i]}\","  >> $MANIFEST_FILE
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

    # ── Source dirs ────────────────────────────────────────────────────────────

    HASKELL_DIRS=()
    for dir in ${lib.concatStringsSep " " cfg.hsDirs}; do
      HASKELL_DIRS+=("$PROJECT_ROOT/$BACKEND_PATH/$dir")
    done

    PURESCRIPT_DIRS=()
    for dir in ${lib.concatStringsSep " " cfg.psDirs}; do
      PURESCRIPT_DIRS+=("$PROJECT_ROOT/$FRONTEND_PATH/$dir")
    done

    # ── Test dirs ──────────────────────────────────────────────────────────────

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

    # ── Scan Haskell source files ──────────────────────────────────────────────

    echo "Finding Haskell source files..."
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

    # ── Scan Haskell test files ────────────────────────────────────────────────

    echo "Finding Haskell test files..."
    HS_TEST_FILES=()

    for dir in "''${HS_TEST_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "Scanning $dir for Haskell test files"
        while IFS= read -r file; do
          if [ -n "$file" ]; then
            rel_path="''${file#$PROJECT_ROOT/}"
            HS_TEST_FILES+=("$rel_path")
          fi
        done < <(find "$dir" -type f -name "*.hs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done

    # ── Scan PureScript source files ──────────────────────────────────────────

    echo "Finding PureScript source files..."
    PS_FILES=()
    PS_GENERATED_FILES=()

    for dir in "''${PURESCRIPT_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "Scanning $dir for PureScript files"
        while IFS= read -r file; do
          if [ -n "$file" ]; then
            rel_path="''${file#$PROJECT_ROOT/}"

            if [[ "$rel_path" == *"/Generated/"* ]] || [[ "$rel_path" == *"/$GENERATED_DIR/"* ]]; then
              PS_GENERATED_FILES+=("$rel_path")
            else
              PS_FILES+=("$rel_path")
            fi
          fi
        done < <(find "$dir" -type f -name "*.purs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done

    ALL_PS_FILES=("''${PS_GENERATED_FILES[@]}" "''${PS_FILES[@]}")

    # ── Scan PureScript test files ─────────────────────────────────────────────

    echo "Finding PureScript test files..."
    PS_TEST_FILES=()

    for dir in "''${PS_TEST_DIRS[@]}"; do
      if [ -d "$dir" ]; then
        echo "Scanning $dir for PureScript test files"
        while IFS= read -r file; do
          if [ -n "$file" ]; then
            rel_path="''${file#$PROJECT_ROOT/}"
            PS_TEST_FILES+=("$rel_path")
          fi
        done < <(find "$dir" -type f -name "*.purs" 2>/dev/null | grep -v "${excludePatternStr}" | sort)
      fi
    done

    # ── Scan Nix files ─────────────────────────────────────────────────────────

    echo "Finding Nix files..."
    NIX_FILES=()


    if [ -d "$PROJECT_ROOT" ]; then
      while IFS= read -r file; do
        rel_path="''${file#$PROJECT_ROOT/}"
        if [ -f "$file" ] && [[ "$file" != *"/script/concat_archive/"* ]]; then
          NIX_FILES+=("$rel_path")
        fi
      done < <(find "$PROJECT_ROOT" -maxdepth 1 -type f -name "*.nix" 2>/dev/null | sort)
    fi


    if [ -d "$PROJECT_ROOT/nix" ]; then
      while IFS= read -r file; do
        rel_path="''${file#$PROJECT_ROOT/}"
        NIX_FILES+=("$rel_path")
      done < <(find "$PROJECT_ROOT/nix" -type f -name "*.nix" 2>/dev/null | sort)
    fi

    # ── Write manifest.json ────────────────────────────────────────────────────

    echo "{" > $MANIFEST_FILE
    echo "  \"meta\": {" >> $MANIFEST_FILE
    echo "    \"generated\": \"$(date '+%s')\","  >> $MANIFEST_FILE
    echo "    \"humanTime\": \"$(date '+%Y-%m-%d %H:%M:%S')\","  >> $MANIFEST_FILE
    echo "    \"projectRoot\": \"$PROJECT_ROOT\","  >> $MANIFEST_FILE
    echo "    \"backendPath\": \"$BACKEND_PATH\","  >> $MANIFEST_FILE
    echo "    \"frontendPath\": \"$FRONTEND_PATH\""  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # haskell source section
    echo "  \"haskell\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    ${emitJsonArray "HS_FILES"}
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#HS_FILES[@]}"  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # haskell test section
    echo "  \"haskellTests\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    ${emitJsonArray "HS_TEST_FILES"}
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#HS_TEST_FILES[@]}"  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # purescript source section
    echo "  \"purescript\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    ${emitJsonArray "ALL_PS_FILES"}
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"generated\": ["  >> $MANIFEST_FILE
    ${emitJsonArray "PS_GENERATED_FILES"}
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#ALL_PS_FILES[@]},"  >> $MANIFEST_FILE
    echo "    \"generatedCount\": ''${#PS_GENERATED_FILES[@]}"  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # purescript test section
    echo "  \"purescriptTests\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    ${emitJsonArray "PS_TEST_FILES"}
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#PS_TEST_FILES[@]}"  >> $MANIFEST_FILE
    echo "  },"  >> $MANIFEST_FILE

    # nix section
    echo "  \"nix\": {"  >> $MANIFEST_FILE
    echo "    \"include\": ["  >> $MANIFEST_FILE
    ${emitJsonArray "NIX_FILES"}
    echo "    ],"  >> $MANIFEST_FILE
    echo "    \"exclude\": [],"  >> $MANIFEST_FILE
    echo "    \"count\": ''${#NIX_FILES[@]}"  >> $MANIFEST_FILE
    echo "  }"  >> $MANIFEST_FILE
    echo "}"  >> $MANIFEST_FILE


    ${pkgs.jq}/bin/jq . "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp" && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"


    BACKUP_TIME=$(date '+%Y%m%d_%H%M%S')
    cp "$MANIFEST_FILE" "$MANIFEST_FILE.$BACKUP_TIME"

    echo "Manifest generated at: $MANIFEST_FILE"
    echo "Backup created at: $MANIFEST_FILE.$BACKUP_TIME"
    echo "Found ''${#HS_FILES[@]} Haskell source, ''${#HS_TEST_FILES[@]} Haskell test, ''${#ALL_PS_FILES[@]} PureScript source, ''${#PS_TEST_FILES[@]} PureScript test, ''${#NIX_FILES[@]} Nix files"
  '';


  manifestData = {
    meta = {
      projectRoot = cfg.projectRoot;
      backendPath = cfg.backendPath;
      frontendPath = cfg.frontendPath;
    };
    haskell.include = [];
    haskell.exclude = [];
    haskell.count = 0;
    haskellTests.include = [];
    haskellTests.exclude = [];
    haskellTests.count = 0;
    purescript.include = [];
    purescript.exclude = [];
    purescript.generated = [];
    purescript.count = 0;
    purescript.generatedCount = 0;
    purescriptTests.include = [];
    purescriptTests.exclude = [];
    purescriptTests.count = 0;
    nix.include = [];
    nix.exclude = [];
    nix.count = 0;
  };

in {

  data = manifestData;


  json = builtins.toJSON manifestData;


  generateScript = generateManifestScript;


  debug = {
    config = cfg;
    excludePattern = excludePatternStr;
  };
}
