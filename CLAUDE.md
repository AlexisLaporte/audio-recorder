# audio-recorder

CLI bash pour enregistrer des réunions, transcrire (WhisperX) et générer des minutes (Claude).

## Installation

```bash
./install.sh           # symlink ~/.local/bin, vérifie ffmpeg/whisperx/claude
audio-recorder setup   # configure HF_TOKEN, RECORDINGS_DIR, WHISPER_MODEL, TULS_API_TOKEN
```

WhisperX utilise pyannote pour la diarization : token HuggingFace (Read) requis, et
il faut accepter les conditions de `pyannote/speaker-diarization-3.1` et
`pyannote/segmentation-3.0` sur huggingface.co avant le premier `setup`.
macOS : `brew install --cask background-music` pour capter l'audio système.

## Utilisation

```bash
audio-recorder start                   # démarre l'enregistrement
audio-recorder stop                    # stop → transcription → minutes → renommage dossier
audio-recorder stop --only             # stop sans processing
audio-recorder stop --trim             # stop → trim auto → transcription → minutes
audio-recorder status / list           # durée en cours / liste des enregistrements
audio-recorder trim [folder]           # analyse silences → découpe auto (alias: cut)
audio-recorder transcribe [nom|/path]  # (re-)transcrire un enregistrement ou fichier
audio-recorder summarize [folder]      # minutes + renommage dossier
audio-recorder push [folder]           # pousser vers tuls.me (--with-audio pour le mp3)
```

## Pièges

- `summarize` cherche un `CLAUDE.md` en remontant les dossiers parents et le passe à
  Claude comme contexte (noms d'équipe, terminologie, objectifs) — un projet sans
  CLAUDE.md produit des minutes plus génériques.
- Trim : détecte les silences >3s en un seul pass ffmpeg, cherche le premier silence
  ≥10s après 5 min (fallback : rupture de densité) ; l'original est toujours gardé en
  `audio_full.mp3`.
- Détection audio : Linux suit le sink/source actif (`pactl`, BT inclus) ; macOS passe
  par AVFoundation + Background Music. Auto-unmute si le mic est muté ou < 50 %.
  Watchdog toutes les 2 min : notification desktop si le niveau capté est < -60 dB.
- `summarize` refuse un transcript < 2 lignes ; le renommage de dossier est contraint
  à `[a-z0-9_]`, 50 caractères max, sinon laissé tel quel.
- `push` vers `audio-recorder-transcript.tuls.me` (doc : https://tuls.me/api/docs/) ou
  `oto audio push/list/get/delete/summarize` — `TULS_API_TOKEN` vit dans
  `~/.config/audio-recorder/config` (posé par `audio-recorder setup`).

## Dev

```bash
make lint   # shellcheck
make test   # bats
```
</content>
