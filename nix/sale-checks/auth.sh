# ── Auth ────────────────────────────────────────────────────────────────

echo "── Auth ──"
check "request with no credentials is refused" 401 \
  "$($CURL -s -o /dev/null -w "%{http_code}" "$BASE_URL/session")"
check "a user id in the Authorization header is refused" 401 \
  "$($CURL -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ADMIN_ID" "$BASE_URL/session")"

# Logs in and prints the session token, or nothing when login fails.
login_token() {
  local body
  body=$($JQ -nc --arg u "$1" --arg p "$2" \
    '{loginUsername: $u, loginPassword: $p, loginRegisterId: null}')
  $CURL -s -D - -o /dev/null -X POST "$BASE_URL/auth/login" \
      -H "Content-Type: application/json" -d "$body" \
    | grep -i '^set-cookie:' | grep 'cheeblr_session=' \
    | sed 's/.*cheeblr_session=\([^;]*\).*/\1/' | tr -d '\r' | head -1 || true
}

TOKEN=$(login_token admin "$ADMIN_PASS")
if [ -z "$TOKEN" ]; then
  echo "  ✗ login did not return a session cookie"
  exit 1
fi
check "session cookie is accepted" 200 \
  "$($CURL -s -o /dev/null -w "%{http_code}" -H "Cookie: cheeblr_session=$TOKEN" "$BASE_URL/session")"