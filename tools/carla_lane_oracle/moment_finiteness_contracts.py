"""Source-bound finite-intermediate proof for the dynamic moment producer."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source
from pathlib import Path

if __package__:
    from . import source_contracts
else:
    import source_contracts

MODULE='extensions/carla/spiral_moment_proof.mojo'
INTERVAL='extensions/carla/curve_interval.mojo'
EXPECTED='9001f34d01c28de8dcf85af0bec9d9b9409ef8d56e083bfc25d6342c375f80d1'
EXPECTED_INTERVAL='e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11'

def verify_text(module, interval, geometry, trig):
    import json
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='moment-gate-') as directory:
        folder = Path(directory)
        paths = {}
        for name, text in (
            ('module', module), ('interval', interval),
            ('geometry', geometry), ('trig', trig),
        ):
            path = folder / (name + '.mojo')
            path.write_text(text)
            paths[name] = str(path)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--module', paths['module'], '--interval', paths['interval'],
             '--geometry', paths['geometry'], '--trig', paths['trig']],
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
    interval = (root/INTERVAL).read_text()
    if _operation is not None:
        interval = full_audit._observe_text(root, INTERVAL, interval, _operation=_operation)
    geometry = (root/'extensions/carla/geometry.mojo').read_text()
    if _operation is not None:
        geometry = full_audit._observe_text(
            root, 'extensions/carla/geometry.mojo', geometry, _operation=_operation)
    trig = (root/'extensions/carla/curve_trig.mojo').read_text()
    if _operation is not None:
        trig = full_audit._observe_text(
            root, 'extensions/carla/curve_trig.mojo', trig, _operation=_operation)
    return verify_text(module, interval, geometry, trig)
