"""Exact graph for the reviewed private Y-finiteness lemma. No arbitrary projection."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

from pathlib import Path
EXPECTED = {'extensions/carla/spiral_grouped_roundoff_proof.mojo': 'cd92ac2f02c75fc420920fe3a73b4ddd28a4e5cf0d97785b4ae4eb0f54f2cbd7', 'extensions/carla/curve_interval.mojo': 'e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11', 'extensions/carla/curve_trig.mojo': '523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f', 'extensions/carla/geometry.mojo': 'a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb', 'extensions/carla/curve_sum2.mojo': '3fbcbb7f6ba0b9120500698665f0419acf6618d8bd34b7e18b9d10896282383d'}

def _pass_record():
    return {'status': 'PASS', 'maximum_accumulator_exponent': 947, 'origin_error_refusal_unchanged': True, 'y_call_and_writes_retained': True}


def _token_mismatches(modules):
    """Return the modules whose Y-finiteness tokens differ, in review order."""
    import json
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    names = (
        ('grouped', 'extensions/carla/spiral_grouped_roundoff_proof.mojo'),
        ('interval', 'extensions/carla/curve_interval.mojo'),
        ('trig', 'extensions/carla/curve_trig.mojo'),
        ('geometry', 'extensions/carla/geometry.mojo'),
        ('sum2', 'extensions/carla/curve_sum2.mojo'),
    )
    with tempfile.TemporaryDirectory(prefix='y-mismatches-') as directory:
        folder = Path(directory)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_y_gate',
                     '--mismatches']
        for flag, path in names:
            target = folder / (flag + '.mojo')
            target.write_text(modules[path])
            arguments.extend(['--' + flag, str(target)])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def verify_text(modules):
    if set(modules) != set(EXPECTED):
        raise ValueError('Wrong Y-finiteness dependency set')
    mismatches = _token_mismatches(modules)
    if mismatches:
        if __package__:
            from . import reviewed_cleanup_contracts as words
        else:
            import reviewed_cleanup_contracts as words
        for name in mismatches:
            try:
                words.verify_dependency(name, modules[name], EXPECTED[name])
            except ValueError as error:
                raise ValueError('Y-finiteness premise, graph, writes or ordering changed: ' + name) from error
    return _pass_record()

def verify(root, *, _operation=None):
    root = Path(root)
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    modules = {p: (root/p).read_text() for p in EXPECTED}
    if _operation is not None:
        modules = {p: _typed_source.historical_text(root, p, full_audit._observe_text(root, p, text, _operation=_operation), _operation=_operation)
                   for p, text in modules.items()}
    else:
        modules = {p: _typed_source.historical_text(root, p, text)
                   for p, text in modules.items()}
    return verify_text(modules)

MODULE = 'extensions/carla/spiral_grouped_roundoff_proof.mojo'
RECORD = 'tools/carla_lane_oracle/grouped-y-successor-record.json'
RECORD_SHA256 = '4b72cd07de22d61d70c7aa489e566cd25468189b6a60b5e105fa26ea726e6853'
PREDECESSOR_TOKEN_SHA256 = 'a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7'


def _gate_predecessor(record):
    """Check the successor record, then return the earlier module."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='y-predecessor-') as directory:
        target = Path(directory) / 'record.json'
        target.write_bytes(record)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_y_gate',
             '--predecessor', str(target)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def predecessor_text(root, path, *, _operation=None):
    """Verify all actual Y premises before restoring its exact prior module."""
# #333 explicit historical provenance views; current inputs remain operation-owned.
    root = Path(root)
    if str(path) != MODULE:
        raise ValueError('Y projection permits only its exact grouped module')
    # Never call selection or another historical projection from here. The
    # actual five-file graph must pass before any record can provide text.
    verify(root, _operation=_operation)
    payload = _typed_source.historical_bytes(root, root / RECORD, (root / RECORD).read_bytes(), _operation=_operation)
    return _gate_predecessor(payload)
