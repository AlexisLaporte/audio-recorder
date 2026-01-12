# 🎙️ audio-recorder

**Never take meeting notes again.** Record any conversation, get a structured summary with key takeaways in seconds.

```bash
audio-recorder start   # Hit record
# ... have your meeting ...
audio-recorder stop    # Get instant AI summary
```

## Why?

- 📝 **Meetings disappear** → Now you have searchable transcripts with speaker identification
- ⏱️ **Note-taking kills focus** → Stay present, let AI capture everything
- 📋 **Action items get lost** → Structured summaries with highlights & tasks
- 🔍 **"What did we decide?"** → Revisit any conversation instantly

## What You Get

```
~/Recordings/q1_budget_review/
├── audio.mp3           # Original recording
├── transcript.txt      # Full transcript with [SPEAKER_00], [SPEAKER_01]...
└── summary.md          # AI summary 👇
```

```markdown
# Q1 Budget Review - Finance Team

## Highlights
- Marketing budget increased 20% for Q2 campaign
- Engineering headcount frozen until Q3
- New vendor contract saves $50k/year

## Action Items
- [ ] Sarah: Send revised projections by Friday
- [ ] Mike: Schedule follow-up with procurement
```

## Install

```bash
# One-liner
curl -sL https://github.com/AlexisLaporte/audio-recorder/releases/latest/download/install.sh | bash

# Or clone
git clone https://github.com/AlexisLaporte/audio-recorder.git
cd audio-recorder && ./install.sh
```

Then configure:
```bash
audio-recorder setup
```

## Commands

| Command | What it does |
|---------|--------------|
| `start` | Start recording (captures mic + system audio) |
| `stop` | Stop → transcribe → summarize (all automatic) |
| `stop -c "context"` | Add context for better summaries |
| `stop --only` | Just stop, process later |
| `status` | Show recording time |
| `list` | Browse all recordings |
| `open` | Open folder in file manager |

## Add Context for Better Summaries

```bash
audio-recorder stop --comment "Weekly sync with design team about mobile app redesign"
```

The AI uses your context to generate more relevant summaries and suggest better folder names.

## Customize

Edit `~/Recordings/summarize-prompt.md` to change how summaries are generated. Want bullet points? A different structure? More detail? Less? Make it yours.

## Requirements

- **Linux** (PulseAudio) or **macOS** (+ [BlackHole](https://github.com/ExistentialAudio/BlackHole) for system audio)
- [ffmpeg](https://ffmpeg.org/)
- [whisperx](https://github.com/m-bain/whisperX) + HuggingFace token
- [claude](https://github.com/anthropics/claude-code)

## License

MIT
