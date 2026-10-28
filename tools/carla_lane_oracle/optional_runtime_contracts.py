#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reviewed obligations for the optional runtime dependency migration.

The checks below name the critical source edges and preconditions separately
from complete token bindings. Neither is a mathematical proof or a native
execution/coverage claim. The migration record retains the external proof
lineage and the exact selected production bytes. Nothing refreshes pins here.
"""
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

from functools import lru_cache

try:
    import sum2_guard_contracts as guard
    import source_contracts
    import full_audit_cleanup_contracts as full_audit
except ModuleNotFoundError:
    from tools.carla_lane_oracle import sum2_guard_contracts as guard, source_contracts
    from tools.carla_lane_oracle import full_audit_cleanup_contracts as full_audit

_NEW_MODULES = None


def _new_modules():
    """Return the five optional-runtime module names in reviewed order."""
    global _NEW_MODULES
    if _NEW_MODULES is not None:
        return _NEW_MODULES
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_optional_runtime_modules'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _NEW_MODULES = json.loads(result.stdout)
    return _NEW_MODULES


def __getattr__(name):
    if name == 'NEW_MODULES':
        return tuple(_new_modules())
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


_RUNTIME_CONTRACT = None


def _runtime_contract():
    """Return the optional-runtime contract messages."""
    global _RUNTIME_CONTRACT
    if _RUNTIME_CONTRACT is not None:
        return _RUNTIME_CONTRACT
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_optional_runtime_messages'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _RUNTIME_CONTRACT = json.loads(result.stdout)
    return _RUNTIME_CONTRACT


def require(condition, message):
    if not condition:
        raise ValueError(_runtime_contract()['prefix'] + message)


def body(root, module, name, *, _operation=None):
    text = _typed_source.historical_text(root, root / ('extensions/carla/' + module + '.mojo'), source._observe_text(root, (root / ('extensions/carla/' + module + '.mojo')).relative_to(root).as_posix(), (root / ('extensions/carla/' + module + '.mojo')).read_text(), _operation=_operation), _operation=_operation)
    return body_from_source(text, name)


def _lexical_directory(flag, texts):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not texts:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='optional-lexical-') as directory:
        folder = Path(directory)
        for index, text in enumerate(texts):
            (folder / f'{index}.text').write_text(text)
        (folder / 'count').write_text(str(len(texts)))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             flag, str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _semantic_declaration(text, name):
    """Return one declaration with postfix move sigils removed."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='semantic-declaration-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_semantic_declaration', str(source), name],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        contract = _runtime_contract()
        if message == contract['move']:
            message = contract['prefix'] + message
        raise ValueError(message)
    return result.stdout


def _semantic_declarations(items):
    """Return the moved declarations for one group."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='semantic-declarations-') as directory:
        path = Path(directory) / 'declarations.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_semantic_declarations', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        contract = _runtime_contract()
        if message == contract['move']:
            message = contract['prefix'] + message
        raise ValueError(message)
    return json.loads(result.stdout)


def _semantic_step(payload):
    """Bind one group and check its edges."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='semantic-step-') as directory:
        path = Path(directory) / 'step.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_semantic_step',
             '--with-contract', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


class _RuntimeFunction:
    """One moved helper declaration checked by the Mojo fragment gate."""

    def __init__(self, name, source):
        self.name = name
        self._runtime_name = name
        self._runtime_source = source


def body_from_source(text, name):
    """Bind one moved declaration; this grants no source admission."""
    # The historical AST adapter has no lane-search move arguments. Remove
    # only postfix move sigils before argument delimiters for this semantic
    # view; complete lexical contracts separately retain every move token.
    return _RuntimeFunction(name, _semantic_declaration(text, name))


def _fragment_checks(items):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not items:
        return
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='fragment-checks-') as directory:
        path = Path(directory) / 'checks.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_fragment_checks', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        contract = _runtime_contract()
        if message.startswith(contract['fragment']):
            message = contract['prefix'] + message
        raise ValueError(message)


def _edge(source, name, kind, fragment, label, expected=1, message=None, call=''):
    item = {
        'source': source, 'name': name, 'kind': kind, 'fragment': fragment,
        'label': label, 'expected': expected,
    }
    if message is not None:
        item['message'] = message
    if call:
        item['call'] = call
    return item


def _node_edge(node, kind, fragment, label, expected=1, message=None, call='',
               source_label=None):
    return _edge(
        _runtime_source(node, source_label or label), node._runtime_name, kind,
        fragment, label, expected, message, call)


def _runtime_source(node, label):
    source = getattr(node, '_runtime_source', None)
    require(source is not None, label)
    return source


def contains(node, text, label, count=1):
    _fragment_checks([_node_edge(node, 'contains', text, label, count)])


def expression(node, text, label, count=1):
    _fragment_checks([_node_edge(node, 'expression', text, label, count)])


def sequence(node, text, label):
    """Bind adjacent statements in one suite, without textual sentinels."""
    _fragment_checks([_node_edge(node, 'sequence', text, label)])


def _fresh_item(node):
    contract = _runtime_contract()
    fragment = contract['fresh_fragment']
    label = contract['fresh_label'] + node.name
    return _node_edge(node, 'first', fragment, node.name, message=label)


def fresh_guard(node):
    _fragment_checks([_fresh_item(node)])


# Removal is a scheduling decision, not a rejection of the standalone model's
# mathematics. Keep its proof and integer admission obligations below. A new
# production consumer, including an alias/re-export in a new namespace, needs
# a separate review; comments, docstrings and test-only callers are inert here.
@lru_cache(maxsize=256)
def executable_names(text):
    return frozenset(_lexical_directory('--names', [text])[0])


def _observed_consumers(items):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps([{'path': path, 'text': text} for path, text in items],
                         separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='optional-consumers-') as directory:
        path = Path(directory) / 'consumers.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_optional_consumers', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _production_paths(roots, paths):
    """Return which relative paths stay in the production scan."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not paths:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'roots': list(roots), 'paths': list(paths)}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='production-paths-') as directory:
        record = Path(directory) / 'paths.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_production_paths', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    flags = json.loads(result.stdout)
    if len(flags) != len(paths):
        raise ValueError(_runtime_contract()['paths'])
    return flags


def _watched_names():
    """Return the model names and the removed search names."""
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_watched_model_names'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _model_mentions(names, texts):
    """Return which texts contain one of `names`."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not texts:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    framed = bytearray()
    for text in texts:
        raw = text.encode('utf-8')
        framed += str(len(raw)).encode('ascii') + b'\n' + raw
    with tempfile.TemporaryDirectory(prefix='model-mentions-') as directory:
        folder = Path(directory)
        names_path = folder / 'names.json'
        texts_path = folder / 'texts.bin'
        names_path.write_text(json.dumps(list(names), separators=(',', ':')))
        texts_path.write_bytes(framed)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_model_mentions',
             str(names_path), str(texts_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    flags = json.loads(result.stdout)
    if len(flags) != len(texts):
        raise ValueError(_runtime_contract()['models'])
    return flags


def verify_no_containing_model_consumers(root, *, _operation=None):
    found = []
    for path in sorted(root.rglob('*.mojo')):
        found.append((path, path.relative_to(root).as_posix()))
    keep = _production_paths(guard.NONPRODUCTION, [relative for _, relative in found])
    texts = []
    relatives = []
    for (path, relative), kept in zip(found, keep):
        if not kept:
            continue
        text = _typed_source.historical_text(root, path, source._observe_text(root, (path).relative_to(root).as_posix(), path.read_text(), _operation=_operation), _operation=_operation)
        texts.append(text)
        relatives.append(relative)
    hits = _model_mentions(_watched_names(), texts)
    chosen = []
    for relative, text, hit in zip(relatives, texts, hits):
        if not hit:
            continue
        chosen.append((relative, text))
    _observed_consumers(chosen)


def _search_edges(source, name, mode):
    """Check the fresh producer, and the search predicates when requested."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='search-edges-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(source)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_runtime_search_edges', str(path), name, mode],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        contract = _runtime_contract()
        if message.startswith(contract['fragment']):
            message = contract['prefix'] + message
        raise ValueError(message)


def verify_fresh_producer(run):
    _search_edges(
        _runtime_source(run, _runtime_contract()['frontier']),
        run._runtime_name, 'fresh')


def verify_search_semantics(run):
    """Check retained historical run predicates without admitting a root.

    Actual source admission must precede the exact center predecessor.
    Historical AST fixtures can exercise diagnostics but grant no source edge.
    """
    _search_edges(
        _runtime_source(run, _runtime_contract()['frontier']),
        run._runtime_name, 'search')


def _semantic_edges(group, nodes):
    """Check one optional-runtime fragment group."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({
        key: {'name': node._runtime_name, 'source': node._runtime_source}
        for key, node in nodes.items()
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='semantic-edges-') as directory:
        path = Path(directory) / 'edges.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_semantic_edges', group, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        contract = _runtime_contract()
        if message.startswith(contract['fragment']):
            message = contract['prefix'] + message
        raise ValueError(message)


_SEMANTIC_PLAN = None


def _semantic_plan():
    """Return the optional-runtime declaration groups in reviewed order."""
    global _SEMANTIC_PLAN
    if _SEMANTIC_PLAN is not None:
        return _SEMANTIC_PLAN
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_optional_runtime_schedule'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _SEMANTIC_PLAN = json.loads(result.stdout)
    return _SEMANTIC_PLAN


def _run_semantic_steps(root, steps, operation):
    """Bind each declaration, then check that group's edges."""
    prepared = []
    for step in steps:
        loaded = []
        for item in step['bind']:
            module = item['module']
            text = _typed_source.historical_text(root, root / ('extensions/carla/' + module + '.mojo'), source._observe_text(root, (root / ('extensions/carla/' + module + '.mojo')).relative_to(root).as_posix(), (root / ('extensions/carla/' + module + '.mojo')).read_text(), _operation=operation), _operation=operation)
            loaded.append((item, text))
        prepared.append((step, loaded))
    _semantic_step({
        'steps': [{
            'group': step['group'],
            'items': [{
                'key': item['key'],
                'name': item['name'],
                'source': text,
            } for item, text in loaded],
            'bind_labels': [{
                'key': item['key'],
                'label': item['label'] if 'label' in item else item['name'],
            } for item, _text in loaded],
            'checks': [{
                'key': item['key'],
                'label': item['label'],
            } for item in step['check']] if 'check' in step else [],
            'edges': list(step['edges']),
        } for step, loaded in prepared],
    })


def verify_semantics(root, *, _operation=None):
    # Exact guarded raw -> private origin -> checked Sum2 leaf edge. The
    # global inventory also rejects any new direct or alias route to it.
    # Model data is meaningful only for the same ideal producer and owner.
    # Complete caller/source bindings cover producer smoothness and lifetime.
    plan = _semantic_plan()
    _run_semantic_steps(root, plan['before'], _operation)
    verify_no_containing_model_consumers(root, _operation=_operation)
    # The standalone helper remains reviewed and tested even though the
    # search solver no longer imports, captures, or restricts this model.
    _run_semantic_steps(root, plan['after'], _operation)
    # The exact reviewed raw inverse establishes the same immediate bracket
    # without re-evaluating predecessors. Keep every outer admission above.
    try:
        import raw_cut_inverse_contracts as raw_inverse
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import raw_cut_inverse_contracts as raw_inverse
    raw_inverse.verify_premises(root, _operation=_operation)
    # Keep all live non-lane, absence, room, fee and raw-inverse premises.
    # Only the complete live gate and exact center inverse admit a predecessor;
    # current lane failures may differ diagnostically from historical fixtures.
    previous = full_audit.reviewed_lane_before_center_text(root, _operation=_operation)
    verify_search_semantics(body_from_source(previous, plan['search']))
    # Retain the sampled-reference gate after raw-inverse diagnostics.
    if __package__:
        from .ideal_projection import verify_try_only_reference
    else:
        from ideal_projection import verify_try_only_reference
    verify_try_only_reference(_typed_source.historical_text(root, root / 'extensions/carla/curve_bounds.mojo', source._observe_text(root, (root / 'extensions/carla/curve_bounds.mojo').relative_to(root).as_posix(), (root / 'extensions/carla/curve_bounds.mojo').read_text(), _operation=_operation), _operation=_operation), root, _operation=_operation)
    return _optional_runtime_result(_new_modules())


def _optional_runtime_result(modules):
    """Return the optional-runtime result for one module list."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({'new_modules': list(modules)}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='optional-runtime-result-') as directory:
        path = Path(directory) / 'result.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_optional_runtime_result', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def verify(root, *, _operation=None):
    semantics = verify_semantics(root, _operation=_operation)
    semantics['dependencies'] = source_contracts.verify_group(root, 'optional_runtime', _operation=_operation)
    return semantics
