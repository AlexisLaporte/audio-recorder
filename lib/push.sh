#!/bin/bash
# audio-recorder - Push module
# shellcheck disable=SC2012  # ls used intentionally for sorting by time

# ─────────────────────────────────────────────────────────────────────────────
# Push to tuls.me
# ─────────────────────────────────────────────────────────────────────────────

TULS_API_URL="https://audio-recorder-transcript.tuls.me"

cmd_push() {
    if [ -z "$TULS_API_TOKEN" ]; then
        error "TULS_API_TOKEN not set. Run 'audio-recorder setup'"
        return 1
    fi

    local folder=""
    local with_audio=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --with-audio) with_audio=true; shift ;;
            *) folder="$1"; shift ;;
        esac
    done

    # Default to latest valid recording
    if [ -z "$folder" ]; then
        folder=$(latest_recording_dir)
    fi
    [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"

    local transcript="$folder/transcript.txt"
    if [ ! -f "$transcript" ]; then
        error "No transcript: $transcript"
        return 1
    fi

    local name
    name=$(basename "$folder")
    info "Pushing ${BOLD}$name${NC}..."

    # Build curl args
    local curl_args=(
        -s -w "\n%{http_code}"
        -H "Authorization: Bearer $TULS_API_TOKEN"
        -F "transcript=<$transcript"
        -F "original_filename=$name"
    )

    # Optional summary
    [ -f "$folder/summary.md" ] && curl_args+=(-F "summary=<$folder/summary.md")

    # Optional duration via ffprobe
    if [ -f "$folder/audio.mp3" ]; then
        local duration
        duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$folder/audio.mp3" 2>/dev/null)
        [ -n "$duration" ] && curl_args+=(-F "duration_seconds=$duration")

        if [ "$with_audio" = true ]; then
            curl_args+=(-F "file=@$folder/audio.mp3")
            info "Including audio file"
        fi
    fi

    local response
    response=$(curl "${curl_args[@]}" "$TULS_API_URL/api/audio/recordings")
    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    case "$http_code" in
        201)
            local url
            url=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
            success "Pushed! $TULS_API_URL/recording/$url"
            notify "Push complete" "$name"
            ;;
        409)
            warn "Already pushed"
            ;;
        401)
            error "Invalid API token. Run 'audio-recorder setup'"
            return 1
            ;;
        403)
            error "Audio not enabled for your account"
            return 1
            ;;
        *)
            error "Push failed (HTTP $http_code)"
            echo "$body"
            return 1
            ;;
    esac
}
