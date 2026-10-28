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
    with tempfile.TemporaryDirectory(prefix='dispatch-source-graphs-') as directory:
        path = Path(directory) / 'graphs.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_gate',
             '--source-graphs', str(path)],
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


def _declaration_matches(items):
    """Return whether each declaration matches its recorded source."""
    if not items:
        return []
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps([
        {
            'source': source,
            'name': name,
            'owner': list(owner),
            'expected': expected,
        }
        for source, name, owner, expected in items
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='declaration-match-') as directory:
        path = Path(directory) / 'declarations.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_lane_declarations',
             '--match', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


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
    with tempfile.TemporaryDirectory(prefix='dispatch-token-match-') as directory:
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
    return json.loads(result.stdout)


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


def _dispatch_choices(items):
    """Return `current` or `restore` for each source."""
    if not items:
        return []
    import json
    return json.loads(_dispatch_query('--choice', items))


def reviewed_sources(root, items, *, _operation=None):
    """Return each source after its reviewed choice."""
    if _operation is not None:
        _check_operation(root, _operation)
    if not items:
        return []
    labels = _dispatch_labels()
    loaded = []
    for path, expected in items:
        text = _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)
        loaded.append((path, expected, text))
    choices = _dispatch_choices([{
        'text': text,
        'expected': expected,
        'path': path,
        'dispatch_path': labels['dispatch_path'],
    } for path, expected, text in loaded])
    restored = None
    operation = {} if _operation is None else {'_operation': _operation}
    results = []
    for (path, expected, text), choice in zip(loaded, choices):
        if choice == labels['current']:
            results.append(text)
            continue
        if choice != labels['restore']:
            raise ValueError(labels['unreviewed'] + path)
        if restored is None:
            if __package__:
                from . import raw_cut_inverse_contracts as raw
            else:
                import raw_cut_inverse_contracts as raw
            restored = raw.verify(root, **operation)
        _gate_edge(restored['before_token_sha256'], expected)
        results.append(restored['before_source'])
    return results


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

def _declaration_tokens(items):
    """Read each declaration and require its recorded token digest."""
    if not items:
        return
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps([
        {
            'source': source,
            'name': name,
            'owner': list(owner),
            'token': token,
            'label': label,
        }
        for source, name, owner, token, label in items
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='declaration-tokens-') as directory:
        path = Path(directory) / 'declarations.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_gate',
             '--declaration-tokens', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


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


def _declaration_fallbacks(items):
    """Compare each premise declaration and choose its fallback."""
    if not items:
        return [], []
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps([
        {
            'source': source,
            'name': name,
            'owner': list(owner),
            'expected': expected,
            'path': path,
        }
        for source, name, owner, expected, path in items
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='declaration-fallbacks-') as directory:
        path = Path(directory) / 'declarations.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_lane_declarations',
             '--fallbacks', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    return parsed['flags'], parsed['fallbacks']


def verify_premises(root, *, _operation=None):
    # Deliberately independent of complete-module successor digest checks.
    # Bind operation graphs, local guards, full caller bodies, and declarations.
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    labels = _dispatch_labels()
    operation_args = {} if _operation is None else {'_operation': _operation}
    prepared = []
    source_items = list(record['sources'].items())
    chosen = reviewed_sources(root, [
        (path, item['after_token_sha256']) for path, item in source_items
    ], **operation_args)
    for (path, item), text in zip(source_items, chosen):
        prepared.append((
            text,
            item['after_source'],
            labels['successor_operations'] + path))
    _significant_graphs(prepared)
    prepared = []
    for path, item in record['premise_modules'].items():
        prepared.append((
            _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation),
            item['source'],
            labels['premise_modules'] + path))
    _significant_graphs(prepared)
    loaded = []
    for item in record['premise_functions']:
        physical_text = _observe_text(root, item['path'], (root/item['path']).read_text(), _operation=_operation)
        text = _typed_source.historical_text(root, item['path'], physical_text, _operation=_operation)
        loaded.append((item, physical_text, text))
    matched_flags, fallbacks = _declaration_fallbacks([
        (text, item['name'], item['owner'], item['source'], item['path'])
        for item, _physical_text, text in loaded])
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
            seed_flags = _declaration_matches([
                (predecessor, item['name'], [], item['source'])
                for _index, item, predecessor in seed_rows])
        except (ValueError, OSError) as error:
            require(False, labels['seed_message'] + str(error))
        for position, (index, _item, _predecessor) in enumerate(seed_rows):
            seed_matched[index] = seed_flags[position] == 'true'
    lane_matched = {}
    if any(flag == labels['lane'] for flag in fallbacks):
        if __package__:
            from . import lane_control_contracts as lane
        else:
            import lane_control_contracts as lane
        lane_rows = [
            (index, item) for index, (item, _physical_text, _text) in enumerate(loaded)
            if fallbacks[index] == labels['lane']]
        try:
            lane_flags = lane.accepts_predecessors(root, [
                (item['path'], item['name'], tuple(item['owner']), item['source'])
                for _index, item in lane_rows
            ], **operation_args)
        except RuntimeError as error:
            require(False, labels['lane_message'] + str(error))
        for (index, _item), flag in zip(lane_rows, lane_flags):
            lane_matched[index] = flag
    for index, (item, _physical_text, _text) in enumerate(loaded):
        matched = matched_flags[index] == 'true'
        fallback = fallbacks[index]
        if fallback == labels['seed']:
            matched = seed_matched[index]
        if fallback == labels['lane']:
            matched = lane_matched[index]
        require(matched, labels['premise_function'] + item['name'])
    references = []
    for item in record['reference_functions']:
        text = _typed_source.historical_text(root, item['path'], _observe_text(root, item['path'], (root/item['path']).read_text(), _operation=_operation), _operation=_operation)
        references.append((item, text))
    _declaration_tokens([
        (text, item['name'], [], item['token_sha256'],
         labels['reference'] + item['name'])
        for item, text in references])
    return record


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    labels = _dispatch_labels()
    operation_args = {} if _operation is None else {'_operation': _operation}
    pairs = []
    source_items = list(record['sources'].items())
    chosen = reviewed_sources(root, [
        (path, item['after_token_sha256']) for path, item in source_items
    ], **operation_args)
    for (path, item), text in zip(source_items, chosen):
        pairs.append((text, item['after_token_sha256'], labels['complete'] + path))
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
