{ pkgs, lib ? pkgs.lib, name }:

# test-sale: runs the sale path against a throwaway PostgreSQL cluster and a
# backend started for the test, then checks the rows in the database.
#
# Nothing here touches the development database. The cluster lives in a
# temporary directory, listens on a unix socket only, and is removed on exit.
#
# Set BACKEND_BIN to a pre-built backend binary to skip `cabal run`.
#
# This file is the harness: the throwaway database, the backend, the seed
# data and the helper functions. The checks themselves are plain bash files
# in ./sale-checks, read in below in the order they run. They share one
# shell, so a later file can use what an earlier one set. A new file has to
# be added to git before the flake can see it.

let
  config = import ./config.nix { inherit name; };

  host = config.network.host;
  backendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head config.haskell.codeDirs));

  saleBackendPort = "18081";
  # A second port, used only to start a backend that is expected to refuse
  # its configuration and exit.
  saleConfigPort = "18082";
  saleDbPort = "5432";

  pg   = pkgs.postgresql;
  curl = "${pkgs.curl}/bin/curl";
  jq   = "${pkgs.jq}/bin/jq";

  test-sale = pkgs.writeShellScriptBin "test-sale" ''
    set -uo pipefail

    echo "════════════════════════════════════════════"
    echo "  ${name}: sale path against a throwaway database"
    echo "════════════════════════════════════════════"
    echo ""

    export USE_TLS="false"
    export TEST_PGDATA="''${TMPDIR:-/tmp}/${name}-sale-$$"
    export PGDATA="$TEST_PGDATA"
    export PGPORT="${saleDbPort}"
    export PGUSER="$(whoami)"
    export PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS"
    export PGDATABASE="${name}"
    export PGHOST="$PGDATA"
    export PORT="${saleBackendPort}"
    # The backend has no default for these two. The checks start with both
    # on no-restock. Group M restarts the backend with both on restock.
    export RESTOCK_ON_VOID="no-restock"
    export RESTOCK_ON_REFUND="no-restock"
    BASE_URL="http://${host}:${saleBackendPort}"

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
      ${pkgs.lsof}/bin/lsof -ti :${saleBackendPort} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
      ${pkgs.lsof}/bin/lsof -ti :${saleConfigPort} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
      if [ -d "$TEST_PGDATA" ]; then
        ${pg}/bin/pg_ctl -D "$TEST_PGDATA" stop -m immediate > /dev/null 2>&1 || true
        rm -rf "$TEST_PGDATA"
      fi
      rm -rf "$WORK"
      exit $exit_code
    }
    trap cleanup EXIT INT TERM

    # ── Database ────────────────────────────────────────────────────────────

    echo "Starting throwaway PostgreSQL in $TEST_PGDATA ..."
    mkdir -p "$TEST_PGDATA"
    ${pg}/bin/initdb -D "$TEST_PGDATA" \
      --auth=trust --no-locale --encoding=UTF8 \
      --username="$(whoami)" > /dev/null 2>&1 || { echo "initdb failed"; exit 1; }

    cat > "$TEST_PGDATA/postgresql.conf" << EOF
listen_addresses = '''
port = ${saleDbPort}
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

    sql() {
      ${pg}/bin/psql -X -w -At -h "$PGHOST" -p "$PGPORT" "$PGDATABASE" -c "$1"
    }

    # ── Backend ─────────────────────────────────────────────────────────────

    # Runs the backend in the foreground with the environment it is given.
    run_backend() {
      if [ -n "''${BACKEND_BIN:-}" ] && [ -x "''${BACKEND_BIN}" ]; then
        "''${BACKEND_BIN}"
      else
        (cd ${backendPath} && cabal run ${name}-backend)
      fi
    }

    # Starts the backend in the background with the current environment and
    # waits until it answers. Its output is appended to one log.
    start_backend() {
      local retries=0
      (run_backend >> "$WORK/backend.log" 2>&1) &
      BACKEND_PID=$!
      while ! ${curl} -s "$BASE_URL/openapi.json" > /dev/null 2>&1; do
        retries=$((retries + 1))
        if [ $retries -ge 120 ] || ! kill -0 "$BACKEND_PID" 2>/dev/null; then
          echo "Backend did not come up. Last lines of its log:"
          tail -n 40 "$WORK/backend.log" || true
          return 1
        fi
        sleep 1
      done
    }

    # Stops the backend and waits until its port no longer answers.
    stop_backend() {
      local waited=0
      if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill -TERM "$BACKEND_PID" 2>/dev/null || true
      fi
      sleep 1
      ${pkgs.lsof}/bin/lsof -ti :${saleBackendPort} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
      while ${curl} -s "$BASE_URL/openapi.json" > /dev/null 2>&1; do
        waited=$((waited + 1))
        if [ $waited -ge 15 ]; then
          return 1
        fi
        sleep 1
      done
      BACKEND_PID=""
    }

    # Starts a backend on the second port with one variable unset (second
    # argument empty) or set to the second argument. Prints "refused" when
    # the backend exits by itself and its output names the variable, and
    # says what happened otherwise.
    config_outcome() {
      local log="$WORK/config-$1.log" pid waited=0
      : > "$log"
      (
        export PORT="${saleConfigPort}"
        if [ -z "$2" ]; then unset "$1"; else export "$1=$2"; fi
        run_backend
      ) >> "$log" 2>&1 &
      pid=$!
      while kill -0 "$pid" 2>/dev/null && [ $waited -lt 120 ]; do
        sleep 1
        waited=$((waited + 1))
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        ${pkgs.lsof}/bin/lsof -ti :${saleConfigPort} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
        echo "kept running"
      elif grep -q "$1" "$log"; then
        echo "refused"
      else
        echo "exited without naming $1"
      fi
    }

    echo "Starting backend on port ${saleBackendPort} ..."
    start_backend || exit 1
    echo "✓ Backend ready at $BASE_URL"

    # ── Admin account and seed data ─────────────────────────────────────────

    BOOT_OUT=$(cd ${backendPath} && cabal run ${name}-bootstrap-admin -v0 2>&1)
    ADMIN_PASS=$(echo "$BOOT_OUT" | grep "^password" | awk '{print $3}' || true)
    if [ -z "$ADMIN_PASS" ]; then
      echo "Could not create the admin account. Output:"
      echo "$BOOT_OUT"
      exit 1
    fi
    ADMIN_ID=$(sql "select id from users where username = 'admin'")
    echo "✓ Admin account created"

    SKU_MAIN="aaaaaaaa-0000-4000-8000-000000000001"
    SKU_LAST="aaaaaaaa-0000-4000-8000-000000000002"
    REGISTER_ID="bbbbbbbb-0000-4000-8000-000000000001"
    LOCATION_ID="cccccccc-0000-4000-8000-000000000001"

    seed_item() {
      sql "insert into menu_items (sort, sku, brand, name, price, measure_unit, per_package, quantity, category, subcategory, description, tags, effects) values (0, '$1', 'Test', '$2', 1999, 'g', '3.5', $3, 'Flower', 'Indoor', 'seeded by test-sale', '{}', '{}')" > /dev/null \
        && sql "insert into strain_lineage (sku, thc, cbg, strain, creator, species, dominant_terpene, terpenes, lineage, leafly_url, img) values ('$1', '20%', '1%', 'Test', 'Test', 'Hybrid', 'Myrcene', '{}', '{}', 'https://example.com', 'https://example.com/i.jpg')" > /dev/null
    }
    seed_item "$SKU_MAIN" "Main item" 100 || { echo "could not seed the main item"; exit 1; }
    seed_item "$SKU_LAST" "Last unit" 1   || { echo "could not seed the last-unit item"; exit 1; }
    echo "✓ Seeded two menu items (stock 100 and stock 1)"
    echo ""

    # ── Helpers ─────────────────────────────────────────────────────────────

    # Tool paths for the check files, which cannot use Nix interpolation.
    CURL="${curl}"
    JQ="${jq}"
    PSQL="${pg}/bin/psql"

    PASS=0
    FAIL=0
    TOKEN=""

    check() {
      if [ "$2" = "$3" ]; then
        echo "  ✓ $1 ($3)"
        PASS=$((PASS + 1))
      else
        echo "  ✗ $1: expected $2, got $3"
        FAIL=$((FAIL + 1))
      fi
    }

    # POSTs a JSON body as the logged-in admin and prints the HTTP status.
    post() {
      ${curl} -s -o /dev/null -w "%{http_code}" --max-time 30 \
        -H "Cookie: cheeblr_session=$TOKEN" \
        -H "Content-Type: application/json" \
        -X POST -d "$2" "$BASE_URL$1"
    }

    # Sends a DELETE as the logged-in admin and prints the HTTP status.
    del() {
      ${curl} -s -o /dev/null -w "%{http_code}" --max-time 30 \
        -H "Cookie: cheeblr_session=$TOKEN" \
        -X DELETE "$BASE_URL$1"
    }

    # Sends a GET as the logged-in user and prints the HTTP status.
    get_code() {
      ${curl} -s -o /dev/null -w "%{http_code}" --max-time 30 \
        -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL$1"
    }

    # Sends a GET as the logged-in user and prints the response body.
    get_body() {
      ${curl} -s --max-time 30 \
        -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL$1"
    }

    add_body() {
      ${jq} -nc --arg s "$1" --arg k "$2" --argjson q "$3" \
        '{addItemSaleId: $s, addItemSku: $k, addItemQuantity: $q}'
    }

    pay_body() {
      ${jq} -nc --arg s "$1" --argjson a "$2" \
        '{addPaymentSaleId: $s, addPaymentMethod: "Cash", addPaymentAmount: $a, addPaymentTendered: null, addPaymentReference: null}'
    }

    # Starts a sale and prints its id.
    start_sale() {
      local body code
      body=$(${jq} -nc --arg e "$ADMIN_ID" --arg r "$REGISTER_ID" --arg l "$LOCATION_ID" \
        '{startSaleEmployeeId: $e, startSaleRegisterId: $r, startSaleLocationId: $l}')
      code=$(post /pos/sale "$body")
      if [ "$code" != "200" ]; then
        echo ""
        return 1
      fi
      sql "select id from transaction order by created desc limit 1"
    }

    status_of()    { sql "select status from transaction where id = '$1'"; }
    line_count()   { sql "select count(*) from transaction_item where transaction_id = '$1'"; }
    line_qty()     { sql "select coalesce(sum(quantity), 0) from transaction_item where transaction_id = '$1'"; }
    live_res()     { sql "select count(*) from inventory_reservation where transaction_id = '$1' and status = 'Reserved'"; }
    live_res_qty() { sql "select coalesce(sum(quantity), 0) from inventory_reservation where transaction_id = '$1' and status = 'Reserved'"; }
    totals_agree() { sql "select (select total from transaction where id = '$1') = (select coalesce(sum(total), 0) from transaction_item where transaction_id = '$1')"; }
    stock_of()     { sql "select quantity from menu_items where sku = '$1'"; }

    ${builtins.readFile ./sale-checks/auth.sh}
    ${builtins.readFile ./sale-checks/lines.sh}
    ${builtins.readFile ./sale-checks/void-finalize.sh}
    ${builtins.readFile ./sale-checks/identity.sh}
    ${builtins.readFile ./sale-checks/constraints.sh}
    ${builtins.readFile ./sale-checks/locks.sh}
    ${builtins.readFile ./sale-checks/refund.sh}
    ${builtins.readFile ./sale-checks/restock.sh}
    ${builtins.readFile ./sale-checks/rows.sh}

    echo ""
    echo "════════════════════════════════════════════"
    echo "  Passed: $PASS  Failed: $FAIL"
    if [ $FAIL -eq 0 ]; then
      echo "  ✓ SALE PATH VERIFIED"
    else
      echo "  ✗ SALE PATH HAS FAILURES"
      echo "  Backend log: last 30 lines"
      tail -n 30 "$WORK/backend.log" || true
    fi
    echo "════════════════════════════════════════════"

    [ $FAIL -eq 0 ]
  '';

in {
  inherit test-sale;
}