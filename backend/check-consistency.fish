#!/usr/bin/env fish
# Counts rows that break the rules tying sales, lines, reservations and
# stock together. Every count should be 0. Read-only. Run through with-db.
#
# Optional: CHEEBLR_SINCE, a timestamp. When set, the rules about sales
# only look at sales created at or after it. The two stock rules always
# look at everything.

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

echo "database: $PGUSER@$PGHOST:$PGPORT/$PGDATABASE"
if not psql -X -w -At -c 'select 1' >/dev/null
    echo "ERROR  cannot connect to the database with the settings above. No rule was checked."
    exit 2
end

if set -q CHEEBLR_SINCE
    set -g since "t.created >= '$CHEEBLR_SINCE'"
    echo "scope:    sales created at or after $CHEEBLR_SINCE"
else
    set -g since true
    echo "scope:    all sales"
end

set -g bad 0
set -g errors 0

function rule -a label query
    set n (psql -X -w -At -c $query 2>/dev/null)
    if test $status -ne 0
        echo "ERROR $label: the query did not run"
        set -g errors (math $errors + 1)
    else if test "$n" = 0
        echo "PASS  $label"
    else
        echo "FAIL  $label: $n"
        set -g bad (math $bad + 1)
    end
end

rule "stored subtotal equals the sum of line subtotals" "select count(*) from transaction t where $since and t.subtotal <> coalesce((select sum(i.subtotal) from transaction_item i where i.transaction_id = t.id), 0)"

rule "stored tax total equals the sum of line taxes" "select count(*) from transaction t where $since and t.tax_total <> coalesce((select sum(x.amount) from transaction_tax x join transaction_item i on i.id = x.transaction_item_id where i.transaction_id = t.id), 0)"

rule "stored total equals subtotal minus discount plus tax" "select count(*) from transaction t where $since and t.total <> t.subtotal - t.discount_total + t.tax_total"

rule "no sale has two lines for one sku" "select count(*) from (select 1 from transaction_item i join transaction t on t.id = i.transaction_id where $since group by i.transaction_id, i.menu_item_sku having count(*) > 1) d"

rule "every line on an open sale has exactly one live reservation of its quantity" "select count(*) from transaction_item i join transaction t on t.id = i.transaction_id where $since and t.status in ('CREATED', 'IN_PROGRESS') and (select count(*) from inventory_reservation r where r.transaction_id = t.id and r.item_sku = i.menu_item_sku and r.status = 'Reserved' and r.quantity = i.quantity) <> 1"

rule "no live reservation without a line on its sale" "select count(*) from inventory_reservation r join transaction t on t.id = r.transaction_id where $since and r.status = 'Reserved' and not exists (select 1 from transaction_item i where i.transaction_id = r.transaction_id and i.menu_item_sku = r.item_sku)"

rule "no live reservation on a closed sale" "select count(*) from inventory_reservation r join transaction t on t.id = r.transaction_id where $since and r.status = 'Reserved' and t.status not in ('CREATED', 'IN_PROGRESS')"

rule "no item has negative stock" "select count(*) from menu_items where quantity < 0"

rule "no item is reserved beyond its stock" "select count(*) from menu_items m where m.quantity < coalesce((select sum(r.quantity) from inventory_reservation r where r.item_sku = m.sku and r.status = 'Reserved'), 0)"

rule "every completed sale has at least one line" "select count(*) from transaction t where $since and t.status = 'COMPLETED' and t.transaction_type = 'SALE' and not exists (select 1 from transaction_item i where i.transaction_id = t.id)"

rule "every completed sale is paid in full" "select count(*) from transaction t where $since and t.status = 'COMPLETED' and t.transaction_type = 'SALE' and t.total > coalesce((select sum(p.amount) from payment_transaction p where p.transaction_id = t.id), 0)"

echo
echo "in-progress sales with no lines (allowed today, listed for information):" (psql -X -w -At -c "select count(*) from transaction t where $since and t.status = 'IN_PROGRESS' and not exists (select 1 from transaction_item i where i.transaction_id = t.id)" 2>/dev/null)
echo
if test $errors -gt 0
    echo "$errors QUERY ERROR(S), $bad RULE(S) BROKEN"
    exit 2
else if test $bad -eq 0
    echo "ALL RULES HOLD"
else
    echo "$bad RULE(S) BROKEN"
end
exit $bad