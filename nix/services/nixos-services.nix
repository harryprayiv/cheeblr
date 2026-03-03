{ config, lib, pkgs, name, ... }:

{
  options.services.${name} = {
    enable = lib.mkEnableOption "${name} application";
    
    backendPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };
    
    frontendPort = lib.mkOption {
      type = lib.types.port;
      default = 5173;
    };
  };

  config = lib.mkIf config.services.${name}.enable {
    networking.firewall.allowedTCPPorts = [
      config.services.${name}.backendPort
      config.services.${name}.frontendPort
    ];
    
    # Backend service
    systemd.services."${name}-backend" = {
      description = "${name} Haskell Backend";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${config.services.${name}.package}/bin/${name}-backend";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Frontend service  
    systemd.services."${name}-frontend" = {
      description = "${name} PureScript Frontend";
      after = [ "${name}-backend.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "simple";
        WorkingDirectory = "/var/lib/${name}/frontend";
        ExecStart = "${pkgs.nodejs}/bin/npx vite --host 0.0.0.0 --port ${toString config.services.${name}.frontendPort}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}