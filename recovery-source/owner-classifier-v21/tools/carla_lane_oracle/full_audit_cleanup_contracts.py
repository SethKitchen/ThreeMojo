#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""New, reviewable source authority for the recovered CARLA cleanup.

This is a reconstruction, not the lost checker. Source admission is distinct
from native qualification. No historical record, budget, outcome or mask is
modified. Every projection is named and follows fresh physical admission.
"""
import ast
import hashlib
import importlib.util
import io
import json
import types
import os
from pathlib import Path
import stat
import struct
import sys
import threading
import tokenize


class ContractError(ValueError, RuntimeError):
    """A missing or changed premise prevents source admission."""


def require(ok, message):
    if not ok:
        raise ContractError('full-audit cleanup successor: ' + message)


try:
    if __package__:
        from . import source_contracts as source
        from . import sum2_guard_contracts as guard
    else:
        import source_contracts as source
        import sum2_guard_contracts as guard
except ImportError as error:
    raise ContractError('full-audit cleanup successor: dependency import failed') from error

# BEGIN GENERATED AUTHORITY CONSTANTS
MIGRATION = 'tools/carla_lane_oracle/full-audit-cleanup-successor.json'
MIGRATION_SHA256 = '36198962f9fba313b4da6d74651586e3d1da95a9904e63388aa3014cdada09c5'
SOURCE_PATHS = ('extensions/carla/curve_bounds.mojo',
 'extensions/carla/lane_value_bounds.mojo',
 'extensions/carla/lane_refinement.mojo',
 'extensions/carla/junction_bounds.mojo')
BEFORE_SHA256 = {'extensions/carla/curve_bounds.mojo': 'a57a5fa078fc6f36389a0abdce1eaa483a1cb7b7325688689a5602e8680ca3fb',
 'extensions/carla/junction_bounds.mojo': 'c933e03b6bde0bede8fb0745e9c1ef075d9699fde72b74795368943381d1aa74',
 'extensions/carla/lane_refinement.mojo': 'd6bb8cb266fa350491f71e92295e70bcbfc2566b34db02400b3a6cb5bb5a93ad',
 'extensions/carla/lane_value_bounds.mojo': '08978a7aa665aca4b82d41e1ff8b99451c647c0f8e7d6ee010fc6a6143f7959c'}
AFTER_SHA256 = {'extensions/carla/curve_bounds.mojo': 'a5f662df6bc146010b065341143c75223151289dc0cc633590d96b0a199ab8f5',
 'extensions/carla/junction_bounds.mojo': 'd8b7a6de8e495ab16f0cbe9688459eb544ac9ef6c8ec0c44c952ed5b4743a615',
 'extensions/carla/lane_refinement.mojo': '13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737',
 'extensions/carla/lane_value_bounds.mojo': '9028d65fdcb680ec5363f7fc974d8d46532b0f50397d7a348fc16e33821f4121'}
BEFORE_TOKEN_SHA256 = {'extensions/carla/curve_bounds.mojo': '9bc62290a6bdeca43c4d695a0f0ce6592d69f49386d83ce7342b667c73680fce',
 'extensions/carla/junction_bounds.mojo': '35aa94a154256542285a5dc4ab2b1a6378c501fb9cbf737511b129c23f51cb47',
 'extensions/carla/lane_refinement.mojo': '9893380d70f28a8cd85d41f21cb05102905f4ba528e7916437ba4397058895e0',
 'extensions/carla/lane_value_bounds.mojo': 'c844c435ae666043615f06c3e9fbed7ea83d2f48c8df02a600939d85802e8e31'}
AFTER_TOKEN_SHA256 = {'extensions/carla/curve_bounds.mojo': 'd22b440d4d1d9055701a82fb17a758e64cad1128d041389c653025feab33bec6',
 'extensions/carla/junction_bounds.mojo': 'fa2d376df3050ad4dec11a1ca6fb7abcc6359d8778d043595ede08d66fdc4540',
 'extensions/carla/lane_refinement.mojo': '9557481d4f1ef5a7d5349afde0258496c0d1bc9d57ad6e9741a0e496be5bda0d',
 'extensions/carla/lane_value_bounds.mojo': '58c92f55c0a0e3e5ccdfeedfcbf29eb1040a67db9bb6c7d6d7f857ac5d62b745'}
EDIT_NAMES = {'extensions/carla/curve_bounds.mojo': ('finite_nonnegative_blend',),
 'extensions/carla/junction_bounds.mojo': ('distinct_sorted_cut',),
 'extensions/carla/lane_refinement.mojo': ('finite_rounded_inverse',
                                           'finite_width_first',
                                           'post_local_natural_enclosure',
                                           'chord_endpoint_admission_before_derivative',
                                           'center_variant_import',
                                           'center_bound_declarations_and_producer',
                                           'center_cache_ownership_move',
                                           'center_invocation_context_initialization',
                                           'center_bound_proposal_dispatch'),
 'extensions/carla/lane_value_bounds.mojo': ('finite_nonnegative_blend',)}
CENTER_EDIT_NAMES = ('center_variant_import',
 'center_bound_declarations_and_producer',
 'center_cache_ownership_move',
 'center_invocation_context_initialization',
 'center_bound_proposal_dispatch')
CENTER_INTERMEDIATE_SHA256 = '370dee032a5e126e727c46d0ceb7103359f1ad7fba8151e341b594df0c7d0e30'
CENTER_DESCRIPTOR_SHA256 = '358877b68a90a0cbe94a0b794f79ef3a310061be12cd1eceacc5307948977c1f'
FROZEN_GROUP_SHA256 = {'additional_records': '51b1e14d2384ba3eb47ad51b565db8d6ba7c4cc3c60675989e68cc6d7b5c335d',
 'historical_records': '624f08764c8ba8ad6b9ba8559e4ce9f16522114be65eb0eaee684fc41d954add',
 'native_dependency_inputs': 'e84239a211d91b7df30a1b3431a03805541295b15bb5003d0aed67410e9161f6',
 'native_references': '80e0d013ed8ddf21c1be3a60d132508d8403ef3c3b83916212bfc05743eee55d',
 'native_support_inputs': 'b43540ff615c688a9a60e5e8a3d5c1b2e50613fe6d5f10660b30c4ec1b4826a9',
 'native_witnesses': 'd68d4edec7e65368cc8e708386b2479105f169464dc914fa28cfef2e63eb7fee',
 'theorem_documents': '55ade83bfe2fa27228609be9559d40b8fd455b71684702d9d0900f758222a2a1',
 'unchanged_inputs': '4539299b475e65adf0c87c72b77f837186d20ed1cef65f9c251826c136a30ef2'}
FROZEN_ORIGINAL_EDITS_SHA256 = {'extensions/carla/curve_bounds.mojo': '5b98742872aa686508477b48f579a98a51e5dc6563a5b5fd80b7fd2d4dacfad8',
 'extensions/carla/junction_bounds.mojo': 'b58641179b16d599bcaf8eea2806247e1155d99bbe8a548d00897013d3345015',
 'extensions/carla/lane_refinement.mojo': 'ff347dc85bb378a1c4553988edca3fd20c99bc144ae171618a72396de1fd775c',
 'extensions/carla/lane_value_bounds.mojo': '5b98742872aa686508477b48f579a98a51e5dc6563a5b5fd80b7fd2d4dacfad8'}
NATIVE_WITNESSES = ('tests/test_carla_tight_rounding.mojo',
 'tests/test_carla_sampled_value_bounds.mojo',
 'tests/test_carla_junction_endpoint_refusals.mojo',
 'tests/test_carla_chord_endpoint_refusals.mojo',
 'tests/test_carla_retained_boundary_guards.mojo',
 'tests/test_carla_width_overflow_admission.mojo',
 'tests/test_carla_lane_center_bound_phase.mojo',
 'tests/test_carla_speed_parser_exceptions.mojo',
 'tests/test_carla_lane_proof_fallback_residuals.mojo',
 'tests/test_carla_lane_cache_scale_residuals.mojo',
 'tests/test_carla_lane_search_positive_controls.mojo',
 'tests/test_carla_lane_search_edge_controls.mojo',
 'tests/test_carla_goal_directed.mojo',
 'tests/test_carla_rounded_arc_witness.mojo',
 'tests/test_spiral_lazy_taylor_paths.mojo',
 'tests/test_carla_optional_followup.mojo',
 'tests/test_carla_junction_arithmetic_states.mojo',
 'tests/test_carla_lane_local_scale_goal.mojo',
 'tests/test_spiral_domain_map_integration.mojo')
NATIVE_SUPPORT_INPUTS = ('tools/native_test_support.py', 'tools/fixtures/carla_sum2_fp_state.c')
NATIVE_SUPPORT_MAPPING = {'tests/test_carla_junction_endpoint_refusals.mojo': ['tools/fixtures/carla_sum2_fp_state.c'],
 'tests/test_carla_sum2_environment.mojo': ['tools/fixtures/carla_sum2_fp_state.c']}
THEOREM_DOCUMENT = 'docs/validation/full-audit-711-invariants.md'
DEPENDENCY_TOOL_SHA256 = {'tools/affected.py': 'a56194a3e722ad341a42f3defec282b8154f5e4db8340df855f0199ea9830ebb',
 'tools/cache_key.py': 'ec06247feb8fe079c30b6da19fc655ffec363f1ce8e3372d063bf728e8c804c4',
 'tools/carla_lane_oracle/source_contracts.py': '857dd399291611dd35e11adbbdde0fca03ed4ff4277eec54ed3ec5815bbaf791',
 'tools/carla_lane_oracle/sum2_guard_contracts.py': '870073a08ebf9a99c06c8fb618d5576f69d88ffb1dc1dcc2347baddd9cb29afd'}
SUM2_CALLER_SHA256 = {'extensions/carla/curve_bounds.mojo': {'_lane_jet_model_proof': ('78af46e5597996ebc42df93d5810dfb53106f0b13ee3f356e4f7881108403083',),
                                        '_spiral_expression': ('ec69aa43b922b41ce5e3640695c1c2658b4e7b57e05cd73b915cef3aa54e54bc',)},
 'extensions/carla/lane_refinement.mojo': {'_continue_lane_certificate': ('b184c43c38c7482351e8979b85976da7a90e707c909d9b37dc9d8e8f8466ec38',),
                                           '_lane_certificate_contains': ('af1e51d5cfa1b29d9998354307b9b2ff28a7590b312caf4504266ce9732b0928',),
                                           '_refine_lane_certificate': ('1008c34c542d249660b38b314c98a8f353d81ab63dc318d3a66853a6646f7501',),
                                           '_run_lane_search': ('6ca003f3fa02f7f06cc1184bfb2bbbec60506dfcf05288aa3010114ed1c2456f',
                                                                'af1c6ca7a4d14f4e1b1be5046bff33be946882e56eb655e19c4720da6ce63479')}}
INVENTORY_NAMES = frozenset({'_LaneBoundClose',
           '_LaneBoundContract',
           '_LaneBoundDiscard',
           '_LaneBoundPolicy',
           '_LaneBoundProposal',
           '_LaneExpansionContext',
           '_ObjectiveModel',
           '_RoundedBox',
           '_chord_certificate_impl_with_nodes',
           '_expansion_center',
           '_global_lower',
           '_insert_break',
           '_lane_section_box_with_work',
           '_local_seed',
           '_minimizer_support',
           '_objective_followup_room',
           '_objective_recheck_room',
           '_reference_work',
           '_refinement_square',
           '_restrict_objective_model',
           '_rounded_axis_lane_minimum',
           '_rounded_line_axis_context',
           '_rounded_operand',
           '_roundoff',
           '_run_lane_search',
           '_sample_blend_jet',
           '_sample_blend_value',
           '_scaled_point_distance_box',
           '_stored_blend_error',
           '_try_lane_center_bound',
           '_try_objective_model',
           '_try_proof_expansion_jet',
           'curve_bounds',
           'curve_objective_model',
           'junction_bounds',
           'lane_refinement',
           'lane_value_bounds'})
# END GENERATED AUTHORITY CONSTANTS

BOUND_GROUPS = ('unchanged_inputs', 'historical_records', 'additional_records',
                'native_references', 'native_witnesses',
                'native_dependency_inputs', 'native_support_inputs',
                'theorem_documents')
NONPRODUCTION = frozenset({'tests', 'examples', 'bench', 'tools', 'docs', 'assets',
                          'out', 'coverage', 'cache', 'build', 'node_modules'})
SKIP = frozenset({'.git', '.venv', '.cache', 'out', 'node_modules', '__pycache__',
                  '.agents', '.claude'})
CHECKER_PATHS = ('tools/carla_lane_oracle/full_audit_cleanup_contracts.py',
                 'tools/carla_lane_oracle/source_contracts.py',
                 'tools/carla_lane_oracle/sum2_guard_contracts.py',
                 'tools/affected.py', 'tools/cache_key.py')


def _center_require(ok, message):
    require(ok, 'center extraction: ' + message)


def sha(value):
    return hashlib.sha256(value.encode() if isinstance(value, str) else value).hexdigest()


def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))


def _rows(text):
    """Bind statement depth, qualifiers, STRING spelling and operand order."""
    require(type(text) is str, 'source is not text')
    result, statement, depth = [], [], 0
    try:
        for token in source.tokens(text):
            if token.type == tokenize.INDENT:
                depth += 1
            elif token.type == tokenize.DEDENT:
                depth -= 1
                require(depth >= 0, 'unmatched lexical scope')
            elif token.type == tokenize.NEWLINE:
                if statement:
                    result.append([depth, statement])
                    statement = []
            elif token.type not in (tokenize.NL, tokenize.COMMENT, tokenize.ENDMARKER):
                statement.append([token.type, token.string])
    except (ValueError, SyntaxError, tokenize.TokenError, IndentationError) as error:
        raise ContractError('full-audit cleanup successor: invalid lexical source') from error
    require(not statement and depth == 0, 'unterminated lexical statement')
    return result


def _words(row):
    return [word for kind, word in row[1]]


def _values(text):
    rows = _rows(text + '\n')
    require(len(rows) == 1, 'expected one lexical statement')
    return rows[0][1]


def _declaration_rows(text, name, kind='def'):
    stream = _rows(text)
    found = [i for i, row in enumerate(stream) if _words(row)[:2] == [kind, name]]
    require(len(found) == 1, 'missing or duplicate declaration: ' + name)
    begin = found[0]
    require(stream[begin][0] == 0, 'wrong declaration owner: ' + name)
    end = begin + 1
    if kind != 'comptime':
        while end < len(stream) and stream[end][0] > 0:
            end += 1
        while begin and stream[begin - 1][0] == 0 and _words(stream[begin - 1])[:1] == ['@']:
            begin -= 1
    return stream[begin:end]


def _routing_rows(text):
    # Omit only function suites, not arbitrary nested suites. Imports, aliases,
    # decorators, traits, structure fields and method signatures remain live.
    result, function_depth = [], None
    for row in _rows(text):
        depth = row[0]
        if function_depth is not None:
            if depth > function_depth:
                continue
            function_depth = None
        result.append(row)
        if _words(row)[:1] in (['def'], ['fn']):
            function_depth = depth
    return result


def declaration_sha256(text, name):
    return sha(_canonical(_declaration_rows(text, name)))


def center_declaration_sha256(text, name, kind):
    """Hash one complete top-level declaration, including decorators/fields."""
    try:
        _center_require(kind in ('def', 'struct', 'comptime'), 'unknown declaration kind')
        return sha(_canonical(_declaration_rows(text, name, kind)))
    except (ContractError, ValueError, TypeError, KeyError, IndexError) as error:
        raise ContractError('full-audit cleanup successor: center extraction: malformed declaration') from error


CENTER_SUBSTITUTIONS = (
    ('context.section', 'section', 4), ('context.lane', 'lane', 4),
    ('context.root.low', 'low', 1), ('context.root.high', 'high', 1),
    ('context.location', 'location', 5), ('context.spiral_proof', 'spiral_proof', 3),
    ('context.frozen', 'frozen', 2), ('context.external_witness', 'external_witness', 5),
    ('context.cached_fast', 'cached_fast', 5), ('context.cached_expansion', 'cached_expansion', 5),
    ('cell.low', 'lo', 9), ('cell.high', 'hi', 9), ('policy.upper', 'best_upper', 7),
    ('policy.scale', 'scale', 11), ('policy.tolerance', 'tolerance', 4),
    ('policy.goal', 'goal', 4), ('whole_work', 'work', 2),
    ('terms', 'certificate.terms', 7), ('nodes', 'certificate.nodes', 2),
)


def _center_substitute(stream):
    counts = {name: 0 for name, _, _ in CENTER_SUBSTITUTIONS}
    rules = [(name, _values(name), _values(old)) for name, old, _ in CENTER_SUBSTITUTIONS]
    result = []
    for depth, values in stream:
        target, index = [], 0
        while index < len(values):
            for name, before, after in rules:
                # A root cannot begin after a member selector. Following
                # selectors such as context.frozen.value() remain legal.
                if (values[index:index + len(before)] == before
                        and (index == 0 or values[index - 1] != [tokenize.OP, '.'])):
                    counts[name] += 1
                    target.extend(after)
                    index += len(before)
                    break
            else:
                target.append(values[index])
                index += 1
        result.append([depth, target])
    _center_require(counts == {name: count for name, _, count in CENTER_SUBSTITUTIONS},
                    'substitution counts changed')
    return result


def _center_phase(text, current):
    stream = _declaration_rows(text, '_try_lane_center_bound' if current else '_run_lane_search')
    starts = [i for i, row in enumerate(stream)
              if _words(row)[:4] == ['var', 'center_s', '=', '_expansion_center']]
    _center_require(len(starts) == 1, 'missing or ambiguous numerical phase')
    start = starts[0]
    base = stream[start][0]
    if current:
        _center_require(_words(stream[-1]) == ['return', 'None']
                        and stream[-1][0] == base, 'fallthrough changed')
        end = len(stream) - 1
    else:
        end = start + 1
        while end < len(stream) and stream[end][0] >= base:
            end += 1
    return [[depth - base, values] for depth, values in stream[start:end]]


def _center_descriptor(descriptor):
    _center_require(type(descriptor) is dict, 'descriptor is not an object')
    fields = {'schema', 'name', 'intermediate_source', 'intermediate_sha256',
              'intermediate_token_sha256', 'edit_names', 'substitution_counts',
              'exit_map', 'formatting_sites', 'phase_statement_counts',
              'local_declaration', 'structural_declarations',
              'function_declarations', 'intermediate_declarations',
              'canonical_phase_sha256', 'intermediate_routing_sha256', 'current_routing_sha256'}
    _center_require(set(descriptor) == fields, 'descriptor fields changed')
    try:
        descriptor_digest = sha(_canonical(descriptor))
    except (TypeError, ValueError) as error:
        raise ContractError('full-audit cleanup successor: center extraction: malformed descriptor data') from error
    _center_require(descriptor_digest == CENTER_DESCRIPTOR_SHA256, 'immutable descriptor changed')
    _center_require(type(descriptor['schema']) is int and descriptor['schema'] == 1,
                    'descriptor schema changed')
    _center_require(descriptor['intermediate_sha256'] == CENTER_INTERMEDIATE_SHA256
                    and sha(descriptor['intermediate_source']) == CENTER_INTERMEDIATE_SHA256,
                    'intermediate authority changed')
    _center_require(descriptor['substitution_counts'] ==
                    {name: count for name, _, count in CENTER_SUBSTITUTIONS},
                    'descriptor substitution counts changed')
    _center_require(descriptor['edit_names'] == list(CENTER_EDIT_NAMES), 'center edit scope changed')


def _replace_rows(stream, old, new, label):
    _center_require(bool(old), 'empty row replacement: ' + label)
    starts = [i for i in range(len(stream) - len(old) + 1) if stream[i:i + len(old)] == old]
    _center_require(len(starts) == 1, 'missing or ambiguous ' + label)
    index = starts[0]
    return stream[:index] + new + stream[index + len(old):]


def _format_site_safe(old, current):
    """Only the four reviewed formatter effects, never general token erasure."""
    if len(old) != 1 or len(current) != 1 or old[0][0] != current[0][0]:
        return False
    before, after = old[0][1], current[0][1]
    bw, aw = _words(old[0]), _words(current[0])
    if bw[:2] == ['raise', 'Error'] and aw[:2] == ['raise', 'Error']:
        expected_old = _values('raise Error("Lane refinement exhausted its quadrature work" " limit")')
        expected_new = _values('raise Error("Lane refinement exhausted its quadrature work limit")')
        return before == expected_old and after == expected_new
    if bw[:2] == ['if', '(']:
        return before == _values('if (domain.second.is_finite() or not domain.rounded_value().is_finite()):') and after == _values('if domain.second.is_finite() or not domain.rounded_value().is_finite():')
    for call in ('center = _frozen_arc_expansion(frozen.value(), center_s, location, scale)',
                 'center = _expansion_distance_jet(road, section, lane, center_s, location, scale)'):
        if before == _values(call) and after == _values(call[:-1] + ',)'):
            return True
    return False


def verify_center_correspondence(intermediate_text, current_text, descriptor):
    """Check the numerical stream and scoped ownership before any projection.

    The supplied current source is not admitted by a complete after-hash here.
    Counts, exact exit payload/predicate/depth, every canonical statement and
    full context/caller declarations independently protect extraction semantics.
    """
    try:
        _center_descriptor(descriptor)
        before = _center_phase(intermediate_text, False)
        after_raw = _center_phase(current_text, True)
        after = _center_substitute(after_raw)
        _center_require(len(before) == 79 and len(after_raw) == 73,
                        'raw phase statement count changed')
        for entry in descriptor['exit_map']:
            label = entry['name']
            sentinel = [entry['depth'], [['exit', label], ['alternative', entry['alternative']],
                                       ['lower', entry['lower']], ['support', entry['support']]]]
            before = _replace_rows(before, [entry['predicate'], *entry['before_rows']],
                                   [entry['predicate'], sentinel], 'old exit ' + label)
            after = _replace_rows(after, [entry['predicate'], *entry['after_rows']],
                                  [entry['predicate'], sentinel], 'new exit ' + label)
        after = _replace_rows(after, [descriptor['local_declaration']], [], 'point-domain local binding')
        for site in descriptor['formatting_sites']:
            _center_require(_format_site_safe(site['old'], site['current']), 'unreviewed formatter site')
            before = _replace_rows(before, site['old'], site['current'], 'formatter correspondence')
        _center_require(len(before) == len(after) == 72 and before == after,
                        'canonical numerical statement stream changed')
        _center_require(sha(_canonical(after)) == descriptor['canonical_phase_sha256'],
                        'reviewed canonical numerical phase changed')
        _center_require(sha(_canonical(_routing_rows(intermediate_text))) == descriptor['intermediate_routing_sha256']
                        and sha(_canonical(_routing_rows(current_text))) == descriptor['current_routing_sha256'],
                        'module declaration/import/alias routing changed')
        for name, item in descriptor['structural_declarations'].items():
            _center_require(center_declaration_sha256(current_text, name, item['kind']) == item['tokens_sha256'],
                            'structural declaration changed: ' + name)
        for name, expected in descriptor['function_declarations'].items():
            _center_require(declaration_sha256(current_text, name) == expected,
                            'current scoped declaration changed: ' + name)
        for name, expected in descriptor['intermediate_declarations'].items():
            _center_require(declaration_sha256(intermediate_text, name) == expected,
                            'predecessor scoped declaration changed: ' + name)
    except ContractError as error:
        if 'center extraction:' in str(error):
            raise
        raise ContractError('full-audit cleanup successor: center extraction: ' + str(error)) from error
    except (KeyError, IndexError, TypeError, ValueError, SyntaxError, tokenize.TokenError,
            IndentationError, UnicodeError) as error:
        raise ContractError('full-audit cleanup successor: center extraction: malformed source or descriptor') from error


def _reverse_span(text, edit):
    require(type(edit) is dict and set(edit) ==
            {'name', 'before', 'after', 'before_sha256', 'after_sha256'}, 'wrong inverse span fields')
    for side in ('before', 'after'):
        require(type(edit[side]) is str and bool(edit[side])
                and sha(edit[side]) == edit[side + '_sha256'], 'inverse span digest changed: ' + edit['name'])
    require(text.count(edit['after']) == 1, 'missing or ambiguous inverse span: ' + edit['name'])
    return text.replace(edit['after'], edit['before'], 1)


def reverse_center_exact(text, item):
    _center_require(type(item) is dict and 'center_extraction' in item, 'missing inverse descriptor')
    descriptor = item['center_extraction']
    _center_descriptor(descriptor)
    _center_require(sha(text) == AFTER_SHA256[SOURCE_PATHS[2]] and text == item['after_source'],
                    'complete center inverse endpoint changed')
    _center_require(tuple(edit['name'] for edit in item['edits']) == EDIT_NAMES[SOURCE_PATHS[2]],
                    'missing, duplicate, reordered or extra inverse edit')
    for edit in reversed(item['edits'][-len(CENTER_EDIT_NAMES):]):
        text = _reverse_span(text, edit)
    _center_require(sha(text) == CENTER_INTERMEDIATE_SHA256
                    and text == descriptor['intermediate_source'], 'exact intermediate reconstruction failed')
    return text


def reverse_exact(path, text, item):
    require(path in SOURCE_PATHS, 'unlisted inverse source')
    require(sha(text) == AFTER_SHA256[path] and text == item['after_source'], 'complete inverse endpoint changed: ' + path)
    require(tuple(e['name'] for e in item['edits']) == EDIT_NAMES[path], 'inverse edit inventory changed: ' + path)
    edits = item['edits']
    if path == SOURCE_PATHS[2]:
        text = reverse_center_exact(text, item)
        edits = edits[:-len(CENTER_EDIT_NAMES)]
    for edit in reversed(edits):
        text = _reverse_span(text, edit)
    require(sha(text) == BEFORE_SHA256[path] and text == item['before_source'], 'exact predecessor reconstruction failed: ' + path)
    return text


def verify_chord_refusal_order(item):
    """Bind the two intact independent refusal blocks and their sole permutation."""
    edit = item['edits'][3]
    require(edit['name'] == 'chord_endpoint_admission_before_derivative', 'chord inverse changed')
    before, after = _rows(edit['before']), _rows(edit['after'])
    # Each leading indented fragment has the same harmless wrapper only for
    # tokenization; rows are otherwise exact. Five statements: derivative,
    # derivative refusal/return, two count calls, count refusal/return.
    require(len(before) == len(after) == 7, 'chord refusal statement count changed')
    require(after == before[3:] + before[:3], 'chord refusal is not the fixed block permutation')
    require(_words(before[2]) == _words(before[6]) == ['return', '(', 'natural', ',', 'box', ',', 'spent', ')'],
            'chord refusal return payload changed')


def read_record(root):
    """Read immutable authority afresh; this function does not admit live source."""
    require(MIGRATION_SHA256 != 'UNSEALED', 'candidate is not sealed')
    try:
        raw = (Path(root) / MIGRATION).read_bytes()
        require(sha(raw) == MIGRATION_SHA256, 'immutable successor record changed')
        record = json.loads(raw, object_pairs_hook=source.unique_keys)
        require(type(record['schema']) is int and record['schema'] == 3, 'wrong new recovery schema')
        require(set(record['sources']) == set(SOURCE_PATHS), 'wrong source endpoint set')
        for group, expected in FROZEN_GROUP_SHA256.items():
            require(sha(_canonical(record[group])) == expected, 'immutable input group changed: ' + group)
        for path, item in record['sources'].items():
            require(item['before_sha256'] == BEFORE_SHA256[path] and item['after_sha256'] == AFTER_SHA256[path],
                    'endpoint metadata changed: ' + path)
            for side in ('before', 'after'):
                require(sha(item[side + '_source']) == item[side + '_sha256']
                        and source.token_sha256(item[side + '_source']) == item[side + '_token_sha256'],
                        'recorded source changed: ' + path)
            old_edits = item['edits'][:-len(CENTER_EDIT_NAMES)] if path == SOURCE_PATHS[2] else item['edits']
            require(sha(_canonical(old_edits)) == FROZEN_ORIGINAL_EDITS_SHA256[path],
                    'fixed original inverse objects changed: ' + path)
        _center_descriptor(record['sources'][SOURCE_PATHS[2]]['center_extraction'])
        return record
    except ContractError:
        raise
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError) as error:
        raise ContractError('full-audit cleanup successor: unreadable or malformed record') from error


OBSERVATION_NAMES = frozenset({'nodes', 'terms', 'max_nodes', 'max_terms', 'work',
    'max_work', '_require_sum2_environment', '_sum2_supported_environment',
    'MapBuildBudget', 'MapBuildWork'})
OBSERVATION_RENAMES = (
    (33, 'var point = _checked_center(road, section, lane, seed, terms, max_terms)',
         'var seed_point = _checked_center(road, section, lane, seed, terms, max_terms)'),
    (34, 'return (seed, _legacy_square(point, query), point^, nodes, terms)',
         'return (seed, _legacy_square(seed_point, query), seed_point^, nodes, terms,)'),
)


def live_observations(text):
    return [row for row in _rows(text) if set(_words(row)) & OBSERVATION_NAMES]


def verify_observations(path, text, item):
    observed = live_observations(text)
    require(observed == item['live_observations'], 'live environment, budget or debit changed: ' + path)
    before = [row[1] for row in live_observations(item['before_source'])]
    retained = observed
    if path == SOURCE_PATHS[2]:
        intermediate = reverse_center_exact(item['after_source'], item)
        retained = live_observations(intermediate)
        require(retained == item['intermediate_observations'], 'intermediate observations changed')
    after = [row[1] for row in retained]
    if path == SOURCE_PATHS[2]:
        # One-based rows34/35 are the sole rounded-seed local rename and
        # the formatter's trailing return comma, never generic token erasure.
        for ordinal, old, new in OBSERVATION_RENAMES:
            require(ordinal < len(before) and ordinal < len(after)
                    and before[ordinal] == _values(old) and after[ordinal] == _values(new),
                    'rounded-seed local correspondence changed')
            before[ordinal] = _values(new)
    require(before == after, 'ordered environment/budget/debit operations changed: ' + path)


def _physical_text(raw):
    # Physical CRLF equivalence is universal-newline decoding, not rewriting
    # backslash escapes or STRING tokens inside the lexer.
    with io.TextIOWrapper(io.BytesIO(raw), encoding='utf-8', newline=None) as reader:
        return reader.read()


def _sibling(name):
    path = Path(__file__).resolve().parents[1] / (name + '.py')
    relative = 'tools/' + name + '.py'
    require(not path.is_symlink() and sha(path.read_bytes()) == DEPENDENCY_TOOL_SHA256.get(relative),
            'unreviewed maintained dependency tool: ' + relative)
    key = '_full_audit_cleanup_' + name
    module = sys.modules.get(key)
    if module is None:
        spec = importlib.util.spec_from_file_location(key, path)
        require(spec is not None and spec.loader is not None, 'missing maintained dependency tool')
        module = importlib.util.module_from_spec(spec)
        sys.modules[key] = module
        spec.loader.exec_module(module)
    return module


def _code_constant(value):
    """Typed immutable constants; no marshal reference/interning encoding."""
    if isinstance(value, types.CodeType):
        return ('code', _code_identity(value))
    if type(value) is tuple:
        return ('tuple', tuple(_code_constant(item) for item in value))
    if type(value) is frozenset:
        return ('frozenset', frozenset(_code_constant(item) for item in value))
    if type(value) is float:
        return ('float', struct.pack('>d', value))
    if type(value) is complex:
        return ('complex', struct.pack('>dd', value.real, value.imag))
    if value is Ellipsis:
        return ('ellipsis',)
    require(type(value) in (str, bytes, int, bool, type(None)), 'unsupported executed-code constant')
    return (type(value).__name__, value)


def _code_identity(code):
    require(type(code) is types.CodeType, 'missing executed module-code witness')
    # Compare every public code-data field, recursively. The sole normalized
    # field is co_filename, which may differ for the same relocated checkout.
    # This does not serialize object identities, refcounts or string interning.
    return tuple((name, _code_constant(getattr(code, name))) for name in sorted(dir(code))
                 if name.startswith('co_') and name != 'co_filename'
                 and not callable(getattr(code, name)))


def _compiled_functions(raw, filename):
    module_code = compile(raw, filename, 'exec', dont_inherit=True, optimize=sys.flags.optimize)
    return {item.co_name: item for item in module_code.co_consts if isinstance(item, types.CodeType)}


def _compiled_defaults(raw):
    result = {}
    def collect(statements, owner=''):
        for statement in statements:
            if isinstance(statement, (ast.FunctionDef, ast.AsyncFunctionDef)):
                try:
                    positional = tuple(ast.literal_eval(value) for value in statement.args.defaults)
                    keyword = {name.arg: ast.literal_eval(value) for name, value
                               in zip(statement.args.kwonlyargs, statement.args.kw_defaults, strict=True)
                               if value is not None}
                except (ValueError, TypeError) as error:
                    raise ContractError('full-audit cleanup successor: unsupported checker default expression') from error
                result[owner + statement.name] = (positional or None, keyword or None)
            elif isinstance(statement, ast.ClassDef):
                collect(statement.body, owner + statement.name + '.')
    collect(ast.parse(raw).body)
    return result


def _check_defaults(value, expected, label):
    while hasattr(value, '__wrapped__'):
        value = value.__wrapped__
    require(expected is not None and (getattr(value, '__defaults__', None),
            getattr(value, '__kwdefaults__', None)) == expected,
            'executing callable defaults changed: ' + label)


# This is code identity, not an admission/result/read/resolver cache. The
# actually executing top-level checker code must match captured physical source.
_IMPORT_IDENTITIES = {}
_IMPORT_CODE = {}
_IMPORT_MODULE_CODE = {}
_IMPORT_DEFAULTS = {}
_SELF_PATH = Path(__file__).resolve()
_SELF_RAW = _SELF_PATH.read_bytes()
require(_code_identity(sys._getframe().f_code) == _code_identity(compile(
        _SELF_RAW, __file__, 'exec', dont_inherit=True, optimize=sys.flags.optimize)),
        'executing checker code does not match source')
_IMPORT_IDENTITIES[str(_SELF_PATH)] = sha(_SELF_RAW)
_IMPORT_CODE[str(_SELF_PATH)] = _compiled_functions(_SELF_RAW, __file__)
_IMPORT_MODULE_CODE[str(_SELF_PATH)] = sys._getframe().f_code
_IMPORT_DEFAULTS[str(_SELF_PATH)] = _compiled_defaults(_SELF_RAW)
for _module in (source, guard, _sibling('affected'), _sibling('cache_key')):
    require(type(getattr(_module, '__file__', None)) is str, 'incomplete dependency module identity')
    _path = Path(_module.__file__).resolve()
    require(Path(__file__).resolve().parents[2] in _path.parents, 'dependency module came from another root')
    try:
        _raw = _path.read_bytes()
    except OSError as _error:
        raise ContractError('full-audit cleanup successor: unreadable executing dependency source') from _error
    _IMPORT_IDENTITIES[str(_path)] = sha(_raw)
    _IMPORT_CODE[str(_path)] = _compiled_functions(_raw, _module.__file__)
    _relative = _path.relative_to(Path(__file__).resolve().parents[2]).as_posix()
    require(sha(_raw) == DEPENDENCY_TOOL_SHA256.get(_relative), 'unreviewed dependency checker bytes: ' + _relative)
    _executed = getattr(_module, '_EXECUTED_MODULE_CODE', None)
    require(isinstance(_executed, types.CodeType)
            and _code_identity(_executed) == _code_identity(compile(_raw, _module.__file__, 'exec',
                dont_inherit=True, optimize=sys.flags.optimize)),
            'executed dependency module differs from captured source: ' + _relative)
    _IMPORT_MODULE_CODE[str(_path)] = _executed
    _IMPORT_DEFAULTS[str(_path)] = _compiled_defaults(_raw)


def _live_function_code(value):
    seen = set()
    while hasattr(value, '__wrapped__'):
        require(id(value) not in seen, 'cyclic executing function wrapper')
        seen.add(id(value))
        value = value.__wrapped__
    return getattr(value, '__code__', None)


def executing_checker_bindings(root=None):
    base = Path(__file__).resolve().parents[2]
    modules = (globals(), vars(source), vars(guard), vars(_sibling('affected')), vars(_sibling('cache_key')))
    result = {}
    for relative, namespace in zip(CHECKER_PATHS, modules, strict=True):
        path = base / relative
        key = str(path.resolve())
        captured = _IMPORT_IDENTITIES.get(key)
        require(captured is not None and not path.is_symlink() and sha(path.read_bytes()) == captured,
                'executing checker bytes changed: ' + relative)
        if relative != CHECKER_PATHS[0]:
            require(namespace.get('_EXECUTED_MODULE_CODE') is _IMPORT_MODULE_CODE[key]
                    and captured == DEPENDENCY_TOOL_SHA256[relative],
                    'executed module-code witness changed: ' + relative)
        for name, expected in _IMPORT_CODE[key].items():
            live = namespace.get(name)
            # Top-level class bodies execute once; check their methods against
            # the class code's definitions. Simple classes may have none.
            if isinstance(live, type):
                expected_methods = {c.co_name: c for c in expected.co_consts if isinstance(c, types.CodeType)}
                for method, code in expected_methods.items():
                    actual = _live_function_code(getattr(live, method, None))
                    _check_defaults(getattr(live, method, None), _IMPORT_DEFAULTS[key].get(name + '.' + method), relative + ':' + name + '.' + method)
                    require(actual is not None and _code_identity(actual) == _code_identity(code),
                            'executing class method changed: ' + relative + ':' + name + '.' + method)
            elif name.startswith('<'):
                continue
            else:
                actual = _live_function_code(live)
                _check_defaults(live, _IMPORT_DEFAULTS[key].get(name), relative + ':' + name)
                require(actual is not None and _code_identity(actual) == _code_identity(expected),
                        'executing function changed: ' + relative + ':' + name)
        if root is not None:
            supplied = Path(root) / relative
            require(not supplied.is_symlink() and sha(supplied.read_bytes()) == captured,
                    'receipt checker differs from executing checker: ' + relative)
        result[relative] = captured
    return result


def _root_unaliased(root):
    absolute = Path(root).absolute()
    return all(not path.is_symlink() for path in (absolute, *absolute.parents))


def _regular(root, relative):
    parts = Path(relative).parts
    require(parts and not Path(relative).is_absolute() and '..' not in parts, 'unsafe input path')
    path = Path(root)
    require(_root_unaliased(path), 'symbolic root or ancestor')
    for part in parts:
        path = path / part
        require(not path.is_symlink(), 'symlink input: ' + relative)
    require(stat.S_ISREG(path.stat().st_mode), 'input is not a regular file: ' + relative)
    return path


def inventory(root, *, _snapshots=None, _production=None):
    """Fresh whole-production census, including new packages and re-exports."""
    result = {}
    for path in sorted(guard.production_mojo_paths(Path(root))):
        relative = path.relative_to(root).as_posix()
        if _production is not None:
            _production.add(relative)
        path = _regular(root, relative)
        raw = path.read_bytes()
        if _snapshots is not None:
            previous = _snapshots.setdefault(relative, raw)
            require(previous == raw, 'source changed during caller census: ' + relative)
        text = _physical_text(raw)
        if not any(name in text for name in INVENTORY_NAMES):
            continue
        names = {token.string for token in source.tokens(text) if token.type == tokenize.NAME}
        if names & INVENTORY_NAMES:
            result[relative] = {'tokens_sha256': source.token_sha256(text)}
    return result


def dependency_inventory(root, *, roots=(), entries=(), _known=None, _snapshots=None):
    inputs, affected = _sibling('cache_key'), _sibling('affected')
    known = _known if _known is not None else {p.as_posix() for p in inputs.input_paths(root) if p.suffix == '.mojo'}
    found, pending = set(), list(roots)
    while pending:
        path = pending.pop()
        if path in found:
            continue
        require(path in known, 'missing maintained dependency: ' + path)
        found.add(path)
        raw = _regular(root, path).read_bytes()
        if _snapshots is not None:
            previous = _snapshots.setdefault(path, raw)
            require(previous == raw, 'source changed during import census: ' + path)
        text = _physical_text(raw)
        for name in affected.imported_names(text):
            pending.extend(affected.resolve(name, path, known, entries=entries))
    return found


def _native_dependency_inventory(root, *, witnesses, _known=None, _snapshots=None):
    """Share one fresh traversal only when witness entry contexts agree."""
    entries = {str(Path(witness).parent) for witness in witnesses}
    if len(entries) == 1:
        # The existing LIFO traversal must start with the first witness.
        # Its local visited set removes duplicate reads, not snapshot checks
        # on consumed bytes or verify's final source/path/resolver checks.
        return dependency_inventory(root, roots=tuple(reversed(witnesses)),
            entries=(next(iter(entries)),), _known=_known, _snapshots=_snapshots)
    found = set()
    for witness in witnesses:
        found.update(dependency_inventory(root, roots=(witness,),
            entries=(str(Path(witness).parent),), _known=_known, _snapshots=_snapshots))
    return found


def resolver_unshadowed(root, paths):
    """Refuse alternate qualified-module and namespace lookup surfaces.

    Every reviewed import begins at a protected top-level namespace. Guard
    those namespace names conservatively everywhere, including every compiled
    entry directory, repository root and supplied include root. Imported-module
    directories are not Mojo lookup roots. An unrelated leaf basename elsewhere
    cannot shadow a qualified import and is not itself a namespace competitor.
    Exact consumed module/prefix coordinates still reject case, alternate
    suffix/package and symlink changes. Only three exact regular wiki files are
    inert. Include roots receive structural checks only: maintained generation
    origins and source/staged manifests bind instrumented coverage bytes.
    """
    root = Path(root)
    if not root.is_dir() or not _root_unaliased(root):
        return False
    allowed = set(paths)
    stems = {str(Path(p).with_suffix('')).casefold() for p in allowed}
    canonical_prefixes = {str(parent) for p in allowed for parent in Path(p).parents if str(parent) != '.'}
    prefixes = {prefix.casefold() for prefix in canonical_prefixes}
    top = {Path(p).parts[0].casefold() for p in allowed} | {'std'}
    inert = {'docs/wiki/Math.md', 'docs/wiki/Units.md', 'docs/wiki/Extensions.md'}
    try:
        for folder, directories, files in os.walk(root, followlinks=False):
            relative_dir = Path(folder).relative_to(root).as_posix()
            directories[:] = [name for name in directories if name not in SKIP
                              and (Path(relative_dir) / name).as_posix() != 'coverage/build']
            for name in directories + files:
                path = Path(folder) / name
                relative = path.relative_to(root).as_posix()
                folded = relative.casefold()
                stem = str(Path(relative).with_suffix('')).casefold()
                # Namespace roots remain protected at every actual lookup root.
                scoped_name = name.split('.')[0].casefold()
                relevant = (folded in stems or folded in prefixes or stem in stems
                            or stem in prefixes or scoped_name in top
                            or (name == '__init__.mojo' and relative_dir.casefold() in prefixes))
                if not relevant:
                    continue
                if relative in inert and not path.is_symlink() and path.is_file():
                    continue
                if path.is_symlink():
                    return False
                if path.is_dir():
                    if relative not in canonical_prefixes:
                        return False
                    continue
                if relative not in allowed or not path.is_file():
                    return False
        return True
    except OSError:
        return False


def native_support_mapping(root, *, raw=None):
    if raw is None:
        raw = _regular(root, 'tools/native_test_support.py').read_bytes()
    tree = ast.parse(_physical_text(raw))
    entries = [node for node in tree.body if isinstance(node, ast.Assign)
               and any(isinstance(target, ast.Name) and target.id == 'FIXTURES' for target in node.targets)]
    require(len(entries) == 1, 'native fixture registry declaration changed')
    return {path: list(values) for path, values in ast.literal_eval(entries[0].value).items()}


def _different_alias_leaf(filename, expected_names):
    """Reject only lexical filenames that cannot match any owner alias."""
    if (os.name != 'posix' or type(filename) is not str
            or type(__file__) is not str
            or not filename.startswith('/') or not __file__.startswith('/')):
        return False
    leaf = filename.rsplit('/', 1)[-1]
    core_leaf = __file__.rsplit('/', 1)[-1]
    if leaf in ('', '.', '..') or core_leaf in ('', '.', '..'):
        return False
    return leaf not in expected_names


def _cache_verify_frame(frame, *, include_aliases=False):
    """Recognize supported owners; aliases may only block outer borrowing."""
    name = (__package__ + '.cache_key_contracts') if __package__ else 'cache_key_contracts'
    cache = sys.modules.get(name)
    if (frame is not None and cache is not None and frame.f_globals is vars(cache)
            and frame.f_code is _live_function_code(cache.verify)):
        return True
    main = sys.modules.get('__main__')
    if (frame is not None and main is not None and frame.f_globals is vars(main)
            and type(getattr(main, '__file__', None)) is str
            and Path(main.__file__).absolute() == Path(__file__).absolute().with_name('cache_key_contracts.py')
            and frame.f_code is _live_function_code(getattr(main, 'verify', None))):
        return True
    # An importlib alias can run the public fresh path without being registered
    # in sys.modules. It is still a distinct operation, never an outer borrower.
    namespace = frame.f_globals if frame is not None else {}
    if include_aliases is True and _different_alias_leaf(namespace.get('__file__'), ('cache_key_contracts.py',)):
        return False
    return (include_aliases and type(namespace.get('__file__')) is str
            and Path(namespace['__file__']).absolute() == Path(__file__).absolute().with_name('cache_key_contracts.py')
            and frame.f_code is _live_function_code(namespace.get('verify')))


def _nearest_cache_verify():
    frame = sys._getframe(1)
    while frame is not None:
        if _cache_verify_frame(frame, include_aliases=True):
            return frame
        frame = frame.f_back
    return None


class _CacheInputs:
    """One synchronous cache.verify's immutable input image, never a receipt."""

    def __init__(self, owner, root, owner_frame):
        self._owner = owner
        self._owner_frame = owner_frame
        self._stamp = id(self)
        self._thread = threading.get_ident()
        self._state = 'pending'
        self._root = str(Path(root).absolute())
        self._cwd = str(Path.cwd())
        self._include_roots = ()
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = frozenset()
        self._production = frozenset()
        self._entries = ()
        self._native_contexts = ()
        self._resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})

    def _check_context(self, root):
        try:
            require(str(Path(root).absolute()) == self._root
                    and str(Path.cwd()) == self._cwd and self._include_roots == (),
                    'cache input root or working directory changed')
        except ContractError:
            raise
        except (OSError, ValueError, TypeError) as error:
            raise ContractError('full-audit cleanup successor: unreadable cache input context') from error

    def _check_pending(self, root):
        require(type(self) is _CacheInputs and self._stamp == id(self)
                and self._state == 'pending' and not self._raw
                and self._record_raw is None and self._thread == threading.get_ident(),
                'invalid pending cache input capture')
        self._check_context(root)
        owner_frame = _nearest_cache_verify()
        require(owner_frame is self._owner_frame and owner_frame is not None
                and owner_frame.f_locals.get('_input_owner') is self._owner
                and owner_frame.f_locals.get('_inputs', False) is None,
                'cache input owner is not active')
        frame = sys._getframe(1)
        while frame is not None and not (frame.f_globals is globals()
                and frame.f_code is _live_function_code(verify)):
            frame = frame.f_back
        factory = frame.f_back if frame is not None else None
        require(factory is not None and factory.f_globals is globals()
                and factory.f_code is _live_function_code(_cache_lane_inputs)
                and factory.f_back is owner_frame
                and factory.f_locals.get('_pending') is self,
                'cache input capture was not issued by its owner')

    def _publish(self, root, snapshots, authority_raw, known, production,
                 entries, resolver_paths, executing):
        caller = sys._getframe(1)
        require(caller.f_globals is globals()
                and caller.f_code is _live_function_code(verify),
                'cache input publication requires the full gate')
        self._check_pending(root)
        require(type(authority_raw) is bytes and sha(authority_raw) == MIGRATION_SHA256,
                'invalid captured authority bytes')
        image = dict(snapshots)
        for path, raw in image.items():
            require(type(path) is str and Path(path).as_posix() == path
                    and bool(Path(path).parts) and not Path(path).is_absolute()
                    and '..' not in Path(path).parts and type(raw) is bytes,
                    'invalid captured input bytes or path')
        require(set(known) <= image.keys() and set(production) <= image.keys()
                and set(SOURCE_PATHS) <= image.keys(), 'incomplete captured input image')
        self._raw = types.MappingProxyType(image)
        self._record_raw = authority_raw
        self._known = frozenset(known)
        self._production = frozenset(production)
        self._entries = tuple(entries)
        self._native_contexts = tuple((path, (str(Path(path).parent),)) for path in NATIVE_WITNESSES)
        self._resolver_paths = frozenset(resolver_paths)
        self._executing = types.MappingProxyType(dict(executing))
        self._state = 'active'

    def _check(self, owner, root):
        require(type(self) is _CacheInputs and self._stamp == id(self)
                and self._state == 'active' and owner is self._owner
                and self._thread == threading.get_ident(),
                'inactive or foreign cache input view')
        self._check_context(root)
        frame = _nearest_cache_verify()
        require(frame is self._owner_frame and frame is not None
                and frame.f_locals.get('_input_owner') is owner
                and frame.f_locals.get('_inputs') is self,
                'cache input owner is not active')

    def raw(self, owner, root, path):
        self._check(owner, root)
        require(type(path) is str and path in self._raw,
                'unlisted cache input request')
        return self._raw[path]

    def text_default(self, owner, root, path):
        raw = self.raw(owner, root, path)
        try:
            with io.TextIOWrapper(io.BytesIO(raw), encoding=None, newline=None) as reader:
                return reader.read()
        except (OSError, UnicodeError, ValueError) as error:
            raise ContractError('full-audit cleanup successor: unreadable owned text: ' + path) from error

    def text_utf8(self, owner, root, path):
        raw = self.raw(owner, root, path)
        try:
            return raw.decode('utf-8')
        except UnicodeError as error:
            raise ContractError('full-audit cleanup successor: unreadable owned UTF-8 input: ' + path) from error

    def observe_bytes(self, owner, root, path):
        expected = self.raw(owner, root, path)
        try:
            raw = _regular(root, path).read_bytes()
            require(type(raw) is bytes and raw == expected, 'owned input changed: ' + path)
            return raw
        except ContractError:
            raise
        except (OSError, UnicodeError, ValueError, TypeError) as error:
            raise ContractError('full-audit cleanup successor: unreadable owned input: ' + path) from error

    def production_paths(self, owner, root):
        self._check(owner, root)
        return self._production

    def known_paths(self, owner, root):
        self._check(owner, root)
        return self._known

    def exact_edges(self, owner, root):
        self._check(owner, root)
        for path in SOURCE_PATHS:
            require(sha(self.raw(owner, root, path)) == AFTER_SHA256[path],
                    'unreviewed complete live endpoint: ' + path)
        self.checkpoint(owner, root)
        try:
            record = json.loads(self._record_raw, object_pairs_hook=source.unique_keys)
            return {path: {'path': path, **{field: item[field] for field in
                    ('before_sha256', 'after_sha256', 'before_token_sha256', 'after_token_sha256')}}
                    for path, item in record['sources'].items()}
        except (UnicodeError, ValueError, TypeError, KeyError, IndexError) as error:
            raise ContractError('full-audit cleanup successor: malformed captured authority') from error

    def checkpoint(self, owner, root):
        self._check(owner, root)
        try:
            for path in self._raw:
                self.observe_bytes(owner, root, path)
            require({p.as_posix() for p in _sibling('cache_key').input_paths(root)
                     if p.suffix == '.mojo'} == self._known,
                    'source path inventory changed during owned verification')
            require({path.relative_to(root).as_posix()
                     for path in guard.production_mojo_paths(Path(root))} == self._production,
                    'production path inventory changed during owned verification')
            require(resolver_unshadowed(root, self._resolver_paths)
                    and all(resolver_unshadowed(location, self._resolver_paths)
                            for location in self._include_roots),
                    'resolver surface changed during owned verification')
            raw = _regular(root, MIGRATION).read_bytes()
            require(type(raw) is bytes and raw == self._record_raw,
                    'record changed during owned verification')
            require(executing_checker_bindings() == self._executing,
                    'executing checker changed during owned verification')
        except ContractError:
            raise
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, SyntaxError) as error:
            raise ContractError('full-audit cleanup successor: malformed or unreadable owned input') from error

    def close(self, owner):
        require(type(self) is _CacheInputs and self._stamp == id(self) and owner is self._owner,
                'inactive or foreign cache input view')
        self._state = 'closed'
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = frozenset()
        self._production = frozenset()
        self._entries = ()
        self._native_contexts = ()
        self._resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._owner_frame = None

    def __copy__(self):
        raise ContractError('full-audit cleanup successor: cache input views cannot be copied')

    def __deepcopy__(self, memo):
        raise ContractError('full-audit cleanup successor: cache input views cannot be copied')

    def __reduce_ex__(self, protocol):
        raise ContractError('full-audit cleanup successor: cache input views cannot be serialized')


class _OperationCoherenceError(ContractError):
    """An observed input/context failure invalidates the enclosing operation."""


def _operation_fail(operation, error):
    if operation is None:
        raise error
    if type(operation) is _InvariantInputs:
        operation._invalidate(error)
    if isinstance(error, _OperationCoherenceError):
        raise error
    failure = _OperationCoherenceError(str(error))
    if hasattr(error, 'source_path'):
        failure.source_path = error.source_path
    raise failure from error


def _owner_module(kind):
    if kind in ('map_loops', 'rtree_loops'):
        return None
    name = {'invariant': 'coverage_invariant_contracts',
            'winner': 'winner_sign_contracts', 'border': 'border_parser_contracts'}.get(kind)
    return sys.modules.get((__package__ + '.' if __package__ else '') + name) if name else None


def _operation_frame_kind(frame, *, include_aliases=False):
    if frame is None:
        return None
    namespace = frame.f_globals
    filename = namespace.get('__file__')
    # Pure negative filter only for exact builtin absolute spellings and plain
    # functions. Relative paths, decorated/cyclic/exotic values keep full checks.
    if (type(filename) is str and filename.startswith('/')
            and type(__file__) is str and __file__.startswith('/')):
        candidates = (namespace.get('verify'), namespace.get('reviewed_nonempty_loops'))
        if all(value is None or (type(value) is types.FunctionType
                and '__wrapped__' not in value.__dict__
                and frame.f_code is not value.__code__) for value in candidates):
            return None
    for kind in ('invariant', 'winner', 'border'):
        module = _owner_module(kind)
        if (module is not None and namespace is vars(module)
                and frame.f_code is _live_function_code(getattr(module, 'verify', None))):
            return kind
    for name in ('coverage_loop_proofs', 'tools.coverage_loop_proofs'):
        module = sys.modules.get(name)
        if (module is not None and namespace is vars(module)
                and frame.f_code is _live_function_code(getattr(module, 'reviewed_nonempty_loops', None))):
            return {'extensions/carla/map': 'map_loops',
                    'extensions/carla/rtree': 'rtree_loops'}.get(frame.f_locals.get('module'), 'other_loops')
    if not include_aliases or type(filename) is not str:
        return None
    if _different_alias_leaf(filename, ('coverage_invariant_contracts.py', 'winner_sign_contracts.py',
                                         'border_parser_contracts.py', 'coverage_loop_proofs.py')):
        return None
    for kind, name in (('invariant', 'coverage_invariant_contracts.py'),
                       ('winner', 'winner_sign_contracts.py'),
                       ('border', 'border_parser_contracts.py')):
        if (Path(filename).absolute() == Path(__file__).absolute().with_name(name)
                and frame.f_code is _live_function_code(namespace.get('verify'))):
            return 'alias_' + kind
    if (Path(filename).absolute() == Path(__file__).absolute().parent.parent / 'coverage_loop_proofs.py'
            and frame.f_code is _live_function_code(namespace.get('reviewed_nonempty_loops'))):
        return 'alias_loops'
    return None


def _invariant_verify_frame(frame, *, include_aliases=False):
    kind = _operation_frame_kind(frame, include_aliases=include_aliases)
    return kind == 'invariant' or (include_aliases and kind == 'alias_invariant')


def _private_operation_wrapper(frame, kind, operation):
    """Return only the exact explicit child wrapper; never skip arbitrary frames."""
    if kind not in ('invariant', 'border') or operation._kind != 'winner':
        return None
    module = _owner_module(kind)
    if module is None or frame.f_globals is not vars(module):
        return None
    public = getattr(module, 'verify', None)
    private = getattr(module, '_verify_owned', None)
    caller = frame.f_back
    if kind == 'border':
        import contextlib
        wrapped = getattr(public, '__wrapped__', None)
        inner_code = next((value for value in contextlib.ContextDecorator.__call__.__code__.co_consts
                           if isinstance(value, types.CodeType) and value.co_name == 'inner'), None)
        if (type(public) is not types.FunctionType or type(wrapped) is not types.FunctionType
                or public.__code__ is not inner_code or public.__globals__ is not vars(contextlib)
                or caller is None or caller.f_code is not inner_code
                or caller.f_globals is not vars(contextlib)
                or caller.f_locals.get('func') is not wrapped
                or frame.f_code is not wrapped.__code__ or frame.f_globals is not wrapped.__globals__):
            return None
        manager = caller.f_locals.get('self')
        if (type(manager) is not contextlib._GeneratorContextManager
                or manager.func is not getattr(source.lexical_memo_scope, '__wrapped__', None)
                or manager.args != () or manager.kwds != {}):
            return None
        caller = caller.f_back
    if (type(private) is not types.FunctionType or caller is None
            or caller.f_globals is not vars(module) or caller.f_code is not private.__code__
            or frame.f_locals.get('_operation') is not operation
            or caller.f_locals.get('_operation') is not operation):
        return None
    for local in (frame.f_locals, caller.f_locals):
        if str(Path(local.get('root')).absolute()) != operation._root:
            return None
    return caller


def _operation_borrow(operation, root, kind):
    try:
        require(type(operation) is _InvariantInputs and kind in ('invariant', 'border'),
                'invalid explicit operation borrower')
        _operation_check(operation, root)
        module = _owner_module(kind)
        frame = sys._getframe(1)
        require(module is not None and frame.f_globals is vars(module)
                and frame.f_code is getattr(module, '_verify_owned').__code__
                and frame.f_locals.get('_operation') is operation
                and str(Path(frame.f_locals.get('root')).absolute()) == operation._root
                and operation._kind == 'winner', 'invalid private operation wrapper')
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        _operation_fail(operation, error)


def _operation_enter(root, kind, _operation=None, *, module=None, include_roots=()):
    """Enter a fresh public owner or its exact explicitly bound private child."""
    frame = sys._getframe(1)
    try:
        if kind is None or include_roots != ():
            require(_operation is None, 'unsupported context cannot borrow operation inputs')
            return None, False
        require(kind in ('invariant', 'winner', 'border', 'map_loops', 'rtree_loops'),
                'unknown bounded operation kind')
        actual = _operation_frame_kind(frame)
        if _operation is not None:
            require(type(_operation) is _InvariantInputs and actual == kind
                    and _private_operation_wrapper(frame, kind, _operation) is not None,
                    'operation argument requires its exact private wrapper')
            _operation_check(_operation, root)
            return _operation, False
        if actual != kind:
            return None, False
        if kind in ('map_loops', 'rtree_loops'):
            expected = 'extensions/carla/map' if kind == 'map_loops' else 'extensions/carla/rtree'
            require(module == expected and frame.f_locals.get('module') == expected
                    and frame.f_locals.get('include_roots') == (),
                    'loop input owner context differs from its public invocation')
        return _InvariantInputs(root, frame, kind), True
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        if (_operation is None and kind in ('map_loops', 'rtree_loops')
                and _operation_frame_kind(frame) == kind):
            raise _OperationCoherenceError(str(error)) from error
        _operation_fail(_operation, error)


def _invariant_operation(root):
    """Compatibility entry for the previously reviewed invariant-only owner."""
    frame = sys._getframe(1)
    if not _invariant_verify_frame(frame):
        return None
    return _InvariantInputs(root, frame, 'invariant')


def _operation_text(raw, mode):
    require(type(raw) is bytes, 'operation input is not builtin bytes')
    if mode == 'utf8':
        return raw.decode('utf-8')
    require(mode in ('default', 'physical', 'supplied_default', 'supplied_physical'),
            'unknown operation text mode')
    encoding = None if mode in ('default', 'supplied_default') else 'utf-8'
    with io.TextIOWrapper(io.BytesIO(raw), encoding=encoding, newline=None) as reader:
        return reader.read()


def _operation_check(operation, root):
    try:
        if operation is not None:
            require(type(operation) is _InvariantInputs, 'invalid operation input owner')
            operation._check_owner(root)
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(operation, error)


def _operation_production_paths(root, discovered, *, _operation=None):
    if _operation is None:
        return discovered
    _operation_check(_operation, root)

    def checked_paths():
        try:
            paths = set()
            for path in discovered:
                _operation_check(_operation, root)
                paths.add(Path(path).relative_to(root).as_posix())
                yield path
            _operation._discovery(root, frozenset(paths), 'production')
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(_operation, error)

    return checked_paths()


def _operation_known_paths(root, discovered, *, _operation=None):
    try:
        if _operation is not None:
            _operation_check(_operation, root)
            _operation._discovery(root, frozenset(discovered), 'known')
        return discovered
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


def _operation_observe(operation, root, path, value, mode):
    """Check an original-callsite observation; this function performs no read."""
    try:
        if operation is None:
            return value
        require(type(operation) is _InvariantInputs, 'invalid operation input owner')
        operation._observe(root, str(path), value, mode)
        return value
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(operation, error)


def _operation_record(operation, root, *, exact=False, include_roots=(), expected_lane_raw=None):
    try:
        require(type(operation) is _InvariantInputs and include_roots == (),
                'invalid private operation projection')
        return operation._admit(root, exact=exact, expected_lane_raw=expected_lane_raw)
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(operation, error)


def _observe_bytes(root, path, value, *, _operation=None):
    return _operation_observe(_operation, root, path, value, 'bytes')


def _observe_text(root, path, value, *, _operation=None, mode='default',
                  supplied=False, _checked_raw=None):
    try:
        if _operation is None:
            return value
        require(type(supplied) is bool and mode in ('default', 'physical', 'utf8'),
                'invalid operation text observation mode')
        if _checked_raw is not None:
            require(type(value) is str, 'operation text is not builtin str: ' + str(path))
            checked = _operation_text(_checked_raw, mode)
            require((source.token_sha256(value) == source.token_sha256(checked))
                    if supplied else value == checked,
                    'checked physical and supplied views differ: ' + str(path))
            _operation_observe(_operation, root, path, _checked_raw, 'bytes')
        actual_mode = 'supplied_' + mode if supplied else mode
        return _operation_observe(_operation, root, path, value, actual_mode)
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


class _InvariantInputs(_CacheInputs):
    """One explicit bounded invocation; source data, never a transferable PASS."""

    def __init__(self, root, owner_frame, kind):
        caller = sys._getframe(1)
        require(caller.f_globals is globals()
                and caller.f_code in (_live_function_code(_invariant_operation), _live_function_code(_operation_enter))
                and caller.f_back is owner_frame and _operation_frame_kind(owner_frame) == kind,
                'bounded inputs require their direct owner factory')
        super().__init__(object(), root, owner_frame)
        self._kind = kind
        self._failed = False
        self._failure_reason = None
        self._observations = []
        self._discoveries = []
        self._capturing = False

    def _invalidate(self, error):
        self._failed = True
        self._failure_reason = str(error)
        self._state = 'invalid'
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = frozenset()
        self._production = frozenset()
        self._entries = ()
        self._native_contexts = ()
        self._resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._observations = []
        self._discoveries = []

    def _check_owner(self, root):
        try:
            if self._failed:
                raise _OperationCoherenceError(self._failure_reason or 'invalid operation inputs')
            require(type(self) is _InvariantInputs and self._stamp == id(self)
                    and self._state in ('pending', 'active')
                    and self._thread == threading.get_ident(), 'inactive bounded input owner')
            self._check_context(root)
            frame = sys._getframe(1)
            while frame is not None:
                kind = _operation_frame_kind(frame, include_aliases=True)
                if kind is not None:
                    if frame is self._owner_frame:
                        require(kind == self._kind and frame.f_locals.get('_operation') is self,
                                'operation owner binding changed')
                        return
                    wrapper = _private_operation_wrapper(frame, kind, self)
                    require(wrapper is not None, 'nearer independent operation blocks borrowing')
                    frame = wrapper.f_back
                else:
                    frame = frame.f_back
            require(False, 'operation owner is no longer active')
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def _check(self, owner, root):
        self._check_owner(root)
        require(owner is self._owner and self._state == 'active',
                'inactive or foreign invariant input view')

    def _check_pending(self, root):
        self._check_owner(root)
        require(self._state == 'pending' and self._capturing and not self._raw
                and self._record_raw is None, 'invalid pending invariant capture')
        frame = sys._getframe(1)
        while frame is not None and not (frame.f_globals is globals()
                and frame.f_code is _live_function_code(verify)):
            frame = frame.f_back
        factory = frame.f_back if frame is not None else None
        require(factory is not None and factory.f_globals is globals()
                and factory.f_code is _InvariantInputs._admit.__code__
                and factory.f_locals.get('self') is self,
                'invariant capture was not issued by its explicit owner')

    def _publish(self, root, snapshots, authority_raw, known, production,
                 entries, resolver_paths, executing):
        caller = sys._getframe(1)
        require(caller.f_globals is globals()
                and caller.f_code is _live_function_code(verify),
                'invariant publication requires the full gate')
        # The base publication also checks its direct caller. Keep this exact
        # publication body local rather than weakening the existing cache path.
        self._check_pending(root)
        require(type(authority_raw) is bytes and sha(authority_raw) == MIGRATION_SHA256,
                'invalid captured authority bytes')
        image = dict(snapshots)
        for path, raw in image.items():
            require(type(path) is str and Path(path).as_posix() == path
                    and bool(Path(path).parts) and not Path(path).is_absolute()
                    and '..' not in Path(path).parts and type(raw) is bytes,
                    'invalid captured input bytes or path')
        require(set(known) <= image.keys() and set(production) <= image.keys()
                and set(SOURCE_PATHS) <= image.keys(), 'incomplete captured input image')
        self._raw = types.MappingProxyType(image)
        self._record_raw = authority_raw
        self._known = frozenset(known)
        self._production = frozenset(production)
        self._entries = tuple(entries)
        self._native_contexts = tuple((path, (str(Path(path).parent),)) for path in NATIVE_WITNESSES)
        self._resolver_paths = frozenset(resolver_paths)
        self._executing = types.MappingProxyType(dict(executing))
        self._state = 'active'
        for path, value, mode in self._observations:
            self._match(root, path, value, mode)
        self._observations.clear()
        for paths, kind in self._discoveries:
            self._discovery(root, paths, kind)
        self._discoveries.clear()

    def _discovery(self, root, paths, kind):
        try:
            self._check_owner(root)
            require(kind in ('production', 'known'), 'unknown operation discovery kind')
            require(all(type(path) is str for path in paths), 'invalid operation discovered path')
            if self._state == 'pending':
                self._discoveries.append((frozenset(paths), kind))
            else:
                expected = self._production if kind == 'production' else self._known
                require(paths == expected, 'consumed operation path census changed: ' + kind)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def _match(self, root, path, value, mode):
        require(path in self._raw or path == MIGRATION,
                'unlisted operation input: ' + path)
        _regular(root, path)
        raw = self._record_raw if path == MIGRATION else self._raw[path]
        if mode == 'bytes':
            require(type(value) is bytes and value == raw,
                    'consumed operation bytes changed: ' + path)
        else:
            text = _operation_text(raw, mode)
            require(type(value) is str, 'operation text is not builtin str: ' + path)
            if mode.startswith('supplied_'):
                require(source.token_sha256(value) == source.token_sha256(text),
                        'supplied and captured source views differ: ' + path)
            else:
                require(value == text, 'consumed operation text changed: ' + path)

    def _observe(self, root, path, value, mode):
        try:
            self._check_owner(root)
            require(type(path) is str and path and Path(path).as_posix() == path
                    and not Path(path).is_absolute() and '..' not in Path(path).parts,
                    'invalid operation observation path')
            require(mode in ('bytes', 'default', 'physical', 'utf8',
                             'supplied_default', 'supplied_physical'),
                    'unknown operation observation mode')
            require(type(value) is (bytes if mode == 'bytes' else str),
                    'non-builtin operation observation')
            if self._state == 'pending':
                # Historical operations retain their existing physical path policy.
                # Actual current acquisition must reconcile every prior value.
                self._observations.append((path, value, mode))
            else:
                self._match(root, path, value, mode)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def _admit(self, root, *, exact=False, expected_lane_raw=None):
        try:
            self._check_owner(root)
            require(type(exact) is bool, 'invalid operation exactness request')
            if expected_lane_raw is not None:
                self._observe(root, SOURCE_PATHS[2], expected_lane_raw, 'bytes')
            if self._state == 'pending':
                self._capturing = True
                try:
                    verify(root, _expected_lane_raw=expected_lane_raw, _capture=self)
                except BaseException:
                    self.close()
                    raise
                finally:
                    self._capturing = False
            self._check(self._owner, root)
            if exact:
                for path in SOURCE_PATHS:
                    require(sha(self.raw(self._owner, root, path)) == AFTER_SHA256[path],
                            'unreviewed exact operation endpoint: ' + path)
            return json.loads(self._record_raw, object_pairs_hook=source.unique_keys)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def checkpoint(self, owner, root):
        # Private demand points keep lifetime checks; the whole-image sweep is
        # owned once by finish(), before the outer public result can escape.
        self._check(owner, root)

    def finish(self, root):
        try:
            self._check_owner(root)
            try:
                if self._state == 'active':
                    _CacheInputs.checkpoint(self, self._owner, root)
            except BaseException:
                self.close()
                raise
            self._state = 'finished'
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def close(self):
        require(type(self) is _InvariantInputs and self._stamp == id(self),
                'invalid invariant input disposal')
        self._state = 'closed'
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = frozenset()
        self._production = frozenset()
        self._entries = ()
        self._native_contexts = ()
        self._resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._observations.clear()
        self._discoveries.clear()
        self._owner_frame = None
        self._capturing = False


class _BorrowedCacheInputs(_CacheInputs):
    """A cache.verify lease over its explicitly supplied operation image."""

    def __init__(self, owner, root, owner_frame, operation):
        caller = sys._getframe(1)
        require(caller.f_globals is globals()
                and caller.f_code is _live_function_code(_cache_lane_inputs)
                and caller.f_back is owner_frame and _cache_verify_frame(owner_frame),
                'borrowed cache inputs require the direct cache factory')
        require(type(operation) is _InvariantInputs, 'invalid borrowed operation inputs')
        operation._check(operation._owner, root)
        super().__init__(owner, root, owner_frame)
        self._operation = operation
        self._raw = operation._raw
        self._record_raw = operation._record_raw
        self._known = operation._known
        self._production = operation._production
        self._entries = operation._entries
        self._native_contexts = operation._native_contexts
        self._resolver_paths = operation._resolver_paths
        self._executing = operation._executing
        self._state = 'active'

    def _check(self, owner, root):
        try:
            require(type(self) is _BorrowedCacheInputs and self._stamp == id(self)
                    and self._state == 'active' and owner is self._owner
                    and self._thread == threading.get_ident(), 'inactive or foreign cache lease')
            self._check_context(root)
            self._operation._check(self._operation._owner, root)
            frame = _nearest_cache_verify()
            require(frame is self._owner_frame and frame is not None
                    and frame.f_locals.get('_input_owner') is owner
                    and frame.f_locals.get('_inputs') is self
                    and frame.f_locals.get('_operation') is self._operation,
                    'borrowed cache owner is not active')
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self._operation, error)

    def raw(self, owner, root, path):
        try:
            return _CacheInputs.raw(self, owner, root, path)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self._operation, error)

    def text_default(self, owner, root, path):
        try:
            return _CacheInputs.text_default(self, owner, root, path)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self._operation, error)

    def text_utf8(self, owner, root, path):
        try:
            return _CacheInputs.text_utf8(self, owner, root, path)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self._operation, error)

    def observe_bytes(self, owner, root, path):
        try:
            return _CacheInputs.observe_bytes(self, owner, root, path)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self._operation, error)

    def exact_edges(self, owner, root):
        try:
            return _CacheInputs.exact_edges(self, owner, root)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self._operation, error)

    def checkpoint(self, owner, root):
        self._check(owner, root)

    def close(self, owner):
        require(type(self) is _BorrowedCacheInputs and self._stamp == id(self)
                and owner is self._owner, 'invalid cache lease disposal')
        self._state = 'closed'
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = frozenset()
        self._production = frozenset()
        self._entries = ()
        self._native_contexts = ()
        self._resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._operation = None
        self._owner_frame = None


def _cache_lane_inputs(root, supplied_text, owner, *, _operation=None):
    """Acquire only for the direct current cache.verify frame; no ambient view."""
    owner_frame = sys._getframe(1)
    require(_cache_verify_frame(owner_frame)
            and owner_frame.f_locals.get('_input_owner') is owner
            and owner_frame.f_locals.get('_inputs', False) is None,
            'cache input factory requires its cache.verify owner')
    path = SOURCE_PATHS[2]
    _pending = None
    try:
        digest = source.token_sha256(supplied_text)
        if digest == BEFORE_TOKEN_SHA256[path]:
            return supplied_text, None
        require(digest == AFTER_TOKEN_SHA256[path],
                'unreviewed supplied successor source: ' + path)
        raw = _regular(root, path).read_bytes()
        require(type(raw) is bytes, 'expected lane observation is not bytes')
        require(digest == source.token_sha256(_physical_text(raw)),
                'supplied and physical lane observation views differ')
        if _operation is None:
            _pending = _CacheInputs(owner, root, owner_frame)
            record = verify(root, _expected_lane_raw=raw, _capture=_pending)
        else:
            require(type(_operation) is _InvariantInputs, 'invalid borrowed cache operation')
            _operation_observe(_operation, root, path, supplied_text, 'supplied_default')
            record = _operation._admit(root, expected_lane_raw=raw)
            _pending = _BorrowedCacheInputs(owner, root, owner_frame, _operation)
        item = record['sources'][path]
        predecessor = reverse_exact(path, item['after_source'], item)
        return predecessor, _pending
    except BaseException as error:
        if _pending is not None:
            _pending.close(owner)
        if _operation is not None and isinstance(error, (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError)):
            _operation_fail(_operation, error)
        if isinstance(error, ContractError):
            raise
        if isinstance(error, (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, SyntaxError)):
            raise ContractError('full-audit cleanup successor: malformed or unreadable cache lane input') from error
        raise


def verify(root, *, exact=False, include_roots=(), _expected_lane_raw=None, _capture=None):
    """Check actual complete current endpoints and all premises without caches."""
    root = Path(root)
    try:
        if _capture is not None:
            require(type(_capture) in (_CacheInputs, _InvariantInputs) and not exact and include_roots == (),
                    'invalid cache input capture request')
            _capture._check_pending(root)
        executing = executing_checker_bindings()
        record = read_record(root)
        require(record['qualification_ready'] is True and not record['unresolved_inputs'],
                'new recovery authority still has unresolved reviewed inputs')
        verify_chord_refusal_order(record['sources'][SOURCE_PATHS[2]])
        snapshots = {p: _regular(root, p).read_bytes() for p in SOURCE_PATHS}
        if _expected_lane_raw is not None:
            require(type(_expected_lane_raw) is bytes, 'expected lane observation is not bytes')
            require(snapshots[SOURCE_PATHS[2]] == _expected_lane_raw,
                    'lane observation changed before current admission')
        for path, raw in snapshots.items():
            text = _physical_text(raw)
            supplied_view = (root / path).read_text(encoding='utf-8')
            require(source.token_sha256(supplied_view) == source.token_sha256(text),
                    'supplied and physical source views differ: ' + path)
            item = record['sources'][path]
            require((not exact or sha(raw) == AFTER_SHA256[path])
                    and source.token_sha256(_physical_text(raw)) == item['after_token_sha256']
                    and source.token_sha256(text) == item['after_token_sha256'],
                    'unreviewed complete live endpoint: ' + path)
            if path == SOURCE_PATHS[2]:
                descriptor = item['center_extraction']
                verify_center_correspondence(descriptor['intermediate_source'], text, descriptor)
            verify_observations(path, text, item)
            # Fixed exact inverse objects are not a normalization API. Only
            # sealed recorded endpoints may be inverted, after live checks.
            reverse_exact(path, item['after_source'], item)
        resolver_paths = (set(record['dependency_inventory']) | set(record['inventory'])
                          | set(record['native_dependency_inventory']))
        require(resolver_unshadowed(root, resolver_paths)
                and all(resolver_unshadowed(location, resolver_paths)
                        for location in include_roots),
                'unreviewed alternate, compiled, package, symlink or std resolver surface')
        known = {p.as_posix() for p in _sibling('cache_key').input_paths(root) if p.suffix == '.mojo'}
        # #720 resolves from actual compiled entrypoint directories. Bind all
        # maintained production entry contexts and each witness's own root.
        live_sources = {}
        for path in sorted(known):
            raw = _regular(root, path).read_bytes()
            previous = snapshots.setdefault(path, raw)
            require(previous == raw, 'source changed before entrypoint census: ' + path)
            live_sources[path] = _physical_text(raw)
        entries = _sibling('affected').entry_directories(live_sources)
        require(entries == record['entry_directories'], 'maintained entrypoint directories changed')
        require(dependency_inventory(root, roots=(*SOURCE_PATHS, *record['inventory']), entries=entries,
                                     _known=known, _snapshots=snapshots)
                == set(record['dependency_inventory']), 'production import inventory changed')
        native_found = _native_dependency_inventory(root, witnesses=NATIVE_WITNESSES,
            _known=known, _snapshots=snapshots)
        require(native_found == set(record['native_dependency_inventory']), 'native witness import inventory changed')
        bound = {}
        for group in BOUND_GROUPS:
            for path, expected in record[group].items():
                raw = _regular(root, path).read_bytes()
                previous = snapshots.setdefault(path, raw)
                require(previous == raw, 'bound input changed after consumption: ' + path)
                require(sha(raw) == expected, 'unchanged premise, record or fixture changed: ' + path)
                bound[path] = raw
        require(native_support_mapping(root, raw=bound['tools/native_test_support.py']) == record['native_support_mapping'], 'native fixture mapping changed')
        production = set() if _capture is not None else None
        observed_inventory = (inventory(root, _snapshots=snapshots) if _capture is None else
                              inventory(root, _snapshots=snapshots, _production=production))
        require(observed_inventory == record['inventory'], 'production caller/use inventory changed')
        for path, raw in {**bound, **snapshots}.items():
            require(_regular(root, path).read_bytes() == raw, 'input changed during verification: ' + path)
        require({p.as_posix() for p in _sibling('cache_key').input_paths(root) if p.suffix == '.mojo'} == known,
                'source path inventory changed during verification')
        require(resolver_unshadowed(root, resolver_paths)
                and all(resolver_unshadowed(location, resolver_paths) for location in include_roots),
                'resolver surface changed during verification')
        if _capture is not None:
            _regular(root, MIGRATION)
        authority_raw = (root / MIGRATION).read_bytes()
        require(sha(authority_raw) == MIGRATION_SHA256, 'record changed during verification')
        require(executing_checker_bindings() == executing, 'executing checker changed during verification')
        if _capture is not None:
            _capture._publish(root, snapshots, authority_raw, known, production, entries,
                              resolver_paths, executing)
        return record
    except ContractError:
        raise
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, SyntaxError) as error:
        raise ContractError('full-audit cleanup successor: malformed or unreadable live input') from error


def predecessor_source(root, path, *, _operation=None):
    require(path in SOURCE_PATHS, 'unlisted predecessor source request')
    record = (verify(root) if _operation is None else
              _operation_record(_operation, root))
    item = record['sources'][path]
    return reverse_exact(path, item['after_source'], item)


def reviewed_text(root, path, text=None, *, _operation=None):
    """Keep historical views unchanged without granting current-root admission.

    Historical composed fixtures still face their original consumer checks.
    Only a successor projection requires and grants complete live admission.
    """
    path = str(path)
    if text is None:
        text = _regular(root, path).read_text(encoding='utf-8')
    if path not in SOURCE_PATHS or source.token_sha256(text) == BEFORE_TOKEN_SHA256[path]:
        return text
    require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unreviewed supplied successor source: ' + path)
    if _operation is not None:
        _observe_text(root, path, text, _operation=_operation, mode='physical', supplied=True)
    return predecessor_source(root, path, _operation=_operation)


def _reviewed_lane_observation(root, text, expected_raw, *, _operation=None):
    """Project one physical lane observation and bind its intervening road read."""
    path = SOURCE_PATHS[2]
    try:
        require(type(expected_raw) is bytes, 'expected lane observation is not bytes')
        digest = source.token_sha256(text)
        require(digest == source.token_sha256(_physical_text(expected_raw)),
                'supplied and physical lane observation views differ')
        if digest == BEFORE_TOKEN_SHA256[path]:
            return text, None
        require(digest == AFTER_TOKEN_SHA256[path],
                'unreviewed supplied successor source: ' + path)
        road = 'extensions/carla/road.mojo'
        road_raw = _regular(root, road).read_bytes()
        require(type(road_raw) is bytes, 'road observation is not bytes')
        _observe_bytes(root, road, road_raw, _operation=_operation)
        _observe_text(root, path, text, _operation=_operation, mode='physical', supplied=True)
        record = (verify(root, _expected_lane_raw=expected_raw) if _operation is None else
                  _operation_record(_operation, root, expected_lane_raw=expected_raw))
        require(sha(road_raw) == record['unchanged_inputs'][road],
                'road observation changed before current admission')
        item = record['sources'][path]
        return reverse_exact(path, item['after_source'], item), road_raw
    except ContractError:
        raise
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, SyntaxError) as error:
        raise ContractError('full-audit cleanup successor: malformed or unreadable lane/road observation') from error


def reviewed_sources(root, texts):
    """Project one supplied operation; historical pass-through grants no admission."""
    changed = {p for p, text in texts.items() if p in SOURCE_PATHS
               and source.token_sha256(text) != BEFORE_TOKEN_SHA256[p]}
    if not changed:
        return dict(texts)
    record = verify(root)
    result = dict(texts)
    # A successor operation may not mix a historical supplied endpoint with
    # current ones, or smuggle an unrelated fabricated supplied source view.
    for path, text in texts.items():
        if path in SOURCE_PATHS:
            item = record['sources'][path]
            require(source.token_sha256(text) == item['after_token_sha256'],
                    'mixed or unreviewed supplied successor source: ' + path)
            result[path] = reverse_exact(path, item['after_source'], item)
        else:
            raw = _regular(root, path).read_bytes()
            require(source.token_sha256(text) == source.token_sha256(_physical_text(raw)),
                    'unreviewed unrelated supplied source: ' + path)
    return result


def reviewed_sum2_callers(root, *, _operation=None):
    """Fixed CALLERS-only discriminator; current callers require the full gate.

    Historical callers do not acquire cleanup authority from an unrelated
    noncaller variation. Existing Sum2 routing/dependency checks still run.
    """
    for path, functions in SUM2_CALLER_SHA256.items():
        try:
            physical = _regular(root, path)
            raw = _observe_bytes(root, path, physical.read_bytes(), _operation=_operation)
            text = _physical_text(raw)
            supplied = _observe_text(root, path, physical.read_text(encoding='utf-8'),
                                    _operation=_operation, mode='physical', supplied=True, _checked_raw=raw)
            require(source.token_sha256(supplied) == source.token_sha256(text),
                    'Sum2 caller supplied and physical views differ: ' + path)
            changed = any(declaration_sha256(text, name) not in expected
                          for name, expected in functions.items())
            if changed:
                require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path],
                        'unrecognized complete Sum2 caller source: ' + path)
        except ContractError as error:
            error.source_path = path
            if _operation is not None:
                _operation_fail(_operation, error)
            raise
        except (OSError, UnicodeError, ValueError, TypeError) as error:
            wrapped = ContractError('full-audit cleanup successor: unreadable Sum2 caller: ' + path)
            wrapped.source_path = path
            if _operation is not None:
                _operation_fail(_operation, wrapped)
            raise wrapped from error
        if changed:
            # A later dependency failure is deliberately not attributed to
            # this direct caller by the discriminator's error wrapper.
            record = (verify(root) if _operation is None else _operation_record(_operation, root))
            return {p: reverse_exact(p, item['after_source'], item)
                    for p, item in record['sources'].items()}
    return {}


def reviewed_lane_before_center_text(root, text=None):
    path = SOURCE_PATHS[2]
    if text is not None:
        require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unreviewed supplied center source')
    item = verify(root)['sources'][path]
    return reverse_center_exact(item['after_source'], item)


def verified_edges(root, *, include_roots=(), _operation=None):
    record = (verify(root, exact=True, include_roots=include_roots) if _operation is None else
              _operation_record(_operation, root, exact=True, include_roots=include_roots))
    return {path: {'path': path, **{field: item[field] for field in
            ('before_sha256', 'after_sha256', 'before_token_sha256', 'after_token_sha256')}}
            for path, item in record['sources'].items()}


def digest_edges(root, *, include_roots=()):
    return verified_edges(root, include_roots=include_roots)


def extends_digest(root, path, before, after, *, include_roots=()):
    if path not in SOURCE_PATHS or before != BEFORE_SHA256[path] or after != AFTER_SHA256.get(path):
        return False
    edge = verified_edges(root, include_roots=include_roots)[path]
    return edge['before_sha256'] == before and edge['after_sha256'] == after


def proof_bindings(root, *, include_roots=(), _operation=None):
    try:
        executing = executing_checker_bindings(root)
        record = (verify(root, exact=True, include_roots=include_roots) if _operation is None else
                  _operation_record(_operation, root, exact=True, include_roots=include_roots))
        require(executing_checker_bindings(root) == executing, 'receipt checker changed during verification')
        result = {MIGRATION: MIGRATION_SHA256, **executing}
        result.update({path: item['after_sha256'] for path, item in record['sources'].items()})
        for group in BOUND_GROUPS:
            result.update(record[group])
        return result
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--exact', action='store_true')
    parser.add_argument('--include-root', action='append', type=Path, default=[])
    arguments = parser.parse_args()
    verify(arguments.root, exact=arguments.exact, include_roots=arguments.include_root)
    print('Full-audit cleanup source authority: PASS (native qualification is separate)')
