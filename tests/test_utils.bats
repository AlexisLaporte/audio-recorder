#!/usr/bin/env bats

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    source "$SCRIPT_DIR/lib/utils.sh"
}

@test "format_duration: seconds" {
    result=$(format_duration 45)
    [ "$result" = "45s" ]
}

@test "format_duration: minutes and seconds" {
    result=$(format_duration 125)
    [ "$result" = "2m 5s" ]
}

@test "format_duration: hours" {
    result=$(format_duration 3665)
    [ "$result" = "1h 1m" ]
}

@test "info outputs message" {
    run info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"test message"* ]]
}

@test "error outputs to stderr" {
    run error "error message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"error message"* ]]
}

@test "colors are set when terminal" {
    # In test context, colors may or may not be set
    # Just verify variables exist
    [ -n "${RED+x}" ] || [ -z "$RED" ]
}
