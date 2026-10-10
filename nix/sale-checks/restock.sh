# ── M. Stock on void and refund follows the configuration ───────────────

echo ""
echo "── M. Stock on void and refund follows the configuration ──"

# Starts a sale of the given quantity of the main item, pays it in full,
# completes it and prints its id.
completed_sale_of() {
  local sale total
  sale=$(start_sale) || return 1
  post /pos/sale/item "$(add_body "$sale" "$SKU_MAIN" "$1")" > /dev/null
  total=$(sql "select total from transaction where id = '$sale'")
  post /pos/sale/payment "$(pay_body "$sale" "$total")" > /dev/null
  post "/pos/sale/finalize/$sale" "" > /dev/null
  echo "$sale"
}
need_sale() { echo "  ✗ could not prepare a completed sale"; exit 1; }

# The backend refuses to start without both settings.
check "the backend does not start without RESTOCK_ON_VOID" refused "$(config_outcome RESTOCK_ON_VOID "")"
check "the backend does not start without RESTOCK_ON_REFUND" refused "$(config_outcome RESTOCK_ON_REFUND "")"
check "the backend does not start with an unknown RESTOCK_ON_VOID value" refused "$(config_outcome RESTOCK_ON_VOID "sometimes")"

# The backend has been running with both settings on no-restock.
NS0=$(stock_of "$SKU_MAIN")
NV=$(completed_sale_of 2) || need_sale
check "a completed sale of two takes two out of stock" "$((NS0 - 2))" "$(stock_of "$SKU_MAIN")"
check "no-restock: void of the completed sale returns 200" 200 "$(post "/sale/void/$NV" '"void without restock"')"
check "no-restock: the void leaves stock as it is" "$((NS0 - 2))" "$(stock_of "$SKU_MAIN")"
NR=$(completed_sale_of 3) || need_sale
check "no-restock: refund of a completed sale returns 200" 200 "$(post "/sale/refund/$NR" '"refund without restock"')"
check "no-restock: the refund leaves stock as it is" "$((NS0 - 5))" "$(stock_of "$SKU_MAIN")"

# The same backend, restarted with both settings on restock.
stop_backend || { echo "  ✗ the backend did not stop"; exit 1; }
export RESTOCK_ON_VOID="restock"
export RESTOCK_ON_REFUND="restock"
start_backend || { echo "  ✗ the backend did not restart"; exit 1; }
TOKEN=$(login_token admin "$ADMIN_PASS")
check "the backend restarted with both settings on restock" 200 "$(get_code /sale)"

RS0=$(stock_of "$SKU_MAIN")
RV=$(completed_sale_of 2) || need_sale
check "a completed sale of two takes two out of stock" "$((RS0 - 2))" "$(stock_of "$SKU_MAIN")"
check "restock: void of the completed sale returns 200" 200 "$(post "/sale/void/$RV" '"void with restock"')"
check "restock: the void puts both units back" "$RS0" "$(stock_of "$SKU_MAIN")"
check "restock: a second void returns 409" 409 "$(post "/sale/void/$RV" '"void again"')"
check "restock: the second void adds nothing" "$RS0" "$(stock_of "$SKU_MAIN")"
check "restock: a refund of the voided sale returns 409" 409 "$(post "/sale/refund/$RV" '"refund after void"')"
check "restock: the refused refund adds nothing" "$RS0" "$(stock_of "$SKU_MAIN")"

RR=$(completed_sale_of 3) || need_sale
check "a completed sale of three takes three out of stock" "$((RS0 - 3))" "$(stock_of "$SKU_MAIN")"
check "restock: refund of the completed sale returns 200" 200 "$(post "/sale/refund/$RR" '"refund with restock"')"
check "restock: the refund puts all three units back" "$RS0" "$(stock_of "$SKU_MAIN")"
check "restock: a second refund returns 409" 409 "$(post "/sale/refund/$RR" '"refund again"')"
check "restock: the second refund adds nothing" "$RS0" "$(stock_of "$SKU_MAIN")"
check "restock: a void of the refunded sale returns 409" 409 "$(post "/sale/void/$RR" '"void after refund"')"
check "restock: the refused void adds nothing" "$RS0" "$(stock_of "$SKU_MAIN")"

# A sale that was never completed has taken nothing out of stock, so its
# void must not add anything.
RO=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
post /pos/sale/item "$(add_body "$RO" "$SKU_MAIN" 4)" > /dev/null
check "restock: void of an open sale returns 200" 200 "$(post "/sale/void/$RO" '"void of an open sale"')"
check "restock: the void of an open sale adds nothing" "$RS0" "$(stock_of "$SKU_MAIN")"
check "restock: the void of an open sale released its reservation" 0 "$(live_res "$RO")"

# Two voids at once, and a void and a refund at once, put the stock back
# exactly once.
VOID_PAIR_BAD=0
for _r in $(seq 1 8); do
  PV=$(completed_sale_of 1) || need_sale
  post "/sale/void/$PV" '"void one"' > "$WORK/pv1" &
  PV1=$!
  post "/sale/void/$PV" '"void two"' > "$WORK/pv2" &
  PV2=$!
  wait "$PV1" "$PV2" 2>/dev/null || true
  PCODES=$(sort "$WORK/pv1" "$WORK/pv2" | tr -d '\n')
  PSTOCK=$(stock_of "$SKU_MAIN")
  if [ "$PCODES" != "200409" ] || [ "$PSTOCK" != "$RS0" ]; then
    VOID_PAIR_BAD=$((VOID_PAIR_BAD + 1))
    echo "  round $_r: codes=$PCODES stock=$PSTOCK expected=$RS0"
  fi
done
check "restock: two voids at once always put the stock back once" 0 "$VOID_PAIR_BAD"

MIXED_BAD=0
for _r in $(seq 1 8); do
  PM=$(completed_sale_of 1) || need_sale
  post "/sale/void/$PM" '"void in a race"' > "$WORK/pm1" &
  PM1=$!
  post "/sale/refund/$PM" '"refund in a race"' > "$WORK/pm2" &
  PM2=$!
  wait "$PM1" "$PM2" 2>/dev/null || true
  MCODES=$(sort "$WORK/pm1" "$WORK/pm2" | tr -d '\n')
  MSTOCK=$(stock_of "$SKU_MAIN")
  MSTATUS=$(status_of "$PM")
  if [ "$MCODES" != "200409" ] || [ "$MSTOCK" != "$RS0" ] \
     || { [ "$MSTATUS" != "VOIDED" ] && [ "$MSTATUS" != "REFUNDED" ]; }; then
    MIXED_BAD=$((MIXED_BAD + 1))
    echo "  round $_r: codes=$MCODES stock=$MSTOCK expected=$RS0 status=$MSTATUS"
  fi
done
check "restock: a void and a refund at once put the stock back once" 0 "$MIXED_BAD"