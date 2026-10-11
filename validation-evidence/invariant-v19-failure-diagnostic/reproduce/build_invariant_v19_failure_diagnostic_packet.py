"""Package frozen v19 failures and censored diagnostic evidence, without execution.

Only named ordinary receipts, configs and source inputs are included. Existing
receipts and candidate roots are never modified. No external upload is performed.
"""
from pathlib import Path
import base64
import gzip
import hashlib
import json

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-invariant-v19-failure-diagnostic-packet'
SOURCE_SHA = '8985c71b586bf5a8b8e7b7ddc21ad9c61be72f416da9b5d06d8e5c5901c2ae4e'
SOURCE_MANIFEST_SHA = '33b6b19f3e3185fe2a792b61c998d8859a2d5c7497525e7130c2b76908fda0ad'
PHASES = ['invariant-input-cold-probes-v19', 'invariant-input-diagnostic-v19']
RESULT_SHAS = ['bf4d3be4a9ca045bfe7cdfb0c9c2146c91be6ab90eef94eee91e25231b9e1c77',
               '264fbb282f7e7f6024fc2b1d8bf4759e585f78edf74e9a1c8bf76bc33dc986c7']
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
need(digest(R / 'CANDIDATE-V19-SOURCE-SEAL.json') == SOURCE_SHA, 'V19 source seal changed')
manifest_path = R / 'bounded-operation-implementation-v19/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(manifest_path) == SOURCE_MANIFEST_SHA, '29-path source manifest changed')
source_manifest = read(manifest_path)
source_seal = read(R / 'CANDIDATE-V19-SOURCE-SEAL.json')
need(source_manifest['source_seal_sha256'] == SOURCE_SHA
     and len(source_manifest['files']) == 29, 'Source manifest differs')
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
    expected_files |= {'RAW-PROFILE.json', 'profile.pstats', 'RAW-CALL-EDGE-ANALYSIS.txt'} if phase == PHASES[1] else {'FAILURE.json'}
    need({p.name for p in evidence.iterdir()} == expected_files, 'Unexpected or missing phase file')
    for name in sorted(expected_files):
        add(evidence / name, 'actual/' + phase + '/' + name,
            'original-binary-pstats' if name == 'profile.pstats' else 'existing-derived-call-edge-analysis' if name == 'RAW-CALL-EDGE-ANALYSIS.txt' else 'original-raw-receipt-or-profile',
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

cold, diagnostic = results
need(not cold['sequence_completed'] and cold['failure'] is not None
     and cold['stages'][0]['returncode'] == -9 and cold['stages'][0]['timed_out']
     and cold['stages'][0]['stage_timeout_seconds'] == 10
     and cold['stages'][0]['seconds'] == 10.045146466000006
     and len(configs[0]['stages']) == 4, 'Cold failure classification differs')
need(diagnostic['sequence_completed'] and diagnostic['failure'] is None
     and diagnostic['stages'][0]['returncode'] == 1 and not diagnostic['stages'][0]['timed_out']
     and configs[1]['stages'][0]['accept_nonzero'] is True
     and diagnostic['stages'][0]['stage_timeout_seconds'] == 30, 'Diagnostic classification differs')
profile_path = R / 'evidence' / PHASES[1] / 'RAW-PROFILE.json'
need(digest(profile_path) == '1b3c4ea4f0b63fe9d874e4c30526a69449e74fd9d7cad22c8ff080b8915df606',
     'Original raw profile changed')
profile = read(profile_path)
payload = read(R / 'invariant-profile-command-v19.json')
need(payload['command'] == cold['stages'][0]['argv'][-1]
     and SHA(payload['command'].encode()) == payload['command_sha256'] == profile['command_sha256'],
     'Profile command differs from cold command')
need(profile['status'] == 'diagnostic deadline' and profile['work_cap_seconds'] == 28
     and profile['outer_child_cap_seconds'] == 30
     and profile['raw_code_identities_preserved_before_pstats'], 'Profile was not the declared censored diagnostic')
gate_path = str(R / 'candidate-v19/tools/carla_lane_oracle/full_audit_cleanup_contracts.py')
gate_entries = [row for row in profile['entries'] if row['code'].get('filename') == gate_path
                and row['code'].get('qualname') == 'verify']
finish_entries = [row for row in profile['entries'] if row['code'].get('filename') == gate_path
                  and row['code'].get('qualname') == '_InvariantInputs.finish']
need(len(gate_entries) == 1 and gate_entries[0]['calls'] == 1 and not finish_entries,
     'Censored gate/finalizer observations differ')
diagnostic_log = raw(R / 'evidence' / PHASES[1] / 'bounded-complete-cost-profile.log').decode()
need(diagnostic_log.startswith('Timeout (0:00:14)!\n')
     and 'line 731 in _regular' in diagnostic_log and 'line 491 in verify_score_caller_inventory' in diagnostic_log, 'Fourteen-second stack snapshot missing')
need(json.loads(diagnostic_log.splitlines()[-1]) ==
     {key: value for key, value in profile.items() if key not in ('entries', 'module_bindings')},
     'Raw profile metadata differs from original supervised output')
need(len(profile['entries']) == 889 and len(profile['module_bindings']) == 309,
     'Raw code identity inventory changed')

for name in ['run_checkpoint_matrix.py', 'profile_invariant_child_v19.py',
             'invariant-profile-command-v19.json', 'CANDIDATE-V19-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-harness-profile-payload-or-source-seal', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-29-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v19' / row['path']
    need(digest(path) == row['sha256'] == source_seal[row['path']]
         and path.stat().st_size == row['bytes'], 'Frozen source changed: ' + row['path'])
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v19-manifest-source')
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v19' / support) == source_seal[support], 'SDK identity support changed')
add(R / 'candidate-v19' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')

summary = {
    'schema': 1, 'status': 'FAILED_V19_REAL_COLD_GATE_WITH_CENSORED_DIAGNOSTIC',
    'scope': 'Ordinary frozen-v19 cold failure and one censored diagnostic only. No admission pass, timing-cap success, readiness or broader qualification claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': SOURCE_MANIFEST_SHA,
    'exact_frozen_source_paths': 29,
    'cold_probe': {'status': 'FAILED_ORIGINAL_10_SECOND_BOUND', 'result_sha256': RESULT_SHAS[0],
                   'executed': 'normal-direct', 'returncode': -9, 'timed_out': True,
                   'cap_seconds': 10, 'observed_stage_seconds': cold['stages'][0]['seconds'],
                   'unrun': ['normal-package', 'optimized-direct', 'optimized-package']},
    'diagnostic': {'status': 'CENSORED_PARTIAL_PROFILE_NOT_A_PASS', 'result_sha256': RESULT_SHAS[1],
                   'work_cap_seconds': 28, 'outer_stage_cap_seconds': 30,
                   'profile_elapsed_seconds': profile['elapsed_seconds'],
                   'supervised_stage_seconds': diagnostic['stages'][0]['seconds'],
                   'returncode': 1, 'timed_out_by_outer_supervisor': False,
                   'sequence_completed_meaning': 'The diagnostic collection configuration accepted nonzero exit 1. Completion of the collection sequence does not mean invariant.verify completed or passed.',
                   'qualification_cap_unchanged': 'The separately authorized 28-second diagnostic work window and 30-second outer collection cap do not relax the original 10-second qualification bound.',
                   'raw_profile_sha256': digest(profile_path),
                   'pstats_sha256': digest(R / 'evidence' / PHASES[1] / 'profile.pstats'),
                   'raw_code_entries': len(profile['entries']), 'module_bindings': len(profile['module_bindings']),
                   'raw_code_object_ids_preserved': True, 'pstats_loaded_by_packager': False,
                   'fourteen_second_stack': 'The original merged diagnostic log retains the 14-second faulthandler stack through _regular, _match, _observe, operation observation and seed_count.verify_score_caller_inventory.',
                   'observed_full_audit_verify_invocations': 1,
                   'operation_finish_entries_observed': 0,
                   'censoring_limit': 'One full-audit verify invocation is observed in this interrupted profile. No operation finish entry is observed before censoring; the complete invariant operation is not established. Profile timings include instrumentation and do not establish unprofiled performance.',
                   'profile_label_limit': 'The original stage label bounded-complete-cost-profile is retained exactly. Despite that prospective label, the profile was censored and does not provide complete end-to-end cost.',
                   'existing_analysis_file': 'RAW-CALL-EDGE-ANALYSIS.txt is preserved byte-for-byte as existing derived numeric call-edge analysis, not relabeled as a supervisor-generated execution receipt.',
                   'profiler_binding_limit': 'The original stage identifies the profiler path but does not separately hash its source. This packet records the present source bytes and digest; WINDOW-START independently binds the supervisor hash.'},
    'all_phase_source_sdk_unchanged': True, 'all_phase_remaining_owned_descendants': [],
    'window_cap_seconds_per_phase': 300,
    'stream_capture': 'Original stage .log files merge stdout and stderr. Separate streams were not recorded or reconstructed.',
    'source_manifest_time_boundary': 'The original 29-path manifest retains source-only/unqualified status. The later original receipts here preserve the failure and censored diagnostic.',
    'other_scope': 'The 29 source paths include test files as frozen source evidence; no new test execution is performed or claimed by this packet. Other commands, controls and broader qualification remain outside this evidence.',
    'evidence_policy': 'Every file in both original phase directories is preserved byte-for-byte, including nonzero results, empty output, binary pstats, raw profile and the existing derived call-edge report. No internal reviews/design notes, secrets, executable binaries, broad unrelated source, candidate edits, reruns, native execution or external upload.',
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
             ('decode_verify.py', raw(R / 'decode_invariant_v19_evidence.py'), 'safe-decoder-no-execution-or-pstats-loading'),
             ('reproduce/build_invariant_v19_failure_diagnostic_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# Frozen-v19 cold failure and censored diagnostic evidence

The exact maintained normal-direct admission command failed its original
10-second bound (10.045146466 seconds, exit -9). Normal package and both optimized
cold commands were not run. The single separately authorized diagnostic was
censored after 28 seconds under a 30-second outer collection limit and returned
1. Its collection sequence accepted that nonzero result; it is not an admission,
timing-cap or readiness pass. The original 10-second qualification limit remains.

The diagnostic contains 889 raw code entries and 309 module bindings. Raw object
identities, binary pstats and the 14-second faulthandler stack are preserved.
One full-audit verify invocation and no operation finish entry are observed in
the censored profile. End-to-end completion, full finalizer behavior and complete
operation cost are not established. The prospective stage label is retained
unchanged and does not override the actual diagnostic-deadline result.

Every original file in both phase directories is preserved, including the
existing numeric RAW-CALL-EDGE-ANALYSIS.txt, explicitly identified as derived
analysis. Actual commands/configs, supervisor output, profiler source/payload,
all 29 frozen source-manifest paths, full source seal and SDK receipts are kept.
The profiler path is historically recorded; this packet seals its present source
bytes rather than inventing a historical source-content hash. The supervisor is
independently bound by the original WINDOW-START hash.

Readable receipt/config files retain exact bytes. Remaining original members,
including pstats and RAW-PROFILE.json, are encoded as per-member base64 in one
JSON container, gzip-compressed with mtime=0 and base64-encoded for transport.
INNER-MEMBER-MANIFEST.json records each original path, byte length, SHA-256 and
storage. PUBLISHABLE-EVIDENCE-MANIFEST.json seals transport payloads and does not
recursively list itself. Derived summary and command bindings are separate.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects traversal, duplicate
members, symlink payloads and existing output. It never executes decoded content,
imports candidate modules, or loads/unmarshals pstats. Original absolute paths
are provenance only. No candidate modification, rerun, upload or new test/native
execution occurs. This is a durable failure/diagnostic record, with no acceptance
or readiness claim.
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
