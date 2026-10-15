{ pkgs, lib ? pkgs.lib, name }:

# test-model: the model test of the sale and register commands.
#
# It starts a throwaway PostgreSQL and a backend on their own port, creates
# the admin account, and runs the cabal test suite cheeblr-model-tests
# (backend/model-test) against that backend. Nothing it starts or writes
# outlives the command.
#
# Settings, all optional, read from the environment:
#   MODEL_TESTS          sequences for the one-puppet test, default 100
#   MODEL_SIZE           most commands in one sequence, default 60
#   MODEL_PUPPETS        puppets running at once, default 4
#   MODEL_PARALLEL_TESTS rounds of the puppets test, default 30
#   MODEL_ROTATION_SECS  the backend's session token rotation interval,
#                        default 5, so that rotation happens during a run
#   RESTOCK_ON_VOID      restock or no-restock, default no-restock
#   RESTOCK_ON_REFUND    restock or no-restock, default no-restock
#   HEDGEHOG_SEED        "a b", the two numbers of a reported Seed; runs the
#                        same sequences again

let
  config = import ./config.nix { inherit name; };

  host = config.network.host;
  backendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head config.haskell.codeDirs));

  # test-integration uses 18080, test-sale 18081 and 18082.
  modelBackendPort = "18083";
  modelDbPort = "5432";

  pg   = pkgs.postgresql;
  curl = "${pkgs.curl}/bin/curl";

  test-model = pkgs.writeShellScriptBin "test-model" ''
    set -uo pipefail

    echo "════════════════════════════════════════════"
    echo "  ${name}: model test against a throwaway database"
    echo "════════════════════════════════════════════"
    echo ""

    export USE_TLS="false"
    export TEST_PGDATA="''${TMPDIR:-/tmp}/${name}-model-$$"
    export PGDATA="$TEST_PGDATA"
    export PGPORT="${modelDbPort}"
    export PGUSER="$(whoami)"
    export PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS"
    export PGDATABASE="${name}"
    export PGHOST="$PGDATA"
    export PORT="${modelBackendPort}"

    # The backend and the model read the same two variables, so they
    # cannot disagree about the policy.
    export RESTOCK_ON_VOID="''${RESTOCK_ON_VOID:-no-restock}"
    export RESTOCK_ON_REFUND="''${RESTOCK_ON_REFUND:-no-restock}"
    export TOKEN_ROTATION_SECS="''${MODEL_ROTATION_SECS:-5}"
    BASE_URL="http://${host}:${modelBackendPort}"

    WORK="$(mktemp -d)"
    BACKEND_PID=""

    cleanup() {
      local exit_code=$?
      echo ""
      echo "Cleaning up..."
      if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill -TERM "$BACKEND_PID" 2>/dev/null || true
        for _i in $(seq 1 5); do
          kill -0 "$BACKEND_PID" 2>/dev/null || break
          sleep 1
        done
        kill -9 "$BACKEND_PID" 2>/dev/null || true
      fi
      ${pkgs.lsof}/bin/lsof -ti :${modelBackendPort} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
      if [ -d "$TEST_PGDATA" ]; then
        ${pg}/bin/pg_ctl -D "$TEST_PGDATA" stop -m immediate > /dev/null 2>&1 || true
        rm -rf "$TEST_PGDATA"
      fi
      rm -rf "$WORK"
      exit $exit_code
    }
    trap cleanup EXIT INT TERM

    echo "Starting throwaway PostgreSQL in $TEST_PGDATA ..."
    mkdir -p "$TEST_PGDATA"
    ${pg}/bin/initdb -D "$TEST_PGDATA" \
      --auth=trust --no-locale --encoding=UTF8 \
      --username="$(whoami)" > /dev/null 2>&1 || { echo "initdb failed"; exit 1; }

    cat > "$TEST_PGDATA/postgresql.conf" << EOF
listen_addresses = '''
port = ${modelDbPort}
unix_socket_directories = '$TEST_PGDATA'
max_connections = 40
shared_buffers = '32MB'
dynamic_shared_memory_type = posix
logging_collector = off
EOF

    cat > "$TEST_PGDATA/pg_hba.conf" << EOF
local   all   all   trust
EOF

    ${pg}/bin/pg_ctl -D "$TEST_PGDATA" -l "$TEST_PGDATA/postgresql.log" start > /dev/null 2>&1

    RETRIES=0
    while ! ${pg}/bin/pg_isready -h "$PGHOST" -p "$PGPORT" -q 2>/dev/null; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -ge 15 ]; then
        echo "PostgreSQL failed to start. Log:"
        cat "$TEST_PGDATA/postgresql.log" || true
        exit 1
      fi
      sleep 1
    done

    ${pg}/bin/psql -X -q -h "$PGHOST" -p "$PGPORT" postgres \
      -c "CREATE DATABASE ${name};" > /dev/null || { echo "could not create the test database"; exit 1; }
    echo "✓ PostgreSQL ready (unix socket only)"

    # Build the test suite before the backend starts, so that a compile
    # error is reported at once and not after the wait for the backend.
    echo "Building ${name}-model-tests ..."
    (cd ${backendPath} && cabal build ${name}-model-tests) > "$WORK/build.log" 2>&1 || {
      echo "The model test suite did not build:"
      tail -n 60 "$WORK/build.log"
      exit 1
    }
    echo "✓ Test suite built"

    echo "Starting backend on port ${modelBackendPort} ..."
    (cd ${backendPath} && cabal run ${name}-backend >> "$WORK/backend.log" 2>&1) &
    BACKEND_PID=$!
    RETRIES=0
    while ! ${curl} -s "$BASE_URL/openapi.json" > /dev/null 2>&1; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -ge 120 ] || ! kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo "Backend did not come up. Last lines of its log:"
        tail -n 40 "$WORK/backend.log" || true
        exit 1
      fi
      sleep 1
    done
    echo "✓ Backend ready at $BASE_URL"

    BOOT_OUT=$(cd ${backendPath} && cabal run ${name}-bootstrap-admin -v0 2>&1)
    ADMIN_PASS=$(echo "$BOOT_OUT" | grep "^password" | awk '{print $3}' || true)
    if [ -z "$ADMIN_PASS" ]; then
      echo "Could not create the admin account. Output:"
      echo "$BOOT_OUT"
      exit 1
    fi
    echo "✓ Admin account created"
    echo ""

    export MODEL_BASE_URL="$BASE_URL"
    export MODEL_ADMIN_PASSWORD="$ADMIN_PASS"

    (cd ${backendPath} && cabal test ${name}-model-tests --test-show-details=streaming)
    RESULT=$?

    echo ""
    echo "════════════════════════════════════════════"
    if [ $RESULT -eq 0 ]; then
      echo "  ✓ THE BACKEND MATCHES THE MODEL"
    else
      echo "  ✗ THE BACKEND AND THE MODEL DISAGREE"
      echo "  The report above names the failing check and the shortest"
      echo "  command sequence that shows it."
      echo "  Backend log: last 30 lines"
      tail -n 30 "$WORK/backend.log" || true
    fi
    echo "════════════════════════════════════════════"

    [ $RESULT -eq 0 ]
  '';

in {
  inherit test-model;
}