#!/bin/bash
# Safety net: force shutdown if uptime exceeds MAX_MINUTES.
# Add to crontab: */10 * * * * /opt/audio-recorder/max-uptime-shutdown.sh
MAX_MINUTES=120
UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime)
if [ "$UPTIME_SECONDS" -gt $((MAX_MINUTES * 60)) ]; then
    echo "Uptime ${UPTIME_SECONDS}s exceeds ${MAX_MINUTES}min, shutting down"
    shutdown -h now
fi
