# ── Lock waits: every sale write decides after it has the lock ──────────
#
# The race checks in the other groups depend on timing. These do not. For
# each write, a second database connection takes the sale's row lock, holds
# it for two seconds, changes the sale's status by hand and commits. The
# write is sent while the lock is held. At that moment the sale still reads
# as open, so the write passes the service's early check and has to wait at
# the lock. When the lock is released it must read the new status and
# refuse. A write that decided before taking the lock would go through.

echo ""
echo "── Lock waits: every sale write decides after it has the lock ──"

# Takes the row lock of sale $1 on a second connection, holds it for two
# seconds, sets the status to $2 and commits. Returns once the lock is held.
hold_sale() {
  sql "begin; select id from transaction where id = '$1' for update; select pg_sleep(2); update transaction set status = '$2' where id = '$1'; commit;" > /dev/null 2>&1 &
  LW_HOLDER=$!
  sleep 0.5
}

# Runs the request given as arguments, which prints a status code. Records
# the code and whether the request took at least a second, which it can
# only do by waiting for the lock.
timed_request() {
  local start ms
  start=$(date +%s%N)
  LW_CODE=$("$@")
  ms=$(( ($(date +%s%N) - start) / 1000000 ))
  wait "$LW_HOLDER" 2>/dev/null || true
  if [ "$ms" -ge 1000 ]; then LW_WAITED=yes; else LW_WAITED="no, answered in $ms ms"; fi
}

# The two checks every case shares. $1 names the write.
waited_and_refused() {
  check "$1 sent while the sale row is locked waits for the lock" yes "$LW_WAITED"
  check "$1 that waited reads the new status and returns 409" 409 "$LW_CODE"
}

# A sale whose status was changed by hand is put back to IN_PROGRESS and
# voided, which releases its reservation. A failure here is counted.
put_back_and_void() {
  local code
  sql "update transaction set status = 'IN_PROGRESS' where id = '$1'" > /dev/null
  code=$(post "/sale/void/$1" '"lock wait cleanup"')
  if [ "$code" != "200" ]; then
    echo "  ✗ cleanup void of $1: expected 200, got $code"
    FAIL=$((FAIL + 1))
  fi
}

# Starts a sale with one unit of the main item and prints its id.
open_sale_with_line() {
  local sale
  sale=$(start_sale) || return 1
  post /pos/sale/item "$(add_body "$sale" "$SKU_MAIN" 1)" > /dev/null
  echo "$sale"
}
no_open_sale() { echo "  ✗ could not prepare an open sale"; exit 1; }
payment_count() { sql "select count(*) from payment_transaction where transaction_id = '$1'"; }

# Add item.
LS=$(open_sale_with_line) || no_open_sale
hold_sale "$LS" COMPLETED
timed_request post /pos/sale/item "$(add_body "$LS" "$SKU_MAIN" 1)"
waited_and_refused "an add item"
check "the refused add left the quantity at one" 1 "$(line_qty "$LS")"
put_back_and_void "$LS"

# Add payment.
LS=$(open_sale_with_line) || no_open_sale
LS_TOTAL=$(sql "select total from transaction where id = '$LS'")
hold_sale "$LS" COMPLETED
timed_request post /pos/sale/payment "$(pay_body "$LS" "$LS_TOTAL")"
waited_and_refused "an add payment"
check "the refused payment was not stored" 0 "$(payment_count "$LS")"
put_back_and_void "$LS"

# Remove payment.
LS=$(open_sale_with_line) || no_open_sale
LS_TOTAL=$(sql "select total from transaction where id = '$LS'")
post /pos/sale/payment "$(pay_body "$LS" "$LS_TOTAL")" > /dev/null
LS_PAYMENT=$(sql "select id from payment_transaction where transaction_id = '$LS' limit 1")
hold_sale "$LS" COMPLETED
timed_request del "/pos/sale/payment/$LS_PAYMENT"
waited_and_refused "a remove payment"
check "the payment is still on the sale" 1 "$(payment_count "$LS")"
put_back_and_void "$LS"

# Clear.
LS=$(open_sale_with_line) || no_open_sale
hold_sale "$LS" COMPLETED
timed_request post "/pos/sale/clear/$LS" ""
waited_and_refused "a clear"
check "the refused clear left the line on the sale" 1 "$(line_count "$LS")"
put_back_and_void "$LS"

# Finalize. The sale is paid in full, so only its status can stop it.
LS=$(open_sale_with_line) || no_open_sale
LS_TOTAL=$(sql "select total from transaction where id = '$LS'")
post /pos/sale/payment "$(pay_body "$LS" "$LS_TOTAL")" > /dev/null
LS_STOCK=$(stock_of "$SKU_MAIN")
hold_sale "$LS" COMPLETED
timed_request post "/pos/sale/finalize/$LS" ""
waited_and_refused "a finalize"
check "the refused finalize took nothing out of stock" "$LS_STOCK" "$(stock_of "$SKU_MAIN")"
put_back_and_void "$LS"

# Void. A void accepts a completed sale, so the status is set to VOIDED.
LS=$(open_sale_with_line) || no_open_sale
hold_sale "$LS" VOIDED
timed_request post "/sale/void/$LS" '"void behind the lock"'
waited_and_refused "a void"
check "the refused void did not set the voided flag" f "$(sql "select is_voided from transaction where id = '$LS'")"
put_back_and_void "$LS"

# Refund. The sale is really completed. The status is set to REFUNDED by
# hand, with no return row, and put back to COMPLETED afterwards.
LC=$(completed_sale) || { echo "  ✗ could not prepare a completed sale"; exit 1; }
hold_sale "$LC" REFUNDED
timed_request post "/sale/refund/$LC" '"refund behind the lock"'
waited_and_refused "a refund"
check "the refused refund wrote no return row" 0 "$(refunds_of "$LC")"
sql "update transaction set status = 'COMPLETED' where id = '$LC'" > /dev/null
