#!/bin/bash
# audio-recorder - Summarize module
# shellcheck disable=SC2012  # ls used intentionally for sorting by time

# ─────────────────────────────────────────────────────────────────────────────
# Summarize
# ─────────────────────────────────────────────────────────────────────────────

cmd_summarize() {
    local folder=""
    local no_context=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-context|-n) no_context=true; shift ;;
            *) folder="$1"; shift ;;
        esac
    done

    # Default to latest recording (directories only)
    if [ -z "$folder" ]; then
        folder=$(find "$RECORDINGS_DIR" -maxdepth 1 -type d -name "recording_*" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    fi
    [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"

    local transcript="$folder/transcript.txt"
    if [ ! -f "$transcript" ]; then
        error "No transcript: $transcript"
        return 1
    fi

    # Ensure CLAUDE.md exists in recordings dir
    ensure_recordings_claude_md

    local folder_name
    folder_name=$(basename "$folder")

    # Build prompt for Claude
    local prompt
    if [ "$no_context" = true ]; then
        prompt="Lis $folder_name/transcript.txt et génère un résumé structuré (highlights, résumé, notes, actions). Écris-le dans $folder_name/summary.md puis propose un nom descriptif pour renommer le dossier."
    else
        prompt="Tu dois synthétiser l'enregistrement dans $folder_name/transcript.txt.

Étape 1: Demande-moi le contexte (client/projet, type de réunion, participants si connus).
Étape 2: Après ma réponse, lis le transcript et cherche le dossier CRM correspondant si pertinent.
Étape 3: Génère un résumé structuré et écris-le dans $folder_name/summary.md.
Étape 4: Propose un nom descriptif pour renommer le dossier.

Commence par me demander le contexte."
    fi

    info "Lancement de Claude pour la synthèse..."
    echo ""

    # Launch Claude interactively from recordings dir
    cd "$RECORDINGS_DIR" && claude --add-dir "${CONTEXT_BASE_DIR:-/data/alexis/pro}" "$prompt"
}

# Ensure CLAUDE.md exists in recordings directory
ensure_recordings_claude_md() {
    local claude_md="$RECORDINGS_DIR/CLAUDE.md"
    [ -f "$claude_md" ] && return

    cat > "$claude_md" << 'EOF'
# Recordings - Audio Recorder

Ce dossier contient les enregistrements audio transcrits.

## Structure d'un enregistrement

Chaque sous-dossier contient :
- `audio.mp3` - L'enregistrement audio
- `transcript.txt` - La transcription (WhisperX avec diarization)
- `summary.md` - Le résumé (à créer)

## Instructions de synthèse

Quand on te demande de synthétiser un enregistrement :

1. **Lis le transcript** dans le dossier indiqué
2. **Demande le contexte** si pas fourni (client, projet, type de réunion)
3. **Cherche le dossier CRM** correspondant dans `/data/alexis/pro/crm/` pour enrichir le contexte
4. **Génère un résumé structuré** avec :
   - Titre descriptif
   - Highlights (3-5 points clés)
   - Résumé (2-3 paragraphes)
   - Notes condensées du flux de discussion
   - Actions à faire (si mentionnées)
5. **Écris le résumé** dans `summary.md` du dossier de l'enregistrement
6. **Propose un nom** descriptif pour renommer le dossier (snake_case, max 40 chars)
7. **Mets à jour le CRM** si pertinent (créer/màj fiche client, CR de réunion)

## Dossier CRM

Le CRM est dans `/data/alexis/pro/crm/` avec la structure :
- `0-cold/` - Prospects froids
- `1-outreach/` - En cours de contact
- `2-warm/` - En discussion
- `3-negotiation/` - En négociation
- `clients/` - Clients actifs

Chaque dossier client contient des fiches `.md` et des CR de réunions.
EOF

    success "Created $claude_md"
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
