# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check direct-call types in emitted Metal kernel AIR.

Mojo can drop a device pointer's `addrspace(1)` where the pointer crosses a
call or rides in a struct. The call then passes `ptr addrspace(1)` to a
function that declares `ptr`, or the reverse. LLVM's verifier accepts that
under opaque pointers, but Apple's air-lld linker segfaults on it and Mojo
reports only "Metal Compiler failed to compile metallib"
(modular/modular#7238).

This bounded checker compares direct calls with definitions or declarations
using scalar, opaque-pointer and literal aggregate types. It requires one
nonempty module with a function body for every discovered kernel. Missing
signatures and unsupported call/type syntax fail closed; this is not an LLVM
verifier or a GPU execution test. Run with `make check-gpu-air`.
"""

import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
# Kernels are launched from these modules. Each `enqueue_function[name]`
# with a plain name is checked.
MODULES = ('render/gpu.mojo', 'render/gpu_vxgi.mojo')
TARGET = 'metal:4'
SEPARATOR = '; ===== kernel '
ENTRY = '; ===== entry '


class AirError(ValueError):
    """Missing, malformed or unsupported input cannot count as a pass."""


_QUOTED = re.compile(r'"(?:[^"\\\n]|\\[0-9a-fA-F]{2})*"')
_NAME = r'("(?:[^"\\\n]|\\[0-9a-fA-F]{2})*"|[-\w.$]+)'
_SYMBOL = re.compile(r'@' + _NAME + r'\s*\(')
_PAIRS = {'(': ')', '{': '}', '[': ']', '<': '>'}


def quoted_end(text, start):
    found = _QUOTED.match(text, start)
    if not found:
        raise AirError('unterminated or unsupported quoted string')
    return found.end()


def group_end(text, start):
    """Return the end of a balanced group, respecting quoted symbols."""
    stack = []
    index = start
    while index < len(text):
        char = text[index]
        if char == '"':
            index = quoted_end(text, index)
            continue
        if char in _PAIRS:
            stack.append(_PAIRS[char])
        elif char in _PAIRS.values():
            if not stack or stack.pop() != char:
                raise AirError(f'unbalanced delimiters: {text[:80]}')
            if not stack:
                return index + 1
        index += 1
    raise AirError(f'unbalanced delimiters: {text[:80]}')


def split_top(text):
    """Split a parameter or argument list at its top-level commas."""
    if not text.strip():
        return []
    parts, start, index = [], 0, 0
    while index < len(text):
        char = text[index]
        if char == '"':
            index = quoted_end(text, index)
            continue
        if char in _PAIRS:
            index = group_end(text, index)
            continue
        if char in _PAIRS.values():
            raise AirError(f'unbalanced delimiters: {text[:80]}')
        if char == ',':
            parts.append(text[start:index].strip())
            start = index + 1
        index += 1
    parts.append(text[start:].strip())
    if any(not part for part in parts):
        raise AirError('empty parameter or argument')
    return parts


def parenthesized(line, start):
    return line[start + 1:group_end(line, start) - 1]


def read_type(item):
    """Return (canonical type, unconsumed suffix) for supported AIR types."""
    item = item.strip()
    scalar = re.match(r'(void|i[1-9][0-9]*|half|bfloat|float|double|fp128|'
                      r'x86_fp80|ppc_fp128|ptr)\b', item)
    if scalar:
        kind, end = scalar.group(0), scalar.end()
        space = re.match(r'\s+addrspace\(\s*([0-9]+)\s*\)', item[end:])
        if kind == 'ptr' and space:
            kind += f' addrspace({int(space.group(1))})'
            end += space.end()
        if end < len(item) and not item[end].isspace():
            raise AirError(f'unsupported type: {item[:80]}')
        return kind, item[end:].strip()
    if item and item[0] in '{[<':
        end = group_end(item, 0)
        inside = item[1:end - 1].strip()
        if item[0] == '{':
            fields = [complete_type(field) for field in split_top(inside)]
            kind = '{ ' + ', '.join(fields) + ' }'
        elif item[0] == '<' and inside.startswith('{'):
            kind = '<' + complete_type(inside) + '>'
        else:
            sequence = re.fullmatch(r'((?:vscale\s+x\s+)?[0-9]+)\s+x\s+(.+)',
                                    inside)
            if not sequence or (item[0] == '[' and 'vscale' in inside):
                raise AirError(f'unsupported type: {item[:80]}')
            count = ' '.join(sequence.group(1).split())
            kind = item[0] + count + ' x ' + complete_type(sequence.group(2))
            kind += _PAIRS[item[0]]
        return kind, item[end:].strip()
    raise AirError(f'missing or unsupported type: {item[:80]}')


def complete_type(item):
    kind, rest = read_type(item)
    if rest or kind == 'void':
        raise AirError(f'unsupported aggregate element: {item[:80]}')
    return kind


def type_of(item):
    """Return a parameter/argument type, without its value or attributes."""
    kind, rest = read_type(item)
    if kind == 'void' or rest.startswith(('addrspace', '*', '(')):
        raise AirError(f'unsupported parameter or argument: {item[:80]}')
    return kind


_ATTRIBUTES = re.compile(
    r'^(?:(?:internal|private|external|dso_local|dso_preemptable|hidden|'
    r'protected|default|linkonce|linkonce_odr|weak|weak_odr|available_externally|'
    r'dllimport|dllexport|ccc|fastcc|coldcc|noundef|nonnull|noalias|zeroext|'
    r'signext|fast|nnan|ninf|nsz|arcp|contract|afn|reassoc)\s+)*')
_CALL = re.compile(r'(?:(?:%"(?:[^"\\]|\\[0-9a-fA-F]{2})*"|%[-\w.$]+)'
                   r'\s*=\s*)?(?:(?:tail|musttail|notail)\s+)?'
                   r'(call|invoke|callbr)\b')
_ARG_ATTRIBUTES = re.compile(
    r'^(?:(?:noundef|nonnull|noalias|nocapture|readonly|readnone|writeonly|'
    r'immarg|inreg|returned|nest|swiftself|swifterror|zeroext|signext|'
    r'align\s+[0-9]+|dereferenceable(?:_or_null)?\([0-9]+\))\s+)*')


def argument_type(item):
    kind = type_of(item)
    _, rest = read_type(item)
    # A value must remain after recognized attributes. This is deliberately
    # not a verifier for constant expressions or aggregate value contents.
    value = _ARG_ATTRIBUTES.sub('', rest + ' ').strip()
    if not value:
        raise AirError('call argument has no value')
    # These are the additional literal forms observed in the pinned Metal
    # emitter, rather than a blanket acceptance of arbitrary value keywords.
    floating = r'(?:f0x[0-9A-Fa-f]{8}|[+\-]?[0-9]+\.[0-9]*(?:[eE][+\-]?[0-9]+)?)'
    if value.startswith('f0x'):
        if kind != 'float' or not re.fullmatch(r'f0x[0-9A-Fa-f]{8}', value):
            raise AirError('unsupported f0x literal')
        return kind
    if value.startswith('splat'):
        if (not re.fullmatch(r'<[1-9][0-9]* x float>', kind) or
                not re.fullmatch(r'splat\s*\(\s*float\s+' + floating + r'\s*\)', value)):
            raise AirError('unsupported splat literal')
        return kind
    if not re.match(r'(?:[%@]|[+\-0-9]|true\b|false\b|null\b|undef\b|poison\b|'
                    r'zeroinitializer\b|[\[{<]|(?:getelementptr|bitcast|inttoptr|'
                    r'ptrtoint|addrspacecast|blockaddress)\b)', value):
        raise AirError(f'unsupported call argument value or attributes: {item[:80]}')
    # Validate delimiter/quote balance even though value semantics are outside
    # this check (including commas within an aggregate or constant expression).
    split_top(value)
    return kind


def signature_suffix(tail, definition=False):
    """Check the supported attribute/metadata suffix, not LLVM attribute semantics."""
    if definition:
        if not tail.endswith('{'):
            raise AirError('definition has no opening body brace')
        tail = tail[:-1].strip()
    attribute = re.compile(
        r'(?:#[0-9]+|local_unnamed_addr|unnamed_addr|nounwind|willreturn|'
        r'noreturn|norecurse|nosync|nofree|readnone|readonly|writeonly|'
        r'convergent|mustprogress|alwaysinline|noinline|optnone|optsize|'
        r'minsize|speculatable|nocallback|cold|hot|nobuiltin|builtin|'
        r'align\s+[0-9]+|addrspace\([0-9]+\)|memory\((?:none|read|write|readwrite)\))'
        r'(?=\s|,|$)')
    while tail:
        found = attribute.match(tail)
        if not found:
            break
        tail = tail[found.end():].strip()
    if tail and not re.fullmatch(r'(?:,?\s*![\w.]+\s+![0-9]+\s*)+', tail):
        raise AirError(f'unsupported signature/call suffix: {tail[:80]}')


def symbol_name(name):
    if name.startswith('"'):
        return re.sub(r'\\([0-9a-fA-F]{2})',
                      lambda match: chr(int(match.group(1), 16)), name[1:-1])
    return name


def signature(text):
    found = _SYMBOL.search(text)
    if not found:
        raise AirError(f'missing or unsupported direct-call signature: {text[:80]}')
    name = symbol_name(found.group(1))
    returned, rest = read_type(_ATTRIBUTES.sub('', text[:found.start()]).strip())
    if rest:
        raise AirError(f'unsupported return/call signature: {text[:80]}')
    start = found.end() - 1
    end = group_end(text, start)
    items = split_top(text[start + 1:end - 1])
    return name, returned, items, text[end:].strip()


def clean_line(line):
    """Remove LLVM comments without treating semicolons in quotes as comments."""
    index = 0
    while index < len(line):
        if line[index] == '"':
            index = quoted_end(line, index)
        elif line[index] == ';':
            return line[:index].strip()
        else:
            index += 1
    return line.strip()


def emitted_symbol(air):
    """Read one entry name emitted from the same CompiledFunctionInfo as asm."""
    lines = air.splitlines()
    entries = [line[len(ENTRY):] for line in lines if line.startswith(ENTRY)]
    if len(entries) != 1 or not entries[0] or not lines[0].startswith(ENTRY):
        raise AirError('missing, duplicate or misplaced emitted entry name')
    return entries[0]


def kernel_entry(air, definitions, expected):
    """Bind !air.kernel to the exact compiler-returned function_name.

    The observed single-entry metadata form selects a defined function with
    a metal.kernel attribute. Source-name prefixes are insufficient because
    the compiler truncates them and includes specialization text. No Mojo
    mangling or demangling rule is assumed.
    """
    expected_symbol = emitted_symbol(air)
    metadata, attributes = {}, {}
    for raw in air.splitlines():
        line = clean_line(raw)
        found = re.fullmatch(r'(!(?:air\.kernel|[0-9]+))\s*=\s*(.*)', line)
        if found:
            key, value = found.groups()
            if key in metadata:
                raise AirError(f'duplicate metadata: {key}')
            metadata[key] = value
        found = re.fullmatch(r'attributes\s+#([0-9]+)\s*=\s*(\{.*\})', line)
        if found:
            key, value = found.groups()
            if key in attributes:
                raise AirError(f'duplicate attribute group: #{key}')
            attributes[key] = value
    reference = re.fullmatch(r'!\{\s*(![0-9]+)\s*\}',
                             metadata.get('!air.kernel', ''))
    if not reference:
        raise AirError('missing or unsupported single-entry !air.kernel metadata')
    node = metadata.get(reference.group(1), '')
    if not node.startswith('!{') or not node.endswith('}'):
        raise AirError('missing or unsupported kernel entry metadata node')
    operands = split_top(node[2:-1])
    entry = re.fullmatch(r'ptr\s+@' + _NAME, operands[0]) if operands else None
    if (not entry or len(operands) != 3 or
            any(not re.fullmatch(r'![0-9]+', item) for item in operands[1:])):
        raise AirError('unsupported kernel entry metadata operands')
    if any(item not in metadata for item in operands[1:]):
        raise AirError('missing kernel argument metadata')
    name = symbol_name(entry.group(1))
    if name not in definitions:
        raise AirError(f'kernel entry has no function body: {name}')
    if name != expected_symbol:
        raise AirError(f'kernel entry {name} does not match compiler-returned '
                       f'entry {expected_symbol} for {expected[0]}:{expected[1]}')
    groups = re.findall(r'#([0-9]+)', definitions[name])
    if not any(re.search(r'"metal\.kernel"\s*=\s*"true"', attributes.get(g, ''))
               for g in groups):
        raise AirError(f'kernel entry lacks metal.kernel attribute: {name}')


def mismatches(air, expected_kernel=None):
    """Compare supported direct calls; reject uncheckable input with AirError.

    A body must close and contain a recognized terminator. Function headers
    and calls must each fit on one line. Indirect calls,
    invoke/callbr, explicit function types, varargs and named types are not
    supported. Other instructions and argument values are not LLVM-verified.
    """
    signatures, calls, definitions = {}, [], {}
    active, body = None, False
    for number, raw in enumerate(air.splitlines(), 1):
        line = clean_line(raw)
        if not line:
            continue
        try:
            if re.match(r'(define|declare)\b', line):
                if active is not None:
                    raise AirError('nested function or missing closing brace')
                form, text = line.split(None, 1)
                name, returned, items, tail = signature(text)
                signature_suffix(tail, definition=form == 'define')
                types = [type_of(item) for item in items]
                current = (returned, types)
                if name in signatures and signatures[name] != current:
                    raise AirError(f'conflicting signatures for {name}')
                signatures[name] = current
                if form == 'define':
                    if name in definitions or not tail.endswith('{'):
                        raise AirError(f'duplicate or incomplete definition for {name}')
                    definitions[name] = tail
                    active, body = name, False
                elif '{' in tail or '}' in tail:
                    raise AirError(f'body on declaration for {name}')
                continue
            if line == '}':
                if active is None or not body:
                    raise AirError('missing function body or recognized terminator')
                active = None
                continue
            if line.endswith(':'):
                if active is None:
                    raise AirError('label outside function')
                continue
            call = _CALL.match(line)
            if call and active is None:
                raise AirError('call outside function')
            if active is None:
                if not re.match(r'(?:source_filename\s*=|target\s+|module\s+asm\s+|'
                                r'attributes\s+#[0-9]+\s*=|[!@$%])', line):
                    raise AirError('unrecognized output outside function')
                continue
            if call:
                if call.group(1) != 'call':
                    raise AirError('unsupported call instruction')
                name, returned, items, tail = signature(line[call.end():].strip())
                signature_suffix(tail)
                args = [argument_type(item) for item in items]
                calls.append((name, returned, args))
            if re.match(r'(?:ret|br|switch|indirectbr|unreachable|resume|'
                        r'catchret|cleanupret)\b', line):
                body = True
        except (AirError, ValueError) as exc:
            raise AirError(f'line {number}: {exc}') from exc
    if active is not None:
        raise AirError(f'unterminated function body: {active}')
    if not definitions:
        raise AirError('AIR module has no function body')
    if expected_kernel is not None:
        kernel_entry(air, definitions, expected_kernel)
    found_bad = []
    for name, returned, args in calls:
        if name not in signatures:
            raise AirError(f'missing definition or declaration for callee {name}')
        expected_return, params = signatures[name]
        if returned != expected_return:
            found_bad.append((name, f'returns {returned}, declared {expected_return}'))
        if len(args) != len(params):
            found_bad.append((name, f'{len(args)} arguments, declared {len(params)}'))
            continue
        for index, (arg, param) in enumerate(zip(args, params)):
            if arg != param:
                found_bad.append((name, f'argument {index} is {arg}, declared {param}'))
    return found_bad


def kernels(root):
    """Return (module, kernel) for each plainly named kernel launch."""
    out = []
    for module in MODULES:
        text = (root / module).read_text()
        for name in sorted(set(re.findall(
                r'enqueue_function\[(\w+)\]', text))):
            if re.search(rf'\ndef {name}\(', text):
                out.append((module, name))
    return out


def emitted_modules(stdout, found):
    """Require exactly one nonempty record for every expected kernel."""
    expected = {f'{module}:{name}' for module, name in found}
    if not expected or len(expected) != len(found):
        raise AirError('kernel discovery is empty or contains duplicate entries')
    records, symbols, label, body = {}, set(), None, []

    def finish():
        if label is not None:
            module = '\n'.join(body)
            if not module.strip():
                raise AirError(f'empty AIR record: {label}')
            symbol = emitted_symbol(module)
            if symbol in symbols:
                raise AirError(f'emitted entry reused across kernel records: {symbol}')
            symbols.add(symbol)
            records[label] = module

    for line in stdout.splitlines():
        if line.startswith(SEPARATOR):
            finish()
            label = line[len(SEPARATOR):]
            if label not in expected:
                raise AirError(f'unexpected AIR record: {label}')
            if label in records:
                raise AirError(f'duplicate AIR record: {label}')
            body = []
        elif label is None:
            if line.strip():
                raise AirError('unexpected output before first AIR record')
        else:
            body.append(line)
    finish()
    missing = expected - records.keys()
    if missing:
        raise AirError('missing AIR records: ' + ', '.join(sorted(missing)))
    return records


def emit(root, mojo, found):
    """Return each kernel's AIR, from one generated program."""
    if not found:
        raise AirError('no kernels discovered')
    lines = ['from max.gpu.host.compile import _compile_code, '
             'get_gpu_target']
    # Two modules can name a kernel alike, so each is imported by number.
    for index, (module, name) in enumerate(found):
        package = module[:-len('.mojo')].replace('/', '.')
        lines.append(f'from {package} import {name} as kernel_{index}')
    lines += ['', '', 'def main() raises:']
    for index, (module, name) in enumerate(found):
        lines.append(f'    var compiled_{index} = _compile_code[kernel_{index}, '
                     f'emission_kind="asm", '
                     f'target = get_gpu_target["{TARGET}"]()]()')
        lines.append(f'    print("{SEPARATOR}{module}:{name}")')
        lines.append(f'    print("{ENTRY}" + String(compiled_{index}.function_name))')
        lines.append(f'    print(compiled_{index}.asm)')
    with tempfile.TemporaryDirectory(prefix='threemojo-air-') as folder:
        program = Path(folder) / 'emit_air.mojo'
        program.write_text('\n'.join(lines) + '\n')
        result = subprocess.run(
            [mojo, 'run', '-I', str(root), str(program)], cwd=root,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=1800)
    if result.returncode != 0:
        raise RuntimeError('AIR emission failed:\n' + result.stderr[-4000:])
    return emitted_modules(result.stdout, found)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    args = parser.parse_args(argv)
    mojo = str(Path(args.mojo).resolve())
    failed = 0
    try:
        found = kernels(ROOT)
        records = emit(ROOT, mojo, found)
        for name, air in records.items():
            try:
                bad = mismatches(air, tuple(name.split(':', 1)))
            except AirError as exc:
                raise AirError(f'{name}: {exc}') from exc
            for callee, detail in bad:
                print(f'{name}: call to {callee}: {detail}', file=sys.stderr)
            failed += len(bad)
    except (AirError, RuntimeError, OSError, subprocess.SubprocessError) as exc:
        print(f'AIR check failed: {exc}', file=sys.stderr)
        return 1
    if failed:
        print(f'{failed} call type mismatches; see modular/modular#7238. Give '
              'every device pointer an explicit address space '
              '(`DevicePointer` in render/gpu.mojo).', file=sys.stderr)
        return 1
    print(f'PASS {len(records)} Metal kernel AIR modules: '
          'supported direct-call types match definitions/declarations')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
