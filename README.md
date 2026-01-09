# audio-recorder

Record audio (mic + system) with automatic transcription via WhisperX (speaker diarization included).

## Dependencies

```bash
# FFmpeg for recording
sudo apt install ffmpeg

# WhisperX for transcription
pipx install whisperx
```

Note: WhisperX requires a HuggingFace token and accepting conditions at:
- https://hf.co/pyannote/speaker-diarization-3.1
- https://hf.co/pyannote/segmentation-3.0

## Installation

```bash
git clone git@github.com:AlexisLaporte/audio-recorder.git
ln -s $(pwd)/audio-recorder/audio-recorder ~/.local/bin/audio-recorder
```

## Configuration

Set your HuggingFace token in `~/.bashrc` or `.envrc`:
```bash
export HF_TOKEN="hf_xxx"
```

## Usage

```bash
audio-recorder start      # Start recording
audio-recorder stop       # Stop recording
audio-recorder status     # Show status
audio-recorder list       # List recordings
audio-recorder transcribe # Transcribe latest recording
```

## Output structure

```
~/Enregistrements/
└── recording_YYYYMMDD_HHMMSS/
    ├── audio.mp3
    └── transcript.txt
```

Transcript includes speaker identification (`[SPEAKER_00]`, `[SPEAKER_01]`, etc.).
