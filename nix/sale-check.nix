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

    # ── Auth ────────────────────────────────────────────────────────────────

    echo "── Auth ──"
    check "request with no credentials is refused" 401 \
      "$(${curl} -s -o /dev/null -w "%{http_code}" "$BASE_URL/session")"
    check "a user id in the Authorization header is refused" 401 \
      "$(${curl} -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_ID" "$BASE_URL/session")"

    LOGIN_BODY=$(${jq} -nc --arg p "$ADMIN_PASS" \
      '{loginUsername: "admin", loginPassword: $p, loginRegisterId: null}')
    TOKEN=$(${curl} -s -D - -o /dev/null -X POST "$BASE_URL/auth/login" \
        -H "Content-Type: application/json" -d "$LOGIN_BODY" \
      | grep -i '^set-cookie:' | grep 'cheeblr_session=' \
      | sed 's/.*cheeblr_session=\([^;]*\).*/\1/' | tr -d '\r' | head -1 || true)
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

    # ── H. Consistency of every row ─────────────────────────────────────────

    echo ""
    echo "── H. Every row in the database obeys the rules ──"
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