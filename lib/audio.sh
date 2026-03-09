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
            MONITOR="$(pactl get-default-sink).monitor"
            MIC="$(pactl get-default-source)"
            ;;
    esac
}

ensure_mic_active() {
    # Unmute mic if muted
    local muted
    muted=$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | awk '{print $2}')
    if [ "$muted" = "oui" ] || [ "$muted" = "yes" ]; then
        pactl set-source-mute @DEFAULT_SOURCE@ 0
        warn "Mic was muted — auto-unmuted"
    fi

    # Ensure volume is at least 50%
    local vol_pct
    vol_pct=$(pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -oP '\d+%' | head -1 | tr -d '%')
    if [ -n "$vol_pct" ] && [ "$vol_pct" -lt 50 ]; then
        pactl set-source-volume @DEFAULT_SOURCE@ 100%
        warn "Mic volume was ${vol_pct}% — set to 100%"
    fi
}

check_audio_volume() {
    local file="$1"
    local duration="${2:-2}"
    local test_file
    test_file=$(mktemp /tmp/audio-test-XXXXX.wav)
    # Sample last N seconds of the file
    ffmpeg -sseof "-${duration}" -i "$file" -t "$duration" -y "$test_file" &>/dev/null
    local volume
    volume=$(ffmpeg -i "$test_file" -af volumedetect -f null /dev/null 2>&1 | grep mean_volume | awk '{print $5}')
    rm -f "$test_file"
    echo "${volume:--91.0}"
}

audio_watchdog() {
    local audio_file="$1"
    local pid_file="$2"
    local check_interval=120  # 2 minutes

    sleep "$check_interval"
    while [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; do
        local vol
        vol=$(check_audio_volume "$audio_file" 5)
        local vol_int=${vol%%.*}
        if [ "$vol_int" -lt -60 ]; then
            notify "⚠️ Audio may be empty" "Monitor volume: ${vol} dB — check your audio source"
            warn "Audio seems empty (${vol} dB) — check your audio source!"
        fi
        sleep "$check_interval"
    done
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

    if [ "$OS" != "Darwin" ]; then
        ensure_mic_active
    fi

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

    # Detect audio mode
    local audio_mode sink_name mic_name
    case "$OS" in
        Darwin) sink_name="AVFoundation :$MONITOR"; mic_name="AVFoundation :$MIC"; audio_mode="macOS" ;;
        *)
            sink_name=$(pactl get-default-sink)
            mic_name=$(pactl get-default-source)
            if echo "$sink_name" | grep -qi "bluez"; then
                audio_mode="🎧 Bluetooth"
            else
                audio_mode="🔊 Speakers + Mic"
            fi
            ;;
    esac

    echo ""
    echo -e "  ${RED}●${NC} ${BOLD}Recording${NC}  ${YELLOW}${audio_mode}${NC}"
    echo -e "  ${DIM}$name${NC}"
    echo -e "  ${DIM}⏎ ${sink_name}${NC}"
    echo -e "  ${DIM}⏎ ${mic_name}${NC}"
    echo ""

    notify "Recording started" "$name"

    # Background watchdog (Linux only)
    if [ "$OS" != "Darwin" ]; then
        audio_watchdog "$folder/audio.mp3" "$PID_FILE" &
        echo $! > "/tmp/audio-recorder-watchdog.pid"
        disown
    fi
}

cmd_stop() {
    local process_audio=true

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only) process_audio=false; shift ;;
            *) shift ;;
        esac
    done

    if ! is_recording; then
        error "No recording in progress"
        return 1
    fi

    # Stop watchdog
    [ -f "/tmp/audio-recorder-watchdog.pid" ] && kill "$(cat "/tmp/audio-recorder-watchdog.pid")" 2>/dev/null
    rm -f "/tmp/audio-recorder-watchdog.pid"

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
        read -rp "Transcrire maintenant ? [Y/n] " do_transcribe
        if [[ "$do_transcribe" =~ ^[Nn] ]]; then
            return 0
        fi

        local num_speakers=""
        read -rp "Combien de speakers ? [auto] " num_speakers

        echo ""
        echo -e "${BOLD}Processing...${NC}"
        echo ""

        if cmd_transcribe "$folder" "" "$num_speakers"; then
            cmd_summarize "$folder"
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
