# audio-recorder

CLI bash pour enregistrer des réunions, transcrire (WhisperX) et générer des minutes (Claude).

## Installation

```bash
./install.sh           # symlink ~/.local/bin, vérifie ffmpeg/whisperx/claude
audio-recorder setup   # configure HF_TOKEN, RECORDINGS_DIR, WHISPER_MODEL, LOCAL_SPEAKER,
                       # WHISPER_LANGUAGE, WHISPER_INITIAL_PROMPT, TULS_API_TOKEN
```

WhisperX utilise pyannote pour la diarization : token HuggingFace (Read) requis, et
il faut accepter les conditions de `pyannote/speaker-diarization-community-1` (modèle
par défaut de whisperx ≥ 3.8) sur huggingface.co avant le premier `setup`.
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
- Deux pistes : le micro est enregistré à gauche, l'audio système à droite (tag mp3
  `comment=audio-recorder:L=mic,R=system`). À la transcription, chaque canal est
  normalisé à part avant le downmix (le monitor suit le volume de sortie), puis
  `lib/transcript.py` attribue à `LOCAL_SPEAKER` les segments où le micro est actif
  (par trames de 100 ms, au-dessus de son bruit de fond et de la fuite des
  haut-parleurs mesurée sur l'enregistrement) — pyannote ne départage plus que les
  distants. Sans audio distant (réunion en présentiel), diarization seule ; en
  hybride, toute la salle est attribuée à `LOCAL_SPEAKER`. Les anciens
  enregistrements (mixés) gardent la diarization seule.
- Détection audio : Linux suit le sink/source par défaut (`pactl`). Bluetooth sans cas
  particulier : le monitor du sink bluez capte en A2DP comme en HFP, et WirePlumber
  bascule seul en HFP quand le micro du casque s'ouvre puis revient en A2DP. macOS passe
  par AVFoundation + Background Music. Auto-unmute du micro s'il est muté.
- `WHISPER_INITIAL_PROMPT` : vocabulaire (noms, produits, sigles) passé en amorce à
  Whisper — corrige les mots mal entendus (« Cloud » pour « Claude »).
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
