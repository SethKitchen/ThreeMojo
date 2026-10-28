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

_SOURCES = None


def _sources():
    """Return the moment proof path, the interval path, and their tokens."""
    global _SOURCES
    if _SOURCES is not None:
        return _SOURCES
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_sources'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _SOURCES = json.loads(result.stdout)
    return _SOURCES


def _ensure_sources():
    """Bind the moment paths and tokens before a source read."""
    global MODULE, INTERVAL, EXPECTED, EXPECTED_INTERVAL
    data = _sources()
    MODULE = data['module']
    INTERVAL = data['interval']
    EXPECTED = data['module_token']
    EXPECTED_INTERVAL = data['interval_token']


def __getattr__(name):
    if name in ('MODULE', 'INTERVAL', 'EXPECTED', 'EXPECTED_INTERVAL'):
        _ensure_sources()
    if name == 'MODULE':
        return MODULE
    if name == 'INTERVAL':
        return INTERVAL
    if name == 'EXPECTED':
        return EXPECTED
    if name == 'EXPECTED_INTERVAL':
        return EXPECTED_INTERVAL
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')

_GATED_MOMENT = None


def verify_text(module, interval, geometry, trig):
    """Check one moment-producer tuple once for the same texts.

    Args:
        module: The moment proof source.
        interval: The interval source.
        geometry: The geometry source.
        trig: The trig source.

    Returns:
        The parsed pass record.

    Raises:
        ValueError: A token digest or a stored bound changed.
    """
    global _GATED_MOMENT
    key = (module, interval, geometry, trig)
    cached = _GATED_MOMENT
    if cached is not None and cached[0] == key:
        return cached[1]
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
    parsed = json.loads(result.stdout)
    _GATED_MOMENT = (key, parsed)
    return parsed

def verify(root, *, _operation=None):
    _ensure_sources()
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
