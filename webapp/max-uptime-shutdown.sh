#!/bin/bash
# Safety net: shutdown if idle or uptime exceeds limit.
# Crontab: */5 * * * * /opt/audio-recorder/max-uptime-shutdown.sh

MAX_UPTIME_MINUTES=120
IDLE_MINUTES=10
HEARTBEAT_FILE=/tmp/worker-heartbeat
BOOT_GRACE=120  # seconds — don't shutdown during boot

UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime)

# Max uptime hard limit
if [ "$UPTIME_SECONDS" -gt $((MAX_UPTIME_MINUTES * 60)) ]; then
    echo "Uptime ${UPTIME_SECONDS}s exceeds ${MAX_UPTIME_MINUTES}min, shutting down"
    shutdown -h now
    exit 0
fi

# Don't check idle during boot grace period
if [ "$UPTIME_SECONDS" -lt "$BOOT_GRACE" ]; then
    exit 0
fi

# Idle detection: worker process dead or heartbeat stale
if ! pgrep -f 'worker.py' > /dev/null; then
    echo "Worker process not running (uptime ${UPTIME_SECONDS}s), shutting down"
    shutdown -h now
    exit 0
fi

if [ -f "$HEARTBEAT_FILE" ]; then
    HEARTBEAT=$(cat "$HEARTBEAT_FILE")
    NOW=$(date +%s)
    IDLE=$((NOW - ${HEARTBEAT%.*}))
    if [ "$IDLE" -gt $((IDLE_MINUTES * 60)) ]; then
        echo "Heartbeat stale (${IDLE}s idle), shutting down"
        shutdown -h now
        exit 0
    fi
fi
