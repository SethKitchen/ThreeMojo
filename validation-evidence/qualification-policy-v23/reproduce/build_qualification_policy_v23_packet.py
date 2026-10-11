"""Preserve passing v23 policy/control subsets without relabeling prior failures.

Only named original files are packaged. No candidate, test or native content is
executed, and no prior packet, source file or receipt is modified or uploaded.
"""
from pathlib import Path
import base64
import gzip
import hashlib
import json
import re

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-qualification-policy-v23-packet'
SOURCE_SHA = '568961570d775e5b35bfbdec45a6b3530baa7422794a76a8b2ee59887e45dda7'
SOURCE_MANIFEST_SHA = 'a1a5c2cfbaecbdec07676467e4e5fe3f337470084c709ded33fd429f371df6c7'
PRIOR_SOURCE_SHA = '9fcd79a43418f8c8db99b559da8a0d9dfb32154b4ec9d5758d4d3bf73b51fcb3'
PRIOR_PACKET_SHA = '193f3f25ad34577e925b05f80887ecfeea4f0612bdc12bc665f9c612644ad52f'
PRIOR_FAILURE_SHA = 'f4f6808ea03a62c31cd1b89cfdf0cc5ebd4d3102e158e9ddb5be5abbf04c421d'
POLICY_PATH = 'docs/validation/full-audit-721-qualification-policy.md'
PHASES = ['invariant-input-policy-probes-v23', 'qualification-policy-maintained-tests-v23',
          'bounded-operation-synthetic-v23']
RESULT_SHAS = ['962b9e2deb77258faa6094dc7a189a81782b0d5ddb8a0af8c7b46f23ecd56e16',
               'c35635a9e0664034a94a3d67b5db13add6dfabb2c95af4466a0458b07aa54afd',
               '36c2d628342829c9d81799a047da1fb3bf4d9930f95f18d3acc657bda772b315']
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
need(digest(R / 'CANDIDATE-V23-SOURCE-SEAL.json') == SOURCE_SHA, 'V23 source seal changed')
need(digest(R / 'CANDIDATE-V22-SOURCE-SEAL.json') == PRIOR_SOURCE_SHA, 'Prior v22 seal changed')
manifest_path = R / 'qualification-policy-implementation-v23/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(manifest_path) == SOURCE_MANIFEST_SHA, '31-path source manifest changed')
source_manifest = read(manifest_path)
source_seal = read(R / 'CANDIDATE-V23-SOURCE-SEAL.json')
prior_seal = read(R / 'CANDIDATE-V22-SOURCE-SEAL.json')
need(source_manifest['source_seal_sha256'] == SOURCE_SHA and len(source_manifest['files']) == 31,
     'Source manifest differs')
changed_paths = {name for name in source_seal.keys() | prior_seal.keys()
                 if source_seal.get(name) != prior_seal.get(name)}
expected_changes = {POLICY_PATH, 'tools/carla_lane_oracle/test_coverage_invariant_contracts.py',
                    'tools/test_coverage_loop_proofs.py'}
need(changed_paths == expected_changes, 'Sealed v22/v23 policy delta differs')
need({row['path'] for row in source_manifest['delta_from_v22']} == expected_changes,
     'Manifest policy delta differs')
for row in source_manifest['delta_from_v22']:
    need(row['before_sha256'] == prior_seal.get(row['path'])
         and row['after_sha256'] == source_seal[row['path']], 'Policy delta hash differs')
prior_manifest = R / 'validation-evidence-lexical-relative-v22-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
prior_failure = R / 'evidence/invariant-input-cold-probes-v22/RESULT.json'
need(digest(prior_manifest) == PRIOR_PACKET_SHA and digest(prior_failure) == PRIOR_FAILURE_SHA,
     'Prior failure packet context changed')
old = read(prior_failure)
need(not old['sequence_completed'] and old['failure'] is not None
     and old['stages'][0]['returncode'] == -9 and old['stages'][0]['timed_out']
     and old['stages'][0]['stage_timeout_seconds'] == 10
     and old['stages'][0]['source_seal_sha256'] == PRIOR_SOURCE_SHA,
     'Historical v22 failure classification differs')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


results = []
configs = []
command_rows = []
sdk_reference = None
for index, (phase, result_sha) in enumerate(zip(PHASES, RESULT_SHAS)):
    evidence = R / 'evidence' / phase
    need(digest(evidence / 'RESULT.json') == result_sha, 'Phase result changed')
    result = read(evidence / 'RESULT.json')
    config = read(R / (phase + '.json'))
    window = read(evidence / 'WINDOW-START.json')
    need(len(result['stages']) == len(config['stages']) == [4, 4, 2][index], 'Stage inventory differs')
    need(result['sequence_completed'] and result['failure'] is None
         and result['source_seal_unchanged'] and result['sdk_identity_unchanged']
         and result['remaining_owned_descendants'] == [], 'Phase completion/source/SDK/cleanup differs')
    need(result['scope'] == config['scope'], 'Phase scope differs')
    need(digest(evidence / 'SOURCE-SEAL.json') == config['source_seal_sha256']
         == window['source_seal_sha256'] == SOURCE_SHA, 'Phase source binding differs')
    need(raw(evidence / 'SDK-BEFORE.json') == raw(evidence / 'SDK-AFTER.json'), 'SDK changed')
    if sdk_reference is None:
        sdk_reference = raw(evidence / 'SDK-BEFORE.json')
    need(sdk_reference == raw(evidence / 'SDK-BEFORE.json'), 'SDK differs between phases')
    need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
         and window['whole_window_seconds'] == config['window_seconds'] == [300, 10800, 10800][index]
         and window['python_optimize'] == 0, 'Supervisor/window binding differs')
    expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                      'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json'}
    readable_names = {'RESULT.json'}
    if index == 0:
        readable_names |= {'SDK-BEFORE.json', 'SDK-AFTER.json'}
    stage_bindings = []
    for stage, configured in zip(result['stages'], config['stages']):
        label = stage['label']
        need(stage == read(evidence / (label + '-RESULT.json')), 'Final/stage result differs')
        start = read(evidence / (label + '-START.json'))
        need(all(stage.get(key) == value for key, value in start.items()), 'START/result differs')
        expected_command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                            .replace('{evidence}', str(evidence)).replace('{root}', str(R))
                            for part in configured['command']]
        need(stage['argv'] == expected_command and stage['label'] == configured['label']
             and stage['cwd'] == config['source']
             and stage['stage_timeout_seconds'] == configured['seconds'] == [30, 1800, 1800][index],
             'Actual command or stage cap differs')
        need(stage['returncode'] == 0 and not stage['timed_out'] and stage['leader_reaped']
             and stage['remaining_owned_descendants'] == [] and stage['source_seal_sha256'] == SOURCE_SHA
             and stage['log_sha256'] == digest(evidence / (label + '.log')), 'Passing stage binding differs')
        log = raw(evidence / (label + '.log')).decode()
        if 'expected_tests' in configured:
            count = configured['expected_tests']
            need(stage['test_count'] == stage['expected_tests'] == count
                 and stage['skipped_test_count'] == 0, 'Method count or skip record differs')
            need(re.findall(r'^Ran (\d+) tests? in ', log, re.M) == [str(count)]
                 and len(re.findall(r'^test_.* \.\.\. ', log, re.M)) == count
                 and (len(re.findall(r'^test_.* \.\.\. ok$', log, re.M))
                      + len(re.findall(r'^ok$', log, re.M))) == count
                 and ' ... skipped ' not in log and log.rstrip().endswith('\nOK'),
                 'Raw unittest output differs from passing zero-skip count')
        else:
            need(index == 0 and log == '', 'Unexpected non-unittest probe output')
        expected_files |= {label + suffix for suffix in ['-START.json', '-RESULT.json', '.log']}
        readable_names.add(label + '.log')
        stage_bindings.append({'stage': stage,
                               'start_sha256': digest(evidence / (label + '-START.json')),
                               'stage_result_sha256': digest(evidence / (label + '-RESULT.json'))})
    console_lines = raw(R / (phase + '.supervisor.log')).splitlines()
    need(len(console_lines) == len(result['stages']) + 1
         and json.loads(console_lines[-1]) == result, 'Final supervisor console record differs')
    for line, stage in zip(console_lines[:-1], result['stages']):
        emitted = json.loads(line)
        need(all(stage.get(key) == value for key, value in emitted.items())
             and set(stage) - set(emitted) <= {'test_count', 'expected_tests', 'skipped_test_count'},
             'Original emitted stage record differs beyond later inventory annotations')
    need({path.name for path in evidence.iterdir()} == expected_files, 'Unexpected/missing original phase file')
    for name in sorted(expected_files):
        add(evidence / name, 'actual/' + phase + '/' + name, 'original-phase-receipt-or-merged-log',
            readable=name in readable_names)
    for suffix in ['.json', '.supervisor.log']:
        add(R / (phase + suffix), 'reproduce/' + phase + suffix,
            'actual-command-config-or-original-supervisor-console-output', readable=True)
    command_rows.append({'phase': phase, 'stages': stage_bindings,
                         'configured_but_unrun_labels': [],
                         'config_sha256': digest(R / (phase + '.json')), 'result_sha256': result_sha})
    results.append(result)
    configs.append(config)

probes, maintained, synthetic = results
need([s['label'] for s in probes['stages']] == ['normal-direct', 'normal-package', 'optimized-direct', 'optimized-package'],
     'Fresh policy probe mode inventory differs')
need([s['test_count'] for s in maintained['stages']] == [1, 4, 1, 4]
     and sum(s['test_count'] for s in maintained['stages']) == 10, 'Maintained method inventory differs')
need([s['test_count'] for s in synthetic['stages']] == [8, 8], 'Existing synthetic method inventory differs')
for name in ['run_checkpoint_matrix.py', 'CANDIDATE-V23-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'exact-supervisor-or-frozen-source-seal', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-31-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v23' / row['path']
    need(digest(path) == row['sha256'] == source_seal[row['path']]
         and path.stat().st_size == row['bytes'], 'Frozen manifest source changed')
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v23-source-or-policy-addendum',
        readable=row['path'] == POLICY_PATH)
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v23' / support) == source_seal[support], 'SDK identity support source changed')
add(R / 'candidate-v23' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')
add(prior_manifest, 'context/prior-v22-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json',
    'original-separate-prior-failure-packet-reference', readable=True)
add(prior_failure, 'context/prior-v22-original-10s-failure/RESULT.json',
    'original-v22-failure-not-a-v23-pass', readable=True)
add(R / 'invariant-input-cold-probes-v22.json', 'context/prior-v22-original-10s-failure/CONFIG.json',
    'original-prior-10-second-command-config')
add(R / 'CANDIDATE-V22-SOURCE-SEAL.json', 'context/prior-v22-original-10s-failure/SOURCE-SEAL.json',
    'original-prior-v22-source-seal')
summary = {
    'schema': 1, 'status': 'PASSED_V23_EXPLICIT_POLICY_AND_EXISTING_CONTROL_SUBSETS',
    'scope': 'Fresh four-mode probes under the explicit new 30-second policy, five affected maintained methods per mode, and eight existing synthetic methods per mode passed. Proposed real lifecycle/per-site additions, full matrix, native coverage and full completion are not qualified.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': SOURCE_MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 31, 'policy_addendum_path': 'reproduce/source/' + POLICY_PATH,
    'policy_addendum_sha256': source_seal[POLICY_PATH],
    'policy_boundary': {'new_import_source_verification_subprocess_seconds': 30,
        'prior_allowance_seconds': 10,
        'changed_harness_sites': ['CoverageInvariantContracts.test_direct_and_qualified_package_verification',
                                  'MapSuccessorLoopTests.clean_import_probe'],
        'sealed_delta_from_v22': sorted(changed_paths),
        'limit': 'This is an explicit new policy/source version with fresh execution receipts. Earlier original-limit failures remain failures; no claim is made that they passed or were merely diagnostic.'},
    'fresh_policy_probes': {'result_sha256': RESULT_SHAS[0], 'passed_commands': 4,
        'stage_cap_seconds': 30, 'window_cap_seconds': 300,
        'mode_timings_seconds': {stage['label']: stage['seconds'] for stage in probes['stages']},
        'all_returncodes_zero': True, 'all_modes_executed': True},
    'maintained_method_subset': {'result_sha256': RESULT_SHAS[1], 'methods_per_mode': 5,
        'method_executions': 10, 'skips': 0, 'module_cap_seconds': 1800, 'window_cap_seconds': 10800,
        'method_groups': {'invariant_direct_and_package_method': 1, 'clean_import_methods': 4},
        'limit': 'Only the five named affected maintained methods per mode; not the full Python matrix.'},
    'existing_synthetic_subset': {'result_sha256': RESULT_SHAS[2], 'methods_per_mode': 8,
        'method_executions': 16, 'skips': 0, 'module_cap_seconds': 1800, 'window_cap_seconds': 10800,
        'limit': 'The existing eight synthetic methods only. Separately proposed real owner lifecycle and per-site additions are not executed or qualified here.'},
    'passed_stages': 10, 'unittest_method_executions': 26, 'additional_fresh_probe_commands': 4,
    'all_phase_source_sdk_unchanged': True, 'all_phase_remaining_owned_descendants': [],
    'prior_v22_failure': {'status': 'FAILED_ORIGINAL_10_SECOND_GATE_UNCHANGED',
        'separate_packet_manifest_sha256': PRIOR_PACKET_SHA, 'result_sha256': PRIOR_FAILURE_SHA,
        'source_seal_sha256': PRIOR_SOURCE_SHA, 'returncode': -9, 'timed_out': True,
        'original_stage_cap_seconds': 10, 'observed_stage_seconds': old['stages'][0]['seconds'],
        'boundary': 'Included only as clearly separated prior evidence context. It is never relabeled as a new-policy v23 pass.'},
    'console_and_stream_capture': 'All three actual aggregate supervisor logs are preserved. They emit stage records before final test-inventory annotations; final/stage JSON preserves those annotations. Stage stdout/stderr are merged in the original logs, including empty probe output.',
    'remaining_qualification': ['proposed real lifecycle/per-site additions', 'full Python matrix',
                                'native controls and maintained coverage', 'exact-head hosted CI', 'overall issue completion'],
    'evidence_policy': 'All original files from all three terminal phase directories, actual root supervisor logs/configs, checked supervisor source, full source/SDK seals, 31-path manifest and source bytes including policy addendum are preserved. Prior v22 evidence remains separate and unchanged. No private reviews/design notes, secrets, broad unrelated source, candidate edits, tests/native reruns or external upload.'}
commands = {'schema': 1, 'kind': 'derived-actual-command-and-receipt-binding',
            'source_seal_sha256': SOURCE_SHA, 'phases': command_rows}

archive_name = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
members = []
archived = []
payloads = []
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
need(gzip.decompress(base64.b64decode(encoded)) == container, 'Container roundtrip failed')
inner = {'schema': 1, 'original_member_count': len(members),
         'original_member_bytes': sum(row['bytes'] for row in members),
         'container': {'path': archive_name, 'encoding': 'base64 of deterministic gzip mtime=0 containing JSON',
                       'members': len(archived), 'json_bytes': len(container), 'json_sha256': SHA(container)},
         'members': members}
payloads += [(archive_name, encoded, 'lossless-original-phase-receipts-and-source-bytes'),
             ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-path-byte-hash-and-storage-inventory'),
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-policy-and-control-subset-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(R / 'decode_qualification_policy_v23_evidence.py'), 'safe-decoder-no-content-execution'),
             ('reproduce/build_qualification_policy_v23_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# V23 policy and existing-control subset evidence

All ten supervised stages passed: four fresh direct/package normal/optimized
probes under the explicit new 30-second policy, five affected maintained methods
per mode (ten method executions), and eight existing synthetic methods per mode
(sixteen method executions). All unittest executions have zero skips. Source and
SDK identities were unchanged and no owned descendants remained.

The new policy changes only two named import/source-verification subprocess
allowances from ten to thirty seconds and adds the preserved policy addendum.
The 1,800-second module and 10,800-second test-window limits remain unchanged.
V22's original ten-second gate remains a failure, referenced separately under
context/ with its exact prior packet manifest, result/config and source seal.
No historical receipt is relabeled as a v23 pass.

These results do not qualify proposed real lifecycle/per-site additions, the
full Python matrix, native coverage, hosted CI or overall issue completion.
The synthetic result covers only the existing eight methods in each mode.

Every file in the three terminal phase directories is byte-preserved, along
with all three actual root supervisor console logs, exact configs/commands,
supervisor source, source/SDK seals, 31-path manifest and source bytes including
the readable policy addendum. The supervisor emitted each console stage record
before adding test-count fields; original final/stage receipts retain those
later inventory annotations. Raw merged stdout/stderr and empty logs are intact.

Readable files retain exact bytes. Other originals use per-member base64 in a
JSON container, gzip-compressed with mtime=0 and base64-encoded for transport.
INNER-MEMBER-MANIFEST.json records all paths, lengths, hashes and storage.
PUBLISHABLE-EVIDENCE-MANIFEST.json seals transport payloads, excluding itself.
Summary and command binding documents are derived and separate from receipts.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects unsafe paths, duplicate
members, symlinks and existing output. It never executes candidate content.
No candidate edits, test/native runs, private-note inclusion or uploads occur.
'''
payloads.append(('README.md', guide.encode(), 'scope-and-safe-transport-guide'))
need(len(payloads) == len({name for name, _, _ in payloads}) <= 35, 'Transport payload limit exceeded')
O.mkdir()
rows = []
for name, data, kind in sorted(payloads):
    path = O / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as output:
        output.write(data)
    need(raw(path) == data, 'Packet copy mismatch')
    rows.append({'path': name, 'local_source': str(path), 'bytes': len(data),
                 'sha256': SHA(data), 'kind': kind})
manifest = O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json'
with manifest.open('xb') as output:
    output.write(JSON({'schema': 1, 'scope': summary['scope'], 'files': rows}))
print(json.dumps({'manifest': str(manifest), 'sha256': digest(manifest),
                  'files': len(rows), 'bytes': sum(row['bytes'] for row in rows),
                  'manifest_bytes': manifest.stat().st_size,
                  'total_files_including_manifest': len(rows) + 1,
                  'total_bytes_including_manifest': sum(row['bytes'] for row in rows) + manifest.stat().st_size,
                  'original_members': len(members), 'archived_members': len(archived),
                  'source_seal_sha256': SOURCE_SHA}))
