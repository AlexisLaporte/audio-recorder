#!/usr/bin/env python3
"""Format a WhisperX JSON into transcript lines, fixing the local speaker.

Dual-track recordings (--dual-track, see DUAL_TRACK_TAG in lib/config.sh)
carry the mic on the left channel and the system audio on the right. For
those, segments where the mic is active — beyond what the speakers leak
into it — are attributed to the local speaker, overriding pyannote, which
only guesses from the mixed voice and often mislabels short replies.
Remote speakers keep their labels.

Usage: transcript.py <whisperx.json> <audio> [--dual-track] [--local-speaker NAME]
"""

import argparse
import array
import json
import math
import subprocess
import sys

SAMPLE_RATE = 4000  # energy only: the speech band below 2 kHz is enough
FRAME = SAMPLE_RATE // 10  # 100 ms
ACTIVE_DB = 20.0  # a frame is active this far above its channel's noise floor
BLEED_MARGIN_DB = 10.0  # local speech must beat the speaker leak by this much
MIN_REMOTE_ACTIVITY = 0.05  # below this, nothing plays remotely: in-room meeting


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


def frame_db(channel):
    out = []
    for i in range(0, len(channel) - FRAME + 1, FRAME):
        power = sum(s * s for s in channel[i:i + FRAME]) / FRAME
        out.append(10 * math.log10(power / 32768**2) if power else -120.0)
    return out


def activity(dbs):
    floor = sorted(dbs)[len(dbs) // 10]
    return [d >= floor + ACTIVE_DB for d in dbs]


def local_frames(mic, system):
    """Per frame: (local speech, any speech). None when no remote side played."""
    mic_db, sys_db = frame_db(mic), frame_db(system)
    if not mic_db:
        return None
    mic_on, sys_on = activity(mic_db), activity(sys_db)
    if sum(sys_on) < MIN_REMOTE_ACTIVITY * len(sys_on):
        return None
    # Typical mic/system gap while the system plays = how much the speakers
    # leak into the mic (very negative with a headset).
    gaps = sorted(m - s for m, s, on in zip(mic_db, sys_db, sys_on) if on)
    bleed = gaps[len(gaps) // 2]
    local = [on and m - s >= bleed + BLEED_MARGIN_DB
             for m, s, on in zip(mic_db, sys_db, mic_on)]
    active = [a or b for a, b in zip(mic_on, sys_on)]
    return local, active


def is_local(frames, start, end):
    local, active = frames
    span = range(int(start * 10), min(int(end * 10) + 1, len(local)))
    n_active = sum(active[i] for i in span)
    return n_active > 0 and sum(local[i] for i in span) >= n_active / 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("json_path")
    parser.add_argument("audio")
    parser.add_argument("--dual-track", action="store_true")
    parser.add_argument("--local-speaker", default="ME")
    args = parser.parse_args()

    with open(args.json_path) as f:
        segments = json.load(f).get("segments", [])

    frames = local_frames(*load_channels(args.audio)) if args.dual_track else None

    for seg in segments:
        text = seg.get("text", "").strip()
        if not text:
            continue
        start = seg.get("start", 0)
        speaker = seg.get("speaker", "UNKNOWN")
        if frames and is_local(frames, start, seg.get("end", start)):
            speaker = args.local_speaker
        mm, ss = divmod(int(start), 60)
        print(f"[{mm:02d}:{ss:02d}] {speaker}: {text}")


if __name__ == "__main__":
    main()
