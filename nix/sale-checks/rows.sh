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
rule "every completed or refunded sale has at least one line" \
  "select count(*) from transaction t where t.status in ('COMPLETED', 'REFUNDED') and t.transaction_type = 'SALE' and not exists (select 1 from transaction_item i where i.transaction_id = t.id)"
rule "every completed or refunded sale is paid in full" \
  "select count(*) from transaction t where t.status in ('COMPLETED', 'REFUNDED') and t.transaction_type = 'SALE' and t.total > coalesce((select sum(p.amount) from payment_transaction p where p.transaction_id = t.id), 0)"
rule "the refunded flag and the REFUNDED status always agree" \
  "select count(*) from transaction t where t.transaction_type <> 'RETURN' and (t.status = 'REFUNDED') <> t.is_refunded"
rule "every refunded sale has exactly one return row" \
  "select count(*) from transaction t where t.status = 'REFUNDED' and (select count(*) from transaction r where r.reference_transaction_id = t.id and r.transaction_type = 'RETURN') <> 1"
rule "every return row refunds a sale with status REFUNDED" \
  "select count(*) from transaction r where r.transaction_type = 'RETURN' and not exists (select 1 from transaction t where t.id = r.reference_transaction_id and t.status = 'REFUNDED')"
rule "every return row is the negation of its sale" \
  "select count(*) from transaction r join transaction t on t.id = r.reference_transaction_id where r.transaction_type = 'RETURN' and r.total <> 0 - t.total"