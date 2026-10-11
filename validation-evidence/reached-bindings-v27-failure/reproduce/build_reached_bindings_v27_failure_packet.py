"""Package actual v27 failed sweep receipts and frozen source without execution.

Only byte reads, JSON/AST inspection, hashing and reversible serialization are
performed. No candidate import, test invocation, profiler load or upload occurs.
"""
from pathlib import Path
import ast
import base64
import gzip
import hashlib
import json
import re

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-reached-bindings-v27-failure-packet'
PHASE = 'reached-bindings-v27'
SOURCE_SHA = 'a36731dcc18ee0757482f613ad6d3b5ef96f0b67c0dd96a80d95105ed46ce8e5'
MANIFEST_SHA = '00064f7ae60ff1fdfcea950d3f07b20078d7ea5b05c3509a352ce89e1ac107c6'
RESULT_SHA = '3969fb3139c1a2b3c87417471f3ab9fd9cd1ec307e6ea59382e1a36b383d3560'
LOG_SHA = '61bed3e8e065548660dcaaf09130984fdae009e1083c519b81f5581464631705'
TEST = 'tools/carla_lane_oracle/test_invariant_operation_inputs.py'
TEST_SHA = 'e5b205db38fa5969e1bfee2f18742c8892deaac89c083c6fd0e567955d0939af'
METHOD = 'OperationReachedBindingControls.test_current_cold_routes_preserve_consumed_value_bindings'
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
manifest_path = R / 'test-append-implementation-v27/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(R / 'CANDIDATE-V27-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen source seal changed')
need(digest(manifest_path) == MANIFEST_SHA, 'Frozen source manifest changed')
need(digest(E / 'RESULT.json') == RESULT_SHA, 'Actual failure result changed')
source_seal = read(R / 'CANDIDATE-V27-SOURCE-SEAL.json')
source_manifest = read(manifest_path)
need(source_manifest['source_seal_sha256'] == SOURCE_SHA
     and source_manifest['status'] == 'source_only_unqualified'
     and len(source_manifest['files']) == 31
     and source_manifest['focused_methods'] == [METHOD], 'Frozen source manifest differs')
result = read(E / 'RESULT.json'); config = read(R / (PHASE + '.json')); window = read(E / 'WINDOW-START.json')
need(len(result['stages']) == 1 and len(config['stages']) == 2, 'Stage inventory differs')
stage = result['stages'][0]; label = stage['label']
need(label == 'normal-reached-bindings-v27' and stage['returncode'] == 1
     and not stage['timed_out'] and stage['seconds'] == 70.16300123700057
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
sdk = raw(E / 'SDK-BEFORE.json')
need(sdk == raw(E / 'SDK-AFTER.json') and SHA(sdk) == '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
     'SDK identities differ')
need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
     == '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
     and window['whole_window_seconds'] == config['window_seconds'] == 10800
     and stage['stage_timeout_seconds'] == config['stages'][0]['seconds'] == 1800,
     'Supervisor/cap binding differs')
for mode, configured in zip(('normal', 'optimized'), config['stages']):
    need(configured['expected_tests'] == 1 and configured['seconds'] == 1800
         and configured['label'] == mode + '-reached-bindings-v27'
         and configured['command'] == ['{python}'] + (['-O'] if mode == 'optimized' else [])
         + ['-B', TEST, '-v', '-f', METHOD], 'Configured focused command differs')
expected_command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                    for part in config['stages'][0]['command']]
need(stage['argv'] == expected_command and stage['cwd'] == config['source']
     == str(R / 'candidate-v27'), 'Actual fail-fast command differs')
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
need(SHA(log_raw) == stage['log_sha256'] == LOG_SHA and len(log_raw) == 944885, 'Raw log differs')
log = log_raw.decode('utf-8')
need(re.findall(r'^Ran (\d+) tests? in ', log, re.M) == ['1']
     and log.rstrip().endswith('FAILED (failures=1)')
     and ' ... skipped ' not in log and len(re.findall(r'^FAIL: ', log, re.M)) == 1
     and not re.search(r'^ERROR: ', log, re.M), 'Raw failure count differs')
started = re.findall(r'^test_\w+ \(__main__\.([^\n]+)\) \.\.\. ', log, re.M)
need(started == [METHOD] and "(owner='map_loops') ... FAIL" in log
     and "case.assertTrue(item['matched'])\nAssertionError: False is not true" in log,
     'Map assertion failure differs')
records = [json.loads(line.removeprefix('OPERATION_REACHED_BINDINGS '))
           for line in log.splitlines() if line.startswith('OPERATION_REACHED_BINDINGS ')]
need([row['route'] for row in records] == ['invariant', 'winner'], 'Completed route record inventory differs')
need([len(row['reached_sites']) for row in records] == [73, 102]
     and [len(row['residual_unreached_sites']) for row in records] == [35, 6]
     and all(set(row['site_bindings']) == set(row['reached_sites'])
             and row['original_streams'] == 0 for row in records), 'Saved route record inventory differs')
test_raw = raw(R / 'candidate-v27' / TEST)
need(SHA(test_raw) == source_seal[TEST] == TEST_SHA, 'Executed test source differs')
tree = ast.parse(test_raw)
methods = sorted(c.name + '.' + n.name for c in tree.body if isinstance(c, ast.ClassDef)
                 for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_'))
need(len(methods) == 34 and METHOD in methods, 'Frozen source method inventory differs')
lines = test_raw.decode().splitlines()
need(lines[2213].strip() == "case.assertTrue(item['matched'])"
     and lines[2306].strip() == 'report = summarize(operation, kind)', 'Traceback/source line binding differs')
prior_seal = read(R / 'CANDIDATE-V26-SOURCE-SEAL.json')
need(digest(R / 'CANDIDATE-V26-SOURCE-SEAL.json') == '22620c7e0e7308c7485d364c355a31c3f43ec58e26198ca673f65daacb34ce1a'
     and {p for p in source_seal.keys() | prior_seal.keys() if source_seal.get(p) != prior_seal.get(p)} == {TEST},
     'Sealed source delta differs')
expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                  'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json', 'FAILURE.json',
                  label + '-RESULT.json', label + '-START.json', label + '.log'}
need({p.name for p in E.iterdir()} == expected_files, 'Unexpected or missing original phase file')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


for name in sorted(expected_files):
    add(E / name, 'actual/' + PHASE + '/' + name, 'original-failure-phase-receipt-or-merged-log',
        readable=name in {'RESULT.json', 'FAILURE.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'})
for name in [PHASE + '.json', PHASE + '.supervisor.log', 'run_checkpoint_matrix.py', 'CANDIDATE-V27-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-config-console-supervisor-or-source-seal', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-31-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v27' / row['path']; data = raw(path)
    need(SHA(data) == row['sha256'] == source_seal[row['path']] and len(data) == row['bytes'],
         'Frozen source mismatch: ' + row['path'])
    need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == row['git_blob'],
         'Source Git blob mismatch')
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v27-source',
        readable=row['path'] in {TEST, 'docs/validation/full-audit-721-qualification-policy.md'})
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v27' / support) == source_seal[support], 'SDK support source changed')
add(R / 'candidate-v27' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')
summary = {
    'schema': 1, 'status': 'FAILED_V27_NORMAL_REACHED_BINDINGS_SWEEP_NOT_A_QUALIFICATION_PASS',
    'scope': 'One normal-mode focused method failed at the Map stream matched assertion after two completed invariant/winner route records. The normal Rtree route and all optimized routes were unrun. No dynamic sweep, suite or broader qualification pass.',
    'cause_classification': 'Unresolved binding evidence pending fresh exact queue replay. The saved failure does not establish a production defect or a harness defect.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 31, 'executed_test_path': TEST, 'executed_test_sha256': TEST_SHA,
    'source_test_methods': 34, 'selected_method': METHOD, 'other_33_methods_selected': False,
    'result_sha256': RESULT_SHA, 'stage_log_sha256': LOG_SHA, 'stage_log_bytes': len(log_raw),
    'actual_stage': {'label': label, 'returncode': 1, 'timed_out': False,
                     'elapsed_seconds': stage['seconds'], 'stage_cap_seconds': 1800,
                     'whole_window_cap_seconds': 10800, 'whole_window_elapsed_seconds': result['elapsed_seconds'],
                     'sequence_completed': False, 'fail_fast': True},
    'observed_normal_methods': {'ran': 1, 'passed': 0, 'failures': 1, 'errors': 0, 'skips_observed': 0,
                                'method_names': started, 'failure_subtest': "owner='map_loops'"},
    'normal_routes': {'completed_report_routes': ['invariant', 'winner'],
                      'failed_route': 'map_loops', 'unrun_routes': ['rtree_loops'],
                      'completed_report_metadata': [
                          {'route': row['route'], 'reached_sites': len(row['reached_sites']),
                           'residual_unreached_sites': len(row['residual_unreached_sites']),
                           'original_streams': row['original_streams']} for row in records],
                      'map_report_serialized': False, 'rtree_report_serialized': False},
    'optimized': {'status': 'UNRUN', 'configured_methods': 1,
                  'unrun_routes': ['invariant', 'winner', 'map_loops', 'rtree_loops']},
    'count_provenance': 'Counts are read from the original unittest log. The supervisor stopped on exit 1 before post-success test-count annotations. The configured expected_tests=1 is not a pass.',
    'binding_evidence_limit': 'Only invariant and winner JSON route records were emitted. The Map route reached summarize and failed at its stream matched assertion, so its stream/queue item and full Map report were not serialized. No missing Map or Rtree report is reconstructed and no failure cause is inferred.',
    'traceback_preservation': 'The full raw log preserves the Map subtest assertion traceback and both preceding route records. FAILURE.json preserves the supervisor traceback; the actual aggregate supervisor console is retained unchanged.',
    'source_sdk_unchanged': True, 'remaining_owned_descendants': [], 'sdk_receipt_sha256': SHA(sdk),
    'source_manifest_time_boundary': 'The original source_only_unqualified manifest is unchanged. This packet records the later failed run. The frozen source differs from v26 only at the test file; production/proof bytes are unchanged.',
    'reproduction_boundary': 'Includes all eleven original phase files, actual config/console/supervisor, the full source seal, all31 frozen manifest source paths and SDK identity support. The full unchanged repository and SDK executable image are not distributed.',
    'qualification_limit': 'No complete normal/optimized reached-binding sweep, full Python matrix, native coverage, hosted CI or overall issue completion is qualified. Earlier evidence remains in its separate packets.',
    'stream_capture': 'Original stdout/stderr share one merged stage log. The complete 944885-byte log is preserved in the reversible container. Separate streams and absent reports are not reconstructed.',
    'evidence_policy': 'Ordinary original receipts/logs/config and exact source bytes only. No private review/design notes, later proposed test changes, candidate edits, reruns, native execution or upload.'
}
commands = {'schema': 1, 'kind': 'derived-actual-command-and-receipt-binding',
            'phase': PHASE, 'source_seal_sha256': SOURCE_SHA,
            'config_sha256': digest(R / (PHASE + '.json')), 'result_sha256': RESULT_SHA,
            'stage': stage, 'start_sha256': digest(E / (label + '-START.json')),
            'stage_result_sha256': digest(E / (label + '-RESULT.json')),
            'supervisor_console_sha256': digest(R / (PHASE + '.supervisor.log')),
            'configured_but_unrun_stage_labels': ['optimized-reached-bindings-v27']}
archive_name = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
members = []; archived = []; payloads = []
need(len({row['path'] for row in originals}) == len(originals), 'Duplicate original member')
for row in sorted(originals, key=lambda row: row['path']):
    data = row['data']; member = {key: row[key] for key in ['path', 'kind', 'original_source']}
    member.update(bytes=len(data), sha256=SHA(data))
    if row['readable']:
        data.decode('utf-8'); payloads.append((row['path'], data, 'byte-exact-readable-original'))
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
need(digest(decoder) == 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4', 'Reviewed decoder changed')
payloads += [(archive_name, encoded, 'lossless-original-failure-receipts-full-raw-log-and-source-bytes'),
             ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-path-byte-hash-and-storage-inventory'),
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-failed-sweep-and-unrun-inventory-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(decoder), 'safe-decoder-no-content-execution'),
             ('reproduce/build_reached_bindings_v27_failure_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# V27 reached-bindings sweep failure evidence

FAILED: one selected normal-mode method ran and failed. Two completed route
records, invariant and winner, precede the Map stream matched assertion failure.
The Rtree route and the entire optimized stage were unrun. The normal stage
returned 1 without timeout after 70.163001237 seconds. Its original stage cap
was 1,800 seconds and window cap was 10,800 seconds. Source/SDK receipts were
unchanged; no owned descendants remained.

The cause is unresolved binding evidence pending fresh exact queue replay.
This receipt does not establish a production defect or a harness defect.
Only two route reports were serialized. No full Map report or failing queue
item was saved, and no Map/Rtree report is reconstructed. Completed route
records are partial evidence; they are not a completed dynamic sweep pass.

All eleven original phase files, actual configuration and supervisor console,
bound supervisor, full source/SDK seals, all thirty-one frozen manifest source
paths and SDK support source are preserved. The exact test source is readable.
Its original source-only status is historical and unchanged. The other thirty-
three test methods were not selected. No full matrix, native coverage, hosted
CI or overall completion is established. Earlier packets remain separate.

The entire 944,885-byte merged log, including both JSON route records and all
warnings/tracebacks, is preserved byte-for-byte inside the reversible container.
Other archived originals use per-member base64 in the same JSON container,
gzip-compressed with mtime=0 and base64-encoded. The inner manifest records
each original path, byte length, hash and storage. Readable originals retain
exact bytes. The outer manifest seals payloads and excludes its own bytes.
Summary and command-binding documents are explicitly derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder checks bytes before writing and rejects unsafe paths, duplicates,
symlink payloads and existing output. It never executes decoded content.
The full unchanged repository and SDK executable image are not distributed.
Packaging performs no candidate edit, test/native rerun or upload. Private
review/design notes and later proposed source changes are excluded.
'''
payloads.append(('README.md', guide.encode(), 'scope-and-safe-transport-guide'))
need(len(payloads) == len({n for n, _, _ in payloads}) <= 35, 'Transport payload limit exceeded')
O.mkdir(); rows = []
for name, data, kind in sorted(payloads):
    path = O / name; path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(data)
    need(raw(path) == data, 'Packet copy differs')
    rows.append({'path': name, 'local_source': str(path), 'bytes': len(data), 'sha256': SHA(data), 'kind': kind})
manifest = O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with manifest.open('xb') as stream:
    stream.write(JSON({'schema': 1, 'scope': summary['scope'], 'files': rows}))
print(json.dumps({'manifest': str(manifest), 'sha256': digest(manifest), 'payloads': len(rows),
                  'original_members': len(members), 'archived_members': len(archived),
                  'original_bytes': inner['original_member_bytes'],
                  'total_packet_bytes_including_manifest': sum(r['bytes'] for r in rows) + manifest.stat().st_size,
                  'source_seal_sha256': SOURCE_SHA}))
