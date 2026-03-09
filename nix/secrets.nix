{ config, pkgs, lib, ... }:

let
  appConfig = import ./config.nix {};
  name      = appConfig.name;
  dbPort    = toString appConfig.database.port;
in

{
  sops.defaultSopsFile = ../secrets/${name}.yaml;


  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];


  sops.secrets."tls_cert" = {
    owner = name;
    group = name;
    mode  = "0444";
    path  = "/run/secrets/${name}/tls.crt";

    restartUnits = [ "${name}-backend.service" ];
  };

  sops.secrets."tls_key" = {
    owner = name;
    group = name;
    mode  = "0400";
    path  = "/run/secrets/${name}/tls.key";
    restartUnits = [ "${name}-backend.service" ];
  };


  sops.secrets."db_password" = {
    owner = name;
    group = name;
    mode  = "0400";
    path  = "/run/secrets/${name}/db_password";
    restartUnits = [ "${name}-backend.service" ];
  };


  sops.templates."${name}-env" = {
    owner   = name;
    group   = name;
    mode    = "0400";
    content = ''
      USE_TLS=true
      TLS_CERT_FILE=/run/secrets/${name}/tls.crt
      TLS_KEY_FILE=/run/secrets/${name}/tls.key
      PGPASSWORD=${config.sops.placeholder."db_password"}
      DB_PASSWORD=${config.sops.placeholder."db_password"}
      DATABASE_URL=postgresql://${name}:${config.sops.placeholder."db_password"}@localhost:${dbPort}/${name}
    '';
  };


  systemd.tmpfiles.rules = [
    "d /run/secrets/${name} 0750 ${name} ${name} -"
  ];
}
