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
    local model="${2:-small}"
    local audio=""
    local output_dir=""
    local basename_noext=""

    # Default to latest recording
    if [ -z "$input" ]; then
        input=$(ls -td "$RECORDINGS_DIR"/recording_* 2>/dev/null | head -1)
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

    info "Transcribing with WhisperX (model: $model)..."
    info "Input: $audio"

    # Run whisperx (write transcript lines to progress file in real-time)
    local progress_file="$output_dir/progress.txt"
    : > "$progress_file"  # Clear/create progress file

    whisperx "$audio" \
        --model "$model" \
        --diarize \
        --hf_token "$HF_TOKEN" \
        --output_dir "$output_dir" 2>&1 | awk -v pf="$progress_file" '
            /^Transcript:/ {
                sub(/^Transcript: \[[^]]+\]  /, "")
                print >> pf
                fflush(pf)
                next
            }
            !/^\/|UserWarning|^$|^Traceback|^  File/ { print; fflush() }
        ' || true

    rm -f "$progress_file" 2>/dev/null

    # Cleanup other formats
    rm -f "$output_dir/$basename_noext".{json,srt,tsv,vtt} 2>/dev/null

    local whisper_output="$output_dir/$basename_noext.txt"
    local transcript="$output_dir/transcript.txt"

    # If transcribing a non-audio.mp3 file, keep the original name
    if [ "$basename_noext" != "audio" ]; then
        transcript="$output_dir/${basename_noext}_transcript.txt"
    fi

    if [ -f "$whisper_output" ]; then
        # Only rename if different
        if [ "$whisper_output" != "$transcript" ]; then
            mv "$whisper_output" "$transcript"
        fi
        success "Transcript: $transcript"
        return 0
    else
        error "Transcription failed"
        return 1
    fi
}
