#!/bin/bash
# audio-recorder - Transcription module
# shellcheck disable=SC2012  # ls used intentionally for sorting by time

# ─────────────────────────────────────────────────────────────────────────────
# Transcribe
# ─────────────────────────────────────────────────────────────────────────────

cmd_transcribe() {
    if [ -z "$HF_TOKEN" ]; then
        error "HF_TOKEN not set. Run 'audio-recorder setup'"
        return 1
    fi

    if ! command -v whisperx &>/dev/null; then
        error "whisperx not found in PATH. Re-run the installer:"
        error "  cd $(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd) && ./install.sh"
        error "Or install manually: uv tool install whisperx --python 3.12"
        return 1
    fi

    local input="$1"
    local model="${2:-${WHISPER_MODEL:-large-v3}}"
    local num_speakers="$3"
    local audio=""
    local output_dir=""
    local basename_noext=""

    # Default to latest recording
    if [ -z "$input" ]; then
        input=$(latest_recording_dir)
    fi

    # Check if input is a file or folder
    if [ -f "$input" ]; then
        # Direct file path
        audio="$input"
        output_dir="$(dirname "$audio")"
        basename_noext="$(basename "$audio" | sed 's/\.[^.]*$//')"
    else
        # Folder path (existing behavior)
        local folder="$input"
        [[ ! "$folder" == /* ]] && folder="$RECORDINGS_DIR/$folder"
        audio="$folder/audio.mp3"
        output_dir="$folder"
        basename_noext="audio"
    fi

    if [ ! -f "$audio" ]; then
        error "No audio file: $audio"
        return 1
    fi

    # Extract audio from video files
    local mime
    mime=$(file --mime-type -b "$audio")
    if [[ "$mime" == video/* ]]; then
        local extracted="$output_dir/${basename_noext}.mp3"
        info "Extracting audio from video..."
        ffmpeg -i "$audio" -vn -acodec libmp3lame -q:a 2 "$extracted" -y -loglevel error || {
            error "Failed to extract audio from video"
            return 1
        }
        audio="$extracted"
        basename_noext="$(basename "$audio" | sed 's/\.[^.]*$//')"
    fi

    info "Transcribing with WhisperX (model: $model)..."
    info "Input: $audio"

    local dual_track=false
    if [ "$(ffprobe -v error -show_entries format_tags=comment -of default=nw=1:nk=1 "$audio")" = "$DUAL_TRACK_TAG" ]; then
        dual_track=true
    fi

    # Dual-track: level each channel on its own before the mono downmix — the
    # system channel follows the output volume and can sit 20 dB below the mic.
    local whisper_input="$audio" tmp_dir=""
    if [ "$dual_track" = true ]; then
        tmp_dir=$(mktemp -d)
        whisper_input="$tmp_dir/$basename_noext.wav"
        if ! ffmpeg -v error -i "$audio" -af "dynaudnorm=n=0,pan=mono|c0=0.5*c0+0.5*c1" \
            -ar 16000 "$whisper_input"; then
            rm -rf "$tmp_dir"
            error "Failed to level the dual-track audio"
            return 1
        fi
    fi

    # Run whisperx (write transcript lines to progress file in real-time)
    local progress_file="$output_dir/progress.txt"
    local whisper_log="$output_dir/whisperx.log"
    : > "$progress_file"  # Clear/create progress file
    : > "$whisper_log"

    local speaker_args=()
    if [[ -n "$num_speakers" && "$num_speakers" =~ ^[0-9]+$ ]]; then
        speaker_args=(--min_speakers "$num_speakers" --max_speakers "$num_speakers")
    fi

    # VRAM-safety knobs (override via env). Defaults tuned to avoid OOM on long
    # recordings: smaller batch + int8 compute keep peak VRAM well under budget.
    # WHISPER_DEVICE=cpu lets transcription run without a working GPU (slower).
    local batch_size="${WHISPER_BATCH_SIZE:-4}"
    local compute_type="${WHISPER_COMPUTE_TYPE:-int8}"
    local device="${WHISPER_DEVICE:-cuda}"

    # Force language (skip auto-detect). Useful when a chunk starts on silence
    # and language detection misfires. Empty = auto-detect (default).
    local lang_args=()
    if [[ -n "$WHISPER_LANGUAGE" ]]; then
        lang_args=(--language "$WHISPER_LANGUAGE")
    fi

    # Domain vocabulary (names, products, acronyms) primes the first window and
    # stops Whisper from mishearing them ("Cloud" for "Claude").
    local prompt_args=()
    if [[ -n "$WHISPER_INITIAL_PROMPT" ]]; then
        prompt_args=(--initial_prompt "$WHISPER_INITIAL_PROMPT")
    fi

    if ! PYTHONWARNINGS=ignore whisperx "$whisper_input" \
        --model "$model" \
        --device "$device" \
        --batch_size "$batch_size" \
        --compute_type "$compute_type" \
        "${lang_args[@]}" \
        "${prompt_args[@]}" \
        --diarize \
        --hf_token "$HF_TOKEN" \
        "${speaker_args[@]}" \
        --output_dir "$output_dir" 2>&1 | tee "$whisper_log" | awk -v pf="$progress_file" '
            /^Transcript:/ {
                sub(/^Transcript: \[[^]]+\]  /, "")
                print >> pf
                fflush(pf)
                next
            }
            !/^\/|UserWarning|^$|^Traceback|^  File/ { print; fflush() }
        '
    then
        rm -f "$progress_file" 2>/dev/null
        rm -rf "$tmp_dir"
        error "WhisperX failed. See log: $whisper_log"
        tail -20 "$whisper_log" >&2
        return 1
    fi

    rm -f "$progress_file" 2>/dev/null
    rm -rf "$tmp_dir"

    local whisper_json="$output_dir/$basename_noext.json"
    local whisper_output="$output_dir/$basename_noext.txt"
    local transcript="$output_dir/transcript.txt"

    # If transcribing a non-audio.mp3 file, keep the original name
    if [ "$basename_noext" != "audio" ]; then
        transcript="$output_dir/${basename_noext}_transcript.txt"
    fi

    # Format transcript from JSON (has timestamps + speakers)
    if [ -f "$whisper_json" ]; then
        local track_args=()
        [ "$dual_track" = true ] && track_args=(--dual-track)
        python3 -I "$SCRIPT_DIR/lib/transcript.py" "$whisper_json" "$audio" "${track_args[@]}" \
            --local-speaker "${LOCAL_SPEAKER:-ME}" > "$transcript" || {
            error "Transcript formatting failed"
            return 1
        }
        rm -f "$whisper_json"
        rm -f "$whisper_output" 2>/dev/null
    elif [ -f "$whisper_output" ]; then
        if [ "$whisper_output" != "$transcript" ]; then
            mv "$whisper_output" "$transcript"
        fi
    else
        error "Transcription failed. WhisperX produced no usable output. See log: $whisper_log"
        return 1
    fi

    # Cleanup other formats
    rm -f "$output_dir/$basename_noext".{srt,tsv,vtt} 2>/dev/null

    success "Transcript: $transcript"
}
