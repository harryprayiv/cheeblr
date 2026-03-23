{ pkgs, lib ? pkgs.lib, name }:

let
  config      = import ./config.nix { inherit name; };
  certDir     = config.tls.certDir;
  tlsCfg      = config.tls;
  secretsFile = "secrets/${name}.yaml";

  sops-init-key = pkgs.writeShellApplication {
    name = "sops-init-key";
    runtimeInputs = [ pkgs.ssh-to-age pkgs.age ];
    text = ''
      SSH_KEY="$HOME/.ssh/id_ed25519"
      AGE_DIR="$HOME/.config/sops/age"
      AGE_KEYS="$AGE_DIR/keys.txt"

      if [ ! -f "$SSH_KEY" ]; then
        echo "No ed25519 SSH key found at $SSH_KEY"
        echo "Generate one with:  ssh-keygen -t ed25519"
        exit 1
      fi

      mkdir -p "$AGE_DIR"
      chmod 700 "$AGE_DIR"

      if [ -f "$AGE_KEYS" ]; then
        echo "Age key already present at $AGE_KEYS"
        PUBKEY=$(ssh-to-age -i "$SSH_KEY.pub" 2>/dev/null || \
                 grep "^# public key:" "$AGE_KEYS" | awk '{print $NF}')
        echo "Public key: $PUBKEY"
        exit 0
      fi

      echo "Deriving age key from $SSH_KEY ..."
      ssh-to-age -private-key -i "$SSH_KEY" > "$AGE_KEYS"
      chmod 600 "$AGE_KEYS"

      PUBKEY=$(ssh-to-age -i "$SSH_KEY.pub")
      echo "# public key: $PUBKEY" >> "$AGE_KEYS"

      echo "✓ Age key written to $AGE_KEYS"
      echo "  Public key: $PUBKEY"
      echo ""
      echo "Next: run 'sops-bootstrap' to create ${secretsFile}"
    '';
  };

  sops-pubkey = pkgs.writeShellApplication {
    name = "sops-pubkey";
    runtimeInputs = [ pkgs.ssh-to-age ];
    text = ''
      SSH_PUB="$HOME/.ssh/id_ed25519.pub"
      AGE_KEYS="$HOME/.config/sops/age/keys.txt"

      if [ -f "$SSH_PUB" ]; then
        ssh-to-age -i "$SSH_PUB"
      elif [ -f "$AGE_KEYS" ]; then
        grep "^# public key:" "$AGE_KEYS" | awk '{print $NF}'
      else
        echo "No SSH public key or age keys file found."
        echo "Run 'sops-init-key' first."
        exit 1
      fi
    '';
  };

  sops-bootstrap = pkgs.writeShellApplication {
    name = "sops-bootstrap";
    runtimeInputs = [ pkgs.sops pkgs.ssh-to-age pkgs.openssl pkgs.jq ];
    text = ''
      set -euo pipefail
      PROJECT_ROOT="$(pwd)"
      SECRETS_DIR="$PROJECT_ROOT/secrets"
      SECRETS_FILE="$SECRETS_DIR/${name}.yaml"
      SOPS_CONFIG="$PROJECT_ROOT/.sops.yaml"
      AGE_KEYS="$HOME/.config/sops/age/keys.txt"
      SSH_PUB="$HOME/.ssh/id_ed25519.pub"

      if [ ! -f "$AGE_KEYS" ]; then
        echo "Age key not found — running sops-init-key first..."
        sops-init-key
      fi

      if [ -f "$SSH_PUB" ]; then
        PUBKEY=$(ssh-to-age -i "$SSH_PUB")
      else
        PUBKEY=$(grep "^# public key:" "$AGE_KEYS" | awk '{print $NF}')
      fi
      echo "Using age public key: $PUBKEY"
      echo ""

      if [ ! -f "$SOPS_CONFIG" ]; then
        cat > "$SOPS_CONFIG" <<EOF
keys:
  - &dev_key $PUBKEY

creation_rules:
  - path_regex: secrets/.*\\.yaml\$
    key_groups:
      - age:
          - *dev_key
EOF
        echo "✓ Created .sops.yaml"
      else
        echo "✓ .sops.yaml already present"
      fi

      if [ -f "$SECRETS_FILE" ]; then
        echo "✓ $SECRETS_FILE already exists — skipping"
        echo "  Use 'sops ${secretsFile}' to edit."
        exit 0
      fi

      mkdir -p "$SECRETS_DIR"
      DB_PASS=$(openssl rand -base64 24 | tr -d '=/+' | head -c 32)

      TMPFILE=$(mktemp --suffix=.yaml)
      trap 'rm -f "$TMPFILE"' EXIT
      cat > "$TMPFILE" <<EOF
db_password: $DB_PASS
tls_cert: ""
tls_key: ""
admin_password: ""
EOF

      SOPS_AGE_KEY_FILE="$AGE_KEYS" sops --encrypt \
        --age "$PUBKEY" "$TMPFILE" > "$SECRETS_FILE"

      echo "✓ Encrypted secrets written to $SECRETS_FILE"
      echo ""
      echo "  DB password (shown once — now encrypted):"
      echo "  $DB_PASS"
      echo ""
      echo "  Next steps:"
      echo "    tls-setup           generate mkcert dev certs"
      echo "    tls-sops-update     encrypt them into $SECRETS_FILE"
      echo "    bootstrap-admin     create initial admin user"
      echo "    sops-status         verify everything is working"
      echo ""
      echo "  Commit: .sops.yaml  secrets/${name}.yaml"
      echo "  NEVER commit: ~/.config/sops/age/keys.txt"
    '';
  };

  sops-get = pkgs.writeShellApplication {
    name = "sops-get";
    runtimeInputs = [ pkgs.sops pkgs.jq ];
    text = ''
      KEY="''${1:-}"
      if [ -z "$KEY" ]; then
        echo "Usage: sops-get <key>"
        exit 1
      fi
      SECRETS_FILE="$(pwd)/${secretsFile}"
      if [ ! -f "$SECRETS_FILE" ]; then
        echo "sops-get: no secrets file at $SECRETS_FILE" >&2
        echo "  Run 'sops-bootstrap' first." >&2
        exit 1
      fi
      sops --decrypt --output-type json "$SECRETS_FILE" \
        | jq -r --arg k "$KEY" '.[$k] // empty'
    '';
  };

  sops-exec = pkgs.writeShellApplication {
    name = "sops-exec";
    runtimeInputs = [ pkgs.sops pkgs.jq pkgs.gettext ];
    text = ''
      if [ $# -eq 0 ]; then
        echo "Usage: sops-exec <command> [args...]"
        exit 1
      fi

      SECRETS_FILE="$(pwd)/${secretsFile}"

      if [ ! -f "$SECRETS_FILE" ]; then
        echo "sops-exec: no secrets file at $SECRETS_FILE — continuing without secrets" >&2
        exec "$@"
      fi

      DECRYPTED=$(sops --decrypt --output-type json "$SECRETS_FILE")

      DB_PASS=$(echo "$DECRYPTED" | jq -r '.db_password // empty')
      if [ -n "$DB_PASS" ]; then
        export PGPASSWORD="$DB_PASS"
        export DB_PASSWORD="$DB_PASS"
      fi

      CERT=$(echo "$DECRYPTED" | jq -r '.tls_cert // empty')
      TKEY=$(echo "$DECRYPTED" | jq -r '.tls_key // empty')

      if [ -n "$CERT" ] && [ -n "$TKEY" ] && \
         [ "$CERT" != '""' ] && [ "$TKEY" != '""' ]; then
        SECRETS_TMPDIR=$(mktemp -d)
        chmod 700 "$SECRETS_TMPDIR"
        trap 'rm -rf "$SECRETS_TMPDIR"' EXIT INT TERM HUP

        printf '%s\n' "$CERT" > "$SECRETS_TMPDIR/tls.crt"
        printf '%s\n' "$TKEY" > "$SECRETS_TMPDIR/tls.key"
        chmod 444 "$SECRETS_TMPDIR/tls.crt"
        chmod 400 "$SECRETS_TMPDIR/tls.key"

        export TLS_CERT_FILE="$SECRETS_TMPDIR/tls.crt"
        export TLS_KEY_FILE="$SECRETS_TMPDIR/tls.key"
        export USE_TLS="true"
      else
        CERT_DIR="$(echo "${certDir}" | envsubst)"
        LOCAL_CERT="$CERT_DIR/${tlsCfg.certFile}"
        LOCAL_KEY="$CERT_DIR/${tlsCfg.keyFile}"
        if [ -f "$LOCAL_CERT" ] && [ -f "$LOCAL_KEY" ]; then
          export TLS_CERT_FILE="$LOCAL_CERT"
          export TLS_KEY_FILE="$LOCAL_KEY"
          export USE_TLS="true"
        fi
      fi

      exec "$@"
    '';
  };

  sops-status = pkgs.writeShellApplication {
    name = "sops-status";
    runtimeInputs = [ pkgs.sops pkgs.ssh-to-age pkgs.jq ];
    text = ''
      PROJECT_ROOT="$(pwd)"
      AGE_KEYS="$HOME/.config/sops/age/keys.txt"
      SSH_PUB="$HOME/.ssh/id_ed25519.pub"
      SOPS_CONFIG="$PROJECT_ROOT/.sops.yaml"
      SECRETS_FILE="$PROJECT_ROOT/${secretsFile}"

      echo "${name} — sops status"
      echo "────────────────────────────────────────────"

      if [ -f "$SSH_PUB" ]; then
        PUBKEY=$(ssh-to-age -i "$SSH_PUB" 2>/dev/null || echo "")
        if [ -n "$PUBKEY" ]; then
          echo "  ssh→age key  : ✓ $PUBKEY"
        else
          echo "  ssh→age key  : ✗ ssh-to-age conversion failed"
        fi
      else
        echo "  ssh key      : ✗ $SSH_PUB not found"
      fi

      if [ -f "$AGE_KEYS" ]; then
        echo "  age keys.txt : ✓ present"
      else
        echo "  age keys.txt : ✗ missing — run 'sops-init-key'"
      fi

      if [ -f "$SOPS_CONFIG" ]; then
        echo "  .sops.yaml   : ✓ present"
      else
        echo "  .sops.yaml   : ✗ missing — run 'sops-bootstrap'"
      fi

      if [ -f "$SECRETS_FILE" ]; then
        echo "  secrets file : ✓ $SECRETS_FILE"
        if sops --decrypt "$SECRETS_FILE" > /dev/null 2>&1; then
          echo "  decryptable  : ✓ age key works"
          DECRYPTED=$(sops --decrypt --output-type json "$SECRETS_FILE")

          DB=$(echo "$DECRYPTED" | jq -r '.db_password // empty')
          if [ -n "$DB" ]; then
            echo "  db_password  : ✓ set (length: ''${#DB})"
          else
            echo "  db_password  : ✗ empty"
          fi

          CERT=$(echo "$DECRYPTED" | jq -r '.tls_cert // empty')
          if [ -n "$CERT" ] && [ "$CERT" != '""' ]; then
            echo "  tls_cert     : ✓ present"
          else
            echo "  tls_cert     : ✗ empty — run: tls-setup && tls-sops-update"
          fi

          TKEY=$(echo "$DECRYPTED" | jq -r '.tls_key // empty')
          if [ -n "$TKEY" ] && [ "$TKEY" != '""' ]; then
            echo "  tls_key      : ✓ present"
          else
            echo "  tls_key      : ✗ empty — run: tls-setup && tls-sops-update"
          fi

          APASS=$(echo "$DECRYPTED" | jq -r '.admin_password // empty')
          if [ -n "$APASS" ] && [ "$APASS" != '""' ]; then
            echo "  admin_password: ✓ set (length: ''${#APASS})"
            echo "                  reveal with: sops-get admin_password"
          else
            echo "  admin_password: ✗ not set — run 'bootstrap-admin' after pg-start"
          fi
        else
          echo "  decryptable  : ✗ wrong key or corrupted file"
        fi
      else
        echo "  secrets file : ✗ missing — run 'sops-bootstrap'"
      fi

      echo "────────────────────────────────────────────"
    '';
  };

  loadSecretsHook = ''
    _SOPS_FILE="$(pwd)/${secretsFile}"
    if [ -f "$_SOPS_FILE" ] && command -v sops &>/dev/null; then
      _DECRYPTED=$(sops --decrypt --output-type json "$_SOPS_FILE" 2>/dev/null || true)
      if [ -n "$_DECRYPTED" ]; then
        _DB_PASS=$(echo "$_DECRYPTED" | ${pkgs.jq}/bin/jq -r '.db_password // empty' 2>/dev/null || true)
        if [ -n "$_DB_PASS" ]; then
          export PGPASSWORD="$_DB_PASS"
          echo "    ✓ PGPASSWORD loaded from sops"
        fi
        unset _DB_PASS _DECRYPTED
      else
        export PGPASSWORD="${config.database.password}"
        echo "    ✗ sops decrypt failed — using config default password"
      fi
    else
      export PGPASSWORD="${config.database.password}"
      echo "    ⚠ sops not bootstrapped — using config default password"
      echo "      Run 'sops-init-key' then 'sops-bootstrap' to enable."
    fi
    unset _SOPS_FILE
  '';

in {
  inherit
    sops-init-key
    sops-pubkey
    sops-bootstrap
    sops-get
    sops-exec
    sops-status
    loadSecretsHook;
}
