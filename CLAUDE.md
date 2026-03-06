# audio-recorder

CLI pour enregistrer des réunions et transcrire (WhisperX avec diarization).

## Installation

Quand l'utilisateur demande d'installer ou setup, suis ces étapes :

### 1. Lancer install.sh

```bash
./install.sh
```

Ça crée un symlink dans `~/.local/bin/` et vérifie les dépendances (ffmpeg, whisperx). Les libs sont chargées directement depuis le repo.

### 2. HuggingFace Token

WhisperX utilise pyannote pour identifier les speakers. Il faut un token HuggingFace.

**Étapes à expliquer à l'utilisateur :**

1. Créer un compte sur https://huggingface.co si pas déjà fait
2. Aller sur https://huggingface.co/settings/tokens
3. Créer un token (Read access suffit)
4. Accepter les conditions sur ces pages (bouton "Agree") :
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/speaker-diarization-community-1
   - https://huggingface.co/pyannote/segmentation-3.0
5. Lancer `audio-recorder setup` et coller le token

### 3. macOS uniquement

Pour capturer l'audio système (pas seulement le micro), installer :

```bash
brew install --cask background-music
```

### 4. Test

```bash
audio-recorder start
# Attendre quelques secondes
audio-recorder stop --only  # Stop sans processing pour tester
```

## Utilisation

```bash
audio-recorder start              # Démarre l'enregistrement
audio-recorder stop               # Stop → prompt transcription → prompt nb speakers → transcrit
audio-recorder stop --only        # Stop sans processing
audio-recorder status             # Durée en cours
audio-recorder list               # Liste les enregistrements
audio-recorder transcribe [nom]   # Re-transcrire un enregistrement
audio-recorder transcribe /path   # Transcrire un fichier audio/vidéo (extraction auto)
```

Après `stop`, le CLI demande interactivement :
1. **Transcrire maintenant ? [Y/n]** — n pour arrêter là
2. **Combien de speakers ? [auto]** — Enter pour auto-detect, ou un nombre

Les transcripts sont dans `~/Recordings/recording_YYYYMMDD_HHMMSS/transcript.txt`.

## Configuration

```bash
audio-recorder setup
```

- `HF_TOKEN` : Token HuggingFace pour WhisperX
- `RECORDINGS_DIR` : Dossier des enregistrements (défaut: `~/Recordings`)

## Structure

```
lib/
├── config.sh      # Configuration
├── utils.sh       # Helpers (colors, spinner, notify)
├── audio.sh       # Enregistrement (ffmpeg) + flow stop interactif
└── transcribe.sh  # Transcription (whisperx, supporte --min/max_speakers)
```

## Dev

```bash
make lint   # shellcheck
make test   # bats
```
