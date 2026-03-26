{ name ? "cheeblr", ... }:
{
  # Project name - used EVERYWHERE
  inherit name;

  # Network settings
  network = {
    host = "localhost";
    bindAddress = "0.0.0.0";
  };

  # Add to the config attrset:
  tls = {
    enable = true;  # set false to stay on HTTP for quick local dev
    certDir = "$HOME/.local/share/${name}/certs";
    # mkcert generates these
    certFile = "cert.pem";
    keyFile = "key.pem";
    # SANs for cert generation
    domains = [ "localhost" "127.0.0.1" "::1" ];
    # Add your LAN IP here
    extraDomains = [ "192.168.8.248" ];
  };

  database = {
    name = name;
    user = "$(whoami)";
    password = "BOOTSTRAP_FALLBACK_ONLY_USE_SOPS";
    port = 5432;
    dataDir = "$HOME/.local/share/${name}/postgres";
    settings = {
      max_connections = 100;
      shared_buffers = "128MB";
      dynamic_shared_memory_type = "posix";
      log_destination = "stderr";
      logging_collector = true;
      log_directory = "log";
      log_filename = "postgresql-%Y-%m-%d_%H%M%S.log";
      log_min_messages = "info";
      log_min_error_statement = "info";
      log_connections = true;
      listen_addresses = "localhost";
    };
  };

  vite = {
    port = 5173;
    settings = {};
  };

  purescript = {
    spagoFile = "./frontend/spago.yaml";
    codeDirs = [
      "./frontend/app"
      "./frontend/src"
    ];
    tests = "./frontend/test";
    settings = {};
  };

  haskell = {
    port = 8080;
    cabalFile = "./backend/${name}-backend.cabal";
    codeDirs = [
      "./backend/app"
      "./backend/src"
    ];
    tests = "./backend/test";
    settings = {};
  };

  # Data directories
  dataDir = "$HOME/.local/share/${name}";
  logDir  = "$HOME/.local/share/${name}/logs";
  logFile = "$HOME/.local/share/${name}/logs/${name}-compliance.log";
}