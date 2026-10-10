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
wait "${BURST_PIDS[@]}" 2>/dev/null || true
check "still one line" 1 "$(line_count "$SALE")"
check "line quantity after the burst" 13 "$(line_qty "$SALE")"
check "still one live reservation" 1 "$(live_res "$SALE")"
check "reserved quantity after the burst" 13 "$(live_res_qty "$SALE")"
check "sale total equals the line total" t "$(totals_agree "$SALE")"