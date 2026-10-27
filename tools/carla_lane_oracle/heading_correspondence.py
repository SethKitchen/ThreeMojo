# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow fresh/proof SPIRAL heading graph correspondence.

Complete module tokens and stored-helper dependencies are checked separately.
This projection expands only the fresh local k0 constant and specializes its
Expression name to the full Jet alias. It never projects ideal u or eligibility
into a scalar-heading proof and does not claim arbitrary error equivalence.
"""
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

import json
_CONSUMERS = None


def _consumers():
    """Return the three heading consumers in reviewed order."""
    global _CONSUMERS
    if _CONSUMERS is not None:
        return _CONSUMERS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_heading_consumers'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CONSUMERS = json.loads(result.stdout)
    return _CONSUMERS


def __getattr__(name):
    if name == 'CONSUMERS':
        return _consumers()
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def _heading_graph(fresh, consumers, eligibility):
    """Compare the fresh heading graph with each stored consumer."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({
        'fresh': fresh,
        'consumers': [
            {'file': filename, 'name': name, 'text': text}
            for filename, name, text in consumers
        ],
        'eligibility': eligibility,
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='heading-graph-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--heading', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _heading_result(consumers):
    """Return the heading correspondence result for `consumers` entries."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({'consumers': consumers}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='heading-result-') as directory:
        path = Path(directory) / 'result.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_heading_result',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def verify(root, *, _operation=None):
    path = root/'extensions/carla'
    fresh = _typed_source.historical_text(root, path/'curve_bounds.mojo', source._observe_text(root, 'extensions/carla/curve_bounds.mojo', (path/'curve_bounds.mojo').read_text(), _operation=_operation), _operation=_operation)
    consumers = []
    for filename, name in _consumers().items():
        consumers.append((filename, name, _typed_source.historical_text(root, path/filename, source._observe_text(root, 'extensions/carla/' + filename, (path/filename).read_text(), _operation=_operation), _operation=_operation)))
    eligibility = _typed_source.historical_text(root, path/'spiral_moment_proof.mojo', source._observe_text(root, 'extensions/carla/spiral_moment_proof.mojo', (path/'spiral_moment_proof.mojo').read_text(), _operation=_operation), _operation=_operation)
    _heading_graph(fresh, consumers, eligibility)
    return _heading_result(len(_consumers()))
