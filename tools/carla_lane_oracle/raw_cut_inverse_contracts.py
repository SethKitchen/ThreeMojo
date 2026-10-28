# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact guarded raw-inverse successor; no unproved branch exclusion."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source
# #333 explicit historical provenance views; current inputs remain operation-owned.
import json
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

MIGRATION = 'tools/carla_lane_oracle/raw-cut-inverse-migration.json'
MIGRATION_SHA256 = '4f4eb051d9c1f9194796d3073fcadfa9f49dda4c44a851da0a3409ba09587dd0'
SOURCE_PATH = 'extensions/carla/curve_sample_dispatch.mojo'
PROTECTED_INPUTS = (MIGRATION, SOURCE_PATH, 'extensions/carla/curve_sum2.mojo',
                    'tools/carla_lane_oracle/curve-support-dispatch-migration.json',
                    'tests/test_carla_raw_cut_successor.mojo',
                    'tests/test_carla_support_dispatch_successor.mojo')


def require(condition, message):
    if not condition:
        raise ValueError('raw cut inverse contract: ' + message)


def _gate(migration, module=None):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='raw-cut-gate-') as directory:
        folder = Path(directory)
        record_path = folder / 'migration.json'
        record_path.write_bytes(migration)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_raw_cut_gate', '--migration', str(record_path)]
        if module is not None:
            module_path = folder / 'module.mojo'
            module_path.write_text(module)
            arguments.extend(['--module', str(module_path)])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _significant_documents(texts):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not texts:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='significant-json-') as directory:
        folder = Path(directory)
        for index, text in enumerate(texts):
            (folder / f'{index}.text').write_text(text)
        (folder / 'count').write_text(str(len(texts)))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--significant-json', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _gate_graph(actual, expected, kind):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='raw-cut-graph-') as directory:
        folder = Path(directory)
        left = folder / 'actual.json'
        right = folder / 'wanted.json'
        left.write_text(actual)
        right.write_text(expected)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_raw_cut_gate',
             '--actual', str(left), '--wanted', str(right), '--part', kind],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_binding(successor, recorded):
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_raw_cut_gate',
         '--successor', successor, '--recorded', recorded],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_fixture(text, expected):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='raw-cut-fixture-') as directory:
        target = Path(directory) / 'fixture.mojo'
        target.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_raw_cut_gate',
             '--fixture', str(target), '--token', expected],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_predecessor(payload, expected):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='raw-cut-predecessor-') as directory:
        target = Path(directory) / 'predecessor.json'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_raw_cut_gate',
             '--predecessor', str(target), '--sha', expected],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_bound(text, recorded):
    """Read the predecessor token, then check the binding."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='raw-cut-bound-') as directory:
        target = Path(directory) / 'predecessor.json'
        target.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_raw_cut_gate',
             '--bound', str(target), recorded],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def read_record(root):
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    _gate(payload)
    read_record.payload = payload
    return json.loads(payload)


def _declaration(text, name, owner):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='declaration-gate-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_cleanup_gate', '--declaration', str(source),
                     '--name', name]
        for part in owner:
            arguments.extend(['--owner', part])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def verify_premises(root, *, _operation=None):
    # Independently bind the complete lexical operations rather than relying
    # on the successor digest. The proof requires this exact stored predicate,
    # fresh environment guard, admission tests, and ordered adjacent candidates.
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    record = read_record(root)
    text = (root/SOURCE_PATH).read_text()
    if _operation is not None:
        text = full_audit._observe_text(root, SOURCE_PATH, text, _operation=_operation)
    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)
    graph_actual, graph_expected = _significant_documents([
        text, record['after_source']])
    _gate_graph(graph_actual, graph_expected, 'graph')
    environment = (root/'extensions/carla/curve_sum2.mojo').read_text()
    if _operation is not None:
        environment = full_audit._observe_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)
    environment = _typed_source.historical_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)
    environment_actual, environment_expected = _significant_documents([
        environment, record['environment_source']])
    _gate_graph(environment_actual, environment_expected, 'environment')
    predecessor_payload = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json', (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_bytes(), _operation=_operation)
    _gate_predecessor(predecessor_payload, record['predecessor_migration_sha256'])
    predecessor_text = (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()
    if _operation is not None:
        predecessor_text = full_audit._observe_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation, _checked_raw=predecessor_payload)
    predecessor_text = _typed_source.historical_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation)
    _gate_bound(predecessor_text, record['before_token_sha256'])
    fixture = (root/'tests/test_carla_raw_cut_successor.mojo').read_text()
    if _operation is not None:
        fixture = full_audit._observe_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)
    fixture = _typed_source.historical_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)
    _gate_fixture(fixture, record['native_fixture_token_sha256'])
    reference = (root/'tests/test_carla_support_dispatch_successor.mojo').read_text()
    if _operation is not None:
        reference = full_audit._observe_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)
    reference = _typed_source.historical_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)
    ref = _declaration(reference,
                       '_reference_sample_dispatch_cut', ())
    reference_actual, reference_expected = _significant_documents([
        ref, record['native_reference_source']])
    _gate_graph(reference_actual, reference_expected, 'reference')
    return record


def verify(root, *, _operation=None):
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    record = read_record(root)
    text = (root/SOURCE_PATH).read_text()
    if _operation is not None:
        text = full_audit._observe_text(root, SOURCE_PATH, text, _operation=_operation)
    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)
    _gate(read_record.payload, text)
    verify_premises(root, _operation=_operation)
    return record
