#!/bin/bash
# audio-recorder installer

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/.local/bin"
COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"

OS="$(uname -s)"

echo "=== audio-recorder installer ==="
echo ""

# Create directories
mkdir -p "$BIN_DIR"
mkdir -p "$COMPLETION_DIR"

# Symlink binary
ln -sf "$REPO_DIR/audio-recorder" "$BIN_DIR/audio-recorder"
echo "[OK] Installed to $BIN_DIR/audio-recorder"

# Install bash completion
ln -sf "$REPO_DIR/audio-recorder.bash-completion" "$COMPLETION_DIR/audio-recorder"
echo "[OK] Bash completion installed"

# Copy default prompt template to Recordings
RECORDINGS_DIR="$HOME/Recordings"
mkdir -p "$RECORDINGS_DIR"
if [ ! -f "$RECORDINGS_DIR/summarize-prompt.md" ]; then
    cp "$REPO_DIR/summarize-prompt.default.md" "$RECORDINGS_DIR/summarize-prompt.md" 2>/dev/null || true
    [ -f "$RECORDINGS_DIR/summarize-prompt.md" ] && echo "[OK] Prompt template copied to $RECORDINGS_DIR/"
fi

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "[WARN] $BIN_DIR is not in your PATH"
    echo "Add this to your ~/.bashrc or ~/.zshrc:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "=== Checking dependencies ==="

install_deps() {
    echo ""
    read -p "Install missing dependencies? [Y/n] " confirm
    [[ "$confirm" =~ ^[Nn] ]] && return

    case "$OS" in
        Darwin)
            echo "Installing ffmpeg..."
            brew install ffmpeg || true
            ;;
        *)
            echo "Installing ffmpeg..."
            sudo apt install -y ffmpeg || true
            ;;
    esac

    # WhisperX
    if ! command -v whisperx &>/dev/null; then
        echo "Installing whisperx..."
        if command -v pipx &>/dev/null; then
            pipx install whisperx
        elif command -v pip &>/dev/null; then
            pip install --user whisperx
        else
            echo "[ERROR] Neither pipx nor pip found. Install whisperx manually."
        fi
    fi
}

MISSING=0

if command -v ffmpeg &>/dev/null; then
    echo "[OK] ffmpeg"
else
    echo "[MISSING] ffmpeg"
    MISSING=1
fi

if command -v whisperx &>/dev/null; then
    echo "[OK] whisperx"
else
    echo "[MISSING] whisperx"
    MISSING=1
fi

if command -v claude &>/dev/null; then
    echo "[OK] claude (for summarize)"
else
    echo "[OPTIONAL] claude CLI not found (needed for summarize command)"
fi

[ $MISSING -eq 1 ] && install_deps

# macOS: check for BlackHole
if [ "$OS" = "Darwin" ]; then
    echo ""
    echo "=== macOS note ==="
    echo "For system audio capture, install BlackHole:"
    echo "  brew install blackhole-2ch"
    echo "Then set up a Multi-Output Device in Audio MIDI Setup."
fi

# Claude skill
echo ""
echo "=== Claude Code skill ==="
SKILL_DIR="$HOME/.claude/skills"
SKILL_FILE="$SKILL_DIR/audio-recorder.md"

if [ -d "$HOME/.claude" ]; then
    if [ -f "$SKILL_FILE" ]; then
        echo "[OK] Claude skill already installed"
    else
        read -p "Install Claude Code skill? (lets Claude use audio-recorder) [Y/n] " confirm
        if [[ ! "$confirm" =~ ^[Nn] ]]; then
            mkdir -p "$SKILL_DIR"
            ln -sf "$REPO_DIR/claude-skill.md" "$SKILL_FILE"
            echo "[OK] Claude skill installed to $SKILL_FILE"
        fi
    fi
else
    echo "[SKIP] ~/.claude not found (Claude Code not installed)"
fi

echo ""
echo "=== Setup ==="
echo "Run 'audio-recorder setup' to configure your HuggingFace token."
echo ""
echo "WhisperX requires accepting conditions at:"
echo "  - https://hf.co/pyannote/speaker-diarization-3.1"
echo "  - https://hf.co/pyannote/segmentation-3.0"
echo ""
echo "Done!"
