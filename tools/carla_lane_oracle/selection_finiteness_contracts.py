"""Bind local ordered/nonnegative-error selection producers and exact constants."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source
from pathlib import Path
if __package__:
    from . import source_contracts
else:
    import source_contracts
_EXPECTED = None


def _expected():
    """Return the two selection producer digests in reviewed order."""
    global _EXPECTED
    if _EXPECTED is not None:
        return _EXPECTED
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_selection_producers'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _EXPECTED = json.loads(result.stdout)
    return _EXPECTED


def __getattr__(name):
    if name == 'EXPECTED':
        return _expected()
    if name == 'INTERVAL':
        return _selection_labels()['interval']
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')

def _scalar(text,name):
    # Lazy imports avoid a cycle with maintained migration verifiers.
    if __package__:
        from . import spiral_moments as moments
        from . import ideal_projection
    else:
        import spiral_moments as moments
        import ideal_projection
    try:
        literal = ideal_projection.scalar_literal(text, name)
    except ValueError as error:
        raise ValueError(_selection_labels()['scalar']) from error
    return moments.fraction_of_word(moments.decimal_word(literal))

def verify_text(modules, interval, trig):
    import json
    import os
    import subprocess
    import tempfile
    if __package__:
        from . import ideal_projection
    else:
        import ideal_projection
    ideal_projection.moment_guard('--names', {
        'names': list(modules),
        'expected': list(_expected()),
        'message': _selection_labels()['producer_set'],
    })
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='selection-gate-') as directory:
        folder = Path(directory)
        names = dict(zip(('--grouped', '--roundoff'), _expected()))
        command = ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_selection_gate']
        for flag, path in names.items():
            target = folder / flag.strip('-') 
            target.write_text(modules[path])
            command.extend([flag, str(target)])
        for flag, text in (('--interval', interval), ('--trig', trig)):
            target = folder / flag.strip('-')
            target.write_text(text)
            command.extend([flag, str(target)])
        result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)

def _producer_text(root, path, *, _operation=None):
    """Admit only the exact current Y successor before a selection view."""
    text = (root/path).read_text()
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        text = _typed_source.historical_text(root, path, full_audit._observe_text(root, path, text, _operation=_operation), _operation=_operation)
    if __package__:
        from . import ideal_projection
    else:
        import ideal_projection
    if (path == next(iter(_expected()))
            and not ideal_projection.token_digest_equals(text, _expected()[path])):
        if __package__:
            from . import grouped_y_finiteness_contracts as grouped_y
        else:
            import grouped_y_finiteness_contracts as grouped_y
        text = grouped_y.predecessor_text(root, path, _operation=_operation)
    return text


def verify(root, *, _operation=None):
    root=Path(root)
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    modules = {p:_producer_text(root,p, _operation=_operation) for p in _expected()}
    interval = (root/'extensions/carla/curve_interval.mojo').read_text()
    if _operation is not None:
        interval = _typed_source.historical_text(root, 'extensions/carla/curve_interval.mojo', full_audit._observe_text(
            root, 'extensions/carla/curve_interval.mojo', interval, _operation=_operation), _operation=_operation)
    trig = (root/'extensions/carla/curve_trig.mojo').read_text()
    if _operation is not None:
        trig = _typed_source.historical_text(root, 'extensions/carla/curve_trig.mojo', full_audit._observe_text(
            root, 'extensions/carla/curve_trig.mojo', trig, _operation=_operation), _operation=_operation)
    return verify_text(modules, interval, trig)


def _gate_record(payload):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='selection-record-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_selection_record_gate',
             '--migration', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_restored(text, expected):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='selection-restored-') as directory:
        target = Path(directory) / 'restored.mojo'
        target.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_selection_record_gate', '--source', str(target),
             '--token', expected],
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


def _selection_predecessor(payload):
    """Return one restored selection predecessor."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='selection-predecessor-') as directory:
        path = Path(directory) / 'predecessor.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_selection_predecessor', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _declaration_bounds(text, name, owner):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='declaration-bounds-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_cleanup_gate', '--bounds', str(source),
                     '--name', name]
        for part in owner:
            arguments.extend(['--owner', part])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    record = json.loads(result.stdout)
    return record['text'], record['first'], record['last']


def _replace_span(text, first, last, replacement):
    """Replace one half-open line span in `text`."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='line-span-') as directory:
        folder = Path(directory)
        (folder / 'source.text').write_text(text)
        (folder / 'replacement.text').write_text(replacement)
        (folder / 'span.text').write_text(str(first) + ' ' + str(last) + '\n')
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--splice', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _envelope_name(path):
    """Return the reviewed roundoff envelope for one module path."""
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_roundoff_name',
         path],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


_SELECTION_LABELS = None


def _selection_labels():
    """Return the selection contract path and the predecessor messages."""
    global _SELECTION_LABELS
    if _SELECTION_LABELS is not None:
        return _SELECTION_LABELS
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_selection_labels'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _SELECTION_LABELS = json.loads(result.stdout)
    return _SELECTION_LABELS


def predecessor_text(root, path, *, _operation=None):
    """Verify both actual producers before reconstructing one legacy module."""
# #333 explicit historical provenance views; current inputs remain operation-owned.
    import json
    root=Path(root)
    verify(root, _operation=_operation)
    contract = _selection_labels()['contract']
    payload=_typed_source.historical_bytes(root, root/contract, (root/contract).read_bytes(), _operation=_operation)
    _gate_record(payload)
    record=json.loads(payload,object_pairs_hook=source_contracts.unique_keys)
    item=record['modules'][path]
    name=_envelope_name(path)
    text=_producer_text(root,path, _operation=_operation)
    return _selection_predecessor({
        'path': path,
        'names': list(_expected()),
        'record_names': list(record['modules']),
        'message': _selection_labels()['predecessor'],
        'body_message': _selection_labels()['body'],
        'name': name,
        'text': text,
        'after': item['after_complete_function'],
        'before': item['before_complete_function'],
        'token': item['before_token_sha256'],
    })
