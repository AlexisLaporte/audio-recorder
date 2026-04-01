#!/usr/bin/env bats

setup() {
    REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$REPO_DIR/lib/utils.sh"
    source "$REPO_DIR/lib/audio.sh"

    TEST_TMPDIR="$(mktemp -d)"
    RECORDINGS_DIR="$TEST_TMPDIR/recordings"
    mkdir -p "$RECORDINGS_DIR"

    PID_FILE="$TEST_TMPDIR/audio-recorder.pid"
    FOLDER_FILE="$TEST_TMPDIR/audio-recorder-folder"
    NAME_FILE="$TEST_TMPDIR/audio-recorder-name"
    START_TIME_FILE="$TEST_TMPDIR/audio-recorder-start"

    export RECORDINGS_DIR PID_FILE FOLDER_FILE NAME_FILE START_TIME_FILE
}

teardown() {
    if [ -n "${TEST_PID:-}" ]; then
        kill "$TEST_PID" 2>/dev/null || true
        wait "$TEST_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_TMPDIR"
}

@test "latest_recording_dir returns the newest renamed recording folder" {
    mkdir -p "$RECORDINGS_DIR/recording_old" "$RECORDINGS_DIR/20260401_sync_client"
    touch "$RECORDINGS_DIR/recording_old/audio.mp3"
    sleep 1
    touch "$RECORDINGS_DIR/20260401_sync_client/transcript.txt"

    result="$(latest_recording_dir)"

    [ "$result" = "$RECORDINGS_DIR/20260401_sync_client" ]
}

@test "latest_recording_dir ignores folders without recording artifacts" {
    mkdir -p "$RECORDINGS_DIR/empty_dir" "$RECORDINGS_DIR/20260401_ready"
    touch "$RECORDINGS_DIR/20260401_ready/summary.md"

    result="$(latest_recording_dir)"

    [ "$result" = "$RECORDINGS_DIR/20260401_ready" ]
}

@test "cmd_stop fails without tty unless --yes or --only is passed" {
    sleep 60 &
    TEST_PID=$!
    echo "$TEST_PID" > "$PID_FILE"
    echo "$RECORDINGS_DIR/recording_1" > "$FOLDER_FILE"
    echo "recording_1" > "$NAME_FILE"
    date +%s > "$START_TIME_FILE"

    run cmd_stop

    [ "$status" -eq 1 ]
    [[ "$output" == *"Use --yes to process or --only to skip processing."* ]]
}

@test "cmd_stop --yes processes non-interactively with speaker count and comment" {
    sleep 60 &
    TEST_PID=$!
    echo "$TEST_PID" > "$PID_FILE"
    echo "$RECORDINGS_DIR/recording_2" > "$FOLDER_FILE"
    echo "recording_2" > "$NAME_FILE"
    date +%s > "$START_TIME_FILE"

    cleanup_bt_profile() { :; }
    notify() { :; }
    cmd_transcribe() {
        echo "$1|$2|$3" > "$TEST_TMPDIR/transcribe_args"
        return 0
    }
    cmd_summarize() {
        printf '%s\n' "$*" > "$TEST_TMPDIR/summarize_args"
        return 0
    }

    run cmd_stop --yes --speakers 2 --comment "brief client sync"

    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TMPDIR/transcribe_args")" = "$RECORDINGS_DIR/recording_2||2" ]
    [ "$(cat "$TEST_TMPDIR/summarize_args")" = "$RECORDINGS_DIR/recording_2 --comment brief client sync" ]
}

@test "cmd_stop rejects an invalid speaker count" {
    run cmd_stop --yes --speakers nope

    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid speaker count: nope"* ]]
}
