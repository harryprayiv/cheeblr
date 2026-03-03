{ pkgs, lib ? pkgs.lib, name }:

let
  config = import ./config.nix { inherit name; };
  tlsConfig = config.tls;
  certDir = tlsConfig.certDir;
  allDomains = tlsConfig.domains ++ tlsConfig.extraDomains;
  domainArgs = lib.concatStringsSep " " (map (d: ''"${d}"'') allDomains);

in {
  # Generate certs with mkcert (install local CA + generate cert)
  tls-setup = pkgs.writeShellScriptBin "tls-setup" ''
    set -euo pipefail
    
    CERT_DIR="${certDir}"
    CERT_DIR="$(echo "$CERT_DIR" | envsubst)"
    mkdir -p "$CERT_DIR"
    
    CERT_FILE="$CERT_DIR/${tlsConfig.certFile}"
    KEY_FILE="$CERT_DIR/${tlsConfig.keyFile}"
    
    # Install local CA if not already done
    echo "Installing mkcert local CA (may require sudo)..."
    ${pkgs.mkcert}/bin/mkcert -install 2>/dev/null || true
    
    # Only regenerate if certs don't exist or are older than 30 days
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
      AGE=$(( $(date +%s) - $(stat -c %Y "$CERT_FILE") ))
      if [ $AGE -lt 2592000 ]; then
        echo "Certs exist and are fresh ($(( AGE / 86400 )) days old), skipping generation."
        echo "  Cert: $CERT_FILE"
        echo "  Key:  $KEY_FILE"
        exit 0
      fi
      echo "Certs are older than 30 days, regenerating..."
    fi
    
    echo "Generating TLS certificates for: ${lib.concatStringsSep ", " allDomains}"
    ${pkgs.mkcert}/bin/mkcert \
      -cert-file "$CERT_FILE" \
      -key-file "$KEY_FILE" \
      ${domainArgs}
    
    echo "Certificates generated:"
    echo "  Cert: $CERT_FILE"
    echo "  Key:  $KEY_FILE"
    echo ""
    echo "CA root location:"
    ${pkgs.mkcert}/bin/mkcert -CAROOT
  '';

  # Show cert info
  tls-info = pkgs.writeShellScriptBin "tls-info" ''
    set -euo pipefail
    CERT_DIR="$(echo "${certDir}" | envsubst)"
    CERT_FILE="$CERT_DIR/${tlsConfig.certFile}"
    
    if [ ! -f "$CERT_FILE" ]; then
      echo "No certificate found. Run 'tls-setup' first."
      exit 1
    fi
    
    echo "Certificate details:"
    ${pkgs.openssl}/bin/openssl x509 -in "$CERT_FILE" -noout \
      -subject -issuer -dates -ext subjectAltName
    echo ""
    echo "CA root:"
    ${pkgs.mkcert}/bin/mkcert -CAROOT
  '';

  # Clean certs
  tls-clean = pkgs.writeShellScriptBin "tls-clean" ''
    set -euo pipefail
    CERT_DIR="$(echo "${certDir}" | envsubst)"
    if [ -d "$CERT_DIR" ]; then
      rm -rf "$CERT_DIR"
      echo "Removed $CERT_DIR"
    else
      echo "No cert directory found."
    fi
  '';
}