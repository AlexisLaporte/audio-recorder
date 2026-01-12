# audio-recorder

Record → Transcribe → Summarize. One command.

```bash
audio-recorder start    # Start recording
audio-recorder stop     # Stop + transcribe + AI summary
```

## Install

```bash
git clone https://github.com/AlexisLaporte/audio-recorder.git
cd audio-recorder && ./install.sh
audio-recorder setup    # Configure HuggingFace token
```

**Requirements**: ffmpeg, [whisperx](https://github.com/m-bain/whisperX), [claude](https://github.com/anthropics/claude-code)

## Commands

| Command | Description |
|---------|-------------|
| `start` | Start recording (mic + system audio) |
| `stop` | Stop → transcribe → summarize |
| `stop --only` | Stop without processing |
| `stop -c "context"` | Stop with context for AI |
| `status` | Show recording status |
| `list` | List recordings |
| `open [folder]` | Open in file manager |
| `transcribe [folder]` | Transcribe only |
| `summarize [folder]` | Summarize only |
| `setup` | Configure settings |

## Output

```
~/Recordings/
├── summarize-prompt.md          # Customize AI prompt
└── meeting_name/
    ├── audio.mp3
    ├── transcript.txt           # Speaker diarization
    └── summary.md               # Highlights + notes
```

## Platforms

- **Linux**: PulseAudio
- **macOS**: AVFoundation + [BlackHole](https://github.com/ExistentialAudio/BlackHole) for system audio

## License

MIT
