#!/bin/bash
# audio-recorder - Audio recording module

# ─────────────────────────────────────────────────────────────────────────────
# Audio sources
# ─────────────────────────────────────────────────────────────────────────────

get_sources() {
    local devices
    case "$OS" in
        Darwin)
            devices=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1 | grep -A 100 "audio devices" | grep "^\[")
            # Try Background Music first, then BlackHole
            MONITOR=$(echo "$devices" | grep -i "background music" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
            [ -z "$MONITOR" ] && MONITOR=$(echo "$devices" | grep -i "blackhole" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
            MIC=$(echo "$devices" | grep -i "microphone\|macbook" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
            [ -z "$MIC" ] && MIC="0"
            ;;
        *)
            MONITOR=$(pactl list short sources | grep "monitor" | grep -v "SUSPENDED" | head -1 | cut -f2)
            MIC=$(pactl list short sources | grep "input" | grep -v "SUSPENDED" | head -1 | cut -f2)
            [ -z "$MONITOR" ] && MONITOR=$(pactl list short sources | grep "monitor" | head -1 | cut -f2)
            [ -z "$MIC" ] && MIC=$(pactl list short sources | grep "input" | head -1 | cut -f2)
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Recording
# ─────────────────────────────────────────────────────────────────────────────

is_recording() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

cmd_start() {
    if is_recording; then
        error "Already recording: $(cat "$NAME_FILE" 2>/dev/null)"
        return 1
    fi

    get_sources

    local name folder
    name="recording_$(date +%Y%m%d_%H%M%S)"
    folder="$RECORDINGS_DIR/$name"
    mkdir -p "$folder"

    echo "$folder" > "$FOLDER_FILE"
    echo "$name" > "$NAME_FILE"
    date +%s > "$START_TIME_FILE"

    case "$OS" in
        Darwin)
            if [ -n "$MONITOR" ]; then
                ffmpeg -f avfoundation -i ":$MONITOR" -f avfoundation -i ":$MIC" \
                    -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest[out]" \
                    -map "[out]" -codec:a libmp3lame -q:a 2 \
                    "$folder/audio.mp3" &>/dev/null &
            else
                ffmpeg -f avfoundation -i ":$MIC" -codec:a libmp3lame -q:a 2 \
                    "$folder/audio.mp3" &>/dev/null &
            fi
            ;;
        *)
            ffmpeg -f pulse -i "$MONITOR" -f pulse -i "$MIC" \
                -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest[out]" \
                -map "[out]" -codec:a libmp3lame -q:a 2 \
                "$folder/audio.mp3" &>/dev/null &
            ;;
    esac

    echo $! > "$PID_FILE"

    echo ""
    echo -e "  ${RED}●${NC} ${BOLD}Recording${NC}"
    echo -e "  ${DIM}$name${NC}"
    echo ""

    notify "Recording started" "$name"
}

cmd_stop() {
    local process_audio=true
    local comment=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only) process_audio=false; shift ;;
            --comment|-c) comment="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if ! is_recording; then
        error "No recording in progress"
        return 1
    fi

    # Stop ffmpeg
    kill "$(cat "$PID_FILE")" 2>/dev/null
    rm -f "$PID_FILE"

    local name folder start_time
    name=$(cat "$NAME_FILE" 2>/dev/null)
    folder=$(cat "$FOLDER_FILE" 2>/dev/null)
    start_time=$(cat "$START_TIME_FILE" 2>/dev/null)
    local duration=""

    if [ -n "$start_time" ]; then
        local elapsed=$(($(date +%s) - start_time))
        duration=$(format_duration $elapsed)
    fi

    echo ""
    echo -e "  ${GREEN}■${NC} ${BOLD}Stopped${NC} ${DIM}($duration)${NC}"
    echo -e "  ${DIM}$folder/audio.mp3${NC}"

    notify "Recording stopped" "$name ($duration)"

    # Process if requested
    if [ "$process_audio" = true ]; then
        echo ""
        echo -e "${BOLD}Processing...${NC}"
        echo ""

        # Transcribe
        if cmd_transcribe "$folder"; then
            # Summarize
            if [ -n "$comment" ]; then
                cmd_summarize "$folder" --comment "$comment"
            else
                cmd_summarize "$folder"
            fi
        fi
    fi
}

cmd_status() {
    local name start_time
    if is_recording; then
        name=$(cat "$NAME_FILE" 2>/dev/null)
        start_time=$(cat "$START_TIME_FILE" 2>/dev/null)
        local duration=""
        if [ -n "$start_time" ]; then
            local elapsed=$(($(date +%s) - start_time))
            duration=" ($(format_duration $elapsed))"
        fi
        echo -e "${RED}●${NC} Recording: ${BOLD}$name${NC}$duration"
    else
        echo -e "${DIM}■${NC} Not recording"
    fi
}
