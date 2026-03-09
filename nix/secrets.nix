{ config, pkgs, lib, ... }:

{
  sops.defaultSopsFile = ../secrets/cheeblr.yaml;

  # Uses the machine's SSH host key for decryption — zero extra key management
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets."tls_cert" = {
    owner = "cheeblr";
    mode = "0444";  # cert is not secret, but keep it managed
    path = "/run/secrets/cheeblr/tls.crt";
  };

  sops.secrets."tls_key" = {
    owner = "cheeblr";
    mode = "0400";
    path = "/run/secrets/cheeblr/tls.key";
  };

  sops.secrets."db_password" = {
    owner = "cheeblr";
    mode = "0400";
  };
}