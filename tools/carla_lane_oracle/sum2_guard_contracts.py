# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact lexical contracts for invocation-local Sum2 environment guards.

Mojo keyword subscripts are not Python syntax. They are compared as complete
lexical operations, retaining unsafe_offset, volatile, qualifiers and operand
order. Actual token-bound function spans prevent comment/docstring decoys.
This does not execute or qualify native volatile loads or floating-point state.
"""
import json
from pathlib import Path
import textwrap
import tokenize

try:
    import ideal_projection
    import source_contracts
except ModuleNotFoundError:
    from tools.carla_lane_oracle import ideal_projection, source_contracts

PINS = Path('tools/carla_lane_oracle/sum2-guard-pins.json')
MANIFEST_SHA256 = '98933650efb2cad39d62a4fe1ddc18c35331cd79dac3fb8b021284148f6b6109'
FORMAT_MANIFEST_SHA256 = '60448936958e8748ef0a419e6679ec6542e72615ac89a80a7bb24a79581a4e06'
PUBLIC_DOC_MIGRATION_SHA256 = '4cc4cefa6199c1cfbcfd05a636254d1a061889b9a51951d8ceb723544aa6c3dd'
FINAL_SOURCE_FREEZE_SHA256 = 'eb64ab48aa4e09ea5c064a8ad7c7801bb7c04fdf5a14c7f61494ba8186930aef'
CALLERS = {
    'lane_geometry': ('_lane_spiral',),
    'curve_bounds': ('_spiral_expression', '_lane_jet_model_proof'),
    'lane_refinement': ('_lane_certificate_contains', '_refine_lane_certificate',
                        '_continue_lane_certificate'),
    'map': ('_closest_lane_certificate', '_closest_lane_certificate_with_work', '_create_segments'),
    'map_builder': ('build',),
    'spiral_domain_proof': ('_try_pack_spiral_proof', '_spiral_proof_branch'),
    'spiral_moment_proof': ('_try_build_spiral_moments', '_try_spiral_moment_expansion'),
    'spiral_moment_table': ('_try_spiral_moment_expansion',),
    'spiral_roundoff_proof': ('_sum2_envelope_error',),
}
OWNERS = {'map': ('Map',), 'map_builder': ('MapBuilder',)}
PROTECTED = {'_sum2_update', '_require_sum2_environment', '_sum2_supported_environment',
             '_sum2_error', '_sum2_error_checked', '_spiral_proof_branch'}


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


def verify(root):
    pins = json.loads((root / PINS).read_text(), object_pairs_hook=source_contracts.unique_keys)
    require(set(pins) == {'schema', 'source_manifest_sha256', 'format_manifest_sha256',
                          'public_doc_migration_sha256', 'final_source_freeze_sha256',
                          'scope', 'helper_source', 'callers'},
            'wrong Sum2 guard pin keys')
    require(type(pins['schema']) is int and pins['schema'] == 2,
            'unsupported Sum2 guard pin schema')
    require(pins['source_manifest_sha256'] == MANIFEST_SHA256,
            'unreviewed Sum2 guard source manifest')
    require(pins['format_manifest_sha256'] == FORMAT_MANIFEST_SHA256 and
            pins['public_doc_migration_sha256'] == PUBLIC_DOC_MIGRATION_SHA256 and
            pins['final_source_freeze_sha256'] == FINAL_SOURCE_FREEZE_SHA256,
            'unreviewed final Sum2 format/documentation lineage')
    require(set(pins['callers']) == set(CALLERS), 'wrong Sum2 guard caller modules')
    helper = (root/'extensions/carla/curve_sum2.mojo').read_text()
    require(significant(helper) == significant(pins['helper_source']),
            'Sum2 complete guard/helper token graph changed')
    count = 0
    for module, names in CALLERS.items():
        record = pins['callers'][module]
        require(set(record) == {'routing', 'functions'} and set(record['functions']) == set(names),
                'wrong Sum2 guard caller function set: ' + module)
        text = (root / ('extensions/carla/' + module + '.mojo')).read_text()
        require(declaration_routing(text) == record['routing'],
                'Sum2 guard import/declaration routing changed: ' + module)
        spans = []
        for name in names:
            source, span, tokens = function_span(text, name, OWNERS.get(module, ()))
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
    return {'status': 'PASS', 'guarded_modules': len(CALLERS), 'complete_caller_declarations': count,
            'volatile_loads': 3, 'probe_sum2_calls': 4,
            'unsupported_paths': 'raise, infinity, unknown Jet, or absent optional proof as bound by each caller',
            'native_fp_state_execution_qualified': False}
