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

FOLLOWUP_ROOM = """
def _objective_followup_room(
    nodes: Int, terms: Int, max_nodes: Int, max_terms: Int,
    reference_work: Int, center_work: Int,
) -> Bool:
    if nodes < 0 or nodes > max_nodes or terms < 0 or terms > max_terms or reference_work < 0 or center_work < 0:
        return False
    var remaining = max_terms - terms
    return (
        max_nodes - nodes >= 4
        and center_work <= remaining
        and reference_work <= (remaining - center_work) // 8
    )
"""

RECHECK_ROOM = """
def _objective_recheck_room(nodes: Int, max_nodes: Int) -> Bool:
    return nodes >= 0 and nodes < max_nodes
"""

NEW_MODULES = ('curve_minimizer_support', 'curve_objective_model',
               'curve_sample_dispatch', 'spiral_grouped_lane',
               'spiral_grouped_roundoff_proof')


def require(condition, message):
    if not condition:
        raise ValueError('optional runtime contract: ' + message)


def body(root, module, name, *, _operation=None):
    text = _typed_source.historical_text(root, root / ('extensions/carla/' + module + '.mojo'), source._observe_text(root, (root / ('extensions/carla/' + module + '.mojo')).relative_to(root).as_posix(), (root / ('extensions/carla/' + module + '.mojo')).read_text(), _operation=_operation), _operation=_operation)
    return body_from_source(text, name)


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


def _without_moves(text):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='optional-moves-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--moves', str(source)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        if message == 'unsupported move-token placement':
            message = 'optional runtime contract: ' + message
        raise ValueError(message)
    return result.stdout


class _RuntimeFunction:
    """One moved helper declaration checked by the Mojo fragment gate."""

    def __init__(self, name, source):
        self.name = name
        self._runtime_name = name
        self._runtime_source = source


def body_from_source(text, name):
    """Bind one moved declaration; this grants no source admission."""
    source = _declaration(text, name, ())
    # The historical AST adapter has no lane-search move arguments. Remove
    # only postfix move sigils before argument delimiters for this semantic
    # view; complete lexical contracts separately retain every move token.
    return _RuntimeFunction(name, _without_moves(source))


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
        if message.startswith('invalid checker fragment:'):
            message = 'optional runtime contract: ' + message
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
    fragment = 'if not _sum2_supported_environment():\n    return None'
    label = 'fresh invocation guard missing or moved: ' + node.name
    return _node_edge(node, 'first', fragment, node.name, message=label)


def fresh_guard(node):
    _fragment_checks([_fresh_item(node)])


# Removal is a scheduling decision, not a rejection of the standalone model's
# mathematics. Keep its proof and integer admission obligations below. A new
# production consumer, including an alias/re-export in a new namespace, needs
# a separate review; comments, docstrings and test-only callers are inert here.
MODEL_NAMES = frozenset(('curve_objective_model', '_ObjectiveModel',
    '_try_objective_model', '_restrict_objective_model',
    '_objective_followup_room', '_objective_recheck_room'))
REMOVED_SEARCH_NAMES = frozenset(('cached_model', 'reused_domain', 'reused_delta',
    'reused_lower', 'reused_tolerance', 'reused_center_s', 'reused_center_work',
    'reused_center', 'ideal_center', 'reused_support', 'needs_model', 'packed_model'))

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
        raise ValueError('optional runtime contract: production path set changed')
    return flags


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
        raise ValueError('optional runtime contract: model name set changed')
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
    hits = _model_mentions(MODEL_NAMES | REMOVED_SEARCH_NAMES, texts)
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
        if message.startswith('invalid checker fragment:'):
            message = 'optional runtime contract: ' + message
        raise ValueError(message)


def verify_fresh_producer(run):
    _search_edges(
        _runtime_source(run, 'one original search frontier loop'),
        run._runtime_name, 'fresh')


def verify_search_semantics(run):
    """Check retained historical run predicates without admitting a root.

    Actual source admission must precede the exact center predecessor.
    Historical AST fixtures can exercise diagnostics but grant no source edge.
    """
    _search_edges(
        _runtime_source(run, 'one original search frontier loop'),
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
        if message.startswith('invalid checker fragment:'):
            message = 'optional runtime contract: ' + message
        raise ValueError(message)


def verify_semantics(root, *, _operation=None):
    helper = body(root, 'lane_refinement', '_same_cache_key', _operation=_operation)
    _runtime_source(helper, 'exact UInt64 pair helper comparison')
    _semantic_edges('helper', {'helper': helper})
    model = body(root, 'curve_objective_model', '_try_objective_model', _operation=_operation)
    restrict = body(root, 'curve_objective_model', '_restrict_objective_model', _operation=_operation)
    cut = body(root, 'curve_sample_dispatch', '_sample_dispatch_cut', _operation=_operation)
    cuts = body(root, 'curve_sample_dispatch', '_try_sample_dispatch_cuts', _operation=_operation)
    lane = body(root, 'spiral_grouped_lane', '_try_grouped_lane_jet', _operation=_operation)
    raw = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope', _operation=_operation)
    metered = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope_metered', _operation=_operation)
    for node in (model, restrict, cut, cuts, lane, raw, metered):
        _runtime_source(node, node._runtime_name)
    _semantic_edges('guards', {
        'model': model, 'restrict': restrict, 'cut': cut, 'cuts': cuts,
        'lane': lane, 'raw': raw, 'metered': metered,
    })

    # Exact guarded raw -> private origin -> checked Sum2 leaf edge. The
    # global inventory also rejects any new direct or alias route to it.
    origin = body(root, 'spiral_grouped_roundoff_proof', '_grouped_origin_error', _operation=_operation)
    _runtime_source(origin, 'grouped origin must use the canonical checked error arguments')
    _runtime_source(raw, 'complete X stored-term count and origin')
    _semantic_edges('origin', {'origin': origin, 'raw': raw})
    work = body(root, 'spiral_grouped_roundoff_proof', '_spiral_grouped_roundoff_work', _operation=_operation)
    _runtime_source(work, 'whole count work bound')
    _runtime_source(lane, 'whole optional union admission')
    _runtime_source(metered, 'standalone adapter preserves independent fallback reservation')
    _semantic_edges('work', {'work': work, 'lane': lane, 'metered': metered})

    # Model data is meaningful only for the same ideal producer and owner.
    # Complete caller/source bindings cover producer smoothness and lifetime.
    _runtime_source(model, 'model ordered owner')
    _runtime_source(restrict, 'restriction cannot widen owner low')
    _semantic_edges('model', {'model': model, 'restrict': restrict})

    support = body(root, 'curve_minimizer_support', '_minimizer_support', _operation=_operation)
    _runtime_source(support, 'actual witness lower containment')
    _semantic_edges('support', {'support': support})

    predicate = body(root, 'curve_sample_dispatch', '_sample_dispatch_predicate', _operation=_operation)
    _runtime_source(predicate, 'exact stored subtraction/clamp dispatch predicate')
    _runtime_source(cuts, 'actual predecessor sample index')
    _semantic_edges('dispatch', {'predicate': predicate, 'cuts': cuts})

    verify_no_containing_model_consumers(root, _operation=_operation)
    # The standalone helper remains reviewed and tested even though the
    # search solver no longer imports, captures, or restricts this model.
    room = body(root, 'curve_objective_model', '_objective_followup_room', _operation=_operation)
    _fragment_checks([_node_edge(
        room, 'equal', FOLLOWUP_ROOM,
        'complete overflow-safe integer followup admission')])
    recheck = body(root, 'curve_objective_model', '_objective_recheck_room', _operation=_operation)
    _fragment_checks([_node_edge(
        recheck, 'equal', RECHECK_ROOM,
        'complete integer cached-closure recheck admission')])
    fee = body(root, 'map', '_query_node_step_cost', _operation=_operation)
    _fragment_checks([
        _node_edge(fee, 'contains', 'var fixed = 26 if goal else 20',
                   'reviewed goal node fee'),
        _node_edge(fee, 'contains', 'fixed += 16', 'stored dispatch logical fee'),
        _node_edge(fee, 'contains', 'if witness:\n    fixed += 14',
                   'retained containing-model logical fee'),
        _node_edge(fee, 'contains', 'if witness:\n    fixed += 26',
                   'witness frontier logical fee'),
        _node_edge(fee, 'contains', 'return 100 * lanes + fixed',
                   'original profile record work convention'),
    ])
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
    verify_search_semantics(body_from_source(previous, '_run_lane_search'))
    # Retain the sampled-reference gate after raw-inverse diagnostics.
    if __package__:
        from .ideal_projection import verify_try_only_reference
    else:
        from ideal_projection import verify_try_only_reference
    verify_try_only_reference(_typed_source.historical_text(root, root / 'extensions/carla/curve_bounds.mojo', source._observe_text(root, (root / 'extensions/carla/curve_bounds.mojo').relative_to(root).as_posix(), (root / 'extensions/carla/curve_bounds.mojo').read_text(), _operation=_operation), _operation=_operation), root, _operation=_operation)
    return _optional_runtime_result(list(NEW_MODULES))


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
