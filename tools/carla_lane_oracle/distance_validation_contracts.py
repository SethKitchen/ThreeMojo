"""Exact bounded representation checks; not capture/proof authentication."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

from pathlib import Path
MODULE='extensions/carla/spiral_domain_proof.mojo'

def verify_text(module, interval):
    import json
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='distance-gate-') as directory:
        folder = Path(directory)
        module_path = folder / 'module.mojo'
        interval_path = folder / 'interval.mojo'
        module_path.write_text(module)
        interval_path.write_text(interval)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_distance_gate',
             '--module', str(module_path), '--interval', str(interval_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)

def verify(root, *, _operation=None):
    root=Path(root)
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    module = (root/MODULE).read_text()
    if _operation is not None:
        module = full_audit._observe_text(root, MODULE, module, _operation=_operation)
    interval = (root/'extensions/carla/curve_interval.mojo').read_text()
    if _operation is not None:
        interval = full_audit._observe_text(
            root, 'extensions/carla/curve_interval.mojo', interval, _operation=_operation)
    module = _typed_source.historical_text(root, MODULE, module, _operation=_operation)
    interval = _typed_source.historical_text(root, 'extensions/carla/curve_interval.mojo', interval, _operation=_operation)
    return verify_text(module, interval)
