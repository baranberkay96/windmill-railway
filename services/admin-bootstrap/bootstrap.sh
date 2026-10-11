#!/bin/sh
# One-shot job: replace the documented default password of Windmill's seeded
# superadmin (admin@windmill.dev / "changeme") with WINDMILL_ADMIN_PASSWORD.
#
# Idempotent: if the default password is no longer accepted (already rotated,
# or changed by a human), the job exits 0 without touching anything.
# Exits non-zero on any unexpected answer so Railway's ON_FAILURE policy retries.
#
# Uses only Windmill's public REST API over the private network:
#   GET  /api/version          readiness
#   POST /api/auth/login       {email,password} -> session token (text/plain)
#   POST /api/users/setpassword {password}      (as the logged-in user)
#   POST /api/auth/logout
set -eu

SERVER_URL="${WINDMILL_INTERNAL_URL:?WINDMILL_INTERNAL_URL is required}"
ADMIN_EMAIL="${WINDMILL_ADMIN_EMAIL:-admin@windmill.dev}"
NEW_PASSWORD="${WINDMILL_ADMIN_PASSWORD:?WINDMILL_ADMIN_PASSWORD is required}"
WAIT_SECONDS="${BOOTSTRAP_WAIT_SECONDS:-900}"
POLL_SECONDS=5
MIN_PASSWORD_LENGTH=16
# Windmill's documented first-login password; only used to detect and replace it.
DEFAULT_PASSWORD="changeme"

umask 077
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

log() { printf '[admin-bootstrap] %s\n' "$*"; }
fail() { printf '[admin-bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

# --- input validation -------------------------------------------------------
case "$SERVER_URL" in
  http://*|https://*) ;;
  *) fail "WINDMILL_INTERNAL_URL must start with http:// or https://" ;;
esac
SERVER_URL="${SERVER_URL%/}"

# Letters and digits only: matches the generated secret and keeps the JSON
# bodies below free of characters that would need escaping.
case "$NEW_PASSWORD" in
  *[!A-Za-z0-9]*) fail "WINDMILL_ADMIN_PASSWORD must contain only letters and digits" ;;
esac
[ "${#NEW_PASSWORD}" -ge "$MIN_PASSWORD_LENGTH" ] \
  || fail "WINDMILL_ADMIN_PASSWORD must be at least $MIN_PASSWORD_LENGTH characters"
[ "$NEW_PASSWORD" != "$DEFAULT_PASSWORD" ] \
  || fail "WINDMILL_ADMIN_PASSWORD must differ from the default password"

case "$ADMIN_EMAIL" in
  *[!A-Za-z0-9@._+-]*|*@*@*|@*|*@) fail "WINDMILL_ADMIN_EMAIL is not a plain email address" ;;
  *@*.*) ;;
  *) fail "WINDMILL_ADMIN_EMAIL is not a plain email address" ;;
esac

case "$WAIT_SECONDS" in
  ''|*[!0-9]*) fail "BOOTSTRAP_WAIT_SECONDS must be a whole number" ;;
esac

# --- helpers ----------------------------------------------------------------
# post_json <path> <body-file> [token] -> prints HTTP status, body in $WORK_DIR/out
post_json() {
  if [ -n "${3:-}" ]; then
    curl -sS --max-time 20 -o "$WORK_DIR/out" -w '%{http_code}' \
      -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $3" \
      --data-binary "@$2" "$SERVER_URL$1"
  else
    curl -sS --max-time 20 -o "$WORK_DIR/out" -w '%{http_code}' \
      -H 'Content-Type: application/json' \
      --data-binary "@$2" "$SERVER_URL$1"
  fi
}

# login <password> -> prints HTTP status, token in $WORK_DIR/out on 200
login() {
  printf '{"email":"%s","password":"%s"}' "$ADMIN_EMAIL" "$1" > "$WORK_DIR/login.json"
  post_json /api/auth/login "$WORK_DIR/login.json"
}

read_token() {
  token="$(cat "$WORK_DIR/out")"
  case "$token" in
    no_auth) fail "Windmill runs with NO_AUTH; refusing to continue" ;;
    ''|*[!A-Za-z0-9]*) fail "Unexpected login response format" ;;
  esac
  printf '%s' "$token"
}

logout() {
  printf '{}' > "$WORK_DIR/empty.json"
  post_json /api/auth/logout "$WORK_DIR/empty.json" "$1" > /dev/null || true
}

# --- wait for the server ----------------------------------------------------
log "Waiting up to ${WAIT_SECONDS}s for Windmill at $SERVER_URL"
deadline=$(( $(date +%s) + WAIT_SECONDS ))
until version="$(curl -fsS --max-time 5 "$SERVER_URL/api/version" 2>/dev/null)"; do
  [ "$(date +%s)" -lt "$deadline" ] || fail "Windmill did not answer within ${WAIT_SECONDS}s"
  sleep "$POLL_SECONDS"
done
log "Windmill is up ($version)"

# --- try the default credentials --------------------------------------------
status="$(login "$DEFAULT_PASSWORD")" || fail "Login request failed"
case "$status" in
  200) ;;
  400|401|403)
    log "Default password is not accepted for $ADMIN_EMAIL; nothing to rotate."
    exit 0
    ;;
  *) fail "Unexpected HTTP $status from /api/auth/login" ;;
esac
default_token="$(read_token)"

# --- rotate -----------------------------------------------------------------
printf '{"password":"%s"}' "$NEW_PASSWORD" > "$WORK_DIR/password.json"
status="$(post_json /api/users/setpassword "$WORK_DIR/password.json" "$default_token")" \
  || fail "setpassword request failed"
if [ "$status" != "200" ]; then
  logout "$default_token"
  fail "HTTP $status from /api/users/setpassword: $(head -c 300 "$WORK_DIR/out")"
fi
logout "$default_token"

# --- verify -----------------------------------------------------------------
status="$(login "$NEW_PASSWORD")" || fail "Verification login request failed"
[ "$status" = "200" ] || fail "New password was not accepted (HTTP $status)"
verify_token="$(read_token)"
logout "$verify_token"

log "Password of $ADMIN_EMAIL rotated. Read it from this service's WINDMILL_ADMIN_PASSWORD variable."
