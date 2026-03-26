{ pkgs, lib, name, backendPath, frontendPath, hsDirs, psDirs, hsTestDirs ? [], psTestDirs ? [], hsConfig ? {} }:

let
  excludePatterns = ".spago\\|node_modules\\|dist\\|dist-newstyle\\|output\\|\\.psci_modules";

  manifest-tui = pkgs.writeShellScriptBin "manifest-tui" ''
    set -euo pipefail
    _G="${pkgs.gum}/bin/gum"

    PROJECT_ROOT="$(pwd)"
    MANIFEST_FILE="$PROJECT_ROOT/script/manifest.json"
    mkdir -p "$PROJECT_ROOT/script"

    # ── display helpers ────────────────────────────────────────────────────

    header() {
      clear
      "$_G" style \
        --foreground 10 --border-foreground 2 --border double \
        --align center --width 62 --margin "1 2" --padding "1 3" \
        "${lib.toUpper name}" "manifest tools"
      echo ""
    }

    section_header() {
      "$_G" style \
        --foreground 6 --border-foreground 6 --border normal \
        --align center --width 62 --margin "0 2" --padding "0 2" \
        "$1"
      echo ""
    }

    pause() {
      echo ""
      read -r -p "  Press Enter to continue..."
    }

    ok()   { "$_G" style --foreground 2  "  ✓ $*"; }
    err()  { "$_G" style --foreground 1  "  ✗ $*"; }
    info() { "$_G" style --foreground 3  "  · $*"; }
    dim()  { "$_G" style --foreground 8  "  $*"; }

    ensure_manifest() {
      if [ ! -f "$MANIFEST_FILE" ]; then
        info "No manifest found — running generate-manifest..."
        echo ""
        generate-manifest
        echo ""
      fi
    }

    # ── file scanner (mirrors generate-manifest logic) ─────────────────────

    scan_section_files() {
      local section="$1"
      case "$section" in
        haskell)
          for dir in ${lib.concatStringsSep " " (map (d: "${backendPath}/${d}") hsDirs)}; do
            local full="$PROJECT_ROOT/$dir"
            if [ -d "$full" ]; then
              find "$full" -type f -name "*.hs" 2>/dev/null \
                | grep -v "${excludePatterns}" | sort \
                | sed "s|$PROJECT_ROOT/||"
            fi
          done ;;
        haskellTests)
          for dir in ${lib.concatStringsSep " " (if hsTestDirs != [] then map (d: "${backendPath}/${d}") hsTestDirs else ["${backendPath}/test"])}; do
            local full="$PROJECT_ROOT/$dir"
            if [ -d "$full" ]; then
              find "$full" -type f -name "*.hs" 2>/dev/null \
                | grep -v "${excludePatterns}" | sort \
                | sed "s|$PROJECT_ROOT/||"
            fi
          done ;;
        purescript)
          for dir in ${lib.concatStringsSep " " (map (d: "${frontendPath}/${d}") psDirs)}; do
            local full="$PROJECT_ROOT/$dir"
            if [ -d "$full" ]; then
              find "$full" -type f -name "*.purs" 2>/dev/null \
                | grep -v "${excludePatterns}" | sort \
                | sed "s|$PROJECT_ROOT/||"
            fi
          done ;;
        purescriptTests)
          for dir in ${lib.concatStringsSep " " (if psTestDirs != [] then map (d: "${frontendPath}/${d}") psTestDirs else ["${frontendPath}/test"])}; do
            local full="$PROJECT_ROOT/$dir"
            if [ -d "$full" ]; then
              find "$full" -type f -name "*.purs" 2>/dev/null \
                | grep -v "${excludePatterns}" | sort \
                | sed "s|$PROJECT_ROOT/||"
            fi
          done ;;
        nix)
          find "$PROJECT_ROOT" -maxdepth 1 -type f -name "*.nix" 2>/dev/null \
            | sort | sed "s|$PROJECT_ROOT/||"
          if [ -d "$PROJECT_ROOT/nix" ]; then
            find "$PROJECT_ROOT/nix" -type f -name "*.nix" 2>/dev/null \
              | sort | sed "s|$PROJECT_ROOT/||"
          fi ;;
      esac
    }

    # ── manifest section editor ────────────────────────────────────────────

    edit_section() {
      local section="$1"
      header
      section_header "Edit section: $section"

      mapfile -t ALL_FILES < <(scan_section_files "$section" 2>/dev/null | grep -v '^$' || true)

      if [ ''${#ALL_FILES[@]} -eq 0 ]; then
        err "No $section files found on disk for this section."
        pause
        return
      fi

      local CURRENT_STR=""
      if [ -f "$MANIFEST_FILE" ]; then
        CURRENT_STR=$(${pkgs.jq}/bin/jq -r \
          ".\"$section\".include[]?" "$MANIFEST_FILE" 2>/dev/null \
          | tr '\n' ',' | sed 's/,$//' || true)
      fi

      # Default to all files selected if section is empty or manifest is new
      if [ -z "$CURRENT_STR" ]; then
        CURRENT_STR=$(printf '%s\n' "''${ALL_FILES[@]}" | tr '\n' ',' | sed 's/,$//')
      fi

      local current_count=0
      current_count=$(echo "$CURRENT_STR" | tr ',' '\n' | grep -c . || echo 0)

      dim "''${#ALL_FILES[@]} files found on disk  ·  $current_count currently in manifest"
      dim "Space to toggle  ·  Enter to confirm  ·  / to filter"
      echo ""

      local CHOSEN=""
      CHOSEN=$("$_G" choose --no-limit \
        --selected="$CURRENT_STR" \
        --header="$section — select files to include:" \
        --height=35 \
        "''${ALL_FILES[@]}" || true)

      if [ -z "$CHOSEN" ]; then
        info "No selection made — manifest unchanged."
        pause
        return
      fi

      local NEW_JSON
      NEW_JSON=$(echo "$CHOSEN" | ${pkgs.jq}/bin/jq -R . | ${pkgs.jq}/bin/jq -s .)

      if [ "$section" = "purescript" ]; then
        local GEN_JSON
        GEN_JSON=$(echo "$NEW_JSON" | ${pkgs.jq}/bin/jq '[.[] | select(test("/Generated/"))]')
        ${pkgs.jq}/bin/jq \
          --argjson files "$NEW_JSON" \
          --argjson gen   "$GEN_JSON" \
          '.purescript.include        = $files              |
           .purescript.count          = ($files | length)  |
           .purescript.generated      = $gen               |
           .purescript.generatedCount = ($gen   | length)' \
          "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp" \
          && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"
      else
        ${pkgs.jq}/bin/jq \
          --argjson files "$NEW_JSON" \
          "."$section".include = \$files | ."$section".count = (\$files | length)" \
          "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp" \
          && mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"
      fi


      local SAVED_COUNT
      SAVED_COUNT=$(echo "$NEW_JSON" | ${pkgs.jq}/bin/jq -r 'length')
      ok "Saved $SAVED_COUNT files to $section."
      pause
    }

    # ── edit manifest (section picker) ────────────────────────────────────

    edit_manifest() {
      ensure_manifest
      while true; do
        header
        section_header "Edit Manifest"

        hs_c=$(${pkgs.jq}/bin/jq    -r '.haskell.count         // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)
        hs_t_c=$(${pkgs.jq}/bin/jq  -r '.haskellTests.count    // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)
        ps_c=$(${pkgs.jq}/bin/jq    -r '.purescript.count      // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)
        ps_t_c=$(${pkgs.jq}/bin/jq  -r '.purescriptTests.count // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)
        nix_c=$(${pkgs.jq}/bin/jq   -r '.nix.count             // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)

        SECTION=$("$_G" choose \
          --cursor "> " \
          --header "  Choose a section to edit:" \
          --height 10 \
          "haskell          ($hs_c files)" \
          "haskellTests     ($hs_t_c files)" \
          "purescript       ($ps_c files)" \
          "purescriptTests  ($ps_t_c files)" \
          "nix              ($nix_c files)" \
          "Back") || break

        case "$SECTION" in
          haskellTests*)    edit_section "haskellTests" ;;
          haskell*)         edit_section "haskell" ;;
          purescriptTests*) edit_section "purescriptTests" ;;
          purescript*)      edit_section "purescript" ;;
          nix*)             edit_section "nix" ;;
          Back)             break ;;
        esac
      done
    }

    # ── git ref picker ─────────────────────────────────────────────────────

    pick_git_ref() {
      local prompt="$1"
      local default="''${2:-HEAD}"

      local REFS
      REFS=$(
        echo "HEAD"
        echo "(working tree)"
        git -C "$PROJECT_ROOT" branch --format='%(refname:short)' 2>/dev/null || true
        git -C "$PROJECT_ROOT" branch -r --format='%(refname:short)' 2>/dev/null | grep -v '/HEAD' || true
        git -C "$PROJECT_ROOT" tag 2>/dev/null || true
      )

      local CHOSEN
      CHOSEN=$(echo "$REFS" | "$_G" filter \
        --prompt="  $prompt > " \
        --placeholder="type to search refs..." \
        --height=20 || echo "$default")

      echo "$CHOSEN"
    }

    # ── llm context runner ─────────────────────────────────────────────────

    run_llm_context() {
      header
      section_header "LLM Context"

      if ! git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
        err "Not a git repository."
        pause
        return
      fi

      echo ""
      dim "Step 1 of 3 — pick base ref (diff FROM this)"
      echo ""
      local BASE_REF
      BASE_REF=$(pick_git_ref "Base ref")
      ok "Base ref:    $BASE_REF"
      echo ""

      dim "Step 2 of 3 — pick compare ref (diff TO this)"
      dim "Choose '(working tree)' to compare against current uncommitted changes"
      echo ""
      local COMPARE_REF
      COMPARE_REF=$(pick_git_ref "Compare ref" "(working tree)")
      ok "Compare ref: $COMPARE_REF"
      echo ""

      dim "Step 3 of 3 — options"
      echo ""
      local FLAGS_RAW
      FLAGS_RAW=$("$_G" choose --no-limit \
        --header="Select flags (space to toggle, enter to confirm):" \
        --height=8 \
        "--diff-only     skip full file contents, show diff only" \
        "--files-only    skip diff, show full file contents only" \
        "--no-compile    do not run cabal / spago" \
        "--no-strip      keep comments in output" || true)

      local CMD_FLAGS=()
      echo "$FLAGS_RAW" | grep -q -- "--diff-only"  && CMD_FLAGS+=(--diff-only)
      echo "$FLAGS_RAW" | grep -q -- "--files-only" && CMD_FLAGS+=(--files-only)
      echo "$FLAGS_RAW" | grep -q -- "--no-compile" && CMD_FLAGS+=(--no-compile)
      echo "$FLAGS_RAW" | grep -q -- "--no-strip"   && CMD_FLAGS+=(--no-strip)

      [ "$BASE_REF"    != "(working tree)" ] && CMD_FLAGS+=(--base-ref="$BASE_REF")
      [ "$COMPARE_REF" != "(working tree)" ] && CMD_FLAGS+=(--compare-ref="$COMPARE_REF")

      echo ""
      "$_G" style --foreground 6 "  llm-context ''${CMD_FLAGS[*]+"''${CMD_FLAGS[*]}"}"
      echo ""
      echo "────────────────────────────────────────────────────────────"
      echo ""

      if llm-context "''${CMD_FLAGS[@]+"''${CMD_FLAGS[@]}"}"; then
        echo ""
        echo "────────────────────────────────────────────────────────────"
        ok "LLM context generated."
      else
        echo ""
        echo "────────────────────────────────────────────────────────────"
        err "llm-context exited with an error."
      fi
      pause
    }

    # ── compile runners ────────────────────────────────────────────────────

    run_generate_manifest() {
      header
      section_header "Generate Manifest"
      echo ""
      if generate-manifest; then
        echo ""
        ok "Manifest generated."
      else
        echo ""
        err "generate-manifest failed."
      fi
      pause
    }

    run_compile_manifest() {
      header
      section_header "Compile Manifest"
      echo ""
      if compile-manifest; then
        echo ""
        ok "compile-manifest finished."
      else
        echo ""
        err "compile-manifest exited with an error."
      fi
      pause
    }

    run_compile_archive() {
      header
      section_header "Compile Archive"
      echo ""
      if compile-archive; then
        echo ""
        ok "Archive created."
      else
        echo ""
        err "compile-archive exited with an error."
      fi
      pause
    }

    # ── main menu ──────────────────────────────────────────────────────────

    while true; do
      header

      if [ -f "$MANIFEST_FILE" ]; then
          HT=$(${pkgs.jq}/bin/jq -r '.meta.humanTime // "unknown"' "$MANIFEST_FILE" 2>/dev/null || echo "unknown")
          HS_C=$(${pkgs.jq}/bin/jq  -r '.haskell.count    // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)
        PS_C=$(${pkgs.jq}/bin/jq  -r '.purescript.count // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)
        NIX_C=$(${pkgs.jq}/bin/jq -r '.nix.count        // 0' "$MANIFEST_FILE" 2>/dev/null || echo 0)
        dim "manifest: $HT  ·  HS $HS_C  PS $PS_C  Nix $NIX_C"
      else
        "$_G" style --foreground 1 --margin "0 4" "No manifest found — run Generate Manifest first"
      fi
      echo ""

      ACTION=$("$_G" choose \
        --cursor "> " \
        --header "  Select action:" \
        --height 10 \
        "Generate Manifest" \
        "Edit Manifest" \
        "Compile Manifest" \
        "Compile Archive" \
        "LLM Context" \
        "Quit") || break

      case "$ACTION" in
        "Generate Manifest") run_generate_manifest ;;
        "Edit Manifest")     edit_manifest ;;
        "Compile Manifest")  run_compile_manifest ;;
        "Compile Archive")   run_compile_archive ;;
        "LLM Context")       run_llm_context ;;
        "Quit"|*)            break ;;
      esac
    done

    clear
    "$_G" style --foreground 2 --align center --width 62 --margin "1 2" \
      "Goodbye from ${name} manifest tools."
  '';

in {
  inherit manifest-tui;
}