# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact lexical contracts for invocation-local Sum2 environment guards.

Mojo keyword subscripts are not Python syntax. They are compared as complete
lexical operations, retaining unsafe_offset, volatile, qualifiers and operand
order. Actual token-bound function spans prevent comment/docstring decoys.
This does not execute or qualify native volatile loads or floating-point state.
"""
from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import textwrap
import tokenize

try:
    import ideal_projection
    import source_contracts
    import reviewed_cleanup_contracts
except ModuleNotFoundError:
    from tools.carla_lane_oracle import (
        ideal_projection, source_contracts, reviewed_cleanup_contracts,
    )
try:
    import cache_key_contracts as cache_key
except ModuleNotFoundError:
    from tools.carla_lane_oracle import cache_key_contracts as cache_key


PINS = Path('tools/carla_lane_oracle/sum2-guard-pins.json')
MANIFEST_SHA256 = '98933650efb2cad39d62a4fe1ddc18c35331cd79dac3fb8b021284148f6b6109'
FORMAT_MANIFEST_SHA256 = '60448936958e8748ef0a419e6679ec6542e72615ac89a80a7bb24a79581a4e06'
PUBLIC_DOC_MIGRATION_SHA256 = '4cc4cefa6199c1cfbcfd05a636254d1a061889b9a51951d8ceb723544aa6c3dd'
CONTAINING_MODEL_REMOVAL_SHA256 = '3407eccdc3a2e58acfea1922f6e9f9cb7b9b5601c2c377b8da64ab5e7fb605f8'
WINNER_SIGN_MIGRATION_SHA256 = 'b154b18213f9f0400661aff93e47b86bf83990c8838dfa0fca00b0fe6710b9a3'
FINAL_SOURCE_FREEZE_SHA256 = 'eb64ab48aa4e09ea5c064a8ad7c7801bb7c04fdf5a14c7f61494ba8186930aef'
CALLERS = {
    'lane_geometry': ('_lane_spiral',),
    'curve_bounds': ('_spiral_expression', '_lane_jet_model_proof'),
    'lane_refinement': ('_lane_certificate_contains', '_refine_lane_certificate',
                        '_continue_lane_certificate', '_run_lane_search'),
    'map': ('_closest_lane_certificate', '_closest_lane_certificate_with_work', '_create_segments',
            '_seed_exact_interval', '_seed_reference_domain', '_winner_seed_room', '_try_winner_seed'),
    'map_builder': ('build',),
    'spiral_domain_proof': ('_try_pack_spiral_proof', '_spiral_proof_branch'),
    'spiral_moment_proof': ('_try_build_spiral_moments', '_try_spiral_moment_expansion'),
    'spiral_moment_table': ('_try_spiral_moment_expansion',),
    'spiral_roundoff_proof': ('_sum2_envelope_error',),
    'curve_objective_model': ('_try_objective_model', '_restrict_objective_model',
                              '_objective_followup_room', '_objective_recheck_room'),
    'curve_minimizer_support': ('_minimizer_support',),
    'curve_sample_dispatch': ('_sample_dispatch_predicate', '_sample_dispatch_cut',
                              '_try_sample_dispatch_cuts'),
    'spiral_grouped_lane': ('_try_grouped_lane_jet',),
    'spiral_grouped_roundoff_proof': ('_grouped_origin_error',
        '_try_spiral_grouped_roundoff_envelope',
        '_try_spiral_grouped_roundoff_envelope_metered'),
}
OWNERS = {'map': ('Map',), 'map_builder': ('MapBuilder',)}
OWNER_OVERRIDES = {('map', name): () for name in
    ('_seed_exact_interval', '_seed_reference_domain', '_winner_seed_room', '_try_winner_seed')}
PROTECTED = {'_seed_exact_interval', '_seed_reference_domain', '_winner_seed_room', '_try_winner_seed', '_sum2_update', '_require_sum2_environment', '_sum2_supported_environment',
             '_sum2_error', '_sum2_error_checked', '_spiral_proof_branch',
             '_grouped_origin_error', '_try_spiral_grouped_roundoff_envelope',
             '_try_objective_model', '_restrict_objective_model', '_objective_followup_room', '_objective_recheck_room',
             '_minimizer_support',
             '_sample_dispatch_predicate', '_sample_dispatch_cut',
             '_try_sample_dispatch_cuts', '_try_grouped_lane_jet'}
# Scan every production namespace, including new directories. Tests and tool
# entrypoints are separate consumers, not runtime authority. Include __init__
# files: a re-export or module alias must not evade the caller review.
NONPRODUCTION = {'tests', 'examples', 'bench', 'tools', 'docs', 'assets', 'out',
                 'coverage', 'cache', 'build', 'node_modules'}
PROTECTED_MODULES = {'curve_sum2', 'spiral_domain_proof', 'curve_bounds',
    'curve_objective_model', 'curve_minimizer_support', 'curve_sample_dispatch',
    'spiral_grouped_lane', 'spiral_grouped_roundoff_proof'}


@lru_cache(maxsize=256)
def protected_source_digest(text):
    # Fast negative filter only. Positive classification always uses tokens,
    # so comments and docstrings cannot manufacture protected helper uses.
    names = PROTECTED | PROTECTED_MODULES
    if not any(name in text for name in names):
        return None
    identifiers = [token.string for token in source_contracts.tokens(text)
                   if token.type == tokenize.NAME]
    uses = [(index, name) for index, name in enumerate(identifiers) if name in names]
    if not uses:
        return None
    # Preserve existing harmless grouping controls in unrelated caller bodies.
    # Complete routing binds all imports, aliases and declaration owners;
    # protected name ordinals bind every actual use (including in new bodies).
    # Reviewed complete caller bodies and dependency groups bind operations.
    record = {'routing': declaration_routing(text), 'protected_names': uses}
    return hashlib.sha256(json.dumps(record, separators=(',', ':')).encode()).hexdigest()


def production_mojo_paths(root):
    """Fresh census with the established exclusions pruned before descent.

    Keep nested ordinary directories named tests/tools and matching directories
    or symlinks: read_text must still reject unreadable matching entries. Like
    Path.rglob, do not recurse through directory symlinks. Unlike rglob, reject
    scan/classification errors instead of silently omitting production callers.
    """
    root = Path(root)
    pending = [root]
    while pending:
        parent = pending.pop()
        top_level = parent == root
        with os.scandir(parent) as scan:
            entries = list(scan)
        for entry in entries:
            name = entry.name
            if name.startswith('.') or (top_level and name in NONPRODUCTION):
                continue
            path = parent / name
            if path.match('*.mojo'):
                yield path
            if entry.is_dir(follow_symlinks=False):
                pending.append(path)


def protected_inventory(root, *, verified_lane_predecessor=None,
                        verified_map_predecessor=None):
    result = {}
    for path in sorted(production_mojo_paths(root)):
        relative = path.relative_to(root)
        if relative.parts[0] in NONPRODUCTION or any(
                part.startswith('.')
                for part in relative.parts):
            continue
        text = path.read_text()
        if relative.as_posix() == cache_key.MODULE and verified_lane_predecessor is not None:
            text = verified_lane_predecessor
        if relative.as_posix() == 'extensions/carla/map.mojo' and verified_map_predecessor is not None:
            text = verified_map_predecessor
        digest = protected_source_digest(text)
        if digest is not None:
            result[relative.as_posix()] = digest
    return result



def require(condition, message):
    if not condition:
        raise ValueError(message)


def significant(text):
    return [(token.type, token.string) for token in source_contracts.tokens(text)
            if token.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER)]


def declaration_routing(text):
    """Retain top-level and class-level routing, including method bindings.

    Only function suites are omitted here. Function declarations/decorators,
    complete class declarations/fields/aliases and enclosing lexical scopes
    remain. Reviewed caller suites have their own complete token contracts.
    """
    tokens = source_contracts.tokens(text)
    scopes, statement, rows, pending = [], [], [], None
    for token in tokens:
        if token.type == tokenize.INDENT:
            scopes.append(pending or ('block', ()))
            pending = None
        elif token.type == tokenize.DEDENT:
            require(bool(scopes), 'unmatched routing scope')
            scopes.pop()
            pending = None
        elif token.type == tokenize.NEWLINE:
            if statement:
                words = [word for kind, word in statement]
                if not any(kind == 'def' for kind, value in scopes):
                    rows.append((list(scopes), statement))
                if words[-1] == ':':
                    pending = ((words[0], words[1]) if len(words) >= 2 and
                               words[0] in ('def', 'struct', 'trait', 'class')
                               else ('block', tuple(words)))
                else:
                    pending = None
            statement = []
        elif token.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER):
            statement.append((token.type, token.string))
    require(not statement and not scopes, 'incomplete declaration routing')
    return json.dumps(rows, separators=(',', ':'))


def function_span(text, name, expected_owner=None):
    """Find one actual declaration, exact lexical owner and all decorators.

    INDENT scopes retain structural declarations and non-declaration suites.
    A copied method under another method/conditional is not the same callable.
    """
    tokens = source_contracts.tokens(text)
    found, scopes, statement, decorators = [], [], [], {}
    pending = None
    for index, token in enumerate(tokens):
        if token.type == tokenize.INDENT:
            scopes.append(pending or ('block', ()))
            pending = None
            decorators.pop(len(scopes), None)
        elif token.type == tokenize.DEDENT:
            require(bool(scopes), 'unmatched source scope')
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
                    if len(words) >= 2 and words[0] == 'def' and words[1] == name:
                        found.append((statement[0], preceding[0] if preceding else statement[0],
                                      index, tuple(scopes)))
                if words[-1] == ':':
                    if len(words) >= 2 and words[0] in ('def', 'struct', 'trait', 'class'):
                        pending = (words[0], words[1])
                    else:
                        pending = ('block', tuple(words))
                else:
                    pending = None
            statement = []
        elif token.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER):
            statement.append(index)
    require(len(found) == 1, 'missing or ambiguous actual guard declaration: ' + name)
    start, decorated_start, signature, owner = found[0]
    if expected_owner is not None:
        wanted = tuple(('struct', part) for part in expected_owner)
        require(owner == wanted, 'guard caller owner/scope changed: ' + name)
    body = signature + 1
    while body < len(tokens) and tokens[body].type in (tokenize.COMMENT, tokenize.NL):
        body += 1
    require(body < len(tokens) and tokens[body].type == tokenize.INDENT,
            'unsupported guard function body: ' + name)
    end, depth = body + 1, 1
    while end < len(tokens) and depth:
        depth += (tokens[end].type == tokenize.INDENT) - (tokens[end].type == tokenize.DEDENT)
        end += 1
    require(depth == 0, 'unclosed guard function body: ' + name)
    first = tokens[decorated_start].start[0] - 1
    last = tokens[end - 1].start[0] - 1
    lines = text.splitlines(keepends=True)
    source = textwrap.dedent(''.join(lines[first:last]))
    require(source.strip(), 'empty actual guard function: ' + name)
    return source, (decorated_start, end), tokens


def declaration(text, name, expected_owner=()):
    return function_span(text, name, expected_owner)[0]


def _winner_seed_live_observables(text):
    """Read the actual first operation and ordered, scoped debit statements."""
    rows, statement, depth = [], [], 0
    for token in source_contracts.tokens(text):
        if token.type == tokenize.INDENT:
            depth += 1
        elif token.type == tokenize.DEDENT:
            depth -= 1
        elif token.type == tokenize.NEWLINE:
            if statement:
                rows.append((depth, tuple(statement)))
            statement = []
        elif token.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER):
            statement.append((token.type, token.string))
    first = next((row for row in rows if row[0] == 1), None)
    debits = []
    for row in rows:
        words = tuple(word for kind, word in row[1])
        if words[:3] in (('work', '.', '_step'), ('work', '.', 'charge'),
                         ('certificate', '.', 'nodes'), ('certificate', '.', 'terms'),
                         ('certificate', '.', 's'), ('certificate', '.', 'point'),
                         ('certificate', '.', 'upper')):
            debits.append(row)
    return first, debits


def verify(root):
    pins = json.loads((root / PINS).read_text(), object_pairs_hook=source_contracts.unique_keys)
    require(set(pins) == {'schema', 'source_manifest_sha256', 'format_manifest_sha256',
                          'public_doc_migration_sha256', 'final_source_freeze_sha256',
                          'containing_model_removal_sha256', 'winner_sign_migration_sha256',
                          'scope', 'helper_source', 'callers', 'protected_inventory'},
            'wrong Sum2 guard pin keys')
    require(type(pins['schema']) is int and pins['schema'] == 2,
            'unsupported Sum2 guard pin schema')
    require(pins['source_manifest_sha256'] == MANIFEST_SHA256,
            'unreviewed Sum2 guard source manifest')
    require(pins['format_manifest_sha256'] == FORMAT_MANIFEST_SHA256 and
            pins['public_doc_migration_sha256'] == PUBLIC_DOC_MIGRATION_SHA256 and
            pins['final_source_freeze_sha256'] == FINAL_SOURCE_FREEZE_SHA256,
            'unreviewed final Sum2 format/documentation lineage')
    require(pins['containing_model_removal_sha256'] == CONTAINING_MODEL_REMOVAL_SHA256,
            'unreviewed containing-model removal lineage')
    require(pins['winner_sign_migration_sha256'] == WINNER_SIGN_MIGRATION_SHA256 and
            hashlib.sha256((root/'tools/carla_lane_oracle/winner-sign-query-migration.json').read_bytes()).hexdigest() == WINNER_SIGN_MIGRATION_SHA256,
            'unreviewed winner/sign-query source migration')
    require(set(pins['callers']) == set(CALLERS), 'wrong Sum2 guard caller modules')
    helper = (root/'extensions/carla/curve_sum2.mojo').read_text()
    require(significant(helper) == significant(pins['helper_source']),
            'Sum2 complete guard/helper token graph changed')
    count = 0
    verified_lane_predecessor = None
    verified_map_predecessor = None
    for module, names in CALLERS.items():
        record = pins['callers'][module]
        require(set(record) == {'routing', 'functions'} and set(record['functions']) == set(names),
                'wrong Sum2 guard caller function set: ' + module)
        path = 'extensions/carla/' + module + '.mojo'
        text = (root / path).read_text()
        if path == cache_key.MODULE:
            try:
                text = cache_key.reviewed_text(root, path, text)
            except (ValueError, OSError) as error:
                raise ValueError('Sum2 complete guarded caller changed or routing changed: '
                                 + module + ' (' + str(error) + ')') from error
            verified_lane_predecessor = text
        if module == 'map':
            live_seed = declaration(text, '_try_winner_seed', ())
            recorded_seed = record['functions']['_try_winner_seed']
            if significant(live_seed) != significant(recorded_seed):
                try:
                    try:
                        import seed_count_contracts as seed_count
                    except ModuleNotFoundError:
                        from tools.carla_lane_oracle import seed_count_contracts as seed_count
                    text = seed_count.reviewed_text(root, path, text)
                except (ValueError, OSError) as error:
                    raise ValueError('Sum2 complete guarded caller changed or routing changed: '
                                     + module + ' (' + str(error) + ')') from error
                require(_winner_seed_live_observables(live_seed) ==
                        _winner_seed_live_observables(recorded_seed),
                        'Sum2 live winner-seed fresh guard or debit statements changed')
                verified_map_predecessor = text
        require(declaration_routing(text) == record['routing'],
                'Sum2 guard import/declaration routing changed: ' + module)
        spans = []
        for name in names:
            source, span, tokens = function_span(text, name, OWNER_OVERRIDES.get((module, name), OWNERS.get(module, ())))
            require(significant(source) == significant(record['functions'][name]),
                    'Sum2 complete guarded caller changed: ' + module + ':' + name)
            spans.append(span)
            count += 1
        # Every use of a protected callable must lie in a reviewed complete
        # function or a separately matched direct top-level import statement.
        import_spans = []
        depth = 0
        for index, token in enumerate(tokens):
            depth += (token.type == tokenize.INDENT) - (token.type == tokenize.DEDENT)
            if depth == 0 and token.type == tokenize.NAME and token.string in ('from', 'import'):
                end = index
                while end < len(tokens) and tokens[end].type != tokenize.NEWLINE:
                    end += 1
                import_spans.append((index, end))
        for index, token in enumerate(tokens):
            if token.type == tokenize.NAME and token.string in PROTECTED:
                require(any(start <= index < end for start, end in spans + import_spans),
                        'unreviewed Sum2 helper binding/use: ' + module + ':' + token.string)
    require(protected_inventory(root, verified_lane_predecessor=verified_lane_predecessor,
                                verified_map_predecessor=verified_map_predecessor) == pins['protected_inventory'],
            'global protected-helper use/import inventory changed')
    reviewed_cleanup_contracts.verify(root)
    return {'status': 'PASS', 'guarded_modules': len(CALLERS), 'complete_caller_declarations': count,
            'volatile_loads': 3, 'probe_sum2_calls': 4,
            'unsupported_paths': 'raise, infinity, unknown Jet, or absent optional proof as bound by each caller',
            'native_fp_state_execution_qualified': False,
            'protected_production_modules': len(pins['protected_inventory'])}
