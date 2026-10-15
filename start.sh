#!/bin/sh
# Deplexo worker: run the v0-line nezha agent (panel nezhak2 = v0.17.9).
# Config comes from env (set in the Deplexo dashboard, never committed).
#
# ⚠️ Never use ${VAR:?msg} here: on busybox/ash a failed parameter expansion exits
# with status 2, which the platform reports as "app exited during startup with exit
# code 2" — indistinguishable from a real crash. Fall back to defaults and log.
set -u
log() { echo "[start $(date -u +%H:%M:%S)] $*"; }

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ASSET=amd64 ;;
  aarch64|arm64) ASSET=arm64 ;;
  *) log "unsupported arch: $ARCH"; exec sleep 3600 ;;
esac

BIN=/tmp/nezha-agent
PINNED=/tmp/nezha-agent.pinned

NEZHA_SERVER="${NEZHA_SERVER:-nezhak2.btpp.ggff.net}"
NEZHA_PORT="${NEZHA_PORT:-443}"
NEZHA_KEY="${NEZHA_KEY:-}"
NAME="${NAME:-deplexo}"
log "arch=$ARCH server=$NEZHA_SERVER:$NEZHA_PORT name=$NAME key_len=${#NEZHA_KEY}"

if [ -z "$NEZHA_KEY" ]; then
  log "NEZHA_KEY is empty — set it in Dashboard > Env vars. Idling."
  exec sleep 3600
fi

fetch() {
  rm -rf /tmp/a.zip /tmp/x
  curl -fsSL --retry 3 --max-time 120 \
    "https://github.com/nezhahq/agent/releases/download/v0.20.5/nezha-agent_linux_${ASSET}.zip" \
    -o /tmp/a.zip || { log "curl failed rc=$?"; return 1; }
  unzip -o -q /tmp/a.zip -d /tmp/x || { log "unzip failed rc=$?"; return 1; }
  f=$(find /tmp/x -type f -name 'nezha-agent*' | head -1)
  [ -n "$f" ] || { log "no binary in zip"; return 1; }
  cp "$f" "$PINNED" && chmod +x "$PINNED" && log "pinned $f ($(wc -c < "$PINNED") bytes)" && return 0
}

n=0
while [ $n -lt 5 ]; do
  n=$((n+1))
  fetch && break
  sleep 5
done
[ -f "$PINNED" ] || { log "could not fetch agent; idling"; exec sleep 3600; }

i=0
while [ $i -lt 10 ]; do
  i=$((i+1))
  cp "$PINNED" "$BIN"; chmod +x "$BIN"
  log "spawn #$i"
  "$BIN" -s "$NEZHA_SERVER:$NEZHA_PORT" -p "$NEZHA_KEY" --tls \
    --report-delay 3 --skip-procs --skip-conn \
    --disable-send-query --disable-nat \
    --disable-auto-update --disable-force-update 2>&1
  log "agent exited rc=$? (spawn #$i)"
  sleep 5
done
log "giving up after $i spawns; idling"
exec sleep 3600
