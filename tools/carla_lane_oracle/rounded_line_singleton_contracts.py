# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact source/name binding for the rounded LINE singleton successor.

This standalone verifier grants no coverage exclusion. Central migration and
independent approval must compose this proposal into aggregate tooling.
"""
if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

# #333 explicit historical provenance views; current inputs remain operation-owned.
import json
if __package__:
    from . import source_contracts as source
    from . import full_audit_cleanup_contracts as full_audit
else:
    import source_contracts as source
    import full_audit_cleanup_contracts as full_audit


_MIGRATION_RECORDS = None


def _migration_records():
    """Return the reviewed migration paths and digests."""
    global _MIGRATION_RECORDS
    if _MIGRATION_RECORDS is not None:
        return _MIGRATION_RECORDS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_migration_records'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _MIGRATION_RECORDS = json.loads(result.stdout)
    return _MIGRATION_RECORDS


def _ensure_migration():
    """Bind this checker's migration path and digest."""
    global MIGRATION, MIGRATION_SHA256
    if 'MIGRATION' in globals() and MIGRATION is not None:
        return
    record = _migration_records()['singleton']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']



_CONTRACT_PREFIXES = None


def _contract_prefixes():
    """Return the reviewed contract prefixes."""
    global _CONTRACT_PREFIXES
    if _CONTRACT_PREFIXES is not None:
        return _CONTRACT_PREFIXES
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_contract_prefixes'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CONTRACT_PREFIXES = json.loads(result.stdout)
    return _CONTRACT_PREFIXES


def require(value, message):
    if not value:
        raise ValueError(_contract_prefixes()['singleton'] + message)


def _gate(payload):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='singleton-gate-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--migration', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_views(text, decoded):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='singleton-views-') as directory:
        folder = Path(directory)
        text_path = folder / 'text.mojo'
        decoded_path = folder / 'decoded.mojo'
        text_path.write_text(text)
        decoded_path.write_text(decoded)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--text', str(text_path), '--decoded', str(decoded_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_selector(actual, expected):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='singleton-path-') as directory:
        folder = Path(directory)
        actual_path = folder / 'actual'
        expected_path = folder / 'expected'
        actual_path.write_text(actual)
        expected_path.write_text(expected)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--selector', str(actual_path), '--wanted', str(expected_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _significant_graphs(pairs):
    """Compare every source pair by its significant tokens."""
    if not pairs:
        return
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps([
        {'label': label, 'actual': actual, 'source': source}
        for actual, source, label in pairs
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='singleton-source-graphs-') as directory:
        path = Path(directory) / 'graphs.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--source-graphs', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def read_record(root):
    _ensure_migration()
    payload = _typed_source.historical_bytes(root, root / MIGRATION, (root / MIGRATION).read_bytes())
    _gate(payload)
    return json.loads(payload, object_pairs_hook=source.unique_keys)


def _prepare_rounded(paths):
    """Read the singleton paths and remember the rounded-line modules."""
    global _SINGLETON_PATHS, _ROUNDED
    if _ROUNDED is not None:
        return
    if not paths:
        _ROUNDED = set()
        return
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(list(paths), separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='rounded-line-flags-') as directory:
        record = Path(directory) / 'paths.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_paths',
             '--flags', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    data = json.loads(result.stdout)
    if _SINGLETON_PATHS is None:
        _SINGLETON_PATHS = data['paths']
    chosen = set()
    for path, flag in zip(paths, data['flags']):
        if flag:
            chosen.add(path)
    _ROUNDED = chosen


def _significant_matches(pairs):
    """Return whether each source pair has the same significant tokens."""
    if not pairs:
        return []
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps([
        {'actual': actual, 'source': source} for actual, source in pairs
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='significant-match-') as directory:
        path = Path(directory) / 'pairs.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_source',
             '--token-match', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [flag == 'true' for flag in json.loads(result.stdout)]


def _selected_minima(items):
    """Return whether each declaration is the rounded lane minimum."""
    if not items:
        return []
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps([
        {'path': path, 'name': name, 'owner': list(owner)}
        for path, name, owner in items
    ], separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='lane-minimum-') as directory:
        record = Path(directory) / 'minimum.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_lane_predecessor', '--minimum', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [flag == 'true' for flag in json.loads(result.stdout)]


_SINGLETON_PATHS = None
_ROUNDED = None


def _singleton_paths():
    """Return the lane path, the rounded-line path, and the messages."""
    global _SINGLETON_PATHS
    if _SINGLETON_PATHS is not None:
        return _SINGLETON_PATHS
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _SINGLETON_PATHS = json.loads(result.stdout)
    return _SINGLETON_PATHS


def _reviewed_text(root, path, record):
    text = _typed_source.historical_text(root, root/path, (root/path).read_text())
    if _ROUNDED is None:
        _prepare_rounded([path])
    if path not in _ROUNDED:
        return text
    if _significant_matches([(text, record['modules'][path]['source'])])[0]:
        return text
    if __package__:
        from . import rounded_line_selector_contracts as successor
    else:
        import rounded_line_selector_contracts as successor
    # Validate the actual complete selector/context/name graph before restoring
    # its exact immediate predecessor. The successor calls read_record only.
    current = successor.verify_premises(root)
    _gate_selector(current['path'], path)
    return current['before_source']


def _verify_dependencies(items):
    if not items:
        return
    if __package__:
        from . import reviewed_cleanup_contracts as words
    else:
        import reviewed_cleanup_contracts as words
    words.verify_dependencies(items)


def _checked_import_scopes(items, lane_index, label_prefix):
    """Extract every import scope, then check the graphs when the lane matches."""
    if not items:
        return {'restore': False}
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = {
        'texts': [text for _path, text, _expected in items],
        'expected': [expected for _path, _text, expected in items],
        'labels': [label_prefix + path for path, _text, _expected in items],
    }
    if lane_index is not None:
        payload['lane'] = lane_index
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='import-scopes-') as directory:
        path = Path(directory) / 'scopes.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--import-scopes', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _scopes_then_minima(items, lane_index, label_prefix, minima):
    """Check the import scopes, then the lane minima when they match."""
    if not items and not minima:
        return {'restore': False, 'minima': []}
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = {
        'scopes': {
            'texts': [text for _path, text, _expected in items],
            'expected': [expected for _path, _text, expected in items],
            'labels': [label_prefix + path for path, _text, _expected in items],
        },
        'minima': [
            {'path': path, 'name': name, 'owner': list(owner)}
            for path, name, owner in minima
        ],
    }
    if lane_index is not None:
        payload['scopes']['lane'] = lane_index
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='scopes-minima-') as directory:
        path = Path(directory) / 'scopes.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--scopes-then-minima', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _import_scope(text):
    """Return the consumer prefix before the first definition."""
    return _import_scopes([text])[0]


def _import_scopes(texts):
    """Return the consumer prefix of each module."""
    if not texts:
        return []
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(list(texts), separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='import-scopes-') as directory:
        path = Path(directory) / 'scopes.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_import_scopes',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _universal_newlines(text):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='universal-newlines-') as directory:
        path = Path(directory) / 'text.txt'
        path.write_bytes(text.encode('utf-8'))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_universal_newlines', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _views_after_newlines(text, physical):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='singleton-views-') as directory:
        folder = Path(directory)
        text_path = folder / 'text.mojo'
        physical_path = folder / 'physical.mojo'
        text_path.write_text(text)
        physical_path.write_bytes(physical.encode('utf-8'))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--views-after-newlines', str(text_path), str(physical_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _lane_text(root):
    """Compare actual text/byte views without imposing a historical file pin."""
    path = root/_singleton_paths()['lane']
    text = path.read_text()
    physical = path.read_bytes()
    _views_after_newlines(text, physical.decode('utf-8'))
    return _typed_source.historical_text(root, path, physical.decode('utf-8'))


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


def _checked_declaration_graphs(rows):
    """Read every declaration, then check every graph when each selected one matches."""
    if not rows:
        return {'restore': False, 'declared': [], 'flags': []}
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(rows, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='declaration-graphs-') as directory:
        path = Path(directory) / 'declarations.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--declaration-graphs', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _restored_graphs(restores, graphs):
    """Read each restored declaration, then compare every source graph."""
    if not restores and not graphs:
        return
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({
        'restores': [{
            'index': index,
            'source': text,
            'name': item['name'],
            'owner': list(item['owner']),
        } for index, item, text in restores],
        'graphs': [{
            'label': label,
            'actual': actual,
            'source': source,
        } for actual, source, label in graphs],
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='singleton-restored-graphs-') as directory:
        path = Path(directory) / 'graphs.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--restored-graphs', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify_premises(root):
    record = read_record(root)
    _prepare_rounded(list(record['modules']))
    # Whole module tokens bind imports, declaration owners and local names.
    checked = []
    for path, item in record['modules'].items():
        actual = _reviewed_text(root, path, record)
        checked.append((path, actual, item['source'], item['token_sha256']))
    matched_flags = _significant_matches([
        (actual, source) for _, actual, source, _ in checked])
    pending = []
    for index, (path, actual, _, token) in enumerate(checked):
        if not matched_flags[index]:
            pending.append((path, actual, token))
    _verify_dependencies(pending)
    labels = _singleton_paths()
    scope_items = []
    lane_index = None
    for path, expected in record['import_scopes'].items():
        text = _lane_text(root) if path == labels['lane'] else _typed_source.historical_text(root, root/path, (root/path).read_text())
        if path == labels['lane']:
            lane_index = len(scope_items)
        scope_items.append((path, text, expected))
    minimum_items = []
    for item in record['declarations']:
        minimum_items.append((item, tuple(item['owner'])))
    checked = _scopes_then_minima(
        scope_items, lane_index, labels['import_scope'], minimum_items)
    if checked['restore']:
        prefixes = checked['prefixes']
        path, text, expected = scope_items[lane_index]
        text = full_audit.reviewed_text(root, path, text)
        prefixes[lane_index] = _import_scope(text)
        prepared = []
        for index, (path, _text, expected) in enumerate(scope_items):
            prepared.append((prefixes[index], expected,
                             labels['import_scope'] + path))
        _significant_graphs(prepared)
        selected_flags = _selected_minima([
            (item['path'], item['name'], owner)
            for item, owner in minimum_items])
    else:
        selected_flags = [flag == 'true' for flag in checked['minima']]
    loaded = []
    for (item, _owner), selected in zip(minimum_items, selected_flags):
        text = _lane_text(root) if selected else _typed_source.historical_text(root, root/item['path'], (root/item['path']).read_text())
        loaded.append((item, selected, text))
    rows = []
    for item, selected, text in loaded:
        row = {
            'source': text,
            'name': item['name'],
            'owner': list(item['owner']),
            'graph': item['source'],
            'label': labels['declaration'] + item['name'],
        }
        if selected:
            row['expected'] = item['source']
        rows.append(row)
    checked = _checked_declaration_graphs(rows)
    if checked['restore']:
        declared = checked['declared']
        selected_flags = [flag == 'true' for flag in checked['flags']]
        selected_match = {}
        flag_index = 0
        for index, (_item, selected, _text) in enumerate(loaded):
            if not selected:
                continue
            selected_match[index] = selected_flags[flag_index]
            flag_index += 1
        restores = []
        for index, (item, _selected, text) in enumerate(loaded):
            if index in selected_match and not selected_match[index]:
                text = full_audit.reviewed_text(root, item['path'], text)
                restores.append((index, item, text))
        prepared = []
        for index, (item, _selected, _text) in enumerate(loaded):
            prepared.append((declared[index], item['source'],
                             labels['declaration'] + item['name']))
        _restored_graphs(restores, prepared)
    return record


def verify(root):
    record = read_record(root)
    _prepare_rounded(list(record['modules']))
    dependencies = []
    for path, item in record['modules'].items():
        dependencies.append((
            path, _reviewed_text(root, path, record), item['token_sha256']))
    _verify_dependencies(dependencies)
    verify_premises(root)
    return record
