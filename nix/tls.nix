{ pkgs, lib ? pkgs.lib, name, mode ? "dev" }:

let
  config = import ./config.nix { inherit name; };
  tlsConfig = config.tls;
  certDir = tlsConfig.certDir;
  allDomains = tlsConfig.domains ++ tlsConfig.extraDomains;
  domainArgs = lib.concatStringsSep " " (map (d: ''"${d}"'') allDomains);

  # Sops-managed paths (used in NixOS module / systemd service context)
  sopsCertPath = "/run/secrets/cheeblr/tls.crt";
  sopsKeyPath  = "/run/secrets/cheeblr/tls.key";

in {

  # ── Dev workflow: mkcert (unchanged) ──────────────────────────────────────

  tls-setup = pkgs.writeShellScriptBin "tls-setup" ''
    set -euo pipefail
    CERT_DIR="${certDir}"
    CERT_DIR="$(echo "$CERT_DIR" | envsubst)"
    mkdir -p "$CERT_DIR"
    CERT_FILE="$CERT_DIR/${tlsConfig.certFile}"
    KEY_FILE="$CERT_DIR/${tlsConfig.keyFile}"

    echo "Installing mkcert local CA (may require sudo)..."
    ${pkgs.mkcert}/bin/mkcert -install 2>/dev/null || true

    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
      AGE=$(( $(date +%s) - $(stat -c %Y "$CERT_FILE") ))
      if [ $AGE -lt 2592000 ]; then
        echo "Certs exist and are fresh ($(( AGE / 86400 )) days old), skipping."
        exit 0
      fi
    fi

    echo "Generating TLS certificates for: ${lib.concatStringsSep ", " allDomains}"
    ${pkgs.mkcert}/bin/mkcert \
      -cert-file "$CERT_FILE" \
      -key-file  "$KEY_FILE" \
      ${domainArgs}

    echo "Cert: $CERT_FILE"
    echo "Key:  $KEY_FILE"
    ${pkgs.mkcert}/bin/mkcert -CAROOT
  '';

  tls-info = pkgs.writeShellScriptBin "tls-info" ''
    set -euo pipefail
    CERT_DIR="$(echo "${certDir}" | envsubst)"
    CERT_FILE="$CERT_DIR/${tlsConfig.certFile}"
    if [ ! -f "$CERT_FILE" ]; then
      echo "No certificate found. Run 'tls-setup' first."
      exit 1
    fi
    ${pkgs.openssl}/bin/openssl x509 -in "$CERT_FILE" -noout \
      -subject -issuer -dates -ext subjectAltName
    echo ""
    ${pkgs.mkcert}/bin/mkcert -CAROOT
  '';

  tls-clean = pkgs.writeShellScriptBin "tls-clean" ''
    set -euo pipefail
    CERT_DIR="$(echo "${certDir}" | envsubst)"
    if [ -d "$CERT_DIR" ]; then
      rm -rf "$CERT_DIR"
      echo "Removed $CERT_DIR"
    fi
  '';

  # ── Sops secret management helpers ────────────────────────────────────────

  # Update the encrypted secrets/cheeblr.yaml from freshly-generated mkcert certs
  tls-sops-update = pkgs.writeShellScriptBin "tls-sops-update" ''
    set -euo pipefail
    CERT_DIR="${certDir}"
    CERT_DIR="$(echo "$CERT_DIR" | envsubst)"
    CERT_FILE="$CERT_DIR/${tlsConfig.certFile}"
    KEY_FILE="$CERT_DIR/${tlsConfig.keyFile}"
    SECRETS_FILE="$(pwd)/secrets/cheeblr.yaml"

    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
      echo "No local certs found. Run 'tls-setup' first."
      exit 1
    fi

    if [ ! -f "$SECRETS_FILE" ]; then
      echo "No sops secrets file found at $SECRETS_FILE"
      echo "Bootstrap with: sops secrets/cheeblr.yaml"
      exit 1
    fi

    CERT_CONTENT="$(cat "$CERT_FILE")"
    KEY_CONTENT="$(cat "$KEY_FILE")"

    echo "Updating TLS cert in sops secrets..."
    ${pkgs.sops}/bin/sops --set '["tls_cert"] "'"$CERT_CONTENT"'"' "$SECRETS_FILE"
    ${pkgs.sops}/bin/sops --set '["tls_key"] "'"$KEY_CONTENT"'"' "$SECRETS_FILE"
    echo "Done. Commit secrets/cheeblr.yaml when ready."
  '';

  # Extract sops-managed certs to local paths (for dev machines pulling from shared secrets)
  tls-sops-extract = pkgs.writeShellScriptBin "tls-sops-extract" ''
    set -euo pipefail
    CERT_DIR="${certDir}"
    CERT_DIR="$(echo "$CERT_DIR" | envsubst)"
    mkdir -p "$CERT_DIR"
    SECRETS_FILE="$(pwd)/secrets/cheeblr.yaml"

    if [ ! -f "$SECRETS_FILE" ]; then
      echo "No sops secrets file found."
      exit 1
    fi

    echo "Extracting TLS certs from sops secrets..."
    ${pkgs.sops}/bin/sops --extract '["tls_cert"]' --decrypt "$SECRETS_FILE" \
      > "$CERT_DIR/${tlsConfig.certFile}"
    ${pkgs.sops}/bin/sops --extract '["tls_key"]' --decrypt "$SECRETS_FILE" \
      > "$CERT_DIR/${tlsConfig.keyFile}"
    chmod 600 "$CERT_DIR/${tlsConfig.keyFile}"
    echo "Extracted to $CERT_DIR"
  '';

  # Env vars for NixOS service deployment (points at sops-managed paths)
  deployTlsEnv = {
    USE_TLS      = "true";
    TLS_CERT_FILE = sopsCertPath;
    TLS_KEY_FILE  = sopsKeyPath;
  };

  # Paths for use in systemd service configs
  inherit sopsCertPath sopsKeyPath;
}