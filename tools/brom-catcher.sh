#!/bin/bash
# BROM catcher for Samsung MTK partition writes via mtkclient.
#
# Loops forever: run an mtkclient script, wait for a BROM window to get caught, then decide
# success from the read-back, not from the log. Things that bit me and are handled here:
#   - flock single-writer:   two USB writers racing one phone is how you get garbage
#   - per-attempt logs:      each attempt gets its own dir under logs/
#   - disk preflight:        the read-back of super is ~10 GB, make sure it fits
#   - sha256 gate:           a grep on the log is not proof the write committed, the hash is
#   - per-attempt timeout:   a wedged DA session can't hang the loop
#
# Set these for your device and firmware. The defaults are my A14 5G (SM-A146U) values and
# yours will differ. EXPECTED especially: compute it from YOUR raw image
# (`sha256sum super_raw.img`). Pasting someone else's hash makes every write look failed.
# For read-only scripts set EXPECTED=none to skip the hash gate.
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"      # repo root, mounted as /a in the container
MTKCLIENT="${MTKCLIENT:-$REPO/mtkclient}"              # your patched mtkclient clone
IMAGE="${IMAGE:-mtkenv}"                               # docker image with mtkclient's deps
SCRIPT="${SCRIPT:-scripts/fix_super2.txt}"             # mtkclient script, relative to REPO
VERIFY_OUT="${VERIFY_OUT:-verify/super2.vfy}"          # read-back output, relative to REPO (must match SCRIPT)
EXPECTED="${EXPECTED:-PUT_YOUR_RAW_SUPER_SHA256_HERE}" # sha256 of your raw image, or "none"
VERIFY_BYTES="${VERIFY_BYTES:-10276044800}"            # read-back size in bytes, for the disk preflight
TIMEOUT="${TIMEOUT:-7200}"                             # seconds per attempt

LOG="$REPO/logs/catcher.log"
mkdir -p "$REPO/logs" "$REPO/$(dirname "$VERIFY_OUT")"
log() { echo "$*" | tee -a "$LOG"; }

exec 9>/var/lock/mtk-usb.lock
flock -n 9 || { log "another USB writer holds the lock, exiting"; exit 3; }

if [ "$EXPECTED" = "PUT_YOUR_RAW_SUPER_SHA256_HERE" ]; then
  log "EXPECTED is unset. Export EXPECTED=<sha256 of your raw image> (or EXPECTED=none for a read-only script). Aborting."
  exit 2
fi
[ -f "$MTKCLIENT/mtk.py" ] || { log "no mtk.py in $MTKCLIENT, set MTKCLIENT"; exit 2; }
[ -f "$REPO/$SCRIPT" ]     || { log "script $REPO/$SCRIPT not found"; exit 2; }

FREE=$(df -B1 --output=avail "$REPO" | tail -1)
if [ "$FREE" -lt $((VERIFY_BYTES + 2*1024*1024*1024)) ]; then
  log "PREFLIGHT FAIL: need $((VERIFY_BYTES/1024/1024))MiB+2GiB, have $((FREE/1024/1024))MiB"
  exit 4
fi

rm -f "$REPO/$VERIFY_OUT"
n=0
while true; do
  n=$((n+1))
  RUN="$REPO/logs/run-$(date +%s%N)"
  mkdir -p "$RUN"
  log "=== attempt $n -> $RUN $(date) ==="
  timeout "$TIMEOUT" docker run --rm --privileged --net=host -e PYTHONUNBUFFERED=1 \
    -v /dev/bus/usb:/dev/bus/usb -v /run/udev:/run/udev:ro \
    -v "$REPO:/a" -v "$MTKCLIENT:/opt/mtkclient" \
    "$IMAGE" sh -c "cd /opt/mtkclient && python3 -u mtk.py --skipwdt script /a/$SCRIPT" \
    > "$RUN/attempt.log" 2>&1
  tail -3 "$RUN/attempt.log" >> "$LOG"

  # success gate: read-back file written, reset sent, and (unless EXPECTED=none) hash matches
  if grep -q "as /a/$VERIFY_OUT" "$RUN/attempt.log" && grep -q "Reset command was sent" "$RUN/attempt.log"; then
    if [ "$EXPECTED" = "none" ]; then
      log "=== attempt $n completed (no hash gate, read-only script) $(date) ==="
      exit 0
    fi
    GOT=$(sha256sum "$REPO/$VERIFY_OUT" 2>/dev/null | awk '{print $1}')
    if [ "$GOT" = "$EXPECTED" ]; then
      log "=== VERIFIED SUCCESS attempt $n $(date) hash=$GOT ==="
      exit 0
    fi
    log "!!! HASH MISMATCH attempt $n got=$GOT expected=$EXPECTED, stopping"
    exit 5
  fi
  log "--- attempt $n incomplete (no catch or aborted) ---"
  sleep 10
done
