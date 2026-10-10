"""Prepare the source-only paired plan; never compile or run Mojo.

Default: read only named files and an existing source-seal JSON, then write the
prospective plan. Full source materialization requires --materialize-after-release
and must be invoked only after root explicitly releases the native/heavy lane.
"""
from pathlib import Path
import argparse, hashlib, json, re, shutil

HERE = Path(__file__).resolve().parent
WORKSPACE = HERE.parent
AFTER = WORKSPACE / 'pr721-rebuild-20261010/candidate-v4'
AFTER_SEAL = AFTER.parent / 'CANDIDATE-V4-SOURCE-SEAL.json'
EXPECTED_SEAL = '0a61eb6de25b426d6b20ee2c73949842fbd92b0fc8432033c38a733047467d6c'
PREDECESSOR = WORKSPACE / 'recovery-endpoint-source/endpoint-current/extensions/carla/lane_refinement.mojo'
LANE = 'extensions/carla/lane_refinement.mojo'
BEFORE_HASH = '370dee032a5e126e727c46d0ceb7103359f1ad7fba8151e341b594df0c7d0e30'
AFTER_HASH = '13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737'
BEFORE = HERE / 'baseline-v4-center-only'
INPUTS = HERE / 'probe-inputs'
SHA = lambda data: hashlib.sha256(data).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def regular_bytes(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Expected regular source file: ' + str(path))
    return path.read_bytes()


def materialize(expected):
    # This deliberately performs no checker import or native execution.
    # Copy only the exact sealed file inventory, never a hard-linked source.
    if BEFORE.exists():
        raise ValueError('Refuse to overwrite an existing baseline: ' + str(BEFORE))
    predecessor = regular_bytes(PREDECESSOR)
    if SHA(predecessor) != BEFORE_HASH:
        raise ValueError('Reviewed predecessor changed')
    BEFORE.mkdir()
    for name, digest in expected.items():
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Invalid source-seal path: ' + name)
        source = AFTER / relative
        data = regular_bytes(source)
        if SHA(data) != digest:
            raise ValueError('After input changed while copying: ' + name)
        target = BEFORE / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(predecessor if name == LANE else data)
    dump(HERE / 'BASELINE-MATERIALIZED.json', {
        'status': 'Exact sealed inventory copied; only reviewed lane replaced.',
        'source': str(BEFORE), 'after_source': str(AFTER),
        'before_lane_sha256': BEFORE_HASH, 'after_lane_sha256': AFTER_HASH,
        'native_qualification': 'Not performed by this script. The fresh supervisor must verify both complete physical roots before execution.',
    })


def main():
    global AFTER, AFTER_SEAL, EXPECTED_SEAL
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--materialize-after-release', action='store_true')
    parser.add_argument('--phase', default='recovered-center-observer-v1')
    parser.add_argument('--after-root', type=Path)
    parser.add_argument('--after-seal', type=Path)
    parser.add_argument('--after-seal-sha256')
    args = parser.parse_args()
    supplied = (args.after_root, args.after_seal, args.after_seal_sha256)
    if any(value is not None for value in supplied):
        if not all(value is not None for value in supplied):
            raise ValueError('Rebinding requires explicit after root, seal, and reviewed seal SHA256 together')
        if not re.fullmatch(r'[0-9a-f]{64}', args.after_seal_sha256):
            raise ValueError('Invalid reviewed seal SHA256')
        AFTER, AFTER_SEAL, EXPECTED_SEAL = args.after_root.resolve(), args.after_seal.resolve(), args.after_seal_sha256
    if not re.fullmatch(r'[a-z0-9-]+', args.phase):
        raise ValueError('Use a fresh simple phase name')
    raw_seal = regular_bytes(AFTER_SEAL)
    if SHA(raw_seal) != EXPECTED_SEAL:
        raise ValueError('Candidate-v4 seal identity differs; do not repin automatically')
    expected = json.loads(raw_seal)
    if expected[LANE] != AFTER_HASH or SHA(regular_bytes(AFTER / LANE)) != AFTER_HASH:
        raise ValueError('After lane differs')
    if SHA(regular_bytes(PREDECESSOR)) != BEFORE_HASH:
        raise ValueError('Reviewed predecessor differs')
    cases = json.loads(regular_bytes(HERE / 'cases.json'))
    if len(cases) != 49 or len(set(cases)) != 49 or any(not re.fullmatch(r'[a-z0-9-]+', x) for x in cases):
        raise ValueError('Expected exactly 49 declared simple case names')
    INPUTS.mkdir(exist_ok=True)
    names = ['lane_phase_differential.mojo', 'cases.json', 'compare_observations.py']
    for name in names:
        shutil.copyfile(HERE / name, INPUTS / name)
    contract = {
        'before_root': str(BEFORE), 'after_root': str(AFTER),
        'driver': str(INPUTS / 'lane_phase_differential.mojo'),
        'runner': str(AFTER / 'tools/run_suite.py'),
        'mojo': str(WORKSPACE / 'restored-toolchain/official-venv/bin/mojo'),
        'python': str(WORKSPACE / 'restored-toolchain/official-venv/bin/python'),
        'before_lane_sha256': BEFORE_HASH, 'after_lane_sha256': AFTER_HASH,
        'after_input_seal_sha256': EXPECTED_SEAL,
        'receipt_source_seal_sha256': SHA((json.dumps(expected, indent=2, sort_keys=True) + '\n').encode()),
    }
    dump(INPUTS / 'PAIR-CONTRACT.json', contract)
    names.append('PAIR-CONTRACT.json')
    inputs = {name: SHA(regular_bytes(INPUTS / name)) for name in names}
    if {x.name for x in INPUTS.iterdir()} != set(names):
        raise ValueError('Unexpected probe-local import/lookup surface')
    dump(HERE / 'PROBE-INPUTS-SEAL.json', inputs)
    before_expected = dict(expected)
    before_expected[LANE] = BEFORE_HASH
    dump(HERE / 'BEFORE-EXPECTED-SOURCE-SEAL.json', before_expected)
    stages = []
    driver = str(INPUTS / 'lane_phase_differential.mojo')
    runner = str(AFTER / 'tools/run_suite.py')
    for mode in ['O3', 'O0']:
        for side, source in [('before', BEFORE), ('after', AFTER)]:
            stages.append({'label': f'{side}-{mode}-build', 'seconds': 180,
                           'cwd': str(INPUTS), 'command': [
                '{mojo}', 'build', '-I', str(source), '--num-threads', '1',
                '--target-triple=x86_64-unknown-linux-gnu', '--target-cpu=x86-64-v3',
                '--Werror', '-' + mode, driver, '-o', '{evidence}/' + side + '-' + mode + '-bin']})
        for index, case in enumerate(cases):
            for side in ['before', 'after']:
                stages.append({'label': f'{side}-{mode}-case-{index:02d}',
                               'seconds': 15, 'cwd': str(INPUTS), 'command': [
                    '{python}', runner, '--seconds', '5', '--suite', driver, '--',
                    '/usr/bin/env', 'THREEMOJO_LANE_PHASE_CASE=' + case,
                    '{evidence}/' + side + '-' + mode + '-bin']})
        stages.append({'label': f'compare-{mode}', 'seconds': 30, 'cwd': str(INPUTS),
                       'command': ['{python}', str(INPUTS / 'compare_observations.py'),
                                   '--evidence', '{evidence}', '--cases', str(INPUTS / 'cases.json'),
                                   '--mode', mode, '--contract', str(INPUTS / 'PAIR-CONTRACT.json'), '--output', '{evidence}/PAIRS-' + mode + '.json']})
    plan = {'phase': args.phase, 'source': str(AFTER), 'seal': str(AFTER_SEAL),
            'window_seconds': 1200,
            'scope': 'Fresh center-only paired observer: 49 cases per O3/O0 mode, exact exported words/order/errors/ledgers. Newly reconstructed observer, not recovered old receipts, no exhaustive internal trace or full-search count-refusal reachability claim.',
            'additional_sources': [
                {'source': str(BEFORE), 'seal': str(HERE / 'BEFORE-EXPECTED-SOURCE-SEAL.json')},
                {'source': str(INPUTS), 'seal': str(HERE / 'PROBE-INPUTS-SEAL.json')}],
            'stages': stages}
    dump(HERE / 'FRESH-RUN-PLAN.json', plan)
    dump(HERE / 'PAIR-INPUTS.json', {
        'status': 'Source-only prospective plan. No native stage has run.',
        'after_root': str(AFTER), 'after_seal_sha256': EXPECTED_SEAL,
        'before_root': str(BEFORE), 'before_status': 'Materialization pending explicit lane release unless BASELINE-MATERIALIZED.json exists.',
        'only_planned_source_difference': LANE, 'before_sha256': BEFORE_HASH,
        'after_sha256': AFTER_HASH, 'probe_files': inputs,
        'stages': len(stages), 'pairs': 98, 'case_executions': 196,
        'supervisor': str(AFTER.parent / 'run_checkpoint_matrix.py'),
        'old_receipts': 'Lost; cannot be cited as current equivalence evidence.',
    })
    if args.materialize_after_release:
        materialize(expected)
    print('Prepared 202 bounded stages; native execution remains a separate, explicitly authorized action.')


if __name__ == '__main__':
    main()
