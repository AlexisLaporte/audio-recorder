#!/bin/bash
# audio-recorder - Summarize module
# shellcheck disable=SC2012  # ls used intentionally for sorting by time

# ─────────────────────────────────────────────────────────────────────────────
# Summarize
# ─────────────────────────────────────────────────────────────────────────────

cmd_summarize() {
    local folder="$1"

    # Default to latest recording
    if [ -z "$folder" ]; then
        folder=$(find "$RECORDINGS_DIR" -maxdepth 1 -type d -name "*recording*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    fi
    [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"

    local transcript="$folder/transcript.txt"
    if [ ! -f "$transcript" ]; then
        error "No transcript: $transcript"
        return 1
    fi

    local summary="$folder/summary.md"

    # Step 1: Generate minutes
    info "Generating minutes with Claude..."

    local prompt_file="$LIB_DIR/prompt_minutes.md"
    local system_prompt
    system_prompt=$(cat "$prompt_file")

    CLAUDECODE= claude -p --system-prompt "$system_prompt" "Voici la transcription :

$(cat "$transcript")" > "$summary" 2>/dev/null
    if [ ! -s "$summary" ]; then
        error "Claude failed to generate summary"
        rm -f "$summary"
        return 1
    fi
    success "Summary: $summary"

    # Step 2: Rename folder
    info "Generating folder name..."

    local date_prefix
    date_prefix=$(basename "$folder" | grep -oP '\d{8}')

    local new_name
    new_name=$(CLAUDECODE= claude -p "À partir de ce résumé, propose UN nom de dossier court et descriptif en snake_case (max 40 chars, sans date). Réponds UNIQUEMENT le nom, rien d'autre.

$(cat "$summary")" 2>/dev/null | tr -d '[:space:]')

    if [ -n "$new_name" ] && [ -n "$date_prefix" ]; then
        local new_folder="$RECORDINGS_DIR/${date_prefix}_${new_name}"
        if [ ! -d "$new_folder" ] && [ "$folder" != "$new_folder" ]; then
            mv "$folder" "$new_folder"
            success "Renamed: $(basename "$new_folder")"
        fi
    fi
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
        folder=$(find "$RECORDINGS_DIR" -maxdepth 1 -type d -name "recording_*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
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
