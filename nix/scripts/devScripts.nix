# devScripts.nix - Direct approach to file processing
{ pkgs, name, lib, backendPath, frontendPath, hsDirs, psDirs, hsConfig }:

let
  # compile-manifest: ONLY processes files listed in manifest.json (plus error files)
  compile-manifest = pkgs.writeShellScriptBin "compile-manifest" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    # Configuration
    BACKEND_DIR="${backendPath}"
    FRONTEND_DIR="${frontendPath}"
    HS_DIRS="${lib.concatStringsSep " " hsDirs}"
    PS_DIRS="${lib.concatStringsSep " " psDirs}"
    
    # Setup paths
    PROJECT_ROOT="$(pwd)"
    SCRIPT_DIR="$PROJECT_ROOT/script"
    MANIFEST_FILE="$SCRIPT_DIR/manifest.json"
    BASE_DIR="$SCRIPT_DIR/concat_archive"
    HASH_DIR="$BASE_DIR/.hashes"
    OUTPUT_DIR="$BASE_DIR/output"
    ARCHIVE_DIR="$BASE_DIR/archive"
    mkdir -p "$OUTPUT_DIR" "$ARCHIVE_DIR" "$HASH_DIR"
    
    TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
    
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
            while ($_ =~ /(\{-#\s+LANGUAGE\s+[^#]*?#-\})/gs) {
                push @pragmas, $1;
            }
            s/\{-#\s+LANGUAGE\s+[^#]*?#-\}\n?//gs;
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
        perl -0777 -pe 's!/\*[^*]*\*+(?:[^/*][^*]*\*+)*/!!gs' | \
        cat -s | \
        sed 's/[[:space:]]*$//' | \
        sed 's/\([ ]*\){[[:space:]]*}/\1{ }/'
    }
    
    get_relative_path() {
        local full_path=$1
        echo "''${full_path#$PROJECT_ROOT/}"
    }
    
    extract_error_files() {
        local compile_output="$1"
        local file_type="$2"
        local error_files=""
        local temp_file=$(mktemp)
        
        echo "$compile_output" > "$temp_file"
        
        if [ "$file_type" = "purs" ]; then
            while IFS= read -r line; do
                if [[ $line =~ \[ERROR[[:space:]].*\][[:space:]]([^:]+): ]]; then
                    local file="''${BASH_REMATCH[1]}"
                    if [[ $file == src/* ]]; then
                        file="$PROJECT_ROOT/$FRONTEND_DIR/$file"
                    fi
                    if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                        error_files="$error_files $file"
                    fi
                fi
            done < "$temp_file"
            
            if [ -z "$error_files" ]; then
                while IFS= read -r line; do
                    if [[ $line =~ "Could not match type" ]]; then
                        local context=$(grep -B 5 -A 5 "Could not match type" "$temp_file" | grep -o "src/[^[:space:]]*\.purs:[0-9]*")
                        if [[ $context =~ (src/[^:]+) ]]; then
                            local file="''${BASH_REMATCH[1]}"
                            if [[ $file == src/* ]]; then
                                file="$PROJECT_ROOT/$FRONTEND_DIR/$file"
                            fi
                            if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                                error_files="$error_files $file"
                            fi
                        fi
                    fi
                done < "$temp_file"
            fi
        elif [ "$file_type" = "hs" ]; then
            while IFS= read -r line; do
                if [[ $line =~ ^([^:]+\.hs):[0-9]+:[0-9]+: ]]; then
                    local file="''${BASH_REMATCH[1]}"
                    if [[ $file == src/* ]]; then
                        file="$PROJECT_ROOT/$BACKEND_DIR/$file"
                    elif [[ $file != /* ]]; then
                        file="$PROJECT_ROOT/$BACKEND_DIR/$file"
                    fi
                    if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                        error_files="$error_files $file"
                    fi
                fi
            done < "$temp_file"
            
            if [ -z "$error_files" ]; then
                while IFS= read -r line; do
                    if [[ $line =~ "Failed to build" ]]; then
                        local context=$(grep -B 5 "Failed to build" "$temp_file" | grep -o "src/[^[:space:]]*\.hs")
                        if [[ -n "$context" ]]; then
                            local file="$PROJECT_ROOT/$BACKEND_DIR/$context"
                            if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                                error_files="$error_files $file"
                            fi
                        fi
                    fi
                done < "$temp_file"
            fi
        fi
        
        rm "$temp_file"
        echo "$error_files"
    }
    
    # Get files from manifest ONLY
    get_included_files() {
        local file_type="$1"
        local section=""
        
        case "$file_type" in
            "purs") section="purescript" ;;
            "hs") section="haskell" ;;
            "nix") section="nix" ;;
            *) echo "Error: Unknown file type $file_type" >&2; return 1 ;;
        esac
        
        if [ ! -f "$MANIFEST_FILE" ]; then
            echo "Error: Manifest file not found at $MANIFEST_FILE" >&2
            echo "Run 'generate-manifest' to create it first" >&2
            return 1
        fi
        
        local include_files=$(${pkgs.jq}/bin/jq -r ".$section.include[]" "$MANIFEST_FILE" 2>/dev/null)
        local file_list=""
        
        while IFS= read -r rel_path; do
            if [ -n "$rel_path" ]; then
                file_list+=" $PROJECT_ROOT/$rel_path"
            fi
        done <<< "$include_files"
        
        echo "$file_list"
    }
    
    get_status_for_filename() {
        local file_content="$1"
        if grep -q "COMPILE_STATUS: true" <<< "$file_content"; then
            echo "[OK]"
        elif grep -q "COMPILE_STATUS: false" <<< "$file_content"; then
            echo "[FAIL]"
        elif grep -q "COMPILE_STATUS: error" <<< "$file_content"; then
            echo "[ERROR]"
        else
            echo "[NOCOMPILE]"
        fi
    }
    
    safe_archive() {
        local ext=$1
        local files=("$OUTPUT_DIR"/*."$ext")
        if [ -e "''${files[0]}" ]; then
            mv "$OUTPUT_DIR"/*."$ext" "$ARCHIVE_DIR/" 2>/dev/null || true
        fi
    }
    
    concatenate_files() {
        local file_type=$1
        local output_base=$2
        local clean_function=$3
        local comment_char=$4
        local compile_function=$5

        echo "Finding $file_type files from manifest..."
        
        local file_list=$(get_included_files "$file_type")
        local error_files=""
        local compile_output=""
        
        if [ -z "$file_list" ]; then
            echo "No $file_type files selected in manifest."
            return
        fi
        
        echo "Found $(echo "$file_list" | wc -w) $file_type files in manifest."

        local current_hash=$(calculate_hash "$file_list")
        local previous_hash=$(get_previous_hash "$file_type")

        local force_regenerate=false
        if [ ! -f "$OUTPUT_DIR"/*."$file_type" ]; then
            force_regenerate=true
        fi

        if [ "$force_regenerate" = false ] && [ -n "$previous_hash" ] && [ "$current_hash" = "$previous_hash" ]; then
            echo "No changes detected in $file_type files, reusing previous content..."
            local latest_file=$(ls -t "$OUTPUT_DIR"/*."$file_type" 2>/dev/null | head -n1)
            if [ -n "$latest_file" ]; then
                local content=$(cat "$latest_file")
                local status=$(get_status_for_filename "$content")
                local output_file="''${output_base}''${status}.$file_type"
                echo "$content" > "$output_file"
                echo "Copied existing $file_type file with status $status"
                return
            fi
        fi

        if [ -n "$compile_function" ]; then
            echo "Running compilation for $file_type..."
            compile_output=$(eval "$compile_function \"$PROJECT_ROOT\"")
            error_files=$(extract_error_files "$compile_output" "$file_type")
            
            if [ -n "$error_files" ]; then
                echo "Found $(echo "$error_files" | wc -w) files with errors."
            fi
        fi

        # Build final list: error files first (even if not in manifest), then manifest files
        local final_file_list=""
        
        if [ -n "$error_files" ]; then
            for error_file in $error_files; do
                if [[ ! $final_file_list =~ (^|[[:space:]])$error_file($|[[:space:]]) ]]; then
                    final_file_list="$final_file_list $error_file"
                fi
            done
        fi
        
        for file in $file_list; do
            if [[ ! $final_file_list =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                final_file_list="$final_file_list $file"
            fi
        done

        echo "Generating concatenated $file_type file..."
        
        local temp_file=$(mktemp)
        {
            if [ "$comment_char" = "--" ]; then
                echo "{-"
                echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "Hash: $current_hash"
                echo "Files from manifest: $(echo "$file_list" | wc -w)"
                if [ -n "$error_files" ]; then
                    echo "Error files added: $(echo "$error_files" | wc -w)"
                fi
                echo "-}"
            else
                echo "/*"
                echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
                echo "Hash: $current_hash"
                echo "Files from manifest: $(echo "$file_list" | wc -w)"
                echo "*/"
            fi
            echo ""
            
            if [ -n "$compile_output" ]; then
                echo "$compile_output"
                echo ""
            fi

            for file in $final_file_list; do
                if [ -f "$file" ]; then
                    echo "''${comment_char} FILE: $(get_relative_path "$file")"
                    cat "$file" | eval "$clean_function"
                    echo "''${comment_char} END OF: $(get_relative_path "$file")"
                    echo ""
                else
                    echo "''${comment_char} WARNING: File not found: $(get_relative_path "$file")"
                    echo ""
                fi
            done
        } > "$temp_file"

        local status=$(get_status_for_filename "$(cat "$temp_file")")
        local output_file="''${output_base}''${status}.$file_type"
        mv "$temp_file" "$output_file"

        save_current_hash "$file_type" "$current_hash"
        echo "Generated new $file_type file with status $status"
    }
    
    # Check manifest exists - do NOT auto-regenerate (user controls this)
    if [ ! -f "$MANIFEST_FILE" ]; then
        echo "Manifest file not found at $MANIFEST_FILE"
        echo "Run 'generate-manifest' to create it first."
        exit 1
    fi
    
    safe_archive "purs"
    safe_archive "hs"
    safe_archive "nix"
    
    purs_base="''${OUTPUT_DIR}/PureScript_''${TIMESTAMP}"
    hs_base="''${OUTPUT_DIR}/Haskell_''${TIMESTAMP}"
    nix_base="''${OUTPUT_DIR}/Nix_''${TIMESTAMP}"
    
    echo -e "\nProcessing files according to manifest..."
    
    concatenate_files "purs" "$purs_base" "clean_haskell_purescript" "--" "compile_purescript"
    concatenate_files "hs" "$hs_base" "clean_haskell" "--" "compile_haskell"
    concatenate_files "nix" "$nix_base" "clean_nix" "#" ""
    
    echo "Concatenation complete. Output files are in $OUTPUT_DIR"
  '';
  
  # compile-archive: Concatenates ALL files, IGNORING manifest entirely
  compile-archive = pkgs.writeShellScriptBin "compile-archive" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    BACKEND_DIR="${backendPath}"
    FRONTEND_DIR="${frontendPath}"
    HS_DIRS="${lib.concatStringsSep " " hsDirs}"
    PS_DIRS="${lib.concatStringsSep " " psDirs}"
    
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
            while ($_ =~ /(\{-#\s+LANGUAGE\s+[^#]*?#-\})/gs) {
                push @pragmas, $1;
            }
            s/\{-#\s+LANGUAGE\s+[^#]*?#-\}\n?//gs;
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
        perl -0777 -pe 's!/\*[^*]*\*+(?:[^/*][^*]*\*+)*/!!gs' | \
        cat -s | sed 's/[[:space:]]*$//'
    }
    
    get_relative_path() {
        local full_path=$1
        echo "''${full_path#$PROJECT_ROOT/}"
    }
    
    # Scan ALL Haskell files directly (not from manifest)
    echo "Scanning ALL Haskell files..."
    hs_files=""
    for dir in $HS_DIRS; do
      full_dir="$PROJECT_ROOT/$BACKEND_DIR/$dir"
      if [ -d "$full_dir" ]; then
        while IFS= read -r -d "" f; do
          hs_files="$hs_files $f"
        done < <(find "$full_dir" -name "*.hs" -type f -print0 | sort -z)
      fi
    done
    
    # Scan ALL PureScript files directly (not from manifest)
    echo "Scanning ALL PureScript files..."
    ps_files=""
    for dir in $PS_DIRS; do
      full_dir="$PROJECT_ROOT/$FRONTEND_DIR/$dir"
      if [ -d "$full_dir" ]; then
        while IFS= read -r -d "" f; do
          ps_files="$ps_files $f"
        done < <(find "$full_dir" -name "*.purs" -type f -print0 | sort -z)
      fi
    done
    
    # Scan ALL Nix files directly (not from manifest)
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
    
    # Generate Haskell archive
    hs_output="$OUTPUT_DIR/Haskell_ARCHIVE_$TIMESTAMP.hs"
    {
        echo "{-"
        echo "FULL PROJECT ARCHIVE - Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Contains ALL Haskell files (manifest IGNORED)"
        echo "Files: $(echo $hs_files | wc -w)"
        echo "-}"
        echo ""
        for file in $hs_files; do
            if [ -f "$file" ]; then
                echo "-- FILE: $(get_relative_path "$file")"
                cat "$file" | clean_haskell
                echo "-- END OF: $(get_relative_path "$file")"
                echo ""
            fi
        done
    } > "$hs_output"
    echo "Created: $hs_output"
    
    # Generate PureScript archive
    ps_output="$OUTPUT_DIR/PureScript_ARCHIVE_$TIMESTAMP.purs"
    {
        echo "{-"
        echo "FULL PROJECT ARCHIVE - Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Contains ALL PureScript files (manifest IGNORED)"
        echo "Files: $(echo $ps_files | wc -w)"
        echo "-}"
        echo ""
        for file in $ps_files; do
            if [ -f "$file" ]; then
                echo "-- FILE: $(get_relative_path "$file")"
                cat "$file" | clean_purescript
                echo "-- END OF: $(get_relative_path "$file")"
                echo ""
            fi
        done
    } > "$ps_output"
    echo "Created: $ps_output"
    
    # Generate Nix archive
    nix_output="$OUTPUT_DIR/Nix_ARCHIVE_$TIMESTAMP.nix"
    {
        echo "/*"
        echo "FULL PROJECT ARCHIVE - Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Contains ALL Nix files (manifest IGNORED)"
        echo "Files: $(echo $nix_files | wc -w)"
        echo "*/"
        echo ""
        for file in $nix_files; do
            if [ -f "$file" ]; then
                echo "# FILE: $(get_relative_path "$file")"
                cat "$file" | clean_nix
                echo "# END OF: $(get_relative_path "$file")"
                echo ""
            fi
        done
    } > "$nix_output"
    echo "Created: $nix_output"
    
    echo ""
    echo "Full archive complete. Files in $OUTPUT_DIR"
    echo "  Haskell: $(echo $hs_files | wc -w) files"
    echo "  PureScript: $(echo $ps_files | wc -w) files"
    echo "  Nix: $(echo $nix_files | wc -w) files"
  '';

  run-codegen = pkgs.writeShellScriptBin "run-codegen" ''
    #!/usr/bin/env bash
    set -euo pipefail
    cd "${frontendPath}"
    echo "Running PureScript codegen..."
    spago run --main Codegen.Run
    echo "Codegen complete."
  '';

in {
  inherit compile-manifest compile-archive run-codegen;
}