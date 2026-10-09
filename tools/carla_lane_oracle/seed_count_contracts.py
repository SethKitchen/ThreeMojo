# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact Map count-refusal cleanup, with its historical inverse.

This source contract does not itself prove numerical or native behavior.
Each named edge has exact reviewed endpoints. The unchanged before
source needs no new edge. Historical pins and live debit checks remain live.
No broad verifier is called here: this is the bottom of the successor graph.
"""
from functools import lru_cache
import hashlib
import importlib.util
import json
import textwrap
import tokenize
from pathlib import Path

if __package__:
    from . import source_contracts as source
    from . import sum2_guard_contracts as guard
else:
    import source_contracts as source
    import sum2_guard_contracts as guard

def _sibling_tool(name):
    """Load the executing checker's fixed sibling, independent of sys.path."""
    path = Path(__file__).resolve().parents[1] / (name + '.py')
    spec = importlib.util.spec_from_file_location('_seed_count_' + name, path)
    if spec is None or spec.loader is None:
        raise ImportError('cannot load checker sibling: ' + str(path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


affected = _sibling_tool('affected')
cache_key = _sibling_tool('cache_key')

MODULE = 'extensions/carla/map.mojo'
MIGRATION = 'tools/carla_lane_oracle/seed-count-successor.json'
MIGRATION_SHA256 = 'fe8f0b4bba9ddc037113340e06f223d1ee4ed0b8ec4d67752d4e39ea946be271'
BEFORE_SHA256 = '52dd32213d64275be94ba714bc9b6a57c28f5ba1303525ef1a1aac20b4743c07'
AFTER_SHA256 = '9e29cdd57fc37ffa9dc9c09ed9b263ddb7ced5781f938ff13d7fd9b2c6c997a5'
BEFORE_TOKEN_SHA256 = '0524759d2516ef9b269c2286cd0bbc01ed8b462718ac33ac276db510739de0c0'
AFTER_TOKEN_SHA256 = 'ef1e317a812dec93adc1e47857825cfc747eae7117dd3f9664b7e4dda646b938'
EDIT_NAMES = ('center_count_refusal', 'retry_count_refusal', 'proposal_count_refusal')
AFTER_TESTS = ('tests/test_carla_winner_seed_recovery.mojo',)

# A distinct reviewed local-guard edge follows the immutable count edge.
# Do not change the earlier endpoints, record, test pins, or three inverse spans.
# Terms: local remaining terms intersect global remaining terms; the admitted
# winner product is <=2,000,000 before the retained global subtraction.
# Steps: proof_nodes=2 reserves (87+followup)*C; exactly two setup charges
# leave >=97*C, C>=82. Retain the retry's separate 12-step charge and admission.
# Midpoints: positive stored binary64 stations stay in [2^-400,2^400]. Every
# nonzero difference is normal (>=2^-452), its half is exact and <=the exact
# difference, and rounded addition stays between representable endpoints.
# Only exact half-product/add contraction is allowed; reassociation or
# distribution of a+0.5*(c-a) is not part of this reviewed operation graph.
# This is not generic interval monotonicity; collapse/progress stay checked.
OPTIONAL_AFTER_SHA256 = 'e4498a5180821de4a1611cbe3c0751bda36d2e80b84c3c53caac2ca1ca0a367c'
OPTIONAL_AFTER_TOKEN_SHA256 = '7cd2f4af3f6ad9f12f610a5c0dfcbf9fc781c46f9bcf39c2755bf3867d251685'
OPTIONAL_EDITS = (('winner_global_term_refusal', '    var terms_left = work.policy.max_terms - work.terms\n    if winner_reference > terms_left // winner_units:\n        return False\n    terms_left -= winner_units * winner_reference\n', '    var terms_left = work.policy.max_terms - work.terms\n    terms_left -= winner_units * winner_reference\n'), ('prepaid_retry_step_refusal', '    if not domain.first.is_finite() or not domain.second.is_finite():\n        if min(work.max_total_steps, work.policy.max_steps) - work.steps < 12:\n            return False\n        # Separate admission preserves the two-setup smooth-root path.\n', '    if not domain.first.is_finite() or not domain.second.is_finite():\n        # Separate admission preserves the two-setup smooth-root path.\n'), ('retry_midpoint_enclosure', '            if (\n                not isfinite(narrowed_low)\n                or not isfinite(narrowed_high)\n                or narrowed_low > original_s\n                or narrowed_high < original_s\n                or narrowed_low >= narrowed_high\n                or (narrowed_low == band_low and narrowed_high == band_high)\n            ):\n', '            if narrowed_low >= narrowed_high or (\n                narrowed_low == band_low and narrowed_high == band_high\n            ):\n'))
OPTIONAL_PREMISE_HASHES = {'_winner_seed_room': '700d00aff6ebf60c3a7a00429ea28df9bb8fbc4d4ffcdeef5ffc2aa6384ece3f', '_try_winner_seed': 'a0e956f7b4527eb02c7d9e52528575601e78310d7dc86953a6a733bf8f911be9'}
OPTIONAL_EXTRA_PREMISES = (('extensions/carla/map_search.mojo', 'validate', ('MapQueryBudget',), 'd4844df8e4cbed35dfa9533c921cacc7975ea2cfed0d4efd57f6541b078a1cdc'), ('extensions/carla/map_search.mojo', '_step_product', ('_MapQueryWork',), '123e48a4de30fe5f383a3e2d4c4b747f53b4181fc672a040560ef72d1d27f825'), ('extensions/carla/curve_sum2.mojo', '_sum2_update', (), 'ce9a6e6e0203c349208ed4d0feee47106c0fbc1b9addd3517a0003b11990f18b'))


# A third, separate edge removes only locally proved error/support guards.
# It does not rewrite either the count edge or the published optional edge.
# Error theorem: stored_difference(variable, constant) starts with two zero
# errors. Its sum/roundoff graph returns zero or a nonnegative allowance;
# Sterbenz's override is zero. The retained error<1 gate and exact-range
# |value endpoints|<=2^400 bound rounded_value by next_up(2^400+1), finite.
# Support theorem: admission/narrowing retain 0<band_low<=original_s<=band_high
# with finite endpoints. Invalid models return this band. Applied ordered
# finite radii enclose nonnegative real radii, so high>=0. Clipping best+radius
# above and best-radius below preserves best and the band. A limit can overflow
# to infinity; min/max with the finite band endpoint still preserves the band.
# No arbitrary-interval monotonicity or finite near-MAX addition is assumed.
# Retain score refusal: exact improvement and genuine point-gap scale alone
# do NOT prove finite interval score (MAX-(-1) has an infinite outward bound).
# Native materialization/coverage remains a separate qualification requirement.
SUPPORT_AFTER_SHA256 = 'b9acf04cb54a84b89928739ea9c4e1098843149b6e926cf043b3333a1cdff518'
SUPPORT_AFTER_TOKEN_SHA256 = '57b5ab51af0a83edabbfa783a9857c8f88f435244f0f171649e4290da69c58d3'
SUPPORT_EDITS = (('nonnegative_stored_difference_error', '    if not _seed_exact_interval(d.value) or not (\n        0.0 <= d.error and d.error < 1.0\n    ):\n', '    if not _seed_exact_interval(d.value) or not d.error < 1.0:\n'), ('bounded_finite_rounded_distance', '    if (\n        not rounded.is_finite()\n        or rounded.low <= 0.0\n        or rounded.high >= geometry.length\n    ):\n', '    if rounded.low <= 0.0 or rounded.high >= geometry.length:\n'), ('positive_finite_minimizer_support', '    var support = _minimizer_support(\n        domain, center, original_s, original_s, band_low, band_high\n    )\n    if (\n        not support.is_finite()\n        or support.low <= 0.0\n        or support.high < support.low\n    ):\n        return False\n', '    var support = _minimizer_support(\n        domain, center, original_s, original_s, band_low, band_high\n    )\n'))
SUPPORT_PREMISE_HASHES = {'_seed_reference_domain': '2dac22303e098b801af08b9abfab282dae48a6895c3ef5754a27ddee83871d1e', '_try_winner_seed': 'ed2260b961b4492a0bb8362e65bb8aee62d2896c58f3ec41dab025a4d0135254'}
SUPPORT_EXTRA_PREMISES = (('extensions/carla/curve_interval.mojo', 'whole', ('_Interval',), '86d1e02f0f8cb20cee66f09ed7e2342d0e56c1d6b7a99de864cb52fb14019dbc'), ('extensions/carla/curve_interval.mojo', 'rounded', ('_Interval',), '4097f0ddac630fbd70272ab9cea2c963fb9150d999d07c32114ea8624813d8aa'), ('extensions/carla/curve_interval.mojo', '__neg__', ('_Interval',), '9e2f35fa8cbc07e6d6ae013d35510b2dd0b3d0327c995ed00f5c9416b12e2dfa'), ('extensions/carla/curve_interval.mojo', '__sub__', ('_Interval',), 'a481d28615c2cf2bccb4248f1977b7273bf29c8d96121ee339ba5e63d2f15a94'), ('extensions/carla/curve_interval.mojo', '__truediv__', ('_Interval',), 'd63998431c4fb89405f915fea9a3de39f5026da3eb3081bad1305c69b2401316'), ('extensions/carla/curve_interval.mojo', 'square', ('_Interval',), '5ba837ee949861751a9996bee84a5cb02bf767c2100e3c8b4f6e3621a910d922'), ('extensions/carla/curve_interval.mojo', 'sqrt', ('_Interval',), '6b3199c6c1f107ea5bad08837c6ff7ad389e655b1eb20ce4d42c904ed271c359'), ('extensions/carla/curve_interval.mojo', 'contains', ('_Interval',), 'a1b087462723ccf3cbc7b63725adf7b67c2487dde5e8a1928acf5be31dbfaf93'))


# A fourth exact edge replaces one frontier-size refusal by its existing
# continuation-headroom refusal. This does NOT prove large frontiers absent.
# Successful node_cap establishes 0<=winner_cap-winner.nodes<=16384. For
# L=len(winner.cells)<=16372, min(L,16373)+12 is exactly L+12. For L>=16373,
# the bounded reservation is 16385 and the first headroom leaf refuses.
# All earlier validation/cap calls and their exception order are unchanged;
# intervening target count comparisons are pure. Later arithmetic/debits are
# unreachable in the saturated case. Integer addition is bounded by 16385.
# Preserve both target_cells guards, headroom order, thresholds and charges.
FRONTIER_AFTER_SHA256 = '37dcfb47476001ba8633a2c9dbb78b2d5f83bc069a0c4551d32ca6fdbb4c60bf'
FRONTIER_AFTER_TOKEN_SHA256 = '214a759d7cb2f804b214bf7324e621d36c83be40af1ecb497550609f6b6bc063'
FRONTIER_EDITS = (('bounded_winner_frontier_guard', '        or target_reference <= 0\n        or len(winner.cells) > 16372\n        or target_cells < 0\n', '        or target_reference <= 0\n        or target_cells < 0\n'), ('saturating_winner_frontier_reservation', '    var winner_followup = len(winner.cells) + 12\n', '    var winner_followup = min(len(winner.cells), 16373) + 12\n'))
FRONTIER_PREMISE_HASHES = {'_winner_seed_room': '6fe8fb2c7802c06ac92466ad1903bb8146548c91f014b3ec4d33b754c1916908'}


# A fifth, separate edge extracts order-before-score without removing refusal.
# This is a numerical helper-boundary witness, not SPIRAL producer reachability.
SCORE_AFTER_SHA256 = '70ec94630e2530e9389fdb6388ff4c139bb268f5549f1a9f06602b6dfebecb94'
SCORE_AFTER_TOKEN_SHA256 = '56e9801cd0b87c07b67ff96286cac37ef621cee7c2967fb16bd979c1f6981b06'
SCORE_EDITS = (('extract_finite_winner_score', 'def _try_winner_seed(\n', 'def _winner_seed_update_score(\n    point: Array[Float64, 3],\n    incumbent: Array[Float64, 3],\n    query: Array[Float64, 3],\n    scale: Float64,\n) raises -> Tuple[Bool, Float64]:\n    # Borrowed points; the caller supplies a positive finite scale and an\n    # established FP environment. The second result is unusable on refusal.\n    if _wide_point_order(point, incumbent, query) < 0:\n        var score = _refinement_square[3](point, query, scale)\n        if not score.is_finite():\n            return (False, 0.0)\n        return (True, score.high)\n    return (False, 0.0)\n\n\ndef _try_winner_seed(\n'), ('call_finite_winner_score', '            if _wide_point_order(point, certificate.point, query) < 0:\n                var score = _refinement_square[3](\n                    point, query, certificate.scale\n                )\n                if not score.is_finite():\n                    continue\n                certificate.s = s\n                certificate.point = point^\n                certificate.upper = score.high\n                improved = True\n', '            var update = _winner_seed_update_score(\n                point, certificate.point, query, certificate.scale\n            )\n            if update[0]:\n                certificate.s = s\n                certificate.point = point^\n                certificate.upper = update[1]\n                improved = True\n'))
SCORE_HELPER_TOKEN_SHA256 = '155efb5cb2224594d4f58a59cbd6e3c84b80ee21bcc8fed50f4252bbab6cb331'
SCORE_CALLER_TOKEN_SHA256 = '530591a025e3ab9a31870ed03f0b79d871e8a96c958eb688aa31d047b0143e40'
SCORE_ROUTING_SHA256 = '6e7a09a1e19c18f4510e3574df0cf9ff3c86096ef06b3f588dd34f9dd77ed50f'
SCORE_TESTS = {'tests/test_carla_winner_seed_update_score.mojo': 'fb9b3c95f3e390bebf2be132544371c5626ed7b9be77181d6701aa2e89a9f3e4'}


def require(value, message):
    """Keep rejection controls active in optimized Python."""
    if not value:
        raise ValueError('reviewed seed-count successor: ' + message)


@lru_cache(maxsize=32)
def _function_span_snapshot(text):
    """Memoize only exact-text lexical spans as immutable nested tuples."""
    tokens = source.tokens(text)
    found, scopes, statement, decorators = [], [], [], {}
    pending, indents, ends = None, [], {}
    for index, token in enumerate(tokens):
        if token.type == tokenize.INDENT:
            indents.append(index)
            scopes.append(pending or ('block', ()))
            pending = None
            decorators.pop(len(scopes), None)
        elif token.type == tokenize.DEDENT:
            require(bool(scopes) and bool(indents), 'unmatched declaration scope')
            ends[indents.pop()] = index+1
            decorators.pop(len(scopes), None)
            scopes.pop()
            pending = None
        elif token.type == tokenize.NEWLINE:
            if statement:
                words = [tokens[i].string for i in statement]
                if words[0] == '@':
                    decorators.setdefault(len(scopes), []).append(statement[0])
                else:
                    preceding = decorators.pop(len(scopes), [])
                    if len(words) >= 2 and words[0] == 'def':
                        found.append((words[1], preceding[0] if preceding else statement[0],
                                      index, tuple(scopes)))
                if words[-1] == ':':
                    pending = ((words[0], words[1]) if len(words) >= 2 and
                               words[0] in ('def','struct','trait','class')
                               else ('block', tuple(words)))
                else:
                    pending = None
            statement = []
        elif token.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER):
            statement.append(index)
    require(not scopes and not indents and not statement, 'incomplete declaration scope')
    result, lines = {}, text.splitlines(keepends=True)
    for name, decorated_start, signature, owner in found:
        body = signature+1
        while body < len(tokens) and tokens[body].type in (tokenize.COMMENT, tokenize.NL):
            body += 1
        require(body < len(tokens) and tokens[body].type == tokenize.INDENT and body in ends,
                'unsupported declaration body: '+name)
        first = tokens[decorated_start].start[0]-1
        last = tokens[ends[body]-1].start[0]-1
        snippet = textwrap.dedent(''.join(lines[first:last]))
        require(bool(snippet.strip()), 'empty declaration: '+name)
        result.setdefault((owner,name), []).append((snippet,first,last))
    return tuple((key, tuple(values)) for key, values in result.items())


def _function_spans(text):
    """Return fresh mutable wrappers over an exact-text lexical snapshot."""
    return {key: list(values) for key, values in _function_span_snapshot(text)}


def _function_span(text, name, expected_owner, *, spans=None):
    spans = _function_spans(text) if spans is None else spans
    key = (tuple(('struct', part) for part in expected_owner),name)
    found = spans.get(key, ())
    require(len(found) == 1, 'missing or ambiguous scoped declaration: '+name)
    return found[0]


def declaration(text, name, owner=(), *, spans=None):
    """Select one actual declaration by its complete lexical owner."""
    return _function_span(text,name,owner,spans=spans)[0]



def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def read_record(root):
    payload = (Path(root)/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'immutable successor record changed')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and record['path'] == MODULE, 'wrong successor scope')
    require((record['before_sha256'], record['after_sha256'],
             record['before_token_sha256'], record['after_token_sha256']) ==
            (BEFORE_SHA256, AFTER_SHA256, BEFORE_TOKEN_SHA256, AFTER_TOKEN_SHA256),
            'reviewed endpoints changed')
    require(set(record['after_correctness_tests']) == set(AFTER_TESTS),
            'count-control fixture scope changed')
    return record


def checked_edits(record):
    edits = record['edits']
    require(tuple(edit['name'] for edit in edits) == EDIT_NAMES,
            'missing, duplicate, reordered or extra inverse edit')
    for edit in edits:
        require(set(edit) == {'name', 'before', 'after', 'before_sha256', 'after_sha256'},
                'inverse edit fields changed')
        for side in ('before', 'after'):
            require(bool(edit[side]) and sha(edit[side]) == edit[side+'_sha256'],
                    'inverse span hash changed: '+edit['name'])
    return edits


def predecessor_source(text, record):
    """Reverse three unique spans and reconstruct every historical byte."""
    require(sha(text) == AFTER_SHA256 and source.token_sha256(text) == AFTER_TOKEN_SHA256,
            'unknown complete after Map')
    for edit in reversed(checked_edits(record)):
        require(text.count(edit['after']) == 1, 'missing or ambiguous inverse anchor')
        text = text.replace(edit['after'], edit['before'], 1)
    require(sha(text) == BEFORE_SHA256 and source.token_sha256(text) == BEFORE_TOKEN_SHA256,
            'inverse does not reconstruct historical Map')
    return text


def successor_source(root):
    """Build the exact after fixture; this does not qualify a live root."""
    record = read_record(root)
    text = (Path(root)/MODULE).read_bytes().decode('utf-8')
    if sha(text) == SCORE_AFTER_SHA256:
        text = score_predecessor_source(text)
    if sha(text) == FRONTIER_AFTER_SHA256:
        text = frontier_predecessor_source(text)
    if sha(text) == SUPPORT_AFTER_SHA256:
        text = support_predecessor_source(text)
    if sha(text) == OPTIONAL_AFTER_SHA256:
        text = optional_predecessor_source(text)
    if sha(text) == BEFORE_SHA256:
        require(source.token_sha256(text) == BEFORE_TOKEN_SHA256, 'before tokens changed')
        for edit in checked_edits(record):
            require(text.count(edit['before']) == 1, 'missing or ambiguous forward anchor')
            text = text.replace(edit['before'], edit['after'], 1)
    predecessor_source(text, record)
    return text


def verify_source(text, record):
    """Admit only the two exact reviewed physical source states."""
    require((record['before_sha256'], record['after_sha256'],
             record['before_token_sha256'], record['after_token_sha256']) ==
            (BEFORE_SHA256, AFTER_SHA256, BEFORE_TOKEN_SHA256, AFTER_TOKEN_SHA256),
            'reviewed endpoint metadata changed')
    digest = sha(text)
    require(digest in {BEFORE_SHA256, AFTER_SHA256}, 'unknown complete Map variant')
    require(source.token_sha256(text) == (BEFORE_TOKEN_SHA256 if digest == BEFORE_SHA256
                                         else AFTER_TOKEN_SHA256), 'actual Map tokens changed')
    if digest == BEFORE_SHA256:
        return None
    predecessor_source(text, record)
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256, 'after_sha256': AFTER_SHA256,
            'before_token_sha256': BEFORE_TOKEN_SHA256, 'after_token_sha256': AFTER_TOKEN_SHA256}


def dependency_inventory(root):
    """Resolve the actual maintained import closure, including package files."""
    root = Path(root)
    known = {path.as_posix() for path in cache_key.input_paths(root) if path.suffix == '.mojo'}
    found, pending = set(), [MODULE]
    while pending:
        name = pending.pop()
        if name in found:
            continue
        require(name in known, 'missing maintained dependency: '+name)
        found.add(name)
        text = (root/name).read_bytes().decode('utf-8')
        for imported in affected.imported_names(text):
            pending.extend(affected.resolve(imported, name, known))
    return found



def optional_predecessor_source(text):
    """Invert only the exact local-guard edge to the prior count successor."""
    require(sha(text) == OPTIONAL_AFTER_SHA256
            and source.token_sha256(text) == OPTIONAL_AFTER_TOKEN_SHA256,
            'unknown optional-guard successor')
    require(tuple(item[0] for item in OPTIONAL_EDITS) == (
        'winner_global_term_refusal', 'prepaid_retry_step_refusal',
        'retry_midpoint_enclosure'), 'optional-guard inverse inventory changed')
    for name, before, after in reversed(OPTIONAL_EDITS):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous optional-guard inverse: '+name)
        text = text.replace(after, before, 1)
    require(sha(text) == AFTER_SHA256 and source.token_sha256(text) == AFTER_TOKEN_SHA256,
            'optional-guard inverse does not reconstruct prior count source')
    return text


def optional_successor_source(root):
    """Build the fixed optional-guard fixture, without admitting a live root."""
    text = successor_source(root)
    for name, before, after in OPTIONAL_EDITS:
        require(text.count(before) == 1, 'missing optional-guard forward anchor: '+name)
        text = text.replace(before, after, 1)
    optional_predecessor_source(text)
    return text


def support_predecessor_source(text):
    """Invert the separate error/support edge to the unchanged optional endpoint."""
    require(sha(text) == SUPPORT_AFTER_SHA256
            and source.token_sha256(text) == SUPPORT_AFTER_TOKEN_SHA256,
            'unknown support-guard successor')
    require(tuple(item[0] for item in SUPPORT_EDITS) == (
        'nonnegative_stored_difference_error', 'bounded_finite_rounded_distance',
        'positive_finite_minimizer_support'), 'support-guard inverse inventory changed')
    for name, before, after in reversed(SUPPORT_EDITS):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous support-guard inverse: '+name)
        text = text.replace(after, before, 1)
    require(sha(text) == OPTIONAL_AFTER_SHA256
            and source.token_sha256(text) == OPTIONAL_AFTER_TOKEN_SHA256,
            'support-guard inverse does not reconstruct published optional source')
    return text


def support_successor_source(root):
    """Build only the fixed new fixture, without qualifying a physical root."""
    text = optional_successor_source(root)
    for name, before, after in SUPPORT_EDITS:
        require(text.count(before) == 1, 'missing support-guard forward anchor: '+name)
        text = text.replace(before, after, 1)
    support_predecessor_source(text)
    return text


def verify_support(root):
    """Verify the new edge and actual premises without masking older endpoints."""
    root = Path(root)
    record = read_record(root)
    text = (root/MODULE).read_bytes().decode('utf-8')
    optional = support_predecessor_source(text)
    middle = optional_predecessor_source(optional)
    prior_edge = verify_source(middle, record)
    require(prior_edge is not None, 'support edge must follow both prior successors')
    _verify_bound_inputs(root, record)
    verify_premises(root, record, after=True, optional=True, support=True)
    require((root/MODULE).read_bytes().decode('utf-8') == text,
            'Map changed during support-guard verification')
    optional_edge = {'path': MODULE, 'before_sha256': AFTER_SHA256,
                     'after_sha256': OPTIONAL_AFTER_SHA256,
                     'before_token_sha256': AFTER_TOKEN_SHA256,
                     'after_token_sha256': OPTIONAL_AFTER_TOKEN_SHA256}
    support_edge = {'path': MODULE, 'before_sha256': OPTIONAL_AFTER_SHA256,
                    'after_sha256': SUPPORT_AFTER_SHA256,
                    'before_token_sha256': OPTIONAL_AFTER_TOKEN_SHA256,
                    'after_token_sha256': SUPPORT_AFTER_TOKEN_SHA256}
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256,
            'after_sha256': SUPPORT_AFTER_SHA256,
            'before_token_sha256': BEFORE_TOKEN_SHA256,
            'after_token_sha256': SUPPORT_AFTER_TOKEN_SHA256,
            'edges': [prior_edge, optional_edge, support_edge]}


def frontier_predecessor_source(text):
    """Invert only the exact bounded-frontier edge to the support endpoint."""
    require(sha(text) == FRONTIER_AFTER_SHA256
            and source.token_sha256(text) == FRONTIER_AFTER_TOKEN_SHA256,
            'unknown frontier-reservation successor')
    require(tuple(item[0] for item in FRONTIER_EDITS) == (
        'bounded_winner_frontier_guard', 'saturating_winner_frontier_reservation'),
            'frontier-reservation inverse inventory changed')
    for name, before, after in reversed(FRONTIER_EDITS):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous frontier-reservation inverse: '+name)
        text = text.replace(after, before, 1)
    require(sha(text) == SUPPORT_AFTER_SHA256
            and source.token_sha256(text) == SUPPORT_AFTER_TOKEN_SHA256,
            'frontier inverse does not reconstruct separate support endpoint')
    return text


def frontier_successor_source(root):
    """Build the fixed frontier fixture without admitting an unreviewed root."""
    text = support_successor_source(root)
    for name, before, after in FRONTIER_EDITS:
        require(text.count(before) == 1, 'missing frontier forward anchor: '+name)
        text = text.replace(before, after, 1)
    frontier_predecessor_source(text)
    return text


def verify_frontier(root):
    """Verify the separate frontier edge, all earlier edges and actual premises."""
    root = Path(root)
    record = read_record(root)
    text = (root/MODULE).read_bytes().decode('utf-8')
    support = frontier_predecessor_source(text)
    optional = support_predecessor_source(support)
    middle = optional_predecessor_source(optional)
    prior_edge = verify_source(middle, record)
    require(prior_edge is not None, 'frontier edge must follow all preceding edges')
    _verify_bound_inputs(root, record)
    verify_premises(root, record, after=True, optional=True, support=True, frontier=True)
    require((root/MODULE).read_bytes().decode('utf-8') == text,
            'Map changed during frontier-reservation verification')
    endpoints = ((AFTER_SHA256, AFTER_TOKEN_SHA256),
                 (OPTIONAL_AFTER_SHA256, OPTIONAL_AFTER_TOKEN_SHA256),
                 (SUPPORT_AFTER_SHA256, SUPPORT_AFTER_TOKEN_SHA256),
                 (FRONTIER_AFTER_SHA256, FRONTIER_AFTER_TOKEN_SHA256))
    edges = [prior_edge]
    for before, after in zip(endpoints, endpoints[1:]):
        edges.append({'path': MODULE, 'before_sha256': before[0],
                      'after_sha256': after[0], 'before_token_sha256': before[1],
                      'after_token_sha256': after[1]})
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256,
            'after_sha256': FRONTIER_AFTER_SHA256,
            'before_token_sha256': BEFORE_TOKEN_SHA256,
            'after_token_sha256': FRONTIER_AFTER_TOKEN_SHA256, 'edges': edges}


def verify_score_live(text):
    """Check the physical helper AND complete caller before RHS projection.

    The caller pin includes exact arguments, branch, final loop position,
    borrowing/move, all writes, charges and fresh first-operation FP guard.
    The helper pin includes strict comparison, score evaluation, finite refusal
    and unmodified high endpoint. Check lexical owner and multiplicity too.
    """
    spans = _function_spans(text)
    for name, expected in (('_winner_seed_update_score', SCORE_HELPER_TOKEN_SHA256),
                           ('_try_winner_seed', SCORE_CALLER_TOKEN_SHA256)):
        require(sum(len(values) for (owner, found), values in spans.items()
                    if found == name) == 1, 'ambiguous score declaration: '+name)
        require(source.token_sha256(declaration(text, name, spans=spans)) == expected,
                'live score helper/caller operation graph changed: '+name)


def verify_score_caller_inventory(root):
    """Keep the borrowed helper's caller-supplied FP/scale preconditions closed.

    This new name has its own production census; historical protected-name
    pins remain immutable. Only the exact Map definition and one call exist.
    The existing census includes package re-exports and nested namespaces.
    """
    root = Path(root)
    found = {}
    for path in guard.production_mojo_paths(root):
        rel = path.relative_to(root)
        if rel.parts[0] in guard.NONPRODUCTION or any(p.startswith('.') for p in rel.parts):
            continue
        text = path.read_text()
        if '_winner_seed_update_score' not in text:
            continue
        count = sum(token.type == tokenize.NAME and token.string == '_winner_seed_update_score'
                    for token in source.tokens(text))
        if count:
            found[rel.as_posix()] = count
    require(found == {MODULE: 2}, 'score helper production caller inventory changed')


def score_live_observables(text):
    """Normalize only the proven result-to-upper correspondence, never omit it."""
    verify_score_live(text)
    actual = declaration(text, '_try_winner_seed')
    require(actual.count('certificate.upper = update[1]') == 1,
            'missing unique score upper correspondence')
    actual = actual.replace('certificate.upper = update[1]',
                            'certificate.upper = score.high', 1)
    return guard._winner_seed_live_observables(actual)


def score_predecessor_source(text):
    """Invert only the exact extraction edge to the unchanged frontier source."""
    require(sha(text) == SCORE_AFTER_SHA256
            and source.token_sha256(text) == SCORE_AFTER_TOKEN_SHA256,
            'unknown score-helper successor')
    verify_score_live(text)
    require(tuple(item[0] for item in SCORE_EDITS) == (
        'extract_finite_winner_score', 'call_finite_winner_score'),
            'score-helper inverse inventory changed')
    for name, before, after in reversed(SCORE_EDITS):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous score-helper inverse: '+name)
        text = text.replace(after, before, 1)
    require(sha(text) == FRONTIER_AFTER_SHA256
            and source.token_sha256(text) == FRONTIER_AFTER_TOKEN_SHA256,
            'score-helper inverse does not reconstruct frontier endpoint')
    return text


def score_successor_source(root):
    """Build the fixed extraction fixture without qualifying a physical root."""
    text = frontier_successor_source(root)
    for name, before, after in SCORE_EDITS:
        require(text.count(before) == 1, 'missing score-helper forward anchor: '+name)
        text = text.replace(before, after, 1)
    score_predecessor_source(text)
    return text


def verify_score(root):
    """Verify all five exact edges and live helper/caller/dependency premises."""
    root = Path(root)
    record = read_record(root)
    text = (root/MODULE).read_bytes().decode('utf-8')
    for path, expected in SCORE_TESTS.items():
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                'score-helper numerical fixture changed: '+path)
    frontier = score_predecessor_source(text)
    support = frontier_predecessor_source(frontier)
    optional = support_predecessor_source(support)
    middle = optional_predecessor_source(optional)
    prior_edge = verify_source(middle, record)
    require(prior_edge is not None, 'score edge must follow all preceding edges')
    _verify_bound_inputs(root, record)
    verify_score_caller_inventory(root)
    verify_premises(root, record, after=True, optional=True, support=True,
                    frontier=True, score=True)
    require((root/MODULE).read_bytes().decode('utf-8') == text,
            'Map changed during score-helper verification')
    endpoints = ((AFTER_SHA256, AFTER_TOKEN_SHA256),
                 (OPTIONAL_AFTER_SHA256, OPTIONAL_AFTER_TOKEN_SHA256),
                 (SUPPORT_AFTER_SHA256, SUPPORT_AFTER_TOKEN_SHA256),
                 (FRONTIER_AFTER_SHA256, FRONTIER_AFTER_TOKEN_SHA256),
                 (SCORE_AFTER_SHA256, SCORE_AFTER_TOKEN_SHA256))
    edges = [prior_edge]
    for before, after in zip(endpoints, endpoints[1:]):
        edges.append({'path': MODULE, 'before_sha256': before[0],
                      'after_sha256': after[0], 'before_token_sha256': before[1],
                      'after_token_sha256': after[1]})
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256,
            'after_sha256': SCORE_AFTER_SHA256,
            'before_token_sha256': BEFORE_TOKEN_SHA256,
            'after_token_sha256': SCORE_AFTER_TOKEN_SHA256, 'edges': edges}


def _verify_bound_inputs(root, record):
    require(dependency_inventory(root) == {MODULE, *record['unchanged_inputs']},
            'live import or package-resolution closure changed')
    for group in ('historical_records', 'unchanged_inputs', 'unchanged_correctness_tests',
                  'after_correctness_tests'):
        for path, expected in record[group].items():
            require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                    'historical record, live dependency or regression fixture changed: '+path)


def verify_optional(root):
    """Verify the distinct edge, preserving every earlier record and fixture."""
    root = Path(root)
    record = read_record(root)
    text = (root/MODULE).read_bytes().decode('utf-8')
    middle = optional_predecessor_source(text)
    prior_edge = verify_source(middle, record)
    require(prior_edge is not None, 'optional edge must follow the count successor')
    _verify_bound_inputs(root, record)
    verify_premises(root, record, after=True, optional=True)
    require((root/MODULE).read_bytes().decode('utf-8') == text,
            'Map changed during optional-guard verification')
    local_edge = {'path': MODULE, 'before_sha256': AFTER_SHA256,
                  'after_sha256': OPTIONAL_AFTER_SHA256,
                  'before_token_sha256': AFTER_TOKEN_SHA256,
                  'after_token_sha256': OPTIONAL_AFTER_TOKEN_SHA256}
    # The compatibility result describes the complete verified chain. The
    # immutable count edge itself still has only its original two endpoints.
    return {'path': MODULE, 'before_sha256': BEFORE_SHA256,
            'after_sha256': OPTIONAL_AFTER_SHA256,
            'before_token_sha256': BEFORE_TOKEN_SHA256,
            'after_token_sha256': OPTIONAL_AFTER_TOKEN_SHA256,
            'edges': [prior_edge, local_edge]}


def verify_premises(root, record, *, after, optional=False, support=False, frontier=False, score=False):
    """Check each actual operation graph independently of whole-file pins."""
    root = Path(root)
    require(not score or frontier, 'score premises require frontier edge')
    require(not frontier or support, 'frontier premises require the support edge')
    require(not support or (after and optional),
            'support premises require both preceding edges')
    # Read actual source on every call. Only exact-text lexical computation
    # is memoized; no filesystem snapshot, comparison or admission is cached.
    snapshots = {}
    for path, expected in record['layout_routing'].items():
        text = (root/path).read_bytes().decode('utf-8')
        if score and path == MODULE:
            verify_score_live(text)
            expected = SCORE_ROUTING_SHA256
        require(sha(guard.declaration_routing(text)) == expected,
                'live owning-storage or declaration routing changed: '+path)
        snapshots[path] = (text, _function_spans(text))
    for item in record['premise_declarations']:
        path = item['path']
        if path not in snapshots:
            text = (root/path).read_bytes().decode('utf-8')
            snapshots[path] = (text, _function_spans(text))
        text, spans = snapshots[path]
        actual = declaration(text,item['name'],tuple(item['owner']),spans=spans)
        expected = item['after_token_sha256'] if after else item['before_token_sha256']
        if optional and path == MODULE and not item['owner']:
            expected = OPTIONAL_PREMISE_HASHES.get(item['name'], expected)
        if support and path == MODULE and not item['owner']:
            expected = SUPPORT_PREMISE_HASHES.get(item['name'], expected)
        if frontier and path == MODULE and not item['owner']:
            expected = FRONTIER_PREMISE_HASHES.get(item['name'], expected)
        if score and path == MODULE and not item['owner'] and item['name'] == '_try_winner_seed':
            expected = SCORE_CALLER_TOKEN_SHA256
        require(source.token_sha256(actual) == expected,
                'live theorem premise changed: '+item['path']+':'+'.'.join([*item['owner'], item['name']]))
    if optional:
        require(after, 'optional premises require the count successor')
        for path, name, owner, expected in OPTIONAL_EXTRA_PREMISES:
            actual = declaration((root/path).read_bytes().decode('utf-8'), name, owner)
            require(source.token_sha256(actual) == expected,
                    'live optional-guard premise changed: '+path+':'+'.'.join((*owner,name)))
    if support:
        for path, name, owner, expected in SUPPORT_EXTRA_PREMISES:
            actual = declaration((root/path).read_bytes().decode('utf-8'), name, owner)
            require(source.token_sha256(actual) == expected,
                    'live support-guard premise changed: '+path+':'+'.'.join((*owner,name)))
    # These statements are read from the real after body, never the inverse.
    text = (root/MODULE).read_bytes().decode('utf-8')
    actual = guard.declaration(text, '_try_winner_seed', ())
    previous = score_predecessor_source(text) if score else text
    previous = frontier_predecessor_source(previous) if frontier else previous
    previous = support_predecessor_source(previous) if support else previous
    previous = optional_predecessor_source(previous) if optional else previous
    prior = guard.declaration(predecessor_source(previous, record) if after else previous,
                              '_try_winner_seed', ())
    actual_observables = (score_live_observables(text) if score else
                          guard._winner_seed_live_observables(actual))
    require(actual_observables ==
            guard._winner_seed_live_observables(prior),
            'live fresh-environment guard or ordered debits changed')


def verify(root):
    """Verify the exact edge, live arithmetic dependencies and regression input."""
    root = Path(root)
    record = read_record(root)
    text = (root/MODULE).read_bytes().decode('utf-8')
    if sha(text) == SCORE_AFTER_SHA256:
        return verify_score(root)
    if sha(text) == FRONTIER_AFTER_SHA256:
        return verify_frontier(root)
    if sha(text) == SUPPORT_AFTER_SHA256:
        return verify_support(root)
    if sha(text) == OPTIONAL_AFTER_SHA256:
        return verify_optional(root)
    edge = verify_source(text, record)
    if edge is None:
        return None
    _verify_bound_inputs(root, record)
    verify_premises(root, record, after=True)
    # A caller must not project a source different from the one just verified.
    require((root/MODULE).read_bytes().decode('utf-8') == text, 'Map changed during verification')
    return edge


def historical_source(root):
    """Return this named predecessor only after exact after-edge verification."""
    root = Path(root)
    text = (root/MODULE).read_bytes().decode('utf-8')
    if sha(text) == BEFORE_SHA256:
        return text
    require(sha(text) in {AFTER_SHA256, OPTIONAL_AFTER_SHA256, SUPPORT_AFTER_SHA256, FRONTIER_AFTER_SHA256, SCORE_AFTER_SHA256},
            'unknown Map cannot use a predecessor')
    require(verify(root) is not None, 'after Map did not activate its reviewed edge')
    require((root/MODULE).read_bytes().decode('utf-8') == text, 'Map changed during reconstruction')
    middle = score_predecessor_source(text) if sha(text) == SCORE_AFTER_SHA256 else text
    middle = frontier_predecessor_source(middle) if sha(middle) == FRONTIER_AFTER_SHA256 else middle
    middle = support_predecessor_source(middle) if sha(middle) == SUPPORT_AFTER_SHA256 else middle
    middle = optional_predecessor_source(middle) if sha(middle) == OPTIONAL_AFTER_SHA256 else middle
    return predecessor_source(middle, read_record(root))


def reviewed_text(root, path, text):
    """Project a token-equivalent view of the verified physical after Map.

    Comments in a caller's text view do not change the physical compiler
    input. Executable tokens, indentation and statement boundaries must
    still match. The live bytes and every successor dependency are checked
    on each call. Only explicitly named physical endpoints are admitted.
    """
    require(str(path) == MODULE, 'wrong supplied Map path')
    physical = (Path(root)/MODULE).read_bytes()
    digest = hashlib.sha256(physical).hexdigest()
    require(digest in {AFTER_SHA256, OPTIONAL_AFTER_SHA256, SUPPORT_AFTER_SHA256, FRONTIER_AFTER_SHA256, SCORE_AFTER_SHA256},
            'supplied after view needs the exact physical after Map')
    expected_tokens = (SCORE_AFTER_TOKEN_SHA256 if digest == SCORE_AFTER_SHA256
                       else FRONTIER_AFTER_TOKEN_SHA256 if digest == FRONTIER_AFTER_SHA256
                       else SUPPORT_AFTER_TOKEN_SHA256 if digest == SUPPORT_AFTER_SHA256
                       else OPTIONAL_AFTER_TOKEN_SHA256 if digest == OPTIONAL_AFTER_SHA256
                       else AFTER_TOKEN_SHA256)
    require(source.token_sha256(text) == expected_tokens,
            'unreviewed supplied Map source')
    require(verify(root) is not None, 'after Map did not activate its reviewed edge')
    require((Path(root)/MODULE).read_bytes() == physical,
            'Map changed during supplied-view verification')
    middle = physical.decode('utf-8')
    if digest == SCORE_AFTER_SHA256:
        middle = score_predecessor_source(middle)
    if sha(middle) == FRONTIER_AFTER_SHA256:
        middle = frontier_predecessor_source(middle)
    if sha(middle) == SUPPORT_AFTER_SHA256:
        middle = support_predecessor_source(middle)
    if sha(middle) == OPTIONAL_AFTER_SHA256:
        middle = optional_predecessor_source(middle)
    return predecessor_source(middle, read_record(root))
