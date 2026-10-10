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