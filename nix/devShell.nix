{ pkgs, name, lib, system ? builtins.currentSystem }:

let
  # Import app config to use in all the scripts
  appConfig = import ./app-config.nix {
    inherit name;
  };
  
  # Extract configuration for different components
  psConfig = appConfig.purescript;
  hsConfig = appConfig.haskell;
  dbConfig = appConfig.database;
  viteConfig = appConfig.vite;
  
  # Helper function to convert list of directories to a space-separated string
  dirsToString = dirs: lib.concatStringsSep " " dirs;
  
  # Generate directory strings for scripts
  psDirs = dirsToString psConfig.codeDirs;
  hsDirs = dirsToString hsConfig.codeDirs;
  
  # Get frontend and backend directories
  frontendDir = builtins.match "(.*)/.*" (builtins.elemAt psConfig.codeDirs 0);
  frontendPath = if frontendDir == null then "./frontend" else builtins.elemAt frontendDir 0;
  
  backendDir = builtins.match "(.*)/.*" (builtins.elemAt hsConfig.codeDirs 0);
  backendPath = if backendDir == null then "./backend" else builtins.elemAt backendDir 0;

  postgresModule = import ./postgres-utils.nix {
    inherit pkgs name;
    # Pass database config to postgres module
    database = dbConfig;
  };

  frontendModule = import ./frontend.nix {
    inherit pkgs name;
    # Pass frontend config to frontend module
    frontend = {
      inherit (viteConfig) viteport settings;
      inherit (psConfig) codeDirs spagoFile;
    };
  };
  
  deployModule = import ./deploy.nix {
    inherit pkgs name;
  };

  # Define workspace utilities directly in this file
  workspaceModule = {
    code-workspace = pkgs.writeShellApplication {
      name = "code-workspace";
      runtimeInputs = with pkgs; [ vscodium ];
      text = ''
        codium ${name}.code-workspace
      '';
    };

    backup-project = pkgs.writeShellApplication {
      name = "backup-project";
      runtimeInputs = with pkgs; [ rsync ];
      text = ''
        rsync -va --delete --exclude-from='.gitignore' --exclude='.git/' ~/workdir/${name}/ ~/plutus/workspace/scdWs/${name}/
        rsync -va ~/.local/share/${name}/backups/ ~/plutus/${name}DB/
      '';
    };
  
    # Updated compile-archive script that uses app-config.nix values
    compile-archive = pkgs.writeShellScriptBin "compile-archive" ''
        #!/usr/bin/env bash

        # Load configuration from app-config.nix
        BACKEND_DIR="${backendPath}"
        FRONTEND_DIR="${frontendPath}"
        HS_DIRS="${hsDirs}"
        PS_DIRS="${psDirs}"
        CABAL_FILE="${hsConfig.cabalFile}"
        
        # Get current working directory as the project root
        project_root="$(pwd)"
        
        # Create script directory under the project
        script_dir="$project_root/script"

        # Create base directory for all outputs and auxiliary files
        base_dir="$script_dir/concat_archive"
        hash_dir="$base_dir/.hashes"
        output_dir="$base_dir/output"
        archive_dir="$base_dir/archive"
        mkdir -p "$output_dir" "$archive_dir" "$hash_dir"

        # Get current timestamp
        timestamp=$(date '+%Y%m%d_%H%M%S')

        # Function to calculate hash for a list of files
        calculate_hash() {
            local file_list="$1"
            echo "$file_list" | xargs sha256sum | sha256sum | cut -d' ' -f1
        }

        # Function to get previous hash
        get_previous_hash() {
            local file_type=$1
            local hash_file="$hash_dir/''${file_type}_last_hash"
            if [ -f "$hash_file" ]; then
                cat "$hash_file"
            else
                echo ""
            fi
        }

        # Function to save current hash
        save_current_hash() {
            local file_type=$1
            local current_hash=$2
            echo "$current_hash" > "$hash_dir/''${file_type}_last_hash"
        }

        # Function to compile Haskell project
        compile_haskell() {
            local project_dir=$1
            local temp_file=$(mktemp)
            
            # Navigate to backend directory and attempt to build
            (cd "$project_dir/$BACKEND_DIR" && cabal build) > "$temp_file" 2>&1
            local build_status=$?
            
            # Format the compilation status and output
            echo "{-"
            if [ -s "$temp_file" ]; then  # Check if file has content
                if [ $build_status -eq 0 ]; then
                    {
                        echo "COMPILE_STATUS: true"
                        echo "BUILD_OUTPUT:"
                        cat "$temp_file"
                    }
                else
                    {
                        echo "COMPILE_STATUS: false"
                        echo "BUILD_OUTPUT:"
                        cat "$temp_file"
                    }
                fi
            else
                echo "COMPILE_STATUS: error"
                echo "BUILD_OUTPUT:"
                echo "No build output captured"
            fi
            echo "-}"
            rm "$temp_file"
        }

        # Function to compile PureScript project
        compile_purescript() {
            local project_dir=$1
            local temp_file=$(mktemp)
            
            # Navigate to frontend directory and attempt to build with timeout
            if timeout 60 bash -c "cd '$project_dir/$FRONTEND_DIR' && spago build" > "$temp_file" 2>&1; then
                build_status=0
            else
                build_status=$?
                # Check if it was a timeout
                if [ $build_status -eq 124 ]; then
                    echo "COMPILE_STATUS: error" > "$temp_file"
                    echo "BUILD_OUTPUT:" >> "$temp_file"
                    echo "Build process timed out after 60 seconds" >> "$temp_file"
                fi
            fi
            
            # Format the compilation status and output
            echo "{-"
            if [ $build_status -eq 0 ]; then
                echo "COMPILE_STATUS: true"
            else
                {
                    echo "COMPILE_STATUS: false"
                    echo "COMPILE_ERROR:"
                    cat "$temp_file"
                }
            fi
            echo "-}"
            rm "$temp_file"
        }

        # Function to clean Haskell/PureScript content
        clean_haskell_purescript() {
            # Remove single-line comments while preserving indentation
            sed 's/\([ ]*\)--.*$/\1/' | \
            # Remove multi-line comments while preserving line structure
            perl -0777 -pe 's/{-.*?-}//gs' | \
            # Remove consecutive blank lines but keep one
            cat -s | \
            # Remove trailing whitespace while preserving indentation
            sed 's/[[:space:]]*$//'
        }

        # Function to clean Nix content with preserved formatting
        clean_nix() {
            # Remove single-line comments while preserving indentation
            sed 's/\([ ]*\)#.*$/\1/' | \
            # Remove multi-line comments while preserving line structure
            perl -0777 -pe 's!/\*[^*]*\*+(?:[^/*][^*]*\*+)*/!!gs' | \
            # Remove consecutive blank lines but keep one
            cat -s | \
            # Remove trailing whitespace while preserving indentation
            sed 's/[[:space:]]*$//' | \
            # Clean up empty attribute sets while preserving indentation
            sed 's/\([ ]*\){[[:space:]]*}/\1{ }/'
        }

        # Function to get relative path
        get_relative_path() {
            local full_path=$1
            echo "''${full_path#$project_root/}"
        }

        # Function to get Haskell source directories from cabal file
        get_haskell_dirs() {
            local project_dir=$1
            
            # If HS_DIRS is set from the configuration, use that instead
            if [ -n "$HS_DIRS" ]; then
                # Convert space-separated string to proper find arguments
                local full_paths=""
                for dir in $HS_DIRS; do
                    if [[ "$dir" = /* ]]; then
                        full_paths="$full_paths $dir"
                    else
                        full_paths="$full_paths $project_dir/$dir"
                    fi
                done
                echo "$full_paths"
                return
            fi
            
            # Fallback to cabal file if HS_DIRS is not set
            local cabal_file="$project_dir/$CABAL_FILE"
            
            if [ -f "$cabal_file" ]; then
                # Get all hs-source-dirs lines, extract the directory names
                source_dirs=$(grep -i "hs-source-dirs:" "$cabal_file" | sed 's/.*hs-source-dirs://' | tr -d ' ' | tr ',' ' ')
                
                # If no source dirs found, default to src
                if [ -z "$source_dirs" ]; then
                    source_dirs="src"
                fi
                
                # Build the full paths
                local full_paths=""
                for dir in $source_dirs; do
                    full_paths="$full_paths $project_dir/$BACKEND_DIR/$dir"
                done
                echo "$full_paths"
            else
                echo "Error: Cannot find cabal file at $cabal_file" >&2
                exit 1
            fi
        }

        # Function to build exclude patterns from gitignore
        build_exclude_patterns() {
            local gitignore="$project_root/.gitignore"
            local patterns=""
            
            # Add explicit exclusion for frontend/.spago directory
            patterns="-not -path '*/$FRONTEND_DIR/.spago/*'"
            
            if [ -f "$gitignore" ]; then
                while IFS= read -r line; do
                    # Skip empty lines and comments
                    [[ -z "$line" || "$line" =~ ^# ]] && continue
                    # Convert gitignore pattern to find pattern
                    if [[ "$line" = /* ]]; then
                        # Remove leading slash for absolute paths
                        line="''${line#/}"
                    fi
                    patterns="$patterns -not -path '*/$line/*' -not -path '*/$line'"
                done < "$gitignore"
            fi
            echo "$patterns"
        }

        # Function to get compilation status for filename
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

        # Function to extract error files from compilation output
        extract_error_files() {
            local compile_output="$1"
            local file_type="$2"
            local error_files=""
            local temp_file=$(mktemp)
            
            # Write compile output to temp file for easier processing
            echo "$compile_output" > "$temp_file"
            
            if [ "$file_type" = "purs" ]; then
                # First pass: Look for explicit error messages
                while IFS= read -r line; do
                    if [[ $line =~ \[ERROR[[:space:]].*\][[:space:]]([^:]+): ]]; then
                        local file="''${BASH_REMATCH[1]}"
                        if [[ $file == src/* ]]; then
                            file="$project_root/$FRONTEND_DIR/$file"
                        fi
                        if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                            error_files="$error_files $file"
                        fi
                    fi
                done < "$temp_file"
                
                # Second pass: Look for type errors and other patterns
                if [ -z "$error_files" ]; then
                    while IFS= read -r line; do
                        if [[ $line =~ "Could not match type" ]]; then
                            # Look ahead for file context
                            local context=$(grep -B 5 -A 5 "Could not match type" "$temp_file" | grep -o "src/[^[:space:]]*\.purs:[0-9]*")
                            if [[ $context =~ (src/[^:]+) ]]; then
                                local file="''${BASH_REMATCH[1]}"
                                if [[ $file == src/* ]]; then
                                    file="$project_root/$FRONTEND_DIR/$file"
                                fi
                                if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                                    error_files="$error_files $file"
                                fi
                            fi
                        fi
                    done < "$temp_file"
                fi
            elif [ "$file_type" = "hs" ]; then
                # First pass: Look for explicit error locations
                while IFS= read -r line; do
                    if [[ $line =~ ^([^:]+\.hs):[0-9]+:[0-9]+: ]]; then
                        local file="''${BASH_REMATCH[1]}"
                        if [[ $file == src/* ]]; then
                            file="$project_root/$BACKEND_DIR/$file"
                        elif [[ $file != /* ]]; then
                            file="$project_root/$BACKEND_DIR/$file"
                        fi
                        if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                            error_files="$error_files $file"
                        fi
                    fi
                done < "$temp_file"
                
                # Second pass: Look for other error patterns
                if [ -z "$error_files" ]; then
                    while IFS= read -r line; do
                        if [[ $line =~ "Failed to build" ]]; then
                            local context=$(grep -B 5 "Failed to build" "$temp_file" | grep -o "src/[^[:space:]]*\.hs")
                            if [[ -n "$context" ]]; then
                                local file="$project_root/backend/$context"
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

        # concatenate files of a specific type
        concatenate_files() {
            local file_type=$1
            local output_base=$2
            local clean_function=$3
            local comment_char=$4
            local compile_function=$5

            # Get exclude patterns from gitignore
            local exclude_patterns=$(build_exclude_patterns)

            # Create temporary list of files
            local file_list=""
            local error_files=""
            local compile_output=""
            
            case "$file_type" in
                "hs")
                    local hs_dirs=$(get_haskell_dirs "$project_root")
                    file_list=$(find $hs_dirs -type f -name "*.$file_type" 2>/dev/null | sort)
                    ;;
                "purs")
                    # Use PS_DIRS from config if available
                    if [ -n "$PS_DIRS" ]; then
                        local ps_paths=""
                        for dir in $PS_DIRS; do
                            if [[ "$dir" = /* ]]; then
                                ps_paths="$ps_paths $dir"
                            else
                                ps_paths="$ps_paths $project_root/$dir"
                            fi
                        done
                        file_list=$(find $ps_paths -type f -name "*.$file_type" 2>/dev/null | sort)
                    else
                        # Fallback to frontend/src if PS_DIRS not set
                        file_list=$(find "$project_root/$FRONTEND_DIR/src" -type f -name "*.$file_type" 2>/dev/null | sort)
                    fi
                    ;;
            esac

            # Calculate current hash
            local current_hash=$(calculate_hash "$file_list")
            local previous_hash=$(get_previous_hash "$file_type")

            # Check if we need to create a new file
            if [ -n "$previous_hash" ] && [ "$current_hash" = "$previous_hash" ]; then
                echo "No changes detected in $file_type files, reusing previous content..."
                local latest_file=$(ls -t "$output_dir"/*."$file_type" 2>/dev/null | head -n1)
                if [ -n "$latest_file" ]; then
                    local content=$(cat "$latest_file")
                    local status=$(get_status_for_filename "$content")
                    local output_file="$output_base$status.$file_type"
                    echo "$content" > "$output_file"
                    echo "Copied existing $file_type file with status $status"
                    return
                fi
            fi

            # Capture compilation output if compile function is provided
            local temp_compile_output=$(mktemp)
            if [ -n "$compile_function" ]; then
                eval "$compile_function \"$project_root\"" > "$temp_compile_output"
                compile_output=$(cat "$temp_compile_output")
                error_files=$(extract_error_files "$compile_output" "$file_type")
                rm "$temp_compile_output"
            fi

            # Create final file list with error files first
            local final_file_list=""
            if [ -n "$error_files" ]; then
                # Add error files first
                for error_file in $error_files; do
                    if [ -f "$error_file" ]; then
                        final_file_list="$final_file_list $error_file"
                    fi
                done
            fi
            
            # Add remaining files
            for file in $file_list; do
                if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                    final_file_list="$final_file_list $file"
                fi
            done

            # Generate output file
            local temp_file=$(mktemp)
            {
                if [ "$comment_char" = "--" ]; then
                    echo "{-"
                    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
                    echo "Hash: $current_hash"
                    echo "-}"
                else
                    echo "/*"
                    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
                    echo "Hash: $current_hash"
                    echo "*/"
                fi
                echo ""
                
                # Add compilation output if present
                if [ -n "$compile_output" ]; then
                    echo "$compile_output"
                    echo ""
                fi

                for file in $final_file_list; do
                    echo "$comment_char FILE: $(get_relative_path "$file")"
                    cat "$file" | eval "$clean_function"
                    echo "$comment_char END OF: $(get_relative_path "$file")"
                    echo ""
                done
            } > "$temp_file"

            # Get the status and create the final filename
            local status=$(get_status_for_filename "$(cat "$temp_file")")
            local output_file="$output_base$status.$file_type"
            mv "$temp_file" "$output_file"

            # Save the current hash
            save_current_hash "$file_type" "$current_hash"
            echo "Generated new $file_type file with status $status"
        }

        # Function to safely move files to archive
        safe_archive() {
            local ext=$1
            local files=("$output_dir"/*."$ext")
            # Check if files exist using standard pattern matching
            if [ -e "''${files[0]}" ]; then
                mv "$output_dir"/*."$ext" "$archive_dir/" 2>/dev/null || true
            fi
        }

        # Archive old files
        safe_archive "purs"
        safe_archive "hs"
        safe_archive "nix"

        # Define base filenames (without status)
        purs_base="$output_dir/PureScript_$timestamp"
        hs_base="$output_dir/Haskell_$timestamp"
        nix_base="$output_dir/Nix_$timestamp"

        # Concatenate files for each type with appropriate comment characters and compilation
        concatenate_files "purs" "$purs_base" "clean_haskell_purescript" "--" ""
        concatenate_files "hs" "$hs_base" "clean_haskell_purescript" "--" "compile_haskell"
        concatenate_files "nix" "$nix_base" "clean_nix" "#" ""

        echo "Concatenation complete. Output files are in $output_dir"
        echo "Previous files have been moved to $archive_dir"  
    '';

    # create a manifest of all files in the project then compile the project and concatenate all files 
    # into one large file with errors and the problem files at the top.
    # If a manifest is detected, it will distate which files get concatenated and which are excluded (unless they have errors) 
    compile-manifest = pkgs.writeShellScriptBin "compile-manifest" ''
      #!/usr/bin/env bash
        
      # Load configuration from app-config.nix
      BACKEND_DIR="${backendPath}"
      FRONTEND_DIR="${frontendPath}"
      HS_DIRS="${hsDirs}"
      PS_DIRS="${psDirs}"
      CABAL_FILE="${hsConfig.cabalFile}"
        
      # Get current working directory as the project root
      project_root="$(pwd)"
      # Script directories should be created in the project
      script_dir="$project_root/script"
      
      # Create base directory for all outputs and auxiliary files
      base_dir="$script_dir/concat_archive"
      hash_dir="$base_dir/.hashes"
      output_dir="$base_dir/output"
      archive_dir="$base_dir/archive"
      mkdir -p "$output_dir" "$archive_dir" "$hash_dir"
      
      # Single manifest file for documentation and control
      manifest_file="$script_dir/manifest.json"

        # Create base directory for all outputs and auxiliary files
        base_dir="''${script_dir}/concat_archive"
        hash_dir="''${base_dir}/.hashes"
        output_dir="''${base_dir}/output"
        archive_dir="''${base_dir}/archive"
        mkdir -p "$output_dir" "$archive_dir" "$hash_dir"

        # Single manifest file for documentation and control
        manifest_file="''${script_dir}/manifest.json"

        # Get current timestamp
        timestamp=$(date '+%Y%m%d_%H%M%S')

        # Function to calculate hash for a list of files
        calculate_hash() {
            local file_list="$1"
            if [ -z "$file_list" ]; then
                echo "empty"
                return
            fi
            echo "$file_list" | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1
        }

        # Function to get previous hash
        get_previous_hash() {
            local file_type=$1
            local hash_file="''${hash_dir}/''${file_type}_last_hash"
            if [ -f "$hash_file" ]; then
                cat "$hash_file"
            else
                echo ""
            fi
        }

        # Function to save current hash
        save_current_hash() {
            local file_type=$1
            local current_hash=$2
            echo "$current_hash" > "''${hash_dir}/''${file_type}_last_hash"
        }

        # Function to compile Haskell project
        compile_haskell() {
            local project_dir=$1
            local temp_file=$(mktemp)
            
            # Navigate to backend directory and attempt to build
            (cd "$project_dir/backend" && cabal build) > "$temp_file" 2>&1
            local build_status=$?
            
            # Format the compilation status and output
            echo "{-"
            if [ -s "$temp_file" ]; then  # Check if file has content
                if [ $build_status -eq 0 ]; then
                    {
                        echo "COMPILE_STATUS: true"
                        echo "BUILD_OUTPUT:"
                        cat "$temp_file"
                    }
                else
                    {
                        echo "COMPILE_STATUS: false"
                        echo "BUILD_OUTPUT:"
                        cat "$temp_file"
                    }
                fi
            else
                echo "COMPILE_STATUS: error"
                echo "BUILD_OUTPUT:"
                echo "No build output captured"
            fi
            echo "-}"
            rm "$temp_file"
        }

        # Function to compile PureScript project
        compile_purescript() {
            local project_dir=$1
            local temp_file=$(mktemp)
            
            # Navigate to frontend directory and attempt to build with timeout
            if timeout 60 bash -c "cd '$project_dir/$FRONTEND_DIR' && spago build" > "$temp_file" 2>&1; then
                build_status=0
            else
                build_status=$?
                # Check if it was a timeout
                if [ $build_status -eq 124 ]; then
                    echo "COMPILE_STATUS: error" > "$temp_file"
                    echo "BUILD_OUTPUT:" >> "$temp_file"
                    echo "Build process timed out after 60 seconds" >> "$temp_file"
                fi
            fi
            
            # Format the compilation status and output
            echo "{-"
            if [ $build_status -eq 0 ]; then
                echo "COMPILE_STATUS: true"
            else
                {
                    echo "COMPILE_STATUS: false"
                    echo "COMPILE_ERROR:"
                    cat "$temp_file"
                }
            fi
            echo "-}"
            rm "$temp_file"
        }

        # Function to clean Haskell/PureScript content
        clean_haskell_purescript() {
            # Remove single-line comments while preserving indentation
            sed 's/\([ ]*\)--.*$/\1/' | \
            # Remove multi-line comments while preserving line structure
            perl -0777 -pe 's/{-.*?-}//gs' | \
            # Remove consecutive blank lines but keep one
            cat -s | \
            # Remove trailing whitespace while preserving indentation
            sed 's/[[:space:]]*$//'
        }

        # Function to clean Nix content with preserved formatting
        clean_nix() {
            # Remove single-line comments while preserving indentation
            sed 's/\([ ]*\)#.*$/\1/' | \
            # Remove multi-line comments while preserving line structure
            perl -0777 -pe 's!/\*[^*]*\*+(?:[^/*][^*]*\*+)*/!!gs' | \
            # Remove consecutive blank lines but keep one
            cat -s | \
            # Remove trailing whitespace while preserving indentation
            sed 's/[[:space:]]*$//' | \
            # Clean up empty attribute sets while preserving indentation
            sed 's/\([ ]*\){[[:space:]]*}/\1{ }/'
        }

        # Function to get relative path
        get_relative_path() {
            local full_path=$1
            echo "''${full_path#$project_root/}"
        }

        # Function to get Haskell source directories from cabal file
        get_haskell_dirs() {
            local project_dir=$1
            local cabal_file=""
            
            # Look for a cabal file in the backend directory
            cabal_file=$(find "$project_dir/backend" -maxdepth 1 -name "*.cabal" | head -n1)
            
            if [ -z "$cabal_file" ]; then
                echo "Warning: Could not find a cabal file in $project_dir/backend" >&2
                echo "$project_dir/backend/src"  # Default to src if cabal file not found
                return
            fi
            
            local source_dirs=""
            
            # Get all hs-source-dirs lines, extract the directory names
            source_dirs=$(grep -i "hs-source-dirs:" "$cabal_file" | sed 's/.*hs-source-dirs://' | tr -d ' ' | tr ',' ' ')
            
            # If no source dirs found, default to src
            if [ -z "$source_dirs" ]; then
                source_dirs="src"
            fi
            
            # Build the full paths
            local full_paths=""
            for dir in $source_dirs; do
                full_paths="$full_paths $project_dir/backend/$dir"
            done
            echo "$full_paths"
        }

        # Function to build exclude patterns from gitignore
        build_exclude_patterns() {
            local gitignore="$project_root/.gitignore"
            local patterns=""
            
            # Add explicit exclusion for frontend/.spago directory
            patterns="-not -path '*/$FRONTEND_DIR/.spago/*'"
            
            if [ -f "$gitignore" ]; then
                while IFS= read -r line; do
                    # Skip empty lines and comments
                    [[ -z "$line" || "$line" =~ ^# ]] && continue
                    # Convert gitignore pattern to find pattern
                    if [[ "$line" = /* ]]; then
                        # Remove leading slash for absolute paths
                        line="''${line#/}"
                    fi
                    patterns="$patterns -not -path '*/$line/*' -not -path '*/$line'"
                done < "$gitignore"
            fi
            echo "$patterns"
        }

        # Function to get compilation status for filename
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

        # Function to extract error files from compilation output
        extract_error_files() {
            local compile_output="$1"
            local file_type="$2"
            local error_files=""
            local temp_file=$(mktemp)
            
            # Write compile output to temp file for easier processing
            echo "$compile_output" > "$temp_file"
            
            if [ "$file_type" = "purs" ]; then
                # First pass: Look for explicit error messages
                while IFS= read -r line; do
                    if [[ $line =~ \[ERROR[[:space:]].*\][[:space:]]([^:]+): ]]; then
                        local file="''${BASH_REMATCH[1]}"
                        if [[ $file == src/* ]]; then
                            file="$project_root/$FRONTEND_DIR/$file"
                        fi
                        if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                            error_files="$error_files $file"
                        fi
                    fi
                done < "$temp_file"
                
                # Second pass: Look for type errors and other patterns
                if [ -z "$error_files" ]; then
                    while IFS= read -r line; do
                        if [[ $line =~ "Could not match type" ]]; then
                            # Look ahead for file context
                            local context=$(grep -B 5 -A 5 "Could not match type" "$temp_file" | grep -o "src/[^[:space:]]*\.purs:[0-9]*")
                            if [[ $context =~ (src/[^:]+) ]]; then
                                local file="''${BASH_REMATCH[1]}"
                                if [[ $file == src/* ]]; then
                                    file="$project_root/$FRONTEND_DIR/$file"
                                fi
                                if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                                    error_files="$error_files $file"
                                fi
                            fi
                        fi
                    done < "$temp_file"
                fi
            elif [ "$file_type" = "hs" ]; then
                # First pass: Look for explicit error locations
                while IFS= read -r line; do
                    if [[ $line =~ ^([^:]+\.hs):[0-9]+:[0-9]+: ]]; then
                        local file="''${BASH_REMATCH[1]}"
                        if [[ $file == src/* ]]; then
                            file="$project_root/$BACKEND_DIR/$file"
                        elif [[ $file != /* ]]; then
                            file="$project_root/$BACKEND_DIR/$file"
                        fi
                        if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                            error_files="$error_files $file"
                        fi
                    fi
                done < "$temp_file"
                
                # Second pass: Look for other error patterns
                if [ -z "$error_files" ]; then
                    while IFS= read -r line; do
                        if [[ $line =~ "Failed to build" ]]; then
                            local context=$(grep -B 5 "Failed to build" "$temp_file" | grep -o "src/[^[:space:]]*\.hs")
                            if [[ -n "$context" ]]; then
                                local file="$project_root/backend/$context"
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

        # Function to generate initial manifest
        generate_manifest() {
            local project_dir="$1"
            local manifest_file="$2"
            local purs_files=()
            local hs_files=()
            local nix_files=()
            
            echo "No manifest file found. Generating initial manifest..."
            
            # Find PureScript files
            if [ -n "$PS_DIRS" ]; then
                for dir in $PS_DIRS; do
                    if [[ "$dir" = /* ]]; then
                        # Absolute path
                        local search_dir="$dir"
                    else
                        # Relative path
                        local search_dir="$project_dir/$dir"
                    fi
                    
                    if [ -d "$search_dir" ]; then
                        while IFS= read -r file; do
                            purs_files+=("$(get_relative_path "$file")")
                        done < <(find "$search_dir" -type f -name "*.purs" | sort)
                    fi
                done
            elif [ -d "$project_dir/$FRONTEND_DIR/src" ]; then
                # Fallback to frontend/src if PS_DIRS is not configured
                while IFS= read -r file; do
                    purs_files+=("$(get_relative_path "$file")")
                done < <(find "$project_dir/$FRONTEND_DIR/src" -type f -name "*.purs" | sort)
            fi
            
            # Find Haskell files
            if [ -d "$project_dir/backend/src" ]; then
                while IFS= read -r file; do
                    hs_files+=("$(get_relative_path "$file")")
                done < <(find "$project_dir/backend/src" -type f -name "*.hs" | sort)
            fi
            
            if [ -d "$project_dir/backend/app" ]; then
                while IFS= read -r file; do
                    hs_files+=("$(get_relative_path "$file")")
                done < <(find "$project_dir/backend/app" -type f -name "*.hs" | sort)
            fi
            
            # Find Nix files
            while IFS= read -r file; do
                nix_files+=("$(get_relative_path "$file")")
            done < <(find "$project_dir" -maxdepth 1 -type f -name "*.nix" | sort)
            
            while IFS= read -r file; do
                nix_files+=("$(get_relative_path "$file")")
            done < <(find "$project_dir/nix" -type f -name "*.nix" 2>/dev/null | sort)
            
            # Create JSON structure - initially all files are included, none excluded
            local json_content="{
          \"purescript\": {
            \"include\": ["
            
            # Add PureScript files
            local first=true
            for file in "''${purs_files[@]}"; do
                if [ "$first" = true ]; then
                    json_content+="
              \"$file\""
                    first=false
                else
                    json_content+=",
              \"$file\""
                fi
            done
            
            # Add empty exclude array and metadata
            json_content+="
            ],
            \"exclude\": [],
            \"count\": ''${#purs_files[@]},
            \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"
          },
          \"haskell\": {
            \"include\": ["
            
            # Add Haskell files
            first=true
            for file in "''${hs_files[@]}"; do
                if [ "$first" = true ]; then
                    json_content+="
              \"$file\""
                    first=false
                else
                    json_content+=",
              \"$file\""
                fi
            done
            
            # Add empty exclude array and metadata
            json_content+="
            ],
            \"exclude\": [],
            \"count\": ''${#hs_files[@]},
            \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"
          },
          \"nix\": {
            \"include\": ["
            
            # Add Nix files
            first=true
            for file in "''${nix_files[@]}"; do
                if [ "$first" = true ]; then
                    json_content+="
              \"$file\""
                    first=false
                else
                    json_content+=",
              \"$file\""
                fi
            done
            
            # Add empty exclude array and metadata
            json_content+="
            ],
            \"exclude\": [],
            \"count\": ''${#nix_files[@]},
            \"timestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\"
          }
        }"
            
            # Write JSON to manifest file
            echo "$json_content" > "$manifest_file"
            
            # Add a backup with timestamp
            cp "$manifest_file" "''${manifest_file}.$(date '+%Y%m%d_%H%M%S')"
            
            echo "Generated manifest file at: $manifest_file"
            echo "You can now edit this file to move files from 'include' to 'exclude' sections"
        }

        # Function to get included files from manifest
        get_included_files() {
            local file_type="$1"
            local section=""
            
            case "$file_type" in
                "purs")
                    section="purescript"
                    ;;
                "hs")
                    section="haskell"
                    ;;
                "nix")
                    section="nix"
                    ;;
                *)
                    echo "Error: Unknown file type $file_type" >&2
                    return 1
                    ;;
            esac
            
            if [ ! -f "$manifest_file" ]; then
                echo "Error: Manifest file not found at $manifest_file" >&2
                return 1
            fi
            
            # Get the include array for the specific section
            local include_files=$(jq -r ".$section.include[]" "$manifest_file" 2>/dev/null)
            local file_list=""
            
            # Convert relative paths to full paths
            while IFS= read -r rel_path; do
                if [ -n "$rel_path" ]; then
                    file_list+=" $project_root/$rel_path"
                fi
            done <<< "$include_files"
            
            echo "$file_list"
        }

        # concatenate files of a specific type
        concatenate_files() {
            local file_type=$1
            local output_base=$2
            local clean_function=$3
            local comment_char=$4
            local compile_function=$5

            # Get files from manifest
            local file_list=$(get_included_files "$file_type")
            local error_files=""
            local compile_output=""
            
            echo "Finding $file_type files from manifest..."
            echo "Found $(echo "$file_list" | wc -w) $file_type files to process."

            # If no files to process, exit this function
            if [ -z "$file_list" ]; then
                echo "No $file_type files selected for processing."
                return
            fi

            # Calculate current hash
            local current_hash=$(calculate_hash "$file_list")
            local previous_hash=$(get_previous_hash "$file_type")

            # Check if we need to create a new file - always regenerate on first run
            local force_regenerate=false
            if [ ! -f "$output_dir"/*."$file_type" ]; then
                force_regenerate=true
            fi

            if [ "$force_regenerate" = false ] && [ -n "$previous_hash" ] && [ "$current_hash" = "$previous_hash" ]; then
                echo "No changes detected in $file_type files, reusing previous content..."
                local latest_file=$(ls -t "$output_dir"/*."$file_type" 2>/dev/null | head -n1)
                if [ -n "$latest_file" ]; then
                    local content=$(cat "$latest_file")
                    local status=$(get_status_for_filename "$content")
                    local output_file="''${output_base}''${status}.$file_type"
                    echo "$content" > "$output_file"
                    echo "Copied existing $file_type file with status $status"
                    return
                fi
            fi

            # Capture compilation output if compile function is provided
            local temp_compile_output=$(mktemp)
            if [ -n "$compile_function" ]; then
                echo "Running compilation for $file_type..."
                eval "$compile_function \"$project_root\"" > "$temp_compile_output"
                compile_output=$(cat "$temp_compile_output")
                error_files=$(extract_error_files "$compile_output" "$file_type")
                rm "$temp_compile_output"
                
                if [ -n "$error_files" ]; then
                    echo "Found $(echo "$error_files" | wc -w) files with errors."
                else
                    echo "No compilation errors found."
                fi
            fi

            # Create final file list with error files first
            local final_file_list=""
            if [ -n "$error_files" ]; then
                # Add error files first (if they're in the included files)
                for error_file in $error_files; do
                    if [[ $file_list =~ (^|[[:space:]])$error_file($|[[:space:]]) ]]; then
                        final_file_list="$final_file_list $error_file"
                    fi
                done
            fi
            
            # Add remaining files
            for file in $file_list; do
                if [[ ! $error_files =~ (^|[[:space:]])$file($|[[:space:]]) ]]; then
                    final_file_list="$final_file_list $file"
                fi
            done

            echo "Generating concatenated $file_type file..."
            
            # Generate output file
            local temp_file=$(mktemp)
            {
                if [ "$comment_char" = "--" ]; then
                    echo "{-"
                    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
                    echo "Hash: $current_hash"
                    echo "Files from manifest: $(echo "$file_list" | wc -w)"
                    echo "-}"
                else
                    echo "/*"
                    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
                    echo "Hash: $current_hash"
                    echo "Files from manifest: $(echo "$file_list" | wc -w)"
                    echo "*/"
                fi
                echo ""
                
                # Add compilation output if present
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

            # Get the status and create the final filename
            local status=$(get_status_for_filename "$(cat "$temp_file")")
            local output_file="''${output_base}''${status}.$file_type"
            mv "$temp_file" "$output_file"

            # Save the current hash
            save_current_hash "$file_type" "$current_hash"
            echo "Generated new $file_type file with status $status"
        }

        # Function to safely move files to archive
        safe_archive() {
            local ext=$1
            local files=("$output_dir"/*."$ext")
            # Check if files exist using standard pattern matching
            if [ -e "''${files[0]}" ]; then
                mv "$output_dir"/*."$ext" "$archive_dir/" 2>/dev/null || true
            fi
        }

        # Parse command line options
        while getopts ":c:" opt; do
          case ''${opt} in
            c )
              manifest_file=$OPTARG
              ;;
            \? )
              echo "Invalid option: $OPTARG" 1>&2
              echo "Usage: $0 [-c manifest_file]" 1>&2
              exit 1
              ;;
            : )
              echo "Invalid option: $OPTARG requires an argument" 1>&2
              exit 1
              ;;
          esac
        done

        # Check if manifest file exists, generate if not
        if [ ! -f "$manifest_file" ]; then
            generate_manifest "$project_root" "$manifest_file"
        else
            echo "Using existing manifest file: $manifest_file"
            echo "Edit this file to control which files are included or excluded."
        fi

        # Archive old files
        safe_archive "purs"
        safe_archive "hs"
        safe_archive "nix"

        # Define base filenames (without status)
        purs_base="''${output_dir}/PureScript_''${timestamp}"
        hs_base="''${output_dir}/Haskell_''${timestamp}"
        nix_base="''${output_dir}/Nix_''${timestamp}"

        # Processing message
        echo -e "\nProcessing files according to manifest..."

        concatenate_files "purs" "$purs_base" "clean_haskell_purescript" "--" "compile_purescript"
        concatenate_files "hs" "$hs_base" "clean_haskell_purescript" "--" "compile_haskell"
        concatenate_files "nix" "$nix_base" "clean_nix" "#" ""

        echo "Concatenation complete. Output files are in $output_dir"
        echo "Previous files have been moved to $archive_dir"
      '';
    
  };

  # Common buildInputs used in development shell
  commonBuildInputs = with pkgs; [
    # Front End tools
    esbuild
    nodejs_20
    nixpkgs-fmt
    purs
    purs-tidy
    purs-backend-es
    purescript-language-server
    spago-unstable

    # Back End tools
    cabal-install
    ghc
    haskellPackages.fourmolu
    haskell-language-server
    hlint
    zlib
    pgcli
    pkg-config
    openssl.dev
    libiconv
    openssl
    
    # PostgreSQL utilities
    postgresModule.pg-start
    postgresModule.pg-connect
    postgresModule.pg-stop
    postgresModule.pg-cleanup
    postgresModule.pg-backup    
    postgresModule.pg-restore    
    postgresModule.pg-rotate-credentials  
    postgresModule.pg-create-schema      
    postgresModule.pg-stats              
    
    # Database tools
    pgadmin4

    # DevShell tools
    toilet # colorful text
    rsync
    tmux
    workspaceModule.backup-project
    workspaceModule.compile-manifest
    workspaceModule.compile-archive


    # Frontend tools
    frontendModule.vite
    frontendModule.vite-cleanup
    frontendModule.spago-watch
    frontendModule.concurrent
    frontendModule.dev

    # Workspace and deployment tools
    workspaceModule.code-workspace
    deployModule.deploy
    deployModule.withdraw
    
    # Additional tools specifically for the scripts
    coreutils
    bash
    gnused
    gnugrep
    jq
    perl
    findutils
  ];

  # Native build inputs
  nativeBuildInputs = with pkgs; [
    pkg-config
    postgresql
    postgresql.lib
    zlib
    openssl.dev
    libiconv
    openssl
    lsof
    tmux
  ];

  # Darwin-specific inputs
  darwinInputs = if (system == "aarch64-darwin" || system == "x86_64-darwin") then
    (with pkgs.darwin.apple_sdk.frameworks; [
      Cocoa
      CoreServices
    ])
  else [];

  # Return a shell configuration
  devShell = pkgs.mkShell {
    inherit name;
    
    inherit nativeBuildInputs;
    
    buildInputs = commonBuildInputs ++ darwinInputs;
    
    shellHook = ''
      export PGDATA="${dbConfig.dataDir}"
      export PGPORT="${toString dbConfig.port}"
      export PGUSER="${dbConfig.user}"
      export PGPASSWORD="${dbConfig.password}"
      export PGDATABASE="${dbConfig.name}"
      export PKG_CONFIG_PATH="${pkgs.postgresql.lib}/lib/pkgconfig:$PKG_CONFIG_PATH"
      
      # Create script directory for compile-with-manifest if it doesn't exist
      mkdir -p "$(pwd)/script/concat_archive/output" "$(pwd)/script/concat_archive/archive" "$(pwd)/script/concat_archive/.hashes"
      
      echo "Welcome to the ${lib.toSentenceCase name} development environment!"

      echo "Available commands:"
      echo "  Database:"
      echo "    pg-start               - Start PostgreSQL server"
      echo "    pg-connect             - Connect to PostgreSQL server"
      echo "    pg-stop                - Stop PostgreSQL server"
      echo "    pg-cleanup             - Remove PostgreSQL data directory"
      echo "    pg-backup              - Backup PostgreSQL database"
      echo "    pg-restore <file>      - Restore PostgreSQL database from backup"
      echo "    pg-rotate-credentials  - Generate new PostgreSQL password"
      echo "    pg-create-schema <n>   - Create new schema"
      echo "    pg-stats               - Show PostgreSQL statistics"
      echo ""
      echo "  Frontend:"
      echo "    vite                   - Start Vite development server"
      echo "    vite-cleanup           - Clean frontend build artifacts"
      echo "    spago-watch            - Watch PureScript files for changes"
      echo "    concurrent             - Run concurrent development tasks"
      echo ""
      echo "  Development:"
      echo "    dev                    - Start all development services in tmux"
      echo "    code-workspace         - Open VSCodium workspace that handles a PS-HS project"
      echo "    backup-project         - Backup project files"
      echo "    compile-manifest       - Compile and concatenate project files (formerly cwm)"
      echo "    cwm                    - Alias for compile-with-manifest"
      echo ""
      echo "  Deployment:"
      echo "    deploy                 - Deploy to server"
      echo "    withdraw               - Withdraw deployment"
      echo ""
      echo ""
      toilet ${lib.toSentenceCase name} -t --metal
    '';
  };

in {
  inherit devShell;
  inherit workspaceModule;
}