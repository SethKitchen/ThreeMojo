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

def __getattr__(name):
    if name == 'RECORD_SHA256':
        return _lane_labels()['record']
    if name == 'PREDECESSOR_SHA256':
        return _lane_labels()['predecessor']
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def _replace_firsts(items):
    """Replace the first occurrence in each text."""
    if not items:
        return []
    import json
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps([
        {'source': source, 'old': old, 'new': new} for source, old, new in items
    ], separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='replace-firsts-') as directory:
        record = Path(directory) / 'replacements.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_replace_firsts',
             str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


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


def _declarations(items):
    """Return the declaration texts in the requested order."""
    import os
    import subprocess
    import tempfile
    if not items:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='lane-declarations-') as directory:
        path = Path(directory) / 'declarations.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_lane_declarations',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


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
    if not ideal_projection.token_texts_match(current, record['after_source']):
        if __package__:
            from . import lane_order_contracts as order
        else:
            import lane_order_contracts as order
        current = order.predecessor_source(root, **operation_args)

    labels = _lane_labels()
    pairs = [(current, record['after_source'], labels['successor'])]
    requests = []
    replacements = []
    for item in record['declarations']:
        name = item['name']
        requests.append({'source': record['before_source'], 'name': name, 'owner': []})
        requests.append({'source': current, 'name': name, 'owner': []})
        test = _typed_source.historical_text(root, 'tests/test_carla_lane_control_successor.mojo', _observe_text(root, 'tests/test_carla_lane_control_successor.mojo',
                             (root / 'tests/test_carla_lane_control_successor.mojo').read_text(),
                             _operation=_operation), _operation=_operation)
        reference = labels['reference'] + name
        requests.append({'source': test, 'name': reference, 'owner': []})
        replacements.append((
            item['before'],
            labels['definition'] + name + labels['call'],
            labels['definition'] + reference + labels['call']))
    frozen_expected = _replace_firsts(replacements)
    premise_items = []
    for item in record['premises']:
        premise_items.append(item)
        requests.append({
            'source': _typed_source.historical_text(root, item['path'], _observe_text(root, item['path'], (root / item['path']).read_text(), _operation=_operation), _operation=_operation),
            'name': item['name'],
            'owner': [],
        })
    declared = _declarations(requests)
    cursor = 0
    for index, item in enumerate(record['declarations']):
        pairs.append((declared[cursor], item['before'], labels['before']))
        pairs.append((declared[cursor + 1], item['after'], labels['after']))
        pairs.append((declared[cursor + 2], frozen_expected[index], labels['frozen']))
        cursor += 3
    for item in premise_items:
        pairs.append((declared[cursor], item['source'], labels['premise'] + item['name']))
        cursor += 1
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
    print(_lane_labels()['pass'])
