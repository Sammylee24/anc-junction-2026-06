#!/bin/bash
# autosave.sh - auto-saves running configs every 5 minutes
# Runs write memory on all Cisco IOL devices so progress survives a container restart.
# JUN-R1 (Juniper) persists config automatically on commit - no action needed.
#
# Usage:
#   bash autosave.sh          # run in foreground (Ctrl+C to stop)
#   bash autosave.sh &        # run in background
#   kill $(cat .autosave.pid) # stop background instance

SAVE_INTERVAL=300   # 5 minutes

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
GREY='\033[0;90m'
NC='\033[0m'

log()  { echo -e "${GREEN}[autosave]${NC} $(date '+%H:%M:%S') $*"; }
warn() { echo -e "${YELLOW}[autosave]${NC} $(date '+%H:%M:%S') $*"; }
dim()  { echo -e "${GREY}[autosave]${NC} $(date '+%H:%M:%S') $*"; }

declare -A DEVICES=(
    [ISP-R]="172.31.34.11"
    [CORE-R1]="172.31.34.13"
    [BR-R1]="172.31.34.14"
    [BR-R2]="172.31.34.15"
    [DIST-SW]="172.31.34.21"
    [ACC-SW1]="172.31.34.22"
)

# Write PID file so caller can stop us cleanly
echo $$ > .autosave.pid

write_mem() {
    local name=$1 ip=$2
    local result
    result=$(printf 'write memory\nexit\n' | \
        sshpass -p admin ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -o BatchMode=no -tt admin@"$ip" 2>/dev/null | \
        grep -i "ok\|success\|Building\|\[OK\]" | head -1)

    if [ -n "$result" ]; then
        dim "  $name ($ip) - saved"
        return 0
    else
        warn "  $name ($ip) - unreachable or not ready (skipped)"
        return 1
    fi
}

save_all() {
    local saved=0 failed=0
    log "Saving configs..."
    for name in "${!DEVICES[@]}"; do
        if write_mem "$name" "${DEVICES[$name]}"; then
            saved=$((saved + 1))
        else
            failed=$((failed + 1))
        fi
    done
    log "Done - ${saved} saved, ${failed} skipped"
    echo ""
}

trap 'echo ""; log "Stopped. Removing PID file."; rm -f .autosave.pid; exit 0' INT TERM

echo ""
echo -e "${BOLD}  ANC Autosave - Junction June 2026${NC}"
echo -e "  Saving all Cisco IOL devices every $((SAVE_INTERVAL / 60)) minutes."
echo -e "  JUN-R1 persists automatically on commit."
echo -e "  Stop with: Ctrl+C  or  kill \$(cat .autosave.pid)"
echo ""

# First save immediately on start
save_all

# Then loop every 5 minutes
while true; do
    sleep "$SAVE_INTERVAL"
    save_all
done
