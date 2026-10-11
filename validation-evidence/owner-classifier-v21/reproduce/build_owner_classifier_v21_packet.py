"""Package v21 classifier controls, cold failure and plain diagnostic receipts.

Only named ordinary evidence is copied. No candidate code, harness, test or
native content is executed. Existing sources/receipts are never edited or uploaded.
"""
from pathlib import Path
import base64
import gzip
import hashlib
import json

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-owner-classifier-v21-packet'
SOURCE_SHA = '5e999090460174e7a57f023a94dbad09d596bcae4414d9785225f428cd1527bc'
SOURCE_MANIFEST_SHA = '367ba38b8dce2a7334d10cf5eda12b178edc52eea4fbc43c1b16f4b62a952afd'
BASELINE_SEAL_SHA = '8985c71b586bf5a8b8e7b7ddc21ad9c61be72f416da9b5d06d8e5c5901c2ae4e'
BASELINE_CORE_SHA = 'e86bdc939aec95fe579ce38cd9ca6c5c9b287a0623003d5d5679719b56d139b5'
PROPOSAL_CORE_SHA = '8a22685850e469f0d21a1865c41ef70b9e6d8780f2887cf6e99251ba09454c51'
HARNESS_SHA = '51b73077e56122ccfe5707a4ff66708abafcf4c0aafbdcdccfc13d247f8b59d4'
CORE = 'tools/carla_lane_oracle/full_audit_cleanup_contracts.py'
PHASES = ['owner-classifier-focused-controls-v21', 'invariant-input-cold-probes-v21',
          'invariant-input-plain-diagnostic-v21']
RESULT_SHAS = ['4e9225f3c96b927d9a419e7e64d466f13af4a6b8551449bb52b04f20dccc70d0',
               '447a4753da128075f0d366b526525917849a9baa0cb07fe7d41b664ddb167212',
               '882560091d6595d664bb6d07221f224060ac8d31a2b8f2da71c006de68b25006']
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
need(digest(R / 'CANDIDATE-V21-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen v21 seal changed')
need(digest(R / 'CANDIDATE-V19-SOURCE-SEAL.json') == BASELINE_SEAL_SHA, 'Frozen v19 baseline seal changed')
manifest_path = R / 'owner-classifier-implementation-v21/PUBLISHABLE-SOURCE-MANIFEST.json'
harness_path = R / 'owner-classifier-implementation-v21/classifier_equivalence_controls.py'
need(digest(manifest_path) == SOURCE_MANIFEST_SHA, '29-path source manifest changed')
need(digest(harness_path) == HARNESS_SHA, 'Checked harness bytes changed')
source_manifest = read(manifest_path)
source_seal = read(R / 'CANDIDATE-V21-SOURCE-SEAL.json')
baseline_seal = read(R / 'CANDIDATE-V19-SOURCE-SEAL.json')
need(source_manifest['source_seal_sha256'] == SOURCE_SHA and len(source_manifest['files']) == 29,
     'Source manifest binding changed')
need(digest(R / 'candidate-v21' / CORE) == source_seal[CORE] == PROPOSAL_CORE_SHA,
     'Proposal core binding changed')
need(digest(R / 'candidate-v19' / CORE) == baseline_seal[CORE] == BASELINE_CORE_SHA,
     'Baseline core binding changed')
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
    need(digest(evidence / 'RESULT.json') == result_sha, 'Phase result identity changed')
    result = read(evidence / 'RESULT.json')
    config = read(R / (phase + '.json'))
    window = read(evidence / 'WINDOW-START.json')
    need(len(result['stages']) == [2, 1, 1][index]
         and len(config['stages']) == [2, 4, 1][index], 'Phase stage inventory differs')
    need(result['source_seal_unchanged'] and result['sdk_identity_unchanged']
         and result['remaining_owned_descendants'] == [], 'Phase source/SDK/cleanup differs')
    need(digest(evidence / 'SOURCE-SEAL.json') == SOURCE_SHA
         and config['source_seal_sha256'] == window['source_seal_sha256'] == SOURCE_SHA,
         'Phase seal differs')
    need(result['scope'] == config['scope'], 'Scope differs')
    need(raw(evidence / 'SDK-BEFORE.json') == raw(evidence / 'SDK-AFTER.json'), 'SDK changed')
    if sdk_reference is None:
        sdk_reference = raw(evidence / 'SDK-BEFORE.json')
    need(sdk_reference == raw(evidence / 'SDK-BEFORE.json'), 'SDK differs across phases')
    need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
         and window['whole_window_seconds'] == config['window_seconds'] == [180, 300, 120][index],
         'Supervisor or whole-window bound changed')
    expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                      'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json'}
    readable_names = {'RESULT.json', 'SDK-AFTER.json', 'SDK-BEFORE.json', 'WINDOW-START.json'}
    if index == 0:
        expected_files |= {'normal-CONTROLS.json', 'optimized-CONTROLS.json'}
    elif index == 1:
        expected_files.add('FAILURE.json')
    stage_bindings = []
    for stage, configured in zip(result['stages'], config['stages']):
        label = stage['label']
        need(stage == read(evidence / (label + '-RESULT.json')), 'Stage/final result mismatch')
        start = read(evidence / (label + '-START.json'))
        need(all(stage.get(key) == value for key, value in start.items()), 'START/result mismatch')
        expected_command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                            .replace('{evidence}', str(evidence)).replace('{root}', str(R))
                            for part in configured['command']]
        need(stage['argv'] == expected_command and stage['label'] == configured['label']
             and stage['cwd'] == config['source']
             and stage['stage_timeout_seconds'] == configured['seconds'] == [30, 10, 30][index],
             'Actual command or cap differs')
        need(stage['source_seal_sha256'] == SOURCE_SHA and stage['leader_reaped']
             and stage['remaining_owned_descendants'] == []
             and stage['log_sha256'] == digest(evidence / (label + '.log')), 'Receipt binding differs')
        expected_files |= {label + suffix for suffix in ['-START.json', '-RESULT.json', '.log']}
        readable_names.add(label + '.log')
        stage_bindings.append({'stage': stage,
                               'start_sha256': digest(evidence / (label + '-START.json')),
                               'stage_result_sha256': digest(evidence / (label + '-RESULT.json'))})
    supervisor_lines = raw(R / (phase + '.supervisor.log')).splitlines()
    need(len(supervisor_lines) == len(result['stages']) + 1
         and [json.loads(line) for line in supervisor_lines[:-1]] == result['stages']
         and json.loads(supervisor_lines[-1]) == result, 'Supervisor output differs')
    need({p.name for p in evidence.iterdir()} == expected_files, 'Unexpected/missing phase file')
    for name in sorted(expected_files):
        add(evidence / name, 'actual/' + phase + '/' + name, 'original-receipt-log-or-controls-report',
            readable=name in readable_names)
    for suffix in ['.json', '.supervisor.log']:
        add(R / (phase + suffix), 'reproduce/' + phase + suffix,
            'original-config-or-supervisor-output', readable=True)
    command_rows.append({'phase': phase, 'stages': stage_bindings,
                         'configured_but_unrun_labels': [s['label'] for s in config['stages'][len(result['stages']):]],
                         'config_sha256': digest(R / (phase + '.json')), 'result_sha256': result_sha})
    results.append(result)
    configs.append(config)

focused, cold, plain = results
need(focused['sequence_completed'] and focused['failure'] is None
     and all(s['returncode'] == 0 and not s['timed_out'] for s in focused['stages']),
     'Focused classifier outcome differs')
need(configs[0]['additional_sources'] == [{'seal': str(R / 'CANDIDATE-V19-SOURCE-SEAL.json'),
                                         'source': str(R / 'candidate-v19')}], 'Baseline additional-source binding differs')
controls = {}
for mode, optimize, expected_sha, stage in zip(['normal', 'optimized'], [0, 1],
        ['88b75e12d03cf0f9b30c3b10a79ba6d69525ed76ececd08751ac305d7467b222',
         'b99afbf75c85f98ef8894bd3cc24cf8ac653e220268c780a9b8647ef4fb5bc77'], focused['stages']):
    path = R / 'evidence' / PHASES[0] / (mode + '-CONTROLS.json')
    need(digest(path) == expected_sha, 'Original control report changed')
    report = read(path)
    need(report['status'] == 'PASS' and report['optimize'] == optimize
         and report['always_active_checks_executed'] == 941
         and len(report['cases']) == report['equivalent'] == 291
         and report['negative_path_elisions'] == 6, 'Control report counts differ')
    need(report['baseline_sha256'] == BASELINE_CORE_SHA and report['proposal_sha256'] == PROPOSAL_CORE_SHA,
         'Report source binding differs')
    measured = [row for row in report['cases'] if row['label'].startswith('measured-')]
    need(len(measured) == 6 and all(row['old_path_constructions'] > 0
         and row['new_path_constructions'] == 0 for row in measured), 'Six designated elision cases differ')
    command = stage['argv'][-1]
    need(HARNESS_SHA in command and str(harness_path) in command
         and "raw=p.read_bytes()" in command and "exec(compile(raw,str(p),'exec')" in command,
         'Harness read/hash/compile command binding differs')
    printed = json.loads(raw(R / 'evidence' / PHASES[0] / (stage['label'] + '.log')))
    need(printed == {'status': 'PASS', 'cases': 291, 'equivalent': 291,
                    'negative_path_elisions': 6, 'optimize': optimize,
                    'always_active_checks_executed': 941, 'output': str(path)},
         'Control report differs from original supervised output')
    controls[mode] = report
need(controls['normal']['cases'] == controls['optimized']['cases'], 'Normal/optimized case records differ')
need(not cold['sequence_completed'] and cold['failure'] is not None
     and cold['stages'][0]['returncode'] == -9 and cold['stages'][0]['timed_out']
     and cold['stages'][0]['seconds'] == 10.061513043001469, 'Cold failure differs')
need(plain['sequence_completed'] and plain['failure'] is None
     and plain['stages'][0]['returncode'] == 0 and not plain['stages'][0]['timed_out']
     and plain['stages'][0]['seconds'] == 12.531899080997391, 'Plain diagnostic outcome differs')
need(cold['stages'][0]['argv'] == plain['stages'][0]['argv']
     and cold['stages'][0]['cwd'] == plain['stages'][0]['cwd']
     and plain['stages'][0]['argv'][1] == '-c'
     and 10 < plain['stages'][0]['seconds'] < 30, 'Plain diagnostic body/source/cap boundary differs')

for name in ['run_checkpoint_matrix.py', 'CANDIDATE-V21-SOURCE-SEAL.json', 'CANDIDATE-V19-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-supervisor-or-source-seal', readable=True)
add(harness_path, 'reproduce/classifier_equivalence_controls.py', 'exact-command-hash-checked-executed-harness', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-29-path-frozen-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v21' / row['path']
    need(digest(path) == row['sha256'] == source_seal[row['path']]
         and path.stat().st_size == row['bytes'], 'Frozen source changed: ' + row['path'])
    add(path, 'reproduce/source/v21/' + row['path'], 'exact-frozen-v21-manifest-source')
add(R / 'candidate-v19' / CORE, 'reproduce/source/baseline-v19/' + CORE, 'exact-report-bound-classifier-baseline-core')
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v21' / support) == source_seal[support], 'SDK identity helper changed')
add(R / 'candidate-v21' / support, 'reproduce/source/support/' + support, 'exact-supervisor-sdk-identity-source')

summary = {
    'schema': 1, 'status': 'V21_CLASSIFIER_CONTROLS_PASS_COLD_GATE_FAIL_PLAIN_DIAGNOSTIC_COMPLETES',
    'scope': 'Focused synthetic-frame classifier equivalence passes only. Original 10-second real cold gate fails. Separate identical-body 30-second plain diagnostic completes above ten seconds. No original-cap, lifecycle, readiness or broader qualification claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': SOURCE_MANIFEST_SHA,
    'exact_frozen_v21_source_paths': 29, 'proposal_core_sha256': PROPOSAL_CORE_SHA,
    'baseline_source_seal_sha256': BASELINE_SEAL_SHA, 'baseline_core_sha256': BASELINE_CORE_SHA,
    'checked_harness_sha256': HARNESS_SHA,
    'classifier_controls': {'status': 'PASS_CLASSIFIER_ONLY', 'result_sha256': RESULT_SHAS[0],
        'modes': {mode: {'optimize': report['optimize'], 'equivalent_differentials': report['equivalent'],
                        'always_active_checks': report['always_active_checks_executed'],
                        'designated_measured_negative_path_elisions': report['negative_path_elisions'],
                        'report_sha256': digest(R / 'evidence' / PHASES[0] / (mode + '-CONTROLS.json'))}
                  for mode, report in controls.items()},
        'stage_cap_seconds': 30, 'window_cap_seconds': 180,
        'harness_binding': 'Each original stage reads the external harness once, checks its exact SHA-256, and compiles those same bytes. The checked revision is preserved; the unexecuted rejected revision is omitted.',
        'scope_limit': 'Real canonical code/global identities are carried by synthetic frame records. Classifier differential equivalence is covered; real owner lifecycle, source admission and maintained cold-watchdog qualification are not.'},
    'cold_probe': {'status': 'FAILED_ORIGINAL_10_SECOND_BOUND', 'result_sha256': RESULT_SHAS[1],
        'executed': 'normal-direct', 'returncode': -9, 'timed_out': True, 'cap_seconds': 10,
        'observed_stage_seconds': cold['stages'][0]['seconds'], 'window_cap_seconds': 300,
        'unrun': ['normal-package', 'optimized-direct', 'optimized-package']},
    'plain_diagnostic': {'status': 'COMPLETED_SEPARATE_30_SECOND_DIAGNOSTIC_NOT_10_SECOND_PASS',
        'result_sha256': RESULT_SHAS[2], 'returncode': 0, 'timed_out': False,
        'stage_cap_seconds': 30, 'window_cap_seconds': 120,
        'observed_stage_seconds': plain['stages'][0]['seconds'],
        'argv_and_cwd_exactly_equal_to_failed_cold_command': True,
        'profiler_or_instrumentation': False,
        'limit': 'The exact same normal-direct body and frozen source complete with exit 0 under the separately authorized 30-second diagnostic cap. The observed stage duration exceeds ten seconds. This does not relax, replace or pass the original 10-second qualification gate.'},
    'all_phase_source_sdk_unchanged': True, 'all_phase_remaining_owned_descendants': [],
    'stream_capture': 'Original logs combine stdout and stderr. Empty cold and plain logs are preserved; separate streams were not recorded or invented.',
    'source_manifest_time_boundary': 'The original source-only/unqualified manifest is preserved unchanged. Later receipts retain their distinct control, failure and diagnostic outcomes.',
    'evidence_policy': 'All files from all three terminal phase directories, actual configs/commands/supervisor output, source/SDK seals, checked harness, 29 frozen v21 source paths and bound v19 baseline core are preserved byte-for-byte. Derived summaries are separate. No rejected harness revision, internal notes/reviews, secrets, broad unrelated source, executable payloads, candidate edits, reruns or uploads.'}
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
payloads += [(archive_name, encoded, 'lossless-original-raw-receipts-and-source-bytes'),
             ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-path-byte-hash-and-storage-inventory'),
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-failure-and-censoring-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(R / 'decode_owner_classifier_v21_evidence.py'), 'safe-decoder-no-content-execution'),
             ('reproduce/build_owner_classifier_v21_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# V21 classifier controls, cold failure and plain diagnostic

Normal and optimized focused classifier controls each passed 291 differential
cases, 941 always-active checks and six designated measured-negative Path-elision
checks. The exact executed harness is SHA-256 checked by each original command.
These are classifier-only controls using synthetic frame records with real
canonical code/global identities, not real operation-lifecycle qualification.

The original maintained 10-second normal-direct cold gate failed at
10.061513043 seconds with exit -9. The remaining normal-package and two optimized
commands were not run. A separately authorized plain diagnostic used the exact
same argv, body, working directory and frozen source, without profiling, and
completed at 12.531899081 seconds with exit 0 under a 30-second outer cap.
That completion exceeds the original ten-second bound and is not a cap pass,
readiness finding or broader qualification result.

Every file in the three terminal evidence directories is preserved, including
all START/RESULT/logs, empty output, process receipts, full control reports,
source and before/after SDK seals. Exact configs and supervisor output, the
checked harness, all 29 frozen v21 manifest source paths, the v19 baseline seal
and report-bound baseline core bytes are included. The unexecuted rejected
harness revision and internal reviews/notes are omitted.

Readable files retain exact bytes. Remaining originals are represented by
per-member base64 in one JSON container, gzip-compressed with mtime=0 and then
base64-encoded. INNER-MEMBER-MANIFEST.json records every original path, length,
SHA-256 and storage. PUBLISHABLE-EVIDENCE-MANIFEST.json seals all transport
payloads, excluding itself. Summary and command binding documents are derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all bytes before writing and rejects unsafe paths,
duplicates, symlink payloads and existing output. It never executes decoded
source or harness content. Original absolute paths are provenance only. No
candidate changes, tests, native runs or uploads are performed by packaging.
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
