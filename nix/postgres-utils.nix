{ pkgs
, lib ? pkgs.lib
, name
, database ? null  # Allow database to be passed in from devShell.nix
}:

let
  # Import app config if database not passed in
  pgConfig = if database != null then 
    { database = database; } 
  else 
    import ./config.nix { inherit name; };

  postgresql = pkgs.postgresql;
  bin = {
    pgctl = "${postgresql}/bin/pg_ctl";
    psql = "${postgresql}/bin/psql";
    initdb = "${postgresql}/bin/initdb";
    createdb = "${postgresql}/bin/createdb";
    pgIsReady = "${postgresql}/bin/pg_isready";
  };

  config = {
    dataDir = pgConfig.database.dataDir;
    port = pgConfig.database.port;
    user = pgConfig.database.user;
    password = pgConfig.database.password;
  };

  # Ensure we handle the settings section properly
  settings = pgConfig.database.settings or {};

  # Get settings with defaults
  listenAddresses = settings.listen_addresses or "localhost";
  maxConnections = settings.max_connections or 100;
  sharedBuffers = settings.shared_buffers or "128MB";
  dynamicSharedMemoryType = settings.dynamic_shared_memory_type or "posix";
  logDestination = settings.log_destination or "stderr";
  logDirectory = settings.log_directory or "log";
  logFilename = settings.log_filename or "postgresql-%Y-%m-%d_%H%M%S.log";

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

  mkHbaConfig = ''
    local   all             all                                     trust
    host    all             all             127.0.0.1/32           trust
    host    all             all             ::1/128                trust
  '';

  envSetup = ''
    export PGPORT="''${PGPORT:-${toString config.port}}"
    export PGUSER="''${PGUSER:-${config.user}}"
    export PGDATABASE="''${PGDATABASE:-${pgConfig.database.name}}"
    export PGHOST="$PGDATA"
  '';

  validateEnv = ''
    if [ -z "$PGDATA" ]; then
      echo "Error: PGDATA environment variable must be set"
      exit 1
    fi
  '';

in {
  inherit config;

  pg-cleanup = pkgs.writeShellScriptBin "pg-cleanup" ''
    ${envSetup}
    ${validateEnv}

    echo "Checking for existing PostgreSQL processes on port $PGPORT..."
    EXISTING_PID=$(lsof -i :$PGPORT -t || true)
    
    if [ ! -z "$EXISTING_PID" ]; then
      echo "Found PostgreSQL process ($EXISTING_PID) using port $PGPORT"
      echo "Stopping process..."
      kill $EXISTING_PID || true
      
      # Wait for process to stop
      RETRIES=0
      while kill -0 $EXISTING_PID 2>/dev/null; do
        RETRIES=$((RETRIES+1))
        if [ $RETRIES -eq 10 ]; then
          echo "Process not responding, forcing shutdown..."
          kill -9 $EXISTING_PID
          break
        fi
        sleep 1
      done
    fi

    if [ -d "$PGDATA" ]; then
      echo "Removing PGDATA directory..."
      rm -rf "$PGDATA"
    fi
  '';

  pg-start = pkgs.writeShellScriptBin "pg-start" ''
    ${envSetup}
    ${validateEnv}

    # Run cleanup first
    ${bin.pgctl} -D "$PGDATA" stop -m fast 2>/dev/null || true
    
    # Create user-owned data directory
    REAL_PGDATA=$(echo ${config.dataDir} | envsubst)
    mkdir -p "$REAL_PGDATA"
    mkdir -p "$PGDATA"

    echo "Initializing with user: $(whoami)"
    ${bin.initdb} -D "$PGDATA" \
        --auth=trust \
        --no-locale \
        --encoding=UTF8 \
        --username="$(whoami)"

    # Write config files
    cat > "$PGDATA/postgresql.conf" << EOF
${mkPgConfig}
EOF

    cat > "$PGDATA/pg_hba.conf" << EOF
${mkHbaConfig}
EOF

    # Ensure all files in PGDATA are owned by current user
    chown -R $(whoami) "$PGDATA"

    echo "Starting PostgreSQL..."
    ${bin.pgctl} -D "$PGDATA" -l "$PGDATA/postgresql.log" start

    if [ $? -ne 0 ]; then
      echo "PostgreSQL failed to start. Here's the log:"
      cat "$PGDATA/postgresql.log"
      exit 1
    fi

    echo "Waiting for PostgreSQL to be ready..."
    RETRIES=0
    while ! ${bin.pgIsReady} -h "$PGHOST" -p "$PGPORT" -q; do
      RETRIES=$((RETRIES+1))
      if [ $RETRIES -eq 10 ]; then
        echo "PostgreSQL failed to become ready. Here's the log:"
        cat "$PGDATA/postgresql.log"
        exit 1
      fi
      sleep 1
      echo "Still waiting... (attempt $RETRIES/10)"
    done

    echo "Creating database and user..."
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" postgres << EOF
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$(whoami)') THEN
        CREATE USER "$(whoami)" WITH PASSWORD '${config.password}' SUPERUSER;
      END IF;
    END
    \$\$;

    DROP DATABASE IF EXISTS ${pgConfig.database.name};
    CREATE DATABASE ${pgConfig.database.name};
    GRANT ALL PRIVILEGES ON DATABASE ${pgConfig.database.name} TO "$(whoami)";
EOF

    echo "PostgreSQL is ready at: postgresql://$(whoami):${config.password}@localhost:$PGPORT/${pgConfig.database.name}"
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

  # New Utilities based on best practices for PostgreSQL databases
  # Backup database to a timestamp-named file
  pg-backup = pkgs.writeShellScriptBin "pg-backup" ''
    ${envSetup}
    ${validateEnv}
    
    BACKUP_DIR="$HOME/.local/share/${name}/backups"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/${name}_$TIMESTAMP.sql"
    
    echo "Creating backup at $BACKUP_FILE..."
    ${postgresql}/bin/pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$PGDATABASE" > "$BACKUP_FILE"
    
    if [ $? -eq 0 ]; then
      echo "Backup created successfully"
      echo "Location: $BACKUP_FILE"
    else
      echo "Backup failed"
      exit 1
    fi
  '';

  # Restore from a specific backup
  pg-restore = pkgs.writeShellScriptBin "pg-restore" ''
    ${envSetup}
    ${validateEnv}
    
    if [ -z "$1" ]; then
      echo "Usage: pg-restore <backup-file>"
      echo "Available backups:"
      ls -l "$HOME/.local/share/${name}/backups"
      exit 1
    fi

    if [ ! -f "$1" ]; then
      echo "Backup file not found: $1"
      exit 1
    fi

    echo "Restoring from $1..."
    ${postgresql}/bin/psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" "$PGDATABASE" < "$1"
  '';

  # Rotate credentials
  pg-rotate-credentials = pkgs.writeShellScriptBin "pg-rotate-credentials" ''
    ${envSetup}
    ${validateEnv}
    
    NEW_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -base64 12)
    
    echo "Rotating password for user $PGUSER..."
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" postgres -c \
      "ALTER USER \"$PGUSER\" WITH PASSWORD '$NEW_PASSWORD';"
    
    if [ $? -eq 0 ]; then
      echo "Password rotated successfully"
      echo "New credentials:"
      echo "User: $PGUSER"
      echo "Password: $NEW_PASSWORD"
      echo "Please update your environment variables accordingly"
    else
      echo "Password rotation failed"
      exit 1
    fi
  '';

  # Create a new schema (avoiding public schema)
  pg-create-schema = pkgs.writeShellScriptBin "pg-create-schema" ''
    ${envSetup}
    ${validateEnv}
    
    if [ -z "$1" ]; then
      echo "Usage: pg-create-schema <schema-name>"
      exit 1
    fi

    echo "Creating schema $1..."
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" "$PGDATABASE" << EOF
      CREATE SCHEMA IF NOT EXISTS $1;
      GRANT ALL ON SCHEMA $1 TO "$PGUSER";
EOF
  '';

  # Monitor database stats
  pg-stats = pkgs.writeShellScriptBin "pg-stats" ''
    ${envSetup}
    ${validateEnv}
    
    echo "Database Statistics for ${name}"
    echo "==============================="
    
    ${bin.psql} -h "$PGHOST" -p "$PGPORT" "$PGDATABASE" << EOF
      \echo 'Database Size:'
      SELECT pg_size_pretty(pg_database_size('$PGDATABASE'));
      
      \echo '\nConnection Count:'
      SELECT count(*) FROM pg_stat_activity;
      
      \echo '\nSchema Sizes:'
      SELECT schema_name, pg_size_pretty(sum(table_size)::bigint) as size
      FROM (
        SELECT table_schema as schema_name,
               pg_total_relation_size(quote_ident(table_schema) || '.' || quote_ident(table_name)) as table_size
        FROM information_schema.tables
      ) t
      GROUP BY schema_name
      ORDER BY sum(table_size) DESC;
EOF
  '';
}