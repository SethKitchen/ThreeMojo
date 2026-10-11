"""Package only the actual passing v26 mechanics phase, without executing source.

Preserve source/test logs and identities. Keep prior v25 evidence outside
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
O = R / 'validation-evidence-maintained-mechanics-v26-packet'
PHASES = ['maintained-mechanics-v26']
SOURCE_SHA = '22620c7e0e7308c7485d364c355a31c3f43ec58e26198ca673f65daacb34ce1a'
MANIFEST_SHA = 'dfd264e0f0cf159e7df385c54386b20ff1f0215fe0fd99a830c5824200042bae'
RESULT_SHAS = ['8ddad21c995b9f87dd8923a007727dd1c8d43efd007224564ee2fda06ba3e7a2']
TEST = 'tools/carla_lane_oracle/test_invariant_operation_inputs.py'
TEST_SHA = 'a65207f101084b01f1a764836359df68a7aed605e7fc76b3be8c7478081125f0'
PRIOR_PACKET = 'validation-evidence-bounded-owner-v25-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
PRIOR_SHA = 'dfd2b0221832d31f2be28fcd4020d85411a30e1d90d1f9416e42bba61e78a13b'
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
manifest_path = R / 'maintained-mechanics-implementation-v26/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(R / 'CANDIDATE-V26-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen source seal changed')
need(digest(manifest_path) == MANIFEST_SHA, 'Frozen manifest changed')
source_seal = read(R / 'CANDIDATE-V26-SOURCE-SEAL.json')
source_manifest = read(manifest_path)
need(source_manifest['source_seal_sha256'] == SOURCE_SHA and len(source_manifest['files']) == 31
     and source_manifest['status'] == 'source_only_unqualified', 'Source manifest identity/status differs')
need(digest(R / 'CANDIDATE-V25-SOURCE-SEAL.json') == '22dae75f9db4f3569aba6d839f71fad9f426fdf10bf32c5d22e2e01530582ac8',
     'Prior v25 seal changed')
prior_seal = read(R / 'CANDIDATE-V25-SOURCE-SEAL.json')
need({p for p in source_seal.keys() | prior_seal.keys() if source_seal.get(p) != prior_seal.get(p)} == {TEST},
     'Sealed production delta differs')
need(digest(R / PRIOR_PACKET) == PRIOR_SHA, 'Prior v25 packet reference changed')
test_raw = raw(R / 'candidate-v26' / TEST)
need(SHA(test_raw) == source_seal[TEST] == TEST_SHA, 'Executed test bytes changed')
test_ast = ast.parse(test_raw)
methods = sorted(c.name + '.' + n.name for c in test_ast.body if isinstance(c, ast.ClassDef)
                 for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_'))
need(len(methods) == 33, 'Frozen thirty-three-method source inventory differs')
focused = ['ReviewedClassifierMechanics.test_reviewed_exact_guard_projection_and_291_cases',
           'ReviewedRelativePathMechanics.test_native_path_fallback_without_layout_requirement',
           'ReviewedRelativePathMechanics.test_reviewed_110_cases_on_supported_posix_layout']
need(set(focused) <= set(methods), 'Selected mechanics methods missing')
prior_test = raw(R / 'candidate-v25' / TEST)
need(SHA(prior_test) == prior_seal[TEST], 'Prior test identity differs')
prior_ast = ast.parse(prior_test)
prior_methods = {(c.name, n.name): ast.dump(n, include_attributes=False)
                 for c in prior_ast.body if isinstance(c, ast.ClassDef)
                 for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}
current_methods = {(c.name, n.name): ast.dump(n, include_attributes=False)
                   for c in test_ast.body if isinstance(c, ast.ClassDef)
                   for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')}
need(len(prior_methods) == 30 and all(current_methods.get(k) == v for k, v in prior_methods.items()),
     'Existing thirty method ASTs differ')
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
    count = 3
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
        need(command[command.index('-f')+1:] == focused, 'Exact three-method selection differs')
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
need(total_tests == 6, 'Expected six method executions')
for name in ('CANDIDATE-V26-SOURCE-SEAL.json', 'run_checkpoint_matrix.py'):
    add(R / name, 'reproduce/' + name, 'original-frozen-source-seal-or-supervisor', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-31-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v26' / row['path']; data = raw(path)
    need(SHA(data) == row['sha256'] == source_seal[row['path']] and len(data) == row['bytes'],
         'Frozen manifest source differs: ' + row['path'])
    need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == row['git_blob'],
         'Git blob source identity differs')
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v26-manifest-source',
        readable=row['path'] in {TEST, 'docs/validation/full-audit-721-qualification-policy.md'})
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v26' / support) == source_seal[support], 'SDK support source changed')
add(R / 'candidate-v26' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')
summary = {
    'schema': 1, 'status': 'PASSED_V26_MAINTAINED_MECHANICS_THREE_METHODS_ONLY',
    'scope': 'Only three selected maintained mechanics methods in normal and optimized modes: six executions, zero skips. No complete owner-suite, dynamic observation sweep, full Python matrix, native coverage, hosted CI or overall completion claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 31, 'executed_test_path': TEST, 'executed_test_sha256': TEST_SHA,
    'method_executions': 6, 'unique_executed_methods': 3, 'selected_method_names': focused,
    'source_test_methods': 33, 'other_thirty_methods_rerun_in_this_phase': False,
    'skips': 0, 'all_two_stages_returncode_zero': True, 'any_stage_timed_out': False,
    'stage_cap_seconds': 1800, 'whole_window_cap_seconds': 10800,
    'phases': phase_summaries, 'source_sdk_unchanged': True,
    'remaining_owned_descendants': [], 'sdk_receipt_sha256': SHA(sdk),
    'method_level_evidence_limit': 'The original logs record three method outcomes per mode. Internal differential cases in method names/source are not separately persisted runtime reports; no new per-case receipts are reconstructed.',
    'source_boundary': 'The sealed source differs from v25 only at the test file. Production/proof source hashes are unchanged. All thirty pre-existing test-method ASTs are unchanged. The original source-only manifest remains intact.',
    'separate_v25_evidence_reference': {
        'packet_path': PRIOR_PACKET, 'packet_manifest_sha256': PRIOR_SHA,
        'raw_members_included_here': False,
        'limit': 'Prior v25 focused/owner results remain a distinct packet. This packet contains only the v26 mechanics phase and does not treat v25 as a v26 suite rerun.'},
    'console_binding_limit': 'Actual supervisor console emitted stage records before adding test_count, expected_tests and skipped_test_count; original final/stage JSON retains the later annotations. No console output is reconstructed.',
    'stream_capture': 'Original stdout/stderr share the merged stage logs; separate streams are not invented.',
    'remaining_qualification': ['dynamic per-site observation sweep', 'complete current owner-suite rerun', 'full Python matrix', 'native controls and maintained coverage', 'exact-head hosted CI', 'overall issue completion'],
    'reproduction_boundary': 'Includes all thirteen phase files, actual config/supervisor console, supervisor source, full source/SDK seals, all31 frozen manifest paths and SDK identity helper. Full unchanged repository and SDK/stdlib image are not distributed. The runtime stdlib-source comparison inside a method has no separately saved digest receipt; no such historical hash is invented.',
    'evidence_policy': 'Only ordinary original receipts/logs/config and bound source bytes. No private review/design notes, unexecuted proposals, prior v25 raw evidence, candidate edits, reruns or uploads.'
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
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-passing-three-method-mechanics-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(decoder), 'safe-decoder-no-content-execution'),
             ('reproduce/build_maintained_mechanics_v26_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = """# V26 maintained mechanics: three-method evidence only

Three selected mechanics methods passed in normal and optimized modes: six
executions, three unique methods, zero skips. Both stage exits were zero without
timeout. Stage times were 1.504460945 and 1.504155921 seconds; the original
1,800-second stage and 10,800-second window limits remain unchanged. Source/SDK
receipts were unchanged and no owned descendants remained.

Only these selected methods ran. The other thirty methods in the frozen test
file were not rerun in this phase. Prior v25 evidence stays in its separate
packet, referenced by path/hash in VALIDATION-SUMMARY.json without copying its
raw members. No full owner-suite, dynamic observation sweep, full Python matrix,
native coverage, hosted CI or overall-completion claim is made here.

The exact test source identifies the classifier projection/cases, lexical cases
and native-path fallback methods. The original logs preserve method outcomes;
no separate per-case runtime report was saved or is reconstructed. The full
source seal differs from v25 only at the test file; production bytes and the
thirty earlier test-method ASTs remain unchanged.

All thirteen original phase files, actual config and supervisor console,
bound supervisor, source/SDK seals, thirty-one frozen manifest source paths
and SDK support source are preserved. The exact test is readable. Original
supervisor console records precede later test-count annotations in stage/final
JSON. Nothing absent is reconstructed. Full unchanged repository and SDK/stdlib
images are not distributed; a historical stdlib-source digest is not invented.

Readable members retain exact bytes. Remaining originals use per-member base64
inside one JSON container, gzip-compressed with mtime=0 and base64-encoded.
INNER-MEMBER-MANIFEST.json records each original path, size, hash and storage.
PUBLISHABLE-EVIDENCE-MANIFEST.json seals payloads, excluding itself. Summary and
command-binding documents are explicitly derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects unsafe paths, duplicates,
symlink payloads and existing output. It never executes decoded source.
Packaging performs no candidate edit, test/native rerun or upload. Private notes
and unexecuted proposal sources are not included.
"""
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
