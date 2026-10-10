# ── H. Identity and permissions ─────────────────────────────────────────

echo ""
echo "── H. The session decides who is acting and what they may do ──"
ADMIN_TOKEN="$TOKEN"
CASHIER_PASS="cashier-test-password-1"
NEW_USER=$($JQ -nc --arg p "$CASHIER_PASS" \
  '{newReqUsername: "cashier1", newReqDisplayName: "Cashier One", newReqEmail: null, newReqRole: "Cashier", newReqLocationId: null, newReqPassword: $p}')
check "admin creates a cashier account" 200 "$(post /auth/users "$NEW_USER")"
CASHIER_ID=$(sql "select id from users where username = 'cashier1'")
CASHIER_TOKEN=$(login_token cashier1 "$CASHIER_PASS")

SALE_A=$(start_sale) || { echo "  ✗ could not start a sale"; exit 1; }
check "admin adds 1 to the admin's sale" 200 "$(post /pos/sale/item "$(add_body "$SALE_A" "$SKU_MAIN" 1)")"
LINE_A=$(sql "select id from transaction_item where transaction_id = '$SALE_A'")
TOTAL_A=$(sql "select total from transaction where id = '$SALE_A'")

TOKEN="$CASHIER_TOKEN"
check "cashier session is accepted" 200 \
  "$($CURL -s -o /dev/null -w "%{http_code}" -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL/session")"
check "cashier cannot add to another employee's sale" 403 "$(post /pos/sale/item "$(add_body "$SALE_A" "$SKU_MAIN" 1)")"
check "cashier cannot pay on another employee's sale" 403 "$(post /pos/sale/payment "$(pay_body "$SALE_A" "$TOTAL_A")")"
check "cashier cannot finalize another employee's sale" 403 "$(post "/pos/sale/finalize/$SALE_A" "")"
check "cashier cannot clear another employee's sale" 403 "$(post "/pos/sale/clear/$SALE_A" "")"
check "cashier cannot remove a line from another employee's sale" 403 "$(del "/pos/sale/item/$LINE_A")"
check "the other employee's sale still has its line" 1 "$(line_qty "$SALE_A")"
check "the other employee's sale has no payment" 0 "$(sql "select count(*) from payment_transaction where transaction_id = '$SALE_A'")"

# start_sale sends the admin's id as the employee id. Sent by the cashier,
# that is a forged id.
SALE_C=$(start_sale) || { echo "  ✗ cashier could not start a sale"; exit 1; }
check "a forged employee id is replaced by the caller's id" "$CASHIER_ID" \
  "$(sql "select employee_id from transaction where id = '$SALE_C'")"
check "cashier adds 1 to the cashier's own sale" 200 "$(post /pos/sale/item "$(add_body "$SALE_C" "$SKU_MAIN" 1)")"
check "cashier cannot void, even the cashier's own sale" 403 "$(post "/sale/void/$SALE_C" '"cashier void"')"
check "the cashier's sale is still IN_PROGRESS" IN_PROGRESS "$(status_of "$SALE_C")"
check "cashier cannot refund a completed sale" 403 "$(post "/sale/refund/$SALE2" '"cashier refund"')"
check "the completed sale is still COMPLETED" COMPLETED "$(status_of "$SALE2")"

TOKEN="$ADMIN_TOKEN"
check "admin can add to the cashier's sale" 200 "$(post /pos/sale/item "$(add_body "$SALE_C" "$SKU_MAIN" 1)")"
check "the cashier's sale now holds 2" 2 "$(line_qty "$SALE_C")"
check "admin can void the cashier's sale" 200 "$(post "/sale/void/$SALE_C" '"admin void"')"
check "the cashier's sale is VOIDED" VOIDED "$(status_of "$SALE_C")"

# ── I. Registers, reservations and the manager's void ───────────────────

echo ""
echo "── I. Registers, reservation routes and the manager's void ──"
TEST_REG="dddddddd-0000-4000-8000-000000000001"
REG_BODY=$($JQ -nc --arg i "$TEST_REG" --arg l "$LOCATION_ID" \
  '{registerId: $i, registerName: "Test register", registerLocationId: $l, registerIsOpen: false, registerCurrentDrawerAmount: 0, registerExpectedDrawerAmount: 0, registerOpenedAt: null, registerOpenedBy: null, registerLastTransactionTime: null}')
check "admin creates a register" 200 "$(post /register "$REG_BODY")"

CUSTOMER_PASS="customer-test-password-1"
NEW_CUSTOMER=$($JQ -nc --arg p "$CUSTOMER_PASS" \
  '{newReqUsername: "customer1", newReqDisplayName: "Customer One", newReqEmail: null, newReqRole: "Customer", newReqLocationId: null, newReqPassword: $p}')
check "admin creates a customer account" 200 "$(post /auth/users "$NEW_CUSTOMER")"
CUSTOMER_TOKEN=$(login_token customer1 "$CUSTOMER_PASS")

# Both register bodies name the admin as the employee, whoever sends them.
OPEN_BODY=$($JQ -nc --arg e "$ADMIN_ID" '{openRegisterEmployeeId: $e, openRegisterStartingCash: 10000}')
CLOSE_BODY=$($JQ -nc --arg e "$ADMIN_ID" '{closeRegisterEmployeeId: $e, closeRegisterCountedCash: 10000}')
START_BODY=$($JQ -nc --arg e "$ADMIN_ID" --arg r "$REGISTER_ID" --arg l "$LOCATION_ID" \
  '{startSaleEmployeeId: $e, startSaleRegisterId: $r, startSaleLocationId: $l}')
RESERVE_BODY=$($JQ -nc --arg s "$SKU_MAIN" --arg t "$SALE_A" \
  '{reserveItemSku: $s, reserveTransactionId: $t, reserveQuantity: 1}')
RES_A=$(sql "select id from inventory_reservation where transaction_id = '$SALE_A' and status = 'Reserved'")
RES_BEFORE=$(sql "select count(*) from inventory_reservation")

TOKEN="$CUSTOMER_TOKEN"
check "customer session is accepted" 200 \
  "$($CURL -s -o /dev/null -w "%{http_code}" -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL/session")"
check "customer cannot start a sale" 403 "$(post /pos/sale "$START_BODY")"
check "customer cannot open a register" 403 "$(post "/register/open/$TEST_REG" "$OPEN_BODY")"
check "the register is still closed" f "$(sql "select is_open from register where id = '$TEST_REG'")"

TOKEN="$CASHIER_TOKEN"
check "cashier opens the register" 200 "$(post "/register/open/$TEST_REG" "$OPEN_BODY")"
check "a forged employee id on the open is replaced by the caller's id" "$CASHIER_ID" \
  "$(sql "select opened_by from register where id = '$TEST_REG'")"
check "the reserve route refuses" 410 "$(post /inventory/reserve "$RESERVE_BODY")"
check "the release route refuses" 410 "$(del "/inventory/release/$RES_A")"
check "no reservation was added" "$RES_BEFORE" "$(sql "select count(*) from inventory_reservation")"
check "the admin's sale still holds its reservation" 1 "$(live_res "$SALE_A")"

TOKEN="$CUSTOMER_TOKEN"
check "customer cannot close a register" 403 "$(post "/register/close/$TEST_REG" "$CLOSE_BODY")"
check "the register is still open" t "$(sql "select is_open from register where id = '$TEST_REG'")"
TOKEN="$CASHIER_TOKEN"
check "cashier closes the register" 200 "$(post "/register/close/$TEST_REG" "$CLOSE_BODY")"

OVERRIDE_BODY=$($JQ -nc --arg a "$ADMIN_ID" '{orActorId: $a, orReason: "manager override"}')
open_pulls() { sql "select count(*) from stock_pull_requests where transaction_id = '$1' and status not in ('PullFulfilled', 'PullCancelled')"; }
check "cashier cannot use the manager's void" 403 "$(post "/manager/override/void/$SALE_A" "$OVERRIDE_BODY")"
TOKEN="$ADMIN_TOKEN"
check "the admin's sale has one open stock pull" 1 "$(open_pulls "$SALE_A")"
check "the manager's void returns 200" 200 "$(post "/manager/override/void/$SALE_A" "$OVERRIDE_BODY")"
check "the sale is VOIDED" VOIDED "$(status_of "$SALE_A")"
check "the void released the reservation" 0 "$(live_res "$SALE_A")"
check "the void cancelled the stock pull" 0 "$(open_pulls "$SALE_A")"
check "a second manager's void returns 409" 409 "$(post "/manager/override/void/$SALE_A" "$OVERRIDE_BODY")"