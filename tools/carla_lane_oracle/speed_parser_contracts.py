# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact parser grammar/correctness successor, never arbitrary repinning."""
if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

# #333 explicit historical provenance views; current inputs remain operation-owned.
import json
from pathlib import Path
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source
MIGRATION = 'tools/carla_lane_oracle/speed-parser-successor.json'
MIGRATION_SHA256 = '47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364'
MODULE = 'extensions/carla/speed_limits.mojo'
TESTS = ('tests/test_carla_speed_lexical.mojo', 'tests/test_carla_speed_xml_lexical.mojo')
PROTECTED_INPUTS = (MIGRATION, MODULE, *TESTS)


def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_text(root, path, text, *, _operation=None, mode='default'):
    if _operation is None:
        return text
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_text(
        root, path, text, _operation=_operation, mode=mode)



def require(value, message):
    if not value:
        raise ValueError('reviewed speed parser successor: ' + message)


def _gate(migration, accepted, module, lexical, xml):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='speed-gate-') as directory:
        folder = Path(directory)
        names = {}
        for name, payload, binary in (
            ('migration', migration, True), ('accepted', accepted, True),
            ('module', module, False), ('lexical', lexical, True),
            ('xml', xml, True),
        ):
            path = folder / name
            if binary:
                path.write_bytes(payload)
            else:
                path.write_text(payload)
            names[name] = str(path)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_speed_gate',
             '--migration', names['migration'], '--accepted', names['accepted'],
             '--module', names['module'], '--lexical', names['lexical'],
             '--xml', names['xml']],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    root = Path(root)
    raw = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes(), _operation=_operation)
    accepted = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/accepted-successor-migration.json', (root/'tools/carla_lane_oracle/accepted-successor-migration.json').read_bytes(), _operation=_operation)
    module = _typed_source.historical_text(root, MODULE, _observe_text(
        root, MODULE, (root/MODULE).read_text(), _operation=_operation), _operation=_operation)
    lexical = _typed_source.historical_bytes(root, root/TESTS[0], (root/TESTS[0]).read_bytes(), _operation=_operation)
    xml = _typed_source.historical_bytes(root, root/TESTS[1], (root/TESTS[1]).read_bytes(), _operation=_operation)
    _gate(raw, accepted, module, lexical, xml)
    return json.loads(raw, object_pairs_hook=source.unique_keys)
