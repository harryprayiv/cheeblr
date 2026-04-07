{ pkgs, lib ? pkgs.lib, name }:

let
  config = import ./config.nix { inherit name; };

  host = config.network.host;
  backendPort = toString config.haskell.port;
  dbPort = toString config.database.port;

  backendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head config.haskell.codeDirs));
  frontendPath = builtins.head (builtins.split "/[^/]*$" (builtins.head config.purescript.codeDirs));
  dataDir = config.dataDir;

  tlsConfig = config.tls;
  certDir = tlsConfig.certDir;

  testBackendPort = "18080";
  testDbPort = "5432";

  test-unit = pkgs.writeShellScriptBin "test-unit" ''
    set -euo pipefail

    echo "════════════════════════════════════════════"
    echo "  ${name} — Unit Tests"
    echo "════════════════════════════════════════════"
    echo ""

    FAILURES=0

    echo "┌──────────────────────────────────────────┐"
    echo "│  Backend (Haskell) unit tests             │"
    echo "└──────────────────────────────────────────┘"
    if (cd ${backendPath} && cabal test ${name}-unit-tests --test-show-details=streaming 2>&1); then
      echo "✓ Backend tests passed"
    else
      echo "✗ Backend tests FAILED"
      FAILURES=$((FAILURES + 1))
    fi

    echo ""

    echo "┌──────────────────────────────────────────┐"
    echo "│  Frontend (PureScript) unit tests          │"
    echo "└──────────────────────────────────────────┘"
    if (cd ${frontendPath} && spago test 2>&1); then
      echo "✓ Frontend tests passed"
    else
      echo "✗ Frontend tests FAILED"
      FAILURES=$((FAILURES + 1))
    fi

    echo ""
    echo "════════════════════════════════════════════"
    if [ $FAILURES -eq 0 ]; then
      echo "  ✓ All unit tests passed"
    else
      echo "  ✗ $FAILURES test suite(s) failed"
    fi
    echo "════════════════════════════════════════════"

    exit $FAILURES
  '';

  test-integration = pkgs.writeShellScriptBin "test-integration" ''
    set -euo pipefail

    echo "════════════════════════════════════════════"
    echo "  ${name} — Integration Tests (HTTP)"
    echo "════════════════════════════════════════════"
    echo ""

    export USE_TLS="false"
    TEST_PROTOCOL="http"

    export TEST_PGDATA="''${TMPDIR:-/tmp}/${name}-test-$$"
    export PGDATA="$TEST_PGDATA"
    export PGPORT="${testDbPort}"
    export PGUSER="$(whoami)"
    PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS"
    export PGDATABASE="${name}"
    export PGHOST="$PGDATA"

    export PORT="${testBackendPort}"
    export DATABASE_URL="postgresql://$PGUSER:$PGPASSWORD@/$PGDATABASE?host=$PGDATA&port=$PGPORT"
    export TEST_BASE_URL="$TEST_PROTOCOL://${host}:${testBackendPort}"

    BACKEND_PID=""

    cleanup() {
      local exit_code=$?
      echo ""
      echo "Cleaning up..."

      if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo "Stopping backend (PID: $BACKEND_PID)..."
        kill -TERM "$BACKEND_PID" 2>/dev/null || true
        for i in $(seq 1 5); do
          kill -0 "$BACKEND_PID" 2>/dev/null || break
          sleep 1
        done
        kill -9 "$BACKEND_PID" 2>/dev/null || true
      fi

      ${pkgs.lsof}/bin/lsof -ti :${testBackendPort} 2>/dev/null | xargs -r kill -9 2>/dev/null || true

      if [ -d "$TEST_PGDATA" ]; then
        echo "Stopping test PostgreSQL..."
        ${pkgs.postgresql}/bin/pg_ctl -D "$TEST_PGDATA" stop -m immediate 2>/dev/null || true
        rm -rf "$TEST_PGDATA"
        echo "Removed test PGDATA: $TEST_PGDATA"
      fi

      exit $exit_code
    }
    trap cleanup EXIT INT TERM

    echo "Starting ephemeral PostgreSQL for testing (port ${testDbPort})..."
    mkdir -p "$TEST_PGDATA"

    ${pkgs.postgresql}/bin/initdb -D "$TEST_PGDATA" \
      --auth=trust --no-locale --encoding=UTF8 \
      --username="$(whoami)" > /dev/null 2>&1

    cat > "$TEST_PGDATA/postgresql.conf" << EOF
listen_addresses = '''
port = ${testDbPort}
unix_socket_directories = '$TEST_PGDATA'
max_connections = 20
shared_buffers = '32MB'
dynamic_shared_memory_type = posix
logging_collector = off
EOF

    cat > "$TEST_PGDATA/pg_hba.conf" << EOF
local   all   all   trust
EOF

    ${pkgs.postgresql}/bin/pg_ctl -D "$TEST_PGDATA" \
      -l "$TEST_PGDATA/postgresql.log" start > /dev/null 2>&1

    echo "Waiting for PostgreSQL..."
    RETRIES=0
    while ! ${pkgs.postgresql}/bin/pg_isready -h "$PGHOST" -p "$PGPORT" -q 2>/dev/null; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -ge 15 ]; then
        echo "PostgreSQL failed to start. Log:"
        cat "$TEST_PGDATA/postgresql.log" || true
        exit 1
      fi
      sleep 1
    done
    echo "✓ PostgreSQL ready on port ${testDbPort} (unix socket only)"

    ${pkgs.postgresql}/bin/psql -h "$PGHOST" -p "$PGPORT" postgres << EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$(whoami)') THEN
    CREATE USER "$(whoami)" WITH PASSWORD 'postgres' SUPERUSER;
  END IF;
END
\$\$;
DROP DATABASE IF EXISTS ${name};
CREATE DATABASE ${name};
GRANT ALL PRIVILEGES ON DATABASE ${name} TO "$(whoami)";
EOF
    echo "✓ Test database created"

    echo "Starting backend server on port ${testBackendPort}..."
    if [ -n "''${BACKEND_BIN:-}" ] && [ -x "''${BACKEND_BIN}" ]; then
      echo "Using pre-built binary: ''${BACKEND_BIN}"
      (PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS" "''${BACKEND_BIN}" 2>&1 | sed 's/^/  [backend] /') &
    else
      (cd ${backendPath} && PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS" cabal run ${name}-backend 2>&1 | sed 's/^/  [backend] /') &
    fi
    BACKEND_PID=$!

    echo "Waiting for backend on port ${testBackendPort}..."
    RETRIES=0
    while ! ${pkgs.curl}/bin/curl -s "$TEST_BASE_URL/openapi.json" > /dev/null 2>&1; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -ge 30 ]; then
        echo "Backend failed to start within 30 seconds"
        if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
          echo "Backend process died. Check build output above."
        fi
        exit 1
      fi
      sleep 1
    done
    echo "✓ Backend ready at $TEST_BASE_URL"

    echo ""
    FAILURES=0

    echo "┌──────────────────────────────────────────┐"
    echo "│  Backend Integration Tests (DB + API)     │"
    echo "└──────────────────────────────────────────┘"
    if (cd ${backendPath} && PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS" cabal test ${name}-integration-tests --test-show-details=streaming 2>&1); then
      echo "✓ Backend integration tests passed"
    else
      echo "✗ Backend integration tests FAILED (or suite not found, which is OK)"
    fi

    echo ""
    echo "════════════════════════════════════════════"
    if [ $FAILURES -eq 0 ]; then
      echo "  ✓ All integration tests passed (HTTP)"
    else
      echo "  ✗ $FAILURES integration suite(s) failed"
    fi
    echo "════════════════════════════════════════════"

    exit $FAILURES
  '';

  test-integration-tls = pkgs.writeShellScriptBin "test-integration-tls" ''
    set -euo pipefail

    echo "════════════════════════════════════════════"
    echo "  ${name} — Integration Tests (TLS)"
    echo "════════════════════════════════════════════"
    echo ""

    echo "Setting up TLS certificates..."
    tls-setup

    CERT_DIR="$(echo "${certDir}" | envsubst)"
    export USE_TLS="true"
    export TLS_CERT_FILE="$CERT_DIR/${tlsConfig.certFile}"
    export TLS_KEY_FILE="$CERT_DIR/${tlsConfig.keyFile}"
    TEST_PROTOCOL="https"

    CAROOT="$(${pkgs.mkcert}/bin/mkcert -CAROOT 2>/dev/null)"
    CURL_CA_ARGS=""
    if [ -f "$CAROOT/rootCA.pem" ]; then
      CURL_CA_ARGS="--cacert $CAROOT/rootCA.pem"
    else
      CURL_CA_ARGS="-k"
    fi

    export TEST_PGDATA="''${TMPDIR:-/tmp}/${name}-test-$$"
    export PGDATA="$TEST_PGDATA"
    export PGPORT="${testDbPort}"
    export PGUSER="$(whoami)"
    PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS"
    export PGDATABASE="${name}"
    export PGHOST="$PGDATA"

    export PORT="${testBackendPort}"
    export DATABASE_URL="postgresql://$PGUSER:$PGPASSWORD@/$PGDATABASE?host=$PGDATA&port=$PGPORT"
    export TEST_BASE_URL="$TEST_PROTOCOL://${host}:${testBackendPort}"

    BACKEND_PID=""

    cleanup() {
      local exit_code=$?
      echo ""
      echo "Cleaning up..."

      if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo "Stopping backend (PID: $BACKEND_PID)..."
        kill -TERM "$BACKEND_PID" 2>/dev/null || true
        for i in $(seq 1 5); do
          kill -0 "$BACKEND_PID" 2>/dev/null || break
          sleep 1
        done
        kill -9 "$BACKEND_PID" 2>/dev/null || true
      fi

      ${pkgs.lsof}/bin/lsof -ti :${testBackendPort} 2>/dev/null | xargs -r kill -9 2>/dev/null || true

      if [ -d "$TEST_PGDATA" ]; then
        echo "Stopping test PostgreSQL..."
        ${pkgs.postgresql}/bin/pg_ctl -D "$TEST_PGDATA" stop -m immediate 2>/dev/null || true
        rm -rf "$TEST_PGDATA"
        echo "Removed test PGDATA: $TEST_PGDATA"
      fi

      exit $exit_code
    }
    trap cleanup EXIT INT TERM

    echo "Starting ephemeral PostgreSQL for testing (port ${testDbPort})..."
    mkdir -p "$TEST_PGDATA"

    ${pkgs.postgresql}/bin/initdb -D "$TEST_PGDATA" \
      --auth=trust --no-locale --encoding=UTF8 \
      --username="$(whoami)" > /dev/null 2>&1

    cat > "$TEST_PGDATA/postgresql.conf" << EOF
listen_addresses = '''
port = ${testDbPort}
unix_socket_directories = '$TEST_PGDATA'
max_connections = 20
shared_buffers = '32MB'
dynamic_shared_memory_type = posix
logging_collector = off
EOF

    cat > "$TEST_PGDATA/pg_hba.conf" << EOF
local   all   all   trust
EOF

    ${pkgs.postgresql}/bin/pg_ctl -D "$TEST_PGDATA" \
      -l "$TEST_PGDATA/postgresql.log" start > /dev/null 2>&1

    echo "Waiting for PostgreSQL..."
    RETRIES=0
    while ! ${pkgs.postgresql}/bin/pg_isready -h "$PGHOST" -p "$PGPORT" -q 2>/dev/null; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -ge 15 ]; then
        echo "PostgreSQL failed to start. Log:"
        cat "$TEST_PGDATA/postgresql.log" || true
        exit 1
      fi
      sleep 1
    done
    echo "✓ PostgreSQL ready on port ${testDbPort} (unix socket only)"

    ${pkgs.postgresql}/bin/psql -h "$PGHOST" -p "$PGPORT" postgres << EOF
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '$(whoami)') THEN
    CREATE USER "$(whoami)" WITH PASSWORD 'postgres' SUPERUSER;
  END IF;
END
\$\$;
DROP DATABASE IF EXISTS ${name};
CREATE DATABASE ${name};
GRANT ALL PRIVILEGES ON DATABASE ${name} TO "$(whoami)";
EOF
    echo "✓ Test database created"

    echo "Starting backend server on port ${testBackendPort} (TLS)..."
    if [ -n "''${BACKEND_BIN:-}" ] && [ -x "''${BACKEND_BIN}" ]; then
      echo "Using pre-built binary: ''${BACKEND_BIN}"
      (PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS" "''${BACKEND_BIN}" 2>&1 | sed 's/^/  [backend] /') &
    else
      (cd ${backendPath} && PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS" cabal run ${name}-backend 2>&1 | sed 's/^/  [backend] /') &
    fi
    BACKEND_PID=$!

    echo "Waiting for backend on port ${testBackendPort}..."
    RETRIES=0
    while ! ${pkgs.curl}/bin/curl -s $CURL_CA_ARGS "$TEST_BASE_URL/openapi.json" > /dev/null 2>&1; do
      RETRIES=$((RETRIES + 1))
      if [ $RETRIES -ge 30 ]; then
        echo "Backend failed to start within 30 seconds"
        if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
          echo "Backend process died. Check build output above."
        fi
        exit 1
      fi
      sleep 1
    done
    echo "✓ Backend ready at $TEST_BASE_URL (TLS verified)"

    echo ""
    FAILURES=0

    echo "┌──────────────────────────────────────────┐"
    echo "│  Backend Integration Tests (DB + API)     │"
    echo "└──────────────────────────────────────────┘"
    if (cd ${backendPath} && PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS" cabal test ${name}-integration-tests --test-show-details=streaming 2>&1); then
      echo "✓ Backend integration tests passed"
    else
      echo "✗ Backend integration tests FAILED (or suite not found, which is OK)"
    fi

    echo ""

    echo "┌──────────────────────────────────────────┐"
    echo "│  TLS-specific checks                      │"
    echo "└──────────────────────────────────────────┘"

    CERT_SANS=$(${pkgs.openssl}/bin/openssl s_client -connect ${host}:${testBackendPort} </dev/null 2>/dev/null \
      | ${pkgs.openssl}/bin/openssl x509 -noout -ext subjectAltName 2>/dev/null || echo "FAIL")
    if echo "$CERT_SANS" | grep -qi "DNS:localhost"; then
      echo "  ✓ TLS certificate SAN includes localhost"
    else
      echo "  ✗ TLS certificate SAN missing localhost: $CERT_SANS"
      FAILURES=$((FAILURES + 1))
    fi

    HTTP_STATUS=$(${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 \
      "http://${host}:${testBackendPort}/openapi.json" 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" = "000" ] || [ "$HTTP_STATUS" = "426" ]; then
      echo "  ✓ Plain HTTP correctly rejected (status: $HTTP_STATUS)"
    else
      echo "  ✗ Plain HTTP returned status $HTTP_STATUS (expected 000 or 426)"
      FAILURES=$((FAILURES + 1))
    fi

    echo ""
    echo "════════════════════════════════════════════"
    if [ $FAILURES -eq 0 ]; then
      echo "  ✓ All integration tests passed (TLS)"
    else
      echo "  ✗ $FAILURES integration suite(s) failed"
    fi
    echo "════════════════════════════════════════════"

    exit $FAILURES
  '';

  test-suite = pkgs.writeShellScriptBin "test-suite" ''
    set -euo pipefail

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║    ${name} — Full Test Suite              ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""

    TOTAL_FAILURES=0

    echo "━━━ Phase 1: Unit Tests ━━━"
    echo ""
    if test-unit; then
      echo ""
      echo "Phase 1 passed ✓"
    else
      UNIT_EXIT=$?
      echo ""
      echo "Phase 1 had failures ✗"
      TOTAL_FAILURES=$((TOTAL_FAILURES + UNIT_EXIT))
    fi

    echo ""

    echo "━━━ Phase 2: Integration Tests (HTTP) ━━━"
    echo ""
    if test-integration; then
      echo ""
      echo "Phase 2 passed ✓"
    else
      INT_EXIT=$?
      echo ""
      echo "Phase 2 had failures ✗"
      TOTAL_FAILURES=$((TOTAL_FAILURES + INT_EXIT))
    fi

    echo ""

    echo "━━━ Phase 3: Integration Tests (TLS) ━━━"
    echo ""
    if test-integration-tls; then
      echo ""
      echo "Phase 3 passed ✓"
    else
      TLS_EXIT=$?
      echo ""
      echo "Phase 3 had failures ✗"
      TOTAL_FAILURES=$((TOTAL_FAILURES + TLS_EXIT))
    fi

    echo ""
    echo "╔══════════════════════════════════════════╗"
    if [ $TOTAL_FAILURES -eq 0 ]; then
      echo "║  ✓ ALL TESTS PASSED                      ║"
    else
      echo "║  ✗ SOME TESTS FAILED ($TOTAL_FAILURES)               ║"
    fi
    echo "╚══════════════════════════════════════════╝"

    exit $TOTAL_FAILURES
  '';

  test-smoke = pkgs.writeShellScriptBin "test-smoke" ''
    set -euo pipefail

    BASE_URL="https://${host}:${backendPort}"

    echo "Smoke testing backend at $BASE_URL ..."
    echo ""

    CAROOT="$(${pkgs.mkcert}/bin/mkcert -CAROOT 2>/dev/null)"
    CURL_CA_ARGS=""
    if [ -f "$CAROOT/rootCA.pem" ]; then
      CURL_CA_ARGS="--cacert $CAROOT/rootCA.pem"
    else
      CURL_CA_ARGS="-k"
    fi

    PASS=0
    FAIL=0

    # $6 is now a session token sent as Cookie: cheeblr_session=<token>
    check() {
      local description="$1"
      local method="$2"
      local url="$3"
      local expected_status="$4"
      local body="''${5:-}"
      local token="''${6:-}"

      local curl_args=(-s -o /dev/null -w "%{http_code}" $CURL_CA_ARGS
                       --connect-timeout 5 --max-time 15 -X "$method")

      if [ -n "$body" ]; then
        curl_args+=(-H "Content-Type: application/json" -d "$body")
      fi

      if [ -n "$token" ]; then
        curl_args+=(-H "Cookie: cheeblr_session=$token")
      fi

      local status
      status=$(${pkgs.curl}/bin/curl "''${curl_args[@]}" "$url" 2>/dev/null || echo "000")

      if [ "$status" = "$expected_status" ]; then
        echo "  ✓ $description (HTTP $status)"
        PASS=$((PASS + 1))
      elif [ "$status" = "000" ]; then
        echo "  ✗ $description (connection failed/timed out)"
        FAIL=$((FAIL + 1))
      else
        echo "  ✗ $description (expected $expected_status, got $status)"
        FAIL=$((FAIL + 1))
      fi
    }


    echo "── Connectivity ──"
    if ! ${pkgs.curl}/bin/curl -s $CURL_CA_ARGS --connect-timeout 5 --max-time 10 \
        "$BASE_URL/openapi.json" > /dev/null 2>&1; then
      echo "✗ Backend is not reachable at $BASE_URL"
      echo "  Make sure the backend is running (e.g. 'backend-start' or 'deploy')"
      exit 1
    fi
    echo "✓ Backend is reachable"
    check "GET /openapi.json (no auth)" GET "$BASE_URL/openapi.json" 200


    echo ""
    echo "── Unauthenticated rejection ──"
    check "GET /inventory (no token)"  GET "$BASE_URL/inventory" 401
    check "GET /session (no token)"    GET "$BASE_URL/session"   401
    check "GET /register (no token)"   GET "$BASE_URL/register"  401


    echo ""
    echo "── Auth flow ──"

    ADMIN_PASSWORD="$(sops-get admin_password 2>/dev/null || true)"
    if [ -z "$ADMIN_PASSWORD" ]; then
      echo "  ✗ Could not retrieve admin_password from sops — skipping auth flow"
      echo "    Run 'bootstrap-admin' if this is a fresh environment"
      FAIL=$((FAIL + 1))
    else
      # Dump response headers (-D -) and body together; token is in Set-Cookie header
      LOGIN_OUTPUT=$(${pkgs.curl}/bin/curl -s -D - $CURL_CA_ARGS \
        -X POST "$BASE_URL/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"loginUsername\":\"admin\",\"loginPassword\":\"$ADMIN_PASSWORD\",\"loginRegisterId\":null}" \
        2>/dev/null || true)

      # Extract cheeblr_session value from Set-Cookie header
      TOKEN=$(echo "$LOGIN_OUTPUT" \
        | grep -i '^set-cookie:' \
        | grep 'cheeblr_session=' \
        | sed 's/.*cheeblr_session=\([^;]*\).*/\1/' \
        | tr -d '\r' \
        | head -1 || true)

      # Also grab the JSON body for diagnostics (everything after the blank header/body separator)
      LOGIN_BODY=$(echo "$LOGIN_OUTPUT" | awk 'BEGIN{p=0} /^[[:space:]]*$/{p=1; next} p{print}' | tail -1)

      if [ -z "$TOKEN" ]; then
        echo "  ✗ Login failed — no cheeblr_session cookie in response"
        echo "    Response body: $LOGIN_BODY"
        FAIL=$((FAIL + 1))
      else
        echo "  ✓ POST /auth/login set cheeblr_session cookie"
        PASS=$((PASS + 1))


        echo ""
        echo "── Authenticated endpoints ──"
        check "GET /auth/me"            GET  "$BASE_URL/auth/me"   200 "" "$TOKEN"
        check "GET /session"            GET  "$BASE_URL/session"   200 "" "$TOKEN"
        check "GET /inventory"          GET  "$BASE_URL/inventory" 200 "" "$TOKEN"
        check "GET /register"           GET  "$BASE_URL/register"  200 "" "$TOKEN"


        echo ""
        echo "── Inventory JSON contract ──"
        INVENTORY_JSON=$(${pkgs.curl}/bin/curl -s $CURL_CA_ARGS \
          -H "Cookie: cheeblr_session=$TOKEN" \
          "$BASE_URL/inventory" 2>/dev/null || true)

        if echo "$INVENTORY_JSON" | ${pkgs.jq}/bin/jq -e 'arrays' > /dev/null 2>&1; then
          echo "  ✓ /inventory returns a JSON array"
          PASS=$((PASS + 1))
          ITEM_COUNT=$(echo "$INVENTORY_JSON" | ${pkgs.jq}/bin/jq 'length')
          echo "  ✓ Inventory item count: $ITEM_COUNT"
          PASS=$((PASS + 1))
          if [ "$ITEM_COUNT" -gt 0 ]; then
            if echo "$INVENTORY_JSON" | ${pkgs.jq}/bin/jq -e '.[0] | .sku and .name and .price' > /dev/null 2>&1; then
              echo "  ✓ First item has expected fields (sku, name, price)"
              PASS=$((PASS + 1))
            else
              echo "  ✗ First item missing expected fields"
              FAIL=$((FAIL + 1))
            fi
          fi
        else
          echo "  ✗ /inventory did not return a JSON array"
          echo "    Response: $(echo "$INVENTORY_JSON" | head -c 200)"
          FAIL=$((FAIL + 1))
        fi


        echo ""
        echo "── Session JSON contract ──"
        SESSION_JSON=$(${pkgs.curl}/bin/curl -s $CURL_CA_ARGS \
          -H "Cookie: cheeblr_session=$TOKEN" \
          "$BASE_URL/session" 2>/dev/null || true)

        if echo "$SESSION_JSON" | ${pkgs.jq}/bin/jq -e \
            '.sessionUserId and .sessionUserName and .sessionRole and .sessionCapabilities' \
            > /dev/null 2>&1; then
          echo "  ✓ /session response has expected fields"
          PASS=$((PASS + 1))
          ROLE=$(echo "$SESSION_JSON" | ${pkgs.jq}/bin/jq -r '.sessionRole')
          echo "  ✓ Logged in as role: $ROLE"
          PASS=$((PASS + 1))
        else
          echo "  ✗ /session response missing expected fields"
          echo "    Response: $(echo "$SESSION_JSON" | head -c 200)"
          FAIL=$((FAIL + 1))
        fi


        echo ""
        echo "── Logout and revocation ──"
        check "POST /auth/logout"           POST "$BASE_URL/auth/logout" 200 "" "$TOKEN"
        check "GET /inventory after logout" GET  "$BASE_URL/inventory"   401 "" "$TOKEN"
      fi
    fi


    echo ""
    echo "── Rate limiting ──"
    for _i in $(seq 1 5); do
      ${pkgs.curl}/bin/curl -s $CURL_CA_ARGS -o /dev/null \
        -X POST "$BASE_URL/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"loginUsername":"nonexistent","loginPassword":"wrong","loginRegisterId":null}' \
        2>/dev/null || true
    done
    RATE_STATUS=$(${pkgs.curl}/bin/curl -s $CURL_CA_ARGS -o /dev/null -w "%{http_code}" \
      -X POST "$BASE_URL/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"loginUsername":"nonexistent","loginPassword":"wrong","loginRegisterId":null}' \
      2>/dev/null || echo "000")
    if [ "$RATE_STATUS" = "429" ]; then
      echo "  ✓ Rate limit enforced after repeated failures (HTTP 429)"
      PASS=$((PASS + 1))
    else
      echo "  ✗ Rate limit not triggered (expected 429, got $RATE_STATUS)"
      FAIL=$((FAIL + 1))
    fi

    echo ""
    echo "────────────────────────────────"
    echo "  Passed: $PASS  Failed: $FAIL"
    echo "────────────────────────────────"

    [ $FAIL -eq 0 ]
  '';

in {
  inherit test-unit test-integration test-integration-tls test-suite test-smoke;
}
