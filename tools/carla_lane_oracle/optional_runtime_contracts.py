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

DISPATCH_ADMISSION = """
if count < 1 or count > 2:
    return None
var extra = 8 * count
var node_reserve = 3 * count + 2
var term_reserve = 16 * count
if max_nodes < node_reserve or max_terms < 0 or nodes < 0 or nodes > max_nodes - node_reserve or terms < 0 or terms > max_terms or term_reserve > max_terms - terms:
    return None
nodes += 1
terms += extra
"""

GROUPED_ADMISSION = """
certificate.terms += work
var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None
if max_nodes - certificate.nodes >= 2:
    grouped = _try_grouped_lane_jet(road, section, lane, lo, hi, certificate.nodes, certificate.terms, max_nodes, max_terms)
if grouped:
    point_domain = grouped.value()
else:
    point_domain = _lane_jet(road, section, lane, lo, hi)
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

FRESH_PRODUCER = """
if certificate.terms > max_terms - work:
    raise Error("Lane refinement exhausted its quadrature work limit")
certificate.terms += work
var point_domain: Tuple[_Jet, _Jet, _Jet]
if frozen:
    point_domain = _frozen_arc_center(frozen.value(), lo, hi, Vector3(0, 0, 0))
else:
    point_domain = _lane_jet_with_proof(road, section, lane, lo, hi, low, high, spiral_proof)
var natural = _scaled_point_distance_box(point_domain, location, scale).low
"""

FAST_MEMO = """
if external_witness and cached_fast and _same_cache_key(cached_fast.value()[0], cached_fast.value()[1], station_word, scale_word):
    fast_center = cached_fast.value()[2]
else:
    fast_center = _try_proof_expansion_jet(road, section, lane, center_s, location, scale, low, high, spiral_proof)
    if external_witness and fast_center:
        cached_fast = (station_word, scale_word, fast_center.value())
"""
EXPANSION_MEMO = """
if external_witness and cached_expansion and _same_cache_key(cached_expansion.value()[0], cached_expansion.value()[1], station_word, scale_word):
    center = cached_expansion.value()[2]
else:
    if frozen:
        center = _frozen_arc_expansion(frozen.value(), center_s, location, scale)
    else:
        center = _expansion_distance_jet(road, section, lane, center_s, location, scale)
    if external_witness:
        cached_expansion = (station_word, scale_word, center)
"""


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


def _fresh_items(run):
    loop = 'one original search frontier loop'
    items = [_node_edge(run, 'fresh', FRESH_PRODUCER, 'fresh', source_label=loop)]
    for name in ('cached_fast', 'cached_expansion'):
        items.append(_node_edge(
            run, 'contains',
            'var ' + name + ': Optional[Tuple[UInt64, UInt64, _Jet]] = None',
            'exact expansion memo lifetime is one search invocation'))
    for fragment, label in ((FAST_MEMO, 'proof'), (EXPANSION_MEMO, 'translated')):
        items.append(_node_edge(
            run, 'sequence',
            'var station_word = bitcast[DType.uint64](center_s)\n'
            + 'var scale_word = bitcast[DType.uint64](scale)\n' + fragment,
            'exact station/scale ' + label + ' expansion memo and fresh fallback'))
    return items


def verify_fresh_producer(run):
    _fragment_checks(_fresh_items(run))


def verify_search_semantics(run):
    """Check retained historical run predicates without admitting a root.

    Actual source admission must precede the exact center predecessor.
    Historical AST fixtures can exercise diagnostics but grant no source edge.
    """
    loop = 'one original search frontier loop'
    items = _fresh_items(run)
    items.extend((
        _node_edge(run, 'contains',
                   'var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = None',
                   'cut lifetime is one search invocation'),
        _node_edge(run, 'contains', 'var best = certificate.s',
                   'incumbent is the validated actual certificate witness'),
        _node_edge(run, 'contains', 'var best_point = certificate.point.copy()',
                   'retain actual witness point'),
        _node_edge(run, 'expression',
                   '_minimizer_support(domain, center, center_s, best, lo, hi)',
                   'support receives same ideal and actual witness'),
        _node_edge(run, 'sequence', GROUPED_ADMISSION,
                   'grouped caller must retain recheck and prepaid original fallback'),
        _node_edge(
            run, 'expression',
            '_try_grouped_lane_jet(road, section, lane, lo, hi, certificate.nodes, certificate.terms, max_nodes, max_terms)',
            'one guarded grouped caller edge'),
        _node_edge(
            run, 'setup',
            'if task[2] >= max_depth:\n    raise Error("Lane refinement exhausted its numerical accuracy limit")',
            'depth refusal precedes dispatch setup', source_label=loop),
        _node_edge(
            run, 'expression',
            'bitcast[DType.float64](bitcast[DType.uint64](split_at) - UInt64(1))',
            'split predecessor preserves every stored owner station'),
    ))
    _fragment_checks(items)


def verify_semantics(root, *, _operation=None):
    helper = body(root, 'lane_refinement', '_same_cache_key', _operation=_operation)
    _fragment_checks([_node_edge(
        helper, 'body',
        'return SIMD[DType.uint64, 2](station, scale) == SIMD[DType.uint64, 2](other_station, other_scale)',
        'exact UInt64 pair helper comparison')])
    model = body(root, 'curve_objective_model', '_try_objective_model', _operation=_operation)
    restrict = body(root, 'curve_objective_model', '_restrict_objective_model', _operation=_operation)
    cut = body(root, 'curve_sample_dispatch', '_sample_dispatch_cut', _operation=_operation)
    cuts = body(root, 'curve_sample_dispatch', '_try_sample_dispatch_cuts', _operation=_operation)
    lane = body(root, 'spiral_grouped_lane', '_try_grouped_lane_jet', _operation=_operation)
    raw = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope', _operation=_operation)
    metered = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope_metered', _operation=_operation)
    _fragment_checks([_fresh_item(node) for node in
                      (model, restrict, cut, cuts, lane, raw, metered)])

    # Exact guarded raw -> private origin -> checked Sum2 leaf edge. The
    # global inventory also rejects any new direct or alias route to it.
    origin = body(root, 'spiral_grouped_roundoff_proof', '_grouped_origin_error', _operation=_operation)
    _fragment_checks([
        _node_edge(origin, 'contains',
                   'var error = _sum2_error_checked(magnitude.high, inherited.high, count)',
                   'grouped origin must use the canonical checked error arguments'),
        _node_edge(raw, 'contains',
                   'var x_error = _grouped_origin_error(x_ideal, x_magnitude, x_inherited, 5 * pieces, geometry.x)',
                   'complete X stored-term count and origin'),
        _node_edge(raw, 'contains',
                   'var y_error = _grouped_origin_error(y_ideal, y_magnitude, y_inherited, 5 * pieces, geometry.y)',
                   'complete Y stored-term count and origin'),
        _node_edge(raw, 'contains',
                   'var distance = _ValueJet(d.value, _Interval.whole(), _Interval.whole(), d.error)',
                   'retain original ideal distance and uniform scalar error'),
        _node_edge(raw, 'contains', 'var copies = (high - low) * multiplicity',
                   'actual group multiplicity'),
        _node_edge(raw, 'contains', 'var multiplicity = 1 if weight == 2 else 2',
                   'stored symmetric weight multiplicity'),
    ])
    work = body(root, 'spiral_grouped_roundoff_proof', '_spiral_grouped_roundoff_work', _operation=_operation)
    _fragment_checks([
        _node_edge(work, 'contains', 'return 3 * min(4, pieces)',
                   'whole count work bound'),
        _node_edge(lane, 'contains',
                   'if nodes < 0 or nodes >= max_nodes or terms < 0 or terms > max_terms or max_terms - terms < 24:\n    return None',
                   'whole optional union admission'),
        _node_edge(lane, 'contains',
                   'if counts[0] < 1 or counts[1] > 64 or counts[1] < counts[0] or counts[1] - counts[0] > 1:\n    return None',
                   'complete at-most-two count domain'),
        _node_edge(lane, 'contains',
                   'var extra = _spiral_grouped_roundoff_work(counts[0])',
                   'first count debit'),
        _node_edge(lane, 'contains',
                   'if counts[1] != counts[0]:\n    extra += _spiral_grouped_roundoff_work(counts[1])',
                   'second count debit'),
        _node_edge(lane, 'before-call', 'terms += extra',
                   'atomic whole-count debit must precede both raw envelopes',
                   call='_try_spiral_grouped_roundoff_envelope'),
        _node_edge(lane, 'expression',
                   '_lane_jet_model_proof[False](road, section, lane, low, high, Vector3(0, 0, 0), proof, low, high, captured, require_reuse=True)',
                   'try-only reconstruction cannot invoke hidden GL'),
        _node_edge(metered, 'contains',
                   'if work + fallback_work > max_terms - terms:\n    return None',
                   'standalone adapter preserves independent fallback reservation'),
    ])

    # Model data is meaningful only for the same ideal producer and owner.
    # Complete caller/source bindings cover producer smoothness and lifetime.
    items = [
        _node_edge(model, 'expression', 'low >= high', 'model ordered owner'),
        _node_edge(model, 'expression', 'center_s < low', 'model center inside owner low'),
        _node_edge(model, 'expression', 'center_s > high', 'model center inside owner high'),
    ]
    for field in ('value', 'first', 'second'):
        items.append(_node_edge(
            model, 'expression', 'not _model_interval(domain.' + field + ')',
            'model finite whole-owner ' + field))
    items.extend((
        _node_edge(model, 'expression', 'not isfinite(domain.error)',
                   'model uniform error finite'),
        _node_edge(model, 'expression', 'domain.error < 0.0',
                   'model uniform error nonnegative'),
        _node_edge(restrict, 'expression', 'low < model.low',
                   'restriction cannot widen owner low'),
        _node_edge(restrict, 'expression', 'high > model.high',
                   'restriction cannot widen owner high'),
        _node_edge(restrict, 'expression',
                   'bitcast[DType.uint64](scale) != model.scale_word',
                   'exact normalization scale word'),
        _node_edge(restrict, 'contains',
                   'return _Jet(value, first, model.domain.second, model.domain.error)',
                   'restriction retains whole-owner curvature and error'),
        _node_edge(
            restrict, 'contains',
            'var value = model.center.value + model.center.first * delta + _Interval.point(0.5) * model.domain.second * delta.square()',
            'same-ideal Taylor value restriction'),
    ))
    _fragment_checks(items)

    support = body(root, 'curve_minimizer_support', '_minimizer_support', _operation=_operation)
    items = []
    for text, label in (('best < low', 'actual witness lower containment'),
                        ('best > high', 'actual witness upper containment'),
                        ('not isfinite(best)', 'actual witness finite station')):
        items.append(_node_edge(support, 'expression', text, label))
    items.extend((
        _node_edge(support, 'contains',
                   'var twice_error = _Interval.point(2.0) * _Interval.point(domain.error)',
                   'support uses uniform whole-domain error'),
        _node_edge(support, 'contains',
                   'var four_error = _Interval.point(4.0) * _Interval.point(domain.error)',
                   'convex support uses uniform whole-domain error'),
        _node_edge(support, 'no-attribute', 'center.error',
                   'translated center error cannot replace world error'),
    ))
    _fragment_checks(items)

    predicate = body(root, 'curve_sample_dispatch', '_sample_dispatch_predicate', _operation=_operation)
    debit = 'dispatch debit must precede optional attempts'
    items = [
        _node_edge(predicate, 'body',
                   'return min(max(station - origin, 0.0), length) > local',
                   'exact stored subtraction/clamp dispatch predicate'),
        _node_edge(cuts, 'contains',
                   'var before_index = _sample_index(geometry, min(max(before - record.s, 0.0), geometry.length))',
                   'actual predecessor sample index'),
        _node_edge(cuts, 'contains',
                   'var after_index = _sample_index(geometry, min(max(station - record.s, 0.0), geometry.length))',
                   'actual cut sample index'),
        _node_edge(cuts, 'contains',
                   'if before_index != threshold_at - 1 or after_index != threshold_at:\n    return None',
                   'both actual indices must match original owners'),
        _node_edge(cuts, 'contains', 'var node_reserve = 3 * count + 2',
                   'dispatch node reserve includes descendants and rechecks'),
        _node_edge(cuts, 'contains', 'var term_reserve = 16 * count',
                   'dispatch probe and descendant term reserve'),
        _node_edge(cuts, 'contains',
                   'if max_nodes < node_reserve or max_terms < 0 or nodes < 0 or nodes > max_nodes - node_reserve or terms < 0 or terms > max_terms or term_reserve > max_terms - terms:\n    return None',
                   'complete dispatch followup reserve before optional work'),
        _node_edge(cuts, 'contains', 'var extra = 8 * count',
                   'complete optional dispatch debit'),
        _node_edge(cuts, 'contains', 'if count < 1 or count > 2:\n    return None',
                   'at most two invocation-local cuts'),
        _node_edge(cuts, 'sequence', DISPATCH_ADMISSION,
                   'bounded count and complete reserve must precede dispatch debit'),
    ]
    for statement in ('nodes += 1', 'terms += extra'):
        items.append(_node_edge(cuts, 'before-loop', statement, debit, source_label=debit))
    _fragment_checks(items)

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
    return {'status': 'PASS', 'new_modules': list(NEW_MODULES),
            'checked_error_edge': 'guarded raw -> grouped origin -> checked Sum2 leaf',
            'containing_model_consumers': 'absent from production; standalone helper retained',
            'fresh_cell_producer': 'original debit immediately precedes current-cell producer',
            'qualification': 'source preconditions and dependency integrity only',
            'native_execution_qualified': False}


def verify(root, *, _operation=None):
    semantics = verify_semantics(root, _operation=_operation)
    semantics['dependencies'] = source_contracts.verify_group(root, 'optional_runtime', _operation=_operation)
    return semantics
