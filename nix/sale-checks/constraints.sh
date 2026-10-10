# ── J. Constraints in the database ──────────────────────────────────────

echo ""
echo "── J. The database itself refuses rows the rules forbid ──"

# Runs one statement straight against the database and prints whether the
# database refused it.
refused() {
  if $PSQL -X -w -q -h "$PGHOST" -p "$PGPORT" "$PGDATABASE" -c "$1" > /dev/null 2>&1; then
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