# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact Map count-refusal cleanup, with its historical inverse.

This source contract does not itself prove numerical or native behavior.
Only the reviewed after source activates the edge. The unchanged before
source needs no new edge. Historical pins and live debit checks remain live.
No broad verifier is called here: this is the bottom of the successor graph.
"""
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


def require(value, message):
    """Keep rejection controls active in optimized Python."""
    if not value:
        raise ValueError('reviewed seed-count successor: ' + message)


def _function_spans(text):
    """Parse one immutable text snapshot, retaining every lexical owner."""
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
    return result


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


def verify_premises(root, record, *, after):
    """Check each actual operation graph independently of whole-file pins."""
    root = Path(root)
    # Reuse derived spans only within this verified call, never across reads.
    snapshots = {}
    for path, expected in record['layout_routing'].items():
        text = (root/path).read_bytes().decode('utf-8')
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
        require(source.token_sha256(actual) == expected,
                'live theorem premise changed: '+item['path']+':'+'.'.join([*item['owner'], item['name']]))
    # These statements are read from the real after body, never the inverse.
    text = (root/MODULE).read_bytes().decode('utf-8')
    actual = guard.declaration(text, '_try_winner_seed', ())
    prior = guard.declaration(predecessor_source(text, record) if after else text,
                              '_try_winner_seed', ())
    require(guard._winner_seed_live_observables(actual) ==
            guard._winner_seed_live_observables(prior),
            'live fresh-environment guard or ordered debits changed')


def verify(root):
    """Verify the exact edge, live arithmetic dependencies and regression input."""
    root = Path(root)
    record = read_record(root)
    text = (root/MODULE).read_bytes().decode('utf-8')
    edge = verify_source(text, record)
    if edge is None:
        return None
    require(dependency_inventory(root) == {MODULE, *record['unchanged_inputs']},
            'live import or package-resolution closure changed')
    for group in ('historical_records', 'unchanged_inputs', 'unchanged_correctness_tests',
                  'after_correctness_tests'):
        for path, expected in record[group].items():
            require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                    'historical record, live dependency or regression fixture changed: '+path)
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
    require(sha(text) == AFTER_SHA256, 'unknown Map cannot use a predecessor')
    require(verify(root) is not None, 'after Map did not activate its reviewed edge')
    require((root/MODULE).read_bytes().decode('utf-8') == text, 'Map changed during reconstruction')
    return predecessor_source(text, read_record(root))


def reviewed_text(root, path, text):
    """Project a token-equivalent view of the verified physical after Map.

    Comments in a caller's text view do not change the physical compiler
    input. Executable tokens, indentation and statement boundaries must
    still match. The live bytes and every successor dependency are checked
    on each call; this does not admit another physical source variant.
    """
    require(str(path) == MODULE, 'wrong supplied Map path')
    require(source.token_sha256(text) == AFTER_TOKEN_SHA256,
            'unreviewed supplied Map source')
    physical = (Path(root)/MODULE).read_bytes()
    require(hashlib.sha256(physical).hexdigest() == AFTER_SHA256,
            'supplied after view needs the exact physical after Map')
    require(verify(root) is not None, 'after Map did not activate its reviewed edge')
    require((Path(root)/MODULE).read_bytes() == physical,
            'Map changed during supplied-view verification')
    return predecessor_source(physical.decode('utf-8'), read_record(root))
