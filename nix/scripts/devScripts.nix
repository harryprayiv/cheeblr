{ pkgs, name, lib, backendPath, frontendPath, hsDirs, psDirs, hsTestDirs ? [], psTestDirs ? [], hsConfig }:

let

  compile-manifest = pkgs.writeShellScriptBin "compile-manifest" ''
    set -euo pipefail

    BACKEND_DIR="${backendPath}"
    FRONTEND_DIR="${frontendPath}"

    PROJECT_ROOT="$(pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/script"
    MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
    BASE_DIR="$SCRIPT_DIR/concat_archive"
    HASH_DIR="$BASE_DIR/.hashes"
    OUTPUT_DIR="$BASE_DIR/output"
    ARCHIVE_DIR="$BASE_DIR/archive"
    mkdir -p "$OUTPUT_DIR" "$ARCHIVE_DIR" "$HASH_DIR"

    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

    if [ ! -f "$MANIFEST_FILE" ]; then
      echo "Manifest not found at $MANIFEST_FILE, running generate-manifest..."
      generate-manifest
      if [ ! -f "$MANIFEST_FILE" ]; then
        echo "Error: generate-manifest did not produce a manifest file."
        exit 1
      fi
    fi

    calculate_hash() {
      local file_list="$1"
      [ -z "$file_list" ] && echo "empty" && return
      echo "$file_list" | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1
    }

    get_previous_hash() {
      local f="$HASH_DIR/$1_last_hash"
      [ -f "$f" ] && cat "$f" || echo ""
    }

    save_current_hash() {
      echo "$2" > "$HASH_DIR/$1_last_hash"
    }

    safe_archive() {
      local prefix="$1" ext="$2"
      find "$OUTPUT_DIR" -maxdepth 1 -name "''${prefix}_*.$ext" 2>/dev/null \
        | xargs -r mv -t "$ARCHIVE_DIR/" 2>/dev/null || true
    }

    compile_haskell() {
      local tmp; tmp=$(mktemp)
      (cd "$PROJECT_ROOT/$BACKEND_DIR" && cabal build) > "$tmp" 2>&1
      local rc=$?
      [ $rc -eq 0 ] && echo "COMPILE_STATUS: true" || echo "COMPILE_STATUS: false"
      echo "BUILD_OUTPUT:"
      cat "$tmp"
      rm "$tmp"
    }

    compile_purescript() {
      local tmp; tmp=$(mktemp)
      if timeout 60 bash -c "cd '$PROJECT_ROOT/$FRONTEND_DIR' && spago build" > "$tmp" 2>&1; then
        echo "COMPILE_STATUS: true"
        echo "BUILD_OUTPUT:"
        cat "$tmp"
      else
        local rc=$?
        echo "COMPILE_STATUS: false"
        if [ $rc -eq 124 ]; then
          echo "BUILD_OUTPUT: timed out after 60 seconds"
        else
          echo "BUILD_OUTPUT:"
          cat "$tmp"
        fi
      fi
      rm "$tmp"
    }

    clean_haskell() {
      perl -0777 -pe '
        my @pragmas;
        while ($_ =~ /(\{-#.*?#-\})/gs) { push @pragmas, $1; }
        s/\{-#.*?#-\}//gs;
        s/(\s*)--.*$/$1/gm;
        s/\{-(?!#).*?-\}//gs;
        if (@pragmas) {
          my %seen;
          @pragmas = grep { !$seen{$_}++ } @pragmas;
          $_ = join("\n", @pragmas) . "\n\n" . $_;
        }
      ' | cat -s | sed 's/[[:space:]]*$//'
    }

    clean_purescript() {
      sed 's/\([ ]*\)--.*$/\1/' | \
      perl -0777 -pe 's/\{-.*?-\}//gs' | \
      cat -s | sed 's/[[:space:]]*$//'
    }

    clean_nix() {
      sed 's/\([ ]*\)#.*$/\1/' | \
      perl -0777 -pe 's!/\*[^*]*\*+(?:[^/][^*]*\*+)*/!!gs' | \
      cat -s | sed 's/[[:space:]]*$//' | \
      sed 's/\([ ]*\){[[:space:]]*}/\1{ }/'
    }

    extract_error_files() {
      local compile_output="$1" ext="$2"
      echo "$compile_output" | grep -q "^COMPILE_STATUS: false" || return 0
      echo "$compile_output" | grep -oE "[a-zA-Z0-9_./-]+\.$ext" | sort -u || true
    }

    resolve_path() {
      local raw="$1"
      [ -f "$raw" ]                                   && echo "$raw"                                   && return
      [ -f "$PROJECT_ROOT/$raw" ]                     && echo "$PROJECT_ROOT/$raw"                     && return
      [ -f "$PROJECT_ROOT/$BACKEND_DIR/$raw" ]        && echo "$PROJECT_ROOT/$BACKEND_DIR/$raw"        && return
      [ -f "$PROJECT_ROOT/$FRONTEND_DIR/$raw" ]       && echo "$PROJECT_ROOT/$FRONTEND_DIR/$raw"       && return
      find "$PROJECT_ROOT" -path "*/$raw" -type f 2>/dev/null | head -1 || true
    }

    process_section() {
      local section_key="$1" prefix="$2" clean_fn="$3" comment_char="$4" compile_fn="$5"
      local file_ext
      case "$section_key" in
        haskell|haskellTests)       file_ext="hs"   ;;
        purescript|purescriptTests) file_ext="purs" ;;
        nix)                        file_ext="nix"  ;;
      esac

      local file_list
      file_list=$(${pkgs.jq}/bin/jq -r ".\"$section_key\".include[]?" "$MANIFEST_FILE" 2>/dev/null || true)

      if [ -z "$file_list" ]; then
        echo "  $section_key: no files in manifest, skipping."
        return
      fi

      local total; total=$(echo "$file_list" | grep -c .)
      local current_hash; current_hash=$(calculate_hash "$file_list")
      local previous_hash; previous_hash=$(get_previous_hash "$section_key")

      if [ "$current_hash" = "$previous_hash" ]; then
        local existing
        existing=$(find "$OUTPUT_DIR" -maxdepth 1 -name "''${prefix}_*.$file_ext" 2>/dev/null | head -1)
        if [ -n "$existing" ]; then
          local old_base sfx=""
          old_base=$(basename "$existing" ".$file_ext")
          [[ "$old_base" == *_OK  ]] && sfx="_OK"
          [[ "$old_base" == *_ERR ]] && sfx="_ERR"
          local new_name
          printf -v new_name '%s/%s_%s%s.%s' "$OUTPUT_DIR" "$prefix" "$TIMESTAMP" "$sfx" "$file_ext"
          mv "$existing" "$new_name"
          echo "  $section_key: unchanged -> $(basename "$new_name")"
          return
        fi
        echo "  $section_key: hash matches but no output found, regenerating."
      fi

      safe_archive "$prefix" "$file_ext"

      local compile_output="" compile_failed=false compile_status="" sfx=""
      if [ -n "$compile_fn" ]; then
        echo "  $section_key: compiling..."
        compile_output=$(eval "$compile_fn")
        if echo "$compile_output" | grep -q "^COMPILE_STATUS: false"; then
          compile_failed=true; sfx="_ERR"; compile_status="FAILED"
        elif echo "$compile_output" | grep -q "^COMPILE_STATUS: true"; then
          sfx="_OK"; compile_status="OK"
        fi
      fi

      local output_file
      printf -v output_file '%s/%s_%s%s.%s' "$OUTPUT_DIR" "$prefix" "$TIMESTAMP" "$sfx" "$file_ext"
      local tmp; tmp=$(mktemp)

      {
        echo "$comment_char$comment_char"
        echo "$comment_char$comment_char Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "$comment_char$comment_char Section:   $section_key"
        echo "$comment_char$comment_char Files:     $total"
        [ -n "$compile_status" ] && echo "$comment_char$comment_char Compile:   $compile_status"
        echo "$comment_char$comment_char"
        echo ""

        if [ "$compile_failed" = true ]; then

          echo "{-"
          echo "$compile_output" | grep -v "^COMPILE_STATUS:" | grep -v "^BUILD_OUTPUT:"
          echo "-}"
          echo ""

          local raw_error_paths
          raw_error_paths=$(extract_error_files "$compile_output" "$file_ext")

          if [ -n "$raw_error_paths" ]; then
            echo "$comment_char$comment_char ---- PROBLEMATIC FILES ----"
            echo ""
            local shown=""
            while IFS= read -r raw; do
              [ -z "$raw" ] && continue
              local fp; fp=$(resolve_path "$raw")
              if [ -n "$fp" ] && [ -f "$fp" ]; then
                local rel="''${fp#$PROJECT_ROOT/}"
                shown="$shown
$rel"
                echo "$comment_char FILE: $rel"
                cat "$fp" | eval "$clean_fn"
                echo "$comment_char END OF: $rel"
                echo ""
              else
                echo "$comment_char WARNING: could not locate $raw"
                echo ""
              fi
            done <<< "$raw_error_paths"

            echo "$comment_char$comment_char ---- ALL MANIFEST FILES ----"
            echo ""

            while IFS= read -r file; do
              [ -z "$file" ] && continue
              if [ -n "$shown" ] && echo "$shown" | grep -qxF "$file" 2>/dev/null; then
                continue
              fi
              local full_path="$PROJECT_ROOT/$file"
              if [ -f "$full_path" ]; then
                echo "$comment_char FILE: $file"
                cat "$full_path" | eval "$clean_fn"
                echo "$comment_char END OF: $file"
                echo ""
              else
                echo "$comment_char WARNING: File not found: $file"
                echo ""
              fi
            done <<< "$file_list"

          else

            while IFS= read -r file; do
              [ -z "$file" ] && continue
              local full_path="$PROJECT_ROOT/$file"
              if [ -f "$full_path" ]; then
                echo "$comment_char FILE: $file"
                cat "$full_path" | eval "$clean_fn"
                echo "$comment_char END OF: $file"
                echo ""
              else
                echo "$comment_char WARNING: File not found: $file"
                echo ""
              fi
            done <<< "$file_list"
          fi

        else

          while IFS= read -r file; do
            [ -z "$file" ] && continue
            local full_path="$PROJECT_ROOT/$file"
            if [ -f "$full_path" ]; then
              echo "$comment_char FILE: $file"
              cat "$full_path" | eval "$clean_fn"
              echo "$comment_char END OF: $file"
              echo ""
            else
              echo "$comment_char WARNING: File not found: $file"
              echo ""
            fi
          done <<< "$file_list"
        fi

      } > "$tmp"

      mv "$tmp" "$output_file"
      save_current_hash "$section_key" "$current_hash"
      echo "  $section_key: -> $(basename "$output_file")"
    }

    echo "Processing manifest sections..."
    process_section "haskell"         "Haskell"         "clean_haskell"    "--" "compile_haskell"
    process_section "haskellTests"    "HaskellTests"    "clean_haskell"    "--" ""
    process_section "purescript"      "PureScript"      "clean_purescript" "--" "compile_purescript"
    process_section "purescriptTests" "PureScriptTests" "clean_purescript" "--" ""
    process_section "nix"             "Nix"             "clean_nix"        "#"  ""
    echo ""
    echo "Done. Output in $OUTPUT_DIR"
  '';

  compile-archive = pkgs.writeShellScriptBin "compile-archive" ''
    set -euo pipefail

    compile-manifest

    PROJECT_ROOT="$(pwd)"
    ARCHIVES_DIR="$PROJECT_ROOT/script/archives"
    mkdir -p "$ARCHIVES_DIR"

    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    ARCHIVE_PATH="$ARCHIVES_DIR/${name}_$TIMESTAMP.tar.gz"

    echo "Creating archive at $ARCHIVE_PATH..."
    tar -czf "$ARCHIVE_PATH" -C "$PROJECT_ROOT" script/concat_archive/output
    echo "Archive created: $ARCHIVE_PATH"
  '';

  llm-context = pkgs.writeShellScriptBin "llm-context" ''
    set -euo pipefail

    BACKEND_DIR="${backendPath}"
    FRONTEND_DIR="${frontendPath}"

    PROJECT_ROOT="$(pwd)"
    MANIFEST_FILE="$PROJECT_ROOT/script/manifest.json"
    OUTPUT_DIR="$PROJECT_ROOT/script/concat_archive/output"
    mkdir -p "$OUTPUT_DIR"

    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

    DIFF_ONLY=false
    FILES_ONLY=false
    NO_COMPILE=false
    NO_STRIP=false
    BASE_REF=""
    COMPARE_REF=""

    for arg in "''${@}"; do
      case "$arg" in
        --diff-only)       DIFF_ONLY=true ;;
        --files-only)      FILES_ONLY=true ;;
        --no-compile)      NO_COMPILE=true ;;
        --no-strip)        NO_STRIP=true ;;
        --base-ref=*)      BASE_REF="''${arg#--base-ref=}" ;;
        --compare-ref=*)   COMPARE_REF="''${arg#--compare-ref=}" ;;
        --help)
          echo "Usage: llm-context [OPTIONS]"
          echo ""
          echo "Generates an LLM-optimized context file from manifest-tracked files"
          echo "that differ between two git refs (default: HEAD vs working tree)."
          echo ""
          echo "Options:"
          echo "  --base-ref=REF      diff from this ref (default: HEAD)"
          echo "  --compare-ref=REF   diff to this ref   (default: working tree)"
          echo "  --diff-only         git diff only, no full file contents"
          echo "  --files-only        full file contents only, no diff"
          echo "  --no-compile        skip compilation"
          echo "  --no-strip          keep comments in file contents"
          echo ""
          echo "Output: script/concat_archive/output/LLMContext_TIMESTAMP[_OK|_ERR].md"
          exit 0 ;;
        *)
          echo "Unknown flag: $arg  (try --help)"
          exit 1 ;;
      esac
    done

    if [ ! -f "$MANIFEST_FILE" ]; then
      echo "No manifest at $MANIFEST_FILE -- run 'generate-manifest' first."
      exit 1
    fi

    if ! git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
      echo "Not a git repository."
      exit 1
    fi

    ALL_CHANGED=""
    if [ -n "$BASE_REF" ] && [ -n "$COMPARE_REF" ]; then
      ALL_CHANGED=$(git -C "$PROJECT_ROOT" diff "''${BASE_REF}...''${COMPARE_REF}" --name-only 2>/dev/null || true)
    elif [ -n "$BASE_REF" ]; then
      ALL_CHANGED=$(git -C "$PROJECT_ROOT" diff "''${BASE_REF}" --name-only 2>/dev/null || true)
    elif git -C "$PROJECT_ROOT" rev-parse HEAD > /dev/null 2>&1; then
      ALL_CHANGED=$(git -C "$PROJECT_ROOT" diff HEAD --name-only 2>/dev/null || true)
    else
      ALL_CHANGED=$(git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null || true)
    fi

    if [ -z "$ALL_CHANGED" ]; then
      echo "No changes detected."
      echo "Hint: use 'compile-manifest' for a full snapshot."
      exit 0
    fi

    get_changed_in_section() {
      local section="$1"
      local manifest_files
      manifest_files=$(${pkgs.jq}/bin/jq -r ".\"$section\".include[]?" "$MANIFEST_FILE" 2>/dev/null \
        | sed 's|^\./||' || true)
      [ -z "$manifest_files" ] && return 0
      while IFS= read -r mf; do
        [ -z "$mf" ] && continue
        if echo "$ALL_CHANGED" | grep -qxF "$mf"; then
          echo "$mf"
        fi
      done <<< "$manifest_files"
    }

    HS_CHANGED=$(get_changed_in_section "haskell")
    HS_TEST_CHANGED=$(get_changed_in_section "haskellTests")
    PS_CHANGED=$(get_changed_in_section "purescript")
    PS_TEST_CHANGED=$(get_changed_in_section "purescriptTests")
    NIX_CHANGED=$(get_changed_in_section "nix")

    ALL_MANIFEST_CHANGED=$(printf '%s\n%s\n%s\n%s\n%s\n' \
      "$HS_CHANGED" "$HS_TEST_CHANGED" \
      "$PS_CHANGED" "$PS_TEST_CHANGED" \
      "$NIX_CHANGED" \
      | sort -u | grep -v '^$' || true)

    if [ -z "$ALL_MANIFEST_CHANGED" ]; then
      echo "No changes found in manifest-tracked files."
      echo "Changed files (outside manifest):"
      echo "$ALL_CHANGED"
      exit 0
    fi

    CHANGED_COUNT=$(echo "$ALL_MANIFEST_CHANGED" | wc -l)
    echo "Found $CHANGED_COUNT changed manifest file(s)."

    HS_COMPILE_OUTPUT=""
    PS_COMPILE_OUTPUT=""
    HS_STATUS=""
    PS_STATUS=""

    compile_haskell_local() {
      local tmp; tmp=$(mktemp)
      (cd "$PROJECT_ROOT/$BACKEND_DIR" && cabal build) > "$tmp" 2>&1
      local rc=$?
      [ $rc -eq 0 ] && echo "COMPILE_STATUS: true" || echo "COMPILE_STATUS: false"
      echo "BUILD_OUTPUT:"
      cat "$tmp"
      rm "$tmp"
    }

    compile_purescript_local() {
      local tmp; tmp=$(mktemp)
      if timeout 60 bash -c "cd '$PROJECT_ROOT/$FRONTEND_DIR' && spago build" > "$tmp" 2>&1; then
        echo "COMPILE_STATUS: true"
        echo "BUILD_OUTPUT:"
        cat "$tmp"
      else
        local rc=$?
        echo "COMPILE_STATUS: false"
        if [ $rc -eq 124 ]; then
          echo "BUILD_OUTPUT: timed out after 60 seconds"
        else
          echo "BUILD_OUTPUT:"
          cat "$tmp"
        fi
      fi
      rm "$tmp"
    }

    compile_status_suffix() {
      local out="$1"
      [ -z "$out" ] && echo "" && return
      echo "$out" | grep -q "^COMPILE_STATUS: true"  && echo "_OK"  && return
      echo "$out" | grep -q "^COMPILE_STATUS: false" && echo "_ERR" && return
      echo ""
    }

    if [ "$NO_COMPILE" = false ]; then
      if [ -n "$HS_CHANGED" ] || [ -n "$HS_TEST_CHANGED" ]; then
        echo "  Compiling Haskell..."
        HS_COMPILE_OUTPUT=$(compile_haskell_local)
        HS_STATUS=$(compile_status_suffix "$HS_COMPILE_OUTPUT")
        echo "  Haskell: $HS_STATUS"
      fi
      if [ -n "$PS_CHANGED" ] || [ -n "$PS_TEST_CHANGED" ]; then
        echo "  Compiling PureScript..."
        PS_COMPILE_OUTPUT=$(compile_purescript_local)
        PS_STATUS=$(compile_status_suffix "$PS_COMPILE_OUTPUT")
        echo "  PureScript: $PS_STATUS"
      fi
    fi

    OVERALL_STATUS=""
    if [ "$HS_STATUS" = "_ERR" ] || [ "$PS_STATUS" = "_ERR" ]; then
      OVERALL_STATUS="_ERR"
    elif [ "$HS_STATUS" = "_OK" ] || [ "$PS_STATUS" = "_OK" ]; then
      OVERALL_STATUS="_OK"
    fi

    extract_error_files() {
      local output="$1" ext="$2" file_list="$3"
      [ -z "$output" ] && return 0
      echo "$output" | grep -q "^COMPILE_STATUS: false" || return 0
      local candidates
      candidates=$(echo "$output" | grep -oE "[a-zA-Z0-9_./-]+\.$ext" | sort -u || true)
      [ -z "$candidates" ] && return 0
      while IFS= read -r raw; do
        [ -z "$raw" ] && continue
        local candidate="''${raw##*/}"
        while IFS= read -r listed; do
          [ -z "$listed" ] && continue
          if [[ "$listed" == "$candidate" ]] || [[ "$listed" == *"/$candidate" ]]; then
            echo "$listed"
          fi
        done <<< "$file_list"
      done <<< "$candidates" | sort -u
    }

    HS_ERROR_FILES=""
    PS_ERROR_FILES=""
    [ -n "$HS_COMPILE_OUTPUT" ] && HS_ERROR_FILES=$(extract_error_files "$HS_COMPILE_OUTPUT" "hs" \
      "$(printf '%s\n%s\n' "$HS_CHANGED" "$HS_TEST_CHANGED" | grep -v '^$' || true)")
    [ -n "$PS_COMPILE_OUTPUT" ] && PS_ERROR_FILES=$(extract_error_files "$PS_COMPILE_OUTPUT" "purs" \
      "$(printf '%s\n%s\n' "$PS_CHANGED" "$PS_TEST_CHANGED" | grep -v '^$' || true)")

    ALL_ERROR_FILES=$(printf '%s\n%s\n' "$HS_ERROR_FILES" "$PS_ERROR_FILES" \
      | sort -u | grep -v '^$' || true)

    strip_file() {
      local file="$1"
      local ext="''${file##*.}"
      case "$ext" in
        hs)
          perl -0777 -pe '
            my @pragmas;
            while ($_ =~ /(\{-#.*?#-\})/gs) { push @pragmas, $1; }
            s/\{-#.*?#-\}//gs;
            s/(\s*)--.*$/$1/gm;
            s/\{-(?!#).*?-\}//gs;
            if (@pragmas) {
              my %seen;
              @pragmas = grep { !$seen{$_}++ } @pragmas;
              $_ = join("\n", @pragmas) . "\n\n" . $_;
            }
          ' "$file" | cat -s | sed 's/[[:space:]]*$//'
          ;;
        purs)
          sed 's/\([ ]*\)--.*$/\1/' "$file" | \
          perl -0777 -pe 's/\{-.*?-\}//gs' | \
          cat -s | sed 's/[[:space:]]*$//'
          ;;
        nix)
          sed 's/\([ ]*\)#.*$/\1/' "$file" | \
          perl -0777 -pe 's!/\*[^*]*\*+(?:[^/][^*]*\*+)*/!!gs' | \
          cat -s | sed 's/[[:space:]]*$//'
          ;;
        *)
          cat "$file"
          ;;
      esac
    }

    emit_file_block() {
      local file="$1"
      local full_path="$PROJECT_ROOT/$file"
      [ -f "$full_path" ] || return 0
      local ext="''${file##*.}"
      echo "### \`$file\`"
      echo ""
      echo "\`\`\`$ext"
      if [ "$NO_STRIP" = false ]; then
        strip_file "$full_path"
      else
        cat "$full_path"
      fi
      echo "\`\`\`"
      echo ""
    }

    LAST_COMMIT=$(git -C "$PROJECT_ROOT" log -1 --oneline 2>/dev/null || echo "no commits")
    OUT_FILE="$OUTPUT_DIR/LLMContext_''${TIMESTAMP}''${OVERALL_STATUS}.md"
    tmp_out=$(mktemp)

    {
      echo "# LLM Context"
      echo ""
      echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
      echo "Last commit: \`$LAST_COMMIT\`"
      echo ""

      echo "## Summary"
      echo ""
      if [ -n "$BASE_REF" ] && [ -n "$COMPARE_REF" ]; then
        echo "Comparing: \`$BASE_REF\` ... \`$COMPARE_REF\`"
      elif [ -n "$BASE_REF" ]; then
        echo "Comparing: \`$BASE_REF\` vs working tree"
      else
        echo "Comparing: HEAD vs working tree"
      fi
      echo "Changed files: **$CHANGED_COUNT**"
      [ -n "$HS_STATUS" ] && echo "Haskell compile: **''${HS_STATUS#_}**"
      [ -n "$PS_STATUS" ] && echo "PureScript compile: **''${PS_STATUS#_}**"
      [ "$NO_COMPILE" = true ] && echo "Compile: skipped (--no-compile)"
      echo ""

      echo "## Changed Files"
      echo ""
      echo '```'
      echo "$ALL_MANIFEST_CHANGED"
      echo '```'
      echo ""

      if [ -n "$HS_COMPILE_OUTPUT" ]; then
        echo "## Haskell Build Output"
        echo ""
        echo '```'
        echo "$HS_COMPILE_OUTPUT"
        echo '```'
        echo ""
      fi

      if [ -n "$PS_COMPILE_OUTPUT" ]; then
        echo "## PureScript Build Output"
        echo ""
        echo '```'
        echo "$PS_COMPILE_OUTPUT"
        echo '```'
        echo ""
      fi

      if [ -n "$ALL_ERROR_FILES" ]; then
        echo "## Files With Errors"
        echo ""
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          emit_file_block "$f"
        done <<< "$ALL_ERROR_FILES"
      fi

      if [ "$FILES_ONLY" = false ]; then
        echo "## Diff"
        echo ""
        echo '```diff'
        while IFS= read -r f; do
          [ -z "$f" ] && continue
          if [ -n "$BASE_REF" ] && [ -n "$COMPARE_REF" ]; then
            git -C "$PROJECT_ROOT" diff "''${BASE_REF}...''${COMPARE_REF}" -U10 -- "$f" 2>/dev/null || true
          elif [ -n "$BASE_REF" ]; then
            git -C "$PROJECT_ROOT" diff "''${BASE_REF}" -U10 -- "$f" 2>/dev/null || true
          else
            git -C "$PROJECT_ROOT" diff HEAD -U10 -- "$f" 2>/dev/null || true
          fi
        done <<< "$ALL_MANIFEST_CHANGED"
        echo '```'
        echo ""
      fi

      if [ "$DIFF_ONLY" = false ]; then
        NON_ERROR_FILES=$(echo "$ALL_MANIFEST_CHANGED" \
          | grep -vxFf <(echo "$ALL_ERROR_FILES") || true)
        if [ -n "$NON_ERROR_FILES" ]; then
          if [ -n "$ALL_ERROR_FILES" ]; then
            echo "## Remaining Changed Files"
          else
            echo "## Changed Files"
          fi
          echo ""
          while IFS= read -r f; do
            [ -z "$f" ] && continue
            emit_file_block "$f"
          done <<< "$NON_ERROR_FILES"
        fi
      fi

    } > "$tmp_out"

    mv "$tmp_out" "$OUT_FILE"
    echo "Generated: $(basename "$OUT_FILE")"
  '';

  run-codegen = pkgs.writeShellScriptBin "run-codegen" ''
    set -euo pipefail
    cd "${frontendPath}"
    echo "Running PureScript codegen..."
    spago run --main Codegen.Run
    echo "Codegen complete."
  '';

in {
  inherit compile-manifest compile-archive llm-context run-codegen;
}
