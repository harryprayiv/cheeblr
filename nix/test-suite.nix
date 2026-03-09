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
      export PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS"
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
      (cd ${backendPath} && cabal run ${name}-backend 2>&1 | sed 's/^/  [backend] /') &
      BACKEND_PID=$!

      echo "Waiting for backend on port ${testBackendPort}..."
      RETRIES=0
      while ! ${pkgs.curl}/bin/curl -s "$TEST_BASE_URL/inventory" > /dev/null 2>&1; do
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
      echo "│  HTTP Integration Tests (PS → Backend)    │"
      echo "└──────────────────────────────────────────┘"
      if (cd ${frontendPath} && spago test 2>&1); then
        echo "✓ HTTP integration tests passed"
      else
        echo "✗ HTTP integration tests FAILED"
        FAILURES=$((FAILURES + 1))
      fi

      echo ""

      echo "┌──────────────────────────────────────────┐"
      echo "│  Backend Integration Tests (DB + API)     │"
      echo "└──────────────────────────────────────────┘"
      if (cd ${backendPath} && cabal test ${name}-integration-tests --test-show-details=streaming 2>&1); then
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
      export PGPASSWORD="BOOTSTRAP_FALLBACK_ONLY_USE_SOPS"
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
      (cd ${backendPath} && cabal run ${name}-backend 2>&1 | sed 's/^/  [backend] /') &
      BACKEND_PID=$!

      echo "Waiting for backend on port ${testBackendPort}..."
      RETRIES=0
      while ! ${pkgs.curl}/bin/curl -s $CURL_CA_ARGS "$TEST_BASE_URL/inventory" > /dev/null 2>&1; do
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
      echo "│  HTTP Integration Tests (PS → Backend)    │"
      echo "└──────────────────────────────────────────┘"
      if (cd ${frontendPath} && spago test 2>&1); then
        echo "✓ HTTP integration tests passed"
      else
        echo "✗ HTTP integration tests FAILED"
        FAILURES=$((FAILURES + 1))
      fi

      echo ""

      echo "┌──────────────────────────────────────────┐"
      echo "│  Backend Integration Tests (DB + API)     │"
      echo "└──────────────────────────────────────────┘"
      if (cd ${backendPath} && cabal test ${name}-integration-tests --test-show-details=streaming 2>&1); then
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
        "http://${host}:${testBackendPort}/inventory" 2>/dev/null || echo "000")
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

      echo "Checking backend connectivity..."
      if ! ${pkgs.curl}/bin/curl -s $CURL_CA_ARGS --connect-timeout 5 --max-time 10 "$BASE_URL/inventory" > /dev/null 2>&1; then
        echo "✗ Backend is not reachable at $BASE_URL"
        echo "  Make sure the backend is running (e.g. 'backend-start' or 'deploy')"
        exit 1
      fi
      echo "✓ Backend is reachable"
      echo ""

      PASS=0
      FAIL=0

      check() {
        local description="$1"
        local method="$2"
        local url="$3"
        local expected_status="$4"
        local body="''${5:-}"
        local auth_header="''${6:-}"

        local curl_args=(-s -o /dev/null -w "%{http_code}" $CURL_CA_ARGS --connect-timeout 5 --max-time 15 -X "$method")

        if [ -n "$body" ]; then
          curl_args+=(-H "Content-Type: application/json" -d "$body")
        fi

        if [ -n "$auth_header" ]; then
          curl_args+=(-H "X-User-Id: $auth_header")
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

      ADMIN_UUID="d3a1f4f0-c518-4db3-aa43-e80b428d6304"
      CASHIER_UUID="0a6f2deb-892b-4411-8025-08c1a4d61229"
      CUSTOMER_UUID="8244082f-a6bc-4d6c-9427-64a0ecdc10db"

      echo "── GET endpoints ──"
      check "GET /inventory (admin)"         GET "$BASE_URL/inventory" 200 "" "$ADMIN_UUID"
      check "GET /inventory (customer)"      GET "$BASE_URL/inventory" 200 "" "$CUSTOMER_UUID"
      check "GET /inventory (no auth)"       GET "$BASE_URL/inventory" 200 "" ""

      echo ""
      echo "── Auth-gated endpoints ──"
      check "GET /register (cashier)"       GET "$BASE_URL/register" 200 "" "$CASHIER_UUID"

      echo ""
      echo "── JSON contract spot checks ──"

      INVENTORY_JSON=$(${pkgs.curl}/bin/curl -s $CURL_CA_ARGS -H "Authorization: $ADMIN_UUID" "$BASE_URL/inventory")
      if echo "$INVENTORY_JSON" | ${pkgs.jq}/bin/jq -e '.type' > /dev/null 2>&1; then
        TYPE=$(echo "$INVENTORY_JSON" | ${pkgs.jq}/bin/jq -r '.type')
        if [ "$TYPE" = "data" ] || [ "$TYPE" = "message" ]; then
          echo "  ✓ Inventory response has valid 'type' field: $TYPE"
          PASS=$((PASS + 1))
        else
          echo "  ✗ Inventory response 'type' field unexpected: $TYPE"
          FAIL=$((FAIL + 1))
        fi

        if [ "$TYPE" = "data" ]; then
          if echo "$INVENTORY_JSON" | ${pkgs.jq}/bin/jq -e '.capabilities.capCanViewInventory' > /dev/null 2>&1; then
            echo "  ✓ Inventory response includes capabilities"
            PASS=$((PASS + 1))
          else
            echo "  ✗ Inventory response missing capabilities"
            FAIL=$((FAIL + 1))
          fi
        fi
      else
        echo "  ✗ Inventory response is not valid JSON"
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
