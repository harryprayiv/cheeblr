# ── L. Refund under the sale lock ───────────────────────────────────────

echo ""
echo "── L. A sale can be refunded once ──"

# Starts a sale, adds one unit, pays it in full, completes it and prints
# its id.
completed_sale() {
  local sale total
  sale=$(start_sale) || return 1
  post /pos/sale/item "$(add_body "$sale" "$SKU_MAIN" 1)" > /dev/null
  total=$(sql "select total from transaction where id = '$sale'")
  post /pos/sale/payment "$(pay_body "$sale" "$total")" > /dev/null
  post "/pos/sale/finalize/$sale" "" > /dev/null
  echo "$sale"
}
refunds_of() { sql "select count(*) from transaction where reference_transaction_id = '$1'"; }

RF=$(completed_sale) || { echo "  ✗ could not prepare a completed sale"; exit 1; }
RF_TOTAL=$(sql "select total from transaction where id = '$RF'")
check "the sale to refund is COMPLETED" COMPLETED "$(status_of "$RF")"
check "refund returns 200" 200 "$(post "/sale/refund/$RF" '"first refund"')"
check "one refund transaction references the sale" 1 "$(refunds_of "$RF")"
check "the refund total is the sale total negated" "$((0 - RF_TOTAL))" \
  "$(sql "select total from transaction where reference_transaction_id = '$RF'")"
check "the sale is marked refunded" t "$(sql "select is_refunded from transaction where id = '$RF'")"
check "the refunded sale has status REFUNDED" REFUNDED "$(status_of "$RF")"
check "the refund row has status COMPLETED" COMPLETED \
  "$(sql "select status from transaction where reference_transaction_id = '$RF'")"
check "the refund row has type RETURN" RETURN \
  "$(sql "select transaction_type from transaction where reference_transaction_id = '$RF'")"
check "a second refund returns 409" 409 "$(post "/sale/refund/$RF" '"second refund"')"
check "still one refund transaction" 1 "$(refunds_of "$RF")"
check "the first refund reason is kept" "first refund" "$(sql "select refund_reason from transaction where id = '$RF'")"
check "a refunded sale cannot be voided" 409 "$(post "/sale/void/$RF" '"void after refund"')"
check "the manager's void of a refunded sale returns 409" 409 \
  "$(post "/manager/override/void/$RF" "$OVERRIDE_BODY")"
check "the sale is still REFUNDED" REFUNDED "$(status_of "$RF")"
check "the sale is not marked voided" f "$(sql "select is_voided from transaction where id = '$RF'")"

REFUND_BAD=0
for _r in $(seq 1 8); do
  RR=$(completed_sale) || { echo "  ✗ could not prepare a completed sale"; exit 1; }
  post "/sale/refund/$RR" '"refund one"' > "$WORK/ref1" &
  REF1=$!
  post "/sale/refund/$RR" '"refund two"' > "$WORK/ref2" &
  REF2=$!
  wait "$REF1" "$REF2" 2>/dev/null || true
  RCODES=$(sort "$WORK/ref1" "$WORK/ref2" | tr -d '\n')
  RCOUNT=$(refunds_of "$RR")
  if [ "$RCODES" != "200409" ] || [ "$RCOUNT" != "1" ]; then
    REFUND_BAD=$((REFUND_BAD + 1))
    echo "  round $_r: codes=$RCODES refund transactions=$RCOUNT"
  fi
done
check "two refunds at once always write exactly one refund" 0 "$REFUND_BAD"

# A stored refund has to be readable again. These read the refund back
# through the API and compare the list with the rows in the database.
REFUND_ID=$(sql "select id from transaction where reference_transaction_id = '$RF'")
check "the stored refund can be read back" 200 "$(get_code "/refund/$REFUND_ID")"
REFUND_JSON=$(get_body "/refund/$REFUND_ID")
check "the refund read back names the sale it refunds" "$RF" \
  "$(echo "$REFUND_JSON" | $JQ -r '.refundReferenceTransactionId')"
check "the refund read back carries its reason" "first refund" \
  "$(echo "$REFUND_JSON" | $JQ -r '.refundReason')"
check "the refund list returns 200" 200 "$(get_code /refund)"
check "the refund list holds every refund row in the database" \
  "$(sql "select count(*) from transaction where transaction_type = 'RETURN'")" \
  "$(get_body /refund | $JQ 'length')"
check "the sale list does not include refunds" 0 \
  "$(get_body /sale | $JQ --arg r "$REFUND_ID" '[.[] | select(.saleId == $r)] | length')"

# The day's figures. A sale adds its total to revenue and one to the
# transaction count. Refunding it takes the revenue back out, leaves the
# count alone and adds one to the refund count.
day_stat() { get_body /manager/activity | $JQ -r ".asTodayStats.$1"; }
REV0=$(day_stat ldsRevenue)
CNT0=$(day_stat ldsTxCount)
RFC0=$(day_stat ldsRefundCount)
RS=$(completed_sale) || { echo "  ✗ could not prepare a completed sale"; exit 1; }
RS_TOTAL=$(sql "select total from transaction where id = '$RS'")
check "a completed sale adds its total to the day's revenue" "$((REV0 + RS_TOTAL))" "$(day_stat ldsRevenue)"
check "a completed sale adds one to the day's transaction count" "$((CNT0 + 1))" "$(day_stat ldsTxCount)"
check "refund of that sale returns 200" 200 "$(post "/sale/refund/$RS" '"stats refund"')"
check "after the refund the day's revenue is back where it was" "$REV0" "$(day_stat ldsRevenue)"
check "after the refund the transaction count is unchanged" "$((CNT0 + 1))" "$(day_stat ldsTxCount)"
check "after the refund the refund count is one higher" "$((RFC0 + 1))" "$(day_stat ldsRefundCount)"