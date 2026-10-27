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
EXPECTED={
'extensions/carla/spiral_grouped_roundoff_proof.mojo':'a8f3beca23c8d6a84d01f5eebecb0a01cd2102aad4e226ed6a782722733a86b7',
'extensions/carla/spiral_roundoff_proof.mojo':'634c4f0f448b472301a42ad6065655f60cf78121f12bafa64085a1e67108fc0f'}
INTERVAL='e2e87c519ed45fb4ec77d9a54aad08406461b17805287874c9b05ddb6bf49b11'

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
        raise ValueError('Missing or ambiguous selector constant') from error
    return moments.fraction_of_word(moments.decimal_word(literal))

def verify_text(modules, interval, trig):
    import json
    import os
    import subprocess
    import tempfile
    if set(modules) != set(EXPECTED):
        raise ValueError('Wrong selection producer set')
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='selection-gate-') as directory:
        folder = Path(directory)
        names = {
            '--grouped': 'extensions/carla/spiral_grouped_roundoff_proof.mojo',
            '--roundoff': 'extensions/carla/spiral_roundoff_proof.mojo',
        }
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
    if (path == 'extensions/carla/spiral_grouped_roundoff_proof.mojo'
            and ideal_projection.token_sha256(text) != EXPECTED[path]):
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
    modules = {p:_producer_text(root,p, _operation=_operation) for p in EXPECTED}
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


def _declaration_bounds(text, name, owner):
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
    header, _, body = result.stdout.partition('\n')
    first, last = header.split()
    return body, int(first), int(last)


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


def predecessor_text(root, path, *, _operation=None):
    """Verify both actual producers before reconstructing one legacy module."""
# #333 explicit historical provenance views; current inputs remain operation-owned.
    import json
    root=Path(root)
    verify(root, _operation=_operation)
    payload=_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/selection-finiteness-contract.json', (root/'tools/carla_lane_oracle/selection-finiteness-contract.json').read_bytes(), _operation=_operation)
    _gate_record(payload)
    record=json.loads(payload,object_pairs_hook=source_contracts.unique_keys)
    if path not in EXPECTED or set(record['modules'])!=set(EXPECTED):
        raise ValueError('Wrong selection predecessor module')
    item=record['modules'][path]
    name=('_try_spiral_grouped_roundoff_envelope' if path.endswith('/spiral_grouped_roundoff_proof.mojo')
          else '_try_spiral_roundoff_envelope')
    text=_producer_text(root,path, _operation=_operation)
    body, first, last = _declaration_bounds(text, name, ())
    current_doc, recorded_doc = _significant_documents([
        body, item['after_complete_function']])
    if current_doc != recorded_doc:
        raise ValueError('Selection complete successor body changed')
    restored=_replace_span(text, first, last, item['before_complete_function'])
    _gate_restored(restored, item['before_token_sha256'])
    return restored
