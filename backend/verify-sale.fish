#!/usr/bin/env fish
# Drives one sale through the API and checks the rows in Postgres.
# Needs curl, jq and psql.
#
# Required: CHEEBLR_USER and CHEEBLR_PASS (a login that may sell and void).
# Optional: CHEEBLR_URL, CHEEBLR_EMPLOYEE, CHEEBLR_REGISTER, CHEEBLR_LOCATION.
#
# Database settings and the server port come from, in order: variables
# already set in this shell, the environment of the running cheeblr-backend
# process, then the backend's own defaults.

function backend_env -a name
    set pid (pgrep -x cheeblr-backend | head -n 1)
    test -n "$pid"; or return 1
    for kv in (string split0 < /proc/$pid/environ)
        set parts (string split -m 1 = -- $kv)
        if test "$parts[1]" = $name
            echo $parts[2]
            return 0
        end
    end
    return 1
end

for v in PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD
    if not set -q $v
        set val (backend_env $v); and set -gx $v $val
    end
end
set -q PGHOST; or set -gx PGHOST localhost
set -q PGPORT; or set -gx PGPORT 5432
set -q PGDATABASE; or set -gx PGDATABASE cheeblr
set -q PGUSER; or set -gx PGUSER cheeblr

set -q CHEEBLR_EMPLOYEE; or set CHEEBLR_EMPLOYEE 8b3ae5bf-9c21-41c0-8554-1292f0827455
set -q CHEEBLR_REGISTER; or set CHEEBLR_REGISTER f046b434-c7f1-44cd-9946-fe047fd20ac6
set -q CHEEBLR_LOCATION; or set CHEEBLR_LOCATION b2bd4b3a-d50f-4c04-90b1-01266735876b

if not set -q CHEEBLR_USER; or not set -q CHEEBLR_PASS
    echo "Set CHEEBLR_USER and CHEEBLR_PASS first."
    exit 2
end

echo "database: $PGUSER@$PGHOST:$PGPORT/$PGDATABASE"
if not psql -X -w -At -c 'select 1' >/dev/null
    echo "ERROR  cannot connect to the database with the settings above. Nothing was checked."
    exit 2
end

# Find the server: https first, then http, on the backend's port.
if not set -q CHEEBLR_URL
    set port (backend_env PORT); or set port 8080
    for scheme in https http
        set probe (curl -sk -o /dev/null -w '%{http_code}' $scheme://localhost:$port/openapi.json)
        if test "$probe" = 200
            set CHEEBLR_URL $scheme://localhost:$port
            break
        end
    end
end
if not set -q CHEEBLR_URL
    echo "ERROR  no cheeblr server answered on https or http at localhost:$port. Nothing was checked."
    exit 2
end
echo "server:   $CHEEBLR_URL"

set -g jar (mktemp)
set -g fails 0

function sql
    psql -X -w -At -c $argv[1]
end

function check -a label expected actual
    if test "$expected" = "$actual"
        echo "PASS  $label ($actual)"
    else
        echo "FAIL  $label: expected $expected, got $actual"
        set -g fails (math $fails + 1)
    end
end

# POSTs a JSON body and prints only the HTTP status code.
function post -a path body
    curl -sk -o /dev/null -w '%{http_code}' -b $jar \
        -H 'Content-Type: application/json' -X POST -d $body $CHEEBLR_URL$path
end

echo "== auth"
check "request with no credentials is refused" 401 (curl -sk -o /dev/null -w '%{http_code}' $CHEEBLR_URL/session)
set someUser (sql "select id from users limit 1")
check "a user id in the Authorization header is refused" 401 (curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $someUser" $CHEEBLR_URL/session)

echo "== login"
set loginBody (jq -nc --arg u $CHEEBLR_USER --arg p $CHEEBLR_PASS \
    '{loginUsername: $u, loginPassword: $p, loginRegisterId: null}')
set code (curl -sk -o /dev/null -w '%{http_code}' -c $jar \
    -H 'Content-Type: application/json' -X POST -d $loginBody $CHEEBLR_URL/auth/login)
check "login returns 200" 200 $code
if test $code != 200
    exit 1
end
check "session cookie is accepted" 200 (curl -sk -o /dev/null -w '%{http_code}' -b $jar $CHEEBLR_URL/session)

echo "== pick the sku with the most free stock"
set row (sql "select m.sku, m.quantity - coalesce((select sum(r.quantity) from inventory_reservation r where r.item_sku = m.sku and r.status = 'Reserved'), 0) as free from menu_items m order by free desc limit 1")
set parts (string split '|' $row)
set sku $parts[1]
set free $parts[2]
echo "sku $sku, free stock $free"
if test -z "$sku"; or test $free -lt 13
    echo "Need a menu item with at least 13 free units."
    exit 2
end

echo "== start a sale"
set startBody (jq -nc --arg e $CHEEBLR_EMPLOYEE --arg r $CHEEBLR_REGISTER --arg l $CHEEBLR_LOCATION \
    '{startSaleEmployeeId: $e, startSaleRegisterId: $r, startSaleLocationId: $l}')
check "start sale returns 200" 200 (post /pos/sale $startBody)
set sale (sql "select id from transaction where employee_id = '$CHEEBLR_EMPLOYEE' order by created desc limit 1")
echo "sale $sale"
check "new sale is CREATED" CREATED (sql "select status from transaction where id = '$sale'")

function addBody -a qty
    jq -nc --arg s $sale --arg k $sku --argjson q $qty \
        '{addItemSaleId: $s, addItemSku: $k, addItemQuantity: $q}'
end

echo "== A. a refused add changes nothing"
check "add beyond stock returns 400" 400 (post /pos/sale/item (addBody (math $free + 1)))
check "sale is still CREATED" CREATED (sql "select status from transaction where id = '$sale'")
check "sale has no lines" 0 (sql "select count(*) from transaction_item where transaction_id = '$sale'")
check "sale holds no reservation" 0 (sql "select count(*) from inventory_reservation where transaction_id = '$sale' and status = 'Reserved'")

echo "== B. adding the same sku twice makes one line"
check "add 1 returns 200" 200 (post /pos/sale/item (addBody 1))
check "add 2 returns 200" 200 (post /pos/sale/item (addBody 2))
check "sale is IN_PROGRESS" IN_PROGRESS (sql "select status from transaction where id = '$sale'")
check "one line" 1 (sql "select count(*) from transaction_item where transaction_id = '$sale'")
check "line quantity" 3 (sql "select coalesce(sum(quantity), 0) from transaction_item where transaction_id = '$sale'")
check "one live reservation" 1 (sql "select count(*) from inventory_reservation where transaction_id = '$sale' and status = 'Reserved'")
check "reserved quantity" 3 (sql "select coalesce(sum(quantity), 0) from inventory_reservation where transaction_id = '$sale' and status = 'Reserved'")
check "sale total equals the line total" t (sql "select (select total from transaction where id = '$sale') = (select coalesce(sum(total), 0) from transaction_item where transaction_id = '$sale')")

echo "== C. ten simultaneous adds of 1 all count"
set one (addBody 1)
for i in (seq 10)
    curl -sk -o /dev/null -b $jar -H 'Content-Type: application/json' \
        -X POST -d $one $CHEEBLR_URL/pos/sale/item &
end
wait
check "still one line" 1 (sql "select count(*) from transaction_item where transaction_id = '$sale'")
check "line quantity after the burst" 13 (sql "select coalesce(sum(quantity), 0) from transaction_item where transaction_id = '$sale'")
check "still one live reservation" 1 (sql "select count(*) from inventory_reservation where transaction_id = '$sale' and status = 'Reserved'")
check "reserved quantity after the burst" 13 (sql "select coalesce(sum(quantity), 0) from inventory_reservation where transaction_id = '$sale' and status = 'Reserved'")
check "sale total equals the line total" t (sql "select (select total from transaction where id = '$sale') = (select coalesce(sum(total), 0) from transaction_item where transaction_id = '$sale')")

echo "== D. void releases the stock"
check "void returns 200" 200 (post /sale/void/$sale '"verify-sale.fish run"')
check "sale is VOIDED" VOIDED (sql "select status from transaction where id = '$sale'")
check "no live reservation left" 0 (sql "select count(*) from inventory_reservation where transaction_id = '$sale' and status = 'Reserved'")

rm -f $jar
echo
if test $fails -eq 0
    echo "ALL CHECKS PASSED"
else
    echo "$fails CHECK(S) FAILED"
end
exit $fails
