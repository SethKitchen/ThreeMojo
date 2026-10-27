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

import ast
from functools import lru_cache

try:
    import check_sampled_values as sampled
    import sum2_guard_contracts as guard
    import source_contracts
    import full_audit_cleanup_contracts as full_audit
    from sum2_contracts import _syntax_tree
except ModuleNotFoundError:
    from tools.carla_lane_oracle import check_sampled_values as sampled
    from tools.carla_lane_oracle import sum2_guard_contracts as guard, source_contracts
    from tools.carla_lane_oracle import full_audit_cleanup_contracts as full_audit
    from tools.carla_lane_oracle.sum2_contracts import _syntax_tree

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


def _fragment_count(source, name, kind, fragment, label, call=''):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = {
        'source': source, 'name': name, 'kind': kind, 'fragment': fragment,
        'label': label,
    }
    if call:
        payload['call'] = call
    payload = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='fragment-count-') as directory:
        path = Path(directory) / 'payload.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--fragment-count', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        if message.startswith('invalid checker fragment:'):
            raise ValueError('optional runtime contract: ' + message)
        raise ValueError(message)
    return int(result.stdout)


def contains(node, text, label, count=1):
    source = getattr(node, '_runtime_source', None)
    if source is not None:
        require(_fragment_count(source, node._runtime_name, 'contains', text, label) == count, label)
        return
    expected = _syntax_tree(text).body
    require(len(expected) == 1, 'invalid checker fragment: ' + label)
    wanted = sampled.dump(expected[0])
    actual = sum(sampled.dump(item) == wanted for item in ast.walk(node))
    require(actual == count, label)


def expression(node, text, label, count=1):
    source = getattr(node, '_runtime_source', None)
    if source is not None:
        require(_fragment_count(source, node._runtime_name, 'expression', text, label) == count, label)
        return
    wanted = sampled.dump(ast.parse(text, mode='eval').body)
    require(sum(sampled.dump(item) == wanted for item in ast.walk(node)) == count,
            label)



def sequence(node, text, label):
    """Bind adjacent statements in one suite, without textual sentinels."""
    source = getattr(node, '_runtime_source', None)
    if source is not None:
        require(_fragment_count(source, node._runtime_name, 'sequence', text, label) == 1, label)
        return
    wanted = [sampled.dump(item) for item in _syntax_tree(text).body]
    matches = 0
    for owner in ast.walk(node):
        for _, values in ast.iter_fields(owner):
            if isinstance(values, list):
                actual = [sampled.dump(value) for value in values]
                matches += sum(actual[i:i+len(wanted)] == wanted for i in range(len(actual)))
    require(matches == 1, label)


def fresh_guard(node):
    fragment = 'if not _sum2_supported_environment():\n    return None'
    source = getattr(node, '_runtime_source', None)
    if source is not None:
        require(_fragment_count(
            source, node._runtime_name, 'first', fragment, node.name) == 1,
            'fresh invocation guard missing or moved: ' + node.name)
        return
    expected = ast.parse(fragment).body[0]
    require(sampled.dump(node.body[0]) == sampled.dump(expected),
            'fresh invocation guard missing or moved: ' + node.name)


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


def verify_no_containing_model_consumers(root, *, _operation=None):
    helper = 'extensions/carla/curve_objective_model.mojo'
    chosen = []
    for path in sorted(root.rglob('*.mojo')):
        relative = path.relative_to(root)
        if relative.parts[0] in guard.NONPRODUCTION or any(
                part.startswith('.') for part in relative.parts):
            continue
        text = _typed_source.historical_text(root, path, source._observe_text(root, (path).relative_to(root).as_posix(), path.read_text(), _operation=_operation), _operation=_operation)
        if not any(name in text for name in MODEL_NAMES | REMOVED_SEARCH_NAMES):
            continue
        chosen.append((relative.as_posix(), text))
    lists = _lexical_directory('--names', [text for _, text in chosen])
    for (relative, _), names_list in zip(chosen, lists):
        names = frozenset(names_list)
        if relative != helper:
            require(not (names & MODEL_NAMES),
                    'containing-objective model production consumer reintroduced: '
                    + relative)
        if relative == 'extensions/carla/lane_refinement.mojo':
            require(not (names & REMOVED_SEARCH_NAMES),
                    'containing-objective model search state reintroduced')


def verify_fresh_producer(run):
    source = getattr(run, '_runtime_source', None)
    if source is not None:
        _fragment_count(source, run._runtime_name, 'fresh', FRESH_PRODUCER, 'fresh')
    else:
        loops = [node for node in run.body if isinstance(node, ast.While)]
        require(len(loops) == 1, 'one original search frontier loop')
        statements = loops[0].body
        work_test = sampled.dump(ast.parse('work >= 0', mode='eval').body)
        choices = [i for i, node in enumerate(statements) if isinstance(node, ast.If)
                   and sampled.dump(node.test) == work_test]
        require(len(choices) == 1 and choices[0] > 0,
                'fresh cell producer must use original reference admission')
        index = choices[0]
        expected_work = _syntax_tree('var work = _reference_work(road, lo, hi)').body[0]
        require(sampled.dump(statements[index - 1]) == sampled.dump(expected_work),
                'fresh cell producer must use current cell work')
        expected = _syntax_tree(FRESH_PRODUCER).body
        require(sampled.dump(statements[index].body[:len(expected)]) == sampled.dump(expected),
                'fresh current-cell producer must immediately follow original debit')
    for name in ('cached_fast', 'cached_expansion'):
        contains(run, 'var ' + name + ': Optional[Tuple[UInt64, UInt64, _Jet]] = None',
                 'exact expansion memo lifetime is one search invocation')
    for fragment, label in ((FAST_MEMO, 'proof'), (EXPANSION_MEMO, 'translated')):
        sequence(run, 'var station_word = bitcast[DType.uint64](center_s)\n'
                 + 'var scale_word = bitcast[DType.uint64](scale)\n' + fragment,
                 'exact station/scale ' + label + ' expansion memo and fresh fallback')


def verify_search_semantics(run):
    """Check retained historical run predicates without admitting a root.

    Actual source admission must precede the exact center predecessor.
    Historical AST fixtures can exercise diagnostics but grant no source edge.
    """
    verify_fresh_producer(run)
    contains(run, 'var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = None', 'cut lifetime is one search invocation')
    contains(run, 'var best = certificate.s', 'incumbent is the validated actual certificate witness')
    contains(run, 'var best_point = certificate.point.copy()', 'retain actual witness point')
    expression(run, '_minimizer_support(domain, center, center_s, best, lo, hi)',
               'support receives same ideal and actual witness')
    sequence(run, GROUPED_ADMISSION,
             'grouped caller must retain recheck and prepaid original fallback')
    expression(run, '_try_grouped_lane_jet(road, section, lane, lo, hi, certificate.nodes, certificate.terms, max_nodes, max_terms)',
               'one guarded grouped caller edge')
    source = getattr(run, '_runtime_source', None)
    if source is not None:
        _fragment_count(
            source, run._runtime_name, 'setup',
            'if task[2] >= max_depth:\n    raise Error("Lane refinement exhausted its numerical accuracy limit")',
            'depth refusal precedes dispatch setup')
    else:
        while_nodes = [item for item in run.body if isinstance(item, ast.While)]
        require(len(while_nodes) == 1, 'one original search frontier loop')
        statements = while_nodes[0].body
        setup = [i for i, item in enumerate(statements) if isinstance(item, ast.If)
                 and sampled.dump(item.test) == sampled.dump(ast.parse(
                     'not sampled_checked', mode='eval').body)]
        require(len(setup) == 1 and setup[0] > 0, 'dispatch setup remains deferred in the original node')
        preceding = statements[setup[0] - 1]
        contains(preceding, 'if task[2] >= max_depth:\n    raise Error("Lane refinement exhausted its numerical accuracy limit")',
                 'depth refusal precedes dispatch setup')
    expression(run, 'bitcast[DType.float64](bitcast[DType.uint64](split_at) - UInt64(1))',
               'split predecessor preserves every stored owner station')


def verify_semantics(root, *, _operation=None):
    helper = body(root, 'lane_refinement', '_same_cache_key', _operation=_operation)
    require(_fragment_count(
        helper._runtime_source, helper._runtime_name, 'body',
        'return SIMD[DType.uint64, 2](station, scale) == SIMD[DType.uint64, 2](other_station, other_scale)',
        'exact UInt64 pair helper comparison') == 1,
        'exact UInt64 pair helper comparison')
    model = body(root, 'curve_objective_model', '_try_objective_model', _operation=_operation)
    restrict = body(root, 'curve_objective_model', '_restrict_objective_model', _operation=_operation)
    cut = body(root, 'curve_sample_dispatch', '_sample_dispatch_cut', _operation=_operation)
    cuts = body(root, 'curve_sample_dispatch', '_try_sample_dispatch_cuts', _operation=_operation)
    lane = body(root, 'spiral_grouped_lane', '_try_grouped_lane_jet', _operation=_operation)
    raw = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope', _operation=_operation)
    metered = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope_metered', _operation=_operation)
    for node in (model, restrict, cut, cuts, lane, raw, metered):
        fresh_guard(node)

    # Exact guarded raw -> private origin -> checked Sum2 leaf edge. The
    # global inventory also rejects any new direct or alias route to it.
    origin = body(root, 'spiral_grouped_roundoff_proof', '_grouped_origin_error', _operation=_operation)
    contains(origin, 'var error = _sum2_error_checked(magnitude.high, inherited.high, count)',
             'grouped origin must use the canonical checked error arguments')
    contains(raw, 'var x_error = _grouped_origin_error(x_ideal, x_magnitude, x_inherited, 5 * pieces, geometry.x)',
             'complete X stored-term count and origin')
    contains(raw, 'var y_error = _grouped_origin_error(y_ideal, y_magnitude, y_inherited, 5 * pieces, geometry.y)',
             'complete Y stored-term count and origin')
    contains(raw, 'var distance = _ValueJet(d.value, _Interval.whole(), _Interval.whole(), d.error)',
             'retain original ideal distance and uniform scalar error')
    contains(raw, 'var copies = (high - low) * multiplicity', 'actual group multiplicity')
    contains(raw, 'var multiplicity = 1 if weight == 2 else 2', 'stored symmetric weight multiplicity')
    work = body(root, 'spiral_grouped_roundoff_proof', '_spiral_grouped_roundoff_work', _operation=_operation)
    contains(work, 'return 3 * min(4, pieces)', 'whole count work bound')
    contains(lane, 'if nodes < 0 or nodes >= max_nodes or terms < 0 or terms > max_terms or max_terms - terms < 24:\n    return None',
             'whole optional union admission')
    contains(lane, 'if counts[0] < 1 or counts[1] > 64 or counts[1] < counts[0] or counts[1] - counts[0] > 1:\n    return None',
             'complete at-most-two count domain')
    contains(lane, 'var extra = _spiral_grouped_roundoff_work(counts[0])', 'first count debit')
    contains(lane, 'if counts[1] != counts[0]:\n    extra += _spiral_grouped_roundoff_work(counts[1])',
             'second count debit')
    if getattr(lane, '_runtime_source', None) is not None:
        _fragment_count(
            lane._runtime_source, lane._runtime_name, 'before-call',
            'terms += extra',
            'atomic whole-count debit must precede both raw envelopes',
            '_try_spiral_grouped_roundoff_envelope')
    else:
        debit = next((i for i, item in enumerate(lane.body)
                      if sampled.dump(item) == sampled.dump(ast.parse('terms += extra').body[0])), -1)
        raw_positions = [i for i, item in enumerate(lane.body) if any(
            isinstance(part, ast.Call) and isinstance(part.func, ast.Name)
            and part.func.id == '_try_spiral_grouped_roundoff_envelope' for part in ast.walk(item))]
        require(debit >= 0 and len(raw_positions) == 2 and all(i > debit for i in raw_positions),
                'atomic whole-count debit must precede both raw envelopes')
    expression(lane, '_lane_jet_model_proof[False](road, section, lane, low, high, Vector3(0, 0, 0), proof, low, high, captured, require_reuse=True)',
               'try-only reconstruction cannot invoke hidden GL')
    contains(metered, 'if work + fallback_work > max_terms - terms:\n    return None',
             'standalone adapter preserves independent fallback reservation')

    # Model data is meaningful only for the same ideal producer and owner.
    # Complete caller/source bindings cover producer smoothness and lifetime.
    expression(model, 'low >= high', 'model ordered owner')
    expression(model, 'center_s < low', 'model center inside owner low')
    expression(model, 'center_s > high', 'model center inside owner high')
    for field in ('value', 'first', 'second'):
        expression(model, 'not _model_interval(domain.' + field + ')', 'model finite whole-owner ' + field)
    expression(model, 'not isfinite(domain.error)', 'model uniform error finite')
    expression(model, 'domain.error < 0.0', 'model uniform error nonnegative')
    expression(restrict, 'low < model.low', 'restriction cannot widen owner low')
    expression(restrict, 'high > model.high', 'restriction cannot widen owner high')
    expression(restrict, 'bitcast[DType.uint64](scale) != model.scale_word', 'exact normalization scale word')
    contains(restrict, 'return _Jet(value, first, model.domain.second, model.domain.error)',
             'restriction retains whole-owner curvature and error')
    contains(restrict, 'var value = model.center.value + model.center.first * delta + _Interval.point(0.5) * model.domain.second * delta.square()',
             'same-ideal Taylor value restriction')

    support = body(root, 'curve_minimizer_support', '_minimizer_support', _operation=_operation)
    for text, label in (('best < low', 'actual witness lower containment'),
                        ('best > high', 'actual witness upper containment'),
                        ('not isfinite(best)', 'actual witness finite station')):
        expression(support, text, label)
    contains(support, 'var twice_error = _Interval.point(2.0) * _Interval.point(domain.error)',
             'support uses uniform whole-domain error')
    contains(support, 'var four_error = _Interval.point(4.0) * _Interval.point(domain.error)',
             'convex support uses uniform whole-domain error')
    if getattr(support, '_runtime_source', None) is not None:
        _fragment_count(
            support._runtime_source, support._runtime_name, 'no-attribute',
            'center.error', 'translated center error cannot replace world error')
    else:
        require(not any(isinstance(part, ast.Attribute) and isinstance(part.value, ast.Name)
                        and part.value.id == 'center' and part.attr == 'error' for part in ast.walk(support)),
                'translated center error cannot replace world error')

    predicate = body(root, 'curve_sample_dispatch', '_sample_dispatch_predicate', _operation=_operation)
    require(_fragment_count(
        predicate._runtime_source, predicate._runtime_name, 'body',
        'return min(max(station - origin, 0.0), length) > local',
        'exact stored subtraction/clamp dispatch predicate') == 1,
        'exact stored subtraction/clamp dispatch predicate')
    contains(cuts, 'var before_index = _sample_index(geometry, min(max(before - record.s, 0.0), geometry.length))',
             'actual predecessor sample index')
    contains(cuts, 'var after_index = _sample_index(geometry, min(max(station - record.s, 0.0), geometry.length))',
             'actual cut sample index')
    contains(cuts, 'if before_index != threshold_at - 1 or after_index != threshold_at:\n    return None',
             'both actual indices must match original owners')
    contains(cuts, 'var node_reserve = 3 * count + 2', 'dispatch node reserve includes descendants and rechecks')
    contains(cuts, 'var term_reserve = 16 * count', 'dispatch probe and descendant term reserve')
    contains(cuts, 'if max_nodes < node_reserve or max_terms < 0 or nodes < 0 or nodes > max_nodes - node_reserve or terms < 0 or terms > max_terms or term_reserve > max_terms - terms:\n    return None',
             'complete dispatch followup reserve before optional work')
    contains(cuts, 'var extra = 8 * count', 'complete optional dispatch debit')
    contains(cuts, 'if count < 1 or count > 2:\n    return None', 'at most two invocation-local cuts')
    sequence(cuts, DISPATCH_ADMISSION, 'bounded count and complete reserve must precede dispatch debit')
    if getattr(cuts, '_runtime_source', None) is not None:
        for statement in ('nodes += 1', 'terms += extra'):
            _fragment_count(
                cuts._runtime_source, cuts._runtime_name, 'before-loop',
                statement, 'dispatch debit must precede optional attempts')
    else:
        names = [sampled.dump(item) for item in cuts.body]
        loop = next((i for i, item in enumerate(cuts.body) if isinstance(item, ast.For)), -1)
        for statement in ('nodes += 1', 'terms += extra'):
            wanted = sampled.dump(ast.parse(statement).body[0])
            require(wanted in names and names.index(wanted) < loop,
                    'dispatch debit must precede optional attempts')

    verify_no_containing_model_consumers(root, _operation=_operation)
    # The standalone helper remains reviewed and tested even though the
    # search solver no longer imports, captures, or restricts this model.
    room = body(root, 'curve_objective_model', '_objective_followup_room', _operation=_operation)
    require(_fragment_count(
        room._runtime_source, room._runtime_name, 'equal', FOLLOWUP_ROOM,
        'complete overflow-safe integer followup admission') == 1,
        'complete overflow-safe integer followup admission')
    recheck = body(root, 'curve_objective_model', '_objective_recheck_room', _operation=_operation)
    require(_fragment_count(
        recheck._runtime_source, recheck._runtime_name, 'equal', RECHECK_ROOM,
        'complete integer cached-closure recheck admission') == 1,
        'complete integer cached-closure recheck admission')
    fee = body(root, 'map', '_query_node_step_cost', _operation=_operation)
    contains(fee, 'var fixed = 26 if goal else 20', 'reviewed goal node fee')
    contains(fee, 'fixed += 16', 'stored dispatch logical fee')
    contains(fee, 'if witness:\n    fixed += 14', 'retained containing-model logical fee')
    contains(fee, 'if witness:\n    fixed += 26', 'witness frontier logical fee')
    contains(fee, 'return 100 * lanes + fixed', 'original profile record work convention')
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
    sampled.reviewed_reference_tree(_typed_source.historical_text(root, root / 'extensions/carla/curve_bounds.mojo', source._observe_text(root, (root / 'extensions/carla/curve_bounds.mojo').relative_to(root).as_posix(), (root / 'extensions/carla/curve_bounds.mojo').read_text(), _operation=_operation), _operation=_operation), root, _operation=_operation)
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
