{ pkgs, lib ? pkgs.lib, name }:

let
  secretsFile = "secrets/${name}.yaml";

  bootstrap-admin = pkgs.writeShellApplication {
    name = "bootstrap-admin";
    runtimeInputs = [ pkgs.sops pkgs.jq ];
    text = ''
      set -euo pipefail

      # Walk up from pwd until we find the project root.
      PROJECT_ROOT="$(pwd)"
      while [ "$PROJECT_ROOT" != "/" ]; do
        [ -f "$PROJECT_ROOT/.sops.yaml" ] && break
        [ -d "$PROJECT_ROOT/secrets"    ] && break
        PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
      done

      SECRETS_FILE="$PROJECT_ROOT/${secretsFile}"
      BACKEND_DIR="$PROJECT_ROOT/backend"
      DRY_RUN=false

      for arg in "$@"; do
        case "$arg" in
          --dry-run) DRY_RUN=true ;;
          *) echo "Unknown argument: $arg"; exit 1 ;;
        esac
      done

      if [ "$DRY_RUN" = "true" ]; then
        echo "bootstrap-admin --dry-run: would run cheeblr-bootstrap-admin from $BACKEND_DIR"
        echo "  secrets file: $SECRETS_FILE"
        exit 0
      fi

      echo "Running cheeblr-bootstrap-admin..."
      echo "  Project root : $PROJECT_ROOT"
      echo "  Backend dir  : $BACKEND_DIR"
      echo "  Secrets file : $SECRETS_FILE"
      echo ""

      # Inject PGPASSWORD from sops if the secrets file exists.
      # PGHOST is already set by the devshell to $PGDATA (Unix socket dir).
      # Run cabal from the backend directory where the cabal project lives.
      OUTPUT=$(cd "$BACKEND_DIR" && with-db cabal run cheeblr-bootstrap-admin -v0 2>/dev/null \
         || cd "$BACKEND_DIR" && with-db cabal run cheeblr-bootstrap-admin)

      echo "$OUTPUT"
      echo ""

      ADMIN_PASS=$(echo "$OUTPUT" | grep "^password" | awk '{print $3}' || true)

      if [ -z "$ADMIN_PASS" ]; then
        exit 0
      fi

      if [ -f "$SECRETS_FILE" ]; then
        echo "Storing admin_password in $SECRETS_FILE ..."
        sops --set '["admin_password"] "'"$ADMIN_PASS"'"' "$SECRETS_FILE"
        echo "✓ admin_password saved to sops secrets."
        echo "  Retrieve later with:  sops-get admin_password"
        echo "  Commit ${secretsFile} to keep it encrypted in git."
      else
        echo "⚠ No sops secrets file — password printed above, store it safely."
        echo "  Run 'sops-bootstrap' to initialise secrets management."
      fi
    '';
  };

  admin-password-info = pkgs.writeShellApplication {
    name = "admin-password-info";
    runtimeInputs = [ pkgs.sops pkgs.jq ];
    text = ''
      PROJECT_ROOT="$(pwd)"
      while [ "$PROJECT_ROOT" != "/" ]; do
        [ -f "$PROJECT_ROOT/.sops.yaml" ] && break
        [ -d "$PROJECT_ROOT/secrets"    ] && break
        PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
      done

      SECRETS_FILE="$PROJECT_ROOT/${secretsFile}"
      if [ ! -f "$SECRETS_FILE" ]; then
        echo "No secrets file at $SECRETS_FILE. Run 'sops-bootstrap' first."
        exit 1
      fi
      PASS=$(sops --decrypt --output-type json "$SECRETS_FILE" \
             | jq -r '.admin_password // empty')
      if [ -n "$PASS" ] && [ "$PASS" != '""' ]; then
        echo "admin_password is set (length: ''${#PASS})"
        echo "To reveal: sops-get admin_password"
      else
        echo "admin_password not yet stored in sops."
        echo "Run 'bootstrap-admin' after pg-start to create the initial admin account."
      fi
    '';
  };

in {
  inherit bootstrap-admin admin-password-info;
}
