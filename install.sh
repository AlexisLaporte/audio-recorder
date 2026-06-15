#!/bin/bash
# audio-recorder installer
#
# Modes:
#   ./install.sh            Install (copy payload to a stable location, then link a launcher).
#                           Survives moving/deleting this checkout. Default — use for end users.
#   ./install.sh --link     Dev install: symlink the launcher to THIS checkout (edits go live).
#   ./install.sh --uninstall  Remove launcher, completion, skill and the installed payload.
#                             Keeps your config (~/.config/audio-recorder) and recordings.
#   -y, --yes               Assume "yes" to prompts (deps, Claude skill). For non-interactive installs.

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
LIBEXEC_DIR="$HOME/.local/share/audio-recorder"
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"
SKILL_DIR="$HOME/.claude/skills"
SKILL_FILE="$SKILL_DIR/audio-recorder.md"
RECORDINGS_DIR="$HOME/Recordings"

OS="$(uname -s)"

MODE="copy"        # copy | link
DO_UNINSTALL=0
ASSUME_YES=0

# Payload that makes up a working install (relative to REPO_DIR).
PAYLOAD=(audio-recorder lib audio-recorder.bash-completion claude-skill.md summarize-prompt.default.md)

usage() {
    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

# ─────────────────────────────────────────────────────────────────────────────
# Args
# ─────────────────────────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
    case "$1" in
        --link)      MODE="link" ;;
        --copy)      MODE="copy" ;;
        --uninstall) DO_UNINSTALL=1 ;;
        -y|--yes)    ASSUME_YES=1 ;;
        -h|--help)   usage; exit 0 ;;
        *)           echo "Unknown option: $1"; echo; usage; exit 1 ;;
    esac
    shift
done

confirm() {
    # confirm "prompt"  -> 0 if yes. Defaults to yes. Honors --yes / non-tty.
    [ "$ASSUME_YES" = 1 ] && return 0
    [ -t 0 ] || return 0
    local reply
    read -rp "$1 [Y/n] " reply
    [[ ! "$reply" =~ ^[Nn] ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────────────────────

if [ "$DO_UNINSTALL" = 1 ]; then
    echo "=== audio-recorder uninstall ==="
    rm -f "$BIN_DIR/audio-recorder"
    rm -f "$COMPLETION_DIR/audio-recorder"
    [ -L "$SKILL_FILE" ] && rm -f "$SKILL_FILE"
    rm -rf "$LIBEXEC_DIR"
    echo "[OK] Removed launcher, completion, skill and $LIBEXEC_DIR"
    echo "[KEPT] Config (~/.config/audio-recorder) and recordings ($RECORDINGS_DIR)"
    exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Install
# ─────────────────────────────────────────────────────────────────────────────

echo "=== audio-recorder installer (mode: $MODE) ==="
echo ""

mkdir -p "$BIN_DIR" "$COMPLETION_DIR"

if [ "$MODE" = "copy" ]; then
    # Copy the payload to a stable location so the install survives this
    # checkout being moved or deleted (and so the release tarball flow works).
    rm -rf "$LIBEXEC_DIR"
    mkdir -p "$LIBEXEC_DIR"
    for item in "${PAYLOAD[@]}"; do
        [ -e "$REPO_DIR/$item" ] && cp -R "$REPO_DIR/$item" "$LIBEXEC_DIR/"
    done
    SRC="$LIBEXEC_DIR"
    echo "[OK] Payload copied to $LIBEXEC_DIR"
else
    SRC="$REPO_DIR"
    echo "[OK] Linking to checkout $REPO_DIR (edits go live)"
fi

# Launcher resolves its real path (readlink -f) to find lib/, so a symlink is fine in both modes.
ln -sf "$SRC/audio-recorder" "$BIN_DIR/audio-recorder"
echo "[OK] Launcher: $BIN_DIR/audio-recorder -> $SRC/audio-recorder"

ln -sf "$SRC/audio-recorder.bash-completion" "$COMPLETION_DIR/audio-recorder"
echo "[OK] Bash completion installed"

# Default prompt template (data, never overwritten if customized)
mkdir -p "$RECORDINGS_DIR"
if [ ! -f "$RECORDINGS_DIR/summarize-prompt.md" ] && [ -f "$SRC/summarize-prompt.default.md" ]; then
    cp "$SRC/summarize-prompt.default.md" "$RECORDINGS_DIR/summarize-prompt.md"
    echo "[OK] Prompt template copied to $RECORDINGS_DIR/"
fi

# PATH check
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "[WARN] $BIN_DIR is not in your PATH. Add to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ─────────────────────────────────────────────────────────────────────────────
# Dependencies
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "=== Checking dependencies ==="

install_deps() {
    confirm "Install missing dependencies?" || return

    case "$OS" in
        Darwin) echo "Installing ffmpeg..."; brew install ffmpeg || true ;;
        *)      echo "Installing ffmpeg..."; sudo apt install -y ffmpeg || true ;;
    esac

    # WhisperX via uv on a pinned Python — its deps cap at Python <3.13, so we
    # can't rely on the system Python on recent distros (e.g. Ubuntu 26.04).
    if ! command -v whisperx &>/dev/null; then
        echo "Installing whisperx..."
        if ! command -v uv &>/dev/null; then
            echo "Installing uv (Python toolchain manager)..."
            curl -LsSf https://astral.sh/uv/install.sh | sh
            export PATH="$HOME/.local/bin:$PATH"
        fi
        if command -v uv &>/dev/null; then
            uv tool install whisperx --python 3.12
        else
            echo "[ERROR] uv install failed. Install whisperx manually:"
            echo "  curl -LsSf https://astral.sh/uv/install.sh | sh"
            echo "  uv tool install whisperx --python 3.12"
        fi
    fi
}

MISSING=0
if command -v ffmpeg &>/dev/null; then echo "[OK] ffmpeg"; else echo "[MISSING] ffmpeg"; MISSING=1; fi
if command -v whisperx &>/dev/null; then echo "[OK] whisperx"; else echo "[MISSING] whisperx"; MISSING=1; fi
if command -v claude &>/dev/null; then echo "[OK] claude (for summarize)"; else echo "[OPTIONAL] claude CLI not found (needed for summarize command)"; fi

[ $MISSING -eq 1 ] && install_deps

if [ "$OS" = "Darwin" ]; then
    echo ""
    echo "=== macOS note ==="
    echo "For system audio capture, install BlackHole:"
    echo "  brew install blackhole-2ch"
    echo "Then set up a Multi-Output Device in Audio MIDI Setup."
fi

# ─────────────────────────────────────────────────────────────────────────────
# Claude Code skill
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "=== Claude Code skill ==="
if [ -d "$HOME/.claude" ]; then
    if [ -L "$SKILL_FILE" ] || [ -f "$SKILL_FILE" ]; then
        echo "[OK] Claude skill already installed"
    elif confirm "Install Claude Code skill? (lets Claude use audio-recorder)"; then
        mkdir -p "$SKILL_DIR"
        ln -sf "$SRC/claude-skill.md" "$SKILL_FILE"
        echo "[OK] Claude skill installed to $SKILL_FILE"
    fi
else
    echo "[SKIP] ~/.claude not found (Claude Code not installed)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Done
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "=== Setup ==="
echo "Run 'audio-recorder setup' to configure your HuggingFace token."
echo ""
echo "WhisperX requires accepting conditions at:"
echo "  - https://hf.co/pyannote/speaker-diarization-3.1"
echo "  - https://hf.co/pyannote/segmentation-3.0"
echo ""
echo "Done!"
