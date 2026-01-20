#!/bin/bash
# audio-recorder - Utilities module
# shellcheck disable=SC2034  # Variables used by other sourced modules

# ─────────────────────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────────────────────

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' NC=''
fi

# ─────────────────────────────────────────────────────────────────────────────
# Output helpers
# ─────────────────────────────────────────────────────────────────────────────

info()    { echo -e "${BLUE}▸${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
error()   { echo -e "${RED}✗${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}!${NC} $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

spinner() {
    local pid="$1"
    local msg="$2"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BLUE}${chars:$i:1}${NC} %s" "$msg"
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done
    printf "\r"
}

format_duration() {
    local seconds="$1"
    if [ "$seconds" -lt 60 ]; then
        echo "${seconds}s"
    elif [ "$seconds" -lt 3600 ]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    fi
}

notify() {
    local title="$1"
    local msg="$2"
    case "$OS" in
        Darwin) osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null ;;
        *)      notify-send "$title" "$msg" -i audio-input-microphone 2>/dev/null ;;
    esac
}
