#!/bin/sh
# Deplexo worker: run the v0-line nezha agent (panel nezhak2 = v0.17.9).
# Config comes from env (set in the Deplexo dashboard, never committed).
#
# Pitfalls baked in (learned 2026-10-15 on Deplexo):
#  * ${VAR:?msg} — a failed expansion exits 2, which the platform reports as "app
#    exited during startup with exit code 2", indistinguishable from a crash.
#    Default + log instead.
#  * /tmp is mounted NOEXEC here: chmod +x succeeds but running the binary gives
#    "Permission denied" / rc=126 on every spawn. Probe for a dir that is both
#    writable and executable before installing the binary.
set -u
log() { echo "[start $(date -u +%H:%M:%S)] $*"; }

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ASSET=amd64 ;;
  aarch64|arm64) ASSET=arm64 ;;
  *) log "unsupported arch: $ARCH"; exec sleep 3600 ;;
esac

NEZHA_SERVER="${NEZHA_SERVER:-nezhak2.btpp.ggff.net}"
NEZHA_PORT="${NEZHA_PORT:-443}"
NEZHA_KEY="${NEZHA_KEY:-}"
NAME="${NAME:-deplexo}"
log "arch=$ARCH server=$NEZHA_SERVER:$NEZHA_PORT name=$NAME key_len=${#NEZHA_KEY}"

if [ -z "$NEZHA_KEY" ]; then
  log "NEZHA_KEY is empty — set it in Dashboard > Env vars. Idling."
  exec sleep 3600
fi

# pick a workdir that is writable AND executable (/tmp is noexec on Deplexo)
DIR=""
for d in "$HOME" /home /root /app /srv /var/tmp /opt /usr/local/bin /tmp; do
  [ -n "$d" ] || continue
  mkdir -p "$d" 2>/dev/null || continue
  probe="$d/.dx_probe.$$"
  if printf '#!/bin/sh\necho ok\n' > "$probe" 2>/dev/null && chmod +x "$probe" 2>/dev/null && "$probe" >/dev/null 2>&1; then
    DIR="$d"; rm -f "$probe"; break
  fi
  rm -f "$probe" 2>/dev/null
done
[ -n "$DIR" ] || { log "no writable+executable dir found"; exec sleep 3600; }
log "workdir=$DIR"

BIN="$DIR/nezha-agent"
PINNED="$DIR/nezha-agent.pinned"

fetch() {
  rm -rf "$DIR/a.zip" "$DIR/x"
  curl -fsSL --retry 3 --max-time 120 \
    "https://github.com/nezhahq/agent/releases/download/v0.20.5/nezha-agent_linux_${ASSET}.zip" \
    -o "$DIR/a.zip" || { log "curl failed rc=$?"; return 1; }
  unzip -o -q "$DIR/a.zip" -d "$DIR/x" || { log "unzip failed rc=$?"; return 1; }
  f=$(find "$DIR/x" -type f -name 'nezha-agent*' | head -1)
  [ -n "$f" ] || { log "no binary in zip"; return 1; }
  cp "$f" "$PINNED" && chmod 755 "$PINNED" && log "pinned $f ($(wc -c < "$PINNED") bytes)" && return 0
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
  cp "$PINNED" "$BIN"; chmod 755 "$BIN"
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
