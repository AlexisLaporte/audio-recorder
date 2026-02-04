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

### Enregistrer

```bash
audio-recorder start              # Démarre l'enregistrement
audio-recorder stop               # Stop + transcription + lance Claude interactif
audio-recorder stop --only        # Stop sans processing
audio-recorder status             # Durée en cours
audio-recorder list               # Liste les enregistrements
```

### Synthèse interactive

Après transcription, le script demande "Demander contexte à Claude ? [Y/n]" puis lance Claude en mode interactif depuis `~/Recordings/`.

- **Y (défaut)** : Claude demande d'abord le contexte (client, projet) avant de synthétiser
- **n** : Claude synthétise directement sans poser de question

Claude peut ensuite :
1. Chercher le dossier CRM correspondant dans `CONTEXT_BASE_DIR`
2. Générer un résumé structuré
3. Mettre à jour le CRM si pertinent

### Transcrire un fichier existant

L'outil peut transcrire n'importe quel fichier audio/vidéo (mp3, mp4, wav, etc.) :

```bash
audio-recorder transcribe /chemin/vers/fichier.mp4
audio-recorder transcribe ~/Téléchargements/meeting.mp3
```

Le transcript est créé dans le même dossier que le fichier source (`fichier_transcript.txt`).

### Re-traiter un enregistrement

```bash
audio-recorder transcribe [nom]   # Re-transcrire
audio-recorder summarize [nom]    # Lance Claude pour synthèse
audio-recorder summarize -n [nom] # Synthèse sans demander contexte
```

## Configuration

```bash
audio-recorder setup
```

Options :
- `HF_TOKEN` : Token HuggingFace pour WhisperX
- `RECORDINGS_DIR` : Dossier des enregistrements (défaut: `~/Recordings`)
- `CONTEXT_BASE_DIR` : Dossier de base pour le contexte CRM/projets (défaut: `$HOME`)

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
