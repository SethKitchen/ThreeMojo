"""Package the terminal, completed v21 diagnostic profile without executing it.

Preserve prior evidence, copy named ordinary inputs, and encode original binary
pstats without loading it. Never modify candidate files or upload the packet.
"""
from pathlib import Path
import base64
import gzip
import hashlib
import json

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-invariant-v21-complete-profile-packet'
E = R / 'evidence/invariant-input-complete-profile-v21'
PHASE = E.name
SOURCE_SHA = '5e999090460174e7a57f023a94dbad09d596bcae4414d9785225f428cd1527bc'
SOURCE_MANIFEST_SHA = '367ba38b8dce2a7334d10cf5eda12b178edc52eea4fbc43c1b16f4b62a952afd'
RESULT_SHA = '8850c61677e8ea412cf750b8d6e24eb4ddcf059af32760ec95181b711c42f4d7'
PROFILE_SHA = '7eb398e5b7549a421023b9a9a11e54bdf8be0f69e13c378ecb63bbafff9ea199'
PSTATS_SHA = 'ccc6a5e1426890ef2df0176cf48dad6a745c83b988527b04d6dea3ef395764c8'
PROFILER_SHA = '0ca7300861c6f2d905dcd44ad0f5b4a5213e0194bf9d2bbb27ad4d93d0095655'
PRIOR_PACKET_SHA = '6f90590d2b1e513134126d002b7383ee065ad08359ad741b172d24bb9df3d262'
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
prior_manifest = R / 'validation-evidence-owner-classifier-v21-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
need(digest(prior_manifest) == PRIOR_PACKET_SHA, 'Existing three-phase packet manifest changed')
need(digest(R / 'CANDIDATE-V21-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen v21 seal changed')
manifest_path = R / 'owner-classifier-implementation-v21/PUBLISHABLE-SOURCE-MANIFEST.json'
need(digest(manifest_path) == SOURCE_MANIFEST_SHA, 'Frozen 29-path source manifest changed')
source_manifest = read(manifest_path)
source_seal = read(R / 'CANDIDATE-V21-SOURCE-SEAL.json')
need(source_manifest['source_seal_sha256'] == SOURCE_SHA and len(source_manifest['files']) == 29,
     'Source manifest binding differs')
need(digest(E / 'RESULT.json') == RESULT_SHA and digest(E / 'RAW-PROFILE.json') == PROFILE_SHA
     and digest(E / 'profile.pstats') == PSTATS_SHA, 'Original diagnostic output changed')
result = read(E / 'RESULT.json')
config = read(R / (PHASE + '.json'))
window = read(E / 'WINDOW-START.json')
profile = read(E / 'RAW-PROFILE.json')
payload = read(R / 'invariant-profile-command-v21.json')
need(result['sequence_completed'] and result['failure'] is None
     and len(result['stages']) == len(config['stages']) == 1, 'Incomplete diagnostic sequence')
need(result['source_seal_unchanged'] and result['sdk_identity_unchanged']
     and result['remaining_owned_descendants'] == [], 'Source, SDK or cleanup differs')
need(digest(E / 'SOURCE-SEAL.json') == config['source_seal_sha256']
     == window['source_seal_sha256'] == SOURCE_SHA, 'Source receipt identity differs')
need(raw(E / 'SDK-BEFORE.json') == raw(E / 'SDK-AFTER.json'), 'SDK identity changed')
need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
     and window['whole_window_seconds'] == config['window_seconds'] == 180,
     'Supervisor or window bound changed')
stage = result['stages'][0]
configured = config['stages'][0]
label = stage['label']
need(label == configured['label'] == 'bounded-current-cost-profile', 'Stage label differs')
need(stage == read(E / (label + '-RESULT.json')), 'Stage/final receipt differs')
start = read(E / (label + '-START.json'))
need(all(stage.get(key) == value for key, value in start.items()), 'Stage START differs')
expected_command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                    .replace('{evidence}', str(E)).replace('{root}', str(R))
                    for part in configured['command']]
need(stage['argv'] == expected_command and stage['cwd'] == config['source']
     and stage['stage_timeout_seconds'] == configured['seconds'] == 60, 'Command or cap differs')
need(stage['returncode'] == 0 and not stage['timed_out'] and stage['leader_reaped']
     and stage['remaining_owned_descendants'] == []
     and stage['log_sha256'] == digest(E / (label + '.log')), 'Diagnostic receipt binding differs')
profiler_path = R / 'profile_invariant_child_v21.py'
need(digest(profiler_path) == PROFILER_SHA, 'Checked profiler source changed')
launcher = stage['argv'][-1]
need(PROFILER_SHA in launcher and str(profiler_path) in launcher
     and 'raw=p.read_bytes()' in launcher and "exec(compile(raw,str(p),'exec')" in launcher,
     'Original profiler read/hash/compile binding differs')
need(profile['status'] == 'completed' and profile['error'] is None
     and profile['work_cap_seconds'] == 58 and profile['outer_child_cap_seconds'] == 60
     and profile['elapsed_seconds'] == 32.86734985699877
     and profile['raw_code_identities_preserved_before_pstats'] and profile['optimize'] == 0,
     'Completed profile status or bounds differ')
need(len(profile['entries']) == 916 and len(profile['module_bindings']) == 317,
     'Raw identity inventory differs')
need(SHA(payload['command'].encode()) == payload['command_sha256'] == profile['command_sha256'],
     'Underlying command digest differs')
log = raw(E / (label + '.log')).decode()
need(log.startswith('Timeout (0:00:29)!\n') and 'line 21 in input_paths' in log,
     'Original scheduled 29-second traceback missing')
need(json.loads(log.splitlines()[-1]) ==
     {key: value for key, value in profile.items() if key not in ('entries', 'module_bindings')},
     'Profile metadata differs from supervised raw output')
supervisor_lines = raw(R / (PHASE + '.supervisor.log')).splitlines()
need(len(supervisor_lines) == 2 and json.loads(supervisor_lines[0]) == stage
     and json.loads(supervisor_lines[-1]) == result, 'Supervisor output differs')
core_path = str(R / 'candidate-v21/tools/carla_lane_oracle/full_audit_cleanup_contracts.py')
observed = {}
for qualname in ['verify', '_InvariantInputs.finish']:
    found = [row for row in profile['entries'] if row['code'].get('filename') == core_path
             and row['code'].get('qualname') == qualname]
    need(len(found) == 1 and found[0]['calls'] == 1, 'Expected gate/finalizer entry differs')
    observed[qualname] = {key: value for key, value in found[0].items() if key != 'callees'}
cold_path = R / 'evidence/invariant-input-cold-probes-v21/RESULT.json'
need(digest(cold_path) == '447a4753da128075f0d366b526525917849a9baa0cb07fe7d41b664ddb167212',
     'Original cold failure context changed')
cold = read(cold_path)
need(not cold['sequence_completed'] and cold['stages'][0]['returncode'] == -9
     and cold['stages'][0]['timed_out'] and cold['stages'][0]['stage_timeout_seconds'] == 10
     and cold['stages'][0]['source_seal_sha256'] == SOURCE_SHA
     and cold['stages'][0]['cwd'] == stage['cwd']
     and cold['stages'][0]['argv'][-1] == payload['command'], 'Cold/profile body-source boundary differs')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RAW-PROFILE.json', 'RESULT.json',
                  'SDK-AFTER.json', 'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json',
                  'profile.pstats', label + '-RESULT.json', label + '-START.json', label + '.log'}
need({path.name for path in E.iterdir()} == expected_files, 'Unexpected/missing phase file')
for name in sorted(expected_files):
    add(E / name, 'actual/' + name,
        'original-binary-pstats' if name == 'profile.pstats' else 'original-receipt-raw-log-or-profile',
        readable=name in {'RESULT.json', 'SDK-AFTER.json', 'SDK-BEFORE.json', 'WINDOW-START.json', label + '.log'})
for name in [PHASE + '.json', PHASE + '.supervisor.log', 'profile_invariant_child_v21.py',
             'invariant-profile-command-v21.json', 'run_checkpoint_matrix.py', 'CANDIDATE-V21-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'exact-config-command-checked-profiler-supervisor-or-seal', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-29-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v21' / row['path']
    need(digest(path) == row['sha256'] == source_seal[row['path']]
         and path.stat().st_size == row['bytes'], 'Frozen source changed: ' + row['path'])
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v21-manifest-source')
for name in ['tools/coverage_toolchain_identity.py', 'tools/cache_key.py']:
    need(digest(R / 'candidate-v21' / name) == source_seal[name], 'Referenced support source changed')
    add(R / 'candidate-v21' / name, 'reproduce/source/' + name, 'exact-bound-sdk-helper-or-stack-referenced-source')
add(cold_path, 'context/original-cold-gate/RESULT.json', 'original-failed-10-second-gate-context', readable=True)
add(R / 'invariant-input-cold-probes-v21.json', 'context/original-cold-gate/CONFIG.json',
    'original-cold-command-config-context', readable=True)
add(prior_manifest, 'context/three-phase-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json',
    'byte-exact-existing-three-phase-manifest-context', readable=True)
summary = {
    'schema': 1, 'status': 'COMPLETED_V21_PROFILE_DIAGNOSTIC_ONLY_ORIGINAL_10S_GATE_FAILED',
    'scope': 'One completed profiled diagnostic with 58-second inner and 60-second outer bounds. The original maintained 10-second cold gate remains failed. No qualification, readiness or cap-relaxation claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': SOURCE_MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 29,
    'result_sha256': RESULT_SHA, 'raw_profile_sha256': PROFILE_SHA, 'pstats_sha256': PSTATS_SHA,
    'profiler_source_sha256': PROFILER_SHA,
    'command_sha256': payload['command_sha256'],
    'diagnostic': {'status': 'completed', 'returncode': 0, 'timed_out': False,
                  'inner_work_cap_seconds': 58, 'outer_stage_cap_seconds': 60, 'whole_window_cap_seconds': 180,
                  'profile_report_elapsed_seconds': profile['elapsed_seconds'],
                  'supervised_stage_elapsed_seconds': stage['seconds'],
                  'whole_window_elapsed_seconds': result['elapsed_seconds'],
                  'raw_code_entries': len(profile['entries']), 'module_bindings': len(profile['module_bindings']),
                  'raw_code_object_identities_preserved': True,
                  'full_audit_verify_calls_observed': 1, 'operation_finish_calls_observed': 1,
                  'observed_entry_details': observed,
                  'scheduled_stack_snapshot_seconds': 29,
                  'stack_header_meaning': 'The Timeout (0:00:29) header is the scheduled faulthandler traceback; the stage was not timed out. Completion and exit 0 are preserved in the actual receipts.',
                  'raw_scope_wording': 'The original profiler template says Partial diagnostic profile. Its actual status in this run is completed; the bytes remain unchanged.',
                  'profiler_binding': 'The original launcher reads the profiler once, checks SHA-256, and compiles those same checked bytes. This packet includes that exact source.',
                  'timing_limit': 'The 32.867-second report includes profiling/instrumentation and report preparation. The supervised stage is 33.084 seconds. Neither is an original 10-second qualification pass.'},
    'original_cold_gate': {'status': 'FAILED', 'result_sha256': digest(cold_path),
                          'stage_cap_seconds': 10, 'observed_stage_seconds': cold['stages'][0]['seconds'],
                          'returncode': -9, 'timed_out': True,
                          'unrun': ['normal-package', 'optimized-direct', 'optimized-package'],
                          'same_underlying_command_and_source': True},
    'existing_three_phase_packet_manifest_sha256': PRIOR_PACKET_SHA,
    'existing_three_phase_packet': 'Preserved unchanged; only its exact manifest is copied here as context.',
    'source_sdk_unchanged': True, 'remaining_owned_descendants': [],
    'stream_capture': 'Original stdout and stderr share the merged stage log; separate streams were not recorded or invented.',
    'reproduction_boundary': 'Includes all 29 frozen manifest paths and the referenced SDK-identity/cache-key helper source, full source seal, exact profiler and command/config. Unchanged full repository and SDK executable payloads are bound by receipts but not distributed; this is not a self-contained SDK image.',
    'evidence_policy': 'All twelve original phase files, raw code identities, binary pstats, checked profiler, config/command, supervisor and source/SDK seals are byte-preserved. Binary content is losslessly base64 encoded and never loaded. No private reviews/design notes, unrelated source, rerun, candidate edit or upload.'}
commands = {'schema': 1, 'kind': 'derived-actual-command-and-receipt-binding',
            'source_seal_sha256': SOURCE_SHA, 'stage': stage,
            'config_sha256': digest(R / (PHASE + '.json')),
            'start_sha256': digest(E / (label + '-START.json')),
            'stage_result_sha256': digest(E / (label + '-RESULT.json')),
            'result_sha256': RESULT_SHA, 'profiler_source_sha256': PROFILER_SHA,
            'underlying_command': payload['command'], 'underlying_command_sha256': payload['command_sha256']}

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
             ('decode_verify.py', raw(R / 'decode_complete_profile_v21_evidence.py'), 'safe-decoder-no-execution-or-pstats-loading'),
             ('reproduce/build_complete_profile_v21_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# Complete v21 profile: diagnostic evidence only

The single authorized profile completed with exit 0 under 58-second inner and
60-second outer bounds. The profiler reports 32.867349857 seconds; the supervisor
records 33.083843828 seconds for its stage. These are different measured windows.
The original maintained 10-second cold gate remains failed. This diagnostic
completion does not change that limit or establish qualification/readiness.

All twelve original phase files are preserved, including 916 raw code entries,
317 module bindings, original object identities and binary pstats. One full-audit
verify and one operation finish invocation are observed. The original log keeps
the scheduled 29-second faulthandler stack; its Timeout header is not a stage
watchdog failure. The profiler template's Partial wording is unchanged, while
its actual status is completed. Raw timings include profiling overhead.

The original launcher read, hash-checked and compiled the same profiler bytes.
That exact source, underlying command, config, supervisor, source/SDK receipts,
29 frozen manifest source paths and referenced support files are included.
The prior three-phase packet remains unchanged; its exact manifest and selected
original cold-gate context are included without importing its entire contents.

Readable inputs retain exact bytes. Remaining originals, including pstats, are
base64-encoded per member in a JSON container, gzip-compressed with mtime=0,
then base64-encoded for transport. INNER-MEMBER-MANIFEST.json records each original
path, length, SHA-256 and storage. PUBLISHABLE-EVIDENCE-MANIFEST.json seals the
transport payloads, excluding itself. Summary and command bindings are derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies all bytes before writing and rejects unsafe paths,
duplicates, symlinks and existing output. It never executes candidate/profiler
content or loads/unmarshals pstats. Full unchanged repository and SDK executables
are not included. No candidate edit, test/native rerun or upload is performed.
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
