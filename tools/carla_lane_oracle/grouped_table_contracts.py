"""Bind the grouped proof to its reviewed immutable-table producer contract."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

from pathlib import Path
# #333 explicit historical provenance views; current inputs remain operation-owned.

_IDENTITY = None


def _identity():
    """Return the grouped proof module and its token digest."""
    global _IDENTITY
    if _IDENTITY is not None:
        return _IDENTITY
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_grouped_table_identity'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _IDENTITY = json.loads(result.stdout)
    return _IDENTITY


def _ensure_identity():
    """Bind the module and token digest before a source read."""
    global MODULE, TOKEN_SHA256
    data = _identity()
    MODULE = data['module']
    TOKEN_SHA256 = data['token']


def __getattr__(name):
    if name in ('MODULE', 'TOKEN_SHA256'):
        _ensure_identity()
    if name == 'MODULE':
        return MODULE
    if name == 'TOKEN_SHA256':
        return TOKEN_SHA256
    if name == 'EXPECTED':
        return _identity()['consumer']
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')

_GATED_GROUPED = None


def _grouped_checked(module, geometry, digest):
    """Compare the grouped token, then check the stored bounds when it matches.

    The same texts are not checked again. A changed text is checked again.
    A failed check is not kept.
    """
    global _GATED_GROUPED
    key = (module, geometry, digest)
    cached = _GATED_GROUPED
    if cached is not None and cached[0] == key:
        return cached[1]
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({
        'module': module,
        'geometry': geometry,
        'digest': digest,
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='grouped-checked-') as directory:
        path = Path(directory) / 'grouped.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_grouped_gate',
             '--checked', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    _GATED_GROUPED = (key, parsed)
    return parsed


def verify_text(module, geometry):
    # Exact complete module binding includes imports, both materializations,
    # every use/write of local arrays, environment guard and error/work graph.
    import json
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='grouped-gate-') as directory:
        folder = Path(directory)
        module_path = folder / 'module.mojo'
        geometry_path = folder / 'geometry.mojo'
        module_path.write_text(module)
        geometry_path.write_text(geometry)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_grouped_gate',
             '--module', str(module_path), '--geometry', str(geometry_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)

def _grouped_then_lane(module, geometry, digest):
    """Check the grouped table, then read the lane-control record paths.

    A successful table check is kept for a later read of the same texts.
    A failed check is not kept.
    """
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    global _GATED_GROUPED
    if __package__:
        from . import lane_control_contracts as lane
    else:
        import lane_control_contracts as lane
    payload = json.dumps({
        'module': module,
        'geometry': geometry,
        'digest': digest,
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='grouped-lane-') as directory:
        path = Path(directory) / 'grouped.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_grouped_gate',
             '--checked-paths', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if not parsed['restore'] and lane._RECORD_PATHS is None and 'paths' in parsed:
        lane._RECORD_PATHS = parsed['paths']
    _GATED_GROUPED = ((module, geometry, digest), parsed)
    return parsed


def verify(root, *, _operation=None, _then_lane_paths=False):
    _ensure_identity()
    root=Path(root)
    text=(root/MODULE).read_text()
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        text = full_audit._observe_text(root, MODULE, text, _operation=_operation)
    geometry = (root/'extensions/carla/geometry.mojo').read_text()
    if _operation is not None:
        geometry = full_audit._observe_text(
            root, 'extensions/carla/geometry.mojo', geometry, _operation=_operation)
    if _then_lane_paths:
        checked = _grouped_then_lane(text, geometry, TOKEN_SHA256)
    else:
        checked = _grouped_checked(text, geometry, TOKEN_SHA256)
    if checked['restore']:
        if __package__:
            from . import selection_finiteness_contracts as selection
        else:
            import selection_finiteness_contracts as selection
        return selection.predecessor_text(
            root, MODULE, _then_grouped=geometry, _operation=_operation)
    return checked['record']
