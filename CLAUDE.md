# audio-recorder

CLI pour enregistrer des réunions, transcrire (WhisperX) et résumer (Claude).

## Installation

Quand l'utilisateur demande d'installer ou setup, suis ces étapes :

### 1. Lancer install.sh

```bash
./install.sh
```

Ça installe le script et vérifie les dépendances (ffmpeg, whisperx).

### 2. HuggingFace Token

WhisperX utilise pyannote pour identifier les speakers. Il faut un token HuggingFace.

**Étapes à expliquer à l'utilisateur :**

1. Créer un compte sur https://huggingface.co si pas déjà fait
2. Aller sur https://huggingface.co/settings/tokens
3. Créer un token (Read access suffit)
4. Accepter les conditions sur ces 2 pages (bouton "Agree") :
   - https://huggingface.co/pyannote/speaker-diarization-3.1
   - https://huggingface.co/pyannote/segmentation-3.0
5. Lancer `audio-recorder setup` et coller le token

### 3. macOS uniquement

Pour capturer l'audio système (pas seulement le micro), installer :

```bash
brew install --cask background-music
```

Alternative : `brew install blackhole-2ch` (nécessite config Audio MIDI Setup).

### 4. Test

```bash
audio-recorder start
# Attendre quelques secondes
audio-recorder stop --only  # Stop sans processing pour tester
```

## Utilisation

```bash
audio-recorder start              # Démarre l'enregistrement
audio-recorder stop               # Stop + transcription + résumé
audio-recorder stop -c "contexte" # Avec contexte pour le résumé
audio-recorder status             # Durée en cours
audio-recorder list               # Liste les enregistrements
audio-recorder transcribe [nom]   # Re-transcrire
audio-recorder summarize [nom]    # Re-résumer
```

## Structure

```
lib/
├── config.sh      # Configuration
├── utils.sh       # Helpers (colors, spinner, notify)
├── audio.sh       # Enregistrement (ffmpeg)
├── transcribe.sh  # Transcription (whisperx)
└── summarize.sh   # Résumé (claude)
```

## Dev

```bash
make lint   # shellcheck
make test   # bats
```
