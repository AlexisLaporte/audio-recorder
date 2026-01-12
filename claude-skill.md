# audio-recorder skill

Use audio-recorder CLI to record, transcribe and summarize audio.

## Commands

```bash
audio-recorder start                     # Start recording (mic + system audio)
audio-recorder stop                      # Stop → auto transcribe → summarize
audio-recorder stop --only               # Stop without processing
audio-recorder stop --comment "context"  # Stop with context for AI summary
audio-recorder status                    # Show recording status & duration

audio-recorder transcribe [folder]       # Transcribe only
audio-recorder summarize [folder]        # Summarize only
audio-recorder summarize -c "context"    # Summarize with user context

audio-recorder list                      # List all recordings with status
audio-recorder open [folder]             # Open folder in file manager
audio-recorder setup                     # Configure HF token & recordings dir
```

## Output structure

Each recording creates a folder in `~/Recordings/`:
```
~/Recordings/
└── meeting_name/
    ├── audio.mp3         # Original recording
    ├── transcript.txt    # WhisperX transcription with speaker diarization
    └── summary.md        # AI summary with highlights & notes
```

## Workflow

1. **Start**: `audio-recorder start` - begins recording mic + system audio
2. **Stop**: `audio-recorder stop` - stops and auto-processes (transcribe + summarize)
3. **Review**: Opens summary.md with highlights, notes, and action items
4. **Rename**: Prompts to rename folder with descriptive name

## Tips

- Use `--comment` to provide context: `audio-recorder stop --comment "Meeting with John about Q1 budget"`
- Use `--only` to just stop without processing: `audio-recorder stop --only`
- Check status during recording: `audio-recorder status` shows elapsed time
- Reprocess existing recordings: `audio-recorder transcribe folder` then `audio-recorder summarize folder`
