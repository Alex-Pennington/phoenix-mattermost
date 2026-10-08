#!/bin/bash
# Local smoke test of the patched image. Runs a throwaway stack (its own
# postgres:16-alpine, internal network, Mattermost on 127.0.0.1 only),
# then tears it down and removes its volumes. Touches nothing live.
#
# Usage: bash test-local.sh [SCRATCHDIR]
#   PATCHED_IMAGE  default phoenix/mattermost-team-edition:11.11.1-phoenix1
#   STOCK_IMAGE    default mattermost/mattermost-team-edition:11.11.1
#   MM_PORT        default 18065
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="${1:-$HOME/mm-phoenix-test}"
PATCHED_IMAGE="${PATCHED_IMAGE:-phoenix/mattermost-team-edition:11.11.1-phoenix1}"
STOCK_IMAGE="${STOCK_IMAGE:-mattermost/mattermost-team-edition:11.11.1}"
export MM_PORT="${MM_PORT:-18065}"
BASE="http://127.0.0.1:${MM_PORT}"
FAKE_AUTH="https://idp.invalid/application/o/authorize/"

mkdir -p "$SCRATCH"
cp "$HERE/test-compose.yml" "$SCRATCH/compose.yml"
DC=(docker compose -f "$SCRATCH/compose.yml" -p mmphoenixtest)
FAIL=0

cleanup() {
  echo "== teardown"
  MM_IMAGE="$PATCHED_IMAGE" "${DC[@]}" down -v --remove-orphans
}
trap cleanup EXIT

check() { # name, condition result (0 = pass)
  if [ "$2" -eq 0 ]; then echo "PASS  $1"; else echo "FAIL  $1"; FAIL=1; fi
}

start_mm() { # image, gitlab on|off
  export MM_IMAGE="$1"
  if [ "$2" = on ]; then
    export GL_ENABLE=true GL_ID=fake-client-id GL_SECRET=fake-client-secret
    export GL_AUTH="$FAKE_AUTH"
    export GL_TOKEN="https://idp.invalid/application/o/token/"
    export GL_USERAPI="https://idp.invalid/application/o/userinfo/"
  else
    export GL_ENABLE=false GL_ID= GL_SECRET= GL_AUTH= GL_TOKEN= GL_USERAPI=
  fi
  "${DC[@]}" up -d --force-recreate mm >/dev/null 2>&1 || { echo "compose up failed"; "${DC[@]}" logs --tail 50 mm; return 1; }
  for _ in $(seq 1 90); do
    if curl -fsS "$BASE/api/v4/system/ping" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  echo "server did not answer ping"; "${DC[@]}" logs --tail 50 mm; return 1
}

phase() { # label, image, gitlab
  local label="$1"
  echo "== $label: $2, GitLab $3"
  start_mm "$2" "$3"; check "$label boots" $?
  local ping
  ping="$(curl -sS "$BASE/api/v4/system/ping")"
  echo "   ping: $ping"
  echo "$ping" | grep -q '"status":"OK"'; check "$label ping status OK" $?
  curl -sS "$BASE/api/v4/config/client?format=old" -o "$SCRATCH/$label.json"
  echo "   X-Version-Id: $(curl -sS -o /dev/null -D - "$BASE/api/v4/system/ping" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-version-id"{print $2}')"
  echo "   EnableSignUpWithGitLab: $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("EnableSignUpWithGitLab","<absent>"))' "$SCRATCH/$label.json")"
  echo "   BuildNumber: $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("BuildNumber"))' "$SCRATCH/$label.json")"
}

gl_flag() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("EnableSignUpWithGitLab","<absent>"))' "$1"; }

echo "== db up"
MM_IMAGE="$STOCK_IMAGE" "${DC[@]}" up -d db >/dev/null 2>&1
check "postgres up" $?

phase stock-off "$STOCK_IMAGE" off
phase stock-on "$STOCK_IMAGE" on
[ "$(gl_flag "$SCRATCH/stock-on.json")" = "<absent>" ]; check "stock + GitLab enabled: flag absent (the v11 gate)" $?

phase patched-off "$PATCHED_IMAGE" off
[ "$(gl_flag "$SCRATCH/patched-off.json")" = "false" ]; check "patched + GitLab disabled: EnableSignUpWithGitLab=false" $?
echo "-- client config, stock-off -> patched-off (expect only the 3 GitLab keys and build identity)"
python3 -I "$HERE/compare-client-config.py" "$SCRATCH/stock-off.json" "$SCRATCH/patched-off.json"

phase patched-on "$PATCHED_IMAGE" on
[ "$(gl_flag "$SCRATCH/patched-on.json")" = "true" ]; check "patched + GitLab enabled: EnableSignUpWithGitLab=true" $?
scope="$("${DC[@]}" exec -T mm mmctl --local config get GitLabSettings.Scope 2>&1 | tr -d '\r')"
echo "   GitLabSettings.Scope: $scope"
[ "$scope" = '""' ]; check "GitLabSettings.Scope empty" $?
loc="$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE/oauth/gitlab/login")"
echo "   /oauth/gitlab/login -> ${loc%%&state=*}&state=..."
case "$loc" in 302\ "$FAKE_AUTH"\?response_type=code\&client_id=fake-client-id*) r=0 ;; *) r=1 ;; esac
check "/oauth/gitlab/login redirects to the configured AuthEndpoint" $r
bn="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("BuildNumber"))' "$SCRATCH/patched-on.json")"
[ "$bn" = "11.11.1-phoenix1" ]; check "BuildNumber is 11.11.1-phoenix1" $?

if [ $FAIL -eq 0 ]; then echo "== ALL PASS"; else echo "== FAILURES"; fi
exit $FAIL
