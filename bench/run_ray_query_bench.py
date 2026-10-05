# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Build and compare complete ray workloads in balanced serial paired order.

Supply two source roots. This script uses identical benchmark drivers from the
candidate root for both builds. It never edits either input tree. Output must
be outside both source roots. No GPU timings are measured by this runner.
"""
import argparse
import csv
import hashlib
import json
import math
import os
import pathlib
import platform
import statistics
import subprocess
import time


def digest(path):
    """Return the SHA-256 digest of a complete file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(root):
    """Hash all source files, excluding generated cache and environment roots."""
    return {str(p.relative_to(root)): digest(p) for p in sorted(root.rglob('*.mojo'))
            if not any(x in {'.cache', 'out', '.venv', '.git'} for x in p.relative_to(root).parts)}


def canonical_digest(value):
    """Hash a JSON value independently of dictionary insertion order."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def main():
    """Build both variants, validate every trial, and save complete evidence."""
    if not __debug__:
        raise SystemExit('Run this verifier without Python -O')
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['baseline', 'candidate', 'output']:
        parser.add_argument('--' + name, required=True, type=pathlib.Path)
    parser.add_argument('--mojo', default='mojo')
    parser.add_argument('--cpu', type=int, required=True)
    parser.add_argument('--pairs', type=int, default=8)
    parser.add_argument('--samples', type=int, default=5)
    parser.add_argument('--repeats', type=int, default=4000)
    args = parser.parse_args()
    if args.pairs <= 0 or args.pairs % 2 or args.samples <= 0 or args.repeats <= 0:
        parser.error('pairs must be positive and even; samples and repeats must be positive')
    roots = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    out = args.output.resolve()
    if any(out.is_relative_to(root) for root in roots.values()):
        parser.error('output must be outside both source roots')
    out.mkdir(parents=True, exist_ok=False)
    drivers = {'queries': roots['candidate'] / 'bench/ray_query_bench.mojo',
               'consumers': roots['candidate'] / 'bench/ray_query_consumers.mojo'}
    inventories = {name: inventory(root) for name, root in roots.items()}
    metadata = {
        'schema': 1, 'runner_sha256': digest(pathlib.Path(__file__)), 'toolchain': subprocess.check_output([args.mojo, '--version'], text=True).strip(),
        'platform': {'os': platform.system(), 'architecture': platform.machine()},
        'flags': ['build', '--Werror', '-I', 'SOURCE'], 'cpu_affinity': 'one fixed logical CPU',
        'pairs': args.pairs, 'samples_per_binary_per_pair': args.samples, 'repeats': args.repeats,
        'source_inventory_sha256': {k: canonical_digest(v) for k, v in inventories.items()},
        'driver_sha256': {k: digest(v) for k, v in drivers.items()}, 'builds': {},
        'status': 'running',
        'workloads': {'queries': '256 stored rays repeated without reducing work; every point coordinate consumed',
                      'gaussian': '4096000 splat-candidate visits in 1000 public raycast calls; every returned field consumed',
                      'physics_mesh': '2048 triangles, prepared Octree, 5600 rays; full PhysicsWorld.raycast with every returned field consumed'},
        'history': 'Query/Gaussian drivers reconstructed from issue 550; physics geometry newly specified. Historical binaries are not used.',
    }
    private = {'cpu_affinity': args.cpu, 'kernel': platform.release(),
               'source_roots': {k: str(v) for k, v in roots.items()}, 'output': str(out),
               'compiler': str(pathlib.Path(args.mojo).resolve()), 'build_commands': [], 'run_commands': [],
               'telemetry_enabled': os.environ.get('MODULAR_TELEMETRY_ENABLED')}
    info = pathlib.Path('/proc/cpuinfo')
    if info.exists():
        private['cpu_models'] = sorted({line.split(':', 1)[1].strip() for line in info.read_text().splitlines() if line.startswith('model name')})
    (out / 'private-provenance.json').write_text(json.dumps(private, indent=2) + '\n')
    (out / 'source-inventories.json').write_text(json.dumps(inventories, sort_keys=True) + '\n')
    for name, root in roots.items():
        for kind, driver in drivers.items():
            binary = out / (name + '-' + kind)
            started = time.perf_counter()
            command = [args.mojo, 'build', '--Werror', '-I', str(root), str(driver), '-o', str(binary)]
            private['build_commands'].append(command)
            result = subprocess.run(command, capture_output=True, text=True)
            elapsed = time.perf_counter() - started
            (out / (name + '-' + kind + '-build.log')).write_text(result.stdout + result.stderr)
            result.check_returncode()
            size = subprocess.check_output(['size', str(binary)], text=True).splitlines()[1].split()
            metadata['builds'][name + '-' + kind] = {'wall_seconds': elapsed, 'binary_sha256': digest(binary),
                                                    'file_bytes': binary.stat().st_size,
                                                    'text_bytes': int(size[0]), 'data_bytes': int(size[1]), 'bss_bytes': int(size[2])}
            print('Built', name, kind, round(elapsed, 3), flush=True)
    (out / 'metadata.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
    rows = []
    checksums = {}
    expected = {'queries': {'sphere_point': 256 * args.repeats, 'sphere_bool': 256 * args.repeats,
                            'box_point': 256 * args.repeats, 'box_bool': 256 * args.repeats},
                'consumers': {'gaussian': 4096000, 'physics_mesh': 5600}}
    with (out / 'trials.jsonl').open('w') as raw:
        for pair in range(args.pairs):
            order = ['baseline', 'candidate'] if pair % 2 == 0 else ['candidate', 'baseline']
            for position, name in enumerate(order):
                for sample in range(args.samples):
                    for kind in drivers:
                        command = ['taskset', '-c', str(args.cpu), str(out / (name + '-' + kind))]
                        if kind == 'queries':
                            command.append(str(args.repeats))
                        private['run_commands'].append(command)
                        result = subprocess.run(command, capture_output=True, text=True, check=True)
                        seen = set()
                        for line in result.stdout.splitlines():
                            workload, calls, ns, checksum = line.split(',')
                            assert workload in expected[kind] and workload not in seen
                            assert int(calls) == expected[kind][workload] and int(ns) > 0
                            assert math.isfinite(float(checksum)), 'nonfinite result checksum'
                            seen.add(workload)
                            if workload not in checksums:
                                checksums[workload] = checksum
                            assert checksum == checksums[workload], (name, workload, checksum, checksums[workload])
                            row = {'pair': pair, 'position': position, 'sample': sample, 'variant': name,
                                   'workload': workload, 'calls': int(calls), 'ns': int(ns), 'checksum': checksum}
                            rows.append(row)
                            raw.write(json.dumps(row, sort_keys=True) + '\n')
                        assert seen == set(expected[kind])
                        raw.flush()
            print('Completed pair', pair, flush=True)
    for name, root in roots.items():
        assert inventories[name] == inventory(root), 'source changed during measurement: ' + name
    for name in roots:
        for kind in drivers:
            assert digest(out / (name + '-' + kind)) == metadata['builds'][name + '-' + kind]['binary_sha256']
    with (out / 'trials.csv').open('w') as f:
        writer = csv.DictWriter(f, fieldnames=rows[0])
        writer.writeheader()
        writer.writerows(rows)
    summary = {}
    for work in checksums:
        values = {v: [r['ns'] / 1e6 for r in rows if r['variant'] == v and r['workload'] == work] for v in roots}
        ratios = []
        for pair in range(args.pairs):
            medians = {v: statistics.median(r['ns'] for r in rows if r['pair'] == pair and r['variant'] == v and r['workload'] == work) for v in roots}
            ratios.append(medians['candidate'] / medians['baseline'])
        entry = {v: {'median_ms': statistics.median(x), 'min_ms': min(x), 'max_ms': max(x),
                     'q1_ms': statistics.quantiles(x)[0], 'q3_ms': statistics.quantiles(x)[2], 'samples': len(x)} for v, x in values.items()}
        entry['median_ratio'] = entry['candidate']['median_ms'] / entry['baseline']['median_ms']
        entry['paired_round_ratios'] = ratios
        entry['paired_round_median_ratio'] = statistics.median(ratios)
        entry['checksum'] = checksums[work]
        summary[work] = entry
    (out / 'private-provenance.json').write_text(json.dumps(private, indent=2) + '\n')
    metadata['status'] = 'complete'
    metadata['verified_unchanged_sources_and_binaries'] = True
    metadata['rows'] = len(rows)
    (out / 'metadata.json').write_text(json.dumps(metadata, indent=2, sort_keys=True) + '\n')
    (out / 'summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
