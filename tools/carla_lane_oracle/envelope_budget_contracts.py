"""Bind the exact no-counter-alias span between envelope budget admissions."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

from pathlib import Path
if __package__:
    from . import source_contracts
else:
    import source_contracts
MODULE='extensions/carla/curve_bounds.mojo'
EXPECTED='9bc62290a6bdeca43c4d695a0f0ce6592d69f49386d83ce7342b667c73680fce'

def verify_text(text, *, root=None, _operation=None):
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        text = full_audit._observe_text(root, MODULE, text, _operation=_operation)
    actual_root = Path(root) if root is not None else Path(__file__).resolve().parents[2]
    text = _typed_source.historical_text(actual_root, MODULE, text, _operation=_operation)
    checked = text
    if source_contracts.token_sha256(text) != EXPECTED:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        actual_root = Path(root) if root is not None else Path(__file__).resolve().parents[2]
        try:
            checked = full_audit.reviewed_text(actual_root, MODULE, text, _operation=_operation)
        except (ValueError, OSError) as error:
            raise ValueError('Reviewed budget admission, routing or arithmetic changed') from error
    _gate_admission(checked, text, EXPECTED)
    return {'status':'PASS','source_token_sha256':EXPECTED,'intervening_counter_uses':0,'retained_capacity_and_debit':True}

def verify(root, *, _operation=None):
    return verify_text((Path(root)/MODULE).read_text(), root=root, _operation=_operation)


def _gate_predecessor(source, record):
    """Check the record, then return the earlier capture function."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='envelope-predecessor-') as directory:
        folder = Path(directory)
        (folder / 'record.json').write_bytes(record)
        (folder / 'module.mojo').write_text(source)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_envelope_gate',
             '--predecessor', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _gate_admission(checked, source, token):
    """Check the admission token, then the capture-function gap."""
    import json
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({
        'checked': checked, 'source': source, 'token': token,
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='envelope-admission-') as directory:
        target = Path(directory) / 'admission.json'
        target.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_envelope_gate',
             '--admission', str(target)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def historical_function(text, *, root=None):
    """Return the bound predecessor only after verifying the exact successor."""
# #333 explicit historical provenance views; current inputs remain operation-owned.
    verify_text(text, root=root)
    record_path = (Path(root)/'tools/carla_lane_oracle/envelope-budget-contract.json'
                   if root is not None else Path(__file__).with_name('envelope-budget-contract.json'))
    payload = _typed_source.historical_bytes(root, record_path, record_path.read_bytes())
    return _gate_predecessor(text, payload)
