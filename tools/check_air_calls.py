# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check that every call in the Metal kernels matches its callee's types.

Mojo can drop a device pointer's `addrspace(1)` where the pointer crosses a
call or rides in a struct. The call then passes `ptr addrspace(1)` to a
function that declares `ptr`, or the reverse. LLVM's verifier accepts that
under opaque pointers, but Apple's air-lld linker segfaults on it and Mojo
reports only "Metal Compiler failed to compile metallib"
(modular/modular#7238). This tool emits each kernel's AIR for a Metal
target, which needs no Apple toolchain and no GPU, and fails on any call
whose argument or return types differ from the callee's.

Run with `make check-gpu-air`.
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


def split_top(text):
    """Split a parameter or argument list at its top-level commas."""
    parts, depth, current = [], 0, ''
    for char in text:
        if char in '{[<(':
            depth += 1
        elif char in '}]>)':
            depth -= 1
        if char == ',' and depth == 0:
            parts.append(current.strip())
            current = ''
        else:
            current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def parenthesized(line, start):
    """Return the text inside the parentheses that open at `start`."""
    depth = 0
    for index in range(start, len(line)):
        if line[index] == '(':
            depth += 1
        elif line[index] == ')':
            depth -= 1
            if depth == 0:
                return line[start + 1:index]
    raise ValueError(f'unbalanced parentheses: {line[:80]}')


def type_of(item):
    """Return the type of one parameter or argument, without its name,
    value or attributes. An address space belongs to the type."""
    depth = 0
    index = 0
    while index < len(item):
        char = item[index]
        if char in '{[<(':
            depth += 1
        elif char in '}]>)':
            depth -= 1
        elif char == ' ' and depth == 0:
            if item[index + 1:].startswith('addrspace('):
                index = item.index(')', index) + 1
                continue
            return item[:index]
        index += 1
    return item


_ATTRIBUTES = re.compile(
    r'^(?:(?:internal|private|dso_local|hidden|linkonce_odr|weak_odr|'
    r'fastcc|noundef|nonnull|noalias|zeroext|signext)\s+)*')


def mismatches(air):
    """Return (callee, detail) for each call whose types differ from the
    callee's definition."""
    params, returns = {}, {}
    for line in air.splitlines():
        if line.startswith('define '):
            found = re.search(r'@([\w.$]+)\(', line)
            name = found.group(1)
            params[name] = [type_of(p) for p in
                            split_top(parenthesized(line, found.end() - 1))]
            returns[name] = _ATTRIBUTES.sub(
                '', line[len('define '):found.start()]).strip()
    found_bad = []
    for line in air.splitlines():
        for call in re.finditer(r'call ([^@]*)@([\w.$]+)\(', line):
            name = call.group(2)
            if name not in params:
                continue
            args = [type_of(a) for a in
                    split_top(parenthesized(line, call.end() - 1))]
            returned = _ATTRIBUTES.sub('', call.group(1)).strip()
            if returned != returns[name]:
                found_bad.append((name, f'returns {returned}, '
                                        f'defined {returns[name]}'))
            if len(args) != len(params[name]):
                found_bad.append((name, f'{len(args)} arguments, defined '
                                        f'{len(params[name])}'))
                continue
            for index, (arg, param) in enumerate(zip(args, params[name])):
                if arg != param:
                    found_bad.append((name, f'argument {index} is {arg}, '
                                            f'defined {param}'))
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


def emit(root, mojo, found):
    """Return each kernel's AIR, from one generated program."""
    lines = ['from max.gpu.host.compile import _compile_code, '
             'get_gpu_target']
    # Two modules can name a kernel alike, so each is imported by number.
    for index, (module, name) in enumerate(found):
        package = module[:-len('.mojo')].replace('/', '.')
        lines.append(f'from {package} import {name} as kernel_{index}')
    lines += ['', '', 'def main() raises:']
    for index, (module, name) in enumerate(found):
        lines.append(f'    print("{SEPARATOR}{module}:{name}")')
        lines.append(f'    print(_compile_code[kernel_{index}, '
                     f'emission_kind="asm", '
                     f'target = get_gpu_target["{TARGET}"]()]().asm)')
    with tempfile.TemporaryDirectory(prefix='threemojo-air-') as folder:
        program = Path(folder) / 'emit_air.mojo'
        program.write_text('\n'.join(lines) + '\n')
        result = subprocess.run(
            [mojo, 'run', '-I', str(root), str(program)], cwd=root,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=1800)
    if result.returncode != 0:
        raise RuntimeError('AIR emission failed:\n' + result.stderr[-4000:])
    chunks = result.stdout.split(SEPARATOR)[1:]
    return {chunk.split('\n', 1)[0]: chunk.split('\n', 1)[1]
            for chunk in chunks}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    args = parser.parse_args(argv)
    mojo = str(Path(args.mojo).resolve())
    found = kernels(ROOT)
    failed = 0
    for name, air in emit(ROOT, mojo, found).items():
        bad = mismatches(air)
        for callee, detail in bad:
            print(f'{name}: call to {callee}: {detail}', file=sys.stderr)
        failed += len(bad)
    if failed:
        print(f'{failed} mismatched calls; see modular/modular#7238. Give '
              'every device pointer an explicit address space '
              '(`DevicePointer` in render/gpu.mojo).', file=sys.stderr)
        return 1
    print(f'PASS {len(found)} Metal kernels: every call matches its callee')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
