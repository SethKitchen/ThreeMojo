"""Package frozen v18 failures and censored diagnostic evidence, without execution.

Only named ordinary receipts, configs and source inputs are included. Existing
receipts and candidate roots are never modified. No external upload is performed.
"""
from pathlib import Path
import base64
import gzip
import hashlib
import json
import re

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-invariant-v18-failure-diagnostic-packet'
SOURCE_SHA = 'ae215438b73c2c18334e5ae98ef8d0fca64e6e0d6c0807d87688a80c4ca51e66'
SOURCE_MANIFEST_SHA = '052d767a5ad66e848e5f2ed3139e4dec96f29c602936ebd63ed51388e00d1fab'
PHASES = ['invariant-input-cold-probes-v18', 'invariant-input-diagnostic-v18',
          'invariant-adapter-synthetic-controls-v18']
RESULT_SHAS = ['0b1d1fb066889920ea20f48632ee50b6d1f8a1f6b8f136c5c72faf4c3bfdda79',
               'ad8b662acac31c2fcbffee82c2db4560eca88222de485ea3a283acd376a7bb44',
               '15805a1caac24ac02a4bdb18a1ecb47bf991b81413d5d2b628e451edf631b6bb']
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
need(digest(R / 'CANDIDATE-V18-SOURCE-SEAL.json') == SOURCE_SHA, 'V18 source seal changed')
manifest_path = R / 'invariant-operation-implementation-v18/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(manifest_path) == SOURCE_MANIFEST_SHA, '18-path source manifest changed')
source_manifest = read(manifest_path)
source_seal = read(R / 'CANDIDATE-V18-SOURCE-SEAL.json')
need(source_manifest['source_seal_sha256'] == SOURCE_SHA
     and source_manifest['count'] == len(source_manifest['files']) == 18, 'Source manifest differs')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


results = []
configs = []
command_rows = []
sdk_reference = None
for phase, result_sha in zip(PHASES, RESULT_SHAS):
    evidence = R / 'evidence' / phase
    need(digest(evidence / 'RESULT.json') == result_sha, 'Final phase result changed: ' + phase)
    result = read(evidence / 'RESULT.json')
    config = read(R / (phase + '.json'))
    window = read(evidence / 'WINDOW-START.json')
    need(len(result['stages']) == 1 and result['source_seal_unchanged']
         and result['sdk_identity_unchanged'] and result['remaining_owned_descendants'] == [],
         'Phase source/SDK/cleanup differs: ' + phase)
    need(digest(evidence / 'SOURCE-SEAL.json') == SOURCE_SHA
         and config['source_seal_sha256'] == SOURCE_SHA
         and window['source_seal_sha256'] == SOURCE_SHA, 'Phase seal differs')
    need(raw(evidence / 'SDK-BEFORE.json') == raw(evidence / 'SDK-AFTER.json'), 'SDK changed')
    if sdk_reference is None:
        sdk_reference = raw(evidence / 'SDK-BEFORE.json')
    need(sdk_reference == raw(evidence / 'SDK-BEFORE.json'), 'SDK differs across phases')
    need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
         and window['whole_window_seconds'] == config['window_seconds'] == 300,
         'Supervisor or whole-window bound changed')
    stage = result['stages'][0]
    configured = config['stages'][0]
    label = stage['label']
    need(stage == read(evidence / (label + '-RESULT.json')), 'Final/stage result mismatch')
    start = read(evidence / (label + '-START.json'))
    need(all(stage.get(key) == value for key, value in start.items()), 'START/result mismatch')
    expected_command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                        .replace('{evidence}', str(evidence)).replace('{root}', str(R))
                        for part in configured['command']]
    need(stage['argv'] == expected_command and stage['label'] == configured['label']
         and stage['cwd'] == config['source']
         and stage['stage_timeout_seconds'] == configured['seconds'], 'Command/cap differs')
    need(stage['source_seal_sha256'] == SOURCE_SHA and stage['leader_reaped']
         and stage['remaining_owned_descendants'] == []
         and stage['log_sha256'] == digest(evidence / (label + '.log')), 'Receipt binding differs')
    supervisor_lines = raw(R / (phase + '.supervisor.log')).splitlines()
    need(len(supervisor_lines) == 2 and json.loads(supervisor_lines[0]) == stage
         and json.loads(supervisor_lines[1]) == result, 'Supervisor log differs')
    expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                      'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json',
                      label + '-RESULT.json', label + '-START.json', label + '.log'}
    expected_files |= {'RAW-PROFILE.json', 'profile.pstats'} if phase == PHASES[1] else {'FAILURE.json'}
    need({p.name for p in evidence.iterdir()} == expected_files, 'Unexpected or missing phase file')
    for name in sorted(expected_files):
        add(evidence / name, 'actual/' + phase + '/' + name,
            'original-binary-pstats' if name == 'profile.pstats' else 'original-raw-receipt-or-profile',
            readable=name in {'RESULT.json', 'SDK-AFTER.json', 'SDK-BEFORE.json', 'WINDOW-START.json', label + '.log'})
    for suffix in ['.json', '.supervisor.log']:
        add(R / (phase + suffix), 'reproduce/' + phase + suffix,
            'original-command-config-or-supervisor-output', readable=True)
    command_rows.append({'phase': phase, 'stage': stage,
                         'configured_but_unrun_labels': [s['label'] for s in config['stages'][1:]],
                         'config_sha256': digest(R / (phase + '.json')),
                         'result_sha256': result_sha,
                         'start_sha256': digest(evidence / (label + '-START.json')),
                         'stage_result_sha256': digest(evidence / (label + '-RESULT.json'))})
    results.append(result)
    configs.append(config)

cold, diagnostic, synthetic = results
need(not cold['sequence_completed'] and cold['failure'] is not None
     and cold['stages'][0]['returncode'] == -9 and cold['stages'][0]['timed_out']
     and cold['stages'][0]['stage_timeout_seconds'] == 10
     and cold['stages'][0]['seconds'] == 10.033769374000258
     and len(configs[0]['stages']) == 4, 'Cold failure classification differs')
need(diagnostic['sequence_completed'] and diagnostic['failure'] is None
     and diagnostic['stages'][0]['returncode'] == 1 and not diagnostic['stages'][0]['timed_out']
     and configs[1]['stages'][0]['accept_nonzero'] is True
     and diagnostic['stages'][0]['stage_timeout_seconds'] == 10, 'Diagnostic classification differs')
need(not synthetic['sequence_completed'] and synthetic['failure'] is not None
     and synthetic['stages'][0]['returncode'] == 1 and not synthetic['stages'][0]['timed_out']
     and synthetic['stages'][0]['stage_timeout_seconds'] == 60
     and len(configs[2]['stages']) == 2, 'Synthetic failure classification differs')
synthetic_log = raw(R / 'evidence' / PHASES[2] / 'normal.log').decode()
need(len(re.findall(r'^test_.* \.\.\. ok$', synthetic_log, re.M)) == 7
     and len(re.findall(r'^test_.* \.\.\. ERROR$', synthetic_log, re.M)) == 1
     and 'Ran 8 tests in ' in synthetic_log and synthetic_log.rstrip().endswith('FAILED (errors=1)'),
     'Synthetic method outcomes differ')
profile_path = R / 'evidence' / PHASES[1] / 'RAW-PROFILE.json'
profile = read(profile_path)
payload = read(R / 'invariant-profile-command-v18.json')
need(payload['command'] == cold['stages'][0]['argv'][-1]
     and SHA(payload['command'].encode()) == payload['command_sha256'] == profile['command_sha256'],
     'Profile command differs from cold command')
need(profile['status'] == 'diagnostic deadline' and profile['work_cap_seconds'] == 8
     and profile['outer_child_cap_seconds'] == 10
     and profile['raw_code_identities_preserved_before_pstats'], 'Profile was not the declared censored diagnostic')
gate_path = str(R / 'candidate-v18/tools/carla_lane_oracle/full_audit_cleanup_contracts.py')
gate_entries = [row for row in profile['entries'] if row['code'].get('filename') == gate_path
                and row['code'].get('qualname') == 'verify']
finish_entries = [row for row in profile['entries'] if row['code'].get('filename') == gate_path
                  and row['code'].get('qualname') == '_InvariantInputs.finish']
need(len(gate_entries) == 1 and gate_entries[0]['calls'] == 1 and not finish_entries,
     'Censored gate/finalizer observations differ')
diagnostic_log = raw(R / 'evidence' / PHASES[1] / 'bounded-partial-profile.log').decode()
need(diagnostic_log.startswith('Timeout (0:00:04)!\n')
     and 'line 749 in inventory' in diagnostic_log, 'Four-second stack snapshot missing')

for name in ['run_checkpoint_matrix.py', 'profile_invariant_child_v18.py',
             'invariant-profile-command-v18.json', 'CANDIDATE-V18-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-harness-profile-payload-or-source-seal', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-18-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v18' / row['path']
    need(digest(path) == row['sha256'] == source_seal[row['path']]
         and path.stat().st_size == row['bytes'], 'Frozen source changed: ' + row['path'])
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v18-manifest-source')
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v18' / support) == source_seal[support], 'SDK identity support changed')
add(R / 'candidate-v18' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')

summary = {
    'schema': 1, 'status': 'FAILED_V18_REAL_COLD_GATE_AND_SYNTHETIC_CONTROL_WITH_CENSORED_DIAGNOSTIC',
    'scope': 'Ordinary frozen-v18 failure and diagnostic receipts only. No passing real admission or timing-cap result; no v19 or broader qualification claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': SOURCE_MANIFEST_SHA,
    'exact_frozen_source_paths': 18,
    'cold_probe': {'status': 'FAILED_10_SECOND_BOUND', 'result_sha256': RESULT_SHAS[0],
                   'executed': 'normal-direct', 'returncode': -9, 'timed_out': True,
                   'cap_seconds': 10, 'observed_stage_seconds': cold['stages'][0]['seconds'],
                   'unrun': ['normal-package', 'optimized-direct', 'optimized-package']},
    'diagnostic': {'status': 'CENSORED_PARTIAL_PROFILE_NOT_A_PASS', 'result_sha256': RESULT_SHAS[1],
                   'work_cap_seconds': 8, 'outer_stage_cap_seconds': 10,
                   'profile_elapsed_seconds': profile['elapsed_seconds'],
                   'supervised_stage_seconds': diagnostic['stages'][0]['seconds'],
                   'returncode': 1, 'timed_out_by_outer_supervisor': False,
                   'sequence_completed_meaning': 'The configured diagnostic collection sequence accepted nonzero exit 1. It does not mean invariant.verify completed or passed.',
                   'raw_profile_sha256': digest(profile_path),
                   'pstats_sha256': digest(R / 'evidence' / PHASES[1] / 'profile.pstats'),
                   'raw_code_entries': len(profile['entries']), 'module_bindings': len(profile['module_bindings']),
                   'raw_code_object_ids_preserved': True, 'pstats_loaded_by_packager': False,
                   'four_second_stack': 'Original merged diagnostic log retains faulthandler stack at full_audit_cleanup_contracts.inventory line 749.',
                   'observed_full_audit_verify_invocations': 1,
                   'operation_finish_entries_observed': 0,
                   'censoring_limit': 'One verify invocation is observed in the interrupted profile; its successful completion is not established. No operation finish entry is observed before censoring. Timings include profiling instrumentation and are not comparable to an unprofiled admission pass.',
                   'profiler_binding_limit': 'The original stage identifies the profiler path but does not separately hash its source. This packet records the present source bytes and digest; WINDOW-START independently binds the supervisor hash.'},
    'synthetic_controls': {'status': 'FAILED_ONE_NEW_COMMENT_POSITIVE_FIXTURE',
                            'result_sha256': RESULT_SHAS[2], 'methods_run': 8,
                            'passing_methods': 7, 'error_methods': 1, 'returncode': 1,
                            'failed_method': 'test_private_selector_supplied_comments_keep_token_equivalence',
                            'reported_error': 'full-audit cleanup successor: checked physical and supplied views differ: extensions/carla/lane_refinement.mojo',
                            'stage_cap_seconds': 60, 'unrun': ['optimized'],
                            'limit': 'Synthetic/AST controls do not establish real source-admission or timing-cap qualification. The recorded fixture error is retained without substitution by a later correction.'},
    'all_phase_source_sdk_unchanged': True, 'all_phase_remaining_owned_descendants': [],
    'window_cap_seconds_per_phase': 300,
    'stream_capture': 'Original stage .log files merge stdout and stderr. Separate streams were not recorded or reconstructed.',
    'source_manifest_time_boundary': 'The original 18-path manifest retains its historical pending-runtime wording. The later original receipts here record the observed failures.',
    'later_candidate_boundary': 'Frozen v18 bytes and outcomes remain unchanged. Any v19 comment-prefix fixture correction is outside this packet and has no execution or qualification receipt here.',
    'evidence_policy': 'Every file in the three original phase directories is preserved byte-for-byte, including failures, nonzero results, empty output, pstats and raw profile. No internal reviews/design notes, secrets, executable binaries, broad unrelated source, source edits, reruns, native execution or external upload.',
}
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
payloads += [(archive_name, encoded, 'lossless-original-bytes-including-binary-pstats'),
             ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-path-byte-hash-and-storage-inventory'),
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-failure-and-censoring-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(R / 'decode_invariant_v18_evidence.py'), 'safe-decoder-no-execution-or-pstats-loading'),
             ('reproduce/build_invariant_v18_failure_diagnostic_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# Frozen-v18 failure and diagnostic evidence

The real normal-direct admission command failed its original 10-second bound
(10.033769374 seconds, exit -9). Normal package and both optimized cold commands
were not run. The separate diagnostic was intentionally interrupted after eight
seconds under a 10-second outer limit and returned 1. Its completed collection
sequence is not an admission or timing-cap pass. Raw profile identities, binary
pstats and the four-second faulthandler stack are preserved. The partial profile
observes one full-audit verify invocation and no operation finish entry; it does
not establish successful gate completion or uncensored finalizer behavior.

The synthetic normal run executed eight methods: seven passed and the new
supplied-comment positive fixture raised the recorded error. Optimized synthetic
controls were not run. No later fixture correction replaces those failure bytes.

Every original file in all three phase directories is preserved, together with
actual configs, supervisor output, profiler source/payload and exact frozen
18-path source bytes plus their original source manifest and full source seal.
The SDK identity helper is included. All original source/SDK receipt hashes are
checked. The profiler's path is recorded by the original command; its source
digest is newly sealed by this packet rather than a historical stage hash.

Readable receipt/config files retain their exact bytes. Remaining originals,
including binary pstats and RAW-PROFILE.json, are losslessly encoded as per-member
base64 inside one JSON container, compressed with gzip mtime=0, then base64-encoded.
INNER-MEMBER-MANIFEST.json records every member's path, length, SHA-256 and storage.
The outer PUBLISHABLE-EVIDENCE-MANIFEST.json seals all transport payloads and does
not recursively list itself. Derived summary and command bindings are separate.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all bytes before writing and rejects traversal, duplicates,
symlinks and existing output. It never executes decoded content, imports candidate
modules or loads/unmarshals pstats. Original absolute paths are provenance only.
No native executable, internal review, private design note, v19 source or v19
qualification is included. This packet performs no rerun and makes no pass claim.
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
