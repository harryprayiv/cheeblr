{ pkgs, name, lib, backendPath, frontendPath, hsDirs, psDirs, hsTestDirs ? [], psTestDirs ? [], hsConfig }:

let

  compile-manifest = pkgs.writeShellScriptBin "compile-manifest" ''

    set -euo pipefail

    BACKEND_DIR="${backendPath}"
    FRONTEND_DIR="${frontendPath}"
    HS_DIRS="${lib.concatStringsSep " " hsDirs}"
    PS_DIRS="${lib.concatStringsSep " " psDirs}"
    HS_TEST_DIRS="${lib.concatStringsSep " " hsTestDirs}"
    PS_TEST_DIRS="${lib.concatStringsSep " " psTestDirs}"

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
        echo "Manifest file not found at $MANIFEST_FILE"
        echo "Run 'generate-manifest' to create it first."
        exit 1
    fi

    calculate_hash() {
        local file_list="$1"
        if [ -z "$file_list" ]; then
            echo "empty"
            return
        fi
        echo "$file_list" | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1
    }

    get_previous_hash() {
        local file_type=$1
        local hash_file="$HASH_DIR/''${file_type}_last_hash"
        if [ -f "$hash_file" ]; then
            cat "$hash_file"
        else
            echo ""
        fi
    }

    save_current_hash() {
        local file_type=$1
        local current_hash=$2
        echo "$current_hash" > "$HASH_DIR/''${file_type}_last_hash"
    }

    compile_haskell() {
        local project_dir=$1
        local tmp
        tmp=$(mktemp)
        (cd "$project_dir/$BACKEND_DIR" && cabal build) > "$tmp" 2>&1
        local rc=$?
        if [ $rc -eq 0 ]; then
            echo "COMPILE_STATUS: true"
        else
            echo "COMPILE_STATUS: false"
        fi
        echo "BUILD_OUTPUT:"
        cat "$tmp"
        rm "$tmp"
    }

    compile_purescript() {
        local project_dir=$1
        local tmp
        tmp=$(mktemp)
        if timeout 60 bash -c "cd '$project_dir/$FRONTEND_DIR' && spago build" > "$tmp" 2>&1; then
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

    clean_haskell_purescript() {
        sed 's/\([ ]*\)--.*$/\1/' | \
        perl -0777 -pe 's/\{-.*?-\}//gs' | \
        cat -s | \
        sed 's/[[:space:]]*$//'
    }

    clean_haskell() {
        perl -0777 -pe '
            my @pragmas;
            while ($_ =~ /(\{-#[^#]*?#-\})/gs) {
                push @pragmas, $1;
            }
            s/\{-#[^#]*?#-\}\n?//gs;
            s/(\s*)--.*$/$1/gm;
            s/\{-(?!#).*?-\}//gs;
            if (@pragmas) {
                my %seen;
                @pragmas = grep { !$seen{$_}++ } @pragmas;
                my $pragma_text = join("\n", @pragmas);
                $_ = "$pragma_text\n\n$_";
            }
        ' | cat -s | sed 's/[[:space:]]*$//'
    }

    clean_nix() {
        sed 's/\([ ]*\)#.*$/\1/' | \
        perl -0777 -pe 's!/\*[^*]*\*+(?:[^/][^*]*\*+)*/!!gs' | \
        cat -s | \
        sed 's/[[:space:]]*$//' | \
        sed 's/\([ ]*\){[[:space:]]*}/\1{ }/'
    }

    get_relative_path() {
        local full_path=$1
        echo "''${full_path#$PROJECT_ROOT/}"
    }

    # Derive _OK / _ERR / "" directly from compile output.
    # Never re-read the output file to determine this.
    compile_status_suffix() {
        local output="$1"
        if [ -z "$output" ]; then
            echo ""
        elif echo "$output" | grep -q "^COMPILE_STATUS: true"; then
            echo "_OK"
        elif echo "$output" | grep -q "^COMPILE_STATUS: false"; then
            echo "_ERR"
        else
            echo ""
        fi
    }

    # Return the subset of file_list entries mentioned in compiler error output.
    extract_error_files() {
        local compile_output="$1"
        local ext="$2"
        local file_list="$3"
        echo "$compile_output" | grep -q "^COMPILE_STATUS: false" || return 0
        local candidates
        candidates=$(echo "$compile_output" | grep -oE "[a-zA-Z0-9_./-]+\.$ext" | sort -u || true)
        [ -z "$candidates" ] && return 0
        while IFS= read -r raw; do
            [ -z "$raw" ] && continue
            # Normalize: strip project root prefix and leading ./
            local candidate="''${raw#$PROJECT_ROOT/}"
            candidate="''${candidate#./}"
            while IFS= read -r listed; do
                [ -z "$listed" ] && continue
                local listed_norm="''${listed#./}"
                if [[ "$listed_norm" == "$candidate" ]] || [[ "$listed_norm" == *"/$candidate" ]]; then
                    echo "$listed"
                fi
            done <<< "$file_list"
        done <<< "$candidates" | sort -u
    }

    safe_archive() {
        local prefix="$1"
        local ext="$2"
        find "$OUTPUT_DIR" -maxdepth 1 -name "''${prefix}*.$ext" 2>/dev/null \
            | xargs -r mv -t "$ARCHIVE_DIR/" 2>/dev/null || true
    }

    concatenate_files() {
        local section_key="$1"
        local output_base="$2"
        local clean_function="$3"
        local comment_char="$4"
        local compile_fn="$5"

        local file_ext file_prefix
        case "$section_key" in
            haskell)            file_ext="hs";   file_prefix="Haskell_" ;;
            haskellTests)       file_ext="hs";   file_prefix="HaskellTests_" ;;
            purescript)         file_ext="purs"; file_prefix="PureScript_" ;;
            purescriptTests)    file_ext="purs"; file_prefix="PureScriptTests_" ;;
            nix)                file_ext="nix";  file_prefix="Nix_" ;;
        esac

        local file_list
        file_list=$(${pkgs.jq}/bin/jq -r ".\"$section_key\".include[]?" "$MANIFEST_FILE" 2>/dev/null || true)

        if [ -z "$file_list" ]; then
            echo "No files found for section '$section_key' in manifest, skipping."
            return
        fi

        local current_hash
        current_hash=$(calculate_hash "$file_list")
        local previous_hash
        previous_hash=$(get_previous_hash "$section_key")

        if [ "$current_hash" = "$previous_hash" ]; then
            # Content unchanged. Rename with current timestamp, preserve status suffix.
            local existing
            existing=$(find "$OUTPUT_DIR" -maxdepth 1 -name "''${file_prefix}*.$file_ext" 2>/dev/null | head -1)
            if [ -n "$existing" ]; then
                local old_base
                old_base=$(basename "$existing" ".$file_ext")
                local preserved_status=""
                [[ "$old_base" == *_OK  ]] && preserved_status="_OK"
                [[ "$old_base" == *_ERR ]] && preserved_status="_ERR"
                local new_name="''${output_base}''${preserved_status}.$file_ext"
                mv "$existing" "$new_name"
                echo "No content changes in $section_key -- refreshed timestamp: $(basename "$new_name")"
                return
            fi
            echo "No existing output for $section_key despite matching hash -- regenerating."
        fi

        # Run compilation before writing anything.
        local compile_output=""
        if [ -n "$compile_fn" ]; then
            echo "  Compiling $section_key ..."
            compile_output=$($compile_fn "$PROJECT_ROOT")
        fi

        # Status determined here, from compile_output, not from the output file.
        local status
        status=$(compile_status_suffix "$compile_output")

        local error_files=""
        if [ -n "$compile_output" ]; then
            error_files=$(extract_error_files "$compile_output" "$file_ext" "$file_list")
        fi

        local tmp
        tmp=$(mktemp)

        {
            echo "$comment_char$comment_char"
            echo "$comment_char$comment_char Generated: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "$comment_char$comment_char Section: $section_key"
            local total
            total=$(echo "$file_list" | wc -l)
            echo "$comment_char$comment_char Files: $total"
            [ -n "$status" ] && echo "$comment_char$comment_char Compile status: $status"
            echo "$comment_char$comment_char"
            echo ""

            if [ -n "$compile_output" ]; then
                echo "{-"
                echo "$compile_output"
                echo "-}"
                echo ""
            fi

            if [ -n "$error_files" ]; then
                echo "$comment_char$comment_char ---- FILES WITH ERRORS (listed first) ----"
                echo ""
                while IFS= read -r err_file; do
                    [ -z "$err_file" ] && continue
                    local fp="$PROJECT_ROOT/$err_file"
                    if [ -f "$fp" ]; then
                        echo "$comment_char FILE: $err_file"
                        cat "$fp" | eval "$clean_function"
                        echo "$comment_char END OF: $err_file"
                        echo ""
                    fi
                done <<< "$error_files"
                echo "$comment_char$comment_char ---- ALL FILES ----"
                echo ""
            fi

            while IFS= read -r file; do
                local full_path="$PROJECT_ROOT/$file"
                if [ -f "$full_path" ]; then
                    echo "$comment_char FILE: $file"
                    cat "$full_path" | eval "$clean_function"
                    echo "$comment_char END OF: $file"
                    echo ""
                else
                    echo "$comment_char WARNING: File not found: $file"
                    echo ""
                fi
            done <<< "$file_list"
        } > "$tmp"

        local output_file="''${output_base}''${status}.$file_ext"
        mv "$tmp" "$output_file"
        save_current_hash "$section_key" "$current_hash"
        echo "Generated $(basename "$output_file")"
    }

    hs_base="''${OUTPUT_DIR}/Haskell_''${TIMESTAMP}"
    hs_tests_base="''${OUTPUT_DIR}/HaskellTests_''${TIMESTAMP}"
    purs_base="''${OUTPUT_DIR}/PureScript_''${TIMESTAMP}"
    purs_tests_base="''${OUTPUT_DIR}/PureScriptTests_''${TIMESTAMP}"
    nix_base="''${OUTPUT_DIR}/Nix_''${TIMESTAMP}"

    echo -e "\nProcessing files according to manifest..."

    concatenate_files "haskell"         "$hs_base"         "clean_haskell"            "--" "compile_haskell"
    concatenate_files "haskellTests"    "$hs_tests_base"   "clean_haskell"            "--" ""
    concatenate_files "purescript"      "$purs_base"       "clean_haskell_purescript" "--" "compile_purescript"
    concatenate_files "purescriptTests" "$purs_tests_base" "clean_haskell_purescript" "--" ""
    concatenate_files "nix"             "$nix_base"        "clean_nix"                "#"  ""

    echo "Done. Output files are in $OUTPUT_DIR"
  '';


  compile-archive = pkgs.writeShellScriptBin "compile-archive" ''

    set -euo pipefail

    BACKEND_DIR="${backendPath}"
    FRONTEND_DIR="${frontendPath}"
    HS_DIRS="${lib.concatStringsSep " " hsDirs}"
    PS_DIRS="${lib.concatStringsSep " " psDirs}"
    HS_TEST_DIRS="${lib.concatStringsSep " " hsTestDirs}"
    PS_TEST_DIRS="${lib.concatStringsSep " " psTestDirs}"

    PROJECT_ROOT="$(pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/script"
    BASE_DIR="$SCRIPT_DIR/concat_archive"
    OUTPUT_DIR="$BASE_DIR/output"
    mkdir -p "$OUTPUT_DIR"

    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

    echo "Creating full project archive (IGNORING manifest)..."

    clean_haskell() {
        perl -0777 -pe '
            my @pragmas;
            while ($_ =~ /(\{-#[^#]*?#-\})/gs) {
                push @pragmas, $1;
            }
            s/\{-#[^#]*?#-\}\n?//gs;
            s/(\s*)--.*$/$1/gm;
            s/\{-(?!#).*?-\}//gs;
            if (@pragmas) {
                my %seen;
                @pragmas = grep { !$seen{$_}++ } @pragmas;
                my $pragma_text = join("\n", @pragmas);
                $_ = "$pragma_text\n\n$_";
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
        cat -s | sed 's/[[:space:]]*$//'
    }

    get_relative_path() {
        local full_path=$1
        echo "''${full_path#$PROJECT_ROOT/}"
    }

    collect_files() {
        local base_dir="$1"
        local sub_dirs="$2"
        local ext="$3"
        local out_var="$4"
        local files=""
        for dir in $sub_dirs; do
            local full_dir="$PROJECT_ROOT/$base_dir/$dir"
            if [ -d "$full_dir" ]; then
                while IFS= read -r -d "" f; do
                    files="$files $f"
                done < <(find "$full_dir" -name "*.$ext" -type f -print0 | sort -z)
            fi
        done
        eval "$out_var='$files'"
    }

    echo "Scanning ALL Haskell source files..."
    collect_files "$BACKEND_DIR" "$HS_DIRS" "hs" hs_files

    echo "Scanning ALL Haskell test files..."
    collect_files "$BACKEND_DIR" "$HS_TEST_DIRS" "hs" hs_test_files

    echo "Scanning ALL PureScript source files..."
    collect_files "$FRONTEND_DIR" "$PS_DIRS" "purs" ps_files

    echo "Scanning ALL PureScript test files..."
    collect_files "$FRONTEND_DIR" "$PS_TEST_DIRS" "purs" ps_test_files

    echo "Scanning ALL Nix files..."
    nix_files=""
    while IFS= read -r -d "" f; do
      nix_files="$nix_files $f"
    done < <(find "$PROJECT_ROOT" -maxdepth 1 -name "*.nix" -type f -print0 | sort -z)
    if [ -d "$PROJECT_ROOT/nix" ]; then
      while IFS= read -r -d "" f; do
        nix_files="$nix_files $f"
      done < <(find "$PROJECT_ROOT/nix" -name "*.nix" -type f -print0 | sort -z)
    fi

    write_archive() {
        local output_file="$1"
        local label="$2"
        local file_list="$3"
        local clean_fn="$4"
        local comment_char="$5"
        local count
        count=$(echo $file_list | wc -w)
        {
            echo "$comment_char$comment_char"
            echo "$comment_char$comment_char FULL PROJECT ARCHIVE -- $label"
            echo "$comment_char$comment_char Generated: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "$comment_char$comment_char Files: $count  (manifest IGNORED)"
            echo "$comment_char$comment_char"
            echo ""
            for file in $file_list; do
                if [ -f "$file" ]; then
                    echo "$comment_char FILE: $(get_relative_path "$file")"
                    cat "$file" | $clean_fn
                    echo "$comment_char END OF: $(get_relative_path "$file")"
                    echo ""
                fi
            done
        } > "$output_file"
        echo "Created: $output_file  ($count files)"
    }

    write_archive \
        "$OUTPUT_DIR/Haskell_ARCHIVE_$TIMESTAMP.hs"           "Haskell Sources"     "$hs_files"      "clean_haskell"    "--"
    write_archive \
        "$OUTPUT_DIR/HaskellTests_ARCHIVE_$TIMESTAMP.hs"      "Haskell Tests"       "$hs_test_files" "clean_haskell"    "--"
    write_archive \
        "$OUTPUT_DIR/PureScript_ARCHIVE_$TIMESTAMP.purs"      "PureScript Sources"  "$ps_files"      "clean_purescript" "--"
    write_archive \
        "$OUTPUT_DIR/PureScriptTests_ARCHIVE_$TIMESTAMP.purs" "PureScript Tests"    "$ps_test_files" "clean_purescript" "--"
    write_archive \
        "$OUTPUT_DIR/Nix_ARCHIVE_$TIMESTAMP.nix"              "Nix"                 "$nix_files"     "clean_nix"        "#"

    echo ""
    echo "Full archive complete. Files in $OUTPUT_DIR"
    echo "  Haskell src:      $(echo $hs_files      | wc -w) files"
    echo "  Haskell tests:    $(echo $hs_test_files | wc -w) files"
    echo "  PureScript src:   $(echo $ps_files      | wc -w) files"
    echo "  PureScript tests: $(echo $ps_test_files | wc -w) files"
    echo "  Nix:              $(echo $nix_files     | wc -w) files"
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

    # ── Flags ──────────────────────────────────────────────────────────────────
    DIFF_ONLY=false
    FILES_ONLY=false
    NO_COMPILE=false
    NO_STRIP=false

    for arg in "''${@}"; do
        case "$arg" in
            --diff-only)  DIFF_ONLY=true ;;
            --files-only) FILES_ONLY=true ;;
            --no-compile) NO_COMPILE=true ;;
            --no-strip)   NO_STRIP=true ;;
            --help)
                echo "Usage: llm-context [OPTIONS]"
                echo ""
                echo "Generates an LLM-optimized context file from files changed"
                echo "since the last git commit (staged + unstaged)."
                echo ""
                echo "Options:"
                echo "  --diff-only   Git diff only, no full file contents"
                echo "  --files-only  Full file contents only, no git diff"
                echo "  --no-compile  Skip compilation"
                echo "  --no-strip    Keep comments in file contents (default: stripped)"
                echo ""
                echo "Output: script/concat_archive/output/LLMContext_TIMESTAMP[_OK|_ERR].md"
                exit 0 ;;
            *)
                echo "Unknown flag: $arg  (try --help)"
                exit 1 ;;
        esac
    done

    # ── Sanity checks ──────────────────────────────────────────────────────────
    if [ ! -f "$MANIFEST_FILE" ]; then
        echo "No manifest at $MANIFEST_FILE -- run 'generate-manifest' first."
        exit 1
    fi

    if ! git -C "$PROJECT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
        echo "Not a git repository."
        exit 1
    fi

    # ── Find changed files ─────────────────────────────────────────────────────
    # git diff HEAD: all files differing from last commit (staged + unstaged combined).
    # Falls back to --cached only if HEAD doesn't exist (fresh repo, no commits yet).
    ALL_CHANGED=""
    if git -C "$PROJECT_ROOT" rev-parse HEAD > /dev/null 2>&1; then
        ALL_CHANGED=$(git -C "$PROJECT_ROOT" diff HEAD --name-only 2>/dev/null || true)
    else
        ALL_CHANGED=$(git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null || true)
    fi

    if [ -z "$ALL_CHANGED" ]; then
        echo "No changes detected since last commit."
        echo "Hint: use 'compile-manifest' for a full snapshot."
        exit 0
    fi

    # ── Filter to manifest-tracked files ──────────────────────────────────────
    # Manifest paths may carry a leading ./ -- strip it for comparison against
    # git output (which never has the ./ prefix).
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

    # ── Compile ────────────────────────────────────────────────────────────────
    HS_COMPILE_OUTPUT=""
    PS_COMPILE_OUTPUT=""
    HS_STATUS=""
    PS_STATUS=""

    compile_haskell_local() {
        local tmp
        tmp=$(mktemp)
        (cd "$PROJECT_ROOT/$BACKEND_DIR" && cabal build) > "$tmp" 2>&1
        local rc=$?
        if [ $rc -eq 0 ]; then echo "COMPILE_STATUS: true"
        else echo "COMPILE_STATUS: false"
        fi
        echo "BUILD_OUTPUT:"
        cat "$tmp"
        rm "$tmp"
    }

    compile_purescript_local() {
        local tmp
        tmp=$(mktemp)
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
        if [ -z "$out" ]; then echo ""; return; fi
        if echo "$out" | grep -q "^COMPILE_STATUS: true"; then echo "_OK"
        elif echo "$out" | grep -q "^COMPILE_STATUS: false"; then echo "_ERR"
        else echo ""
        fi
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

    # Overall status: ERR beats OK beats empty
    OVERALL_STATUS=""
    if [ "$HS_STATUS" = "_ERR" ] || [ "$PS_STATUS" = "_ERR" ]; then
        OVERALL_STATUS="_ERR"
    elif [ "$HS_STATUS" = "_OK" ] || [ "$PS_STATUS" = "_OK" ]; then
        OVERALL_STATUS="_OK"
    fi

    # ── Extract error files ────────────────────────────────────────────────────
    extract_error_files() {
        local output="$1"
        local ext="$2"
        local file_list="$3"
        [ -z "$output" ] && return 0
        echo "$output" | grep -q "^COMPILE_STATUS: false" || return 0
        local candidates
        candidates=$(echo "$output" | grep -oE "[a-zA-Z0-9_./-]+\.$ext" | sort -u || true)
        [ -z "$candidates" ] && return 0
        while IFS= read -r raw; do
            [ -z "$raw" ] && continue
            local candidate="''${raw#$PROJECT_ROOT/}"
            candidate="''${candidate#./}"
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

    # ── Comment stripping ──────────────────────────────────────────────────────
    strip_file() {
        local file="$1"
        local ext="''${file##*.}"
        case "$ext" in
            hs)
                perl -0777 -pe '
                    my @pragmas;
                    while ($_ =~ /(\{-#[^#]*?#-\})/gs) { push @pragmas, $1; }
                    s/\{-#[^#]*?#-\}\n?//gs;
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
        echo "\`\`\`$ext"
        if [ "$NO_STRIP" = false ]; then
            strip_file "$full_path"
        else
            cat "$full_path"
        fi
        echo "\`\`\`"
        echo ""
    }

    # ── Write output ───────────────────────────────────────────────────────────
    LAST_COMMIT=$(git -C "$PROJECT_ROOT" log -1 --oneline 2>/dev/null || echo "no commits")
    OUT_FILE="$OUTPUT_DIR/LLMContext_''${TIMESTAMP}''${OVERALL_STATUS}.md"
    tmp_out=$(mktemp)

    {
        echo "# LLM Context -- ${name}"
        echo ""
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Last commit: \`$LAST_COMMIT\`"
        echo ""

        echo "## Summary"
        echo ""
        echo "Changed files since last commit: **$CHANGED_COUNT**"
        [ -n "$HS_STATUS"   ] && echo "Haskell compile: **$HS_STATUS**"
        [ -n "$PS_STATUS"   ] && echo "PureScript compile: **$PS_STATUS**"
        [ "$NO_COMPILE" = true ] && echo "Compile: skipped (--no-compile)"
        echo ""

        echo "## Changed Files"
        echo ""
        echo '```'
        echo "$ALL_MANIFEST_CHANGED"
        echo '```'
        echo ""

        # Compile output sections
        if [ -n "$HS_COMPILE_OUTPUT" ]; then
            echo "## Haskell Compile Output ($HS_STATUS)"
            echo ""
            echo '```'
            echo "$HS_COMPILE_OUTPUT"
            echo '```'
            echo ""
        fi

        if [ -n "$PS_COMPILE_OUTPUT" ]; then
            echo "## PureScript Compile Output ($PS_STATUS)"
            echo ""
            echo '```'
            echo "$PS_COMPILE_OUTPUT"
            echo '```'
            echo ""
        fi

        # Error files -- always shown first and in full regardless of other flags
        if [ -n "$ALL_ERROR_FILES" ]; then
            echo "## Files With Errors"
            echo ""
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                emit_file_block "$f"
            done <<< "$ALL_ERROR_FILES"
        fi

        # Git diff
        if [ "$FILES_ONLY" = false ]; then
            echo "## Git Diff (vs last commit)"
            echo ""
            echo '```diff'
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                git -C "$PROJECT_ROOT" diff HEAD -U10 -- "$f" 2>/dev/null || true
            done <<< "$ALL_MANIFEST_CHANGED"
            echo '```'
            echo ""
        fi

        # Full file contents (excluding error files already shown above)
        if [ "$DIFF_ONLY" = false ]; then
            # Determine whether there are any non-error files to show
            NON_ERROR_FILES=$(echo "$ALL_MANIFEST_CHANGED" | grep -vxFf <(echo "$ALL_ERROR_FILES") || true)
            if [ -n "$NON_ERROR_FILES" ]; then
                if [ -n "$ALL_ERROR_FILES" ]; then
                    echo "## Remaining Changed Files"
                else
                    echo "## Changed File Contents"
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
