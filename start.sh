#!/bin/sh
# Deplexo worker: run the v0-line nezha agent (panel nezhak2 = v0.17.9).
# All config comes from env (set in the Deplexo dashboard, never committed).
set -u

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ASSET=amd64 ;;
  aarch64|arm64) ASSET=arm64 ;;
  *) echo "unsupported arch: $ARCH"; exec sleep 3600 ;;
esac

BIN=/tmp/nezha-agent
PINNED=/tmp/nezha-agent.pinned

: "${NEZHA_SERVER:?set NEZHA_SERVER}"
: "${NEZHA_PORT:=443}"
: "${NEZHA_KEY:?set NEZHA_KEY}"
: "${NAME:=deplexo}"

fetch() {
  rm -f /tmp/a.zip
  curl -fsSL --retry 3 --max-time 120 \
    "https://github.com/nezhahq/agent/releases/download/v0.20.5/nezha-agent_linux_${ASSET}.zip" \
    -o /tmp/a.zip || return 1
  unzip -o -q /tmp/a.zip -d /tmp/x || return 1
  f=$(find /tmp/x -type f -name 'nezha-agent*' | head -1)
  [ -n "$f" ] || return 1
  cp "$f" "$PINNED" && chmod +x "$PINNED" && return 0
}

n=0
while [ $n -lt 5 ]; do
  n=$((n+1))
  echo "[start] fetch attempt $n"
  fetch && break
  sleep 5
done
[ -f "$PINNED" ] || { echo "[start] could not fetch agent"; exec sleep 3600; }

# Supervisor: re-copy the pinned binary each spawn (force-update can overwrite it),
# respawn up to 10 times so a crash is visible in the platform log.
i=0
while [ $i -lt 10 ]; do
  i=$((i+1))
  cp "$PINNED" "$BIN"; chmod +x "$BIN"
  echo "[start] spawn #$i $(date -u +%FT%TZ)"
  "$BIN" -s "$NEZHA_SERVER:$NEZHA_PORT" -p "$NEZHA_KEY" --tls \
    --report-delay 3 --skip-procs --skip-conn \
    --disable-send-query --disable-nat \
    --disable-auto-update --disable-force-update 2>&1
  echo "[start] agent exited rc=$? (#$i)"
  sleep 5
done
echo "[start] giving up after $i spawns; idling"
exec sleep 3600
