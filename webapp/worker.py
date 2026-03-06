"""GPU worker: poll tuls API for jobs, dispatch to handlers (WhisperX, Ollama)."""

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
HEARTBEAT_FILE = '/tmp/worker-heartbeat'

HEADERS = {
    'Authorization': f'Bearer {WORKER_TOKEN}',
    'Content-Type': 'application/json',
}


# ── Job handlers ──


def handle_transcribe(job):
    """Download audio, run WhisperX, return transcript + duration."""
    audio_path = None
    try:
        audio_path = download_file(job)
        language = job['input_data'].get('language', 'fr')
        transcript, duration = transcribe(audio_path, language)
        return {'transcript': transcript, 'duration_seconds': duration}
    finally:
        if audio_path and os.path.exists(audio_path):
            os.remove(audio_path)


def handle_llm_call(job):
    """Call Claude API, return generated text."""
    text = job['input_data']['text']
    prompt = job['input_data']['prompt']
    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
    message = client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=4096,
        messages=[{'role': 'user', 'content': f'{prompt}\n\n---\n\n{text}'}],
    )
    return {'text': message.content[0].text}


HANDLERS = {
    'transcribe': handle_transcribe,
    'llm_call': handle_llm_call,
}


# ── Core functions ──


def poll_job():
    """Get the next pending job from tuls API."""
    try:
        resp = requests.get(f'{TULS_API}/api/worker/jobs/next', headers=HEADERS, timeout=15)
        if resp.status_code != 200:
            print(f'[poll] HTTP {resp.status_code}')
            return None
        data = resp.json()
        return data.get('job')
    except Exception as e:
        print(f'[poll] Error: {e}')
        return None


def download_file(job):
    """Download file attached to a job, return local path."""
    # Build download URL from job input_data or default pattern
    download_url = f'/api/worker/jobs/{job["id"]}/download/audio'
    url = f'{TULS_API}{download_url}'
    resp = requests.get(url, headers=HEADERS, timeout=300, stream=True)
    resp.raise_for_status()

    suffix = '.mp3'  # default
    cd = resp.headers.get('Content-Disposition', '')
    if 'filename=' in cd:
        fname = cd.split('filename=')[-1].strip('"')
        suffix = os.path.splitext(fname)[1] or suffix

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    for chunk in resp.iter_content(chunk_size=8192):
        tmp.write(chunk)
    tmp.close()
    return tmp.name


def transcribe(audio_path, language='fr'):
    """Run WhisperX transcription with diarization. Returns (transcript_text, duration_seconds)."""
    output_dir = tempfile.mkdtemp()

    wrapper = os.path.join(os.path.dirname(__file__), 'whisperx_wrapper.py')
    cmd = [
        sys.executable, wrapper,
        audio_path,
        '--model', 'large-v3',
        '--output_dir', output_dir,
        '--output_format', 'json',
        '--language', language,
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


def push_result(job_id, output_data=None, error=None):
    """Push results back to tuls API with retries."""
    payload = {}
    if error:
        payload['error'] = str(error)
    else:
        payload['output_data'] = output_data

    for attempt in range(5):
        try:
            resp = requests.put(
                f'{TULS_API}/api/worker/jobs/{job_id}/result',
                headers=HEADERS, json=payload, timeout=30,
            )
            print(f'[result] {resp.status_code}: {resp.json()}')
            if resp.status_code < 500:
                return
        except Exception as e:
            print(f'[result] Attempt {attempt + 1}/5 failed: {e}')
        time.sleep(2 ** attempt)

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
    """Process a single job using the appropriate handler."""
    job_id = job['id']
    job_type = job['type']
    handler = HANDLERS.get(job_type)

    if not handler:
        print(f'[job {job_id}] Unknown job type: {job_type}')
        push_result(job_id, error=f'Unknown job type: {job_type}')
        return

    try:
        print(f'[job {job_id}] Processing {job_type}...')
        output_data = handler(job)
        print(f'[job {job_id}] Done: {list(output_data.keys())}')
        push_result(job_id, output_data=output_data)
    except Exception as e:
        print(f'[job {job_id}] Error: {e}')
        push_result(job_id, error=str(e))


def touch_heartbeat():
    """Write current timestamp to heartbeat file for cron idle detection."""
    with open(HEARTBEAT_FILE, 'w') as f:
        f.write(str(time.time()))


def main():
    """Main worker loop: poll for jobs, process, shutdown after idle timeout."""
    print(f'[worker] Starting. API={TULS_API}, shutdown after {IDLE_SHUTDOWN_MINUTES}min idle')
    last_job_time = time.time()
    touch_heartbeat()

    while True:
        job = poll_job()

        if job:
            last_job_time = time.time()
            touch_heartbeat()
            process_job(job)
            touch_heartbeat()
        else:
            idle_minutes = (time.time() - last_job_time) / 60
            if idle_minutes >= IDLE_SHUTDOWN_MINUTES:
                print(f'[worker] Idle for {idle_minutes:.0f}min, shutting down...')
                shutdown_self()
                break

        time.sleep(POLL_INTERVAL)


if __name__ == '__main__':
    main()
