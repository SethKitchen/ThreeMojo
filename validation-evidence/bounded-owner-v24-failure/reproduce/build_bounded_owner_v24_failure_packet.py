"""Preserve actual failed v24 controls without executing source or rerunning tests.

Only allowlisted original receipts, source identities and source bytes are
packaged. Existing candidate/source/receipt/packet bytes are never changed.
"""
from pathlib import Path
import ast
import base64
import gzip
import hashlib
import json
import re

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-bounded-owner-v24-failure-packet'
PHASE = 'bounded-owner-controls-v24'
SOURCE_SHA = 'fbc9cb60f5ee9320a9ec81b3bfe0c57bdb3ed331b3a93f7ec75268c651f95525'
MANIFEST_SHA = 'b75101f0de0ef206379ee344804f0cf1d3ad5ace5788800a85ab3af319f15bff'
RESULT_SHA = '647570afdfd08a1b6b5dc8f4e338dd99f046321899ab753f58b3efb78c73d810'
TEST = 'tools/carla_lane_oracle/test_invariant_operation_inputs.py'
TEST_SHA = '34de24645442874738c92d26b25e55b978b894cc344e8943a5c290f6cf73bef7'
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def raw(path):
    need(path.is_file() and not path.is_symlink(), 'Expected regular input: ' + str(path))
    return path.read_bytes()


def digest(path):
    return SHA(raw(path))


def read(path):
    return json.loads(raw(path))


need(not O.exists(), 'Never overwrite an evidence packet')
E = R / 'evidence' / PHASE
manifest_path = R / 'bounded-owner-controls-implementation-v24/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(R / 'CANDIDATE-V24-SOURCE-SEAL.json') == SOURCE_SHA, 'Source seal changed')
need(digest(manifest_path) == MANIFEST_SHA, 'Source manifest changed')
need(digest(E / 'RESULT.json') == RESULT_SHA, 'Actual failure result changed')
source_seal = read(R / 'CANDIDATE-V24-SOURCE-SEAL.json')
source_manifest = read(manifest_path)
need(source_manifest['source_seal_sha256'] == SOURCE_SHA
     and source_manifest['status'] == 'source_only_unqualified'
     and len(source_manifest['files']) == 31, 'Frozen source manifest differs')
result = read(E / 'RESULT.json')
config = read(R / (PHASE + '.json'))
window = read(E / 'WINDOW-START.json')
need(len(result['stages']) == 1 and len(config['stages']) == 2,
     'Actual/configured stage inventory differs')
stage = result['stages'][0]
label = stage['label']
need(label == 'normal-bounded-owner-controls'
     and stage['returncode'] == 1 and not stage['timed_out']
     and stage['seconds'] == 141.83296330300072
     and not result['sequence_completed'] and result['failure'] is not None,
     'Actual non-timeout failure differs')
need(stage == read(E / (label + '-RESULT.json')), 'Stage/final result mismatch')
start = read(E / (label + '-START.json'))
need(all(stage.get(k) == v for k, v in start.items()), 'START/result mismatch')
need(stage['source_seal_sha256'] == config['source_seal_sha256']
     == window['source_seal_sha256'] == digest(E / 'SOURCE-SEAL.json') == SOURCE_SHA,
     'Source-seal receipt mismatch')
need(result['scope'] == config['scope'], 'Scope mismatch')
need(result['source_seal_unchanged'] and result['sdk_identity_unchanged']
     and result['remaining_owned_descendants'] == stage['remaining_owned_descendants'] == []
     and stage['leader_reaped'], 'Source/SDK/cleanup receipt differs')
need(raw(E / 'SDK-BEFORE.json') == raw(E / 'SDK-AFTER.json'), 'SDK changed')
need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
     and window['whole_window_seconds'] == config['window_seconds'] == 10800
     and stage['stage_timeout_seconds'] == config['stages'][0]['seconds'] == 1800,
     'Supervisor/cap binding differs')
for configured in config['stages']:
    need(configured['expected_tests'] == 30 and configured['seconds'] == 1800,
         'Configured test inventory or cap differs')
expected_command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                    .replace('{evidence}', str(E)).replace('{root}', str(R))
                    for part in config['stages'][0]['command']]
need(stage['argv'] == expected_command and stage['cwd'] == config['source']
     and stage['argv'][-1] == '-f' and '-O' not in stage['argv'], 'Actual fail-fast command differs')
need(config['stages'][1]['label'] == 'optimized-bounded-owner-controls'
     and '-O' in config['stages'][1]['command'], 'Unrun optimized command differs')
need(not any(k in stage for k in ('test_count', 'expected_tests', 'skipped_test_count')),
     'Unexpected post-success test inventory annotations')
console = raw(R / (PHASE + '.supervisor.log')).splitlines()
need(len(console) == 2 and json.loads(console[0]) == stage and json.loads(console[1]) == result,
     'Actual supervisor console differs')
failure = read(E / 'FAILURE.json')
need(failure['error'] == result['failure'] and 'RuntimeError: Stage failed: ' + label in failure['traceback'],
     'Original supervisor traceback differs')
processes = [json.loads(line) for line in raw(E / 'PROCESSES.jsonl').splitlines()]
need(processes and read(E / 'LATEST.json') == processes[-1]
     and all(row['label'] == label and all(p['pgid'] == stage['pgid'] for p in row['owned'])
             for row in processes), 'Process history differs')
log_raw = raw(E / (label + '.log'))
need(SHA(log_raw) == stage['log_sha256'], 'Raw test log changed')
log = log_raw.decode('utf-8')
need(re.findall(r'^Ran (\d+) tests? in ', log, re.M) == ['10']
     and log.rstrip().endswith('FAILED (errors=1)')
     and ' ... skipped ' not in log, 'Raw failure count differs')
started = re.findall(r'^test_\w+ \(test_invariant_operation_inputs\.([^\n]+)\) \.\.\. ', log, re.M)
need(len(started) == 10, 'Started method count differs')
passed = len(re.findall(r'^test_.* \.\.\. ok$', log, re.M)) + len(re.findall(r'^ok$', log, re.M))
need(passed == 9 and len(re.findall(r'^ERROR: ', log, re.M)) == 1, 'Passed/error counts differ')
failing = 'BoundedOwnerCurrentControls.test_current_foreign_root_thread_and_cwd_poison_the_owner'
need(started[-1] == failing and "(fault='root') ... ERROR" in log,
     'First root-fault error differs')
need('full_audit_cleanup_contracts._OperationCoherenceError: full-audit cleanup successor: cache input root or working directory changed' in log
     and 'The above exception was the direct cause of the following exception:' in log
     and 'ValueError: unreviewed complete successor: full-audit cleanup successor: cache input root or working directory changed' in log,
     'Original public-wrapper traceback chain missing')
test_raw = raw(R / 'candidate-v24' / TEST)
need(SHA(test_raw) == source_seal[TEST] == TEST_SHA, 'Executed test source differs')
tree = ast.parse(test_raw)
methods = sorted(c.name + '.' + n.name for c in tree.body if isinstance(c, ast.ClassDef)
                 for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_'))
need(len(methods) == 30 and started == methods[:10], 'Sealed method inventory/order differs')
remaining = methods[10:]
expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                  'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json', 'FAILURE.json',
                  label + '-RESULT.json', label + '-START.json', label + '.log'}
need({p.name for p in E.iterdir()} == expected_files, 'Unexpected or missing original phase file')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


for name in sorted(expected_files):
    add(E / name, 'actual/' + name, 'original-failure-phase-receipt-or-merged-log',
        readable=name in {'RESULT.json', 'FAILURE.json', 'SDK-BEFORE.json', 'SDK-AFTER.json',
                          'WINDOW-START.json', label + '.log'})
for name in [PHASE + '.json', PHASE + '.supervisor.log', 'run_checkpoint_matrix.py',
             'CANDIDATE-V24-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-config-console-supervisor-or-source-seal', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-31-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v24' / row['path']
    data = raw(path)
    need(SHA(data) == row['sha256'] == source_seal[row['path']] and len(data) == row['bytes'],
         'Frozen source mismatch: ' + row['path'])
    need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == row['git_blob'],
         'Source Git blob mismatch')
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v24-source',
        readable=row['path'] in {TEST, 'docs/validation/full-audit-721-qualification-policy.md'})
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v24' / support) == source_seal[support], 'SDK support source changed')
add(R / 'candidate-v24' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')
summary = {
    'schema': 1, 'status': 'FAILED_V24_NORMAL_BOUNDED_OWNER_CONTROLS_NOT_A_QUALIFICATION_PASS',
    'scope': 'Actual fail-fast normal run only: ten methods ran, nine passed and one errored. Twenty normal methods and all thirty optimized methods were unrun. No suite or broader qualification pass.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 31, 'executed_test_path': TEST, 'executed_test_sha256': TEST_SHA,
    'result_sha256': RESULT_SHA, 'stage_log_sha256': SHA(log_raw),
    'actual_stage': {'label': label, 'returncode': 1, 'timed_out': False,
                     'elapsed_seconds': stage['seconds'], 'stage_cap_seconds': 1800,
                     'whole_window_cap_seconds': 10800, 'whole_window_elapsed_seconds': result['elapsed_seconds'],
                     'sequence_completed': False, 'fail_fast': True},
    'observed_normal_methods': {'ran': 10, 'passed': 9, 'errors': 1, 'skips_observed': 0,
                                'method_names': started, 'first_error_method': failing,
                                'first_error_subtest': "fault='root'",
                                'unrun_count': 20, 'unrun_method_names': remaining},
    'optimized_methods': {'status': 'UNRUN', 'configured_methods': 30, 'unrun_method_names': methods},
    'count_provenance': 'Observed counts are derived from the original unittest log, not fabricated supervisor test-count fields. The supervisor stopped on exit 1 before its post-success expected-test inventory annotations. Configured expected_tests=30 is not a completed count.',
    'traceback_preservation': 'The raw log preserves the internal _OperationCoherenceError and its chained public ValueError from accepted_successor_contracts. The original supervisor FAILURE.json traceback and aggregate console are also intact. No exception or error is normalized into a pass.',
    'subtest_limit': 'The root-fault subtest errored and fail-fast stopped the run. Other fault branches inside that method are not claimed as executed or passed.',
    'source_sdk_unchanged': True, 'remaining_owned_descendants': [],
    'source_manifest_time_boundary': 'The original source_only_unqualified manifest is unchanged; this later receipt records a failed run.',
    'reproduction_boundary': 'Includes the exact executed test, all 31 frozen source-manifest paths, SDK identity support source, full source seal and actual config/supervisor. The full unchanged repository and SDK executable image are not distributed.',
    'qualification_limit': 'No complete normal/optimized control suite, real lifecycle/per-site matrix, native coverage, hosted CI or overall issue completion is qualified by this failed run.',
    'stream_capture': 'Original stage stdout/stderr share one merged log. The actual aggregate supervisor console exists and is preserved. No missing evidence or separate stream is reconstructed.',
    'evidence_policy': 'Only ordinary original receipts, logs, configs and exact source bytes are included. No review/design/private notes, later corrected test proposal, rerun, candidate edit, native execution or upload.'
}
commands = {'schema': 1, 'kind': 'derived-actual-command-and-receipt-binding',
            'phase': PHASE, 'source_seal_sha256': SOURCE_SHA,
            'config_sha256': digest(R / (PHASE + '.json')), 'result_sha256': RESULT_SHA,
            'stage': stage, 'start_sha256': digest(E / (label + '-START.json')),
            'stage_result_sha256': digest(E / (label + '-RESULT.json')),
            'supervisor_console_sha256': digest(R / (PHASE + '.supervisor.log')),
            'configured_but_unrun_stage_labels': ['optimized-bounded-owner-controls']}
archive_name = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
members = []; archived = []; payloads = []
need(len({row['path'] for row in originals}) == len(originals), 'Duplicate original member')
for row in sorted(originals, key=lambda row: row['path']):
    data = row['data']
    member = {key: row[key] for key in ['path', 'kind', 'original_source']}
    member.update(bytes=len(data), sha256=SHA(data))
    if row['readable']:
        data.decode('utf-8')
        payloads.append((row['path'], data, 'byte-exact-readable-original'))
        member.update(storage='readable', transport_path=row['path'])
    else:
        archived.append({'path': row['path'], 'bytes': len(data), 'sha256': SHA(data),
                         'data_base64': base64.b64encode(data).decode('ascii')})
        member.update(storage='container', transport_path=archive_name)
    members.append(member)
container = (json.dumps({'schema': 1, 'encoding': 'base64', 'members': archived},
                        sort_keys=True, separators=(',', ':')) + '\n').encode()
encoded = base64.b64encode(gzip.compress(container, compresslevel=9, mtime=0)) + b'\n'
need(gzip.decompress(base64.b64decode(encoded)) == container, 'Container roundtrip differs')
inner = {'schema': 1, 'original_member_count': len(members),
         'original_member_bytes': sum(row['bytes'] for row in members),
         'container': {'path': archive_name, 'encoding': 'base64 of deterministic gzip mtime=0 containing JSON',
                       'members': len(archived), 'json_bytes': len(container), 'json_sha256': SHA(container)},
         'members': members}
decoder = R / 'validation-evidence-qualification-policy-v23-packet/decode_verify.py'
need(digest(decoder) == 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4',
     'Reviewed decoder bytes changed')
payloads += [(archive_name, encoded, 'lossless-original-failure-receipts-and-source-bytes'),
             ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-path-byte-hash-and-storage-inventory'),
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-failed-control-run-and-unrun-inventory-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(decoder), 'safe-decoder-no-content-execution'),
             ('reproduce/build_bounded_owner_v24_failure_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# V24 bounded-owner control failure evidence

FAILED: ten normal-mode methods ran; nine passed and one errored. Fail-fast
left twenty normal methods and all thirty optimized methods unrun. These are
unrun methods, not skips. The normal stage returned 1 without a timeout after
141.832963303 seconds, under its unchanged 1,800-second module allowance and
10,800-second collection window. Source and SDK receipts were unchanged and
no owned descendants remained. This is not a suite or qualification pass.

The raw test log retains the root-fault subtest error, the internal coherence
exception and the public ValueError wrapper traceback. Its final unittest
summary is Ran 10 tests / FAILED (errors=1). The supervisor stopped before
adding its post-success test-inventory annotations. Configured expected_tests=30
must not be mistaken for thirty executed methods. Derived observed/unrun method
lists are separate from the untouched original runtime receipts.

All eleven original phase files, actual supervisor console, exact config,
supervisor source, full source/SDK seals, 31-path source manifest and frozen
source bytes are preserved. The exact executed test source is readable. Later
corrected proposals, private reviews and design notes are not included. No
missing evidence is reconstructed. The full unchanged repository and SDK binary
image are not distributed; their identities remain bound by the original seals.

Readable members retain exact bytes. Remaining originals use per-member base64
inside one JSON container, gzip-compressed with mtime=0 and then base64-encoded.
INNER-MEMBER-MANIFEST.json records all original paths, lengths, hashes and storage.
PUBLISHABLE-EVIDENCE-MANIFEST.json seals all payloads, excluding itself. Summary
and command-binding documents are derived and explicitly separate.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects unsafe paths, duplicate
members, symlink payloads and existing output. It never executes decoded source.
Packaging performs no candidate edit, test/native rerun or upload. Broader
lifecycle/per-site controls, full matrices, native coverage and hosted CI remain
outside the qualification supported by this failed run.
'''
payloads.append(('README.md', guide.encode(), 'scope-and-safe-transport-guide'))
need(len(payloads) == len({name for name, _, _ in payloads}) <= 35, 'Transport payload limit exceeded')
O.mkdir()
rows = []
for name, data, kind in sorted(payloads):
    path = O / name; path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(data)
    need(raw(path) == data, 'Packet copy mismatch')
    rows.append({'path': name, 'local_source': str(path), 'bytes': len(data),
                 'sha256': SHA(data), 'kind': kind})
manifest = O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with manifest.open('xb') as stream:
    stream.write(JSON({'schema': 1, 'scope': summary['scope'], 'files': rows}))
print(json.dumps({'manifest': str(manifest), 'sha256': digest(manifest), 'payloads': len(rows),
                  'original_members': len(members), 'archived_members': len(archived),
                  'original_bytes': inner['original_member_bytes'],
                  'total_packet_bytes_including_manifest': sum(row['bytes'] for row in rows) + manifest.stat().st_size,
                  'source_seal_sha256': SOURCE_SHA}))
