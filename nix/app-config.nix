{ name, ... }:
{
  database = {
    name = name;
    user = "$(whoami)";
    password = "postgres";
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
    viteport = 5173;
    settings = {
    };
  };
  purescript = {
    spagoFile = "./frontend/spago.yaml";
    codeDirs = [
      "./frontend/app"
      "./frontend/src"
    ];
    tests = "./frontend/test";
    settings = {
    };
  };
  haskell = {
    cabalFile = "./backend/${name}-backend.cabal";
    codeDirs = [
      "./backend/app"
      "./backend/src"
    ];
    tests = "./backend/test";
    settings = {
    };
  };
}