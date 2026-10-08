{ pkgs, lib ? pkgs.lib, name }:

# test-sale: runs the sale path against a throwaway PostgreSQL cluster and a
# backend started for the test, then checks the rows in the database.
#
# Nothing here touches the development database. The cluster lives in a
# temporary directory, listens on a unix socket only, and is removed on exit.
#
# Set BACKEND_BIN to a pre-built backend binary to skip `cabal run`.

let
  config = import ./config.nix { inherit name; };

  host = config.network.host;
  backendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head config.haskell.codeDirs));

  saleBackendPort = "18081";
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

    echo "Starting backend on port ${saleBackendPort} ..."
    if [ -n "''${BACKEND_BIN:-}" ] && [ -x "''${BACKEND_BIN}" ]; then
      ("''${BACKEND_BIN}" > "$WORK/backend.log" 2>&1) &
    else
      (cd ${backendPath} && cabal run ${name}-backend > "$WORK/backend.log" 2>&1) &
    fi
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

    # POSTs a JSON body as the logged-in user and prints the HTTP status.
    post() {
      ${curl} -s -o /dev/null -w "%{http_code}" --max-time 30 \
        -H "Cookie: cheeblr_session=$TOKEN" \
        -H "Content-Type: application/json" \
        -X POST -d "$2" "$BASE_URL$1"
    }

    # Sends a DELETE as the logged-in user and prints the HTTP status.
    del() {
      ${curl} -s -o /dev/null -w "%{http_code}" --max-time 30 \
        -H "Cookie: cheeblr_session=$TOKEN" \
        -X DELETE "$BASE_URL$1"
    }

    add_body() {
      ${jq} -nc --arg s "$1" --arg k "$2" --argjson q "$3" \
        '{addItemSaleId: $s, addItemSku: $k, addItemQuantity: $q}'
    }

    pay_body() {
      ${jq} -nc --arg s "$1" --argjson a "$2" \
        '{addPaymentSaleId: $s, addPaymentMethod: "Cash", addPaymentAmount: $a, addPaymentTendered: null, addPaymentReference: null}'
    }

    # Starts a sale and prints its id. The body always names the admin as the
    # employee, whoever is logged in.
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

    # ── Auth ────────────────────────────────────────────────────────────────

    echo "── Auth ──"
    check "request with no credentials is refused" 401 \
      "$(${curl} -s -o /dev/null -w "%{http_code}" "$BASE_URL/session")"
    check "a user id in the Authorization header is refused" 401 \
      "$(${curl} -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_ID" "$BASE_URL/session")"

    # Logs in and prints the session token, or nothing when login fails.
    login_token() {
      local body
      body=$(${jq} -nc --arg u "$1" --arg p "$2" \
        '{loginUsername: $u, loginPassword: $p, loginRegisterId: null}')
      ${curl} -s -D - -o /dev/null -X POST "$BASE_URL/auth/login" \
          -H "Content-Type: application/json" -d "$body" \
        | grep -i '^set-cookie:' | grep 'cheeblr_session=' \
        | sed 's/.*cheeblr_session=\([^;]*\).*/\1/' | tr -d '\r' | head -1 || true
    }

    TOKEN=$(login_token admin "$ADMIN_PASS")
    if [ -z "$TOKEN" ]; then
      echo "  ✗ login did not return a session cookie"
      exit 1
    fi
    check "session cookie is accepted" 200 \
      "$(${curl} -s -o /dev/null -w "%{http_code}" -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL/session")"

    # ── A. A refused add changes nothing ────────────────────────────────────

    echo ""
    echo "── A. A refused add changes nothing ──"
    SALE=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
    check "new sale is CREATED" CREATED "$(status_of "$SALE")"
    check "add beyond stock returns 400" 400 "$(post /pos/sale/item "$(add_body "$SALE" "$SKU_MAIN" 101)")"
    check "sale is still CREATED" CREATED "$(status_of "$SALE")"
    check "sale has no lines" 0 "$(line_count "$SALE")"
    check "sale holds no reservation" 0 "$(live_res "$SALE")"

    # ── B. The same sku twice makes one line ────────────────────────────────

    echo ""
    echo "── B. Adding the same sku twice makes one line ──"
    check "add 1 returns 200" 200 "$(post /pos/sale/item "$(add_body "$SALE" "$SKU_MAIN" 1)")"
    check "add 2 returns 200" 200 "$(post /pos/sale/item "$(add_body "$SALE" "$SKU_MAIN" 2)")"
    check "sale is IN_PROGRESS" IN_PROGRESS "$(status_of "$SALE")"
    check "one line" 1 "$(line_count "$SALE")"
    check "line quantity" 3 "$(line_qty "$SALE")"
    check "one live reservation" 1 "$(live_res "$SALE")"
    check "reserved quantity" 3 "$(live_res_qty "$SALE")"
    check "sale total equals the line total" t "$(totals_agree "$SALE")"

    # ── C. Simultaneous adds to one sale ────────────────────────────────────

    echo ""
    echo "── C. Ten simultaneous adds of 1 all count ──"
    ONE=$(add_body "$SALE" "$SKU_MAIN" 1)
    BURST_PIDS=()
    for _i in $(seq 1 10); do
      post /pos/sale/item "$ONE" > /dev/null &
      BURST_PIDS+=($!)
    done
    wait "''${BURST_PIDS[@]}" 2>/dev/null || true
    check "still one line" 1 "$(line_count "$SALE")"
    check "line quantity after the burst" 13 "$(line_qty "$SALE")"
    check "still one live reservation" 1 "$(live_res "$SALE")"
    check "reserved quantity after the burst" 13 "$(live_res_qty "$SALE")"
    check "sale total equals the line total" t "$(totals_agree "$SALE")"

    # ── D. Void releases the stock ──────────────────────────────────────────

    echo ""
    echo "── D. Void releases the stock ──"
    check "void returns 200" 200 "$(post "/sale/void/$SALE" '"test-sale run"')"
    check "sale is VOIDED" VOIDED "$(status_of "$SALE")"
    check "no live reservation left" 0 "$(live_res "$SALE")"
    check "stock is unchanged by a voided open sale" 100 "$(stock_of "$SKU_MAIN")"

    # ── E. Payment and finalize ─────────────────────────────────────────────

    echo ""
    echo "── E. Finalize needs full payment and reduces stock once ──"
    SALE2=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
    check "add 2 returns 200" 200 "$(post /pos/sale/item "$(add_body "$SALE2" "$SKU_MAIN" 2)")"
    TOTAL=$(sql "select total from transaction where id = '$SALE2'")
    echo "  sale total is $TOTAL cents"
    check "finalize with no payment returns 409" 409 "$(post "/pos/sale/finalize/$SALE2" "")"
    check "short payment is accepted" 200 "$(post /pos/sale/payment "$(pay_body "$SALE2" $((TOTAL - 1)))")"
    check "finalize while short returns 409" 409 "$(post "/pos/sale/finalize/$SALE2" "")"
    check "sale is still IN_PROGRESS" IN_PROGRESS "$(status_of "$SALE2")"
    check "stock is not reduced by a refused finalize" 100 "$(stock_of "$SKU_MAIN")"
    check "remaining payment is accepted" 200 "$(post /pos/sale/payment "$(pay_body "$SALE2" 1)")"
    check "finalize when paid returns 200" 200 "$(post "/pos/sale/finalize/$SALE2" "")"
    check "sale is COMPLETED" COMPLETED "$(status_of "$SALE2")"
    check "stock is reduced by the quantity sold" 98 "$(stock_of "$SKU_MAIN")"
    check "no live reservation left" 0 "$(live_res "$SALE2")"
    check "second finalize returns 409" 409 "$(post "/pos/sale/finalize/$SALE2" "")"
    check "stock is not reduced twice" 98 "$(stock_of "$SKU_MAIN")"
    check "add to a completed sale returns 409" 409 "$(post /pos/sale/item "$(add_body "$SALE2" "$SKU_MAIN" 1)")"
    check "completed sale still has one line" 1 "$(line_count "$SALE2")"

    # ── F. Two sales and the last unit ──────────────────────────────────────

    echo ""
    echo "── F. Two sales cannot both take the last unit ──"
    SALE3=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
    SALE4=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
    post /pos/sale/item "$(add_body "$SALE3" "$SKU_LAST" 1)" > "$WORK/race3" &
    RACE3=$!
    post /pos/sale/item "$(add_body "$SALE4" "$SKU_LAST" 1)" > "$WORK/race4" &
    RACE4=$!
    wait "$RACE3" "$RACE4" 2>/dev/null || true
    CODES=$(sort "$WORK/race3" "$WORK/race4" | tr -d '\n')
    check "one add succeeds and one is refused" 200400 "$CODES"
    check "exactly one unit is reserved" 1 \
      "$(sql "select coalesce(sum(quantity), 0) from inventory_reservation where item_sku = '$SKU_LAST' and status = 'Reserved'")"

    # ── G. Payments and finalize under one lock ─────────────────────────────

    echo ""
    echo "── G. A payment cannot change under a finalize ──"
    check "payment on a completed sale returns 409" 409 "$(post /pos/sale/payment "$(pay_body "$SALE2" 1)")"
    PAY2=$(sql "select id from payment_transaction where transaction_id = '$SALE2' order by amount desc limit 1")
    check "removing a payment from a completed sale returns 409" 409 "$(del "/pos/sale/payment/$PAY2")"
    check "completed sale still has both payments" 2 "$(sql "select count(*) from payment_transaction where transaction_id = '$SALE2'")"

    FINALIZED=0
    IMPOSSIBLE=0
    for _r in $(seq 1 8); do
      RS=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
      post /pos/sale/item "$(add_body "$RS" "$SKU_MAIN" 1)" > /dev/null
      RT=$(sql "select total from transaction where id = '$RS'")
      post /pos/sale/payment "$(pay_body "$RS" "$RT")" > /dev/null
      RP=$(sql "select id from payment_transaction where transaction_id = '$RS'")
      post "/pos/sale/finalize/$RS" "" > "$WORK/fin" &
      FIN_PID=$!
      del "/pos/sale/payment/$RP" > "$WORK/del" &
      DEL_PID=$!
      wait "$FIN_PID" "$DEL_PID" 2>/dev/null || true
      FIN_CODE=$(cat "$WORK/fin")
      DEL_CODE=$(cat "$WORK/del")
      RSTATUS=$(status_of "$RS")
      RPAID=$(sql "select coalesce(sum(amount), 0) from payment_transaction where transaction_id = '$RS'")
      if [ "$RSTATUS" = "COMPLETED" ]; then
        FINALIZED=$((FINALIZED + 1))
        if [ "$RPAID" -lt "$RT" ] || [ "$FIN_CODE" != "200" ] || [ "$DEL_CODE" = "200" ]; then
          IMPOSSIBLE=$((IMPOSSIBLE + 1))
          echo "  round $_r: COMPLETED with paid=$RPAID total=$RT finalize=$FIN_CODE remove=$DEL_CODE"
        fi
      else
        if [ "$FIN_CODE" = "200" ] || [ "$DEL_CODE" != "200" ]; then
          IMPOSSIBLE=$((IMPOSSIBLE + 1))
          echo "  round $_r: $RSTATUS with paid=$RPAID total=$RT finalize=$FIN_CODE remove=$DEL_CODE"
        fi
      fi
    done
    echo "  finalize won $FINALIZED of 8 races"
    check "no race ended in a state the rules forbid" 0 "$IMPOSSIBLE"
    check "stock fell by one for each completed sale" "$((98 - FINALIZED))" "$(stock_of "$SKU_MAIN")"

    # ── H. Identity and permissions ─────────────────────────────────────────

    echo ""
    echo "── H. The session decides who is acting and what they may do ──"
    ADMIN_TOKEN="$TOKEN"
    CASHIER_PASS="cashier-test-password-1"
    NEW_USER=$(${jq} -nc --arg p "$CASHIER_PASS" \
      '{newReqUsername: "cashier1", newReqDisplayName: "Cashier One", newReqEmail: null, newReqRole: "Cashier", newReqLocationId: null, newReqPassword: $p}')
    check "admin creates a cashier account" 200 "$(post /auth/users "$NEW_USER")"
    CASHIER_ID=$(sql "select id from users where username = 'cashier1'")
    CASHIER_TOKEN=$(login_token cashier1 "$CASHIER_PASS")

    SALE_A=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
    check "admin adds 1 to the admin's sale" 200 "$(post /pos/sale/item "$(add_body "$SALE_A" "$SKU_MAIN" 1)")"
    LINE_A=$(sql "select id from transaction_item where transaction_id = '$SALE_A'")
    TOTAL_A=$(sql "select total from transaction where id = '$SALE_A'")

    TOKEN="$CASHIER_TOKEN"
    check "cashier session is accepted" 200 \
      "$(${curl} -s -o /dev/null -w "%{http_code}" -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL/session")"
    check "cashier cannot add to another employee's sale" 403 "$(post /pos/sale/item "$(add_body "$SALE_A" "$SKU_MAIN" 1)")"
    check "cashier cannot pay on another employee's sale" 403 "$(post /pos/sale/payment "$(pay_body "$SALE_A" "$TOTAL_A")")"
    check "cashier cannot finalize another employee's sale" 403 "$(post "/pos/sale/finalize/$SALE_A" "")"
    check "cashier cannot clear another employee's sale" 403 "$(post "/pos/sale/clear/$SALE_A" "")"
    check "cashier cannot remove a line from another employee's sale" 403 "$(del "/pos/sale/item/$LINE_A")"
    check "the other employee's sale still has its line" 1 "$(line_qty "$SALE_A")"
    check "the other employee's sale has no payment" 0 "$(sql "select count(*) from payment_transaction where transaction_id = '$SALE_A'")"

    # start_sale sends the admin's id as the employee id. Sent by the cashier,
    # that is a forged id.
    SALE_C=$(start_sale) || { echo "  ✗ cashier could not start a sale"; exit 1; }
    check "a forged employee id is replaced by the caller's id" "$CASHIER_ID" \
      "$(sql "select employee_id from transaction where id = '$SALE_C'")"
    check "cashier adds 1 to the cashier's own sale" 200 "$(post /pos/sale/item "$(add_body "$SALE_C" "$SKU_MAIN" 1)")"
    check "cashier cannot void, even the cashier's own sale" 403 "$(post "/sale/void/$SALE_C" '"cashier void"')"
    check "the cashier's sale is still IN_PROGRESS" IN_PROGRESS "$(status_of "$SALE_C")"
    check "cashier cannot refund a completed sale" 403 "$(post "/sale/refund/$SALE2" '"cashier refund"')"
    check "the completed sale is still COMPLETED" COMPLETED "$(status_of "$SALE2")"

    TOKEN="$ADMIN_TOKEN"
    check "admin can add to the cashier's sale" 200 "$(post /pos/sale/item "$(add_body "$SALE_C" "$SKU_MAIN" 1)")"
    check "the cashier's sale now holds 2" 2 "$(line_qty "$SALE_C")"
    check "admin can void the cashier's sale" 200 "$(post "/sale/void/$SALE_C" '"admin void"')"
    check "the cashier's sale is VOIDED" VOIDED "$(status_of "$SALE_C")"

    # ── I. Registers, reservations and the manager's void ───────────────────

    echo ""
    echo "── I. Registers, reservation routes and the manager's void ──"
    TEST_REG="dddddddd-0000-4000-8000-000000000001"
    REG_BODY=$(${jq} -nc --arg i "$TEST_REG" --arg l "$LOCATION_ID" \
      '{registerId: $i, registerName: "Test register", registerLocationId: $l, registerIsOpen: false, registerCurrentDrawerAmount: 0, registerExpectedDrawerAmount: 0, registerOpenedAt: null, registerOpenedBy: null, registerLastTransactionTime: null}')
    check "admin creates a register" 200 "$(post /register "$REG_BODY")"

    CUSTOMER_PASS="customer-test-password-1"
    NEW_CUSTOMER=$(${jq} -nc --arg p "$CUSTOMER_PASS" \
      '{newReqUsername: "customer1", newReqDisplayName: "Customer One", newReqEmail: null, newReqRole: "Customer", newReqLocationId: null, newReqPassword: $p}')
    check "admin creates a customer account" 200 "$(post /auth/users "$NEW_CUSTOMER")"
    CUSTOMER_TOKEN=$(login_token customer1 "$CUSTOMER_PASS")

    # Both register bodies name the admin as the employee, whoever sends them.
    OPEN_BODY=$(${jq} -nc --arg e "$ADMIN_ID" '{openRegisterEmployeeId: $e, openRegisterStartingCash: 10000}')
    CLOSE_BODY=$(${jq} -nc --arg e "$ADMIN_ID" '{closeRegisterEmployeeId: $e, closeRegisterCountedCash: 10000}')
    START_BODY=$(${jq} -nc --arg e "$ADMIN_ID" --arg r "$REGISTER_ID" --arg l "$LOCATION_ID" \
      '{startSaleEmployeeId: $e, startSaleRegisterId: $r, startSaleLocationId: $l}')
    RESERVE_BODY=$(${jq} -nc --arg s "$SKU_MAIN" --arg t "$SALE_A" \
      '{reserveItemSku: $s, reserveTransactionId: $t, reserveQuantity: 1}')
    RES_A=$(sql "select id from inventory_reservation where transaction_id = '$SALE_A' and status = 'Reserved'")
    RES_BEFORE=$(sql "select count(*) from inventory_reservation")

    TOKEN="$CUSTOMER_TOKEN"
    check "customer session is accepted" 200 \
      "$(${curl} -s -o /dev/null -w "%{http_code}" -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL/session")"
    check "customer cannot start a sale" 403 "$(post /pos/sale "$START_BODY")"
    check "customer cannot open a register" 403 "$(post "/register/open/$TEST_REG" "$OPEN_BODY")"
    check "the register is still closed" f "$(sql "select is_open from register where id = '$TEST_REG'")"

    TOKEN="$CASHIER_TOKEN"
    check "cashier opens the register" 200 "$(post "/register/open/$TEST_REG" "$OPEN_BODY")"
    check "a forged employee id on the open is replaced by the caller's id" "$CASHIER_ID" \
      "$(sql "select opened_by from register where id = '$TEST_REG'")"
    check "the reserve route refuses" 410 "$(post /inventory/reserve "$RESERVE_BODY")"
    check "the release route refuses" 410 "$(del "/inventory/release/$RES_A")"
    check "no reservation was added" "$RES_BEFORE" "$(sql "select count(*) from inventory_reservation")"
    check "the admin's sale still holds its reservation" 1 "$(live_res "$SALE_A")"

    TOKEN="$CUSTOMER_TOKEN"
    check "customer cannot close a register" 403 "$(post "/register/close/$TEST_REG" "$CLOSE_BODY")"
    check "the register is still open" t "$(sql "select is_open from register where id = '$TEST_REG'")"
    TOKEN="$CASHIER_TOKEN"
    check "cashier closes the register" 200 "$(post "/register/close/$TEST_REG" "$CLOSE_BODY")"

    OVERRIDE_BODY=$(${jq} -nc --arg a "$ADMIN_ID" '{orActorId: $a, orReason: "manager override"}')
    open_pulls() { sql "select count(*) from stock_pull_requests where transaction_id = '$1' and status not in ('PullFulfilled', 'PullCancelled')"; }
    check "cashier cannot use the manager's void" 403 "$(post "/manager/override/void/$SALE_A" "$OVERRIDE_BODY")"
    TOKEN="$ADMIN_TOKEN"
    check "the admin's sale has one open stock pull" 1 "$(open_pulls "$SALE_A")"
    check "the manager's void returns 200" 200 "$(post "/manager/override/void/$SALE_A" "$OVERRIDE_BODY")"
    check "the sale is VOIDED" VOIDED "$(status_of "$SALE_A")"
    check "the void released the reservation" 0 "$(live_res "$SALE_A")"
    check "the void cancelled the stock pull" 0 "$(open_pulls "$SALE_A")"
    check "a second manager's void returns 409" 409 "$(post "/manager/override/void/$SALE_A" "$OVERRIDE_BODY")"

    # ── J. Constraints in the database ──────────────────────────────────────

    echo ""
    echo "── J. The database itself refuses rows the rules forbid ──"

    # Runs one statement straight against the database and prints whether the
    # database refused it.
    refused() {
      if ${pg}/bin/psql -X -w -q -h "$PGHOST" -p "$PGPORT" "$PGDATABASE" -c "$1" > /dev/null 2>&1; then
        echo accepted
      else
        echo refused
      fi
    }

    SALE_K=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
    check "add 1 returns 200" 200 "$(post /pos/sale/item "$(add_body "$SALE_K" "$SKU_MAIN" 1)")"
    check "a second line for the same sku" refused \
      "$(refused "insert into transaction_item (id, transaction_id, menu_item_sku, quantity, price_per_unit, subtotal, total) values (gen_random_uuid(), '$SALE_K', '$SKU_MAIN', 1, 1, 1, 1)")"
    check "a second live reservation for the same sku" refused \
      "$(refused "insert into inventory_reservation (id, item_sku, transaction_id, quantity, status) values (gen_random_uuid(), '$SKU_MAIN', '$SALE_K', 1, 'Reserved')")"
    check "a reservation for a sale that does not exist" refused \
      "$(refused "insert into inventory_reservation (id, item_sku, transaction_id, quantity, status) values (gen_random_uuid(), '$SKU_MAIN', gen_random_uuid(), 1, 'Released')")"
    check "a reservation with quantity zero" refused \
      "$(refused "update inventory_reservation set quantity = 0 where transaction_id = '$SALE_K'")"
    check "a reservation with an unknown status" refused \
      "$(refused "update inventory_reservation set status = 'Bogus' where transaction_id = '$SALE_K'")"
    check "a line with quantity zero" refused \
      "$(refused "update transaction_item set quantity = 0 where transaction_id = '$SALE_K'")"
    check "a sale with an unknown status" refused \
      "$(refused "update transaction set status = 'BOGUS' where id = '$SALE_K'")"
    check "negative stock" refused \
      "$(refused "update menu_items set quantity = -1 where sku = '$SKU_LAST'")"

    check "adding the same sku again still returns 200" 200 "$(post /pos/sale/item "$(add_body "$SALE_K" "$SKU_MAIN" 1)")"
    check "the line holds 2" 2 "$(line_qty "$SALE_K")"
    check "still one line" 1 "$(line_count "$SALE_K")"
    LINE_K=$(sql "select id from transaction_item where transaction_id = '$SALE_K'")
    check "removing the line returns 200" 200 "$(del "/pos/sale/item/$LINE_K")"
    check "no live reservation left" 0 "$(live_res "$SALE_K")"

    # ── K. Clear and void under the sale lock ───────────────────────────────

    echo ""
    echo "── K. Clear and void decide under the sale lock ──"
    check "clearing a completed sale returns 409" 409 "$(post "/pos/sale/clear/$SALE2" "")"
    check "the completed sale is still COMPLETED" COMPLETED "$(status_of "$SALE2")"
    check "the completed sale still has its line" 1 "$(line_count "$SALE2")"
    check "the completed sale still has both payments" 2 "$(sql "select count(*) from payment_transaction where transaction_id = '$SALE2'")"

    STOCK_BEFORE_K=$(stock_of "$SKU_MAIN")
    CLEAR_FINALIZED=0
    CLEAR_IMPOSSIBLE=0
    for _r in $(seq 1 8); do
      CS=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
      post /pos/sale/item "$(add_body "$CS" "$SKU_MAIN" 1)" > /dev/null
      CT=$(sql "select total from transaction where id = '$CS'")
      post /pos/sale/payment "$(pay_body "$CS" "$CT")" > /dev/null
      post "/pos/sale/finalize/$CS" "" > "$WORK/fin" &
      FIN_PID=$!
      post "/pos/sale/clear/$CS" "" > "$WORK/clr" &
      CLR_PID=$!
      wait "$FIN_PID" "$CLR_PID" 2>/dev/null || true
      FIN_CODE=$(cat "$WORK/fin")
      CLR_CODE=$(cat "$WORK/clr")
      CSTATUS=$(status_of "$CS")
      CLINES=$(line_count "$CS")
      CPAID=$(sql "select coalesce(sum(amount), 0) from payment_transaction where transaction_id = '$CS'")
      CRES=$(live_res "$CS")
      if [ "$CSTATUS" = "COMPLETED" ]; then
        CLEAR_FINALIZED=$((CLEAR_FINALIZED + 1))
        if [ "$FIN_CODE" != "200" ] || [ "$CLR_CODE" != "409" ] || [ "$CLINES" != "1" ] || [ "$CPAID" -lt "$CT" ]; then
          CLEAR_IMPOSSIBLE=$((CLEAR_IMPOSSIBLE + 1))
          echo "  round $_r: COMPLETED with lines=$CLINES paid=$CPAID total=$CT finalize=$FIN_CODE clear=$CLR_CODE"
        fi
      else
        if [ "$CSTATUS" != "CREATED" ] || [ "$FIN_CODE" = "200" ] || [ "$CLR_CODE" != "200" ] || [ "$CLINES" != "0" ] || [ "$CPAID" != "0" ] || [ "$CRES" != "0" ]; then
          CLEAR_IMPOSSIBLE=$((CLEAR_IMPOSSIBLE + 1))
          echo "  round $_r: $CSTATUS with lines=$CLINES paid=$CPAID reservations=$CRES finalize=$FIN_CODE clear=$CLR_CODE"
        fi
      fi
    done
    echo "  finalize won $CLEAR_FINALIZED of 8 races against clear"
    check "no clear race ended in a state the rules forbid" 0 "$CLEAR_IMPOSSIBLE"
    check "stock fell by one for each sale that completed" "$((STOCK_BEFORE_K - CLEAR_FINALIZED))" "$(stock_of "$SKU_MAIN")"

    VOID_BAD=0
    for _r in $(seq 1 8); do
      VS=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
      post /pos/sale/item "$(add_body "$VS" "$SKU_MAIN" 1)" > /dev/null
      post "/sale/void/$VS" '"first void"' > "$WORK/void1" &
      VOID1=$!
      post "/sale/void/$VS" '"second void"' > "$WORK/void2" &
      VOID2=$!
      wait "$VOID1" "$VOID2" 2>/dev/null || true
      VCODES=$(sort "$WORK/void1" "$WORK/void2" | tr -d '\n')
      if [ "$VCODES" != "200409" ] || [ "$(status_of "$VS")" != "VOIDED" ] || [ "$(live_res "$VS")" != "0" ]; then
        VOID_BAD=$((VOID_BAD + 1))
        echo "  round $_r: codes=$VCODES status=$(status_of "$VS") reservations=$(live_res "$VS")"
      fi
    done
    check "two voids at once always give one 200 and one 409" 0 "$VOID_BAD"

    # ── L. Refund under the sale lock ───────────────────────────────────────

    echo ""
    echo "── L. A sale can be refunded once ──"

    # Starts a sale, adds one unit, pays it in full, completes it and prints
    # its id.
    completed_sale() {
      local sale total
      sale=$(start_sale) || return 1
      post /pos/sale/item "$(add_body "$sale" "$SKU_MAIN" 1)" > /dev/null
      total=$(sql "select total from transaction where id = '$sale'")
      post /pos/sale/payment "$(pay_body "$sale" "$total")" > /dev/null
      post "/pos/sale/finalize/$sale" "" > /dev/null
      echo "$sale"
    }
    refunds_of() { sql "select count(*) from transaction where reference_transaction_id = '$1'"; }

    RF=$(completed_sale) || { echo "  ✗ could not prepare a completed sale"; exit 1; }
    RF_TOTAL=$(sql "select total from transaction where id = '$RF'")
    check "the sale to refund is COMPLETED" COMPLETED "$(status_of "$RF")"
    check "refund returns 200" 200 "$(post "/sale/refund/$RF" '"first refund"')"
    check "one refund transaction references the sale" 1 "$(refunds_of "$RF")"
    check "the refund total is the sale total negated" "$((0 - RF_TOTAL))" \
      "$(sql "select total from transaction where reference_transaction_id = '$RF'")"
    check "the sale is marked refunded" t "$(sql "select is_refunded from transaction where id = '$RF'")"
    check "a second refund returns 409" 409 "$(post "/sale/refund/$RF" '"second refund"')"
    check "still one refund transaction" 1 "$(refunds_of "$RF")"
    check "the first refund reason is kept" "first refund" "$(sql "select refund_reason from transaction where id = '$RF'")"

    REFUND_BAD=0
    for _r in $(seq 1 8); do
      RR=$(completed_sale) || { echo "  ✗ could not prepare a completed sale"; exit 1; }
      post "/sale/refund/$RR" '"refund one"' > "$WORK/ref1" &
      REF1=$!
      post "/sale/refund/$RR" '"refund two"' > "$WORK/ref2" &
      REF2=$!
      wait "$REF1" "$REF2" 2>/dev/null || true
      RCODES=$(sort "$WORK/ref1" "$WORK/ref2" | tr -d '\n')
      RCOUNT=$(refunds_of "$RR")
      if [ "$RCODES" != "200409" ] || [ "$RCOUNT" != "1" ]; then
        REFUND_BAD=$((REFUND_BAD + 1))
        echo "  round $_r: codes=$RCODES refund transactions=$RCOUNT"
      fi
    done
    check "two refunds at once always write exactly one refund" 0 "$REFUND_BAD"

    # ── M. Consistency of every row ─────────────────────────────────────────

    echo ""
    echo "── M. Every row in the database obeys the rules ──"
    rule() { check "$1" 0 "$(sql "$2")"; }

    rule "stored subtotal equals the sum of line subtotals" \
      "select count(*) from transaction t where t.subtotal <> coalesce((select sum(i.subtotal) from transaction_item i where i.transaction_id = t.id), 0)"
    rule "stored tax total equals the sum of line taxes" \
      "select count(*) from transaction t where t.tax_total <> coalesce((select sum(x.amount) from transaction_tax x join transaction_item i on i.id = x.transaction_item_id where i.transaction_id = t.id), 0)"
    rule "stored total equals subtotal minus discount plus tax" \
      "select count(*) from transaction t where t.total <> t.subtotal - t.discount_total + t.tax_total"
    rule "no sale has two lines for one sku" \
      "select count(*) from (select 1 from transaction_item group by transaction_id, menu_item_sku having count(*) > 1) d"
    rule "every line on an open sale has exactly one live reservation of its quantity" \
      "select count(*) from transaction_item i join transaction t on t.id = i.transaction_id where t.status in ('CREATED', 'IN_PROGRESS') and (select count(*) from inventory_reservation r where r.transaction_id = t.id and r.item_sku = i.menu_item_sku and r.status = 'Reserved' and r.quantity = i.quantity) <> 1"
    rule "no live reservation without a line on its sale" \
      "select count(*) from inventory_reservation r where r.status = 'Reserved' and not exists (select 1 from transaction_item i where i.transaction_id = r.transaction_id and i.menu_item_sku = r.item_sku)"
    rule "no live reservation on a closed sale" \
      "select count(*) from inventory_reservation r join transaction t on t.id = r.transaction_id where r.status = 'Reserved' and t.status not in ('CREATED', 'IN_PROGRESS')"
    rule "no item has negative stock" \
      "select count(*) from menu_items where quantity < 0"
    rule "no item is reserved beyond its stock" \
      "select count(*) from menu_items m where m.quantity < coalesce((select sum(r.quantity) from inventory_reservation r where r.item_sku = m.sku and r.status = 'Reserved'), 0)"
    rule "every completed sale has at least one line" \
      "select count(*) from transaction t where t.status = 'COMPLETED' and t.transaction_type = 'SALE' and not exists (select 1 from transaction_item i where i.transaction_id = t.id)"
    rule "every completed sale is paid in full" \
      "select count(*) from transaction t where t.status = 'COMPLETED' and t.transaction_type = 'SALE' and t.total > coalesce((select sum(p.amount) from payment_transaction p where p.transaction_id = t.id), 0)"

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