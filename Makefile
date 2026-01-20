.PHONY: test lint all

all: lint test

lint:
	shellcheck lib/*.sh audio-recorder

test:
	bats tests/
