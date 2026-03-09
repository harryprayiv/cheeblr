{ config, pkgs, lib, ... }:

# NixOS sops-nix integration for cheeblr.
#
# This module is activated at NixOS configuration time.  It decrypts secrets
# at system activation and places them at well-known paths under /run/secrets.
# The backend reads TLS_CERT_FILE / TLS_KEY_FILE / DATABASE_URL from the
# environment, which systemd injects via EnvironmentFile or PassEnvironment.
#
# Dev counterpart: nix/sops-dev.nix + `with-secrets` for local workstation use.

{
  sops.defaultSopsFile = ../secrets/cheeblr.yaml;

  # Decrypt using the host's SSH ed25519 key (converted to age internally by
  # sops-nix).  This key is present on every NixOS machine after first boot.
  # For VMs / OCI containers, ensure the host key is stable across rebuilds
  # (e.g. bind-mount /etc/ssh from a persistent volume in Talos).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Alternatively, use a dedicated age key stored on disk:
  # sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  # sops.generateAgeKeysFromSSH = false;

  # ── TLS ──────────────────────────────────────────────────────────────────

  sops.secrets."tls_cert" = {
    owner = "cheeblr";
    group = "cheeblr";
    mode  = "0444";
    path  = "/run/secrets/cheeblr/tls.crt";
    # Restart the backend whenever the cert changes (e.g. renewal)
    restartUnits = [ "cheeblr-backend.service" ];
  };

  sops.secrets."tls_key" = {
    owner = "cheeblr";
    group = "cheeblr";
    mode  = "0400";
    path  = "/run/secrets/cheeblr/tls.key";
    restartUnits = [ "cheeblr-backend.service" ];
  };

  # ── Database ─────────────────────────────────────────────────────────────

  sops.secrets."db_password" = {
    owner = "cheeblr";
    group = "cheeblr";
    mode  = "0400";
    path  = "/run/secrets/cheeblr/db_password";
    restartUnits = [ "cheeblr-backend.service" ];
  };

  # ── Rendered environment file for systemd ─────────────────────────────────
  #
  # sops-nix can render a secrets-interpolated EnvironmentFile.  The backend
  # service's EnvironmentFile points here so no secrets touch the Nix store.
  #
  # Add this to your backend systemd service:
  #   serviceConfig.EnvironmentFile = config.sops.templates."cheeblr-env".path;

  sops.templates."cheeblr-env" = {
    owner   = "cheeblr";
    group   = "cheeblr";
    mode    = "0400";
    content = ''
      USE_TLS=true
      TLS_CERT_FILE=/run/secrets/cheeblr/tls.crt
      TLS_KEY_FILE=/run/secrets/cheeblr/tls.key
      PGPASSWORD=${config.sops.placeholder."db_password"}
      DB_PASSWORD=${config.sops.placeholder."db_password"}
      DATABASE_URL=postgresql://cheeblr:${config.sops.placeholder."db_password"}@localhost:5432/cheeblr
    '';
  };

  # ── Ensure secret directory exists with correct permissions ───────────────

  systemd.tmpfiles.rules = [
    "d /run/secrets/cheeblr 0750 cheeblr cheeblr -"
  ];
}
