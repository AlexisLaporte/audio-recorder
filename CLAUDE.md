# audio-recorder

CLI bash pour enregistrer des réunions, transcrire (WhisperX) et générer des minutes (Claude).

## Installation

### 1. Lancer install.sh

```bash
./install.sh
```

Symlink dans `~/.local/bin/`, vérifie les dépendances (ffmpeg, whisperx, claude).

### 2. HuggingFace Token

WhisperX utilise pyannote pour la diarization. Token HuggingFace requis.

1. Créer un compte sur https://huggingface.co
2. Créer un token (Read) sur https://huggingface.co/settings/tokens
3. Accepter les conditions :
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
4. `audio-recorder setup` et coller le token

### 3. macOS uniquement

```bash
brew install --cask background-music
```

### 4. Test

```bash
audio-recorder start
audio-recorder stop --only  # Stop sans processing
```

## Utilisation

```bash
audio-recorder start              # Démarre l'enregistrement
audio-recorder stop               # Stop → transcription → minutes → renommage dossier
audio-recorder stop --only        # Stop sans processing
audio-recorder status             # Durée en cours
audio-recorder list               # Liste les enregistrements
audio-recorder transcribe [nom]   # Re-transcrire un enregistrement
audio-recorder transcribe /path   # Transcrire un fichier audio/vidéo
audio-recorder summarize [folder] # Générer minutes + renommer dossier
audio-recorder open [folder]      # Ouvrir le dossier
audio-recorder setup              # Configurer
```

### Flow `stop`
1. **Transcrire ? [Y/n]** → WhisperX transcription avec diarization
2. **Combien de speakers ? [auto]** → auto-detect ou nombre
3. **Minutes** → `claude -p` génère `summary.md` automatiquement
4. **Renommage** → `claude -p` propose un nom descriptif, dossier renommé en `YYYYMMDD_nom`

## Configuration

```bash
audio-recorder setup
```

- `HF_TOKEN` : Token HuggingFace pour WhisperX
- `RECORDINGS_DIR` : Dossier des enregistrements (défaut: `~/Recordings`)
- `WHISPER_MODEL` : Modèle WhisperX (tiny/base/small/medium/large-v2/large-v3, défaut: `large-v3`)

## Structure

```
lib/
├── config.sh      # Configuration + setup interactif
├── utils.sh       # Helpers (colors, spinner, notify)
├── audio.sh       # Enregistrement ffmpeg (pulse/avfoundation) + flow stop
├── transcribe.sh      # Transcription WhisperX avec diarization
├── summarize.sh       # Minutes via claude -p + renommage dossier
└── prompt_minutes.md  # System prompt pour la génération de minutes
```

## Audio source detection

- **Linux** : `pactl get-default-sink/source` (suit le device actif, BT inclus)
- **macOS** : AVFoundation, préfère Background Music pour le system audio
- Au start : affiche le mode (`🎧 Bluetooth` ou `🔊 Speakers + Mic`) + noms des devices
- Auto-unmute : si le mic est muté ou volume < 50%, corrige automatiquement au start
- **Watchdog** : toutes les 2 min, vérifie le volume du fichier audio en cours. Si < -60dB, envoie une notification desktop

## Garde-fous

- `summarize` refuse de traiter un transcript < 2 lignes
- Le rename de dossier est contraint : `[a-z0-9_]` uniquement, max 50 chars, sinon skip

## Dev

```bash
make lint   # shellcheck
make test   # bats
```
