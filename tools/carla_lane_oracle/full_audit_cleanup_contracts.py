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
import pathlib
from pathlib import Path, PosixPath
import stat
import struct
import sys
import threading
import tokenize


# Only the genuine original builtin can use the two-candidate expansion.
# An injected callable retains the original generator and short-circuit protocol.
_BUILTIN_ALL = (all if type(all) is types.BuiltinFunctionType
                and all.__name__ == 'all' and all.__module__ == 'builtins' else None)


class ContractError(ValueError, RuntimeError):
    """A missing or changed premise prevents source admission."""


def require(ok, message):
    if not ok:
        raise ContractError('full-audit cleanup successor: ' + message)


try:
    if __package__:
        from . import source_contracts as source
        from . import sum2_guard_contracts as guard
        from . import consumer_successor_ledger as consumer_ledger
        from . import map_station_contracts as station
        from . import map_deviation_contracts as deviation
        from . import runtime_view_contracts as runtime_view
        from . import shared_helper_contracts as shared_helpers
        from . import witness_format_contracts as witness_format
        from . import scaled_float32_contracts as scaled_float32
        from . import typed_boundary_contracts as typed_boundary
        from . import conditioned_cubic_contracts as conditioned_cubic
    else:
        import source_contracts as source
        import sum2_guard_contracts as guard
        import consumer_successor_ledger as consumer_ledger
        import map_station_contracts as station
        import map_deviation_contracts as deviation
        import runtime_view_contracts as runtime_view
        import shared_helper_contracts as shared_helpers
        import witness_format_contracts as witness_format
        import scaled_float32_contracts as scaled_float32
        import typed_boundary_contracts as typed_boundary
        import conditioned_cubic_contracts as conditioned_cubic
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
DEPENDENCY_TOOL_SHA256 = {'tools/carla_lane_oracle/scaled_float32_contracts.py': 'e3a59a9f8d5a9394007c03fab6ac696e04998812dad5843a22e721bfbe57c2a1',
 'tools/affected.py': 'a56194a3e722ad341a42f3defec282b8154f5e4db8340df855f0199ea9830ebb',
 'tools/cache_key.py': 'ec06247feb8fe079c30b6da19fc655ffec363f1ce8e3372d063bf728e8c804c4',
 'tools/carla_lane_oracle/conditioned_cubic_contracts.py': 'df99ea0826d5efa936c56e4ece9aa79b41806b60e52121c4f564a8de5d5b0198',
 'tools/carla_lane_oracle/consumer_successor_ledger.py': 'ce9a639084dfcc1442c6ac7535060cf5a123c2eb96683d2f35816ec26b0599ed',
 'tools/carla_lane_oracle/map_deviation_contracts.py': '741a95b3fd3d0d51253dfef36327997c19ac90b9230a73942dd4697dcefffd39',
 'tools/carla_lane_oracle/map_station_contracts.py': 'caca22f46767ced3037d839a7941cb73a8ccf816238ad2037e28715f060055b7',
 'tools/carla_lane_oracle/runtime_view_contracts.py': '67316129402fac643be3c6e49ceef94bcb25c1ef92f81fd764a6abb583f89e34',
 'tools/carla_lane_oracle/shared_helper_contracts.py': '70b070d0bd5117b146a71470a46cb7a02c7fc31dfac1a5236eed50faf75b468e',
 'tools/carla_lane_oracle/source_contracts.py': '83fdd35b61f0dc7739160c113ae6b4558ad07d45ffded22b7062bc9a209032d0',
 'tools/carla_lane_oracle/sum2_guard_contracts.py': 'acbf385486e2b0dfe15a409d039cd31c8e9fed295704bc6adcb4289818b65f63',
 'tools/carla_lane_oracle/typed_boundary_contracts.py': '59cc73b325af897981a2d7299cf2d4ed3c61d3ea64d5f958f2b85aef51666362',
 'tools/carla_lane_oracle/witness_format_contracts.py': 'a76ba6d5bf18be80c151fd03ea7a7ebeb75af1c1ed8af1600037d5f75ac13cb3',
 'tools/carla_lane_oracle/cache_key_contracts.py': '87233ebca3701e3a79b57b324afd48fcffb38b87cb3988859b6ae36bd63d919f',
 'tools/carla_lane_oracle/rounded_line_selector_contracts.py': 'e47ff613bc198bc5cb629940fc0bcbe3c9517a153cd8e799e65ff0215f7b12bb',
 'tools/carla_lane_oracle/seed_count_contracts.py': 'ff4a330326fd69bc649e6f235d1f05db4ed40e6b76b1d75e66a4474741c16345'}
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
           '_chord_station_delta',
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

# A new authority is supplemental; historical successor records stay immutable.
CONSUMER_LEDGER = 'tools/carla_lane_oracle/consumer-successor-ledger.json'
CONSUMER_LEDGER_SHA256 = 'cd966262e04f6017317603e2dd4651c26da58030b780506cb189ce5d1c2ae2be'

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
                 'tools/affected.py', 'tools/cache_key.py',
                 'tools/carla_lane_oracle/consumer_successor_ledger.py',
                 'tools/carla_lane_oracle/map_station_contracts.py',
                 'tools/carla_lane_oracle/shared_helper_contracts.py',
                 'tools/carla_lane_oracle/runtime_view_contracts.py',
                 'tools/carla_lane_oracle/map_deviation_contracts.py',
                 'tools/carla_lane_oracle/witness_format_contracts.py',
                 'tools/carla_lane_oracle/typed_boundary_contracts.py',
                 'tools/carla_lane_oracle/conditioned_cubic_contracts.py',
                 'tools/carla_lane_oracle/scaled_float32_contracts.py')


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
    if type(value) is slice:
        # Python 3.14 folds constant slices such as `x[:2]` into co_consts.
        return ('slice', _code_constant(value.start), _code_constant(value.stop),
                _code_constant(value.step))
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
for _module in (source, guard, _sibling('affected'), _sibling('cache_key'), consumer_ledger, station, shared_helpers, runtime_view, deviation, witness_format, typed_boundary, conditioned_cubic, scaled_float32):
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


# Public scopes can be entered by a consumer imported later (or by an importlib
# alias). Bind its reviewed code now, without importing it through a cycle.
for _relative, _digest in DEPENDENCY_TOOL_SHA256.items():
    _path = Path(__file__).resolve().parents[2] / _relative
    _key = str(_path.resolve())
    if _key not in _IMPORT_IDENTITIES:
        _raw = _path.read_bytes()
        require(not _path.is_symlink() and sha(_raw) == _digest,
                'unreviewed public consumer checker bytes: ' + _relative)
        _IMPORT_IDENTITIES[_key] = _digest
        _IMPORT_CODE[_key] = _compiled_functions(_raw, str(_path))
        _IMPORT_DEFAULTS[_key] = _compiled_defaults(_raw)


def _live_function_code(value):
    seen = set()
    while hasattr(value, '__wrapped__'):
        require(id(value) not in seen, 'cyclic executing function wrapper')
        seen.add(id(value))
        value = value.__wrapped__
    return getattr(value, '__code__', None)


_LIVE_FUNCTION_CODE = _live_function_code
_LIVE_FUNCTION_CODE_CODE = _live_function_code.__code__


def executing_checker_bindings(root=None):
    base = Path(__file__).resolve().parents[2]
    modules = (globals(), vars(source), vars(guard), vars(_sibling('affected')),
               vars(_sibling('cache_key')), vars(consumer_ledger), vars(station), vars(shared_helpers), vars(runtime_view),
               vars(deviation), vars(witness_format), vars(typed_boundary), vars(conditioned_cubic),
               vars(scaled_float32))
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
            supplied = _regular(root, relative)
            require(sha(supplied.read_bytes()) == captured,
                    'receipt checker differs from executing checker: ' + relative)
        result[relative] = captured
    typed_boundary.verify_authority()
    conditioned_cubic.verify_authority()
    return result


def _root_unaliased(root):
    absolute = Path(root).absolute()
    return all(not path.is_symlink() for path in (absolute, *absolute.parents))


def _canonical_relative_text(text):
    """Recognize only builtin canonical POSIX relative spellings."""
    return (type(text) is str and bool(text) and text not in ('.', '..')
            and not text.startswith(('/', './', '../'))
            and not text.endswith(('/', '/.', '/..'))
            and '//' not in text and '/./' not in text and '/../' not in text)


def _regular(root, relative):
    if os.name == 'posix' and Path is pathlib.Path and _canonical_relative_text(relative):
        parts = tuple(relative.split('/'))
        require(parts and not relative.startswith('/') and '..' not in parts, 'unsafe input path')
    else:
        parts = Path(relative).parts
        require(parts and not Path(relative).is_absolute() and '..' not in parts, 'unsafe input path')
    path = Path(root)
    require(_root_unaliased(path), 'symbolic root or ancestor')
    for part in parts:
        path = path / part
        require(not path.is_symlink(), 'symlink input: ' + relative)
    require(stat.S_ISREG(path.stat().st_mode), 'input is not a regular file: ' + relative)
    return path


def _relative_path(path, root):
    """Accelerate ordinary POSIX lexical prefixes; defer uncertain layouts."""
    if (os.name == 'posix' and type(root) is PosixPath
            and type(path) is PosixPath):
        # Path can retain lazy str-subclass payloads. Inspect only builtin
        # storage before parsing; unsupported pathlib layouts use the fallback.
        root_raw = getattr(root, '_raw_paths', None)
        path_raw = getattr(path, '_raw_paths', None)
        if (type(root_raw) is list and type(path_raw) is list
                and all(type(part) is str for part in root_raw)
                and all(type(part) is str for part in path_raw)):
            root_parts = root.parts
            path_parts = path.parts
            if (root_parts and path_parts
                    and root_parts[0] == path_parts[0] == '/'
                    and '..' not in root_parts and '..' not in path_parts
                    and path_parts[:len(root_parts)] == root_parts):
                return PosixPath(*path_parts[len(root_parts):])
    return path.relative_to(root)


def inventory(root, *, _snapshots=None, _production=None):
    """Fresh whole-production census, including new packages and re-exports."""
    result = {}
    for path in sorted(guard.production_mojo_paths(Path(root))):
        relative = _relative_path(path, root).as_posix()
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


def resolver_unshadowed(root, paths, *, render_entries=None, typed_entries=None,
                        math_entries=None):
    """Refuse alternate qualified-module and namespace lookup surfaces.

    Every reviewed import begins at a protected top-level namespace. Guard
    those namespace names conservatively everywhere, including every compiled
    entry directory, repository root and supplied include root. Imported-module
    directories are not Mojo lookup roots. An unrelated leaf basename elsewhere
    cannot shadow a qualified import and is not itself a namespace competitor.
    For the new render helper only, a separately verified source entry census
    can restrict bare render basenames to actual compiled lookup directories.
    A separate math scope is only for the exact supplemental native witness.
    It does not replace any production owner's existing resolver obligations.
    The default retains the historical conservative rule for every namespace.
    Exact consumed module/prefix coordinates still reject case, alternate
    suffix/package and symlink changes. Only three exact regular wiki files are
    inert. Include roots receive structural checks only: maintained generation
    origins and source/staged manifests bind instrumented coverage bytes.
    """
    root = Path(root)
    if not root.is_dir() or not _root_unaliased(root):
        return False
    if render_entries is not None and (type(render_entries) is not frozenset
            or '.' not in render_entries or any(type(path) is not str or not path
            or Path(path).is_absolute() or '..' in Path(path).parts for path in render_entries)):
        return False
    if math_entries is not None and (type(math_entries) is not frozenset
            or '.' not in math_entries or any(type(path) is not str or not path
            or Path(path).is_absolute() or '..' in Path(path).parts for path in math_entries)):
        return False
    if typed_entries is not None and (type(typed_entries) is not frozenset
            or '.' not in typed_entries or any(type(path) is not str or not path
            or Path(path).is_absolute() or '..' in Path(path).parts for path in typed_entries)):
        return False
    # Only these newly introduced families use the established compiled-entry
    # lookup rule. Every pre-333 family keeps its historical refusal policy.
    typed_families = ('animation', 'cameras', 'core', 'exporters', 'geometries',
                      'lights', 'materials', 'objects', 'postprocessing', 'renderers')
    allowed = set(paths)
    stems = {str(Path(p).with_suffix('')).casefold() for p in allowed}
    canonical_prefixes = {str(parent) for p in allowed for parent in Path(p).parents if str(parent) != '.'}
    prefixes = {prefix.casefold() for prefix in canonical_prefixes}
    top = {Path(p).parts[0].casefold() for p in allowed} | {'std'}
    inert = {'docs/wiki/Math.md', 'docs/wiki/Units.md', 'docs/wiki/Extensions.md'}
    try:
        for folder, directories, files in os.walk(root, followlinks=False):
            relative_dir = _relative_path(Path(folder), root).as_posix()
            directories[:] = [name for name in directories if name not in SKIP
                              and (Path(relative_dir) / name).as_posix() != 'coverage/build']
            # This is only lexical work on os.walk's builtin POSIX names.
            # Keep every traversal and every relevant filesystem observation.
            plain_directory = (os.name == 'posix' and type(root) is PosixPath
                and type(getattr(root, '_raw_paths', None)) is list
                and all(type(part) is str for part in root._raw_paths)
                and type(folder) is str and folder.startswith('/')
                and all(part not in ('', '.', '..') for part in folder.split('/')[1:])
                and type(relative_dir) is str
                and (relative_dir == '.' or all(part not in ('', '.', '..')
                                               for part in relative_dir.split('/'))))
            for name in directories + files:
                plain_name = (plain_directory and type(name) is str
                    and name not in ('', '.', '..') and '/' not in name
                    and not name.endswith('.'))
                if plain_name:
                    dot = name.rfind('.')
                    leaf_stem = name[:dot] if dot > 0 else name
                    plain_name = leaf_stem not in ('.', '..')
                if plain_name:
                    prefix = '' if relative_dir == '.' else relative_dir + '/'
                    relative = prefix + name
                    stem = (prefix + leaf_stem).casefold()
                    path = None
                else:
                    path = Path(folder) / name
                    relative = _relative_path(path, root).as_posix()
                    stem = str(Path(relative).with_suffix('')).casefold()
                folded = relative.casefold()
                # Namespace roots remain protected at every actual lookup root.
                scoped_name = name.split('.')[0].casefold()
                relevant = (folded in stems or folded in prefixes or stem in stems
                            or stem in prefixes or (scoped_name in top
                                and (scoped_name != 'render' or render_entries is None
                                     or relative_dir.casefold() in render_entries)
                                and (scoped_name != 'math' or math_entries is None
                                     or relative_dir.casefold() in math_entries)
                                and (scoped_name not in typed_families or typed_entries is None
                                     or relative_dir.casefold() in typed_entries))
                            or (name == '__init__.mojo' and relative_dir.casefold() in prefixes))
                if not relevant:
                    continue
                if path is None:
                    path = Path(folder) / name
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


def _render_lookup_args(paths, entries):
    """Scope only reviewed new families with an established entry census.

    Exact module and package prefixes never use this namespace-only exception.
    The caller checks the complete physical source/entry inventory before and
    after the operation; adding a new entry or import cannot reuse this scope.
    Include-root callers first bind their physical source/entry census.
    """
    render = any(path.startswith('render/') for path in paths)
    typed = any(path.split('/')[0] in ('animation', 'cameras', 'core', 'exporters',
        'geometries', 'lights', 'materials', 'objects', 'postprocessing', 'renderers')
        for path in paths)
    if not render and not typed:
        return {}
    require(type(entries) in (tuple, list), 'missing compiled entry census')
    roots = frozenset(('.', *(path.casefold() for path in entries),
        *(str(Path(path).parent).casefold() for path in shared_helpers.TESTS)))
    typed_roots = roots | frozenset(str(Path(path).parent).casefold()
                                    for path in typed_boundary.TESTS)
    return {**({'render_entries': roots} if render else {}),
            **({'typed_entries': typed_roots} if typed else {})}


def _helper_entry_census(root, *, _operation=None):
    """Observe actual source bytes that determine the compiled entry contexts."""
    known = {path.as_posix() for path in _sibling('cache_key').input_paths(root)
             if path.suffix == '.mojo'}
    _operation_known_paths(root, known, _operation=_operation)
    image = {}
    for path in sorted(known):
        raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)
        require(type(raw) is bytes, 'render entry source is not physical bytes: ' + path)
        image[path] = raw
    entries = tuple(_sibling('affected').entry_directories(
        {path: _physical_text(raw) for path, raw in image.items()}))
    return entries, image


def _helper_entry_census_finish(root, image, *, _operation=None):
    """Keep all entry-classifying reads, then finish with a fresh path census."""
    for path, raw in image.items():
        actual = _observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)
        require(type(actual) is bytes and actual == raw, 'render entry source changed: ' + path)
    known = {path.as_posix() for path in _sibling('cache_key').input_paths(root)
             if path.suffix == '.mojo'}
    _operation_known_paths(root, known, _operation=_operation)
    require(known == set(image), 'render entry path census changed')


def _include_entry_context(location, source_image, *, _operation=None):
    """Bind an include surface to maintained source coordinates and entries.

    The coverage generation owner authenticates origins and complete staged
    bytes before requesting proofs. This additional structural gate records
    every physical Mojo file and refuses unknown coordinates or changed entry
    contexts; callers retain and reread its image through finalization.
    """
    entries, image = _helper_entry_census(location, _operation=_operation)
    require(set(image) <= set(source_image), 'unmaintained include source coordinate')
    expected = _sibling('affected').entry_directories(
        {path: _physical_text(source_image[path]) for path in image})
    require(list(entries) == expected, 'include compiled entry directories changed')
    return entries, image


def _helper_render_context(root, *, _inputs=None, _operation=None):
    """Use the actual owned census, or physically establish a historical one."""
    owner = _inputs if _inputs is not None else _operation
    if owner is not None and owner._state == 'active':
        return owner._entries, None
    raw = _observe_bytes(root, MIGRATION, _regular(root, MIGRATION).read_bytes(),
                         _operation=_operation)
    require(sha(raw) == MIGRATION_SHA256, 'render entry authority changed')
    expected = json.loads(raw, object_pairs_hook=source.unique_keys)['entry_directories']
    entries, image = _helper_entry_census(root, _operation=_operation)
    require(list(entries) == expected, 'render compiled entry directories changed')
    if _operation is not None:
        require(_operation._state == 'pending', 'invalid render context owner')
        require(not _operation._known or _operation._known == frozenset(image),
                'pending render source census changed')
        require(not _operation._entries or _operation._entries == entries,
                'pending render entry directories changed')
        _operation._known = frozenset(image)
        _operation._entries = entries
    return entries, image


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
            and not (type(main) is types.ModuleType
                     and type(vars(main).get('__file__')) is str
                     and _different_alias_leaf(vars(main)['__file__'], ('cache_key_contracts.py',)))
            and Path(main.__file__).absolute() == Path(__file__).absolute().with_name('cache_key_contracts.py')
            and frame.f_code is _live_function_code(getattr(main, 'verify', None))):
        return True
    # An importlib alias can run the public fresh path without being registered
    # in sys.modules. It is still a distinct operation, never an outer borrower.
    namespace = frame.f_globals if frame is not None else {}
    if include_aliases is True and _different_alias_leaf(namespace.get('__file__'), ('cache_key_contracts.py',)):
        return False
    # A real helper frame cannot be an unwrapped verify alias. Elide only
    # lexical path construction; every stack walk and live owner check remains.
    if (include_aliases is True and type(frame) is types.FrameType
            and type(namespace) is dict and os.name == 'posix' and Path is pathlib.Path
            and type(namespace.get('__file__')) is str
            and namespace['__file__'].startswith('/')
            and type(__file__) is str and __file__.startswith('/')
            and __file__.rsplit('/', 1)[-1] not in ('', '.', '..')
            and _live_function_code is _LIVE_FUNCTION_CODE
            and _live_function_code.__code__ is _LIVE_FUNCTION_CODE_CODE):
        candidate = namespace.get('verify')
        if (candidate is None or (type(candidate) is types.FunctionType
                and type(candidate.__dict__) is dict
                and '__wrapped__' not in candidate.__dict__
                and frame.f_code is not candidate.__code__)):
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


def _publish_input_image(view, snapshots, authority_raw, known, production,
                         entries, resolver_paths, executing):
    """Store an immutable image only after its concrete owner authenticated it."""
    caller = sys._getframe(1)
    require(caller.f_globals is globals()
            and caller.f_code in (_live_function_code(_CacheInputs._publish),
                                  _live_function_code(_PublicAdmission._publish))
            and caller.f_locals.get('self') is view,
            'input image publication requires its concrete publisher')
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
    require(not view._scaled_resolver_paths or
            (view._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE
             and view._scaled_resolver_paths <= image.keys()),
            'pending scaled native context differs from captured image')
    view._raw = types.MappingProxyType(image)
    view._record_raw = authority_raw
    view._known = frozenset(known)
    view._production = frozenset(production)
    view._entries = tuple(entries)
    view._native_contexts = tuple((path, (str(Path(path).parent),)) for path in NATIVE_WITNESSES)
    view._resolver_paths = frozenset(resolver_paths)
    require(not view._executing or dict(view._executing) == executing,
            'pending checker image differs from captured execution')
    view._executing = types.MappingProxyType(dict(executing))
    view._state = 'active'


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
        self._scaled_resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})

    def _check_context(self, root):
        try:
            require(_absolute_root_text(root) == self._root
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
        _publish_input_image(self, snapshots, authority_raw, known, production,
                             entries, resolver_paths, executing)

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
            require(sha(_historical_typed_text(path, self.raw(owner, root, path).decode('utf-8'))) == AFTER_SHA256[path],
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
            require(resolver_unshadowed(root, self._resolver_paths,
                        **_render_lookup_args(self._resolver_paths, self._entries))
                    and all(resolver_unshadowed(location, self._resolver_paths)
                            for location in self._include_roots),
                    'resolver surface changed during owned verification')
            if self._scaled_resolver_paths:
                require(self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE
                        and resolver_unshadowed(root, self._scaled_resolver_paths,
                                                **_scaled_lookup_args()),
                        'scaled native resolver changed during owned verification')
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
        self._scaled_resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._owner_frame = None

    def __copy__(self):
        raise ContractError('full-audit cleanup successor: cache input views cannot be copied')

    def __deepcopy__(self, memo):
        raise ContractError('full-audit cleanup successor: cache input views cannot be copied')

    def __reduce_ex__(self, protocol):
        raise ContractError('full-audit cleanup successor: cache input views cannot be serialized')


# Only these explicit public entries can own a short-lived typed admission.
# The existing dependency authority binds their complete executable sources.
def _public_admission_entries():
    return {'cache_key_contracts.py': ('verify',),
            'rounded_line_selector_contracts.py': ('verify_premises',),
            'seed_count_contracts.py': ('verify_score',)}



def _public_admission_scope(root, frame):
    caller = sys._getframe(1)
    require(caller.f_globals is vars(source)
            and caller.f_code is _live_function_code(source.typed_admission_scope)
            and caller.f_back is frame,
            'public admission requires its direct source factory')
    return _PublicAdmission(root, frame)


class _PublicAdmission:
    """A live public call's fully admitted image, never an ambient PASS."""

    def __init__(self, root, frame):
        caller = sys._getframe(1)
        require(caller.f_globals is globals()
                and caller.f_code is _public_admission_scope.__code__
                and caller.f_locals.get('frame') is frame,
                'public admission requires its direct factory')
        filename = frame.f_globals.get('__file__')
        require(type(filename) is str
                and Path(filename).absolute().parent == Path(__file__).absolute().parent
                and frame.f_code.co_name in _public_admission_entries().get(Path(filename).name, ()),
                'unsupported public admission owner')
        self._owner_frame = frame
        self._owner = object()
        self._stamp = id(self)
        self._thread = threading.get_ident()
        self._root = _absolute_root_text(root)
        self._cwd = str(Path.cwd())
        self._include_roots = ()
        self._state = 'pending'
        self._failed = False
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = self._production = frozenset()
        self._entries = self._native_contexts = ()
        self._resolver_paths = self._scaled_resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._checker_raw = {}
        self._checker_codes = {}
        self._checker_frames = {}
        self._inventory_frame = None
        require(self._authenticate_frame(frame), 'unreviewed public admission owner code')

    def _authenticate_frame(self, frame):
        namespace = frame.f_globals
        filename = namespace.get('__file__')
        if type(filename) is not str:
            return False
        physical = Path(filename).absolute()
        base = Path(__file__).absolute().parents[2]
        if not physical.is_relative_to(base):
            return False
        relative = physical.relative_to(base).as_posix()
        expected = _IMPORT_IDENTITIES.get(str(physical.resolve()))
        if expected is None:
            return False
        require(physical == _SELF_PATH or DEPENDENCY_TOOL_SHA256.get(relative) == expected,
                'public consumer checker authority changed: ' + relative)
        raw = _regular(base, relative).read_bytes()
        require(sha(raw) == expected, 'public admission checker changed: ' + relative)
        previous = self._checker_raw.setdefault(relative, raw)
        require(previous == raw, 'public admission checker changed during call: ' + relative)
        if relative not in self._checker_codes:
            def nested(code):
                yield code
                for child in code.co_consts:
                    if type(child) is types.CodeType:
                        yield from nested(child)
            self._checker_codes[relative] = {
                code.co_qualname: code for code in nested(compile(
                    raw, filename, 'exec', dont_inherit=True, optimize=sys.flags.optimize))}
        expected_code = self._checker_codes[relative].get(frame.f_code.co_qualname)
        if expected_code is None or _code_identity(frame.f_code) != _code_identity(expected_code):
            return False
        parts = frame.f_code.co_qualname.split('.')
        live = namespace.get(parts[0])
        if type(live) is type and len(parts) > 1:
            live = getattr(live, parts[1], None)
        code = _live_function_code(live)
        if code is frame.f_code:
            self._checker_frames[(id(namespace), frame.f_code)] = frame
            return True
        # Comprehensions retain the identity of their executing parent code.
        def contains(parent):
            return parent is frame.f_code or any(contains(child) for child in parent.co_consts
                if type(child) is types.CodeType)
        return type(code) is types.CodeType and contains(code)

    def __enter__(self):
        require(sys._getframe(1) is self._owner_frame and self._state == 'pending',
                'public admission entry requires its live owner')
        return self

    def _check_context(self, root):
        require(_absolute_root_text(root) == self._root and str(Path.cwd()) == self._cwd
                and self._thread == threading.get_ident(),
                'public admission root, thread or working directory changed')

    def _check(self, owner, root):
        try:
            require(type(self) is _PublicAdmission and self._stamp == id(self)
                    and owner is self._owner and not self._failed
                    and self._state in ('pending', 'active'), 'inactive public admission')
            self._check_context(root)
            methods = {code.co_name: code for code in
                _IMPORT_CODE[str(_SELF_PATH)]['_PublicAdmission'].co_consts
                if type(code) is types.CodeType}
            for name in ('_publish', 'raw', 'observe_bytes'):
                method = vars(_PublicAdmission).get(name)
                require(name not in self.__dict__ and type(method) is types.FunctionType
                        and method.__globals__ is globals()
                        and '__wrapped__' not in method.__dict__
                        and _code_identity(method.__code__) == _code_identity(methods[name]),
                        'public admission image method changed: ' + name)
            shared = {code.co_name: code for code in
                _IMPORT_CODE[str(_SELF_PATH)]['_CacheInputs'].co_consts
                if type(code) is types.CodeType}
            for name in ('raw', 'observe_bytes', 'checkpoint'):
                method = vars(_CacheInputs).get(name)
                require(type(method) is types.FunctionType and method.__globals__ is globals()
                        and '__wrapped__' not in method.__dict__
                        and _code_identity(method.__code__) == _code_identity(shared[name]),
                        'public admission shared method changed: ' + name)
            frame = sys._getframe(1)
            while frame is not None and frame is not self._owner_frame:
                frame = frame.f_back
            require(frame is self._owner_frame and frame is not None
                    and frame.f_locals.get('_typed_admission') is self,
                    'public admission owner is no longer active')
            require(self._authenticate_frame(frame), 'public admission owner code changed')
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError):
            self.fail()
            raise

    def _check_pending(self, root):
        self._check(self._owner, root)
        require(self._state == 'pending' and not self._raw and self._record_raw is None,
                'invalid pending public admission')
        publisher = sys._getframe(1)
        gate = publisher.f_back
        require(publisher.f_code is _live_function_code(_PublicAdmission._publish)
                and gate is not None and gate.f_globals is globals()
                and gate.f_code is _live_function_code(verify)
                and gate.f_locals.get('_public_admission') is self,
                'public admission publication requires its complete gate')

    def _publish(self, root, snapshots, authority_raw, known, production,
                 entries, resolver_paths, executing):
        caller = sys._getframe(1)
        require(caller.f_globals is globals()
                and caller.f_code is _live_function_code(verify),
                'public input publication requires the full gate')
        self._check_pending(root)
        _publish_input_image(self, snapshots, authority_raw, known, production,
                             entries, resolver_paths, executing)

    def raw(self, owner, root, path):
        return _CacheInputs.raw(self, owner, root, path)

    def observe_bytes(self, owner, root, path):
        return _CacheInputs.observe_bytes(self, owner, root, path)


    def _check_consumer_bindings(self):
        for frame in tuple(self._checker_frames.values()):
            require(self._authenticate_frame(frame), 'public consumer frame changed')
            namespace = frame.f_globals
            path = Path(namespace['__file__']).resolve()
            relative = path.relative_to(_SELF_PATH.parents[2]).as_posix()
            if relative in CHECKER_PATHS:
                continue  # The complete gate/checkpoint checks these modules.
            key = str(path)
            for name, expected in _IMPORT_CODE[key].items():
                if name.startswith('<'):
                    continue
                live = namespace.get(name)
                members = ({child.co_name: child for child in expected.co_consts
                            if type(child) is types.CodeType}
                           if type(live) is type else {None: expected})
                for member, code in members.items():
                    value = getattr(live, member, None) if member else live
                    label = relative + ':' + name + ('.' + member if member else '')
                    _check_defaults(value, _IMPORT_DEFAULTS[key].get(
                        name + '.' + member if member else name), label)
                    actual = _live_function_code(value)
                    require(actual is not None and _code_identity(actual) == _code_identity(code),
                            'public consumer binding changed: ' + label)

    def _publication_inputs(self, root, snapshots):
        self._check(self._owner, root)
        self._check_consumer_bindings()
        image = dict(snapshots)
        for path, expected in self._checker_raw.items():
            raw = _regular(root, path).read_bytes()
            require(raw == expected, 'public checker differs from admitted root: ' + path)
            require(image.setdefault(path, raw) == raw, 'public checker observation changed: ' + path)
        if self._state == 'active':
            for path, raw in image.items():
                require(self._raw.get(path) == raw or
                        (path not in self._raw and self._checker_raw.get(path) == raw),
                        'public input changed between admissions: ' + path)
        return image

    def project(self, root, path, raw):
        try:
            self._check(self._owner, root)
            caller = sys._getframe(1)
            require(caller.f_globals is globals()
                    and caller.f_code is _live_function_code(reviewed_typed_text),
                    'public projection requires its actual typed adapter')
            require(self._state == 'active' and self._raw.get(path) == raw,
                    'typed source differs from public admission: ' + path)
            # A semantic admission is not an exact endpoint admission by itself.
            for name in SOURCE_PATHS:
                require(sha(_historical_typed_text(name, self._raw[name].decode('utf-8')))
                        == AFTER_SHA256[name], 'unreviewed exact public endpoint: ' + name)
            typed_boundary.verify_authority()
            conditioned_cubic.verify_authority()
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError):
            self.fail()
            raise

    def fail(self):
        self._failed = True

    def __exit__(self, kind, error, traceback):
        try:
            require(sys._getframe(1) is self._owner_frame,
                    'public admission exit requires its live owner')
            if error is not None:
                self.fail()
            if kind is None:
                self._check(self._owner, Path(self._root))
                if self._state == 'active':
                    self._check_consumer_bindings()
                    for frame in tuple(self._checker_frames.values()):
                        require(self._authenticate_frame(frame),
                                'public admission consumer code changed')
                    for path, raw in self._checker_raw.items():
                        require(_regular(Path(self._root), path).read_bytes() == raw,
                                'public consumer checker changed at exit: ' + path)
                    _CacheInputs.checkpoint(self, self._owner, Path(self._root))
                    self._check(self._owner, Path(self._root))
        finally:
            self._state = 'closed'
            self._raw = types.MappingProxyType({})
            self._record_raw = None
            self._checker_raw.clear()
            self._checker_codes.clear()
            self._checker_frames.clear()
            self._owner_frame = None
            self._inventory_frame = None
        return False

    def __copy__(self):
        raise ContractError('full-audit cleanup successor: public admissions cannot be copied')

    def __deepcopy__(self, memo):
        return self.__copy__()

    def __reduce_ex__(self, protocol):
        return self.__copy__()


def _cache_inventory_admission_frame(frame, scope):
    filename = frame.f_globals.get('__file__')
    valid = (type(filename) is str and Path(filename).absolute() ==
            Path(__file__).absolute().with_name('cache_key_contracts.py')
            and frame.f_code is _live_function_code(frame.f_globals.get('inventory'))
            and frame.f_locals.get('_admission') is scope
            and scope._authenticate_frame(frame))
    if valid:
        if scope._inventory_frame is None:
            scope._inventory_frame = frame
        elif scope._inventory_frame is not frame:
            scope.fail()
            raise ContractError('full-audit cleanup successor: public inventory invocation changed')
    return valid


def _public_admission_for(root, *, publication=False):
    """Find an explicitly entered owner through authenticated callsites only."""
    frames = []
    frame = sys._getframe(1)
    while frame is not None:
        scope = frame.f_locals.get('_typed_admission')
        borrowed = frame.f_locals.get('_admission')
        bridge = (type(borrowed) is _PublicAdmission
                  and _cache_inventory_admission_frame(frame, borrowed))
        if bridge:
            scope = borrowed
        if type(scope) is _PublicAdmission and (scope._owner_frame is frame or bridge):
            try:
                wrappers = set()
                for call in frames:
                    if publication and call.f_code in wrappers:
                        wrappers.remove(call.f_code)
                        continue
                    if not scope._authenticate_frame(call):
                        return None
                    candidate = call.f_globals.get(call.f_code.co_name)
                    while type(candidate) is types.FunctionType and hasattr(candidate, '__wrapped__'):
                        wrappers.add(candidate.__code__)
                        candidate = candidate.__wrapped__
                scope._check(scope._owner, root)
                return scope
            except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError):
                scope.fail()
                raise
        frames.append(frame)
        frame = frame.f_back
    return None


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
    if type(kind) is str:
        if kind == 'invariant':
            name = 'coverage_invariant_contracts'
        elif kind == 'winner':
            name = 'winner_sign_contracts'
        elif kind == 'border':
            name = 'border_parser_contracts'
        elif kind == 'runtime':
            name = 'check_runtime_support'
        elif kind == 'sampled':
            name = 'check_sampled_values'
        else:
            name = None
    else:
        # Exotic keys retain dictionary hashing and equality behavior.
        name = {'invariant': 'coverage_invariant_contracts',
                'winner': 'winner_sign_contracts', 'border': 'border_parser_contracts',
                'runtime': 'check_runtime_support', 'sampled': 'check_sampled_values'}.get(kind)
    return sys.modules.get((__package__ + '.' if __package__ else '') + name) if name else None


def _seed_frame_kind(frame, *, include_aliases=False):
    """Recognize only the canonical standalone seed wrapper; aliases block reuse."""
    namespace = frame.f_globals
    if type(namespace) is not dict:
        return None
    candidate = namespace.get('_verify_standalone')
    if type(candidate) is not types.FunctionType or frame.f_code is not candidate.__code__:
        return None
    filename = namespace.get('__file__')
    if type(filename) is not str:
        return None
    expected = Path(__file__).absolute().with_name('seed_count_contracts.py')
    if Path(filename).absolute() != expected:
        return None
    module_code = namespace.get('_EXECUTED_MODULE_CODE')
    if type(module_code) is types.CodeType:
        codes = [code for code in module_code.co_consts
                 if type(code) is types.CodeType and code.co_name == '_verify_standalone']
        module = sys.modules.get((__package__ + '.' if __package__ else '') + 'seed_count_contracts')
        if (len(codes) == 1 and codes[0] is frame.f_code and candidate.__globals__ is namespace
                and type(module) is types.ModuleType and namespace is vars(module)):
            return 'seed'
    return 'alias_seed' if include_aliases else None


def _operation_frame_kind(frame, *, include_aliases=False):
    if frame is None:
        return None
    namespace = frame.f_globals
    filename = namespace.get('__file__')
    receipt_kind = _receipt_frame_kind(frame, include_aliases=include_aliases)
    if receipt_kind is not None:
        return receipt_kind
    seed_kind = _seed_frame_kind(frame, include_aliases=include_aliases)
    if seed_kind is not None:
        return seed_kind
    # Pure negative filter only for exact builtin absolute spellings and plain
    # functions. Relative paths and deeper/cyclic/exotic wrappers keep full checks.
    if (type(filename) is str and filename.startswith('/')
            and type(__file__) is str and __file__.startswith('/')):
        candidates = (namespace.get('verify'), namespace.get('reviewed_nonempty_loops'))
        candidate_all = all
        if _BUILTIN_ALL is not None and candidate_all is _BUILTIN_ALL:
            first, second = candidates
            negative = (first is None or (type(first) is types.FunctionType
                        and '__wrapped__' not in first.__dict__
                        and frame.f_code is not first.__code__)) and (
                        second is None or (type(second) is types.FunctionType
                        and '__wrapped__' not in second.__dict__
                        and frame.f_code is not second.__code__))
        else:
            negative = candidate_all(value is None or (type(value) is types.FunctionType
                       and '__wrapped__' not in value.__dict__
                       and frame.f_code is not value.__code__) for value in candidates)
        if negative:
            return None
        # Preserve the original plain branch and exotic-dictionary protocols.
        if type(namespace) is dict:
            for value in candidates:
                if value is None:
                    continue
                if type(value) is not types.FunctionType or type(value.__dict__) is not dict:
                    break
                if '__wrapped__' in value.__dict__:
                    value = value.__dict__['__wrapped__']
                    if (type(value) is not types.FunctionType or type(value.__dict__) is not dict
                            or '__wrapped__' in value.__dict__):
                        break
                if frame.f_code is value.__code__:
                    break
            else:
                # Only widen the negative filter in a builtin registry context.
                # Exotic registrations and lazy module exports retain their
                # original lookup/error behavior. No owner result is retained.
                if (type(sys.modules) is dict
                        and (__package__ is None or type(__package__) is str)):
                    prefix = (__package__ + '.') if __package__ else ''
                    for name, attribute in (
                            (prefix + 'coverage_invariant_contracts', 'verify'),
                            (prefix + 'winner_sign_contracts', 'verify'),
                            (prefix + 'border_parser_contracts', 'verify'),
                            (prefix + 'check_runtime_support', 'verify'),
                            (prefix + 'check_sampled_values', 'verify'),
                            ('coverage_loop_proofs', 'reviewed_nonempty_loops'),
                            ('tools.coverage_loop_proofs', 'reviewed_nonempty_loops')):
                        module = sys.modules.get(name)
                        if module is not None and (type(module) is not types.ModuleType
                                or (namespace is vars(module) and attribute not in vars(module)
                                    and '__getattr__' in vars(module))):
                            break
                    else:
                        return None
    for kind in ('invariant', 'winner', 'border', 'runtime', 'sampled'):
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
                                         'border_parser_contracts.py', 'check_runtime_support.py',
                                         'check_sampled_values.py', 'coverage_loop_proofs.py')):
        return None
    for kind, name in (('invariant', 'coverage_invariant_contracts.py'),
                       ('winner', 'winner_sign_contracts.py'),
                       ('border', 'border_parser_contracts.py'),
                       ('runtime', 'check_runtime_support.py'), ('sampled', 'check_sampled_values.py')):
        if (Path(filename).absolute() == Path(__file__).absolute().with_name(name)
                and frame.f_code is _live_function_code(namespace.get('verify'))):
            return 'alias_' + kind
    if (Path(filename).absolute() == Path(__file__).absolute().parent.parent / 'coverage_loop_proofs.py'
            and frame.f_code is _live_function_code(namespace.get('reviewed_nonempty_loops'))):
        return 'alias_loops'
    return None


def _receipt_frame_kind(frame, *, include_aliases=False):
    """Recognize the real maintained import or script; aliases only block reuse."""
    namespace = frame.f_globals
    if type(namespace) is not dict:
        return None
    candidate = namespace.get('build_receipt')
    if type(candidate) is not types.FunctionType or frame.f_code is not candidate.__code__:
        return None
    filename = namespace.get('__file__')
    if type(filename) is not str:
        return None
    expected = Path(__file__).absolute().parent.parent / 'coverage_loop_proofs.py'
    if Path(filename).absolute() != expected:
        return None
    module_code = namespace.get('_EXECUTED_MODULE_CODE')
    if type(module_code) is types.CodeType:
        codes = [code for code in module_code.co_consts
                 if type(code) is types.CodeType and code.co_name == 'build_receipt']
        if len(codes) == 1 and codes[0] is frame.f_code and candidate.__globals__ is namespace:
            for name in ('coverage_loop_proofs', 'tools.coverage_loop_proofs', '__main__'):
                module = sys.modules.get(name)
                if type(module) is types.ModuleType and namespace is vars(module):
                    return 'generated_receipt'
    return 'alias_generated_receipt' if include_aliases else None


def _receipt_operation_enter(root, build, seed):
    """Create a lazy image only for one live maintained generated receipt."""
    frame = sys._getframe(1)
    require(_receipt_frame_kind(frame) == 'generated_receipt'
            and frame.f_locals.get('root') == root and frame.f_locals.get('build') == build
            and frame.f_locals.get('_receipt_seed') is seed,
            'generated receipt requires its direct producer frame')
    return _InvariantInputs(root, frame, 'generated_receipt')


def _operation_include_context(operation, root, include_roots):
    """Nonempty include ownership belongs only to the exact generated invocation."""
    try:
        _operation_check(operation, root)
        if operation is not None:
            expected = operation._include_roots
            supplied = tuple(_absolute_root_text(path) for path in include_roots)
            # A generated receipt also admits root-only historical inputs.
            require(supplied == expected or (supplied == ()
                                             and operation._kind == 'generated_receipt'),
                    'operation include root changed')
            require(not expected or operation._kind == 'generated_receipt',
                    'unowned coverage include roots')
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        _operation_fail(operation, error)


def _invariant_verify_frame(frame, *, include_aliases=False):
    kind = _operation_frame_kind(frame, include_aliases=include_aliases)
    return kind == 'invariant' or (include_aliases and kind == 'alias_invariant')


def _private_operation_wrapper(frame, kind, operation):
    """Return only the exact explicit child wrapper; never skip arbitrary frames."""
    if kind in ('map_loops', 'rtree_loops', 'other_loops', 'alias_loops') and operation._kind == 'generated_receipt':
        caller = frame.f_back
        owner = operation._owner_frame
        namespace = owner.f_globals
        if (kind not in ('map_loops', 'rtree_loops', 'other_loops', 'alias_loops')
                or frame.f_globals is not namespace or caller is None
                or caller.f_globals is not namespace
                or caller.f_code is not _live_function_code(namespace.get('_receipt_reviewed_nonempty_loops'))
                or caller.f_back is not owner):
            return None
        for local in (frame.f_locals, caller.f_locals):
            if (local.get('_operation') is not operation
                    or _absolute_root_text(local.get('root')) != operation._root
                    or tuple(_absolute_root_text(path) for path in local.get('include_roots', ()))
                    != operation._include_roots):
                return None
        return caller
    if kind not in ('invariant', 'border') or operation._kind not in ('winner', 'runtime', 'sampled'):
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
        if _absolute_root_text(local.get('root')) != operation._root:
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
                and operation._kind in ('winner', 'runtime', 'sampled'), 'invalid private operation wrapper')
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        _operation_fail(operation, error)


def _operation_enter(root, kind, _operation=None, *, module=None, include_roots=()):
    """Enter a fresh public owner or its exact explicitly bound private child."""
    frame = sys._getframe(1)
    try:
        if kind is None or include_roots != ():
            require(_operation is None, 'unsupported context cannot borrow operation inputs')
            return None, False
        require(kind in ('invariant', 'winner', 'border', 'runtime', 'sampled', 'seed', 'map_loops', 'rtree_loops'),
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
                paths.add(_relative_path(Path(path), root).as_posix())
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


def _operation_record(operation, root, *, exact=False, include_roots=None, expected_lane_raw=None):
    try:
        require(type(operation) is _InvariantInputs,
                'invalid private operation projection')
        if include_roots is None:
            include_roots = tuple(Path(path) for path in operation._include_roots)
        _operation_include_context(operation, root, include_roots)
        require(_absolute_root_text(root) == operation._root,
                'generated input cannot supply source authority')
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
                and caller.f_code in (_live_function_code(_invariant_operation), _live_function_code(_operation_enter),
                                      _live_function_code(_receipt_operation_enter))
                and caller.f_back is owner_frame and _operation_frame_kind(owner_frame) == kind,
                'bounded inputs require their direct owner factory')
        super().__init__(object(), root, owner_frame)
        self._kind = kind
        self._failed = False
        self._failure_reason = None
        self._observations = []
        self._discoveries = []
        self._capturing = False
        self._checker_receipt = False
        self._receipt_seed = None
        self._receipt_seed_token = None
        self._receipt_source_digests = types.MappingProxyType({})
        self._receipt_stage_digests = types.MappingProxyType({})
        self._receipt_production = types.MappingProxyType({})
        self._receipt_observations = []
        self._receipt_discoveries = []
        self._include_raw = types.MappingProxyType({})
        self._include_entries = ()
        self._include_production = frozenset()
        self._proof_bindings = types.MappingProxyType({})
        if kind == 'generated_receipt':
            build = owner_frame.f_locals['build']
            seed = owner_frame.f_locals['_receipt_seed']
            require(type(seed) is dict and _absolute_root_text(build) != self._root,
                    'invalid generated receipt coordinates')
            self._include_roots = (_absolute_root_text(build),)
            self._receipt_seed = _canonical(seed).encode('utf-8')
            self._receipt_seed_token = seed
            self._receipt_source_digests = types.MappingProxyType(dict(seed['root_inputs']))
            self._receipt_stage_digests = types.MappingProxyType(
                {path: item['instrumented'] for path, item in seed['inputs'].items()})
            production = {}
            for location, digests in ((self._root, self._receipt_source_digests),
                                      (self._include_roots[0], self._receipt_stage_digests)):
                production[location] = self._receipt_production_paths(location)
                require(production[location] <= digests.keys(),
                        'production census differs from producer coordinates')
            self._receipt_production = types.MappingProxyType(production)

    def _check_context(self, root):
        if self._kind != 'generated_receipt':
            return super()._check_context(root)
        frame = self._owner_frame
        require(frame is not None and str(Path.cwd()) == self._cwd
                and _absolute_root_text(root) in (self._root, *self._include_roots)
                and _absolute_root_text(frame.f_locals.get('root')) == self._root
                and (_absolute_root_text(frame.f_locals.get('build')), ) == self._include_roots
                and frame.f_locals.get('_receipt_seed') is self._receipt_seed_token,
                'generated source/build context changed')

    def _receipt_production_paths(self, location):
        build = Path(self._include_roots[0])
        return frozenset(path.relative_to(location).as_posix()
            for path in guard.production_mojo_paths(Path(location))
            if location != self._root or not path.absolute().is_relative_to(build))

    def _receipt_inputs_check(self):
        self._check_owner(Path(self._root))
        require(self._kind == 'generated_receipt' and type(self._receipt_seed) is bytes,
                'invalid generated input boundary')
        require(_canonical(self._receipt_seed_token).encode('utf-8') == self._receipt_seed,
                'generated receipt seed changed after consumption')
        for location, expected in self._receipt_production.items():
            require(self._receipt_production_paths(location) == expected,
                'generated producer production census changed')
        seed = json.loads(self._receipt_seed, object_pairs_hook=source.unique_keys)
        self._owner_frame.f_globals['check_capture_inputs'](
            {'receipt': seed}, Path(self._root), Path(self._include_roots[0]))

    def _receipt_bindings(self, root, include_roots):
        try:
            _operation_include_context(self, root, include_roots)
            require(self._kind == 'generated_receipt' and _absolute_root_text(root) == self._root,
                    'invalid generated proof-binding request')
            self._admit(root, exact=True)
            # This authenticates live descriptor tables without replaying the
            # complete source graph. Rows still read their actual physical bytes.
            typed_boundary.verify_authority()
            return dict(self._proof_bindings)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def _clear_receipt(self):
        self._receipt_seed = None
        self._receipt_seed_token = None
        self._receipt_source_digests = types.MappingProxyType({})
        self._receipt_stage_digests = types.MappingProxyType({})
        self._receipt_production = types.MappingProxyType({})
        self._receipt_observations.clear()
        self._receipt_discoveries.clear()
        self._include_raw = types.MappingProxyType({})
        self._include_entries = ()
        self._include_production = frozenset()
        self._proof_bindings = types.MappingProxyType({})

    def _invalidate(self, error):
        self._failed = True
        self._failure_reason = str(error)
        self._clear_receipt()
        self._state = 'invalid'
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = frozenset()
        self._production = frozenset()
        self._entries = ()
        self._native_contexts = ()
        self._resolver_paths = frozenset()
        self._scaled_resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._observations = []
        self._discoveries = []
        self._checker_receipt = False

    def _bind_checker_receipt(self, root, executing):
        """Retain only a supplied checker image consumed by this operation."""
        try:
            self._check_owner(root)
            caller = sys._getframe(1)
            require(caller.f_globals is globals()
                    and caller.f_code is _live_function_code(proof_bindings)
                    and caller.f_locals.get('_operation') is self
                    and type(executing) is dict
                    and type(self._checker_receipt) is bool
                    and self._state == 'active' and not self._capturing,
                    'checker receipt requires its active proof-binding owner')
            require(executing == dict(self._executing),
                    'checker receipt differs from captured executing image')
            self._checker_receipt = True
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

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
                 entries, resolver_paths, executing, *, receipt_bindings=None,
                 include_images=()):
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
        require(not self._scaled_resolver_paths or
                (self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE
                 and self._scaled_resolver_paths <= image.keys()),
                'pending scaled native context differs from captured image')
        self._raw = types.MappingProxyType(image)
        self._record_raw = authority_raw
        self._known = frozenset(known)
        self._production = frozenset(production)
        self._entries = tuple(entries)
        self._native_contexts = tuple((path, (str(Path(path).parent),)) for path in NATIVE_WITNESSES)
        self._resolver_paths = frozenset(resolver_paths)
        require(not self._executing or dict(self._executing) == executing,
                'pending checker image differs from captured execution')
        self._executing = types.MappingProxyType(dict(executing))
        if self._kind == 'generated_receipt':
            require(type(receipt_bindings) is dict and len(include_images) == 1,
                    'missing generated binding image')
            location, stage_image, stage_args = include_images[0]
            require(_absolute_root_text(location) == self._include_roots[0],
                    'captured generated root changed')
            seed = json.loads(self._receipt_seed, object_pairs_hook=source.unique_keys)
            require(all(seed['root_inputs'][path] == sha(raw) for path, raw in image.items()
                        if path in seed['root_inputs']),
                    'source differs from pre-admission producer observation')
            require(all(seed['inputs'].get(path, {}).get('instrumented') == sha(raw)
                        for path, raw in stage_image.items()),
                    'include differs from pre-admission producer observation')
            require(all(digest == (executing[path] if path in executing else
                        sha(authority_raw if path == MIGRATION else image[path]))
                        for path, digest in receipt_bindings.items()),
                    'generated binding map differs from captured physical domains')
            self._include_raw = types.MappingProxyType(dict(stage_image))
            self._include_entries = tuple(_sibling('affected').entry_directories(
                {path: _physical_text(raw) for path, raw in stage_image.items()}))
            require(stage_args == _render_lookup_args(resolver_paths, self._include_entries),
                    'generated resolver entry context changed')
            self._include_production = frozenset(path.relative_to(location).as_posix()
                for path in guard.production_mojo_paths(Path(location)))
            self._proof_bindings = types.MappingProxyType(dict(receipt_bindings))
            self._checker_receipt = True
        else:
            require(receipt_bindings is None and include_images == (),
                    'non-generated owner received include admission')
        self._state = 'active'
        for location, path, value, mode in self._receipt_observations:
            self._match(Path(location), path, value, mode)
        self._receipt_observations.clear()
        for location, paths, kind in self._receipt_discoveries:
            self._discovery(Path(location), paths, kind)
        self._receipt_discoveries.clear()
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
            if self._kind == 'generated_receipt' and self._state == 'pending':
                location = _absolute_root_text(root)
                digests = (self._receipt_source_digests if location == self._root
                           else self._receipt_stage_digests)
                expected = (self._receipt_production[location] if kind == 'production'
                            else frozenset(path for path in digests if path.endswith('.mojo')))
                require(frozenset(paths) == expected,
                        'consumed census differs from producer boundary: ' + kind)
                self._receipt_discoveries.append((location, frozenset(paths), kind))
                return
            if self._state == 'pending':
                self._discoveries.append((frozenset(paths), kind))
            else:
                generated = self._kind == 'generated_receipt' and _absolute_root_text(root) != self._root
                expected = ((self._include_production if kind == 'production' else frozenset(self._include_raw))
                            if generated else (self._production if kind == 'production' else self._known))
                require(paths == expected, 'consumed operation path census changed: ' + kind)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def _match(self, root, path, value, mode):
        generated = self._kind == 'generated_receipt' and _absolute_root_text(root) != self._root
        image = self._include_raw if generated else self._raw
        require(path in image or (not generated and path == MIGRATION),
                'unlisted operation input: ' + path)
        _regular(root, path)
        raw = self._record_raw if not generated and path == MIGRATION else image[path]
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
            plain_path = (os.name == 'posix' and Path is pathlib.Path and type(path) is str
                          and (path == '.' or _canonical_relative_text(path)))
            require(plain_path or (type(path) is str and path and Path(path).as_posix() == path
                    and not Path(path).is_absolute() and '..' not in Path(path).parts),
                    'invalid operation observation path')
            require(mode in ('bytes', 'default', 'physical', 'utf8',
                             'supplied_default', 'supplied_physical'),
                    'unknown operation observation mode')
            require(type(value) is (bytes if mode == 'bytes' else str),
                    'non-builtin operation observation')
            if self._kind == 'generated_receipt' and self._state == 'pending':
                # Join reads even when no current theorem will trigger capture.
                # A consumed transient value cannot disappear before lazy admission.
                generated = _absolute_root_text(root) != self._root
                digests = self._receipt_stage_digests if generated else self._receipt_source_digests
                digest = digests.get(path)
                if digest is not None:
                    raw = value if mode == 'bytes' else _regular(root, path).read_bytes()
                    require(type(raw) is bytes and sha(raw) == digest,
                            'consumed input differs from generation boundary: ' + path)
                    if mode != 'bytes':
                        expected = _operation_text(raw, mode)
                        require((source.token_sha256(value) == source.token_sha256(expected))
                                if mode.startswith('supplied_') else value == expected,
                                'consumed text differs from generation boundary: ' + path)
                else:
                    require(not generated, 'unknown generated input observation: ' + path)
                self._receipt_observations.append((_absolute_root_text(root), path, value, mode))
            elif self._state == 'pending':
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
                    if self._kind == 'generated_receipt':
                        require(_absolute_root_text(root) == self._root,
                                'generated bytes cannot supply source admission')
                        self._receipt_inputs_check()
                    verify(root, _expected_lane_raw=expected_lane_raw, _capture=self,
                           include_roots=tuple(Path(path) for path in self._include_roots))
                    if self._kind == 'generated_receipt':
                        require(executing_checker_bindings(root) == dict(self._executing),
                                'generated receipt checker differs from executing image')
                except BaseException:
                    self.close()
                    raise
                finally:
                    self._capturing = False
            self._check(self._owner, root)
            if exact:
                for path in SOURCE_PATHS:
                    raw = self.raw(self._owner, root, path)
                    require(sha(raw) == AFTER_SHA256[path] or (typed_boundary.is_current(path, raw)
                            and typed_boundary.edge(path)['before_sha256'] == AFTER_SHA256[path]),
                            'unreviewed exact operation endpoint: ' + path)
            return json.loads(self._record_raw, object_pairs_hook=source.unique_keys)
        except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
            _operation_fail(self, error)

    def checkpoint(self, owner, root):
        # Private demand points keep lifetime checks; the whole-image sweep is
        # owned once by finish(), before the outer public result can escape.
        self._check(owner, root)

    def _receipt_finish_inputs(self, root):
        """One terminal physical sweep, never another source semantic replay."""
        require(_absolute_root_text(root) == self._root, 'foreign generated finalizer root')
        for path in self._raw:
            self.observe_bytes(self._owner, root, path)
        require({p.as_posix() for p in _sibling('cache_key').input_paths(root)
                 if p.suffix == '.mojo'} == self._known,
                'source path inventory changed during generated verification')
        require({path.relative_to(root).as_posix() for path in guard.production_mojo_paths(Path(root))}
                == self._production, 'production path inventory changed during generated verification')
        require(_regular(root, MIGRATION).read_bytes() == self._record_raw,
                'record changed during generated verification')
        typed_boundary.verify_authority()
        location = Path(self._include_roots[0])
        _helper_entry_census_finish(location, self._include_raw, _operation=self)
        require({path.relative_to(location).as_posix() for path in guard.production_mojo_paths(location)}
                == self._include_production, 'generated production path census changed')
        require(resolver_unshadowed(root, self._resolver_paths,
                    **_render_lookup_args(self._resolver_paths, self._entries))
                and resolver_unshadowed(location, self._resolver_paths | {path + '.cov-origin'
                    for path in self._resolver_paths if path.endswith('.mojo')},
                    **_render_lookup_args(self._resolver_paths, self._include_entries)),
                'generated resolver surface changed during verification')
        if self._scaled_resolver_paths:
            require(self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE
                    and _scaled_known_paths(root, _operation=self) == self._known,
                    'generated scaled native context changed')
            scaled_include_paths = self._scaled_resolver_paths | {
                path + '.cov-origin' for path in self._scaled_resolver_paths}
            require(resolver_unshadowed(root, self._scaled_resolver_paths,
                                       **_scaled_lookup_args())
                    and resolver_unshadowed(location, scaled_include_paths,
                                            **_scaled_lookup_args()),
                    'generated scaled native resolver changed during finalization')
        self._receipt_inputs_check()

    def finish(self, root):
        try:
            self._check_owner(root)
            try:
                if self._state == 'active':
                    if self._kind == 'generated_receipt':
                        self._receipt_finish_inputs(root)
                    else:
                        _CacheInputs.checkpoint(self, self._owner, root)
                    require(type(self._checker_receipt) is bool,
                            'invalid consumed checker receipt state')
                    if self._checker_receipt:
                        require(executing_checker_bindings(root) == dict(self._executing),
                                'consumed receipt checker changed during owned verification')
                elif self._kind == 'generated_receipt':
                    # No current theorem is needed, but every consumed read and
                    # census still belongs to this producer observation image.
                    for location, path, value, mode in tuple(self._receipt_observations):
                        raw = _regular(Path(location), path).read_bytes()
                        expected = raw if mode == 'bytes' else _operation_text(raw, mode)
                        require((source.token_sha256(value) == source.token_sha256(expected))
                                if mode.startswith('supplied_') else value == expected,
                                'pending receipt input changed: ' + path)
                    for location, paths, kind in tuple(self._receipt_discoveries):
                        digests = (self._receipt_source_digests if location == self._root
                                   else self._receipt_stage_digests)
                        expected = (self._receipt_production[location] if kind == 'production'
                                    else frozenset(path for path in digests if path.endswith('.mojo')))
                        require(paths == expected, 'pending receipt census changed')
                    location = self._include_roots[0]
                    stage_image = {path: raw for observed_root, path, raw, mode in
                        self._receipt_observations if observed_root == location
                        and mode == 'bytes' and path.endswith('.mojo')}
                    stage_entries = tuple(_sibling('affected').entry_directories(
                        {path: _physical_text(raw) for path, raw in stage_image.items()}))
                    stage_args = _render_lookup_args(self._resolver_paths, stage_entries)
                    require(not stage_args or set(stage_image) == {
                        path for path in self._receipt_stage_digests if path.endswith('.mojo')},
                        'pending include entry context lacks complete observations')
                    include_paths = self._resolver_paths | {path + '.cov-origin'
                        for path in self._resolver_paths if path.endswith('.mojo')}
                    require(resolver_unshadowed(Path(location), include_paths, **stage_args),
                            'pending generated resolver surface changed')
                    if self._scaled_resolver_paths:
                        require(self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE,
                                'pending generated scaled context changed')
                        scaled_paths = self._scaled_resolver_paths | {
                            path + '.cov-origin' for path in self._scaled_resolver_paths}
                        require(resolver_unshadowed(Path(location), scaled_paths,
                                                    **_scaled_lookup_args()),
                                'pending generated scaled resolver surface changed')
                    self._receipt_inputs_check()
                if self._state == 'pending' and (self._resolver_paths or self._scaled_resolver_paths):
                    # Historical owners need no current-root admission. Retain
                    # only their supplemental helper observations until exit.
                    leaf = 'tools/carla_lane_oracle/shared_helper_contracts.py'
                    for path, value, mode in self._observations:
                        if mode == 'bytes' and (path in self._resolver_paths or path == leaf
                                or (self._scaled_resolver_paths and
                                    (path in self._scaled_resolver_paths
                                     or path == scaled_float32.LEAF or path in scaled_float32.TESTS))
                                or (any(name.startswith('render/') for name in self._resolver_paths)
                                    and (path in self._known or path == MIGRATION))):
                            actual = _regular(root, path).read_bytes()
                            require(type(actual) is bytes and actual == value,
                                    'supplemental helper changed during historical operation: ' + path)
                    require(executing_checker_bindings() == dict(self._executing),
                            'supplemental helper checker changed during historical operation')
                    if any(path.startswith('render/') for path in self._resolver_paths):
                        require({path.as_posix() for path in _sibling('cache_key').input_paths(root)
                                 if path.suffix == '.mojo'} == self._known,
                                'render entry path census changed during historical operation')
                    require(resolver_unshadowed(root, self._resolver_paths,
                                **_render_lookup_args(self._resolver_paths, self._entries)),
                            'supplemental resolver surface changed during historical operation')
                    if self._scaled_resolver_paths:
                        require(self._scaled_resolver_paths == scaled_float32.NATIVE_CLOSURE,
                                'historical scaled native context changed')
                        current_known = _scaled_known_paths(root, _operation=self)
                        for paths, kind in self._discoveries:
                            if kind == 'known':
                                require(paths == current_known,
                                        'scaled source path census changed during historical operation')
                        require(resolver_unshadowed(root, self._scaled_resolver_paths,
                                                    **_scaled_lookup_args()),
                                'scaled native resolver changed during historical operation')
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
        self._clear_receipt()
        self._raw = types.MappingProxyType({})
        self._record_raw = None
        self._known = frozenset()
        self._production = frozenset()
        self._entries = ()
        self._native_contexts = ()
        self._resolver_paths = frozenset()
        self._scaled_resolver_paths = frozenset()
        self._executing = types.MappingProxyType({})
        self._observations.clear()
        self._discoveries.clear()
        self._owner_frame = None
        self._capturing = False
        self._checker_receipt = False


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
        self._scaled_resolver_paths = operation._scaled_resolver_paths
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
        self._scaled_resolver_paths = frozenset()
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
        raw = _regular(root, path).read_bytes()
        require(type(raw) is bytes, 'expected lane observation is not bytes')
        require(digest == source.token_sha256(_physical_text(raw)),
                'supplied and physical lane observation views differ')
        require(digest == AFTER_TOKEN_SHA256[path] or typed_boundary.is_current(path, raw),
                'unreviewed supplied successor source: ' + path)
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



def _shared_helper_bindings(root, *, paths=None, _snapshots=None, _inputs=None,
                            _input_owner=None, _operation=None):
    """Bind exact helper sources and tests in the owner's original byte image."""
    _operation_check(_operation, root)
    require((_inputs is None) == (_input_owner is None), 'incomplete helper input ownership')
    if _inputs is not None:
        require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs), 'invalid helper input view')
        _inputs._check(_input_owner, root)
    def observe(path):
        raw = (_observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)
               if _inputs is None else _inputs.raw(_input_owner, root, path))
        require(type(raw) is bytes, 'helper source is not physical bytes: ' + path)
        if _snapshots is not None:
            require(_snapshots.setdefault(path, raw) == raw,
                    'helper input changed after consumption: ' + path)
        return raw
    selected = shared_helpers.ARITHMETIC_PATHS if paths is None else paths
    require(type(selected) is tuple and bool(selected)
            and len(set(selected)) == len(selected)
            and set(selected) <= set(shared_helpers.SOURCE_PATHS), 'invalid helper input scope')
    sources = {path: observe(path) for path in selected}
    active = []
    for path, raw in sources.items():
        require(sha(raw) in (shared_helpers.BEFORE_SHA256[path], shared_helpers.AFTER_SHA256[path]),
                'unknown shared-helper endpoint: ' + path)
        if sha(raw) == shared_helpers.AFTER_SHA256[path]:
            active.append(path)
    if not active:
        return {}
    leaf = 'tools/carla_lane_oracle/shared_helper_contracts.py'
    providers = {name for path in active for name in shared_helpers.PROVIDER_PATHS[path]}
    tests = {name for path in active for name in shared_helpers.TEST_PATHS[path]}
    expected = {leaf: DEPENDENCY_TOOL_SHA256[leaf],
                **shared_helpers.package_inputs((*selected, *providers)),
                **{path: shared_helpers.PROVIDERS[path] for path in providers},
                **{path: shared_helpers.TESTS[path] for path in tests}}
    bound = {path: observe(path) for path in expected}
    typed_fixtures = {}
    for path, raw in bound.items():
        historical = raw
        if path in tests and typed_boundary.is_current(path, raw):
            # Arithmetic capture has no typed fixture edge. Supplemental native
            # fixtures use the complete current graph before exact provenance;
            # source/provider extraction identities remain unchanged.
            require(_snapshots is None, 'typed fixture entered arithmetic helper capture')
            historical = reviewed_typed_text(root, path, raw.decode('utf-8'),
                _operation=_operation, _inputs=_inputs, _input_owner=_input_owner).encode('utf-8')
            typed_fixtures[path] = raw
        require(sha(historical) == expected[path], 'shared-helper fixture changed: ' + path)
    texts = {path: raw.decode('utf-8') for path, raw in sources.items()}
    texts.update({path: bound[path].decode('utf-8') for path in providers})
    require(set(shared_helpers.verify_correspondence(texts)) == set(active),
            'shared-helper active endpoints differ')
    if typed_fixtures and _inputs is None and _operation is None:
        # Owned views retain their complete final sweep. A standalone typed
        # fixture must join the same physical image at the terminal root gate.
        verify(root, exact=True, _expected_sources=typed_fixtures)
    for path, raw in {**sources, **bound}.items():
        require(observe(path) == raw, 'shared-helper input changed during admission: ' + path)
    return {path: sha(raw) for path, raw in {**sources, **bound}.items()}


def shared_helper_proof_bindings(root, *, paths=None, include_roots=(), _inputs=None,
                                 _input_owner=None, _operation=None):
    """Admit supplemental edges without replacing any historical input bytes."""
    try:
        _operation_check(_operation, root)
        include_roots = tuple(include_roots)
        if _operation is not None:
            _operation_include_context(_operation, root, include_roots)
        require((_inputs is None) == (_input_owner is None), 'incomplete helper input ownership')
        if _inputs is not None:
            require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs), 'invalid helper input view')
            _inputs._check(_input_owner, root)
        # Existing owners check the complete executed image at capture and exit.
        # Retained adapters consume that image without starting another root gate.
        standalone = _inputs is None and (_operation is None or _operation._state != 'active')
        executing = (executing_checker_bindings() if standalone else
                     (_inputs._executing if _inputs is not None else _operation._executing))
        result = _shared_helper_bindings(root, paths=paths, _inputs=_inputs,
                                         _input_owner=_input_owner, _operation=_operation)
        fresh_image = None
        render_args = {}
        include_images = []
        if result:
            resolver_paths = {path for path in result if path.endswith('.mojo')}
            if any(path.startswith('render/') for path in resolver_paths):
                require(include_roots == () or (_inputs is None and (_operation is None
                        or _operation._kind == 'generated_receipt')),
                        'unowned helper include roots')
                entries, fresh_image = _helper_render_context(
                    root, _inputs=_inputs, _operation=_operation)
                render_args = _render_lookup_args(resolver_paths, entries)
                result[MIGRATION] = MIGRATION_SHA256
                for location in include_roots:
                    source_image = (fresh_image if fresh_image is not None else
                        {path: _operation._raw[path] for path in _operation._known})
                    stage_entries, stage_image = _include_entry_context(
                        location, source_image, _operation=_operation)
                    include_images.append((location, stage_image,
                        _render_lookup_args(resolver_paths, stage_entries)))
            require(resolver_unshadowed(root, resolver_paths, **render_args) and all(
                    resolver_unshadowed(location, resolver_paths | {path + '.cov-origin' for path in resolver_paths},
                        **(include_images[index][2] if include_images else {}))
                    for index, location in enumerate(include_roots)), 'shared-helper resolver surface changed')
            leaf = 'tools/carla_lane_oracle/shared_helper_contracts.py'
            require(result[leaf] == executing[leaf], 'shared-helper receipt lacks executing leaf')
            # The same owner's exit sweep must retain every supplemental
            # resolver premise consumed after its initial arithmetic capture.
            owners = (() if _inputs is None else (_inputs,))
            if _operation is not None:
                owners += (_operation,)
            if type(_inputs) is _BorrowedCacheInputs:
                owners += (_inputs._operation,)
            for owner in owners:
                observed = (owner._raw.keys() if owner._state == 'active' else
                    {path for location, path, value, mode in owner._receipt_observations
                     if location == owner._root}
                    if type(owner) is _InvariantInputs and owner._kind == 'generated_receipt' else
                    {path for path, value, mode in owner._observations})
                require(resolver_paths <= observed,
                        'helper resolver inputs were not observed by their owner')
                owner._resolver_paths = frozenset(owner._resolver_paths | resolver_paths)
                if owner._state == 'pending':
                    require(not owner._executing or dict(owner._executing) == executing,
                            'pending helper checker image changed')
                    owner._executing = types.MappingProxyType(dict(executing))
        if fresh_image is not None:
            _helper_entry_census_finish(root, fresh_image, _operation=_operation)
        if render_args:
            require(sha(_observe_bytes(root, MIGRATION, _regular(root, MIGRATION).read_bytes(),
                        _operation=_operation)) == MIGRATION_SHA256, 'render entry authority changed')
            for location, image, _ in include_images:
                _helper_entry_census_finish(location, image, _operation=_operation)
            require(resolver_unshadowed(root, resolver_paths, **render_args) and all(
                    resolver_unshadowed(location, resolver_paths | {path + '.cov-origin' for path in resolver_paths},
                        **include_images[index][2])
                    for index, location in enumerate(include_roots)), 'shared-helper final resolver surface changed')
        if standalone:
            require(executing_checker_bindings() == executing,
                    'shared-helper checker changed during admission')
        return result
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


def shared_helper_edges(root, *, paths=None, include_roots=(), _inputs=None,
                        _input_owner=None, _operation=None):
    """Return only live, physically admitted helper extraction descriptors."""
    bindings = shared_helper_proof_bindings(root, paths=paths, include_roots=include_roots,
        _inputs=_inputs, _input_owner=_input_owner, _operation=_operation)
    return shared_helpers.edges(tuple(path for path in shared_helpers.SOURCE_PATHS
        if bindings.get(path) == shared_helpers.AFTER_SHA256[path]))


def _scaled_known_paths(root, *, _operation=None):
    """Validate every discovered path before a set can hide a typed alias."""
    known = set()
    for path in _sibling('cache_key').input_paths(root):
        if path.suffix != '.mojo':
            continue
        name = path.as_posix()
        require(type(name) is str and _canonical_relative_text(name),
                'invalid scaled source path census item')
        known.add(name)
    _operation_known_paths(root, known, _operation=_operation)
    return known


def _scaled_lookup_args():
    """Only the pinned native witnesses establish this supplemental context."""
    return {'math_entries': frozenset(('.', *(str(Path(path).parent).casefold()
        for path in scaled_float32.NATIVE_TESTS)))}


def _scaled_float32_bindings(root, *, paths=None, _snapshots=None, _inputs=None,
                             _input_owner=None, _operation=None, _context=None):
    """Bind the exact math edge and its own native witness, not caller roots."""
    _operation_check(_operation, root)
    require((_inputs is None) == (_input_owner is None), 'incomplete scaled input ownership')
    if _inputs is not None:
        require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs), 'invalid scaled input view')
        _inputs._check(_input_owner, root)
        require(_operation is None or (type(_inputs) is _BorrowedCacheInputs
                and _operation is _inputs._operation), 'unjoined scaled input and operation owners')
    observed = {}

    def observe(path):
        raw = (_observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)
               if _inputs is None else _inputs.raw(_input_owner, root, path))
        require(type(raw) is bytes, 'scaled input is not physical bytes: ' + path)
        require(observed.setdefault(path, raw) == raw, 'scaled input changed after consumption: ' + path)
        if _snapshots is not None:
            require(_snapshots.setdefault(path, raw) == raw, 'scaled captured input changed: ' + path)
        return raw

    selected = scaled_float32.SOURCE_PATHS if paths is None else paths
    require(type(selected) is tuple and selected == scaled_float32.SOURCE_PATHS,
            'invalid scaled input scope')
    sources = {name: observe(name) for name in selected}
    active = scaled_float32.verify_sources({name: raw.decode('utf-8') for name, raw in sources.items()})
    if not active:
        return {}
    expected = {scaled_float32.LEAF: DEPENDENCY_TOOL_SHA256[scaled_float32.LEAF],
                **scaled_float32.PACKAGE_INPUTS, **scaled_float32.PROVIDER_INPUTS,
                **scaled_float32.TESTS}
    for name, digest in expected.items():
        require(sha(observe(name)) == digest, 'scaled correctness input changed: ' + name)
    # Source identity and its actual main declaration jointly establish the
    # fixed witness entry context. No production entry census is inferred.
    affected = _sibling('affected')
    entries = tuple(affected.entry_directories({name: _physical_text(observe(name))
                                              for name in scaled_float32.NATIVE_TESTS}))
    require(entries == tuple(sorted({str(Path(name).parent)
                                     for name in scaled_float32.NATIVE_TESTS})),
            'scaled native entry context changed')
    known = _scaled_known_paths(root, _operation=_operation)
    if _inputs is not None:
        require(known == _inputs._known, 'scaled captured source path census changed')
    found, pending = set(), list(scaled_float32.NATIVE_TESTS)
    while pending:
        name = pending.pop()
        if name in found:
            continue
        require(name in known, 'scaled native dependency missing: ' + name)
        found.add(name)
        for imported in affected.imported_names(_physical_text(observe(name))):
            pending.extend(affected.resolve(imported, name, known, entries=entries))
    require(found == scaled_float32.NATIVE_CLOSURE, 'scaled native import closure changed')
    for name, raw in tuple(observed.items()):
        require(observe(name) == raw, 'scaled input changed during admission: ' + name)
    final_known = _scaled_known_paths(root, _operation=_operation)
    require(final_known == known, 'scaled source path census changed during admission')
    if _context is not None:
        require(type(_context) is dict and not _context, 'invalid scaled source context output')
        _context['known'] = frozenset(known)
    return {name: sha(raw) for name, raw in observed.items()}


def scaled_float32_proof_bindings(root, *, paths=None, include_roots=(), _inputs=None,
                                   _input_owner=None, _operation=None):
    """Admit one source substitution and its fixed native context, never PASS."""
    failure_operation = _operation
    try:
        _operation_check(_operation, root)
        require((_inputs is None) == (_input_owner is None), 'incomplete scaled input ownership')
        if _inputs is not None:
            require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs), 'invalid scaled input view')
            _inputs._check(_input_owner, root)
            if type(_inputs) is _BorrowedCacheInputs:
                # Only a validated real lease may identify its failure owner.
                failure_operation = _inputs._operation
            require(_operation is None or (type(_inputs) is _BorrowedCacheInputs
                    and _operation is _inputs._operation), 'unjoined scaled input and operation owners')
        include_roots = tuple(include_roots)
        if _operation is not None:
            _operation_include_context(_operation, root, include_roots)
        require(include_roots == () or (_inputs is None and (_operation is None
                or _operation._kind == 'generated_receipt')),
                'unowned scaled include roots')
        standalone = _inputs is None and (_operation is None or _operation._state != 'active')
        executing = (executing_checker_bindings() if standalone else
                     (_inputs._executing if _inputs is not None else _operation._executing))
        context = {}
        result = _scaled_float32_bindings(root, paths=paths, _inputs=_inputs,
            _input_owner=_input_owner, _operation=_operation, _context=context)
        if result:
            require(result[scaled_float32.LEAF] == executing[scaled_float32.LEAF],
                    'scaled receipt lacks executing leaf')
            resolver_paths = {name for name in result if name.endswith('.mojo')}
            require(resolver_paths == scaled_float32.NATIVE_CLOSURE,
                    'scaled resolver scope differs from native closure')
            include_paths = resolver_paths | {name + '.cov-origin' for name in resolver_paths}
            require(resolver_unshadowed(root, resolver_paths, **_scaled_lookup_args()) and all(
                resolver_unshadowed(location, include_paths, **_scaled_lookup_args())
                for location in include_roots), 'scaled resolver surface changed')
            owners = (() if _inputs is None else (_inputs,))
            if _operation is not None:
                owners += (_operation,)
            if type(_inputs) is _BorrowedCacheInputs:
                owners += (_inputs._operation,)
            for owner in owners:
                observed = (owner._raw.keys() if owner._state == 'active' else
                    {path for location, path, value, mode in owner._receipt_observations
                     if location == owner._root}
                    if type(owner) is _InvariantInputs and owner._kind == 'generated_receipt' else
                    {name for name, value, mode in owner._observations})
                require(result.keys() <= observed, 'scaled inputs were not observed by their owner')
                # This native-only context must never narrow or replace the
                # owner's existing production/helper resolver obligations.
                owner._scaled_resolver_paths = frozenset(resolver_paths)
                if owner._state == 'pending':
                    require(not owner._executing or dict(owner._executing) == executing,
                            'pending scaled checker image changed')
                    owner._executing = types.MappingProxyType(dict(executing))
            for name, expected in result.items():
                raw = (_observe_bytes(root, name, _regular(root, name).read_bytes(), _operation=_operation)
                       if _inputs is None else _inputs.raw(_input_owner, root, name))
                require(type(raw) is bytes and sha(raw) == expected,
                        'scaled input changed before receipt: ' + name)
            require(resolver_unshadowed(root, resolver_paths, **_scaled_lookup_args()) and all(
                resolver_unshadowed(location, include_paths, **_scaled_lookup_args())
                for location in include_roots), 'scaled final resolver surface changed')
            final_known = _scaled_known_paths(root, _operation=_operation)
            require(final_known == context['known'], 'scaled source path census changed before receipt')
        if standalone:
            require(executing_checker_bindings() == executing, 'scaled checker changed during admission')
        return result
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(failure_operation, error)


def scaled_float32_edges(root, *, paths=None, _inputs=None, _input_owner=None, _operation=None):
    """Return only the live math edge admitted through the same physical owner."""
    bindings = scaled_float32_proof_bindings(root, paths=paths, _inputs=_inputs,
        _input_owner=_input_owner, _operation=_operation)
    return scaled_float32.edges(tuple(name for name in scaled_float32.SOURCE_PATHS
        if bindings.get(name) == scaled_float32.AFTER_SHA256[name]))


def _runtime_view_bindings(root, *, _snapshots=None, _operation=None):
    """Bind the merged runtime-view authority and every consumed fixture."""
    raw = _observe_bytes(root, runtime_view.MIGRATION,
        _regular(root, runtime_view.MIGRATION).read_bytes(), _operation=_operation)
    require(sha(raw) == runtime_view.MIGRATION_SHA256,
            'runtime view record changed during admission')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    runtime_view.checked_steps(record)
    leaf = 'tools/carla_lane_oracle/runtime_view_contracts.py'
    expected_inputs = {runtime_view.MIGRATION: runtime_view.MIGRATION_SHA256,
                       leaf: DEPENDENCY_TOOL_SHA256[leaf],
                       **record['correctness_tests']}
    result = {}
    for path, expected in expected_inputs.items():
        value = _observe_bytes(root, path, _regular(root, path).read_bytes(),
                               _operation=_operation)
        require(sha(_historical_typed_text(path, value.decode('utf-8'))) == expected,
                'runtime view bound input changed: ' + path)
        if _snapshots is not None:
            require(_snapshots.setdefault(path, value) == value,
                    'runtime view input changed after consumption: ' + path)
        result[path] = sha(value)
    return result



def _station_bindings(root, *, _snapshots=None, _operation=None):
    """Admit the supplemental Map edges without replacing any live image bytes.

    The station edge (#302) and its deviation successor (#685) each have exact
    endpoints, a fixed inverse, an executing leaf and bound correctness tests.
    """
    raw = _observe_bytes(root, station.MODULE,
        _regular(root, station.MODULE).read_bytes(), _operation=_operation)
    if _snapshots is not None:
        require(_snapshots.setdefault(station.MODULE, raw) == raw,
                'Map changed before station admission')
    historical = _historical_typed_text(station.MODULE, raw.decode('utf-8'))
    if sha(historical) == station.BEFORE_SHA256:
        require(source.token_sha256(historical) == station.BEFORE_TOKEN_SHA256,
                'historical fifth Map tokens changed')
        return {}
    require(sha(historical) in (station.AFTER_SHA256, deviation.AFTER_SHA256),
            'unknown complete station Map bytes')
    station.predecessor_source(deviation.station_source(historical))
    result = {station.MODULE: sha(raw)}
    leaf = 'tools/carla_lane_oracle/map_station_contracts.py'
    fixtures = {leaf: DEPENDENCY_TOOL_SHA256[leaf], **station.TESTS}
    if sha(historical) == deviation.AFTER_SHA256:
        deviation_leaf = 'tools/carla_lane_oracle/map_deviation_contracts.py'
        fixtures.update({deviation_leaf: DEPENDENCY_TOOL_SHA256[deviation_leaf], **deviation.TESTS})
    for path, expected in fixtures.items():
        value = _observe_bytes(root, path, _regular(root, path).read_bytes(),
                               _operation=_operation)
        require(sha(_historical_typed_text(path, value.decode('utf-8'))) == expected,
                'station correctness fixture changed: ' + path)
        if _snapshots is not None:
            require(_snapshots.setdefault(path, value) == value,
                    'station fixture changed after consumption: ' + path)
        result[path] = sha(value)
    require(_observe_bytes(root, station.MODULE,
            _regular(root, station.MODULE).read_bytes(), _operation=_operation) == raw,
            'Map changed during station admission')
    return result


def _witness_format_bindings(root, *, _snapshots=None, _operation=None):
    """Admit four fixed witness formats without acquiring production context."""
    try:
        _operation_check(_operation, root)
        image, result, active = {}, {}, False
        for path in witness_format.SOURCE_PATHS:
            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(),
                                 _operation=_operation)
            require(type(raw) is bytes, 'witness is not physical bytes: ' + path)
            if _snapshots is not None:
                require(_snapshots.setdefault(path, raw) == raw,
                        'witness changed before format admission: ' + path)
            image[path] = raw
            historical = _historical_typed_text(path, raw.decode('utf-8'))
            digest = sha(historical)
            if digest == witness_format.BEFORE_SHA256[path]:
                require(source.token_sha256(historical) ==
                        witness_format.BEFORE_TOKEN_SHA256[path],
                        'historical witness tokens changed: ' + path)
            else:
                witness_format.predecessor_source(path, historical)
                active = True
            result[path] = sha(raw)
        if active:
            leaf = 'tools/carla_lane_oracle/witness_format_contracts.py'
            for path, expected in {leaf: DEPENDENCY_TOOL_SHA256[leaf],
                                   **witness_format.BOUND_INPUTS}.items():
                raw = _observe_bytes(root, path, _regular(root, path).read_bytes(),
                                     _operation=_operation)
                require(type(raw) is bytes and sha(_historical_typed_text(path, raw.decode('utf-8'))) == expected,
                        'witness-format proof input changed: ' + path)
                if _snapshots is not None:
                    require(_snapshots.setdefault(path, raw) == raw,
                            'witness-format input changed after consumption: ' + path)
                image[path] = raw
                result[path] = sha(raw)
        for path, expected in image.items():
            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(),
                                 _operation=_operation)
            require(type(raw) is bytes and raw == expected,
                    'witness-format input changed during admission: ' + path)
        return result if active else {}
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


def _historical_typed_text(path, text):
    """Pure named provenance projection; never replace a captured input."""
    return typed_boundary.historical_source(str(path), text)


def _typed_boundary_bindings(root, *, _snapshots=None, _operation=None):
    """Bind the complete new source graph and current native closure once."""
    try:
        _operation_check(_operation, root)
        marker = 'extensions/carla/polynomial.mojo'
        marker_raw = _observe_bytes(root, marker, _regular(root, marker).read_bytes(),
                                    _operation=_operation)
        if not typed_boundary.is_current(marker, marker_raw):
            # A local-cubic graph cannot borrow historical polynomial storage.
            # Each exact semantic endpoint must advance in the same operation.
            for path in conditioned_cubic.SOURCE_PATHS:
                raw = marker_raw if path == marker else _observe_bytes(
                    root, path, _regular(root, path).read_bytes(), _operation=_operation)
                require(not typed_boundary.is_current(path, raw),
                        'mixed historical and conditioned source graph: ' + path)
            return {}
        image = {}
        for path in typed_boundary.SOURCE_PATHS:
            raw = marker_raw if path == marker else _observe_bytes(
                root, path, _regular(root, path).read_bytes(), _operation=_operation)
            require(type(raw) is bytes, 'typed source is not physical bytes: ' + path)
            image[path] = raw
        if (type(_operation) is _InvariantInputs
                and _operation._kind == 'generated_receipt'
                and _operation._state == 'active' and not _operation._capturing):
            # Initial publication admitted this entire immutable source image.
            # Every physical read above still joins it through _observe_bytes;
            # authenticate live authority without replaying source semantics.
            typed_boundary.verify_authority()
            conditioned_cubic.verify_authority()
        else:
            typed_boundary.verify_sources({path: raw.decode('utf-8') for path, raw in image.items()})
        leaves = ('tools/carla_lane_oracle/typed_boundary_contracts.py',
                  'tools/carla_lane_oracle/conditioned_cubic_contracts.py')
        conditioned_inputs = {}
        for path, historical_digest in conditioned_cubic.BINDING_INPUTS.items():
            if path in typed_boundary.EDGES:
                edge = typed_boundary.edge(path)
                require(edge['before_sha256'] == historical_digest,
                        'typed input misses fixed conditioned witness/provider: ' + path)
                # The semantic admission reconstructed this complete predecessor.
                # Receipts bind current formatted bytes, not the old witness SHA.
                conditioned_inputs[path] = edge['after_sha256']
            else:
                conditioned_inputs[path] = historical_digest
        expected = {**typed_boundary.CURRENT_DEPENDENCIES, **typed_boundary.NEW_INPUTS, **typed_boundary.TESTS,
                    **typed_boundary.BINDING_INPUTS, **conditioned_inputs,
                    **{path: DEPENDENCY_TOOL_SHA256[path] for path in leaves}}
        for path, digest in expected.items():
            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)
            require(sha(raw) == digest, 'typed boundary bound input changed: ' + path)
            typed_boundary.verify_binding_successor(path, raw)
            require(path not in image or image[path] == raw, 'typed input changed after source admission: ' + path)
            image[path] = raw
        for path, raw in image.items():
            if _snapshots is not None:
                require(_snapshots.setdefault(path, raw) == raw, 'typed input changed after consumption: ' + path)
            require(_observe_bytes(root, path, _regular(root, path).read_bytes(),
                                   _operation=_operation) == raw,
                    'typed input changed during admission: ' + path)
        return {path: sha(raw) for path, raw in image.items()}
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


def reviewed_typed_text(root, path, text, *, _operation=None, _inputs=None, _input_owner=None):
    """Admit physical current bytes before returning historical provenance."""
    path = str(path)
    edge = typed_boundary.EDGES.get(path)
    if edge is None:
        return text
    _public_admission = None
    try:
        if _inputs is None and _operation is None:
            _public_admission = _public_admission_for(root)
        if _inputs is not None:
            require(type(_inputs) in (_CacheInputs, _BorrowedCacheInputs),
                    'invalid typed source owner')
            if type(_inputs) is _BorrowedCacheInputs:
                # Authenticate the lease before using its operation. Its
                # canonical check poisons the consumed owner for bad tokens.
                _BorrowedCacheInputs._check(_inputs, _input_owner, root)
                explicit_operation = _operation
                _operation = _inputs._operation
                require(explicit_operation is None or explicit_operation is _operation,
                        'typed source operation differs from borrowed owner')
        require((_inputs is None) == (_input_owner is None), 'incomplete typed input owner')
        if not (typed_boundary.is_current(path, text) or
                source.token_sha256(text) == edge['after_token_sha256']):
            return text
        _operation_check(_operation, root)
        raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)
        require(typed_boundary.is_current(path, raw),
                'typed physical input is not the exact reviewed endpoint: ' + path)
        physical_text = raw.decode('utf-8')
        require(type(text) is str and source.token_sha256(text) == source.token_sha256(physical_text),
                'supplied typed source differs from physical input: ' + path)
        _observe_text(root, path, text, _operation=_operation, mode='physical',
                      supplied=True, _checked_raw=raw)
        if _inputs is not None:
            require(_inputs.raw(_input_owner, root, path) == raw, 'typed owner image changed: ' + path)
        elif _operation is None:
            if _public_admission is None or _public_admission._state == 'pending':
                verify(root, exact=True)
            if _public_admission is not None:
                _public_admission.project(root, path, raw)
        else:
            _operation_record(_operation, root, exact=True)
        require(_observe_bytes(root, path, _regular(root, path).read_bytes(),
                               _operation=_operation) == raw,
                'typed source changed during provenance reconstruction: ' + path)
        return _historical_typed_text(path, physical_text)
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        if _public_admission is not None:
            _public_admission.fail()
        _operation_fail(_operation, error)


def verify(root, *, exact=False, include_roots=(), _expected_lane_raw=None, _capture=None, _expected_sources=None):
    """Check actual complete current endpoints and all premises without caches."""
    root = Path(root)
    _public_admission = _public_admission_for(root, publication=True) if include_roots == () else None
    try:
        if _capture is not None:
            generated = type(_capture) is _InvariantInputs and _capture._kind == 'generated_receipt'
            require(type(_capture) in (_CacheInputs, _InvariantInputs) and not exact
                    and (include_roots == () or (generated and tuple(
                        _absolute_root_text(path) for path in include_roots) == _capture._include_roots)),
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
        if _expected_sources is not None:
            require(_capture is None and type(_expected_sources) is dict,
                    'invalid supplied source capture request')
            for path, expected in _expected_sources.items():
                require(type(path) is str and _canonical_relative_text(path)
                        and type(expected) is bytes, 'invalid supplied source capture value')
                physical = _regular(root, path)
                if path not in snapshots:
                    snapshots[path] = physical.read_bytes()
                require(snapshots[path] == expected,
                        'supplied source observation changed before admission: ' + path)
        typed_bindings = _typed_boundary_bindings(root, _snapshots=snapshots,
            _operation=_capture if type(_capture) is _InvariantInputs else None)
        for path in SOURCE_PATHS:
            raw = snapshots[path]
            # Exact provenance retains physical line endings. Universal-newline
            # decoding belongs only to the separate semantic source view.
            exact_text = _historical_typed_text(path, raw.decode('utf-8'))
            text = _physical_text(exact_text.encode('utf-8'))
            supplied_view = (root / path).read_text(encoding='utf-8')
            require(source.token_sha256(supplied_view) == source.token_sha256(_physical_text(raw)),
                    'supplied and physical source views differ: ' + path)
            item = record['sources'][path]
            require((not exact or sha(exact_text) == AFTER_SHA256[path])
                    and source.token_sha256(text) == item['after_token_sha256']
                    and source.token_sha256(text) == item['after_token_sha256'],
                    'unreviewed complete live endpoint: ' + path)
            if path == SOURCE_PATHS[2]:
                descriptor = item['center_extraction']
                verify_center_correspondence(descriptor['intermediate_source'], text, descriptor)
            verify_observations(path, text, item)
            # Fixed exact inverse objects are not a normalization API. Only
            # sealed recorded endpoints may be inverted, after live checks.
            reverse_exact(path, item['after_source'], item)
        scaled_bindings = _scaled_float32_bindings(root, _snapshots=snapshots)
        scaled_edges = scaled_float32.edges(tuple(name for name in scaled_float32.SOURCE_PATHS
            if scaled_bindings.get(name) == scaled_float32.AFTER_SHA256[name]))
        helper_bindings = _shared_helper_bindings(root, _snapshots=snapshots)
        helper_edges = shared_helpers.edges(tuple(
            path for path in shared_helpers.SOURCE_PATHS
            if helper_bindings.get(path) == shared_helpers.AFTER_SHA256[path]))
        helper_closure = ({'loaders/utf8.mojo'} if 'loaders/xml.mojo' in helper_edges else set())
        resolver_paths = (set(record['dependency_inventory']) | set(record['inventory'])
                          | set(record['native_dependency_inventory']) | helper_closure
                          | {path for path in helper_bindings if path.endswith('.mojo')}
                          | {path for path in scaled_bindings if path.endswith('.mojo')}
                          | (set(typed_boundary.CURRENT_DEPENDENCIES) if typed_bindings else set())
                          | (set(_capture._resolver_paths) if _capture is not None else set()))
        # Coverage origin files cannot enter Mojo module lookup. Admit only
        # exact sidecar coordinates of reviewed Mojo inputs at include roots;
        # generation_origins and capture verification still bind their bytes.
        include_resolver_paths = resolver_paths | {path + '.cov-origin'
            for path in resolver_paths if path.endswith('.mojo')}
        require(resolver_unshadowed(root, resolver_paths,
                    **_render_lookup_args(resolver_paths, record['entry_directories'])),
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
        include_images = []
        for location in include_roots:
            stage_entries, stage_image = _include_entry_context(
                location, {path: snapshots[path] for path in known})
            stage_args = _render_lookup_args(resolver_paths, stage_entries)
            require(resolver_unshadowed(location, include_resolver_paths, **stage_args),
                    'unreviewed include resolver surface')
            include_images.append((location, stage_image, stage_args))
        require(dependency_inventory(root, roots=(*SOURCE_PATHS, *record['inventory']), entries=entries,
                                     _known=known, _snapshots=snapshots)
                == (set(typed_boundary.PRODUCTION_CLOSURE) if typed_bindings else
                    set(record['dependency_inventory']) | helper_closure), 'production import inventory changed')
        native_found = _native_dependency_inventory(root, witnesses=NATIVE_WITNESSES,
            _known=known, _snapshots=snapshots)
        require(native_found == (set(typed_boundary.NATIVE_CLOSURE) if typed_bindings else
                set(record['native_dependency_inventory']) | helper_closure),
                'native witness import inventory changed')
        if typed_bindings:
            current_native = set()
            test_paths = tuple(path for path in typed_boundary.TESTS if path.endswith('.mojo'))
            for parent in sorted({str(Path(path).parent) for path in test_paths}):
                current_native.update(dependency_inventory(root,
                    roots=tuple(path for path in test_paths if str(Path(path).parent) == parent),
                    entries=(parent,), _known=known, _snapshots=snapshots))
            require(current_native == set(typed_boundary.TYPED_NATIVE_CLOSURE),
                    'typed native test import inventory changed')
            current_production = dependency_inventory(root,
                roots=tuple(path for path in (*typed_boundary.SOURCE_PATHS, *typed_boundary.NEW_INPUTS)
                    if path.endswith('.mojo') and not path.startswith(('tests/', 'tools/', 'examples/', 'bench/'))),
                entries=entries, _known=known, _snapshots=snapshots)
            require(current_production == set(typed_boundary.TYPED_PRODUCTION_CLOSURE),
                    'typed production import inventory changed')
        ledger_raw = _regular(root, CONSUMER_LEDGER).read_bytes()
        require(sha(ledger_raw) == CONSUMER_LEDGER_SHA256, 'unreviewed consumer ledger')
        snapshots[CONSUMER_LEDGER] = ledger_raw
        runtime_bindings = _runtime_view_bindings(root, _snapshots=snapshots)
        station_bindings = _station_bindings(root, _snapshots=snapshots)
        witness_bindings = _witness_format_bindings(root, _snapshots=snapshots,
            _operation=_capture if type(_capture) is _InvariantInputs else None)
        bound = {}
        for group in BOUND_GROUPS:
            for path, expected in record[group].items():
                raw = _regular(root, path).read_bytes()
                previous = snapshots.setdefault(path, raw)
                require(previous == raw, 'bound input changed after consumption: ' + path)
                if path == station.MODULE and station_bindings:
                    require(group in ('unchanged_inputs', 'native_dependency_inputs')
                            and expected == station.BEFORE_SHA256,
                            'station edge does not extend this immutable Map premise')
                    expected = station_bindings[path]
                if path in helper_edges:
                    require(group in ('unchanged_inputs', 'native_dependency_inputs')
                            and expected == helper_edges[path]['before_sha256'],
                            'helper edge does not extend immutable input: ' + path)
                    expected = helper_edges[path]['after_sha256']
                if path in scaled_edges:
                    require(group in ('unchanged_inputs', 'native_dependency_inputs')
                            and expected == scaled_edges[path]['before_sha256'],
                            'scaled edge does not extend immutable input: ' + path)
                    expected = scaled_edges[path]['after_sha256']
                if path in witness_bindings:
                    require(path in witness_format.SOURCE_PATHS
                            and group in ('native_witnesses', 'native_dependency_inputs')
                            and expected == witness_format.BEFORE_SHA256[path],
                            'format edge does not extend immutable witness: ' + path)
                    expected = witness_bindings[path]
                historical = _historical_typed_text(path, raw.decode('utf-8')).encode('utf-8') if path in typed_boundary.EDGES and typed_bindings else raw
                if historical != raw and expected == sha(raw):
                    expected = sha(historical)
                require(sha(historical) == expected, 'unchanged premise, record or fixture changed: ' + path)
                bound[path] = raw
        require(native_support_mapping(root, raw=bound['tools/native_test_support.py']) == record['native_support_mapping'], 'native fixture mapping changed')
        production = set() if _capture is not None or _public_admission is not None else None
        observed_inventory = (inventory(root, _snapshots=snapshots) if production is None else
                              inventory(root, _snapshots=snapshots, _production=production))
        expected_inventory = dict(record['inventory'])
        if station_bindings:
            require(expected_inventory.get(station.MODULE) ==
                    {'tokens_sha256': station.BEFORE_TOKEN_SHA256},
                    'station inventory does not start at fifth Map endpoint')
            expected_inventory[station.MODULE] = {'tokens_sha256': (
                deviation.AFTER_TOKEN_SHA256 if station_bindings[station.MODULE] == deviation.AFTER_SHA256
                else station.AFTER_TOKEN_SHA256)}
        if typed_bindings:
            expected_inventory = typed_boundary.INVENTORY
        require(observed_inventory == expected_inventory, 'production caller/use inventory changed')
        for path, raw in {**bound, **snapshots}.items():
            require(_regular(root, path).read_bytes() == raw, 'input changed during verification: ' + path)
        require({p.as_posix() for p in _sibling('cache_key').input_paths(root) if p.suffix == '.mojo'} == known,
                'source path inventory changed during verification')
        for location, image, _ in include_images:
            _helper_entry_census_finish(location, image)
        require(resolver_unshadowed(root, resolver_paths,
                    **_render_lookup_args(resolver_paths, record['entry_directories']))
                and all(resolver_unshadowed(location, include_resolver_paths, **stage_args)
                        for location, _, stage_args in include_images),
                'resolver surface changed during verification')
        if _capture is not None:
            _regular(root, MIGRATION)
        authority_raw = (root / MIGRATION).read_bytes()
        require(sha(authority_raw) == MIGRATION_SHA256, 'record changed during verification')
        require(executing_checker_bindings() == executing, 'executing checker changed during verification')
        if _capture is not None:
            if type(_capture) is _InvariantInputs and _capture._kind == 'generated_receipt':
                receipt_bindings = {MIGRATION: MIGRATION_SHA256,
                                    CONSUMER_LEDGER: CONSUMER_LEDGER_SHA256, **executing}
                receipt_bindings.update({path: item['after_sha256'] for path, item in record['sources'].items()})
                for group in BOUND_GROUPS:
                    receipt_bindings.update(record[group])
                for family in (station_bindings, scaled_bindings, typed_bindings,
                               witness_bindings, runtime_bindings, helper_bindings):
                    receipt_bindings.update(family)
                if scaled_bindings:
                    scaled_paths = frozenset(name for name in scaled_bindings if name.endswith('.mojo'))
                    require(scaled_paths == scaled_float32.NATIVE_CLOSURE
                            and _scaled_known_paths(root) == known,
                            'generated scaled native context differs from source admission')
                    scaled_include_paths = scaled_paths | {name + '.cov-origin' for name in scaled_paths}
                    require(resolver_unshadowed(root, scaled_paths, **_scaled_lookup_args())
                            and all(resolver_unshadowed(location, scaled_include_paths,
                                                       **_scaled_lookup_args())
                                    for location in include_roots),
                            'generated scaled native resolver changed during admission')
                    _capture._scaled_resolver_paths = scaled_paths
                _capture._publish(root, snapshots, authority_raw, known, production, entries,
                    resolver_paths, executing, receipt_bindings=receipt_bindings,
                    include_images=tuple(include_images))
            else:
                _capture._publish(root, snapshots, authority_raw, known, production, entries,
                                  resolver_paths, executing)
        if _public_admission is not None:
            public_image = _public_admission._publication_inputs(root, snapshots)
            if _public_admission._state == 'pending':
                if scaled_bindings:
                    _public_admission._scaled_resolver_paths = frozenset(
                        path for path in scaled_bindings if path.endswith('.mojo'))
                _public_admission._publish(root, public_image, authority_raw, known,
                    production, entries, resolver_paths, executing)
        return record
    except ContractError:
        if _public_admission is not None:
            _public_admission.fail()
        raise
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, SyntaxError) as error:
        if _public_admission is not None:
            _public_admission.fail()
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
    _public_admission = None
    try:
        if _operation is None:
            _public_admission = _public_admission_for(root)
        path = str(path)
        if text is None:
            text = _observe_text(root, path, _regular(root, path).read_text(encoding='utf-8'),
                                 _operation=_operation, mode='physical')
        if path in SOURCE_PATHS and typed_boundary.is_current(path, text):
            raw = _observe_bytes(root, path, _regular(root, path).read_bytes(), _operation=_operation)
            require(typed_boundary.is_current(path, raw)
                    and source.token_sha256(text) == source.token_sha256(_physical_text(raw)),
                    'supplied typed successor differs from physical input: ' + path)
            record = (verify(root) if _operation is None else _operation_record(_operation, root))
            require(_observe_bytes(root, path, _regular(root, path).read_bytes(),
                                   _operation=_operation) == raw,
                    'typed successor changed during admission: ' + path)
            item = record['sources'][path]
            return reverse_exact(path, item['after_source'], item)
        text = reviewed_typed_text(root, path, text, _operation=_operation)
        if path not in SOURCE_PATHS or source.token_sha256(text) == BEFORE_TOKEN_SHA256[path]:
            return text
        require(source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unreviewed supplied successor source: ' + path)
        return predecessor_source(root, path, _operation=_operation)
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        if _public_admission is not None:
            _public_admission.fail()
        _operation_fail(_operation, error)



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
        require(digest == AFTER_TOKEN_SHA256[path] or typed_boundary.is_current(path, expected_raw),
                'unreviewed supplied successor source: ' + path)
        road = 'extensions/carla/road.mojo'
        road_raw = _regular(root, road).read_bytes()
        require(type(road_raw) is bytes, 'road observation is not bytes')
        _observe_bytes(root, road, road_raw, _operation=_operation)
        _observe_text(root, path, text, _operation=_operation, mode='physical', supplied=True)
        record = (verify(root, _expected_lane_raw=expected_raw) if _operation is None else
                  _operation_record(_operation, root, expected_lane_raw=expected_raw))
        require(sha(_historical_typed_text(road, road_raw.decode('utf-8'))) == record['unchanged_inputs'][road],
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
    physical_inputs = {}
    for path, text in texts.items():
        raw = _regular(root, path).read_bytes()
        require(source.token_sha256(text) == source.token_sha256(_physical_text(raw)),
                'supplied successor source differs from physical input: ' + path)
        physical_inputs[path] = raw
    record = verify(root, _expected_sources=physical_inputs)
    result = dict(texts)
    # A successor operation may not mix a historical supplied endpoint with
    # current ones, or smuggle an unrelated fabricated supplied source view.
    for path, text in texts.items():
        physical = _regular(root, path).read_bytes()
        require(physical == physical_inputs[path],
                'supplied successor physical input changed during admission: ' + path)
        require(source.token_sha256(text) == source.token_sha256(_physical_text(physical)),
                'supplied successor source differs from physical input: ' + path)
        # Only canonical physical bytes enter the exact typed inverse; caller
        # comments have already been compared by the public supplied-view rule.
        text = _historical_typed_text(path, _physical_text(physical))
        if path in SOURCE_PATHS:
            item = record['sources'][path]
            require(source.token_sha256(text) == item['after_token_sha256'],
                    'mixed or unreviewed supplied successor source: ' + path)
            result[path] = reverse_exact(path, item['after_source'], item)
        else:
            raw = _regular(root, path).read_bytes()
            require(raw == physical and source.token_sha256(text) == source.token_sha256(_historical_typed_text(path, _physical_text(raw))),
                    'unreviewed unrelated supplied source: ' + path)
            result[path] = text
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
            typed_current = typed_boundary.is_current(path, text)
            text = _historical_typed_text(path, text)
            changed = typed_current or any(declaration_sha256(text, name) not in expected
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


def reviewed_lane_before_center_text(root, text=None, *, _operation=None):
    path = SOURCE_PATHS[2]
    supplied_raw = None
    if text is not None:
        supplied_raw = _observe_bytes(root, path, _regular(root, path).read_bytes(),
                                      _operation=_operation)
        require(source.token_sha256(text) == source.token_sha256(_physical_text(supplied_raw)),
                'unreviewed supplied center source')
    item = (verify(root, _expected_lane_raw=supplied_raw) if _operation is None else
            _operation_record(_operation, root, expected_lane_raw=supplied_raw))['sources'][path]
    if supplied_raw is not None:
        require(source.token_sha256(_historical_typed_text(path, _physical_text(supplied_raw)))
                == AFTER_TOKEN_SHA256[path], 'unreviewed supplied center source')
        require(_observe_bytes(root, path, _regular(root, path).read_bytes(),
                               _operation=_operation) == supplied_raw,
                'supplied center physical input changed during admission')
    return reverse_center_exact(item['after_source'], item)


def verified_edges(root, *, include_roots=(), _operation=None):
    record = (verify(root, exact=True, include_roots=include_roots) if _operation is None else
              _operation_record(_operation, root, exact=True, include_roots=include_roots))
    return {path: {'path': path, **{field: item[field] for field in
            ('before_sha256', 'after_sha256', 'before_token_sha256', 'after_token_sha256')}}
            for path, item in record['sources'].items()}


def typed_successor_edges(root, *, _operation=None):
    """Return explicit current edges, separately from immutable old records."""
    try:
        marker = 'extensions/carla/polynomial.mojo'
        raw = _observe_bytes(root, marker, _regular(root, marker).read_bytes(),
                             _operation=_operation)
        if not typed_boundary.is_current(marker, raw):
            return {}
        if _operation is None:
            verify(root, exact=True)
        else:
            _operation_record(_operation, root, exact=True)
        result = {}
        for path in typed_boundary.SOURCE_PATHS:
            current = _observe_bytes(root, path, _regular(root, path).read_bytes(),
                                     _operation=_operation)
            require(typed_boundary.is_current(path, current),
                    'typed successor physical endpoint changed: ' + path)
            edge = typed_boundary.edge(path)
            edge['scope'] = 'explicit historical provenance; current typed API admission'
            if path in conditioned_cubic.SOURCE_PATHS:
                edge['conditioned_graph'] = {
                    'before_sha256': conditioned_cubic.BEFORE_SHA256[path],
                    'after_sha256': conditioned_cubic.AFTER_SHA256[path],
                    'scope': 'new local-coefficient graph; no scalar bit-equivalence claim'}
            result[path] = edge
        return result
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


def digest_edges(root, *, include_roots=()):
    return verified_edges(root, include_roots=include_roots)


def extends_digest(root, path, before, after, *, include_roots=()):
    if path not in SOURCE_PATHS or before != BEFORE_SHA256[path] or after != AFTER_SHA256.get(path):
        return False
    edge = verified_edges(root, include_roots=include_roots)[path]
    return edge['before_sha256'] == before and edge['after_sha256'] == after


def station_proof_bindings(root, *, _operation=None):
    """Bind the same executed leaf even in historical-cleanup compositions."""
    try:
        executing = executing_checker_bindings()
        result = _station_bindings(root, _operation=_operation)
        if result.get(station.MODULE) == typed_boundary.EDGES[station.MODULE]['after_sha256']:
            # The public typed receipt requires the complete current graph.
            # Keep _station_bindings itself nonrecursive for verify's capture.
            if _operation is None:
                verify(root, exact=True)
            else:
                _operation_record(_operation, root, exact=True)
            result.update(_typed_boundary_bindings(root, _operation=_operation))
        leaf = 'tools/carla_lane_oracle/map_station_contracts.py'
        require(result.get(leaf) == executing[leaf],
                'station receipt lacks its actual executing leaf')
        deviation_leaf = 'tools/carla_lane_oracle/map_deviation_contracts.py'
        require(result.get(station.MODULE) != deviation.AFTER_SHA256
                or result.get(deviation_leaf) == executing[deviation_leaf],
                'deviation receipt lacks its actual executing leaf')
        require(executing_checker_bindings() == executing,
                'station receipt checker changed during verification')
        return result
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


def proof_bindings(root, *, include_roots=(), _operation=None):
    try:
        if type(_operation) is _InvariantInputs and _operation._kind == 'generated_receipt':
            return _operation._receipt_bindings(root, include_roots)
        executing = executing_checker_bindings(root)
        record = (verify(root, exact=True, include_roots=include_roots) if _operation is None else
                  _operation_record(_operation, root, exact=True, include_roots=include_roots))
        require(executing_checker_bindings(root) == executing, 'receipt checker changed during verification')
        result = {MIGRATION: MIGRATION_SHA256, CONSUMER_LEDGER: CONSUMER_LEDGER_SHA256, **executing}
        result.update({path: item['after_sha256'] for path, item in record['sources'].items()})
        for group in BOUND_GROUPS:
            result.update(record[group])
        # Receipts name the actual admitted Map and its bound native inputs.
        # The immutable record remains a historical premise, never a live hash.
        result.update(_station_bindings(root, _operation=_operation))
        result.update(scaled_float32_proof_bindings(root, include_roots=include_roots,
                                                   _operation=_operation))
        result.update(_typed_boundary_bindings(root, _operation=_operation))
        result.update(_witness_format_bindings(root, _operation=_operation))
        result.update(_runtime_view_bindings(root, _operation=_operation))
        result.update(shared_helper_proof_bindings(root, include_roots=include_roots,
                                                  _operation=_operation))
        if _operation is not None:
            _operation._bind_checker_receipt(root, executing)
        return result
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        _operation_fail(_operation, error)


def _absolute_root_text(root):
    """Avoid reconstructing an ordinary absolute POSIX root; retain fallbacks."""
    if os.name == 'posix' and type(root) is PosixPath:
        raw = getattr(root, '_raw_paths', None)
        if type(raw) is list and len(raw) == 1 and type(raw[0]) is str:
            text = raw[0]
            if text == '/' or (text.startswith('/') and not text.endswith(('/', '/.', '/..'))
                    and '//' not in text and '/./' not in text and '/../' not in text):
                return text
    return str(Path(root).absolute())


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--exact', action='store_true')
    parser.add_argument('--include-root', action='append', type=Path, default=[])
    arguments = parser.parse_args()
    verify(arguments.root, exact=arguments.exact, include_roots=arguments.include_root)
    print('Full-audit cleanup source authority: PASS (native qualification is separate)')
