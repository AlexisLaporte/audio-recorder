# audio-recorder

Record audio (mic + system), transcribe with WhisperX, and summarize with Claude AI.

Works on **Linux** and **macOS**.

## Quick Start

```bash
# Install
git clone https://github.com/AlexisLaporte/audio-recorder.git
cd audio-recorder && ./install.sh

# Configure
audio-recorder setup

# Record
audio-recorder start
audio-recorder stop              # Auto-transcribes & summarizes
```

## Usage

```bash
audio-recorder start                     # Start recording
audio-recorder stop                      # Stop → transcribe → summarize
audio-recorder stop --only               # Stop without processing
audio-recorder stop --comment "context"  # Stop with context for AI
audio-recorder status                    # Show recording status & duration

audio-recorder transcribe [folder]       # Transcribe only
audio-recorder summarize [folder]        # Summarize only
audio-recorder summarize -c "context"    # Summarize with context

audio-recorder list                      # List recordings
audio-recorder open [folder]             # Open in file manager
audio-recorder setup                     # Configure settings
```

## Output

```
~/Recordings/
└── meeting_budget_q1/           # Renamed after summarize
    ├── audio.mp3                # Original recording
    ├── transcript.txt           # WhisperX transcription (speaker diarization)
    └── summary.md               # AI summary with highlights & notes
```

## Summary Format

The AI generates a structured markdown summary:
- **Title**: Descriptive title
- **Highlights**: 3-5 key takeaways
- **Summary**: Brief overview
- **Notes**: Condensed exchange flow
- **Action Items**: Tasks mentioned (if any)

Customize the format by editing `summarize-prompt.md`.

## Installation

The installer:
- Installs CLI to `~/.local/bin`
- Sets up bash completion
- Checks/installs dependencies (ffmpeg, whisperx)

### macOS: System Audio

To capture system audio (not just mic), install BlackHole:
```bash
brew install blackhole-2ch
```
Then create a Multi-Output Device in Audio MIDI Setup.

### HuggingFace

WhisperX requires accepting conditions:
- https://hf.co/pyannote/speaker-diarization-3.1
- https://hf.co/pyannote/segmentation-3.0
