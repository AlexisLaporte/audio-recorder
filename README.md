<p align="center">
  <h1 align="center">🎙️ audio-recorder</h1>
  <p align="center">
    <strong>Record meetings. Get AI summaries. Never take notes again.</strong>
  </p>
  <p align="center">
    <a href="https://github.com/AlexisLaporte/audio-recorder/releases"><img src="https://img.shields.io/github/v/release/AlexisLaporte/audio-recorder?style=flat-square" alt="Release"></a>
    <a href="https://github.com/AlexisLaporte/audio-recorder/blob/master/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License"></a>
    <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey?style=flat-square" alt="Platform">
  </p>
</p>

---

Two commands. That's it.

```bash
audio-recorder start    # Start recording
audio-recorder stop     # Get your summary
```

<br>

## ✨ Features

| | |
|---|---|
| 🎤 **Capture Everything** | Records microphone + system audio simultaneously |
| 🗣️ **Speaker Identification** | Knows who said what with automatic diarization |
| 🤖 **AI Summaries** | Highlights, key decisions, and action items extracted automatically |
| 📁 **Smart Organization** | Auto-suggests descriptive folder names based on content |
| ⚡ **One Command** | Stop recording → transcribe → summarize, all automatic |
| 🎨 **Customizable** | Edit the prompt template to get summaries your way |

<br>

## 🎬 How It Works

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Record    │ ───▶ │ Transcribe  │ ───▶ │  Summarize  │
│   (ffmpeg)  │      │ (WhisperX)  │      │  (Claude)   │
└─────────────┘      └─────────────┘      └─────────────┘
     audio.mp3      transcript.txt         summary.md
```

**What you get:**

```
~/Recordings/q1_budget_review/
├── audio.mp3              # Original recording
├── transcript.txt         # Full transcript with speakers
└── summary.md             # AI-generated summary
```

**Example summary:**

```markdown
# Q1 Budget Review - Finance Team

## Highlights
- Marketing budget increased 20% for Q2 campaign
- Engineering headcount frozen until Q3
- New vendor contract saves $50k/year

## Summary
The finance team reviewed Q1 performance and approved budget
adjustments for Q2. Main discussion focused on reallocating
resources from engineering to marketing...

## Action Items
- [ ] Sarah: Send revised projections by Friday
- [ ] Mike: Schedule follow-up with procurement
```

<br>

## 📦 Installation

### Quick Install

```bash
curl -sL https://github.com/AlexisLaporte/audio-recorder/releases/latest/download/install.sh | bash
```

### Manual Install

```bash
git clone https://github.com/AlexisLaporte/audio-recorder.git
cd audio-recorder
./install.sh
```

### Setup

```bash
audio-recorder setup
```

You'll need a [HuggingFace token](https://huggingface.co/settings/tokens) and to accept conditions for:
- [pyannote/speaker-diarization-3.1](https://hf.co/pyannote/speaker-diarization-3.1)
- [pyannote/segmentation-3.0](https://hf.co/pyannote/segmentation-3.0)

<br>

## 🚀 Usage

### Basic Workflow

```bash
# Start recording before your meeting
audio-recorder start

# When done, stop and get your summary
audio-recorder stop
```

### Add Context for Better Results

```bash
audio-recorder stop --comment "1-on-1 with John about his promotion timeline"
```

The AI uses your context to generate more relevant summaries.

### All Commands

| Command | Description |
|---------|-------------|
| `audio-recorder start` | Start recording |
| `audio-recorder stop` | Stop + transcribe + summarize |
| `audio-recorder stop --only` | Stop without processing |
| `audio-recorder stop -c "..."` | Stop with context for AI |
| `audio-recorder status` | Show recording duration |
| `audio-recorder list` | List all recordings |
| `audio-recorder open [name]` | Open folder in file manager |
| `audio-recorder transcribe [name]` | Re-transcribe a recording |
| `audio-recorder summarize [name]` | Re-summarize a recording |
| `audio-recorder setup` | Configure settings |

<br>

## 🎨 Customization

### Change Summary Format

Edit `~/Recordings/summarize-prompt.md` to customize:
- Summary structure and sections
- Level of detail
- Language and tone
- What to extract (action items, decisions, etc.)

### Change Output Directory

```bash
audio-recorder setup
# Then enter your preferred directory
```

<br>

## 💻 Platform Support

### Linux
Works out of the box with PulseAudio. Captures both microphone and system audio.

### macOS
Requires [BlackHole](https://github.com/ExistentialAudio/BlackHole) for system audio capture:

```bash
brew install blackhole-2ch
```

Then create a Multi-Output Device in Audio MIDI Setup to route system audio through BlackHole.

<br>

## 🔧 Requirements

| Dependency | Purpose |
|------------|---------|
| [ffmpeg](https://ffmpeg.org/) | Audio recording |
| [WhisperX](https://github.com/m-bain/whisperX) | Transcription + speaker diarization |
| [Claude Code](https://github.com/anthropics/claude-code) | AI summaries |

The installer checks for these and helps you install missing dependencies.

<br>

## 🤝 Contributing

Contributions welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests

<br>

## 📄 License

MIT © [Alexis Laporte](https://github.com/AlexisLaporte)

---

<p align="center">
  <sub>Built for people who'd rather listen than write.</sub>
</p>
