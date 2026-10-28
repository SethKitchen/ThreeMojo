# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Source-bound private support and dispatch successor, without a coverage waiver.

The exact historical pin files stay immutable in this standalone proposal.
A composed integration must migrate runtime and guarded-caller pins separately.
"""

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
    record = _migration_records()['dispatch']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']

_PATHS = None


def _paths():
    """Return the dispatch sources and the protected dependency paths."""
    global _PATHS
    if _PATHS is not None:
        return _PATHS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _PATHS = json.loads(result.stdout)
    return _PATHS


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    if name == 'SOURCE_PATHS':
        return tuple(_paths()['sources'])
    if name == 'PROTECTED_INPUTS':
        _ensure_migration()
        data = _paths()
        return (MIGRATION, *data['sources'], *data['protected'])
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


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


def require(condition, message):
    if not condition:
        raise ValueError(_contract_prefixes()['dispatch'] + message)


def _gate(payload):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='dispatch-gate-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_gate',
             '--migration', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_edge(recorded, expected):
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_gate',
         '--edge', recorded, '--expected', expected],
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
    with tempfile.TemporaryDirectory(prefix='dispatch-graphs-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(rows))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_gate',
             '--graphs', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def read_record(root):
    _ensure_migration()
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    _gate(payload)
    return json.loads(payload, object_pairs_hook=source.unique_keys)



def _dispatch_query(mode, payload):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='dispatch-source-') as directory:
        path = Path(directory) / 'source.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_source',
             mode, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


def _match_flags(pairs):
    """Return whether each actual text equals its expected text."""
    if not pairs:
        return []
    import json
    return json.loads(_dispatch_query('--match', [
        {'actual': actual, 'expected': expected} for actual, expected in pairs]))


_DISPATCH_LABELS = None


def _dispatch_labels():
    """Return the dispatch path, choice names, and premise messages."""
    global _DISPATCH_LABELS
    if _DISPATCH_LABELS is not None:
        return _DISPATCH_LABELS
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_labels'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _DISPATCH_LABELS = json.loads(result.stdout)
    return _DISPATCH_LABELS


def reviewed_source(root, path, expected, *, _operation=None):
    """Compose the exact raw inverse theorem with this retained outer proof."""
    if _operation is not None:
        _check_operation(root, _operation)
    text = _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)
    labels = _dispatch_labels()
    choice = _dispatch_query('--choice', {
        'text': text,
        'expected': expected,
        'path': path,
        'dispatch_path': labels['dispatch_path'],
    })
    if choice == labels['current']:
        return text
    if choice != labels['restore']:
        raise ValueError(labels['unreviewed'] + path)
    if __package__:
        from . import raw_cut_inverse_contracts as raw
    else:
        import raw_cut_inverse_contracts as raw
    record = raw.verify(root, **({} if _operation is None else {'_operation': _operation}))
    _gate_edge(record['before_token_sha256'], expected)
    return record['before_source']

def _gate_tokens(pairs):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='dispatch-tokens-') as directory:
        folder = Path(directory)
        labels = []
        for index, (text, token, label) in enumerate(pairs):
            (folder / f'{index}.text').write_text(text)
            labels.append({'label': label, 'token': token})
        (folder / 'labels.json').write_text(json.dumps(labels))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_gate',
             '--tokens', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


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
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not items:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='dispatch-declarations-') as directory:
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


def _premise_fallbacks(items):
    """Return `seed`, `lane`, or `none` for each premise."""
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
        {'matched': matched, 'path': path, 'name': name, 'owner': list(owner)}
        for matched, path, name, owner in items
    ], separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='premise-fallback-') as directory:
        record = Path(directory) / 'fallback.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_premise_fallback', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def verify_premises(root, *, _operation=None):
    # Deliberately independent of complete-module successor digest checks.
    # Bind operation graphs, local guards, full caller bodies, and declarations.
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    labels = _dispatch_labels()
    operation_args = {} if _operation is None else {'_operation': _operation}
    prepared = []
    for path, item in record['sources'].items():
        prepared.append((
            reviewed_source(root, path, item['after_token_sha256'], **operation_args),
            item['after_source'],
            labels['successor_operations'] + path))
    if prepared:
        docs = _significant_documents(
            [text for actual, expected, _ in prepared for text in (actual, expected)])
        _gate_graphs([
            (docs[index * 2], docs[index * 2 + 1], label)
            for index, (_, _, label) in enumerate(prepared)])
    prepared = []
    for path, item in record['premise_modules'].items():
        prepared.append((
            _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation),
            item['source'],
            labels['premise_modules'] + path))
    if prepared:
        docs = _significant_documents(
            [text for actual, expected, _ in prepared for text in (actual, expected)])
        _gate_graphs([
            (docs[index * 2], docs[index * 2 + 1], label)
            for index, (_, _, label) in enumerate(prepared)])
    loaded = []
    for item in record['premise_functions']:
        physical_text = _observe_text(root, item['path'], (root/item['path']).read_text(), _operation=_operation)
        text = _typed_source.historical_text(root, item['path'], physical_text, _operation=_operation)
        loaded.append((item, physical_text, text))
    declared = _declarations([{
        'source': text,
        'name': item['name'],
        'owner': list(item['owner']),
    } for item, _physical_text, text in loaded])
    premise_docs = _significant_documents([
        text for index, (item, _physical_text, _text) in enumerate(loaded)
        for text in (declared[index], item['source'])])
    matched_flags = _match_flags([
        (premise_docs[index * 2], premise_docs[index * 2 + 1])
        for index in range(len(loaded))])
    fallbacks = _premise_fallbacks([
        (matched_flags[index] == 'true', item['path'], item['name'], tuple(item['owner']))
        for index, (item, _physical_text, _text) in enumerate(loaded)])
    seed_matched = {}
    if any(flag == labels['seed'] for flag in fallbacks):
        if __package__:
            from . import seed_count_contracts as seed_count
        else:
            import seed_count_contracts as seed_count
        seed_rows = []
        for index, (item, physical_text, _text) in enumerate(loaded):
            if fallbacks[index] != labels['seed']:
                continue
            try:
                predecessor = seed_count.reviewed_text(
                    root, item['path'], physical_text, **operation_args)
            except (ValueError, OSError) as error:
                require(False, labels['seed_message'] + str(error))
            seed_rows.append((index, item, predecessor))
        try:
            declared_seeds = _declarations([{
                'source': predecessor,
                'name': item['name'],
                'owner': [],
            } for _index, item, predecessor in seed_rows])
            seed_docs = _significant_documents([
                text for position, (_index, item, _predecessor) in enumerate(seed_rows)
                for text in (declared_seeds[position], item['source'])])
            seed_flags = _match_flags([
                (seed_docs[position * 2], seed_docs[position * 2 + 1])
                for position in range(len(seed_rows))])
        except (ValueError, OSError) as error:
            require(False, labels['seed_message'] + str(error))
        for position, (index, _item, _predecessor) in enumerate(seed_rows):
            seed_matched[index] = seed_flags[position] == 'true'
    for index, (item, _physical_text, _text) in enumerate(loaded):
        matched = matched_flags[index] == 'true'
        fallback = fallbacks[index]
        if fallback == labels['seed']:
            matched = seed_matched[index]
        if fallback == labels['lane']:
            try:
                if __package__:
                    from . import lane_control_contracts as lane
                else:
                    import lane_control_contracts as lane
                matched = lane.accepts_predecessor(root, item['path'], item['name'],
                                                  tuple(item['owner']), item['source'], **operation_args)
            except RuntimeError as error:
                require(False, labels['lane_message'] + str(error))
        require(matched, labels['premise_function'] + item['name'])
    pairs = []
    references = []
    for item in record['reference_functions']:
        text = _typed_source.historical_text(root, item['path'], _observe_text(root, item['path'], (root/item['path']).read_text(), _operation=_operation), _operation=_operation)
        references.append((item, text))
    reference_declarations = _declarations([{
        'source': text,
        'name': item['name'],
        'owner': [],
    } for item, text in references])
    for index, (item, _text) in enumerate(references):
        pairs.append((reference_declarations[index], item['token_sha256'],
                      labels['reference'] + item['name']))
    if pairs:
        _gate_tokens(pairs)
    return record


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    labels = _dispatch_labels()
    operation_args = {} if _operation is None else {'_operation': _operation}
    pairs = []
    for path, item in record['sources'].items():
        pairs.append((reviewed_source(root,path,item['after_token_sha256'], **operation_args),
                      item['after_token_sha256'], labels['complete'] + path))
    if pairs:
        _gate_tokens(pairs)
    verify_premises(root, **operation_args)
    return record


def _gate_pin(payload, digest, label):
    _gate_pins([(payload, digest, label)])


def _gate_pins(items):
    """Require every historical pin digest, in order."""
    if not items:
        return
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='dispatch-pins-') as directory:
        folder = Path(directory)
        rows = []
        for index, (payload, digest, label) in enumerate(items):
            name = str(index)
            (folder / name).write_bytes(payload)
            rows.append({'name': name, 'sha': digest, 'label': label})
        (folder / 'labels.json').write_text(json.dumps(rows, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_gate',
             '--pins', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify_historical_pin_inputs(root):
    # Use only before the centrally reviewed integration migration. This is
    # not called by verify: a later exact pin successor must remain possible.
    record = read_record(root)
    loaded = []
    for path, expected in record['historical_pins'].items():
        loaded.append((
            _typed_source.historical_bytes(root, root/path, (root/path).read_bytes()),
            expected, path))
    _gate_pins(loaded)
