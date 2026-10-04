# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reproduce a pinned fixture baseline in temporary storage, never in assets/."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile

from fixture_manifest import ROOT, MANIFEST, digest, runtime_metadata_errors

PACKAGES = Path('tools/fixture-runtime')
SUPPORTED = {'vtk', 'js_number'}


def runtime_errors(observed, baseline):
    """Return differences from the exact supported runtime, including V8."""
    return [f'{key}: expected {baseline[key]}, got {observed.get(key)}'
            for key in ('node', 'v8', 'platform', 'arch')
            if observed.get(key) != baseline[key]]


def table_words(source):
    """Read only the accepted sRGB table, with one word for each byte."""
    match = re.search(r'comptime _SRGB_TO_LINEAR: List\[UInt64\] = \[(.*?)\]',
                      source, re.S)
    if not match:
        raise ValueError('accepted sRGB table was not found')
    return output_words(match.group(1))


def output_words(text):
    """Require 256 hexadecimal UInt64 words, without other generated text."""
    tokens = text.replace(',', ' ').split()
    if len(tokens) != 256 or any(not re.fullmatch(r'0x[0-9A-Fa-f]{16}', t)
                                 for t in tokens):
        raise ValueError('expected exactly 256 hexadecimal Float64 words')
    return [int(t, 16) for t in tokens]


def word_digest(words):
    """Hash Float64 words as 2048 bytes in big-endian order."""
    return hashlib.sha256(b''.join(w.to_bytes(8, 'big') for w in words)).hexdigest()


def word_differences(accepted, generated):
    """Describe each changed positive sRGB Float64 word and Float32 effect."""
    if len(accepted) != len(generated):
        raise ValueError('sRGB word counts differ')
    differences = []
    for byte, (old, new) in enumerate(zip(accepted, generated)):
        if old == new:
            continue
        old_value = struct.unpack('>d', old.to_bytes(8, 'big'))[0]
        new_value = struct.unpack('>d', new.to_bytes(8, 'big'))[0]
        differences.append({
            'byte': byte, 'accepted': f'0x{old:016X}',
            'generated': f'0x{new:016X}', 'ulp_delta': new - old,
            'float32_unchanged': struct.pack('>f', old_value) == struct.pack('>f', new_value),
        })
    return differences


def reproduce(root, family, node, dependencies, diagnose_default_pow=False):
    """Check pins before running the generator; return a comparison report."""
    if family['family'] not in SUPPORTED:
        raise ValueError('this family has no supported runtime verifier')
    baseline = family['verified_runtime']
    if os.environ.get('NODE_OPTIONS'):
        raise ValueError('unset NODE_OPTIONS before fixture verification')
    flags = baseline['node_flags']
    if family['family'] == 'js_number' and flags != ['--no-use-std-math-pow']:
        raise ValueError('the accepted sRGB baseline requires --no-use-std-math-pow')
    if family['family'] == 'vtk' and flags:
        raise ValueError('the verified VTK baseline has no extra Node flags')
    errors = runtime_metadata_errors(root, family)
    if errors:
        raise ValueError('; '.join(errors))
    if diagnose_default_pow:
        if family['family'] != 'js_number':
            raise ValueError('--diagnose-default-pow is only for js_number')
        flags = []
    observed = json.loads(subprocess.check_output([
        node, *flags, '-p',
        'JSON.stringify({node:process.versions.node,v8:process.versions.v8,'
        'platform:process.platform,arch:process.arch})',
    ], text=True, timeout=5))
    errors = runtime_errors(observed, baseline)
    packages = {}
    for name, expected in baseline['dependencies'].items():
        package = dependencies / name / 'package.json'
        actual = json.loads(package.read_text())['version']
        packages[name] = actual
        if actual != expected:
            errors.append(f'{name}: expected {expected}, got {actual}')
    if errors:
        raise ValueError('; '.join(errors))
    generator = root / family['generator']
    if digest(generator) != family['generator_sha256']:
        raise ValueError('generator differs from the accepted manifest')
    report = {
        'family': family['family'], 'runtime': {**observed, 'node_flags': flags},
        'dependencies': packages, 'generator_sha256': digest(generator),
        'historical_environment_recovered': False,
        'mode': 'diagnostic_only' if diagnose_default_pow else 'verify_accepted',
    }
    # Each generator runs in a private working directory. The accepted
    # files are never output targets. No package install runs in this tool.
    with tempfile.TemporaryDirectory(prefix='threemojo-fixture-') as directory:
        work = Path(directory)
        (work / 'node_modules').symlink_to(dependencies.resolve(), target_is_directory=True)
        shutil.copyfile(generator, work / generator.name)
        generated = subprocess.check_output([node, *flags, generator.name], cwd=work,
                                            text=True, timeout=5)
        if family['family'] == 'vtk':
            results = []
            for name, expected in family['artifacts'].items():
                actual = digest(work / Path(name).name)
                results.append({'path': name, 'sha256': actual, 'matches': actual == expected})
            report['artifacts'] = results
            report['matches'] = all(item['matches'] for item in results)
        else:
            table = root / 'loaders/js_number.mojo'
            if digest(table) != family['artifacts']['loaders/js_number.mojo']:
                raise ValueError('accepted sRGB source differs from the manifest')
            accepted = table_words(table.read_text())
            words = output_words(generated)
            report.update({
                'word_count': len(words), 'accepted_words_sha256': word_digest(accepted),
                'generated_words_sha256': word_digest(words),
                'differences': word_differences(accepted, words),
                'not_regenerated': ['assets/js_number/v8.json'],
                'matches': accepted == words,
            })
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('family', choices=sorted(SUPPORTED))
    parser.add_argument('--node', default='node', help='exact pinned Node executable')
    parser.add_argument('--dependencies', type=Path, default=ROOT / PACKAGES / 'node_modules')
    parser.add_argument('--diagnose-default-pow', action='store_true',
                        help='report default-flag differences; never claim baseline reproduction')
    args = parser.parse_args()
    manifest = json.loads((ROOT / MANIFEST).read_text())
    family = next(f for f in manifest['families'] if f['family'] == args.family)
    try:
        report = reproduce(ROOT, family, args.node, args.dependencies, args.diagnose_default_pow)
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        parser.exit(2, f'Fixture verification failed: {error}\n')
    print(json.dumps(report, indent=2))
    return 0 if report['matches'] and not args.diagnose_default_pow else 1


if __name__ == '__main__':
    raise SystemExit(main())
