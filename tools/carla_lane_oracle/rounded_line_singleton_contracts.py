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


def _gate_graphs(pairs):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    rows = [{'label': label, 'actual': actual, 'expected': expected}
            for actual, expected, label in pairs]
    with tempfile.TemporaryDirectory(prefix='singleton-graphs-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(rows))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_singleton_gate',
             '--graphs', str(folder)],
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


def _same_text(actual, expected):
    if __package__:
        from . import ideal_projection
    else:
        import ideal_projection
    return ideal_projection.texts_match(actual, expected)


def _selected_minimum(path, name, owner):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({
        'path': path, 'name': name, 'owner': list(owner),
    }, separators=(',', ':'))
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
    return result.stdout.strip() == 'true'


_SINGLETON_PATHS = None


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
    if not _same_text(path, _singleton_paths()['rounded_line']):
        return text
    current_doc, recorded_doc = _significant_documents([
        text, record['modules'][path]['source']])
    if _same_text(current_doc, recorded_doc):
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


def _import_scope(text):
    """Return the consumer prefix before the first definition."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='import-scope-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--import-scope', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


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


def _lane_text(root):
    """Compare actual text/byte views without imposing a historical file pin."""
    path = root/_singleton_paths()['lane']
    text = path.read_text()
    physical = path.read_bytes()
    decoded = _universal_newlines(physical.decode('utf-8'))
    _gate_views(text, decoded)
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


def _declarations(items):
    """Return the declaration texts in the requested order."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not items:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='singleton-declarations-') as directory:
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


def verify_premises(root):
    record = read_record(root)
    # Whole module tokens bind imports, declaration owners and local names.
    checked = []
    for path, item in record['modules'].items():
        actual = _reviewed_text(root, path, record)
        checked.append((path, actual, item['source'], item['token_sha256']))
    module_docs = _significant_documents(
        [text for _, actual, source, _ in checked for text in (actual, source)])
    pending = []
    for index, (path, actual, _, token) in enumerate(checked):
        if not _same_text(module_docs[index * 2], module_docs[index * 2 + 1]):
            pending.append((path, actual, token))
    _verify_dependencies(pending)
    prepared = []
    labels = _singleton_paths()
    for path, expected in record['import_scopes'].items():
        text = _lane_text(root) if path == labels['lane'] else _typed_source.historical_text(root, root/path, (root/path).read_text())
        actual = _import_scope(text)
        if path == labels['lane']:
            current_doc, recorded_doc = _significant_documents([actual, expected])
            if not _same_text(current_doc, recorded_doc):
                # Only a changed consumed scope requests complete current admission.
                text = full_audit.reviewed_text(root, path, text)
                actual = _import_scope(text)
        prepared.append((actual, expected, labels['import_scope'] + path))
    if prepared:
        scope_docs = _significant_documents(
            [text for actual, expected, _ in prepared for text in (actual, expected)])
        _gate_graphs([
            (scope_docs[index * 2], scope_docs[index * 2 + 1], label)
            for index, (_, _, label) in enumerate(prepared)])
    loaded = []
    for item in record['declarations']:
        selected = _selected_minimum(item['path'], item['name'], tuple(item['owner']))
        text = _lane_text(root) if selected else _typed_source.historical_text(root, root/item['path'], (root/item['path']).read_text())
        loaded.append((item, selected, text))
    declared = _declarations([{
        'source': text,
        'name': item['name'],
        'owner': list(item['owner']),
    } for item, _selected, text in loaded])
    prepared = []
    for index, (item, selected, text) in enumerate(loaded):
        actual = declared[index]
        if selected:
            current_doc, recorded_doc = _significant_documents([
                actual, item['source']])
            if not _same_text(current_doc, recorded_doc):
                text = full_audit.reviewed_text(root, item['path'], text)
                actual = _declaration(text, item['name'], tuple(item['owner']))
        prepared.append((actual, item['source'],
                         labels['declaration'] + item['name']))
    if prepared:
        declaration_docs = _significant_documents(
            [text for actual, source, _ in prepared for text in (actual, source)])
        _gate_graphs([
            (declaration_docs[index * 2], declaration_docs[index * 2 + 1], label)
            for index, (_, _, label) in enumerate(prepared)])
    return record


def verify(root):
    record = read_record(root)
    dependencies = []
    for path, item in record['modules'].items():
        dependencies.append((
            path, _reviewed_text(root, path, record), item['token_sha256']))
    _verify_dependencies(dependencies)
    verify_premises(root)
    return record
