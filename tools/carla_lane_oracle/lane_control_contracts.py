"""Qualify the reviewed lane-control successor without changing historical pins."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source
# #333 explicit historical provenance views; current inputs remain operation-owned.
import json
from pathlib import Path

RECORD_SHA256 = '73d95d594e740205bad4cd900288a68d9f82897474fdc33e4d6043a156790170'
PREDECESSOR_SHA256 = '33d33ba0e481e3eca3b17ae0d02457ab53bae906430b0dca58abcfa876756315'


def _replace_first(text, old, new):
    """Replace the first occurrence of `old` in `text`."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='replace-first-') as directory:
        folder = Path(directory)
        (folder / 'source.text').write_text(text)
        (folder / 'old.text').write_text(old)
        (folder / 'new.text').write_text(new)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--replace-first', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_text(root, path, text, *, _operation=None, supplied=False):
    if _operation is None:
        return text
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_text(
        root, path, text, _operation=_operation, supplied=supplied)



def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def _declaration(text, name, owner=()):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='lane-declaration-') as directory:
        source_path = Path(directory) / 'source.mojo'
        source_path.write_text(text)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_cleanup_gate', '--declaration', str(source_path),
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


def _token_sha256(text):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='lane-token-sha-') as directory:
        source_path = Path(directory) / 'source.mojo'
        source_path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--token-sha', str(source_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


def _gate(payload):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='lane-control-gate-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_lane_control_gate',
             '--migration', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise RuntimeError(message)


def _gate_tokens(pairs):
    import json
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='lane-control-tokens-') as directory:
        folder = Path(directory)
        labels = []
        for index, (left, right, label) in enumerate(pairs):
            (folder / f'{index}.left').write_text(left)
            (folder / f'{index}.right').write_text(right)
            labels.append(label)
        (folder / 'labels.json').write_text(json.dumps(labels))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_lane_control_gate',
             '--tokens', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise RuntimeError(message)


_LANE_LABELS = None
_RECORD_PATHS = None


def _lane_labels():
    """Return the lane-control labels and the frozen reference prefix."""
    global _LANE_LABELS
    if _LANE_LABELS is not None:
        return _LANE_LABELS
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_lane_control_labels'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise RuntimeError(message)
    _LANE_LABELS = json.loads(result.stdout)
    return _LANE_LABELS


def _record_paths():
    """Return the companion migration record paths."""
    global _RECORD_PATHS
    if _RECORD_PATHS is not None:
        return _RECORD_PATHS
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_record_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise RuntimeError(message)
    _RECORD_PATHS = json.loads(result.stdout)
    return _RECORD_PATHS


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    root = Path(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    path = root / _record_paths()['lane_control']
    raw = _typed_source.historical_bytes(root, path, path.read_bytes(), _operation=_operation)
    _gate(raw)
    record = json.loads(raw)
    current = _typed_source.historical_text(root, record['module'], _observe_text(root, record['module'], (root / record['module']).read_text(), _operation=_operation), _operation=_operation)
    if __package__:
        from . import ideal_projection
    else:
        import ideal_projection
    if not ideal_projection.texts_match(
            _token_sha256(current), _token_sha256(record['after_source'])):
        if __package__:
            from . import lane_order_contracts as order
        else:
            import lane_order_contracts as order
        current = order.predecessor_source(root, **operation_args)

    labels = _lane_labels()
    pairs = [(current, record['after_source'], labels['successor'])]
    for item in record['declarations']:
        name = item['name']
        pairs.append((_declaration(record['before_source'], name, ()), item['before'],
                      labels['before']))
        pairs.append((_declaration(current, name, ()), item['after'],
                      labels['after']))
        test = _typed_source.historical_text(root, 'tests/test_carla_lane_control_successor.mojo', _observe_text(root, 'tests/test_carla_lane_control_successor.mojo',
                             (root / 'tests/test_carla_lane_control_successor.mojo').read_text(),
                             _operation=_operation), _operation=_operation)
        reference = labels['reference'] + name
        frozen = _declaration(test, reference, ())
        expected = _replace_first(
            item['before'],
            labels['definition'] + name + labels['call'],
            labels['definition'] + reference + labels['call'])
        pairs.append((frozen, expected, labels['frozen']))
    for item in record['premises']:
        actual = _declaration(_typed_source.historical_text(root, item['path'], _observe_text(root, item['path'], (root / item['path']).read_text(), _operation=_operation), _operation=_operation), item['name'], ())
        pairs.append((actual, item['source'], labels['premise'] + item['name']))
    for rel, expected in record['producer_modules'].items():
        pairs.append((_typed_source.historical_text(root, rel, _observe_text(root, rel, (root / rel).read_text(), _operation=_operation), _operation=_operation), expected,
                      labels['producer'] + rel))
    _gate_tokens(pairs)
    return record


def accepts_predecessor(root, path, name, owner, expected_source, *, _operation=None):
    """Delegate only an exact historical declaration to this reviewed successor."""
    if _operation is not None:
        _check_operation(root, _operation)
    record = verify(root, **({} if _operation is None else {'_operation': _operation}))
    import json
    import os
    import subprocess
    import tempfile
    payload = json.dumps({
        'owner': list(owner),
        'path': path,
        'name': name,
        'expected': expected_source,
        'declarations': [
            {'path': item['path'], 'name': item['name'], 'before': item['before']}
            for item in record['declarations']
        ],
    }, separators=(',', ':'))
    root_path = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root_path / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='lane-predecessor-') as directory:
        record_path = Path(directory) / 'predecessor.json'
        record_path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root_path / 'tools' / 'tool.sh'), mojo,
             'carla_lane_predecessor', str(record_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip() == 'true'


if __name__ == '__main__':
    import sys
    verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2])
    print('Lane control-flow migration: PASS')
