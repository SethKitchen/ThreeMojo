#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reviewed obligations for the optional runtime dependency migration.

The checks below name the critical source edges and preconditions separately
from complete token bindings. Neither is a mathematical proof or a native
execution/coverage claim. The migration record retains the external proof
lineage and the exact selected production bytes. Nothing refreshes pins here.
"""
import ast
from functools import lru_cache
import tokenize

try:
    import check_sampled_values as sampled
    import sum2_guard_contracts as guard
    import source_contracts
except ModuleNotFoundError:
    from tools.carla_lane_oracle import check_sampled_values as sampled
    from tools.carla_lane_oracle import sum2_guard_contracts as guard, source_contracts

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


def body(root, module, name):
    text = (root / ('extensions/carla/' + module + '.mojo')).read_text()
    source = guard.declaration(text, name)
    # The historical AST adapter has no lane-search move arguments. Remove
    # only postfix move sigils before argument delimiters for this semantic
    # view; complete lexical contracts separately retain every move token.
    tokens = source_contracts.tokens(source)
    kept = []
    for index, token in enumerate(tokens):
        if token.type == tokenize.OP and token.string == '^':
            following = next((item for item in tokens[index + 1:]
                              if item.type not in (tokenize.NL, tokenize.COMMENT)), None)
            require(following is not None and following.string in (',', ')'),
                    'unsupported move-token placement')
            continue
        kept.append((token.type, token.string))
    return sampled.unique_function(sampled.syntax_tree(tokenize.untokenize(kept)), name)


def contains(node, text, label, count=1):
    expected = sampled.syntax_tree(text).body
    require(len(expected) == 1, 'invalid checker fragment: ' + label)
    wanted = sampled.dump(expected[0])
    actual = sum(sampled.dump(item) == wanted for item in ast.walk(node))
    require(actual == count, label)


def expression(node, text, label, count=1):
    wanted = sampled.dump(ast.parse(text, mode='eval').body)
    require(sum(sampled.dump(item) == wanted for item in ast.walk(node)) == count,
            label)



def sequence(node, text, label):
    """Bind adjacent statements in one suite, without textual sentinels."""
    wanted = [sampled.dump(item) for item in sampled.syntax_tree(text).body]
    matches = 0
    for owner in ast.walk(node):
        for _, values in ast.iter_fields(owner):
            if isinstance(values, list):
                actual = [sampled.dump(value) for value in values]
                matches += sum(actual[i:i+len(wanted)] == wanted for i in range(len(actual)))
    require(matches == 1, label)


def fresh_guard(node):
    expected = ast.parse('if not _sum2_supported_environment():\n    return None').body[0]
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
    return frozenset(token.string for token in source_contracts.tokens(text)
                     if token.type == tokenize.NAME)


def verify_no_containing_model_consumers(root):
    helper = 'extensions/carla/curve_objective_model.mojo'
    for path in sorted(root.rglob('*.mojo')):
        relative = path.relative_to(root)
        if relative.parts[0] in guard.NONPRODUCTION or any(
                part.startswith('.') for part in relative.parts):
            continue
        text = path.read_text()
        if not any(name in text for name in MODEL_NAMES | REMOVED_SEARCH_NAMES):
            continue
        names = executable_names(text)
        if relative.as_posix() != helper:
            require(not (names & MODEL_NAMES),
                    'containing-objective model production consumer reintroduced: '
                    + relative.as_posix())
        if relative.as_posix() == 'extensions/carla/lane_refinement.mojo':
            require(not (names & REMOVED_SEARCH_NAMES),
                    'containing-objective model search state reintroduced')


def verify_fresh_producer(run):
    loops = [node for node in run.body if isinstance(node, ast.While)]
    require(len(loops) == 1, 'one original search frontier loop')
    statements = loops[0].body
    work_test = sampled.dump(ast.parse('work >= 0', mode='eval').body)
    choices = [i for i, node in enumerate(statements) if isinstance(node, ast.If)
               and sampled.dump(node.test) == work_test]
    require(len(choices) == 1 and choices[0] > 0,
            'fresh cell producer must use original reference admission')
    index = choices[0]
    expected_work = sampled.syntax_tree('var work = _reference_work(road, lo, hi)').body[0]
    require(sampled.dump(statements[index - 1]) == sampled.dump(expected_work),
            'fresh cell producer must use current cell work')
    expected = sampled.syntax_tree(FRESH_PRODUCER).body
    require(sampled.dump(statements[index].body[:len(expected)]) == sampled.dump(expected),
            'fresh current-cell producer must immediately follow original debit')
    for name in ('cached_fast', 'cached_expansion'):
        contains(run, 'var ' + name + ': Optional[Tuple[UInt64, UInt64, _Jet]] = None',
                 'exact expansion memo lifetime is one search invocation')
    for fragment, label in ((FAST_MEMO, 'proof'), (EXPANSION_MEMO, 'translated')):
        sequence(run, 'var station_word = bitcast[DType.uint64](center_s)\n'
                 + 'var scale_word = bitcast[DType.uint64](scale)\n' + fragment,
                 'exact station/scale ' + label + ' expansion memo and fresh fallback')


def verify_semantics(root):
    helper = body(root, 'lane_refinement', '_same_cache_key')
    require(sampled.dump(helper.body) == sampled.dump(sampled.syntax_tree(
        'return SIMD[DType.uint64, 2](station, scale) == SIMD[DType.uint64, 2](other_station, other_scale)').body),
        'exact UInt64 pair helper comparison')
    model = body(root, 'curve_objective_model', '_try_objective_model')
    restrict = body(root, 'curve_objective_model', '_restrict_objective_model')
    cut = body(root, 'curve_sample_dispatch', '_sample_dispatch_cut')
    cuts = body(root, 'curve_sample_dispatch', '_try_sample_dispatch_cuts')
    lane = body(root, 'spiral_grouped_lane', '_try_grouped_lane_jet')
    raw = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope')
    metered = body(root, 'spiral_grouped_roundoff_proof', '_try_spiral_grouped_roundoff_envelope_metered')
    for node in (model, restrict, cut, cuts, lane, raw, metered):
        fresh_guard(node)

    # Exact guarded raw -> private origin -> checked Sum2 leaf edge. The
    # global inventory also rejects any new direct or alias route to it.
    origin = body(root, 'spiral_grouped_roundoff_proof', '_grouped_origin_error')
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
    work = body(root, 'spiral_grouped_roundoff_proof', '_spiral_grouped_roundoff_work')
    contains(work, 'return 3 * min(4, pieces)', 'whole count work bound')
    contains(lane, 'if nodes < 0 or nodes >= max_nodes or terms < 0 or terms > max_terms or max_terms - terms < 24:\n    return None',
             'whole optional union admission')
    contains(lane, 'if counts[0] < 1 or counts[1] > 64 or counts[1] < counts[0] or counts[1] - counts[0] > 1:\n    return None',
             'complete at-most-two count domain')
    contains(lane, 'var extra = _spiral_grouped_roundoff_work(counts[0])', 'first count debit')
    contains(lane, 'if counts[1] != counts[0]:\n    extra += _spiral_grouped_roundoff_work(counts[1])',
             'second count debit')
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

    support = body(root, 'curve_minimizer_support', '_minimizer_support')
    for text, label in (('best < low', 'actual witness lower containment'),
                        ('best > high', 'actual witness upper containment'),
                        ('not isfinite(best)', 'actual witness finite station')):
        expression(support, text, label)
    contains(support, 'var twice_error = _Interval.point(2.0) * _Interval.point(domain.error)',
             'support uses uniform whole-domain error')
    contains(support, 'var four_error = _Interval.point(4.0) * _Interval.point(domain.error)',
             'convex support uses uniform whole-domain error')
    require(not any(isinstance(part, ast.Attribute) and isinstance(part.value, ast.Name)
                    and part.value.id == 'center' and part.attr == 'error' for part in ast.walk(support)),
            'translated center error cannot replace world error')

    predicate = body(root, 'curve_sample_dispatch', '_sample_dispatch_predicate')
    require(sampled.dump(predicate.body) == sampled.dump(ast.parse(
        'return min(max(station - origin, 0.0), length) > local').body),
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
    names = [sampled.dump(item) for item in cuts.body]
    loop = next((i for i, item in enumerate(cuts.body) if isinstance(item, ast.For)), -1)
    for statement in ('nodes += 1', 'terms += extra'):
        wanted = sampled.dump(ast.parse(statement).body[0])
        require(wanted in names and names.index(wanted) < loop,
                'dispatch debit must precede optional attempts')

    run = body(root, 'lane_refinement', '_run_lane_search')
    verify_no_containing_model_consumers(root)
    verify_fresh_producer(run)
    contains(run, 'var sampled_cuts: Optional[Tuple[Float64, Float64, Int]] = None', 'cut lifetime is one search invocation')
    contains(run, 'var best = certificate.s', 'incumbent is the validated actual certificate witness')
    contains(run, 'var best_point = certificate.point.copy()', 'retain actual witness point')
    expression(run, '_minimizer_support(domain, center, center_s, best, lo, hi)',
               'support receives same ideal and actual witness')
    # The standalone helper remains reviewed and tested even though the
    # search solver no longer imports, captures, or restricts this model.
    room = body(root, 'curve_objective_model', '_objective_followup_room')
    expected_room = sampled.unique_function(sampled.syntax_tree(FOLLOWUP_ROOM), '_objective_followup_room')
    require(sampled.dump(room) == sampled.dump(expected_room),
            'complete overflow-safe integer followup admission')
    recheck = body(root, 'curve_objective_model', '_objective_recheck_room')
    require(sampled.dump(recheck) == sampled.dump(sampled.unique_function(
        sampled.syntax_tree(RECHECK_ROOM), '_objective_recheck_room')),
        'complete integer cached-closure recheck admission')
    sequence(run, GROUPED_ADMISSION,
             'grouped caller must retain recheck and prepaid original fallback')
    expression(run, '_try_grouped_lane_jet(road, section, lane, lo, hi, certificate.nodes, certificate.terms, max_nodes, max_terms)',
               'one guarded grouped caller edge')
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
    fee = body(root, 'map', '_query_node_step_cost')
    contains(fee, 'var fixed = 26 if goal else 20', 'reviewed goal node fee')
    contains(fee, 'fixed += 16', 'stored dispatch logical fee')
    contains(fee, 'if witness:\n    fixed += 14', 'retained containing-model logical fee')
    contains(fee, 'if witness:\n    fixed += 26', 'witness frontier logical fee')
    contains(fee, 'return 100 * lanes + fixed', 'original profile record work convention')
    # Only the exact additive default-false refusal is projected away. All
    # historical complete reference graph digests remain unchanged.
    sampled.reviewed_reference_tree((root / 'extensions/carla/curve_bounds.mojo').read_text())
    # The exact reviewed raw inverse establishes the same immediate bracket
    # without re-evaluating predecessors. Keep every outer admission above.
    try:
        import raw_cut_inverse_contracts as raw_inverse
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import raw_cut_inverse_contracts as raw_inverse
    raw_inverse.verify_premises(root)
    return {'status': 'PASS', 'new_modules': list(NEW_MODULES),
            'checked_error_edge': 'guarded raw -> grouped origin -> checked Sum2 leaf',
            'containing_model_consumers': 'absent from production; standalone helper retained',
            'fresh_cell_producer': 'original debit immediately precedes current-cell producer',
            'qualification': 'source preconditions and dependency integrity only',
            'native_execution_qualified': False}


def verify(root):
    semantics = verify_semantics(root)
    semantics['dependencies'] = source_contracts.verify_group(root, 'optional_runtime')
    return semantics
