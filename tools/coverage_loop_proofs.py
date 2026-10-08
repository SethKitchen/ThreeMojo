# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bind conservative constant-loop proofs without changing runtime probes.

The original instrumenter and manifest remain authoritative. The official
report path verifies this receipt against current sources and tool contents,
then derives an outcome-masked manifest for the native reporter. Unknown
syntax or bindings keep both outcomes. This module never executes source.
"""

import argparse
import ast
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import sys
import tokenize

import cache_key
import coverage_toolchain_identity

ACTIVE_SOURCE_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
ACTIVE_TOOLCHAIN_SHA256 = hashlib.sha256(Path(coverage_toolchain_identity.__file__).read_bytes()).hexdigest()
ACTIVE_INVENTORY_SHA256 = hashlib.sha256(Path(cache_key.__file__).read_bytes()).hexdigest()


SCHEMA = 'constant-loops-v2'
# A conservative common subset of signed Int on supported CPU targets.
# No arithmetic expression is folded; both literal endpoints fit signed i32.
MAX_ENDPOINT = (1 << 31) - 1
TOOL_INPUTS = (
    'coverage/build_cli.mojo', 'coverage/instrument.mojo',
    'coverage/scanner.mojo', 'coverage/runtime.mojo',
    'coverage/report.mojo', 'coverage/report_cli.mojo', 'coverage/mcdc.mojo',
    'tools/coverage_loop_proofs.py', 'tools/coverage_io.py',
    'tools/cache_key.py', 'tools/native_test_support.py',
    'tools/coverage_toolchain_identity.py',
    'tools/coverage_hit_aot.py', 'tools/coverage_hit_cache.c',
    'tools/coverage_write_interposer.c', 'tools/test_environment.py',
    'tools/run_suite.py', 'Makefile',
)


def maintained_inputs(root, *, exclude=None, staged=False):
    """Use the maintained cache inventory, including native fixtures/assets.

    The declared output root is excluded even when COV_DIR is customized.
    This inventory, not TOOL_INPUTS, is the integrity boundary.
    """
    root = Path(root).resolve()
    excluded = Path(exclude).resolve() if exclude is not None else None
    result = {}
    for relative in cache_key.input_paths(root):
        path = relative_source(root, relative.as_posix())
        if excluded is not None and path.resolve().is_relative_to(excluded):
            continue
        if staged and (relative.parts[0] == 'hits' or relative.as_posix() in {'loop-proofs.json', 'generation-inputs.json'}):
            continue
        result[relative.as_posix()] = file_sha256(path)
    return result


def _origin_header(raw, offset):
    end = raw.find(b'\n', offset)
    if end < 0:
        raise ValueError('Truncated generation origin header')
    return raw[offset:end].split(b' '), end + 1


def _origin_length(value):
    if not re.fullmatch(rb'0|[1-9][0-9]*', value):
        raise ValueError('Invalid generation origin byte length')
    return int(value)


def _origin_part(raw, offset, size):
    if size > len(raw) - offset:
        raise ValueError('Truncated generation origin payload')
    return raw[offset:offset + size], offset + size


def generation_origins(root, build, manifest, compiler, flags, mojo):
    """Validate a trusted producer's exact input/output/manifest pairing."""
    index = (build / 'origins.ready').read_bytes()
    fields, offset = _origin_header(index, 0)
    if len(fields) != 4 or fields[0] != b'COVORIGIN_INDEX2':
        raise ValueError('Missing or incomplete instrumentation generation')
    count, size, checkpoint_size = map(_origin_length, fields[1:])
    if count < 1 or count > len(index):
        raise ValueError('Invalid generation module count')
    recorded_manifest, offset = _origin_part(index, offset, size)
    if recorded_manifest != manifest:
        raise ValueError('Generation manifest does not match the original manifest')
    checkpoint, offset = _origin_part(index, offset, checkpoint_size)
    names = []
    for _ in range(count):
        length, offset = _origin_header(index, offset)
        if len(length) != 1:
            raise ValueError('Invalid generation source identity')
        name, offset = _origin_part(index, offset, _origin_length(length[0]))
        names.append(name.decode('utf-8'))
    if offset != len(index) or len(set(names)) != len(names):
        raise ValueError('Trailing or duplicate generation records')
    expected_checkpoint = canonical(generation_checkpoint(root, build, compiler, flags, mojo, names)) + b'\n'
    if checkpoint != expected_checkpoint or (build / 'generation-inputs.json').read_bytes() != checkpoint:
        raise ValueError('Stale or modified generation origin checkpoint; regenerate with current sources/tools/compiler')
    expected_files = {name + '.cov-origin' for name in names}
    actual_files = {path.relative_to(build).as_posix() for path in build.rglob('*.cov-origin')}
    if actual_files != expected_files:
        raise ValueError('Missing or extra generation origin records; rebuild the stage')
    origins, fragments = {}, []
    for name in names:
        if not name.endswith('.mojo'):
            raise ValueError('Invalid generation module identity')
        original = relative_source(root, name).read_bytes()
        generated = relative_source(build, name).read_bytes()
        raw = relative_source(build, name + '.cov-origin').read_bytes()
        header, cursor = _origin_header(raw, 0)
        if len(header) != 5 or header[0] != b'COVORIGIN1':
            raise ValueError('Malformed source generation origin')
        parts = []
        for length in header[1:]:
            part, cursor = _origin_part(raw, cursor, _origin_length(length))
            parts.append(part)
        if cursor != len(raw) or parts[0].decode('utf-8') != name:
            raise ValueError('Trailing or mixed-module generation origin')
        if original != parts[1] or generated != parts[2]:
            raise ValueError('Source/staged bytes do not match their generation origin: ' + name)
        fragment = parts[3]
        if any(record[1] != name.removesuffix('.mojo') for record in manifest_records(fragment)):
            raise ValueError('Generation fragment identifies another module')
        fragments.append(fragment)
        origins[name] = {'source': sha256(original), 'instrumented': sha256(generated),
                         'origin_sha256': sha256(raw), 'fragment_sha256': sha256(fragment)}
    if b''.join(fragments) != manifest:
        raise ValueError('Generation fragments do not reconstruct the original manifest')
    return {'index_sha256': sha256(index), 'checkpoint_sha256': sha256(checkpoint), 'modules': origins}


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(',', ':'), allow_nan=False).encode()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for piece in iter(lambda: stream.read(1 << 20), b''):
            digest.update(piece)
    return digest.hexdigest()


def relative_source(root, name):
    """Accept only existing, root-contained, ordinary relative source names."""
    relative = PurePosixPath(name)
    if (not name or relative.is_absolute() or '..' in relative.parts
            or relative.as_posix() != name or '\\' in name or ':' in name):
        raise ValueError('Invalid coverage source identity: ' + repr(name))
    path = root / name
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Missing or escaped coverage source: ' + name)
    return path


def manifest_records(raw):
    """Parse the original, unmasked manifest; proof records are never input."""
    records, seen = [], set()
    for line in raw.decode('utf-8').splitlines():
        fields = line.split()
        if not fields:
            continue
        if (fields[0] not in {'L', 'B', 'C', 'M'}
                or len(fields) != (4 if fields[0] in {'C', 'M'} else 3)
                or not re.fullmatch(r'[1-9][0-9]*', fields[2])
                or (len(fields) == 4 and not re.fullmatch(r'0|[1-9][0-9]*', fields[3]))):
            raise ValueError('Malformed original coverage manifest: ' + line)
        module = PurePosixPath(fields[1])
        if (module.is_absolute() or '..' in module.parts or module.as_posix() != fields[1]
                or '\\' in fields[1] or ':' in fields[1]):
            raise ValueError('Invalid coverage source identity: ' + fields[1])
        record = tuple(fields)
        if record in seen:
            raise ValueError('Duplicate coverage manifest entry: ' + line)
        seen.add(record)
        records.append(record)
    return records


def _statements(source):
    """Tokenize a deliberately small lexical subset, failing closed on doubt."""
    # Normalize physical endings for recognition only; source binding uses the
    # original bytes. Quoted text is a single token and cannot add bindings.
    source = source.replace('\r\n', '\n').replace('\r', '\n')
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return None
    if any(token.type == tokenize.ERRORTOKEN for token in tokens):
        return None
    statements, current = [], []
    for token in tokens:
        if token.type in (tokenize.INDENT, tokenize.DEDENT, tokenize.COMMENT,
                          tokenize.NL, tokenize.ENDMARKER):
            continue
        if token.type == tokenize.NEWLINE:
            if current:
                statements.append(current)
                current = []
        else:
            current.append(token)
    if current:
        return None
    return statements


def constant_loops(source):
    """Return source-proved candidates; no dataflow or user code evaluation.

    Only top-level function bodies qualify initially. Methods, nested
    functions and trait/generic name-resolution uncertainty keep both
    outcomes. A module-wide binding veto is stronger than scope guessing.
    """
    statements = _statements(source)
    if statements is None:
        return {}
    names = [token for statement in statements for token in statement
             if token.type == tokenize.NAME]
    wildcard = any(any(token.string == 'import' for token in statement)
                   and any(token.string == '*' for token in statement)
                   for statement in statements)
    if wildcard:
        return {}
    headers, allowed_range_positions, declarations = [], set(), []
    for statement in statements:
        first = statement[0]
        while declarations and declarations[-1][0] >= first.start[1]:
            declarations.pop()
        words = [token.string for token in statement]
        if words[0] in {'def', 'struct', 'trait'} or words[:2] == ['async', 'def']:
            kind = 'def' if words[0] == 'async' else words[0]
            # A generic function's parameters can alter expression bindings.
            name_position = 2 if words[0] == 'async' else 1
            generic = (len(words) > name_position + 1
                       and words[name_position + 1] == '[')
            declarations.append((first.start[1], kind, generic))
            continue
        # Narrow loop target grammar. More complex targets remain unknown.
        if (len(words) < 5 or words[0] != 'for'
                or statement[1].type != tokenize.NAME or words[2] != 'in'
                or words[-1] != ':'):
            continue
        rhs = statement[3:-1]
        if rhs and rhs[0].string == 'range' and len(rhs) > 1 and rhs[1].string == '(':
            allowed_range_positions.add(rhs[0].start)
        supported_scope = (len(declarations) == 1
                           and declarations[0][1] == 'def'
                           and not declarations[0][2])
        if supported_scope:
            headers.append((first.start[0], rhs))
    range_is_builtin = all(token.start in allowed_range_positions
                           for token in names if token.string == 'range')
    list_is_builtin = not any(token.string == 'List' for token in names)
    found = {}
    for line, rhs in headers:
        expression = tokenize.untokenize([(token.type, token.string)
                                         for token in rhs]).strip()
        try:
            node = ast.parse(expression, mode='eval').body
        except (SyntaxError, ValueError, RecursionError):
            continue
        count, kind = None, None
        if (range_is_builtin and isinstance(node, ast.Call)
                and isinstance(node.func, ast.Name) and node.func.id == 'range'
                and not node.keywords and len(node.args) in (1, 2)
                and all(isinstance(arg, ast.Constant) and type(arg.value) is int
                        and 0 <= arg.value <= MAX_ENDPOINT for arg in node.args)):
            values = [arg.value for arg in node.args]
            start, stop = (0, values[0]) if len(values) == 1 else values
            count, kind = max(0, stop - start), 'literal-range'
        elif (list_is_builtin and isinstance(node, ast.List)
              and not any(isinstance(element, ast.Starred) for element in node.elts)):
            count, kind = len(node.elts), 'literal-list'
        if kind is not None:
            found[line] = {'line': line, 'kind': kind, 'cardinality': count,
                           'required': 'T' if count else 'F',
                           'impossible': 'F' if count else 'T',
                           'expression': expression}
    return found


def _counts(records):
    counts = {kind: 0 for kind in ('L', 'B', 'C', 'M')}
    for record in records:
        counts[record[0]] += 1
    counts['potential_outcomes'] = 2 * (counts['B'] + counts['C'])
    counts['potential_total'] = counts['L'] + counts['potential_outcomes'] + counts['M']
    return counts


def _symbolic_path(path, root, build):
    path = Path(path).resolve()
    for token, base in [('@BUILD@', build), ('@ROOT@', root)]:
        if path.is_relative_to(base):
            relative = path.relative_to(base).as_posix()
            return token if relative == '.' else token + '/' + relative
    return str(path)


def _executable(value, root):
    path = root / value if '/' in value else Path(shutil.which(value) or '')
    if not path.is_file():
        raise ValueError('Missing capture executable: ' + value)
    return path.resolve()


def _command_identity(command, root, build):
    words = shlex.split(command) if isinstance(command, str) else list(command)
    if not words:
        raise ValueError('Compiler invocation identity is required')
    result = []
    for index, word in enumerate(words):
        path = _executable(word, root) if index == 0 else root / word
        if index and not path.is_file() and shutil.which(word):
            path = Path(shutil.which(word))
        if path.is_file():
            result.append({'path': _symbolic_path(path, root, build),
                           **coverage_toolchain_identity.executable_identity(path)})
        else:
            result.append({'literal': word})
    return result


def generation_checkpoint(root, build, compiler, flags, mojo, sources):
    root, build = Path(root).resolve(), Path(build).resolve()
    names = list(sources)
    if not names or len(names) != len(set(names)):
        raise ValueError('Generation requires distinct source identities')
    for name in names:
        if not name.endswith('.mojo'):
            raise ValueError('Generation source must be a Mojo module')
        relative_source(root, name)
    return {'schema': 'coverage-generation-v1', 'root_inputs': maintained_inputs(root, exclude=build),
            'python': sys.version, 'compiler': compiler, 'flags': flags,
            'compiler_command': _command_identity(mojo or ['.venv/bin/mojo'], root, build),
            'producer_arguments': ['run', *shlex.split(flags), 'coverage/build_cli.mojo', '@BUILD@', *names],
            'sources': names}


def begin_generation(root, build, compiler, flags, *, mojo=None, sources):
    """Checkpoint before loading/compiling the trusted producer, never after."""
    build = Path(build)
    build.mkdir(parents=True, exist_ok=True)
    (build / 'origins.ready').write_bytes(b'')
    path = build / 'generation-inputs.json'
    path.unlink(missing_ok=True)
    checkpoint = generation_checkpoint(root, build, compiler, flags, mojo, sources)
    path.write_bytes(canonical(checkpoint) + b'\n')
    return checkpoint


def execution_contract(root, build, inputs, *, mojo=None, capture_cache=None, suites=None):
    """Bind the maintained capture wrappers, compiler and exact run flags."""
    selected = (sorted(name for name in inputs if name.startswith('tests/test_')
                       and name.endswith('.mojo')) if suites is None else sorted(suites))
    if len(set(selected)) != len(selected) or any(name not in inputs for name in selected):
        raise ValueError('Capture suite inventory is invalid or not staged')
    cache = root / '.cache/native-coverage' if capture_cache is None else root / capture_cache
    return {'schema': 'coverage-execution-v1',
            'python': {'path': _symbolic_path(Path(sys.executable), root, build),
                       'sha256': file_sha256(Path(sys.executable).resolve())},
            'compiler': _command_identity(mojo or ['.venv/bin/mojo'], root, build),
            'cache': _symbolic_path(cache, root, build), 'suites': selected,
            'cc': os.environ.get('CC', 'cc'),
            'native_compiler': _command_identity(os.environ.get('CC', 'cc'), root, build),
            'profiles': ['raw', 'aot', 'aot-hits'],
            'capture_flags': ['run', '-I', '@BUILD@', '@SUITE@']}


def expected_capture_command(contract, suite, profile):
    if suite not in contract['suites'] or profile not in contract['profiles']:
        raise ValueError('Capture suite/profile is outside the sealed execution contract')
    runner = (['@ROOT@/tools/native_test_support.py', 'run'] if profile == 'raw'
              else ['@ROOT@/tools/coverage_hit_aot.py', '--profile', profile])
    compiler = [item.get('path', item.get('literal')) for item in contract['compiler']]
    return [contract['python']['path'], *runner, '--root', '@BUILD@',
            '--suite', '@BUILD@/' + suite, '--cache', contract['cache'], '--',
            *compiler, 'run', '-I', '@BUILD@', '@BUILD@/' + suite]


def validate_capture_command(command, envelope, root, build, capture=None, output=None):
    """Validate actual argv before launch; record only its checked canonical form."""
    root, build = Path(root).resolve(), Path(build).resolve()
    contract = envelope['receipt']['execution']
    if not command or not all(isinstance(word, str) for word in command):
        raise ValueError('Coverage capture command identity is required')
    try:
        source = Path(command[command.index('--suite') + 1])
        suite = (root / source).resolve().relative_to(build).as_posix()
    except (ValueError, IndexError):
        raise ValueError('Capture command does not identify a staged suite') from None
    profile = 'raw'
    if '--profile' in command:
        try:
            profile = command[command.index('--profile') + 1]
        except IndexError:
            raise ValueError('Missing capture execution profile') from None
    expected = expected_capture_command(contract, suite, profile)
    if len(command) != len(expected):
        raise ValueError('Capture command differs from its sealed execution contract')
    for index, (actual, wanted) in enumerate(zip(command, expected)):
        is_path = wanted.startswith(('@ROOT@', '@BUILD@', '/'))
        if index == 0:
            normalized = _symbolic_path(_executable(actual, root), root, build)
        elif is_path:
            normalized = _symbolic_path(root / actual, root, build)
        else:
            normalized = actual
        if normalized != wanted:
            raise ValueError('Capture command differs from its sealed execution contract')
    if os.environ.get('CC', 'cc') != contract['cc']:
        raise ValueError('Capture native-compiler setting differs from its sealed contract')
    stem = Path(suite).stem
    if capture is not None and Path(capture).name != stem + '.txt.gz':
        raise ValueError('Capture filename does not identify its sealed suite')
    if output is not None and Path(output).name != stem + '.out':
        raise ValueError('Capture stdout filename does not identify its sealed suite')
    return {'suite': suite, 'profile': profile, 'command': expected}


def _expand_path(value, root, build):
    for token, base in [('@ROOT@', root), ('@BUILD@', build)]:
        if value == token:
            return str(base)
        if value.startswith(token + '/'):
            return str(base / value[len(token) + 1:])
    return value


def check_capture_inputs(envelope, root, build):
    """Check sealed bytes before/after execution without reparsing all loops."""
    root, build = Path(root).resolve(), Path(build).resolve()
    receipt = envelope['receipt']
    if (maintained_inputs(root, exclude=build) != receipt['root_inputs']
            or maintained_inputs(build, staged=True)
            != {name: item['instrumented'] for name, item in receipt['inputs'].items()}
            or file_sha256(build / 'manifest.txt') != receipt['manifest_sha256']
            or file_sha256(build / 'origins.ready') != receipt['generation']['index_sha256']
            or file_sha256(build / 'generation-inputs.json') != receipt['generation']['checkpoint_sha256']):
        raise ValueError('Stale or modified capture input binding')
    expected_origins = {name + '.cov-origin': item['origin_sha256']
                        for name, item in receipt['generation']['modules'].items()}
    actual_origins = {path.relative_to(build).as_posix(): file_sha256(path)
                      for path in build.rglob('*.cov-origin')}
    if actual_origins != expected_origins:
        raise ValueError('Stale or modified capture generation origins')
    for name, active in [('tools/coverage_loop_proofs.py', ACTIVE_SOURCE_SHA256),
                         ('tools/cache_key.py', ACTIVE_INVENTORY_SHA256),
                         ('tools/coverage_toolchain_identity.py', ACTIVE_TOOLCHAIN_SHA256)]:
        if receipt['root_inputs'][name] != active:
            raise ValueError('Stale or modified executing capture verifier')
    contract = receipt['execution']
    command = [_expand_path(item['path'], root, build) if 'path' in item else item['literal']
               for item in contract['compiler']]
    current = execution_contract(root, build, receipt['inputs'], mojo=command,
                                 capture_cache=_expand_path(contract['cache'], root, build),
                                 suites=contract['suites'])
    if current != contract or receipt['python'] != sys.version:
        raise ValueError('Stale or modified capture compiler/execution identity')


def build_receipt(root, build, compiler, flags, *, mojo=None, capture_cache=None, suites=None):
    """Rederive proofs from a verified generation and maintained input closure."""
    root, build = Path(root).resolve(), Path(build).resolve()
    raw = (build / 'manifest.txt').read_bytes()
    records = manifest_records(raw)
    branches = {(record[1], int(record[2])) for record in records if record[0] == 'B'}
    modules = sorted({record[1] for record in records})
    root_inputs = maintained_inputs(root, exclude=build)
    tools = {name: root_inputs[name] for name in TOOL_INPUTS}
    if tools['tools/coverage_loop_proofs.py'] != ACTIVE_SOURCE_SHA256:
        raise ValueError('Stale or modified executing proof tool binding')
    if tools['tools/cache_key.py'] != ACTIVE_INVENTORY_SHA256:
        raise ValueError('Stale or modified executing inventory tool binding')
    if tools['tools/coverage_toolchain_identity.py'] != ACTIVE_TOOLCHAIN_SHA256:
        raise ValueError('Stale or modified executing toolchain identity binding')
    generation = generation_origins(root, build, raw, compiler, flags, mojo)
    staged_inputs = maintained_inputs(build, staged=True)
    inputs = {}
    for name, digest in staged_inputs.items():
        if name not in root_inputs:
            raise ValueError('Unmaintained executable input in stage: ' + name)
        expected = generation['modules'].get(name, {}).get('instrumented', root_inputs[name])
        if digest != expected:
            raise ValueError('Staged input differs from generation or passthrough source: ' + name)
        inputs[name] = {'source': root_inputs[name], 'instrumented': digest}
    for module in modules:
        if module + '.mojo' not in generation['modules']:
            raise ValueError('Manifest module has no generation origin: ' + module)
    proofs = []
    for module in modules:
        name = module + '.mojo'
        original = relative_source(root, name)
        if name not in inputs:
            raise ValueError('Missing instrumented module: ' + module)
        candidates = constant_loops(original.read_text(encoding='utf-8'))
        for line in sorted(candidates):
            if (module, line) not in branches:
                continue  # Existing exclusions cannot become new proofs.
            if any(record[0] in {'C', 'M'} and record[1] == module
                   and int(record[2]) == line for record in records):
                raise ValueError('Loop proof conflicts with compound decision: ' + module)
            proofs.append({'module': module, **candidates[line],
                           'source_sha256': inputs[name]['source']})
    counts = _counts(records)
    counts['proven_impossible'] = len(proofs)
    counts['required_total'] = counts['potential_total'] - len(proofs)
    return {'schema': SCHEMA, 'python': sys.version,
            'compiler': compiler, 'flags': flags,
            'manifest_sha256': sha256(raw), 'tools': tools,
            'root_inputs': root_inputs, 'inputs': inputs, 'generation': generation,
            'execution': execution_contract(root, build, inputs, mojo=mojo,
                                            capture_cache=capture_cache, suites=suites),
            'proofs': proofs, 'denominator': counts}


def _load_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate receipt key: ' + key)
            result[key] = value
        return result
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=pairs)


def read_receipt(path):
    envelope = _load_json(path)
    if not isinstance(envelope, dict) or set(envelope) != {'receipt', 'sha256'}:
        raise ValueError('Malformed loop-proof receipt')
    receipt = envelope['receipt']
    if not isinstance(receipt, dict) or receipt.get('schema') != SCHEMA:
        raise ValueError('Unsupported loop-proof schema')
    if envelope['sha256'] != sha256(canonical(receipt)):
        raise ValueError('Loop-proof receipt digest mismatch')
    return envelope


def seal(root, build, compiler, flags, **settings):
    receipt = build_receipt(root, build, compiler, flags, **settings)
    envelope = {'receipt': receipt, 'sha256': sha256(canonical(receipt))}
    path = Path(build) / 'loop-proofs.json'
    path.write_bytes(canonical(envelope) + b'\n')
    return envelope


def verify(path, root, build, compiler, flags, **settings):
    saved = read_receipt(path)
    expected = build_receipt(root, build, compiler, flags, **settings)
    if canonical(saved['receipt']) != canonical(expected):
        raise ValueError('Stale or modified loop proof, source, tool, manifest, or compiler binding')
    return saved


def masked_manifest(raw, envelope):
    """Preserve all original entries except the explicit outcome masks."""
    receipt = envelope['receipt']
    if sha256(raw) != receipt['manifest_sha256']:
        raise ValueError('Loop-proof manifest binding mismatch')
    manifest_records(raw)
    masks = {(proof['module'], str(proof['line'])): proof for proof in receipt['proofs']}
    rows = ['P ' + SCHEMA + ' ' + envelope['sha256']]
    used = set()
    for line in raw.decode('utf-8').splitlines():
        fields = line.split()
        key = tuple(fields[1:3])
        if fields and fields[0] == 'B' and key in masks:
            proof = masks[key]
            line = ' '.join(['R', *key, proof['required'], proof['kind'], str(proof['cardinality'])])
            used.add(key)
        rows.append(line)
    if used != set(masks):
        raise ValueError('Loop proof does not identify one original branch')
    return ('\n'.join(rows) + '\n').encode('utf-8')


def capture_receipt_path(capture):
    return Path(str(capture) + '.proof.json')


def bind_capture(capture, output, envelope, command, *, root, build):
    """Called only after a successful, complete instrumented capture."""
    capture, output = Path(capture), Path(output)
    execution = validate_capture_command(command, envelope, root, build, capture, output)
    payload = {'schema': SCHEMA, 'proof_sha256': envelope['sha256'],
               'capture': capture.name, 'capture_sha256': file_sha256(capture),
               'output': output.name, 'output_sha256': file_sha256(output),
               **execution}
    capture_receipt_path(capture).write_bytes(canonical(payload) + b'\n')


def verify_captures(captures, envelope):
    for capture in captures:
        capture = Path(capture)
        binding = _load_json(capture_receipt_path(capture))
        expected_keys = {'schema', 'proof_sha256', 'capture', 'capture_sha256', 'output', 'output_sha256', 'command', 'suite', 'profile'}
        if not isinstance(binding, dict) or set(binding) != expected_keys:
            raise ValueError('Malformed coverage capture receipt: ' + capture.name)
        name = binding['output']
        if (not isinstance(binding['command'], list) or not binding['command']
                or not all(isinstance(argument, str) for argument in binding['command'])):
            raise ValueError('Missing coverage capture command identity')
        expected = expected_capture_command(envelope['receipt']['execution'],
                                            binding['suite'], binding['profile'])
        if binding['command'] != expected:
            raise ValueError('Modified capture command provenance')
        stem = Path(binding['suite']).stem
        if binding['capture'] != stem + '.txt.gz' or binding['output'] != stem + '.out':
            raise ValueError('Capture files do not identify the recorded suite')
        if not isinstance(name, str) or Path(name).name != name or name in {'', '.', '..'}:
            raise ValueError('Invalid coverage output identity')
        if (binding['schema'] != SCHEMA or binding['proof_sha256'] != envelope['sha256']
                or binding['capture'] != capture.name
                or binding['capture_sha256'] != file_sha256(capture)
                or binding['output_sha256'] != file_sha256(capture.parent / name)):
            raise ValueError('Stale or modified coverage capture: ' + capture.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['begin', 'seal', 'verify'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--flags', required=True)
    parser.add_argument('--mojo', required=True)
    parser.add_argument('--capture-cache')
    parser.add_argument('--suites', nargs='*')
    parser.add_argument('--sources', nargs='*')
    args = parser.parse_args()
    if args.mode == 'begin':
        begin_generation(args.root, args.build, args.compiler, args.flags,
                         mojo=args.mojo, sources=args.sources or [])
        print('Coverage generation checkpoint prepared')
        return
    if args.mode == 'seal':
        envelope = seal(args.root, args.build, args.compiler, args.flags,
                        mojo=args.mojo, capture_cache=args.capture_cache, suites=args.suites)
    else:
        envelope = verify(args.build / 'loop-proofs.json', args.root, args.build,
                          args.compiler, args.flags, mojo=args.mojo,
                          capture_cache=args.capture_cache, suites=args.suites)
    print('Loop proofs:', envelope['sha256'],
          json.dumps(envelope['receipt']['denominator'], sort_keys=True))


if __name__ == '__main__':
    main()
