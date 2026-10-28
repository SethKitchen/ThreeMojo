"""Exact bounded representation checks; not capture/proof authentication."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

from pathlib import Path
_MODULE_PATH = None


def _module_path():
    """Return the spiral-domain proof path."""
    global _MODULE_PATH
    if _MODULE_PATH is not None:
        return _MODULE_PATH
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_distance_module'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _MODULE_PATH = result.stdout
    return _MODULE_PATH


def _ensure_module():
    """Bind the spiral-domain path before a source read."""
    global MODULE
    MODULE = _module_path()


def __getattr__(name):
    if name == 'MODULE':
        return _module_path()
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')

_GATED_DISTANCE = None


def verify_text(module, interval):
    """Check one spiral-domain pair once for the same texts.

    Args:
        module: The spiral-domain proof source.
        interval: The interval source.

    Returns:
        The parsed pass record.

    Raises:
        ValueError: The token digest changed.
    """
    global _GATED_DISTANCE
    key = (module, interval)
    cached = _GATED_DISTANCE
    if cached is not None and cached[0] == key:
        return cached[1]
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
    parsed = json.loads(result.stdout)
    _GATED_DISTANCE = (key, parsed)
    return parsed

def verify(root, *, _operation=None):
    _ensure_module()
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
