#!/bin/bash
# audio-recorder - Summarize module
# shellcheck disable=SC2012  # ls used intentionally for sorting by time

# ─────────────────────────────────────────────────────────────────────────────
# Summarize
# ─────────────────────────────────────────────────────────────────────────────

cmd_summarize() {
    local folder="$1"
    shift || true
    local comment=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --comment) comment="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Default to latest recording
    if [ -z "$folder" ]; then
        folder=$(latest_recording_dir)
    fi
    [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"

    local transcript="$folder/transcript.txt"
    if [ ! -f "$transcript" ]; then
        error "No transcript: $transcript"
        return 1
    fi

    local line_count
    line_count=$(wc -l < "$transcript")
    if [ "$line_count" -lt 2 ]; then
        error "Transcript too short ($line_count lines) — audio may be empty"
        return 1
    fi

    local summary="$folder/summary.md"

    # Step 1: Generate minutes
    info "Generating minutes with Claude..."

    local prompt_file="$LIB_DIR/prompt_minutes.md"
    local system_prompt
    system_prompt=$(cat "$prompt_file")

    local user_prompt
    user_prompt="Voici la transcription :

$(cat "$transcript")"
    [ -n "$comment" ] && user_prompt="$user_prompt

Contexte additionnel : $comment"

    # Use CLAUDE.md from current directory as project context
    local context_md=""
    local search_dir="$PWD"
    while [ "$search_dir" != "/" ]; do
        if [ -f "$search_dir/CLAUDE.md" ]; then
            context_md="$search_dir/CLAUDE.md"
            break
        fi
        search_dir=$(dirname "$search_dir")
    done
    if [ -n "$context_md" ]; then
        info "Project context: $context_md"
        user_prompt="$user_prompt

Contexte du projet (CLAUDE.md) :
$(cat "$context_md")"
    fi

    env CLAUDECODE= claude -p --system-prompt "$system_prompt" "$user_prompt" > "$summary" 2>/dev/null
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
    new_name=$(env CLAUDECODE= claude -p "À partir de ce résumé, propose UN nom de dossier court et descriptif en snake_case (max 40 chars, sans date, sans accents, uniquement [a-z0-9_]). Réponds UNIQUEMENT le nom, rien d'autre. Exemple: reunion_client_onboarding

$(cat "$summary")" 2>/dev/null | tr -d '[:space:]' | sed 's/[^a-z0-9_]//g')

    if [ ${#new_name} -gt 50 ] || [ -z "$new_name" ]; then
        warn "Invalid folder name generated, skipping rename"
        new_name=""
    fi

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
        folder=$(latest_recording_dir)
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
