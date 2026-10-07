#!/usr/bin/env bats

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    TEST_TMPDIR="$(mktemp -d)"
    # Mic speaks on the left during 0-2 s, the remote side on the right during 2-4 s
    ffmpeg -v error -f lavfi -i "sine=f=300:d=4" -filter_complex \
        "[0:a]volume='if(lt(t,2),1,0)':eval=frame[l];[0:a]volume='if(lt(t,2),0,1)':eval=frame[r];[l][r]join=inputs=2:channel_layout=stereo[out]" \
        -map "[out]" -y "$TEST_TMPDIR/audio.wav"
    cat > "$TEST_TMPDIR/audio.json" <<'JSON'
{"segments": [
  {"start": 0.2, "end": 1.8, "speaker": "SPEAKER_01", "text": " Bonjour."},
  {"start": 2.2, "end": 3.8, "speaker": "SPEAKER_01", "text": " Salut."},
  {"start": 3.9, "end": 3.95, "speaker": "SPEAKER_00", "text": "  "}
]}
JSON
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "transcript.py keeps diarization labels on a mixed recording" {
    run python3 -I "$REPO_DIR/lib/transcript.py" "$TEST_TMPDIR/audio.json" "$TEST_TMPDIR/audio.wav"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[00:00] SPEAKER_01: Bonjour." ]
    [ "${lines[1]}" = "[00:02] SPEAKER_01: Salut." ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "transcript.py pins mic-side segments to the local speaker on dual-track" {
    run python3 -I "$REPO_DIR/lib/transcript.py" "$TEST_TMPDIR/audio.json" "$TEST_TMPDIR/audio.wav" \
        --dual-track --local-speaker Alexis
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[00:00] Alexis: Bonjour." ]
    [ "${lines[1]}" = "[00:02] SPEAKER_01: Salut." ]
}
