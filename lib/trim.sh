#!/bin/bash
# audio-recorder - Trim module (silence analysis + auto-cut)

# ─────────────────────────────────────────────────────────────────────────────
# Trim
# ─────────────────────────────────────────────────────────────────────────────

find_conversation_end() {
    local audio="$1"

    local duration
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$audio")
    local duration_int=${duration%%.*}

    if [ "$duration_int" -lt 600 ]; then
        echo "Recording too short ($(format_duration "$duration_int")) — nothing to trim" >&2
        return 1
    fi

    echo "Analyzing silences..." >&2

    # Single-pass: detect all silences >3s
    local silence_data
    silence_data=$(ffmpeg -i "$audio" -af silencedetect=noise=-30dB:d=3 -f null - 2>&1)

    local -a starts=() durations=()
    mapfile -t starts < <(echo "$silence_data" | grep -oP 'silence_start: \K[0-9.]+')
    mapfile -t durations < <(echo "$silence_data" | grep -oP 'silence_duration: \K[0-9.]+')

    if [ ${#starts[@]} -eq 0 ]; then
        echo "No silences detected" >&2
        return 1
    fi

    local cut_point=""
    local segment=300  # 5 min window for density comparison

    # Strategy 1: first silence >=10s (skip first 5 min)
    # Validate: silence density after >= density before
    for i in "${!starts[@]}"; do
        local s_int=${starts[$i]%%.*}
        local d_int=${durations[$i]:-0}
        d_int=${d_int%%.*}

        [ "$s_int" -lt 300 ] && continue
        [ "$d_int" -lt 10 ] && continue

        local before=0 after=0
        for j in "${!starts[@]}"; do
            local js_int=${starts[$j]%%.*}
            if [ "$js_int" -ge $((s_int - segment)) ] && [ "$js_int" -lt "$s_int" ]; then
                ((before++))
            elif [ "$js_int" -gt "$s_int" ] && [ "$js_int" -le $((s_int + segment)) ]; then
                ((after++))
            fi
        done

        if [ "$after" -ge "$before" ] || [ "$d_int" -ge 15 ]; then
            cut_point="${starts[$i]}"
            break
        fi
    done

    # Strategy 2: find density transition (silence count jumps >1.5x average)
    if [ -z "$cut_point" ]; then
        local -a window_counts=()
        for ((t=0; t<duration_int; t+=segment)); do
            local count=0
            for s in "${starts[@]}"; do
                local s_int=${s%%.*}
                [ "$s_int" -ge "$t" ] && [ "$s_int" -lt $((t + segment)) ] && ((count++))
            done
            window_counts+=("$count")
        done

        local running_sum=0
        for idx in "${!window_counts[@]}"; do
            local c="${window_counts[$idx]}"
            if [ "$idx" -ge 2 ]; then
                local avg=$((running_sum / idx))
                if [ "$avg" -gt 0 ] && [ "$c" -gt $((avg * 3 / 2)) ]; then
                    local window_start=$((idx * segment))
                    # Cut at first >=5s silence in this window
                    for i in "${!starts[@]}"; do
                        local s_int=${starts[$i]%%.*}
                        local d_int=${durations[$i]:-0}
                        d_int=${d_int%%.*}
                        if [ "$s_int" -ge "$window_start" ] && [ "$d_int" -ge 5 ]; then
                            cut_point="${starts[$i]}"
                            break 2
                        fi
                    done
                fi
            fi
            running_sum=$((running_sum + c))
        done
    fi

    if [ -z "$cut_point" ]; then
        echo "No clear conversation end detected" >&2
        return 1
    fi

    echo "$duration_int $cut_point"
}

cmd_trim() {
    local folder="" auto=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y) auto=true; shift ;;
            *) [ -z "$folder" ] && folder="$1"; shift ;;
        esac
    done

    if [ -z "$folder" ]; then
        folder=$(latest_recording_dir)
    fi
    [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"

    local audio="$folder/audio.mp3"
    if [ ! -f "$audio" ]; then
        error "No audio: $audio"
        return 1
    fi

    if [ -f "$folder/audio_full.mp3" ]; then
        error "Already trimmed (audio_full.mp3 exists)"
        return 1
    fi

    local duration_int
    duration_int=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$audio")
    duration_int=${duration_int%%.*}
    info "Duration: $(format_duration "$duration_int")"

    local result
    result=$(find_conversation_end "$audio") || return 1

    local total_dur cut_point
    total_dur=$(echo "$result" | awk '{print $1}')
    cut_point=$(echo "$result" | awk '{print $2}')
    local cut_int=${cut_point%%.*}
    local trim_secs=$((total_dur - cut_int))

    echo ""
    echo -e "  ${BOLD}Conversation end detected at $(format_duration "$cut_int")${NC}"
    echo -e "  ${DIM}(would trim $(format_duration $trim_secs) of trailing audio)${NC}"
    echo ""

    if [ "$auto" != true ]; then
        if [ ! -t 0 ]; then
            error "Use --yes to trim non-interactively"
            return 1
        fi
        local confirm
        read -rp "Cut here? [Y/n] " confirm
        if [[ "$confirm" =~ ^[Nn] ]]; then
            return 0
        fi
    fi

    cp "$audio" "$folder/audio_full.mp3"
    ffmpeg -y -i "$folder/audio_full.mp3" -t "$cut_point" -c copy "$audio" 2>/dev/null

    local new_dur
    new_dur=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$audio")
    new_dur=${new_dur%%.*}
    success "Trimmed: $(format_duration "$total_dur") → $(format_duration "$new_dur") (original: audio_full.mp3)"
}
