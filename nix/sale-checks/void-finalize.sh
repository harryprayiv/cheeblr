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