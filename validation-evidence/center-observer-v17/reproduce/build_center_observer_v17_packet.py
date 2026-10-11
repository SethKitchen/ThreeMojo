"""Package the fresh frozen-v17 center observer receipts; never run native code.

Read only the named evidence and reproducibility inputs. Validate bindings before
creating an immutable, text-only packet. Existing evidence is never overwritten.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys

sys.dont_write_bytecode = True
if sys.flags.optimize:
    raise RuntimeError('Packet validation must remain unoptimized')

R = Path(__file__).resolve().parent
P = R.parent / 'final-center-observer-v17'
E = R / 'evidence/center-observer-final-v17'
O = R / 'validation-evidence-center-observer-v17-packet'
RESULT_SHA = 'e060276e8ccfa1db38e63ce59468c50809fe01ff9b748eedc0fbf37f2f72ebad'
SOURCE_SHA = '3e63e8a02b46f1d2d7102b829427448a891fcb0189c445990ac33bafac9f3d21'
PLAN_SHA = 'b2c8979823cda4d4159fbececdd7775f67949ba1ad3f997cea1f4a00a93ad16c'
CHECKPOINT_SHA = '090cdf4291de569e40a035514bdf17a45ec6e60427c1071c664f4b80118cc11f'
LANE = 'extensions/carla/lane_refinement.mojo'
SHA = lambda data: hashlib.sha256(data).hexdigest()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def raw(path):
    need(path.is_file() and not path.is_symlink(), 'Expected regular file: ' + str(path))
    return path.read_bytes()


def digest(path):
    return SHA(raw(path))


def read(path):
    return json.loads(raw(path))


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


need(not O.exists(), 'Never overwrite an evidence packet')
need(digest(E / 'RESULT.json') == RESULT_SHA, 'Final result identity changed')
need(digest(E / 'SOURCE-SEAL.json') == SOURCE_SHA, 'Executing source seal changed')
need(digest(R / 'CANDIDATE-V17-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen v17 seal changed')
need(digest(P / 'FRESH-RUN-PLAN.json') == PLAN_SHA, 'Executed plan changed')
need(digest(P / 'CHECKPOINT-SOURCE-MANIFEST.json') == CHECKPOINT_SHA, 'Input checkpoint changed')
result = read(E / 'RESULT.json')
plan = read(P / 'FRESH-RUN-PLAN.json')
contract = read(P / 'probe-inputs/PAIR-CONTRACT.json')
checkpoint = read(P / 'CHECKPOINT-SOURCE-MANIFEST.json')
inputs = read(P / 'PROBE-INPUTS-SEAL.json')
source = read(E / 'SOURCE-SEAL.json')
before_source = read(P / 'BEFORE-EXPECTED-SOURCE-SEAL.json')
cases = read(P / 'probe-inputs/cases.json')
window = read(E / 'WINDOW-START.json')
need(result['sequence_completed'] and result['failure'] is None,
     'The sequence did not complete successfully')
need(result['source_seal_unchanged'] and result['sdk_identity_unchanged']
     and result['remaining_owned_descendants'] == [], 'Source, SDK, or cleanup failed')
need(raw(E / 'SDK-BEFORE.json') == raw(E / 'SDK-AFTER.json'), 'SDK receipts differ')
need(result['scope'] == plan['scope'], 'Result scope differs from executed plan')
need(len(cases) == len(set(cases)) == 49, 'Expected 49 distinct cases')
need(len(result['stages']) == len(plan['stages']) == 202, 'Expected 202 stages')
need(plan['window_seconds'] == window['whole_window_seconds'] == 1200,
     'Whole-window bound changed')
need(result['elapsed_seconds'] < 1200 and window['runtime_gate_seconds'] == 5
     and window['python_optimize'] == 0, 'Runtime bounds or supervisor mode changed')
need(digest(R / 'run_checkpoint_matrix.py') == window['supervisor_sha256'],
     'Executed supervisor changed')
need(set(source) == set(before_source)
     and [name for name in source if source[name] != before_source[name]] == [LANE],
     'The before/after source inventories differ beyond the center lane')
need(contract['receipt_source_seal_sha256'] == contract['after_input_seal_sha256'] == SOURCE_SHA,
     'Contract source binding changed')
for name, expected in checkpoint['files'].items():
    need(digest(P / name) == expected, 'Checkpoint input changed: ' + name)
for name, expected in inputs.items():
    need(digest(P / 'probe-inputs' / name) == expected, 'Observer input changed: ' + name)
for side, seal in [('before', before_source), ('after', source)]:
    need(digest(Path(contract[side + '_root']) / LANE)
         == seal[LANE] == contract[side + '_lane_sha256'], 'Bound lane source changed: ' + side)
for name in ['tools/run_suite.py', 'tools/test_environment.py', 'tools/coverage_toolchain_identity.py']:
    need(digest(R / 'candidate-v17' / name) == source[name], 'Executed support source changed: ' + name)

expected_labels = []
for mode in ['O3', 'O0']:
    expected_labels += [f'{side}-{mode}-build' for side in ['before', 'after']]
    expected_labels += [f'{side}-{mode}-case-{index:02d}'
                        for index in range(49) for side in ['before', 'after']]
    expected_labels += ['compare-' + mode]
need([s['label'] for s in result['stages']] == expected_labels, 'Stage order or inventory changed')
commands = []
for stage, configured in zip(result['stages'], plan['stages']):
    label = stage['label']
    expected_command = [part.replace('{mojo}', contract['mojo'])
                       .replace('{python}', contract['python'])
                       .replace('{evidence}', str(E)).replace('{root}', str(R))
                       for part in configured['command']]
    cap = 180 if label.endswith('-build') else 30 if label.startswith('compare-') else 15
    start = read(E / (label + '-START.json'))
    need(stage == read(E / (label + '-RESULT.json')), 'Stage result differs from final receipt: ' + label)
    need(all(stage.get(k) == v for k, v in start.items()), 'Stage START differs from result: ' + label)
    need(stage['label'] == configured['label'] and stage['argv'] == expected_command
         and stage['cwd'] == configured['cwd'], 'Executed command differs from plan: ' + label)
    need(stage['stage_timeout_seconds'] == configured['seconds'] == cap,
         'Stage bound changed: ' + label)
    need(stage['source_seal_sha256'] == SOURCE_SHA and stage['returncode'] == 0
         and stage['timed_out'] is False and stage['leader_reaped'] is True
         and stage['remaining_owned_descendants'] == [], 'Unsuccessful stage: ' + label)
    need(digest(E / (label + '.log')) == stage['log_sha256'], 'Raw log changed: ' + label)
    if '-case-' in label:
        need(stage['argv'][2:4] == ['--seconds', '5'], 'Inner test bound changed: ' + label)
    commands.append({'label': label, 'argv': stage['argv'], 'cwd': stage['cwd'],
                     'stage_timeout_seconds': cap,
                     'start_sha256': digest(E / (label + '-START.json')),
                     'result_sha256': digest(E / (label + '-RESULT.json')),
                     'log_sha256': stage['log_sha256']})

# Load only the sealed pure-Python parser, not its main, compiler, or test runner.
spec = importlib.util.spec_from_file_location('center_observer_packet_parser', P / 'probe-inputs/compare_observations.py')
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)
pairs = {}
excluded = []
for mode in ['O3', 'O0']:
    paired = read(E / ('PAIRS-' + mode + '.json'))
    need(paired['complete'] and paired['all_equal'] and paired['mode'] == mode
         and paired['paired_cases'] == len(paired['pairs']) == 49, 'Incomplete pair result: ' + mode)
    for index, (case, pair) in enumerate(zip(cases, paired['pairs'])):
        need(pair['case'] == case and pair['index'] == index and pair['mode'] == mode
             and pair['equal'] is True, 'Pair inventory changed: ' + case)
        observations = {}
        for side in ['before', 'after']:
            label = f'{side}-{mode}-case-{index:02d}'
            observations[side] = parser.observations(raw(E / (label + '.log')), case)
            need(pair[side] == {'log_sha256': digest(E / (label + '.log')),
                               'observation_sha256': SHA(observations[side]),
                               'status_sha256': digest(E / (label + '-RESULT.json'))},
                 'Pair receipt binding changed: ' + label)
        need(observations['before'] == observations['after'], 'Exported observation differs: ' + case)
    for side in ['before', 'after']:
        name = f'{side}-{mode}-bin'
        build = paired['builds'][side]
        receipt = read(E / (f'{side}-{mode}-build-RESULT.json'))
        need(digest(E / name) == build['binary_sha256_after_runs'], 'Executable identity changed: ' + name)
        need(build['command'] == receipt['argv']
             and build['status_sha256'] == digest(E / (f'{side}-{mode}-build-RESULT.json'))
             and build['log_sha256'] == receipt['log_sha256'], 'Build binding changed: ' + name)
        excluded.append({'name': name, 'bytes': (E / name).stat().st_size,
                         'sha256': build['binary_sha256_after_runs'],
                         'hash_receipt': 'actual/PAIRS-' + mode + '.json',
                         'reason': 'Native executable excluded; original post-run hash retained.'})
    pairs[mode] = paired

expected_files = {s['label'] + suffix for s in result['stages']
                  for suffix in ['.log', '-START.json', '-RESULT.json']}
expected_files |= {'LATEST.json', 'PAIRS-O0.json', 'PAIRS-O3.json', 'PROCESSES.jsonl',
                   'RESULT.json', 'SDK-AFTER.json', 'SDK-BEFORE.json', 'SOURCE-SEAL.json',
                   'WINDOW-START.json'}
need({p.name for p in E.iterdir()} == expected_files | {x['name'] for x in excluded},
     'Unexpected or missing evidence files')
supervisor_lines = raw(R / 'center-observer-final-v17.supervisor.log').splitlines()
need(len(supervisor_lines) == 203 and json.loads(supervisor_lines[-1]) == result,
     'Supervisor output is incomplete')
need([json.loads(line) for line in supervisor_lines[:-1]] == result['stages'],
     'Supervisor stage output differs from receipts')

payloads = []


def queue(path, relative, kind):
    data = raw(path)
    data.decode('utf-8', errors='strict')
    need(b'\0' not in data, 'Unexpected binary content: ' + str(path))
    payloads.append((relative, data, kind))


for name in sorted(expected_files):
    kind = 'original-merged-stdout-stderr-log' if name.endswith('.log') else 'original-supervisor-receipt-or-pair-result'
    queue(E / name, 'actual/' + name, kind)
for name in ['run_checkpoint_matrix.py', 'center-observer-final-v17.supervisor.log',
             'CANDIDATE-V17-SOURCE-SEAL.json']:
    queue(R / name, 'reproduce/' + name, 'exact-supervisor-output-source-seal-or-harness')
for name in ['FRESH-RUN-PLAN.json', 'CHECKPOINT-SOURCE-MANIFEST.json',
             'BEFORE-EXPECTED-SOURCE-SEAL.json', 'PROBE-INPUTS-SEAL.json',
             'PAIR-INPUTS.json', 'BASELINE-MATERIALIZED.json', 'prepare_fresh_run.py']:
    queue(P / name, 'reproduce/' + name, 'exact-executed-config-or-preparation-input')
for name in sorted(inputs):
    queue(P / 'probe-inputs' / name, 'reproduce/probe-inputs/' + name, 'exact-executed-observer-input')
for side in ['before', 'after']:
    queue(Path(contract[side + '_root']) / LANE, 'reproduce/source/' + side + '/' + LANE,
          'exact-before-or-after-center-source')
for name in ['tools/run_suite.py', 'tools/test_environment.py', 'tools/coverage_toolchain_identity.py']:
    queue(R / 'candidate-v17' / name, 'reproduce/source/support/' + name,
          'exact-consumed-runner-or-sdk-identity-source')
queue(Path(__file__), 'reproduce/build_center_observer_v17_packet.py', 'packet-builder-no-native-execution')

summary = {
    'schema': 1, 'status': 'PASSED_FRESH_CENTER_OBSERVER_FROZEN_V17',
    'scope': result['scope'], 'result_sha256': RESULT_SHA,
    'source_seal_sha256': SOURCE_SHA, 'plan_sha256': PLAN_SHA,
    'checkpoint_sha256': CHECKPOINT_SHA,
    'source_pair': {'only_inventory_difference': LANE,
                    'before_lane_sha256': before_source[LANE], 'after_lane_sha256': source[LANE],
                    'before_inventory_sha256': digest(P / 'BEFORE-EXPECTED-SOURCE-SEAL.json'),
                    'after_inventory_sha256': SOURCE_SHA,
                    'inventory_file_count_per_side': len(source)},
    'started': window['started'], 'finished': result['finished'],
    'window_elapsed_seconds': result['elapsed_seconds'],
    'completed_passing_stages': 202, 'build_stages': 4,
    'native_case_executions': 196, 'comparison_stages': 2,
    'exact_equal_before_after_pairs': 98,
    'pairs_by_mode': {mode: {'pairs': 49, 'all_equal': True,
                            'receipt_sha256': digest(E / ('PAIRS-' + mode + '.json'))}
                      for mode in ['O3', 'O0']},
    'caps_seconds': {'build': 180, 'native_test': 5, 'outer_run': 15,
                     'comparison': 30, 'window': 1200},
    'source_sdk_unchanged': True, 'remaining_owned_descendants': [],
    'sdk_receipt_sha256': digest(E / 'SDK-BEFORE.json'),
    'supervisor_sha256': window['supervisor_sha256'],
    'stream_capture': 'Each original .log is the supervisor\'s merged stdout and stderr stream. Separate streams were not recorded and are not fabricated.',
    'receipt_provenance': 'Newly reconstructed observer freshly executed on frozen v17. Earlier lost receipts remain lost and are not relabeled or replaced by historical execution claims.',
    'observation_boundary': 'Exact byte equality after removal only of TestSuite framing, with complete passing frames and ordered observation grammar checked. Exported words, order, error text and ledgers are covered; exhaustive internal traversal and old full-search count-refusal reachability are not claimed.',
    'reproduction_boundary': 'Exact inputs retain original absolute paths. This is a reviewable evidence packet, not a self-contained SDK or full repository. Full inventory seals bind omitted unchanged source; only the before/after center lane and executed Python support sources are included.',
    'preparation_boundary': 'Preparation manifests are preserved unchanged as historical prospective inputs. Their pending/no-execution wording describes preparation time; the original RESULT and PAIRS receipts record this completed fresh run.',
    'other_qualification_boundary': 'This packet does not qualify candidate-v18, the final Python matrix, other paired native controls, maintained coverage, hosted CI, or issue completion.',
    'excluded_executables': excluded,
    'evidence_policy': 'All original receipts, combined raw logs, and named reproduction inputs are copied byte-for-byte. Derived summaries are separate. No executable payloads, internal reviews, private notes, secrets, broad unrelated source, cap relaxation, or external upload.',
}
command_seal = {'schema': 1, 'kind': 'derived-command-and-receipt-binding',
                'plan_sha256': PLAN_SHA, 'result_sha256': RESULT_SHA,
                'source_seal_sha256': SOURCE_SHA,
                'supervisor_sha256': window['supervisor_sha256'], 'stages': commands}
payloads += [('VALIDATION-SUMMARY.json', json_bytes(summary), 'derived-scope-limited-acceptance-summary'),
             ('COMMAND-RECEIPT-SEAL.json', json_bytes(command_seal), 'derived-command-and-receipt-seal'),
             ('EXCLUDED-EXECUTABLES.json', json_bytes({'schema': 1, 'files': excluded}),
              'derived-exclusion-inventory-with-original-binary-hashes')]
readme = '''# Frozen-v17 center observer evidence

Fresh reconstructed observer execution completed 202/202 stages: four builds,
196 native case executions and two comparisons. All 49 before/after pairs match
in each of O3 and O0 (98 total). Original caps: 180-second builds, 5-second tests,
15-second outer case stages, 30-second comparisons and a 1200-second window.

The actual/ directory contains every original stage START, RESULT and merged
stdout/stderr log, final RESULT, SDK before/after receipts, source seal, process
receipts and both PAIRS files. These bytes are unchanged. Separate stdout and
stderr streams were never recorded. The four executable payloads are omitted;
their original post-run hashes remain in PAIRS and EXCLUDED-EXECUTABLES.json.

The reproduce/ directory contains exact source seals, original commands/config,
observer driver, cases, comparator, contract, preparation inputs, before/after
center-lane source and the executed Python support files. Original paths are
retained. Full SDK and unchanged repository source are not distributed here.
Preparation files still contain their original prospective status wording.

VALIDATION-SUMMARY.json and COMMAND-RECEIPT-SEAL.json are explicitly derived
documents, separate from actual execution receipts. The manifest lists payload
paths, byte counts and SHA-256 values; it excludes its own recursive hash.

This is fresh frozen-v17 exported-observation evidence. It does not recover or
relabel lost receipts, establish an exhaustive internal traversal trace, prove
old full-search count-refusal reachability, or qualify candidate-v18 or any
other outstanding validation stage. No native code is run by the packet builder.
'''
payloads.append(('README.md', readme.encode(), 'derived-reader-guide'))
need(len({relative for relative, _, _ in payloads}) == len(payloads), 'Duplicate packet path')
O.mkdir()
rows = []
for relative, data, kind in payloads:
    target = O / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('xb') as output:
        output.write(data)
    need(raw(target) == data, 'Copy verification failed: ' + relative)
    rows.append({'path': relative, 'local_source': str(target), 'sha256': SHA(data),
                 'bytes': len(data), 'kind': kind})
manifest = O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with manifest.open('xb') as output:
    output.write(json_bytes({'schema': 1, 'scope': summary['scope'], 'files': rows}))
print(json.dumps({'manifest': str(manifest), 'sha256': digest(manifest),
                  'files': len(rows), 'bytes': sum(row['bytes'] for row in rows),
                  'manifest_bytes': manifest.stat().st_size,
                  'total_files_including_manifest': len(rows) + 1,
                  'total_bytes_including_manifest': sum(row['bytes'] for row in rows) + manifest.stat().st_size,
                  'result_sha256': RESULT_SHA}))
