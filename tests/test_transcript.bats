#!/usr/bin/env bats

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    TEST_TMPDIR="$(mktemp -d)"
    cat > "$TEST_TMPDIR/audio.json" <<'JSON'
{"segments": [
  {"start": 0.2, "end": 1.4, "speaker": "SPEAKER_01", "text": " Bonjour."},
  {"start": 2.2, "end": 5.8, "speaker": "SPEAKER_01", "text": " Salut."},
  {"start": 5.9, "end": 5.95, "speaker": "SPEAKER_00", "text": "  "}
]}
JSON
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# Builds a 6 s stereo file: mic (left) and system (right) volume expressions over t
make_audio() {
    ffmpeg -v error -f lavfi -i "sine=f=300:d=6" -filter_complex \
        "[0:a]volume='$1':eval=frame[l];[0:a]volume='$2':eval=frame[r];[l][r]join=inputs=2:channel_layout=stereo[out]" \
        -map "[out]" -y "$TEST_TMPDIR/audio.wav"
}

transcript() {
    run python3 -I "$REPO_DIR/lib/transcript.py" "$TEST_TMPDIR/audio.json" "$TEST_TMPDIR/audio.wav" "$@"
}

@test "transcript.py keeps diarization labels on a mixed recording" {
    make_audio "if(lt(t,1.5),1,0)" "if(lt(t,1.5),0,1)"
    transcript
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[00:00] SPEAKER_01: Bonjour." ]
    [ "${lines[1]}" = "[00:02] SPEAKER_01: Salut." ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "transcript.py pins mic-side segments to the local speaker on dual-track" {
    make_audio "if(lt(t,1.5),1,0)" "if(lt(t,1.5),0,1)"
    transcript --dual-track --local-speaker Alexis
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[00:00] Alexis: Bonjour." ]
    [ "${lines[1]}" = "[00:02] SPEAKER_01: Salut." ]
}

@test "transcript.py hears the local speaker over loud system audio" {
    make_audio "if(lt(t,1.5),0.05,0)" "if(lt(t,5.2),1,0)"
    transcript --dual-track --local-speaker Alexis
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[00:00] Alexis: Bonjour." ]
    [ "${lines[1]}" = "[00:02] SPEAKER_01: Salut." ]
}

@test "transcript.py keeps diarization when nothing plays remotely" {
    make_audio "1" "0"
    transcript --dual-track --local-speaker Alexis
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[00:00] SPEAKER_01: Bonjour." ]
    [ "${lines[1]}" = "[00:02] SPEAKER_01: Salut." ]
}
