"""Package only the two actual passing v25 phases, without executing source.

Preserve source/test logs and identities. Keep the earlier v24 failure outside
this packet, as a separate hash/path reference. Do not run tests or upload.
"""
from pathlib import Path
import ast
import base64
import gzip
import hashlib
import json
import re

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-bounded-owner-v25-packet'
PHASES = ['public-error-focused-v25', 'bounded-owner-controls-v25']
SOURCE_SHA = '22dae75f9db4f3569aba6d839f71fad9f426fdf10bf32c5d22e2e01530582ac8'
MANIFEST_SHA = 'eec81feea68a76daccac2d4d9ed255ee7b51d74b6eb029b58cd1b9c86bb9bc32'
RESULT_SHAS = ['e2f6fe63f761352b6b6a340403cb81f68af5ed778d50d70bb36d482581b8783b',
               'a5c8eaacd75bf3557e53902248f64eecbcbd343b267a42896e6d15b0053e0b42']
TEST = 'tools/carla_lane_oracle/test_invariant_operation_inputs.py'
TEST_SHA = 'a24b9ead2d8ed2ae3f05785ebbf3233773c473e595a7214216dc1f568ac54f1d'
PRIOR_PACKET = 'validation-evidence-bounded-owner-v24-failure-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
PRIOR_SHA = '9d60acf971b0979e998e4bfb754d2bee9d51e80e823281e37529f6fa953abd80'
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
manifest_path = R / 'public-error-implementation-v25/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(R / 'CANDIDATE-V25-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen source seal changed')
need(digest(manifest_path) == MANIFEST_SHA, 'Frozen manifest changed')
source_seal = read(R / 'CANDIDATE-V25-SOURCE-SEAL.json')
source_manifest = read(manifest_path)
need(source_manifest['source_seal_sha256'] == SOURCE_SHA and len(source_manifest['files']) == 31
     and source_manifest['status'] == 'source_only_unqualified', 'Source manifest identity/status differs')
need(digest(R / 'CANDIDATE-V24-SOURCE-SEAL.json') == 'fbc9cb60f5ee9320a9ec81b3bfe0c57bdb3ed331b3a93f7ec75268c651f95525',
     'Prior v24 seal changed')
prior_seal = read(R / 'CANDIDATE-V24-SOURCE-SEAL.json')
need({p for p in source_seal.keys() | prior_seal.keys() if source_seal.get(p) != prior_seal.get(p)} == {TEST},
     'Sealed production delta differs')
need(digest(R / PRIOR_PACKET) == PRIOR_SHA, 'Earlier failed packet reference changed')
prior_result = read(R / 'evidence/bounded-owner-controls-v24/RESULT.json')
need(not prior_result['sequence_completed'] and prior_result['stages'][0]['returncode'] == 1
     and not prior_result['stages'][0]['timed_out'], 'Earlier failure classification differs')
test_raw = raw(R / 'candidate-v25' / TEST)
need(SHA(test_raw) == source_seal[TEST] == TEST_SHA, 'Executed test bytes changed')
test_ast = ast.parse(test_raw)
methods = sorted(c.name + '.' + n.name for c in test_ast.body if isinstance(c, ast.ClassDef)
                 for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_'))
need(len(methods) == 30, 'Frozen thirty-method inventory differs')
focused = ['BoundedOwnerCurrentControls.' + name for name in (
    'test_current_foreign_root_thread_and_cwd_poison_the_owner',
    'test_current_invalid_exact_request_is_sticky_when_caught',
    'test_current_nested_public_owner_is_fresh_and_blocks_the_outer_handle',
    'test_current_registered_and_unregistered_aliases_block_outer_use')]
need(set(focused) <= set(methods), 'Focused names not in frozen test')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


command_rows = []; phase_summaries = []; sdk = None; total_tests = 0
for index, (phase, result_sha) in enumerate(zip(PHASES, RESULT_SHAS)):
    E = R / 'evidence' / phase
    need(digest(E / 'RESULT.json') == result_sha, 'Final result changed')
    result = read(E / 'RESULT.json'); config = read(R / (phase + '.json')); window = read(E / 'WINDOW-START.json')
    need(len(result['stages']) == len(config['stages']) == 2, 'Stage inventory differs')
    need(result['sequence_completed'] and result['failure'] is None
         and result['source_seal_unchanged'] and result['sdk_identity_unchanged']
         and result['remaining_owned_descendants'] == [], 'Completion/source/SDK/cleanup differs')
    need(result['scope'] == config['scope'], 'Phase scope differs')
    need(digest(E / 'SOURCE-SEAL.json') == config['source_seal_sha256']
         == window['source_seal_sha256'] == SOURCE_SHA, 'Phase source binding differs')
    if sdk is None:
        sdk = raw(E / 'SDK-BEFORE.json')
    need(sdk == raw(E / 'SDK-BEFORE.json') == raw(E / 'SDK-AFTER.json'), 'SDK identities differ')
    need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
         and window['whole_window_seconds'] == config['window_seconds'] == 10800,
         'Supervisor/window binding differs')
    expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                      'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json'}
    stage_rows = []; details = []
    count = 4 if index == 0 else 30
    for mode, stage, configured in zip(('normal', 'optimized'), result['stages'], config['stages']):
        label = stage['label']; start = read(E / (label + '-START.json'))
        need(stage == read(E / (label + '-RESULT.json'))
             and all(stage.get(k) == v for k, v in start.items()), 'START/stage/final mismatch')
        command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                   .replace('{evidence}', str(E)).replace('{root}', str(R)) for part in configured['command']]
        need(stage['argv'] == command and stage['cwd'] == config['source']
             and ('-O' in command) == (mode == 'optimized'), 'Exact actual command differs')
        need(stage['returncode'] == 0 and not stage['timed_out'] and stage['leader_reaped']
             and stage['remaining_owned_descendants'] == [] and stage['source_seal_sha256'] == SOURCE_SHA,
             'Passing source/cleanup result differs')
        need(stage['stage_timeout_seconds'] == configured['seconds'] == 1800
             and stage['seconds'] < 1800, 'Original stage cap differs')
        need(stage['test_count'] == stage['expected_tests'] == configured['expected_tests'] == count
             and stage['skipped_test_count'] == 0, 'Exact zero-skip count differs')
        log_raw = raw(E / (label + '.log')); log = log_raw.decode()
        need(SHA(log_raw) == stage['log_sha256'], 'Original log hash differs')
        need(re.findall(r'^Ran (\d+) tests? in ', log, re.M) == [str(count)]
             and log.rstrip().endswith('\nOK') and not re.search(r'\b(FAILED|ERROR|FAIL|skipped)\b', log),
             'Raw unittest outcome differs')
        observed = re.findall(r'^test_\w+ \((?:__main__|test_invariant_operation_inputs)\.([^\n]+)\) \.\.\. ', log, re.M)
        expected_methods = focused if index == 0 else methods
        need(observed == expected_methods, 'Observed method names/order differs')
        need(len(re.findall(r'^test_.* \.\.\. ok$', log, re.M)) + len(re.findall(r'^ok$', log, re.M)) == count,
             'Raw successful method status count differs')
        if index == 0:
            need(command[command.index('-f')+1:] == focused, 'Focused selection differs')
        else:
            need(command[command.index('-m'):] == ['-m', 'unittest', 'discover', '-s', 'tools/carla_lane_oracle',
                                                  '-p', 'test_invariant_operation_inputs.py', '-v', '-f'],
                 'Existing thirty-method file selection differs')
        expected_files |= {label + suffix for suffix in ('-START.json', '-RESULT.json', '.log')}
        stage_rows.append({'stage': stage, 'start_sha256': digest(E / (label + '-START.json')),
                           'stage_result_sha256': digest(E / (label + '-RESULT.json'))})
        details.append({'label': label, 'mode': mode, 'method_executions': count, 'skips': 0,
                        'returncode': 0, 'timed_out': False, 'stage_seconds': stage['seconds'],
                        'method_names': observed})
        total_tests += count
    console = [json.loads(line) for line in raw(R / (phase + '.supervisor.log')).splitlines()]
    need(len(console) == 3 and console[-1] == result, 'Original final supervisor console differs')
    for emitted, stage in zip(console[:-1], result['stages']):
        need(emitted == {k: v for k, v in stage.items()
                         if k not in ('test_count', 'expected_tests', 'skipped_test_count')},
             'Console differs beyond original later-added test inventory annotations')
    processes = [json.loads(line) for line in raw(E / 'PROCESSES.jsonl').splitlines()]
    need(processes and read(E / 'LATEST.json') == processes[-1], 'Process LATEST differs')
    stages = {s['label']: s for s in result['stages']}
    need(all(all(p['pgid'] == stages[row['label']]['pgid'] for p in row['owned']) for row in processes),
         'Process group differs')
    need({p.name for p in E.iterdir()} == expected_files and len(expected_files) == 13,
         'Original phase inventory differs')
    readable = {'RESULT.json', 'SDK-AFTER.json', 'SDK-BEFORE.json', 'WINDOW-START.json'}
    for name in sorted(expected_files):
        add(E / name, 'actual/' + phase + '/' + name, 'original-passing-phase-receipt-or-merged-log',
            readable=name in readable or name.endswith('.log'))
    for suffix in ('.json', '.supervisor.log'):
        add(R / (phase + suffix), 'reproduce/' + phase + suffix,
            'actual-config-or-original-supervisor-console', readable=True)
    command_rows.append({'phase': phase, 'stages': stage_rows, 'configured_but_unrun_labels': [],
                         'config_sha256': digest(R / (phase + '.json')), 'result_sha256': result_sha,
                         'supervisor_console_sha256': digest(R / (phase + '.supervisor.log'))})
    phase_summaries.append({'phase': phase, 'result_sha256': result_sha, 'method_executions': 2 * count,
                            'stages': details, 'all_original_phase_files': 13,
                            'window_elapsed_seconds': result['elapsed_seconds']})
need(total_tests == 68, 'Expected 68 method executions')
for name in ('CANDIDATE-V25-SOURCE-SEAL.json', 'run_checkpoint_matrix.py'):
    add(R / name, 'reproduce/' + name, 'original-frozen-source-seal-or-supervisor', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-31-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v25' / row['path']; data = raw(path)
    need(SHA(data) == row['sha256'] == source_seal[row['path']] and len(data) == row['bytes'],
         'Frozen manifest source differs: ' + row['path'])
    need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == row['git_blob'],
         'Git blob source identity differs')
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v25-manifest-source',
        readable=row['path'] in {TEST, 'docs/validation/full-audit-721-qualification-policy.md'})
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v25' / support) == source_seal[support], 'SDK support source changed')
add(R / 'candidate-v25' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')
summary = {
    'schema': 1, 'status': 'PASSED_V25_FOCUSED_PUBLIC_ERROR_AND_BOUNDED_OWNER_CONTROL_PHASES_ONLY',
    'scope': 'Only the two actual phases: eight focused method executions plus sixty executions of the existing thirty-method owner suite, normal and optimized. No dynamic observation sweep, full Python matrix, native coverage, hosted CI or full completion claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 31, 'executed_test_path': TEST, 'executed_test_sha256': TEST_SHA,
    'method_executions': 68, 'focused_method_executions': 8, 'bounded_owner_method_executions': 60,
    'unique_test_methods': 30,
    'overlap_note': 'The four focused methods are repeated within the thirty-method suite. Sixty-eight counts executions across two modes and two phases, not sixty-eight distinct methods.',
    'skips': 0, 'all_four_stages_returncode_zero': True, 'all_stages_timed_out': False,
    'stage_cap_seconds': 1800, 'whole_window_cap_seconds_each_phase': 10800,
    'phases': phase_summaries, 'all_phase_source_sdk_unchanged': True,
    'all_phase_remaining_owned_descendants': [], 'sdk_receipt_sha256': SHA(sdk),
    'source_boundary': 'The full sealed source mapping differs from v24 only at the executed test file. Production source bytes retain their v24 hashes. The original source-only manifest is unchanged; these later receipts establish only the two named passing phases.',
    'earlier_v24_failure_reference': {
        'separate_packet_path': PRIOR_PACKET, 'separate_packet_manifest_sha256': PRIOR_SHA,
        'status': 'FAILED_EARLIER_V24_RUN_UNCHANGED',
        'raw_members_included_here': False,
        'limit': 'The earlier v24 failure remains in its separate packet. None of its raw evidence, logs, source seal or source files is imported as a prior-v24 member into this passing packet; no historical error is relabeled.'},
    'console_binding_limit': 'Actual supervisor consoles emitted stage records before adding test_count, expected_tests and skipped_test_count. Original final and stage JSON retain those later annotations. No console output is reconstructed.',
    'stream_capture': 'Original stdout/stderr are merged in stage logs; warnings are retained. Separate streams are not invented.',
    'remaining_qualification': ['dynamic per-site observation sweep', 'full Python matrix', 'native controls and maintained coverage', 'exact-head hosted CI', 'overall issue completion'],
    'reproduction_boundary': 'Includes all 26 phase files, actual configs/supervisor consoles, supervisor source, full source/SDK seals, all 31 frozen manifest paths and SDK identity helper. Full unchanged repository and SDK executable payloads are not distributed.',
    'evidence_policy': 'Only ordinary original receipts/logs/configs and bound source bytes. No private review/design notes, unexecuted proposals, earlier failure contents, candidate edits, reruns or uploads.'
}
commands = {'schema': 1, 'kind': 'derived-actual-command-and-receipt-binding',
            'source_seal_sha256': SOURCE_SHA, 'phases': command_rows}
archive_name = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
members = []; archived = []; payloads = []
need(len({r['path'] for r in originals}) == len(originals), 'Duplicate original member')
for row in sorted(originals, key=lambda r: r['path']):
    data = row['data']; member = {k: row[k] for k in ('path', 'kind', 'original_source')}
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
         'original_member_bytes': sum(r['bytes'] for r in members),
         'container': {'path': archive_name, 'encoding': 'base64 of deterministic gzip mtime=0 containing JSON',
                       'members': len(archived), 'json_bytes': len(container), 'json_sha256': SHA(container)},
         'members': members}
decoder = R / 'validation-evidence-qualification-policy-v23-packet/decode_verify.py'
need(digest(decoder) == 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4',
     'Reviewed decoder changed')
payloads += [(archive_name, encoded, 'lossless-original-passing-phase-receipts-and-source-bytes'),
             ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-path-byte-hash-and-storage-inventory'),
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-passing-two-phase-execution-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(decoder), 'safe-decoder-no-content-execution'),
             ('reproduce/build_bounded_owner_v25_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# V25 focused and bounded-owner control evidence

Both actual phases passed in normal and optimized modes: four focused methods
per mode (eight executions), then the existing thirty-method suite per mode
(sixty executions). All sixty-eight executions had zero skips. The four focused
methods repeat within the thirty-method suite; this is thirty unique methods,
not sixty-eight distinct tests. All four stage exits were zero without timeout.
Source/SDK receipts were unchanged and no owned descendants remained.

The unchanged 1,800-second stage and 10,800-second phase-window limits apply.
This packet qualifies only these two executed phases. It does not claim a
dynamic per-site observation sweep, the full Python matrix, native coverage,
exact-head hosted CI or overall completion.

The earlier v24 run remains FAILED in the separate packet referenced by path
and manifest hash in VALIDATION-SUMMARY.json. None of that earlier packet's raw
failure members is included here, and no historical error is relabeled as a
v25 pass. The sealed v25 source differs from v24 only in the test file.

Every file from both original thirteen-file phase directories is preserved,
including merged test logs, START/RESULT, process histories, source and SDK
seals. Exact actual configs and supervisor consoles, bound supervisor source,
all thirty-one frozen manifest source paths and SDK identity helper are included.
The exact executed test is readable. The source-only manifest remains unchanged.
Supervisor console records precede the later test-count annotations retained
in original stage/final JSON. Nothing absent is reconstructed.

Readable members retain exact bytes. Other originals use per-member base64 in
one JSON container, gzip-compressed with mtime=0 and base64-encoded for transport.
INNER-MEMBER-MANIFEST.json records each original path, size, hash and storage.
PUBLISHABLE-EVIDENCE-MANIFEST.json seals payloads, excluding itself. Summary and
command-binding documents are derived and separate from original receipts.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects unsafe paths, duplicate
members, symlink payloads and existing output. It never executes decoded source.
Full unchanged repository and SDK binary images are not distributed. Packaging
performs no candidate edit, test/native rerun or upload. No private notes or
unexecuted proposal sources are included.
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
