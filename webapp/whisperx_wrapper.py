"""Wrapper to fix PyTorch 2.6+ weights_only issue with WhisperX."""
import sys
print('[wrapper] Patching torch.load...', file=sys.stderr, flush=True)

import torch

_original_load = torch.load

def _patched_load(*args, **kwargs):
    kwargs['weights_only'] = False
    return _original_load(*args, **kwargs)

torch.load = _patched_load

# Also patch at module level in case libraries use from-import
import torch.serialization
torch.serialization.load = _patched_load

print(f'[wrapper] Patched. torch.load is patched={torch.load is _patched_load}', file=sys.stderr, flush=True)

from whisperx.__main__ import cli
cli()
