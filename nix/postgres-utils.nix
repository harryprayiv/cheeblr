# PostgreSQL dev utilities.
#
# Password resolution order:
#   1. $PGPASSWORD  (set by sops in shellHook — preferred)
#   2. config.password fallback ("BOOTSTRAP_FALLBACK_ONLY_USE_SOPS") for bare `nix develop` without sops
#
# pg_hba.conf uses trust on Unix socket (local connections never need password)
# and md5 on TCP so $PGPASSWORD is actually verified for LAN / test connections.
#
{ pkgs
, lib ? pkgs.lib
, name
, database ? null
}:

let
  pgConfig =
    if database != null then { database = database; }
    else import ./config.nix { inherit name; };

  postgresql = pkgs.postgresql;
  bin = {
    pgctl     = "${postgresql}/bin/pg_ctl";
    psql      = "${postgresql}/bin/psql";
    initdb    = "${postgresql}/bin/initdb";
    createdb  = "${postgresql}/bin/createdb";
    pgIsReady = "${postgresql}/bin/pg_isready";
  };

  config = {
    dataDir  = pgConfig.database.dataDir;
    port     = pgConfig.database.port;
    user     = pgConfig.database.user;
    # config.password is the FALLBACK only; runtime value comes from $PGPASSWORD
    password = pgConfig.database.password;
  };

  settings = pgConfig.database.settings or { };

  listenAddresses         = settings.listen_addresses            or "localhost";
  maxConnections          = settings.max_connections             or 100;
  sharedBuffers           = settings.shared_buffers              or "128MB";
  dynamicSharedMemoryType = settings.dynamic_shared_memory_type  or "posix";
  logDestination          = settings.log_destination             or "stderr";
  logDirectory            = settings.log_directory               or "log";
  logFilename             = settings.log_filename                or "postgresql-%Y-%m-%d_%H%M%S.log";

  mkPgConfig = ''
    listen_addresses = '${listenAddresses}'
    port = ${toString config.port}
    unix_socket_directories = '$PGDATA'
    max_connections = ${toString maxConnections}
    shared_buffers = '${sharedBuffers}'
    dynamic_shared_memory_type = '${dynamicSharedMemoryType}'
    log_destination = '${logDestination}'
    logging_collector = on
    log_directory = '${logDirectory}'
    log_filename = '${logFilename}'
  '';

  # Trust on Unix socket → backend connects passwordless locally.
  # md5 on TCP → $PGPASSWORD enforced for integration tests / LAN access.
  mkHbaConfig = ''
    local   all   all             trust
    host    all   all   127.0.0.1/32   md5
    host    all   all   ::1/128        md5
  '';

  # Sourced at the top of every pg-* script.
  # PGPASSWORD: use whatever is already exported (sops puts it there),
  # falling back to the static config value for bare dev shells.
  envSetup = ''
    export PGPORT="''${PGPORT:-${toString config.port}}"
    export PGUSER="''${PGUSER:-${config.user}}"
    export PGDATABASE="''${PGDATABASE:-${pgConfig.database.name}}"
    export PGHOST="$PGDATA"
    export PGPASSWORD="''${PGPASSWORD:-${config.password}}"
  '';

  validateEnv = ''
    if [ -z "$PGDATA" ]; then
      echo "Error: PGDATA environment variable must be set"
      exit 1
    fi
  '';

in {
  inherit config;

  pg-start = pkgs.writeShellScriptBin "pg-start" ''
    ${envSetup}
    ${validateEnv}

    # Stop any stale cluster
    ${bin.pgctl} -D "$PGDATA" stop -m fast 2>/dev/null || true

    REAL_PGDATA=$(echo ${config.dataDir} | envsubst)
    mkdir -p "$REAL_PGDATA"
    mkdir -p "$PGDATA"

    echo "Initializing PostgreSQL cluster (user: $(whoami))..."
    ${bin.initdb} -D "$PGDATA" \
      --auth=trust \
      --no-locale \
      --encoding=UTF8 \
      --username="$(whoami)"

    cat > "$PGDATA/postgresql.conf" <<EOF
${mkPgConfig}
EOF

    cat > "$PGDATA/pg_hba.conf" <<EOF
${mkHbaConfig}
EOF

    chown -R "$(whoami)" "$PGDATA"

    echo "Starting PostgreSQL..."
    ${bin.pgctl} -D "$PGDATA" -l "$PGDATA/postgresql.log" start
    if [ $? -ne 0 ]; then
      echo "PostgreSQL failed to start. Log:"
      cat "$PGDATA/postgresql.log"
      exit 1
    fi

    echo "Waiting for PostgreSQL..."
    RETRIES=0
    while ! ${bin.pgIsReady} -h "$PGHOST" -p "$PGPORT" -q; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -eq 15 ]; then
        echo "Timed out. Log:"
        cat "$PGDATA/postgresql.log"
        exit 1
      fi
      sleep 1
      echo "  (attempt $RETRIES/15)"
    done

    # Create the application user with the runtime password.
    # On TCP connections, $PGPASSWORD (from sops) is what md5 auth checks.
    echo "Creating database user and schema..."
    PW="$PGPASSWORD"
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$(whoami)') THEN
    CREATE USER "$(whoami)" WITH PASSWORD '$PW' SUPERUSER;
  ELSE
    ALTER USER "$(whoami)" WITH PASSWORD '$PW';
  END IF;
END
\$\$;

DROP DATABASE IF EXISTS ${pgConfig.database.name};
CREATE DATABASE ${pgConfig.database.name};
GRANT ALL PRIVILEGES ON DATABASE ${pgConfig.database.name} TO "$(whoami)";
SQL

    echo ""
    echo "PostgreSQL ready: postgresql://$(whoami):***@localhost:$PGPORT/${pgConfig.database.name}"
    echo "(password sourced from sops when available)"
  '';

  pg-connect = pkgs.writeShellScriptBin "pg-connect" ''
    ${envSetup}
    ${validateEnv}
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" "$PGDATABASE"
  '';

  pg-stop = pkgs.writeShellScriptBin "pg-stop" ''
    ${envSetup}
    ${validateEnv}
    ${bin.pgctl} -D "$PGDATA" stop -m fast
  '';

  pg-cleanup = pkgs.writeShellScriptBin "pg-cleanup" ''
    ${envSetup}
    ${validateEnv}
    echo "Checking for existing PostgreSQL on port $PGPORT..."
    EXISTING_PID=$(lsof -i :"$PGPORT" -t 2>/dev/null || true)
    if [ -n "$EXISTING_PID" ]; then
      echo "Stopping process $EXISTING_PID..."
      kill "$EXISTING_PID" 2>/dev/null || true
      RETRIES=0
      while kill -0 "$EXISTING_PID" 2>/dev/null; do
        RETRIES=$((RETRIES + 1))
        [ $RETRIES -eq 10 ] && { kill -9 "$EXISTING_PID" 2>/dev/null || true; break; }
        sleep 1
      done
    fi
    if [ -d "$PGDATA" ]; then
      echo "Removing PGDATA..."
      rm -rf "$PGDATA"
    fi
  '';

  pg-backup = pkgs.writeShellScriptBin "pg-backup" ''
    ${envSetup}
    ${validateEnv}
    BACKUP_DIR="$HOME/.local/share/${name}/backups"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/${name}_$TIMESTAMP.sql"
    echo "Creating backup: $BACKUP_FILE..."
    ${postgresql}/bin/pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$PGDATABASE" \
      > "$BACKUP_FILE"
    if [ $? -eq 0 ]; then
      echo "Backup created: $BACKUP_FILE"
    else
      echo "Backup failed"; exit 1
    fi
  '';

  pg-restore = pkgs.writeShellScriptBin "pg-restore" ''
    ${envSetup}
    ${validateEnv}
    if [ -z "''${1:-}" ]; then
      echo "Usage: pg-restore <backup-file>"
      echo "Available backups:"
      ls -lh "$HOME/.local/share/${name}/backups/" 2>/dev/null || echo "  (none)"
      exit 1
    fi
    [ ! -f "$1" ] && { echo "Not found: $1"; exit 1; }
    echo "Restoring from $1..."
    ${postgresql}/bin/psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$PGDATABASE" < "$1"
  '';

  pg-rotate-credentials = pkgs.writeShellScriptBin "pg-rotate-credentials" ''
    ${envSetup}
    ${validateEnv}
    NEW_PW=$(${pkgs.openssl}/bin/openssl rand -base64 18 | tr -d '/+=' | head -c 24)
    echo "Rotating password for $PGUSER..."
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" postgres \
      -c "ALTER USER \"$PGUSER\" WITH PASSWORD '$NEW_PW';"
    if [ $? -eq 0 ]; then
      echo "Rotated."
      echo "New password: $NEW_PW"
      echo ""
      echo "Update sops:  sops secrets/${name}.yaml"
      echo "              → set db_password to the new value"
    else
      echo "Rotation failed"; exit 1
    fi
  '';

  pg-create-schema = pkgs.writeShellScriptBin "pg-create-schema" ''
    ${envSetup}
    ${validateEnv}
    [ -z "''${1:-}" ] && { echo "Usage: pg-create-schema <name>"; exit 1; }
    echo "Creating schema $1..."
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" "$PGDATABASE" <<SQL
      CREATE SCHEMA IF NOT EXISTS $1;
      GRANT ALL ON SCHEMA $1 TO "$PGUSER";
SQL
  '';

  pg-stats = pkgs.writeShellScriptBin "pg-stats" ''
    ${envSetup}
    ${validateEnv}
    echo "Database statistics: ${name}"
    echo "==============================="
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" "$PGDATABASE" <<SQL
      \echo 'Database size:'
      SELECT pg_size_pretty(pg_database_size('$PGDATABASE'));

      \echo '\nActive connections:'
      SELECT count(*) FROM pg_stat_activity;

      \echo '\nSchema sizes:'
      SELECT schema_name,
             pg_size_pretty(sum(table_size)::bigint) AS size
      FROM (
        SELECT table_schema AS schema_name,
               pg_total_relation_size(
                 quote_ident(table_schema) || '.' || quote_ident(table_name)
               ) AS table_size
        FROM information_schema.tables
      ) t
      GROUP BY schema_name
      ORDER BY sum(table_size) DESC;
SQL
  '';
}
