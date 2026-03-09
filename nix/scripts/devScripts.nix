
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
        local temp_file=$(mktemp)

        (cd "$project_dir/$BACKEND_DIR" && cabal build) > "$temp_file" 2>&1
        local build_status=$?

        echo "{-"
        if [ -s "$temp_file" ]; then
            if [ $build_status -eq 0 ]; then
                echo "COMPILE_STATUS: true"
                echo "BUILD_OUTPUT:"
                cat "$temp_file"
            else
                echo "COMPILE_STATUS: false"
                echo "BUILD_OUTPUT:"
                cat "$temp_file"
            fi
        else
            echo "COMPILE_STATUS: error"
            echo "BUILD_OUTPUT:"
            echo "No build output captured"
        fi
        echo "-}"
        rm "$temp_file"
    }

    compile_purescript() {
        local project_dir=$1
        local temp_file=$(mktemp)

        if timeout 60 bash -c "cd '$project_dir/$FRONTEND_DIR' && spago build" > "$temp_file" 2>&1; then
            build_status=0
        else
            build_status=$?
            if [ $build_status -eq 124 ]; then
                echo "COMPILE_STATUS: error" > "$temp_file"
                echo "BUILD_OUTPUT:" >> "$temp_file"
                echo "Build process timed out after 60 seconds" >> "$temp_file"
            fi
        fi

        echo "{-"
        if [ $build_status -eq 0 ]; then
            echo "COMPILE_STATUS: true"
        else
            echo "COMPILE_STATUS: false"
            echo "COMPILE_ERROR:"
            cat "$temp_file"
        fi
        echo "-}"
        rm "$temp_file"
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
            while ($_ =~ /(\{-# \w+ [^#]*#-\})/g) {
                push @pragmas, $1;
            }
            s/\{-# \w+ [^#]*#-\}//g;
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

    get_status_for_filename() {
        local content="$1"
        if echo "$content" | grep -q "COMPILE_STATUS: true"; then
            echo "_OK"
        elif echo "$content" | grep -q "COMPILE_STATUS: false"; then
            echo "_ERR"
        else
            echo ""
        fi
    }

    safe_archive() {
        local ext="$1"
        local pattern="*.$ext"
        local found
        found=$(find "$OUTPUT_DIR" -maxdepth 1 -name "$pattern" 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            mv "$OUTPUT_DIR"/*."$ext" "$ARCHIVE_DIR/" 2>/dev/null || true
        fi
    }

    # concatenate_files <section_key> <output_base> <clean_fn> <comment_char> <compile_fn>
    # section_key matches the JSON manifest key: haskell | haskellTests | purescript | purescriptTests | nix
    concatenate_files() {
        local section_key="$1"
        local output_base="$2"
        local clean_function="$3"
        local comment_char="$4"
        local compile_fn="$5"

        local file_ext
        case "$section_key" in
            haskell|haskellTests)   file_ext="hs"   ;;
            purescript|purescriptTests) file_ext="purs" ;;
            nix)                    file_ext="nix"  ;;
        esac

        # Read file list from manifest
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
            echo "No changes in $section_key files since last run, skipping."
            return
        fi

        # Only archive existing outputs for this extension now that we know we'll regenerate
        safe_archive "$file_ext"

        local compile_output=""
        if [ -n "$compile_fn" ]; then
            compile_output=$($compile_fn "$PROJECT_ROOT")
        fi

        local temp_file
        temp_file=$(mktemp)

        {
            echo "$comment_char$comment_char"
            echo "$comment_char$comment_char Generated: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "$comment_char$comment_char Section: $section_key"
            total=$(echo "$file_list" | wc -l)
            echo "$comment_char$comment_char Files from manifest: $total"
            echo "$comment_char$comment_char"
            echo ""

            if [ -n "$compile_output" ]; then
                echo "$compile_output"
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
        } > "$temp_file"

        local status
        status=$(get_status_for_filename "$(cat "$temp_file")")
        local output_file="''${output_base}''${status}.$file_ext"
        mv "$temp_file" "$output_file"

        save_current_hash "$section_key" "$current_hash"
        echo "Generated $output_file"
    }

    # ── Output base paths ──────────────────────────────────────────────────────

    hs_base="''${OUTPUT_DIR}/Haskell_''${TIMESTAMP}"
    hs_tests_base="''${OUTPUT_DIR}/HaskellTests_''${TIMESTAMP}"
    purs_base="''${OUTPUT_DIR}/PureScript_''${TIMESTAMP}"
    purs_tests_base="''${OUTPUT_DIR}/PureScriptTests_''${TIMESTAMP}"
    nix_base="''${OUTPUT_DIR}/Nix_''${TIMESTAMP}"

    echo -e "\nProcessing files according to manifest..."

    concatenate_files "haskell"          "$hs_base"         "clean_haskell"            "--" "compile_haskell"
    concatenate_files "haskellTests"     "$hs_tests_base"   "clean_haskell"            "--" ""
    concatenate_files "purescript"       "$purs_base"       "clean_haskell_purescript" "--" "compile_purescript"
    concatenate_files "purescriptTests"  "$purs_tests_base" "clean_haskell_purescript" "--" ""
    concatenate_files "nix"              "$nix_base"        "clean_nix"                "#"  ""

    echo "Concatenation complete. Output files are in $OUTPUT_DIR"
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
            while ($_ =~ /(\{-# \w+ [^#]*#-\})/g) {
                push @pragmas, $1;
            }
            s/\{-# \w+ [^#]*#-\}//g;
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

    # ── Collect source files ───────────────────────────────────────────────────

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

    # ── Write output files ─────────────────────────────────────────────────────

    write_archive() {
        local output_file="$1"
        local label="$2"
        local file_list="$3"
        local clean_fn="$4"
        local comment_char="$5"
        local ext="$6"

        local count
        count=$(echo $file_list | wc -w)

        {
            echo "$comment_char$comment_char"
            echo "$comment_char$comment_char FULL PROJECT ARCHIVE — $label"
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
        "$OUTPUT_DIR/Haskell_ARCHIVE_$TIMESTAMP.hs"         "Haskell Sources"       "$hs_files"      "clean_haskell"    "--"  "hs"
    write_archive \
        "$OUTPUT_DIR/HaskellTests_ARCHIVE_$TIMESTAMP.hs"    "Haskell Tests"         "$hs_test_files" "clean_haskell"    "--"  "hs"
    write_archive \
        "$OUTPUT_DIR/PureScript_ARCHIVE_$TIMESTAMP.purs"    "PureScript Sources"    "$ps_files"      "clean_purescript" "--"  "purs"
    write_archive \
        "$OUTPUT_DIR/PureScriptTests_ARCHIVE_$TIMESTAMP.purs" "PureScript Tests"    "$ps_test_files" "clean_purescript" "--"  "purs"
    write_archive \
        "$OUTPUT_DIR/Nix_ARCHIVE_$TIMESTAMP.nix"            "Nix"                   "$nix_files"     "clean_nix"        "#"   "nix"

    echo ""
    echo "Full archive complete. Files in $OUTPUT_DIR"
    echo "  Haskell src:    $(echo $hs_files      | wc -w) files"
    echo "  Haskell tests:  $(echo $hs_test_files | wc -w) files"
    echo "  PureScript src: $(echo $ps_files      | wc -w) files"
    echo "  PureScript tests: $(echo $ps_test_files | wc -w) files"
    echo "  Nix:            $(echo $nix_files     | wc -w) files"
  '';

  run-codegen = pkgs.writeShellScriptBin "run-codegen" ''

    set -euo pipefail
    cd "${frontendPath}"
    echo "Running PureScript codegen..."
    spago run --main Codegen.Run
    echo "Codegen complete."
  '';

in {
  inherit compile-manifest compile-archive run-codegen;
}
