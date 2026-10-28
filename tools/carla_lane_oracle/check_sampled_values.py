#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Read-only source correspondence for derivative-elided sampled bounds.

Copied declarations are sliced, renamed, and classified by the Mojo text gate.
The syntax correspondence still uses the Python standard library. Numeric grouping,
branches, imports and retained value/error operations are checked against the
full-Jet source. Primitive changes require renewed review.
"""
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

import argparse
import ast
import hashlib
# #333 explicit historical provenance views; current inputs remain operation-owned.
import io
import json
from pathlib import Path
import re
import tokenize

try:
    from source_contracts import verify_group, verify_qualifiers
except ModuleNotFoundError:
    from tools.carla_lane_oracle.source_contracts import verify_group, verify_qualifiers

ROOT = Path(__file__).resolve().parents[2]


class CheckError(ValueError):
    pass


def __getattr__(name):
    if name == 'IMPORTS':
        return _sampled_closure()['imports']
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def require(condition, message):
    if not condition:
        raise CheckError(message)


def function(text, name):
    matches = list(re.finditer(r'(?m)^def ' + re.escape(name) + r'[\[(]', text))
    require(len(matches) == 1, _sampled_closure()['function'] + name)
    match = matches[0]
    end = re.search(r'(?m)^(?:def |@)', text[match.end():])
    return text[match.start():match.end()+end.start() if end else len(text)]


def _sampled_declarations():
    """Return the three reviewed sampled declarations."""
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_declarations'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return json.loads(result.stdout)


def _helper_then_syntax(primitive, target):
    """Check the stored helpers, then prepare the lane-value syntax."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='helper-syntax-') as directory:
        folder = Path(directory)
        primitive_path = folder / 'primitive.mojo'
        target_path = folder / 'target.mojo'
        primitive_path.write_text(primitive)
        target_path.write_text(target)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_text',
             '--helper-then-syntax', str(primitive_path), str(target_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    try:
        data = json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        return None
    if data.get('fallback'):
        return None
    try:
        return data['source'], data['generics'], data['words']
    except (KeyError, TypeError):
        return None


def _sampled_text(mode, text, name='', index=None, replacement=None):
    """Slice, rename, or dump one declaration with the Mojo text gate."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-text-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        command = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                   'carla_sampled_text', '--strip-gates', mode, str(path)]
        if name:
            command.extend(['--name', name])
        if index is not None:
            command.extend(['--index', str(index)])
        if replacement is not None:
            repl = Path(directory) / 'replacement.mojo'
            repl.write_text(replacement)
            command.extend(['--with', str(repl)])
        result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return result.stdout


def _input_modules():
    """Return the four sampled input modules in reviewed order."""
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_input_modules'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return json.loads(result.stdout)


def _inputs_then_graphs():
    """Read the input plan, then the graph pins and reference names."""
    global _SAMPLED_CLOSURE, _CARLA_PACKAGE
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_sampled_input_modules', '--plan-graphs'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    parsed = json.loads(result.stdout)
    if _CARLA_PACKAGE is None:
        _CARLA_PACKAGE = parsed['package']
    if _SAMPLED_CLOSURE is None:
        _SAMPLED_CLOSURE = parsed['closure']
    return parsed


def _sampled_inputs():
    """Return the input modules, then the package path."""
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_sampled_input_modules', '--plan'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return json.loads(result.stdout)


def _graphs_and_names():
    """Return the graph digests after the reference names match."""
    import json
    import os
    import subprocess
    global _SAMPLED_CLOSURE
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_sampled_graph_pins', '--checked'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    parsed = json.loads(result.stdout)
    _SAMPLED_CLOSURE = parsed['closure']
    return parsed['graphs'], parsed['closure']


def _graph_pins():
    """Return the reference, primitive, and shared graph digests."""
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_graph_pins'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return json.loads(result.stdout)


def _copy_plan():
    """Return the sampled copy order and the rename map."""
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_copies'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return json.loads(result.stdout)


def translated(text):
    # Replace NAME tokens at original offsets, preserving fragment indentation
    # and every string literal. This also handles renamed identifiers of
    # different lengths without reconstructing partial source statements.
    names = _copy_plan()['names']
    lines = text.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    changes = []
    for item in tokenize.generate_tokens(io.StringIO(text).readline):
        if item.type == tokenize.NAME and item.string in names:
            start = offsets[item.start[0]-1] + item.start[1]
            end = offsets[item.end[0]-1] + item.end[1]
            changes.append((start, end, names[item.string]))
    for start, end, word in reversed(changes):
        text = text[:start] + word + text[end:]
    return text


_SYNTAX_WORDS = None
_PREPARED_SYNTAX = {}
_MISSING_SYNTAX = object()
_RESTORED_SYNTAX = {}


_CARLA_PACKAGE = None


def _carla_package():
    """Return the CARLA extension package path."""
    global _CARLA_PACKAGE
    if _CARLA_PACKAGE is not None:
        return _CARLA_PACKAGE
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_carla_package'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    _CARLA_PACKAGE = result.stdout
    return _CARLA_PACKAGE


def _syntax_words():
    """Return the sampled syntax keywords and the generic messages."""
    global _SYNTAX_WORDS
    if _SYNTAX_WORDS is not None:
        return _SYNTAX_WORDS
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_syntax_words'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    _SYNTAX_WORDS = json.loads(result.stdout)
    return _SYNTAX_WORDS


def _python_syntax_tree(text):
    # Keywords are removed lexically, never from string literals. Native
    # structs map to Python classes only for AST inspection; their generic
    # parameters, traits, fields, types, decorators and statements stay bound.
    words = _syntax_words()
    keywords = set(words['keywords'])
    tokens = []
    for item in tokenize.generate_tokens(io.StringIO(text).readline):
        if item.type == tokenize.NAME and item.string in keywords:
            continue
        word = words['class_word'] if item.type == tokenize.NAME and item.string == words['struct_word'] else item.string
        tokens.append((item.type, word))
    # Represent Mojo type-parameter declarations as bound lexical metadata,
    # rather than requiring Python3.12's unrelated generic-function grammar.
    metadata = {}
    index = 0
    while index + 2 < len(tokens):
        if (tokens[index][0] == tokenize.NAME and tokens[index][1] in (words['def_word'], words['class_word'])
                and tokens[index + 1][0] == tokenize.NAME and tokens[index + 2][1] == '['):
            depth = 1
            end = index + 3
            while end < len(tokens) and depth:
                depth += (tokens[end][1] == '[') - (tokens[end][1] == ']')
                end += 1
            require(depth == 0, words['unclosed'])
            items = [(tokenize.tok_name[t], value) for t, value in tokens[index + 3:end - 1]
                     if t not in (tokenize.NL, tokenize.COMMENT)]
            if items and items[-1][1] == ',':
                items.pop()
            key = (tokens[index][1], tokens[index + 1][1])
            require(key not in metadata, words['ambiguous'])
            metadata[key] = items
            del tokens[index + 2:end]
        index += 1
    tree = ast.parse(tokenize.untokenize(tokens))
    for (kind, name), parameters in metadata.items():
        node_type = ast.FunctionDef if kind == words['def_word'] else ast.ClassDef
        matches = [n for n in ast.walk(tree) if isinstance(n, node_type) and n.name == name]
        require(len(matches) == 1, words['parsed'])
        setattr(matches[0], words['mojo_parameters'], parameters)
    return tree


def _syntax_prepare(text):
    """Return parser source, generic rows, and the syntax words."""
    cached = _PREPARED_SYNTAX.get(text, _MISSING_SYNTAX)
    if cached is not _MISSING_SYNTAX:
        return cached
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-syntax-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--classified-syntax', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    try:
        data = json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        _PREPARED_SYNTAX[text] = None
        return None
    if data.get('fallback'):
        _PREPARED_SYNTAX[text] = None
        return None
    try:
        prepared = data['source'], data['generics'], data['words']
    except (KeyError, TypeError):
        prepared = None
    _PREPARED_SYNTAX[text] = prepared
    return prepared


def _classified_sources(texts):
    """Classify every source before the Python comparison."""
    if not texts:
        return []
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='classified-sources-') as directory:
        path = Path(directory) / 'sources.json'
        path.write_text(json.dumps(list(texts), separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--classified-syntax-all', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return _prepared_rows(texts, json.loads(result.stdout))


def _prepared_rows(texts, items):
    """Return classified syntax rows and remember the successful ones."""
    if not isinstance(items, list) or len(items) != len(texts):
        raise CheckError('sampled projection step changed')
    prepared = []
    for item in items:
        if (
            isinstance(item, dict)
            and 'error' in item
            and 'source' not in item
            and 'fallback' not in item
        ):
            prepared.append(item['error'])
        elif not isinstance(item, dict) or item.get('fallback'):
            prepared.append(None)
        else:
            try:
                prepared.append((item['source'], item['generics'], item['words']))
            except (KeyError, TypeError):
                prepared.append(None)
    for text, item in zip(texts, prepared):
        if not isinstance(item, str):
            _PREPARED_SYNTAX[text] = item
    return prepared


def _digest_then_sources(prior, texts):
    """Check one reviewed graph, then classify the following modules."""
    if prior is None:
        return _classified_sources(texts)
    graph, digest, message = prior
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='digest-syntax-') as directory:
        folder = Path(directory)
        graph_path = folder / 'graph.txt'
        sources_path = folder / 'sources.json'
        graph_path.write_text(graph)
        sources_path.write_text(json.dumps(list(texts), separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--digest-then-syntax', str(graph_path), digest, message,
             str(sources_path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        failure = lines[-1] if lines else result.stdout.strip()
        raise CheckError(failure)
    return _prepared_rows(texts, json.loads(result.stdout))


def _graph_digest_rows(rows):
    """Require each plain reference graph digest, in order."""
    if not rows:
        return
    import os
    import subprocess
    import tempfile
    payload = json.dumps([
        {'graph': graph, 'digest': digest, 'message': message}
        for graph, digest, message in rows
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='graph-digests-') as directory:
        path = Path(directory) / 'graphs.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_text',
             '--graph-digests', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        failure = lines[-1] if lines else result.stdout.strip()
        raise CheckError(failure)


def _digests_then_value_fields(rows, text):
    """Check the shared graph digests, then the value fields."""
    import os
    import subprocess
    import tempfile
    payload = json.dumps([
        {'graph': graph, 'digest': digest, 'message': message}
        for graph, digest, message in rows
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='digests-fields-') as directory:
        folder = Path(directory)
        hashes = folder / 'graphs.json'
        source = folder / 'source.mojo'
        hashes.write_text(payload)
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_text',
             '--digests-then-fields', str(hashes), str(source)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        failure = lines[-1] if lines else result.stdout.strip()
        raise CheckError(failure)


def _shared_reference_graphs(reference_trees, shared, label, target):
    """Compare each shared function, then check the value fields."""
    rows = []
    for key, expected_hash in shared.items():
        filename, name = key.split(':', 1)
        try:
            node = unique_function(reference_trees[filename], name)
        except CheckError:
            _graph_digest_rows(rows)
            raise
        rows.append((dump(node), expected_hash, label + key))
    _digests_then_value_fields(rows, target)


def _hashes_then_declaration(rows, text):
    """Check the plain graph digests, then the Jet primitive."""
    import os
    import subprocess
    import tempfile
    payload = json.dumps([
        {'graph': graph, 'digest': digest, 'message': message}
        for graph, digest, message in rows
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='hashes-declaration-') as directory:
        folder = Path(directory)
        hashes = folder / 'graphs.json'
        source = folder / 'source.mojo'
        hashes.write_text(payload)
        source.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_text',
             '--hashes-then-declaration', str(hashes), str(source)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        failure = lines[-1] if lines else result.stdout.strip()
        raise CheckError(failure)


def _plain_reference_graphs(entries, label, prior=None, defer=False):
    """Classify plain reference modules, then compare each graph."""
    if not entries and prior is None:
        return []
    prepared = _digest_then_sources(
        prior, [text for _filename, text, _expected in entries])
    rows = []
    for (filename, text, expected_hash), item in zip(entries, prepared):
        if isinstance(item, str):
            _graph_digest_rows(rows)
            raise CheckError(item)
        try:
            reference_graph = dump(syntax_tree(text, item, _prepare=False))
        except CheckError:
            _graph_digest_rows(rows)
            raise
        rows.append((reference_graph, expected_hash, label + filename))
    if defer:
        return rows
    _graph_digest_rows(rows)
    return []


def _reviewed_reference_graphs(items, texts, reviewed, label, review):
    """Compare reference graphs, classifying each plain run in one check."""
    pending = []
    prior = None
    for filename, expected_hash in items:
        if filename == reviewed:
            _plain_reference_graphs(pending, label, prior)
            pending = []
            prior = (
                review(filename, expected_hash),
                expected_hash,
                label + filename,
            )
        else:
            pending.append((filename, texts[filename], expected_hash))
    return _plain_reference_graphs(pending, label, prior, defer=True)


def syntax_tree(text, prepared=None, _prepare=True):
    # Keywords are removed lexically, never from string literals. Native
    # structs map to Python classes only for AST inspection; their generic
    # parameters, traits, fields, types, decorators and statements stay bound.
    if _prepare:
        prepared = _syntax_prepare(text)
    if prepared is None:
        return _python_syntax_tree(text)
    source, generics, words = prepared
    global _SYNTAX_WORDS
    if _SYNTAX_WORDS is None:
        _SYNTAX_WORDS = words
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return _python_syntax_tree(text)
    for key, parameters in generics:
        kind, name = key
        node_type = ast.FunctionDef if kind == words['def_word'] else ast.ClassDef
        matches = [n for n in ast.walk(tree) if isinstance(n, node_type) and n.name == name]
        require(len(matches) == 1, words['parsed'])
        setattr(matches[0], words['mojo_parameters'], [tuple(item) for item in parameters])
    return tree


def normalized_node(node):
    if isinstance(node, ast.AST):
        words = _syntax_words()
        parameter_name = words['mojo_parameters']
        fields = [(key, normalized_node(value)) for key, value in ast.iter_fields(node)
                  if value is not None and not (key == words['type_params'] and not value)]
        if hasattr(node, parameter_name):
            fields.append((parameter_name, getattr(node, parameter_name)))
        return (type(node).__name__, fields)
    if isinstance(node, list):
        return [normalized_node(value) for value in node]
    return node


def dump(node):
    # Ignore absent optional AST fields that newer Python versions introduce,
    # while binding all actual fields, types and explicit Mojo generics.
    return json.dumps(normalized_node(node), separators=(',', ':'), ensure_ascii=True)


def graph(text):
    return dump(syntax_tree(text))


def unique_function(tree, name):
    found = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name]
    require(len(found) == 1, _sampled_closure()['function'] + name)
    return found[0]


def _aliases_then_graph(text, graph, digest, message):
    """Check the derivative aliases, then the primitive graph digest."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='aliases-graph-') as directory:
        folder = Path(directory)
        source = folder / 'source.mojo'
        dump_path = folder / 'graph.txt'
        source.write_text(text)
        dump_path.write_text(graph)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_text',
             '--aliases-then-graph', str(source), str(dump_path), digest,
             message],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        failure = lines[-1] if lines else result.stdout.strip()
        raise CheckError(failure)


def primitive_graph(text, expected, message, prior_hashes=None):
    if prior_hashes:
        _hashes_then_declaration(prior_hashes, text)
    else:
        _sampled_text('--primitive-declaration', text)
    tree = syntax_tree(text)
    found = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == _syntax_words()['primitive_class']]
    # The declaration count is a token check. The class hash below stays on
    # the Python syntax tree.
    require(len(found) == 1, _sampled_closure()['primitive_declaration'])
    _aliases_then_graph(text, dump(found[0]), expected, message)



def reviewed_reference_tree(text, root=ROOT, *, _operation=None):
    """Retain the historical reference graph after one exact additive refusal.

    Default False preserves every existing call. True may return unknown
    before the unchanged GL fallback; it cannot perform unreserved work.
    The production tokens and grouped True caller are bound separately.
    """
    try:
        try:
            import full_audit_cleanup_contracts as full_audit
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import full_audit_cleanup_contracts as full_audit
        closure = _sampled_closure()
        text = full_audit.reviewed_text(root, _carla_package() + '/' + closure['reviewed'], text, _operation=_operation)
    except (ValueError, OSError) as error:
        raise CheckError(_sampled_closure()['reference_changed'] + _sampled_closure()['reviewed'] + ': ' + str(error)) from error
    # The reviewed no-counter-alias successor changes only optional admission.
    # Reconstruct its exact historical helper before the original projection;
    # every original reference graph digest remains unchanged.
    try:
        try:
            import envelope_budget_contracts as budget
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import envelope_budget_contracts as budget
        previous = budget.historical_function(text, root=root)
    except ValueError as error:
        raise CheckError(_sampled_closure()['reference_changed'] + _sampled_closure()['reviewed'] + ': ' + str(error)) from error
    restored, prepared = _restored_then_syntax(text, previous)
    tree = syntax_tree(restored, prepared, _prepare=False)
    return tree


def _restored_then_syntax(text, replacement):
    """Restore the historical capture, then prepare its Python syntax."""
    cached = _RESTORED_SYNTAX.get((text, replacement))
    if cached is not None:
        return cached
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='restore-syntax-') as directory:
        folder = Path(directory)
        source = folder / 'source.mojo'
        previous = folder / 'replacement.mojo'
        source.write_text(text)
        previous.write_text(replacement)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_restore_reference', '--after-refusal-syntax',
             str(source), str(previous)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    parsed = json.loads(result.stdout)
    syntax = parsed['syntax']
    if syntax.get('fallback'):
        cached = (parsed['restored'], None)
    else:
        cached = (
            parsed['restored'],
            (syntax['source'], syntax['generics'], syntax['words']),
        )
    _RESTORED_SYNTAX[(text, replacement)] = cached
    return cached


def _restored_after_refusal(text, replacement):
    """Check the try-only refusal, then restore the historical capture."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='restore-reference-') as directory:
        folder = Path(directory)
        source = folder / 'source.mojo'
        previous = folder / 'replacement.mojo'
        source.write_text(text)
        previous.write_text(replacement)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_restore_reference', '--after-refusal',
             str(source), str(previous)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return result.stdout


def _restored_reference(text, replacement):
    """Strip the try-only refusal and restore the historical capture."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='restore-reference-') as directory:
        folder = Path(directory)
        source = folder / 'source.mojo'
        previous = folder / 'replacement.mojo'
        source.write_text(text)
        previous.write_text(replacement)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_restore_reference', str(source), str(previous)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return result.stdout


def _source_digests(blobs):
    """Return SHA-256 hex digests of observed bytes, in order."""
    import os
    import subprocess
    import tempfile
    framed = b''.join(
        str(len(raw)).encode('ascii') + b'\n' + raw for raw in blobs)
    repo = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-source-sha-') as directory:
        path = Path(directory) / 'frame.bin'
        path.write_bytes(framed)
        result = subprocess.run(
            ['sh', str(repo / 'tools' / 'tool.sh'), mojo,
             'carla_source_sha256', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    digests = json.loads(result.stdout)
    if len(digests) != len(blobs):
        raise ValueError(_sampled_closure()['frame'])
    return digests


def _sampled_result(root, shared, modules, primitive, sources, successors):
    """Return the sampled-value result in historical field order."""
    import ast
    import os
    import subprocess
    import tempfile
    payload = json.dumps({
        'root': root, 'shared': shared, 'modules': modules,
        'primitive': primitive, 'sources': sources,
        'successors': successors,
    }, separators=(',', ':'))
    repo = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-value-result-') as directory:
        path = Path(directory) / 'result.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(repo / 'tools' / 'tool.sh'), mojo,
             'carla_sampled_value_result', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['key']
        if message.startswith(prefix):
            raise KeyError(ast.literal_eval(message[len(prefix):])) from None
        raise ValueError(message)
    return json.loads(result.stdout)


_SAMPLED_INDENTED = None


def _digests_and_result(blobs, root, shared, modules, primitive, names, successors):
    """Hash the observed sources, then return the result and its indent."""
    global _SAMPLED_INDENTED
    import ast
    import os
    import subprocess
    import tempfile
    framed = b''.join(
        str(len(raw)).encode('ascii') + b'\n' + raw for raw in blobs)
    payload = json.dumps({
        'root': root,
        'shared': shared,
        'modules': modules,
        'primitive': primitive,
        'names': list(names),
        'successors': successors,
    }, separators=(',', ':'))
    repo = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-framed-result-') as directory:
        frame = Path(directory) / 'frame.bin'
        meta = Path(directory) / 'meta.json'
        frame.write_bytes(framed)
        meta.write_text(payload)
        result = subprocess.run(
            ['sh', str(repo / 'tools' / 'tool.sh'), mojo,
             'carla_sampled_value_result', '--framed-indented', str(frame),
             str(meta)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['key']
        if message.startswith(prefix):
            raise KeyError(ast.literal_eval(message[len(prefix):])) from None
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    _SAMPLED_INDENTED = parsed['indented']
    return parsed['result']


_SAMPLED_CLOSURE = None


def _sampled_closure():
    """Return the sampled reference names and the closure groups."""
    global _SAMPLED_CLOSURE
    if _SAMPLED_CLOSURE is not None:
        return _SAMPLED_CLOSURE
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_sampled_closure'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    _SAMPLED_CLOSURE = json.loads(result.stdout)
    return _SAMPLED_CLOSURE


_PROJECTION_RECIPE = None


def _projection_recipe():
    """Return the sampled projection steps and comparison texts."""
    global _PROJECTION_RECIPE
    if _PROJECTION_RECIPE is not None:
        return _PROJECTION_RECIPE
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_sampled_projection_recipe'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    _PROJECTION_RECIPE = json.loads(result.stdout)
    return _PROJECTION_RECIPE


def _project_batch(bounds, trig):
    """Return the copied helpers and the value dispatchers."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'bounds': bounds, 'trig': trig}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='sampled-projection-') as directory:
        path = Path(directory) / 'sources.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_sampled_projection', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return json.loads(result.stdout)


def _recipe_and_batch(bounds, trig, target):
    """Return the projection steps, the helpers, and their syntax."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(
        {'target': target, 'bounds': bounds, 'trig': trig},
        separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='sampled-recipe-') as directory:
        path = Path(directory) / 'sources.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_sampled_projection', '--after-top-level-syntax',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        marker = 'sampled imports: '
        top = 'sampled top-level: '
        if message.startswith(marker) or message.startswith(top):
            if message.startswith(marker):
                message = message[len(marker):]
            else:
                message = message[len(top):]
            closure = _sampled_closure()
            for prefix in (closure['value_gate'], closure['jet_gate']):
                if message.startswith(prefix):
                    message = message[len(prefix):]
        raise CheckError(message)
    return json.loads(result.stdout)


def _project_sampled(bounds, trig, texts, target):
    """Project the helpers, then return syntax after the recipe comparison."""
    checked = _recipe_and_batch(bounds, trig, target)
    recipe = checked['recipe']
    record = checked['record']
    expected = record['helpers']
    # Project complete parsed declarations, never raw prefix/tail slices.
    # Remove precisely the three complete non-sampled branches of the reference
    # capture. The new leading guard rejects those kinds; the independent broad
    # wrapper provides the full-Jet SPIRAL bridge. All 12 statements are
    # accounted for. The statement dumps come from Mojo. Python parses the
    # reviewed source texts and requires the dumps to match.
    del texts
    for step in recipe['steps']:
        kind = step['kind']
        if kind == 'project' or kind == 'rename':
            continue
        elif kind == 'constant':
            require(record['constant']['dump'] == dump(ast.parse(
                step['constructor']).body[0]), step['constructor_message'])
            elements = json.loads(record['constant']['pair'])
            field = step['field']
            for index, _item in enumerate(elements):
                required = ast.parse(
                    field['prefix'] + str(index) + field['suffix'], mode='eval').body
                require(elements[index] == dump(required), step['field_message'])
            # Only derivative constructor fields change. Coefficient enclosure,
            # exact-zero scalar error, result ordering and guards are retained.
        elif kind == 'lane':
            # This private value-only specialization has no cached proof argument.
            # Remove only the exact new refusal branch whose proof condition is false
            # for that route. The full cached-proof caller remains separately bound.
            require(record['lane']['refusal'] == dump(ast.parse(
                step['refusal']).body[0]), step['refusal_message'])
            require(record['lane']['capture'] == dump(ast.parse(
                step['capture']).body[0]), step['capture_message'])
            # 0..13: all record checks/width traversal/elevation setup are retained.
            # 14: the exact capture-only assignments above are deleted.
            # 15..16: complete ARC/LINE branches move under all_geometry, in order.
            # 17..20: complete proof/capture dispatch is replaced by a sampled call.
            # This replacement is justified only by _reference_sampled_value's kind
            # guard and the separately bound SPIRAL full-Jet wrapper, never by a
            # claim that the proof branch is value-independent. Whole reference
            # modules bind every removed proof statement and its dependencies.
            # 21..22: original trig and final output are retained, without slicing.
        else:
            raise CheckError(_sampled_closure()['step'])
    # The recipe comparison above still fails before a syntax error.
    return expected, _prepared_rows(
        [source for _name, source in expected.items()], checked['syntax'])


@source.lexical_memo_scope()
def verify(root):
    if __package__:
        from . import full_audit_cleanup_contracts as audit
    else:
        import full_audit_cleanup_contracts as audit
    _operation, owns = audit._operation_enter(root, 'sampled')
    try:
        inputs = _inputs_then_graphs()
        global _CARLA_PACKAGE
        if _CARLA_PACKAGE is None:
            _CARLA_PACKAGE = inputs['package']
        modules = inputs['modules']
        paths = {name: root / inputs['package'] / name for name in modules}
        texts = {name: _typed_source.historical_text(root, path, _typed_source._observe_text(root, (path).relative_to(root).as_posix(), path.read_text(), _operation=_operation), _operation=_operation) for name, path in paths.items()}
        bounds, trig, target = texts[modules[0]], texts[modules[1]], texts[modules[3]]
        # Deliberately conservative closure: imports, aliases, all helper setup,
        # branch dispatch and every shared operation in all three reference
        # modules are bound. Any dependency change needs renewed source review.
        graphs = inputs['graphs']
        reference_graphs = graphs['reference']
        closure = _sampled_closure()

        def review(filename, _expected_hash):
            return dump(reviewed_reference_tree(
                texts[filename], root, _operation=_operation))

        prior_hashes = _reviewed_reference_graphs(
            reference_graphs.items(), texts, closure['reviewed'],
            closure['reference_changed'], review)
        primitive_graph(
            texts[closure['primitive']], graphs['primitive'],
            closure['primitive_message'], prior_hashes)
        # Complete stored helper/interval closure and lexical qualifiers are
        # independent of the unchanged primitive-class AST hash.
        try:
            for group in closure['groups']:
                verify_group(root, group, _operation=_operation)
            try:
                import sum2_contracts
            except ModuleNotFoundError:
                from tools.carla_lane_oracle import sum2_contracts
            sum2_contracts.verify(root, _operation=_operation)
        except ValueError as error:
            raise CheckError(str(error)) from error
        target_tree = syntax_tree(
            target,
            _helper_then_syntax(texts[closure['primitive']], target),
            _prepare=False,
        )
        reference_trees = {closure['reviewed']: reviewed_reference_tree(bounds, root, _operation=_operation), closure['syntax']: syntax_tree(trig)}
        _shared_reference_graphs(
            reference_trees, graphs['shared'], closure['shared'], target)
        try:
            for filename, text in texts.items():
                verify_qualifiers(root, filename, text, _operation=_operation)
        except ValueError as error:
            raise CheckError(str(error)) from error
        expected, prepared_sources = _project_sampled(
            bounds, trig, texts, target)
        for (name, source), prepared in zip(expected.items(), prepared_sources):
            # Decorators stay on the copied text. The syntax tree is the
            # independent comparison with the sampled module.
            if isinstance(prepared, str):
                raise CheckError(prepared)
            wanted = unique_function(
                syntax_tree(source, prepared, _prepare=False), name)
            actual = unique_function(target_tree, name)
            require(dump(wanted) == dump(actual),
                    closure['diverged'] + name)
        current_edges = audit.typed_successor_edges(root, _operation=_operation)
        observed = [audit._observe_bytes(
            root, path.relative_to(root).as_posix(), path.read_bytes(),
            _operation=_operation) for path in paths.values()]
        if owns:
            _operation.finish(root)
        return _digests_and_result(
            observed, str(root.resolve()), len(graphs['shared']),
            len(reference_graphs), graphs['primitive'], list(paths),
            current_edges)
    finally:
        if owns:
            _operation.close()


_CLI_FAILURES = None


def _cli_failures():
    """Return the checker failure prefixes."""
    global _CLI_FAILURES
    if _CLI_FAILURES is not None:
        return _CLI_FAILURES
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cli_failures'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CLI_FAILURES = json.loads(result.stdout)
    return _CLI_FAILURES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        verify(args.repo_root.resolve())
    except (CheckError, OSError, SyntaxError, ValueError) as error:
        print(_cli_failures()['sampled'], error)
        return 1
    print(_SAMPLED_INDENTED, end='')
    return 0


if __name__ == '__main__':
    # The CLI uses the canonical registered module, so its public verifier
    # can own one physical capture just like an imported invocation.
    from check_sampled_values import main as _owned_main
    raise SystemExit(_owned_main())
