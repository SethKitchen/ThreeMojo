"""Bind the grouped proof to its reviewed immutable-table producer contract."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

from pathlib import Path
# #333 explicit historical provenance views; current inputs remain operation-owned.

if __package__:
    from . import ideal_projection
else:
    import ideal_projection

TOKEN_SHA256='3fcfc637a40c4e322b5747f27f8d77163c3f47a49d1092b37c20744cafecba40'
MODULE='extensions/carla/spiral_grouped_roundoff_proof.mojo'
EXPECTED='0e42c79e3bbda283c32886e50ad8b1acd614f651f1d258f4ea4b5e4e0e139299'

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

def verify(root, *, _operation=None):
    root=Path(root)
    text=(root/MODULE).read_text()
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        text = full_audit._observe_text(root, MODULE, text, _operation=_operation)
    if ideal_projection.token_sha256(text)!=TOKEN_SHA256:
        if __package__:
            from . import selection_finiteness_contracts as selection
        else:
            import selection_finiteness_contracts as selection
        text=selection.predecessor_text(root,MODULE, _operation=_operation)
    geometry = (root/'extensions/carla/geometry.mojo').read_text()
    if _operation is not None:
        geometry = full_audit._observe_text(
            root, 'extensions/carla/geometry.mojo', geometry, _operation=_operation)
    return verify_text(text, geometry)
