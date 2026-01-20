#!/bin/bash
# audio-recorder - Configuration module
# shellcheck disable=SC2034  # Variables used by other sourced modules

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────

CONFIG_DIR="$HOME/.config/audio-recorder"
CONFIG_FILE="$CONFIG_DIR/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OS="$(uname -s)"
RECORDINGS_DIR="$HOME/Recordings"
PID_FILE="/tmp/audio-recorder.pid"
START_TIME_FILE="/tmp/audio-recorder-start"
FOLDER_FILE="/tmp/audio-recorder-folder"
NAME_FILE="/tmp/audio-recorder-name"

# Load config
load_config() {
    # shellcheck source=/dev/null
    [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
    mkdir -p "$RECORDINGS_DIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# Setup
# ─────────────────────────────────────────────────────────────────────────────

setup() {
    mkdir -p "$CONFIG_DIR"

    echo -e "${BOLD}audio-recorder setup${NC}"
    echo "────────────────────"
    echo ""

    # HF Token
    local current_token="${HF_TOKEN:-(not set)}"
    [ ${#current_token} -gt 20 ] && current_token="${current_token:0:10}...${current_token: -4}"
    read -rp "HuggingFace Token [$current_token]: " new_token
    [ -n "$new_token" ] && HF_TOKEN="$new_token"

    # Recordings directory
    read -rp "Recordings directory [$RECORDINGS_DIR]: " new_dir
    [ -n "$new_dir" ] && RECORDINGS_DIR="${new_dir/#\~/$HOME}"

    # Save
    cat > "$CONFIG_FILE" << EOF
HF_TOKEN="$HF_TOKEN"
RECORDINGS_DIR="$RECORDINGS_DIR"
EOF
    chmod 600 "$CONFIG_FILE"
    mkdir -p "$RECORDINGS_DIR"

    echo ""
    success "Config saved to $CONFIG_FILE"
}
