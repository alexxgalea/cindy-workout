#!/usr/bin/env bash
#
# Copies the freshly built debug APK to the directory the phone installs from.
#
# `./gradlew assembleDebug` writes app/build/outputs/apk/debug/app-debug.apk and nothing carries
# it to the little http.server the phone downloads from, so the phone silently keeps installing
# an old build. On 2026-09-10 that cost a whole debugging round: the served APK was four hours
# stale and predated the feature being looked for, so a missing deploy looked like a missing
# feature. This exists so that step cannot be forgotten again.
#
# The serve directory is read from the running server's own working directory rather than
# hard-coded, because it lives in a session scratchpad under /private/tmp that a reboot can take
# away. Set CINDY_SERVE_DIR to override, CINDY_SERVE_PORT for a port other than 8765.
#
# Silent when there is nothing to do — no build, no server, or the served bytes already match —
# so it is safe to run after every build. Never fails a build: it only reports.

set -uo pipefail

PORT="${CINDY_SERVE_PORT:-8765}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"

sha_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

[ -f "$APK" ] || exit 0

# Ask the listener where it is serving from, so a moved scratchpad fixes itself.
find_serve_dir() {
  if [ -n "${CINDY_SERVE_DIR:-}" ]; then printf '%s' "$CINDY_SERVE_DIR"; return 0; fi
  local pid
  pid="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -Fp 2>/dev/null | head -1 | sed 's/^p//')"
  [ -n "$pid" ] || return 1
  lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep '^n' | head -1 | sed 's/^n//'
}

SERVE="$(find_serve_dir)" || { echo "APK not deployed: nothing is listening on port $PORT."; exit 0; }
[ -n "$SERVE" ] && [ -d "$SERVE" ] || { echo "APK not deployed: serve directory '$SERVE' is gone."; exit 0; }

SERVED="$SERVE/cindy-tracker.apk"
APK_SHA="$(sha_of "$APK")"

# Already there. The common case after a no-op build, and worth staying quiet about.
[ -f "$SERVED" ] && [ "$(sha_of "$SERVED")" = "$APK_SHA" ] && exit 0

cp "$APK" "$SERVED" || { echo "APK not deployed: copy to $SERVE failed."; exit 0; }

# The bytes that landed, not the bytes that were sent. A short copy is the failure this catches.
COPIED_SHA="$(sha_of "$SERVED")"
if [ "$COPIED_SHA" != "$APK_SHA" ]; then
  echo "APK deploy FAILED: served copy does not match the build ($COPIED_SHA vs $APK_SHA)."
  exit 0
fi

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BUILT="$(date '+%Y-%m-%d %H:%M')"

# The commit is stamped from HEAD, but the APK is whatever last got built. Those agree when this
# runs straight after a build and can disagree badly when run by hand, which would put a fresh
# commit's name on an old binary — the exact lie this script exists to prevent, relocated.
STALE=""
APK_MTIME="$(stat -f %m "$APK" 2>/dev/null || echo 0)"
HEAD_TIME="$(git -C "$ROOT" log -1 --format=%ct 2>/dev/null || echo 0)"
[ "$APK_MTIME" -lt "$HEAD_TIME" ] && STALE="  ·  WARNING: this APK was built before $COMMIT — rebuild"
INDEX="$SERVE/index.html"
if [ -f "$INDEX" ]; then
  # The page prints these so a stale download is visible on the phone instead of being guessed at.
  sed -i '' -E \
    -e "s|<dt>built</dt><dd>[^<]*</dd>|<dt>built</dt><dd>$BUILT</dd>|" \
    -e "s|<dt>commit</dt><dd>[^<]*</dd>|<dt>commit</dt><dd>$COMMIT</dd>|" \
    -e "s|<dt>sha256</dt><dd>[^<]*</dd>|<dt>sha256</dt><dd>${APK_SHA:0:12}…</dd>|" \
    "$INDEX" 2>/dev/null
fi

# The address is not stable — this Mac has moved networks mid-project, and the old address timed
# out while 127.0.0.1 answered fine, which looks like a wedged server and is not one. So read the
# address now and confirm the server actually answers on it. A HEAD, not the whole 23MB.
IP="$(ipconfig getifaddr en0 2>/dev/null || echo 127.0.0.1)"
if curl -fsI --max-time 5 "http://$IP:$PORT/cindy-tracker.apk" >/dev/null 2>&1; then
  echo "APK deployed to http://$IP:$PORT  ·  $COMMIT  ·  ${APK_SHA:0:12}…$STALE"
else
  echo "APK copied ($COMMIT, ${APK_SHA:0:12}…) but http://$IP:$PORT did not answer — check the server.$STALE"
fi
