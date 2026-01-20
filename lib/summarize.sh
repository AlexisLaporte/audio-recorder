#!/bin/bash
# audio-recorder - Summarize module
# shellcheck disable=SC2012  # ls used intentionally for sorting by time

# ─────────────────────────────────────────────────────────────────────────────
# Summarize
# ─────────────────────────────────────────────────────────────────────────────

cmd_summarize() {
    local folder=""
    local comment=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --comment|-c) comment="$2"; shift 2 ;;
            *) folder="$1"; shift ;;
        esac
    done

    # Default to latest recording
    if [ -z "$folder" ]; then
        folder=$(ls -td "$RECORDINGS_DIR"/* 2>/dev/null | head -1)
    fi
    [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"

    local transcript="$folder/transcript.txt"
    if [ ! -f "$transcript" ]; then
        error "No transcript: $transcript"
        return 1
    fi

    # Look for prompt template in recordings dir, then script dir
    local prompt_file="$RECORDINGS_DIR/summarize-prompt.md"
    [ ! -f "$prompt_file" ] && prompt_file="$SCRIPT_DIR/summarize-prompt.md"
    if [ ! -f "$prompt_file" ]; then
        error "Prompt template not found. Create $RECORDINGS_DIR/summarize-prompt.md"
        return 1
    fi

    info "Summarizing with Claude..."

    # Build prompt
    local prompt result new_name summary
    prompt=$(cat "$prompt_file")
    [ -n "$comment" ] && prompt="$prompt

## User Context
$comment"
    prompt="$prompt

---

## Transcript

$(cat "$transcript")"

    # Call Claude
    result=$(claude -p "$prompt" 2>&1)

    new_name=$(echo "$result" | grep "^FOLDER_NAME:" | tail -1 | sed 's/FOLDER_NAME: *//')
    summary=$(echo "$result" | sed '/^FOLDER_NAME:/,$d')

    if [ -z "$summary" ]; then
        error "Summarization failed"
        echo "$result"
        return 1
    fi

    echo "$summary" > "$folder/summary.md"
    success "Summary: $folder/summary.md"

    # Preview
    echo ""
    echo -e "${DIM}────────────────────────────────────────${NC}"
    head -15 "$folder/summary.md"
    echo -e "${DIM}...${NC}"
    echo -e "${DIM}────────────────────────────────────────${NC}"

    # Rename
    if [ -n "$new_name" ]; then
        echo ""
        info "Suggested name: ${BOLD}$new_name${NC}"
        read -rp "Rename folder? [Y/n] " confirm
        if [[ ! "$confirm" =~ ^[Nn] ]]; then
            local new_folder="$RECORDINGS_DIR/$new_name"
            if [ -d "$new_folder" ]; then
                error "Folder already exists: $new_name"
                return 1
            fi
            mv "$folder" "$new_folder"
            folder="$new_folder"
            success "Renamed to: $new_name"
        fi
    fi

    # Final summary
    echo ""
    echo -e "${GREEN}${BOLD}Done!${NC}"
    echo -e "  ${DIM}$folder${NC}"
    echo -e "  ├── audio.mp3"
    echo -e "  ├── transcript.txt"
    echo -e "  └── summary.md"

    notify "Processing complete" "$(basename "$folder")"
}

# ─────────────────────────────────────────────────────────────────────────────
# List & Open
# ─────────────────────────────────────────────────────────────────────────────

cmd_list() {
    echo -e "${BOLD}Recordings${NC} ${DIM}($RECORDINGS_DIR)${NC}"
    echo ""

    local count=0
    local name icon
    for dir in $(ls -td "$RECORDINGS_DIR"/* 2>/dev/null | head -15); do
        [ ! -d "$dir" ] && continue
        name=$(basename "$dir")
        icon="  "
        [ -f "$dir/transcript.txt" ] && icon="${YELLOW}📝${NC}"
        [ -f "$dir/summary.md" ] && icon="${GREEN}✓${NC} "
        echo -e "  $icon $name"
        ((count++))
    done

    if [ $count -eq 0 ]; then
        echo -e "  ${DIM}No recordings yet${NC}"
    else
        echo ""
        echo -e "  ${DIM}📝 transcribed  ✓ summarized${NC}"
    fi
}

cmd_open() {
    local folder="$1"

    if [ -z "$folder" ]; then
        folder=$(ls -td "$RECORDINGS_DIR"/* 2>/dev/null | head -1)
    fi
    [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"

    if [ ! -d "$folder" ]; then
        error "Folder not found: $folder"
        return 1
    fi

    case "$OS" in
        Darwin) open "$folder" ;;
        *)      xdg-open "$folder" 2>/dev/null || error "Could not open folder" ;;
    esac
}
