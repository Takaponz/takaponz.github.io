#!/bin/sh

set -eu

site_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
site_check_tmp=$(mktemp -d)
site_check_pid=""

cleanup() {
  if [ -n "$site_check_pid" ]; then
    kill "$site_check_pid" 2>/dev/null || true
    wait "$site_check_pid" 2>/dev/null || true
  fi
  rm -rf "$site_check_tmp"
}
trap cleanup EXIT HUP INT TERM

site_check_port=$(python3 -c 'import socket; sock = socket.socket(); sock.bind(("127.0.0.1", 0)); print(sock.getsockname()[1]); sock.close()')

python3 -m http.server "$site_check_port" \
  --bind 127.0.0.1 \
  --directory "$site_root" \
  >"$site_check_tmp/server.log" 2>&1 &
site_check_pid=$!

attempt=0
while ! curl --silent --fail "http://127.0.0.1:$site_check_port/" >/dev/null; do
  if ! kill -0 "$site_check_pid" 2>/dev/null; then
    sed -n '1,120p' "$site_check_tmp/server.log"
    exit 1
  fi
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 50 ]; then
    sed -n '1,120p' "$site_check_tmp/server.log"
    exit 1
  fi
  sleep 0.1
done

fetch() {
  route=$1
  output=$2
  curl --silent --show-error --fail \
    "http://127.0.0.1:$site_check_port$route" \
    >"$output"
}

fetch "/" "$site_check_tmp/home.html"
fetch "/number-sniper/" "$site_check_tmp/marketing.html"
fetch "/number-sniper/support/" "$site_check_tmp/support.html"
fetch "/number-sniper/privacy/" "$site_check_tmp/privacy.html"
fetch "/app-ads.txt" "$site_check_tmp/app-ads.txt"

rg --quiet 'href="/number-sniper/"' "$site_check_tmp/home.html"
rg --quiet 'href="https://takaponz\.github\.io/omikuji-qr-legal/"' \
  "$site_check_tmp/home.html"
rg --quiet 'href="/number-sniper/support/"' "$site_check_tmp/marketing.html"
rg --quiet 'href="/number-sniper/privacy/"' "$site_check_tmp/marketing.html"
rg --quiet 'mailto:takaponz\.support@gmail\.com' "$site_check_tmp/support.html"
rg --quiet 'href="/number-sniper/support/"' "$site_check_tmp/privacy.html"
rg --quiet '^google\.com, pub-8138408268580214, DIRECT, f08c47fec0942fa0$' \
  "$site_check_tmp/app-ads.txt"

if rg --quiet 'noindex|nofollow' \
  "$site_check_tmp/home.html" "$site_check_tmp/marketing.html" \
  "$site_check_tmp/support.html" "$site_check_tmp/privacy.html"; then
  echo "Public pages must remain indexable" >&2
  exit 1
fi

for page in \
  "$site_check_tmp/home.html" \
  "$site_check_tmp/marketing.html" \
  "$site_check_tmp/support.html" \
  "$site_check_tmp/privacy.html"; do
  rg --quiet '<html lang="ja">' "$page"
  rg --quiet '<main' "$page"
  rg --quiet '<h1' "$page"
done

echo "site checks passed"
