#!/usr/bin/env python3
"""Format a WhisperX JSON into transcript lines, fixing the local speaker.

Dual-track recordings (--dual-track, see DUAL_TRACK_TAG in lib/config.sh)
carry the mic on the left channel and the system audio on the right. For
those, each segment whose energy sits on the mic side is attributed to the
local speaker, overriding pyannote — which only guesses from the mixed voice
and often mislabels short replies. Remote speakers keep their labels.

Usage: transcript.py <whisperx.json> <audio> [--dual-track] [--local-speaker NAME]
"""

import argparse
import array
import json
import math
import subprocess
import sys

SAMPLE_RATE = 4000  # energy comparison only: speech band below 2 kHz is enough
LOCAL_MARGIN_DB = 6.0  # mic must dominate system audio by this much


def load_channels(audio):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", audio, "-ac", "2", "-ar", str(SAMPLE_RATE),
         "-f", "s16le", "-"],
        capture_output=True, check=True,
    ).stdout
    samples = array.array("h")
    samples.frombytes(raw)
    if sys.byteorder == "big":
        samples.byteswap()
    return samples[0::2], samples[1::2]


def rms_db(channel, start, end):
    chunk = channel[int(start * SAMPLE_RATE):int(end * SAMPLE_RATE)]
    if not chunk:
        return -120.0
    power = sum(s * s for s in chunk) / len(chunk)
    return 10 * math.log10(power / 32768**2) if power else -120.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("json_path")
    parser.add_argument("audio")
    parser.add_argument("--dual-track", action="store_true")
    parser.add_argument("--local-speaker", default="ME")
    args = parser.parse_args()

    with open(args.json_path) as f:
        segments = json.load(f).get("segments", [])

    channels = load_channels(args.audio) if args.dual_track else None

    for seg in segments:
        text = seg.get("text", "").strip()
        if not text:
            continue
        start = seg.get("start", 0)
        speaker = seg.get("speaker", "UNKNOWN")
        if channels:
            mic_db = rms_db(channels[0], start, seg.get("end", start))
            sys_db = rms_db(channels[1], start, seg.get("end", start))
            if mic_db - sys_db >= LOCAL_MARGIN_DB:
                speaker = args.local_speaker
        mm, ss = divmod(int(start), 60)
        print(f"[{mm:02d}:{ss:02d}] {speaker}: {text}")


if __name__ == "__main__":
    main()
