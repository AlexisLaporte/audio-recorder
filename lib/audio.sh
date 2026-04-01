#!/bin/bash
# audio-recorder - Audio recording module

# ─────────────────────────────────────────────────────────────────────────────
# Audio sources
# ─────────────────────────────────────────────────────────────────────────────

BT_PROFILE_FILE="/tmp/audio-recorder-bt-profile"

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
            local default_sink
            default_sink=$(pactl get-default-sink)

            if echo "$default_sink" | grep -qi "bluez"; then
                # A2DP monitor doesn't capture in PipeWire.
                # Switch to HFP: monitor works + BT mic available.
                local bt_card
                bt_card=$(pactl list cards short 2>/dev/null | grep bluez | cut -f2)
                if [ -n "$bt_card" ]; then
                    echo "$bt_card" > "$BT_PROFILE_FILE"
                    pactl set-card-profile "$bt_card" headset-head-unit
                    sleep 0.5
                    # HFP sink may not be default — force it
                    local bt_sink
                    bt_sink=$(pactl list short sinks | grep bluez | cut -f2)
                    if [ -n "$bt_sink" ]; then
                        pactl set-default-sink "$bt_sink"
                        default_sink="$bt_sink"
                    fi
                fi
            fi

            MONITOR="${default_sink}.monitor"
            MIC="$(pactl get-default-source)"
            ;;
    esac
}

cleanup_bt_profile() {
    if [ ! -f "$BT_PROFILE_FILE" ]; then
        return
    fi
    local bt_card
    bt_card=$(cat "$BT_PROFILE_FILE")
    pactl set-card-profile "$bt_card" a2dp-sink 2>/dev/null
    rm -f "$BT_PROFILE_FILE"
}

ensure_mic_active() {
    # Unmute mic if muted
    local muted
    muted=$(pactl get-source-mute "$MIC" 2>/dev/null | awk '{print $2}')
    if [ "$muted" = "oui" ] || [ "$muted" = "yes" ]; then
        pactl set-source-mute "$MIC" 0
        warn "Mic was muted — auto-unmuted"
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
    # shellcheck disable=SC2153  # PID_FILE comes from sourced config.sh
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
                    -filter_complex "[0:a][1:a]amix=inputs=2:duration=longest:normalize=0[out]" \
                    -map "[out]" -codec:a libmp3lame -q:a 2 \
                    "$folder/audio.mp3" &>/dev/null &
            else
                ffmpeg -f avfoundation -i ":$MIC" -codec:a libmp3lame -q:a 2 \
                    "$folder/audio.mp3" &>/dev/null &
            fi
            ;;
        *)
            ffmpeg -f pulse -i "$MONITOR" -f pulse -i "$MIC" \
                -filter_complex "[0:a]aresample=48000[sys];[1:a]aresample=48000[mic];[sys][mic]amix=inputs=2:duration=longest:normalize=0[mix];[mix]alimiter=limit=0.8[out]" \
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
            mic_name="$MIC"
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
    local comment=""
    local ask_transcribe=true
    local num_speakers=""

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only) process_audio=false; shift ;;
            --yes|--transcribe) ask_transcribe=false; shift ;;
            --speakers)
                num_speakers="$2"
                shift 2
                ;;
            --comment) comment="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ -n "$num_speakers" && ! "$num_speakers" =~ ^[0-9]+$ ]]; then
        error "Invalid speaker count: $num_speakers"
        return 1
    fi

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

    # Restore A2DP profile if we switched to HFP
    cleanup_bt_profile

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
        if [ "$ask_transcribe" = true ]; then
            if [ ! -t 0 ]; then
                error "Stop is interactive by default. Use --yes to process or --only to skip processing."
                return 1
            fi

            local do_transcribe
            echo ""
            read -rp "Transcrire maintenant ? [Y/n] " do_transcribe
            if [[ "$do_transcribe" =~ ^[Nn] ]]; then
                return 0
            fi

            if [ -z "$num_speakers" ]; then
                read -rp "Combien de speakers ? [auto] " num_speakers
                # Validate: must be a positive integer, otherwise auto
                if [[ -n "$num_speakers" && ! "$num_speakers" =~ ^[0-9]+$ ]]; then
                    warn "Invalid input '$num_speakers' — using auto-detect"
                    num_speakers=""
                fi
            fi
        fi

        echo ""
        echo -e "${BOLD}Processing...${NC}"
        echo ""

        if cmd_transcribe "$folder" "" "$num_speakers"; then
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
