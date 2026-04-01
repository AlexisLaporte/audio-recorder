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

    # Run whisperx (write transcript lines to progress file in real-time)
    local progress_file="$output_dir/progress.txt"
    local whisper_log="$output_dir/whisperx.log"
    : > "$progress_file"  # Clear/create progress file
    : > "$whisper_log"

    local speaker_args=()
    if [[ -n "$num_speakers" && "$num_speakers" =~ ^[0-9]+$ ]]; then
        speaker_args=(--min_speakers "$num_speakers" --max_speakers "$num_speakers")
    fi

    if ! PYTHONWARNINGS=ignore whisperx "$audio" \
        --model "$model" \
        --diarize \
        --diarize_model "pyannote/speaker-diarization-3.1" \
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
        error "WhisperX failed. See log: $whisper_log"
        tail -20 "$whisper_log" >&2
        return 1
    fi

    rm -f "$progress_file" 2>/dev/null

    local whisper_json="$output_dir/$basename_noext.json"
    local whisper_output="$output_dir/$basename_noext.txt"
    local transcript="$output_dir/transcript.txt"

    # If transcribing a non-audio.mp3 file, keep the original name
    if [ "$basename_noext" != "audio" ]; then
        transcript="$output_dir/${basename_noext}_transcript.txt"
    fi

    # Format transcript from JSON (has timestamps + speakers)
    if [ -f "$whisper_json" ]; then
        python3 -c "
import json, sys
with open('$whisper_json') as f:
    data = json.load(f)
for seg in data.get('segments', []):
    start = int(seg.get('start', 0))
    speaker = seg.get('speaker', 'UNKNOWN')
    text = seg.get('text', '').strip()
    if not text:
        continue
    mm, ss = divmod(start, 60)
    print(f'[{mm:02d}:{ss:02d}] {speaker}: {text}')
" > "$transcript"
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
