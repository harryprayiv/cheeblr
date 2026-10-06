#!/usr/bin/env fish
# For each rule that check-consistency.fish reported broken, shows the
# offending sales grouped by creation day and status, and the newest one.
# Read-only. Run through with-db.

function show -a title query
    echo "== $title"
    psql -X -w -c $query
end

set totals "t.subtotal <> coalesce((select sum(i.subtotal) from transaction_item i where i.transaction_id = t.id), 0) or t.tax_total <> coalesce((select sum(x.amount) from transaction_tax x join transaction_item i on i.id = x.transaction_item_id where i.transaction_id = t.id), 0)"

show "stored totals differ from the lines: sales per day" "select t.created::date as day, t.status, count(*) as sales from transaction t where $totals group by 1, 2 order by 1, 2"
show "stored totals differ from the lines: newest" "select max(t.created) as newest from transaction t where $totals"

set dupes "(select transaction_id, menu_item_sku from transaction_item group by transaction_id, menu_item_sku having count(*) > 1)"

show "two lines for one sku: sale and sku pairs per day" "select t.created::date as day, t.status, count(*) as pairs from $dupes d join transaction t on t.id = d.transaction_id group by 1, 2 order by 1, 2"
show "two lines for one sku: newest" "select max(t.created) as newest from $dupes d join transaction t on t.id = d.transaction_id"

set unmatched "t.status in ('CREATED', 'IN_PROGRESS') and (select count(*) from inventory_reservation r where r.transaction_id = t.id and r.item_sku = i.menu_item_sku and r.status = 'Reserved' and r.quantity = i.quantity) <> 1"

show "open-sale lines without exactly one matching reservation: lines per day" "select t.created::date as day, t.status, count(*) as lines from transaction_item i join transaction t on t.id = i.transaction_id where $unmatched group by 1, 2 order by 1, 2"
show "open-sale lines without exactly one matching reservation: newest" "select max(t.created) as newest from transaction_item i join transaction t on t.id = i.transaction_id where $unmatched"

show "all open sales, by day (these still hold stock)" "select t.created::date as day, t.status, count(*) as sales from transaction t where t.status in ('CREATED', 'IN_PROGRESS') group by 1, 2 order by 1, 2"
