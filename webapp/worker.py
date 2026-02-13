"""Audio recorder worker: poll tuls API, transcribe with WhisperX, summarize with Claude."""

import json
import os
import subprocess
import sys
import tempfile
import time

import anthropic
import requests

# Config
TULS_API = os.environ.get('TULS_API', 'https://tuls.me')
WORKER_TOKEN = os.environ['AUDIO_WORKER_TOKEN']
ANTHROPIC_API_KEY = os.environ['ANTHROPIC_API_KEY']
HF_TOKEN = os.environ.get('HF_TOKEN')  # for pyannote diarization
SCW_SECRET_KEY = os.environ.get('SCW_SECRET_KEY')
SCW_SERVER_ID = os.environ.get('SCW_SERVER_ID')
SCW_ZONE = os.environ.get('SCW_ZONE', 'fr-par-1')

POLL_INTERVAL = 5  # seconds
IDLE_SHUTDOWN_MINUTES = 10
CLAUDE_MODEL = 'claude-sonnet-4-5-20250929'

HEADERS = {
    'Authorization': f'Bearer {WORKER_TOKEN}',
    'Content-Type': 'application/json',
}

SUMMARY_PROMPT = """You are analyzing a transcribed audio recording. Generate a structured summary in markdown format.

## Output Format

# [Short descriptive title]

## Highlights
- Key point 1
- Key point 2
- Key point 3
(3-5 bullet points capturing the most important takeaways)

## Summary
Brief 2-3 paragraph overview of the conversation/recording.

## Notes
Condensed version of the exchange, capturing the flow and key moments:

- **[Speaker/Topic]**: Main point or statement
- **[Speaker/Topic]**: Response or follow-up

(Keep it concise but preserve the logical flow of the discussion)

## Action Items
- [ ] Task 1 (if any)
- [ ] Task 2 (if any)
(Only include if actionable items were mentioned)

## Guidelines
- Be concise and factual
- Preserve speaker attributions when relevant
- Focus on substance over pleasantries
- Use bullet points for readability"""


def poll_job():
    """Get the next pending job from tuls API."""
    try:
        resp = requests.get(f'{TULS_API}/api/audio/pending', headers=HEADERS, timeout=15)
        if resp.status_code != 200:
            print(f'[poll] HTTP {resp.status_code}')
            return None
        data = resp.json()
        return data.get('job')
    except Exception as e:
        print(f'[poll] Error: {e}')
        return None


def update_status(job_id, status):
    """Update job status on tuls."""
    try:
        requests.put(
            f'{TULS_API}/api/audio/{job_id}/status',
            headers=HEADERS, json={'status': status}, timeout=10,
        )
    except Exception as e:
        print(f'[status] Error: {e}')


def download_audio(job):
    """Download audio file from tuls, return local path."""
    url = f'{TULS_API}{job["download_url"]}'
    resp = requests.get(url, headers=HEADERS, timeout=300, stream=True)
    resp.raise_for_status()

    suffix = os.path.splitext(job.get('original_filename', 'audio.mp3'))[1]
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    for chunk in resp.iter_content(chunk_size=8192):
        tmp.write(chunk)
    tmp.close()
    return tmp.name


def transcribe(audio_path):
    """Run WhisperX transcription with diarization. Returns (transcript_text, duration_seconds)."""
    output_dir = tempfile.mkdtemp()

    cmd = [
        sys.executable, '-m', 'whisperx',
        audio_path,
        '--model', 'large-v3',
        '--output_dir', output_dir,
        '--output_format', 'json',
        '--language', 'fr',
        '--compute_type', 'float16',
    ]
    if HF_TOKEN:
        cmd += ['--diarize', '--hf_token', HF_TOKEN]

    print(f'[whisperx] Running: {" ".join(cmd[:6])}...')
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=3600)
    if result.returncode != 0:
        raise RuntimeError(f'WhisperX failed: {result.stderr[-500:]}')

    # Find the JSON output
    base = os.path.splitext(os.path.basename(audio_path))[0]
    json_path = os.path.join(output_dir, f'{base}.json')
    if not os.path.exists(json_path):
        # Try finding any json in output
        for f in os.listdir(output_dir):
            if f.endswith('.json'):
                json_path = os.path.join(output_dir, f)
                break

    with open(json_path) as f:
        data = json.load(f)

    # Build transcript text from segments
    lines = []
    for seg in data.get('segments', []):
        speaker = seg.get('speaker', '')
        text = seg.get('text', '').strip()
        start = seg.get('start', 0)
        mm, ss = divmod(int(start), 60)
        prefix = f'[{mm:02d}:{ss:02d}]'
        if speaker:
            prefix += f' {speaker}:'
        lines.append(f'{prefix} {text}')

    transcript = '\n'.join(lines)

    # Duration from last segment
    duration = 0
    if data.get('segments'):
        last_seg = data['segments'][-1]
        duration = last_seg.get('end', last_seg.get('start', 0))

    return transcript, duration


def summarize(transcript):
    """Summarize transcript using Claude API."""
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

    message = client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=4096,
        messages=[{
            'role': 'user',
            'content': f'{SUMMARY_PROMPT}\n\n---\n\nHere is the transcript:\n\n{transcript}',
        }],
    )
    return message.content[0].text


def push_result(job_id, transcript=None, summary=None, duration_seconds=None, error=None):
    """Push results back to tuls API with retries."""
    payload = {}
    if error:
        payload['error'] = str(error)
    else:
        payload['transcript'] = transcript
        payload['summary'] = summary
        payload['duration_seconds'] = duration_seconds

    for attempt in range(5):
        try:
            resp = requests.put(
                f'{TULS_API}/api/audio/{job_id}/result',
                headers=HEADERS, json=payload, timeout=30,
            )
            print(f'[result] {resp.status_code}: {resp.json()}')
            if resp.status_code < 500:
                return
        except Exception as e:
            print(f'[result] Attempt {attempt + 1}/5 failed: {e}')
        time.sleep(2 ** attempt)  # 1s, 2s, 4s, 8s, 16s

    print(f'[result] FAILED after 5 attempts for job {job_id}')


def shutdown_self():
    """Shutdown this Scaleway instance. Tries API first, falls back to OS shutdown."""
    if not SCW_SECRET_KEY or not SCW_SERVER_ID:
        print('[shutdown] No SCW credentials, using OS shutdown')
        subprocess.run(['shutdown', '-h', 'now'])
        return

    api = f'https://api.scaleway.com/instance/v1/zones/{SCW_ZONE}'
    headers = {'X-Auth-Token': SCW_SECRET_KEY}
    try:
        resp = requests.post(
            f'{api}/servers/{SCW_SERVER_ID}/action',
            headers=headers, json={'action': 'poweroff'}, timeout=10,
        )
        if resp.status_code < 300:
            print('[shutdown] Poweroff command sent via API')
            return
        print(f'[shutdown] API returned {resp.status_code}, falling back to OS shutdown')
    except Exception as e:
        print(f'[shutdown] API error: {e}, falling back to OS shutdown')

    subprocess.run(['shutdown', '-h', 'now'])


def process_job(job):
    """Process a single job: download → transcribe → summarize → push."""
    job_id = job['id']
    audio_path = None

    try:
        print(f'[job {job_id}] Downloading audio...')
        audio_path = download_audio(job)
        print(f'[job {job_id}] Downloaded: {audio_path}')

        print(f'[job {job_id}] Transcribing...')
        transcript, duration = transcribe(audio_path)
        print(f'[job {job_id}] Transcribed: {len(transcript)} chars, {duration:.1f}s')

        update_status(job_id, 'summarizing')

        print(f'[job {job_id}] Summarizing...')
        summary = summarize(transcript)
        print(f'[job {job_id}] Summary: {len(summary)} chars')

        push_result(job_id, transcript=transcript, summary=summary, duration_seconds=duration)

    except Exception as e:
        print(f'[job {job_id}] Error: {e}')
        push_result(job_id, error=str(e))

    finally:
        if audio_path and os.path.exists(audio_path):
            os.remove(audio_path)


def main():
    """Main worker loop: poll for jobs, process, shutdown after idle timeout."""
    print(f'[worker] Starting. API={TULS_API}, shutdown after {IDLE_SHUTDOWN_MINUTES}min idle')
    last_job_time = time.time()

    while True:
        job = poll_job()

        if job:
            last_job_time = time.time()
            process_job(job)
        else:
            idle_minutes = (time.time() - last_job_time) / 60
            if idle_minutes >= IDLE_SHUTDOWN_MINUTES:
                print(f'[worker] Idle for {idle_minutes:.0f}min, shutting down...')
                shutdown_self()
                break

        time.sleep(POLL_INTERVAL)


if __name__ == '__main__':
    main()
