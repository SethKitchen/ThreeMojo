"""Package v22 helper controls, cold failure and plain diagnostic receipts.

Only named ordinary evidence is copied. No candidate code, harness, test or
native content is executed. Existing sources/receipts are never edited or uploaded.
"""
from pathlib import Path
import base64
import gzip
import hashlib
import json

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-lexical-relative-v22-packet'
SOURCE_SHA = '9fcd79a43418f8c8db99b559da8a0d9dfb32154b4ec9d5758d4d3bf73b51fcb3'
SOURCE_MANIFEST_SHA = 'e5e35b83cdc8bf25f137ca6feb74450fbc25e6fd4f27d633a2a36ae7da3d1588'
PATHLIB_SHA = '10ba48ae8063cfe7589436041d0d4628c05f427c7709cf8e75e486f8930cc32c'
HELPER_AST_SHA = 'd02f09663ba33ad79ce4f5025c317f6c7bfad2e0529286b7a31430994754835f'
PATHLIB_SOURCE = R.parent / 'restored-toolchain/python/cpython-3.12.14-linux-x86_64-gnu/lib/python3.12/pathlib.py'
PROPOSAL_CORE_SHA = '9b3848e41376ca31b7399998187b30f1c05519ba263961e16380a780b92f4643'
HARNESS_SHA = '97eab00022b10243848eac30f556b67b8f21b6e5d2f02ffc5e65e85d1fe037b4'
CORE = 'tools/carla_lane_oracle/full_audit_cleanup_contracts.py'
PHASES = ['lexical-relative-focused-controls-v22', 'invariant-input-cold-probes-v22',
          'invariant-input-plain-diagnostic-v22']
RESULT_SHAS = ['4621782f9ea97222ca237ff6f250b7595e607eaa71f37ee2c744100a9fb76ce6',
               'f4f6808ea03a62c31cd1b89cfdf0cc5ebd4d3102e158e9ddb5be5abbf04c421d',
               'd176df112b5f315313c9a3cc057e907684f3f06b03f9b8add5779f41dd4a0bdf']
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
need(digest(R / 'CANDIDATE-V22-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen v22 seal changed')
manifest_path = R / 'lexical-relative-implementation-v22/PUBLISHABLE-SOURCE-MANIFEST.json'
harness_path = R / 'lexical-relative-implementation-v22/relative_path_equivalence_controls.py'
need(digest(manifest_path) == SOURCE_MANIFEST_SHA, '29-path source manifest changed')
need(digest(harness_path) == HARNESS_SHA, 'Checked harness bytes changed')
source_manifest = read(manifest_path)
source_seal = read(R / 'CANDIDATE-V22-SOURCE-SEAL.json')
need(source_manifest['source_seal_sha256'] == SOURCE_SHA and len(source_manifest['files']) == 29,
     'Source manifest binding changed')
need(digest(R / 'candidate-v22' / CORE) == source_seal[CORE] == PROPOSAL_CORE_SHA,
     'Proposal core binding changed')
need(digest(PATHLIB_SOURCE) == PATHLIB_SHA, 'Exact pathlib reference source changed')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


results = []
configs = []
command_rows = []
supervisor_console_logs = {}
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
    console_path = R / (phase + '.supervisor.log')
    supervisor_console_logs[phase] = console_path.is_file()
    if console_path.is_file():
        supervisor_lines = raw(console_path).splitlines()
        need(len(supervisor_lines) == len(result['stages']) + 1
             and [json.loads(line) for line in supervisor_lines[:-1]] == result['stages']
             and json.loads(supervisor_lines[-1]) == result, 'Supervisor output differs')
    need({p.name for p in evidence.iterdir()} == expected_files, 'Unexpected/missing phase file')
    for name in sorted(expected_files):
        add(evidence / name, 'actual/' + phase + '/' + name, 'original-receipt-log-or-controls-report',
            readable=name in readable_names)
    for suffix in ['.json'] + (['.supervisor.log'] if console_path.is_file() else []):
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
     'Focused helper outcome differs')
need(not configs[0].get('additional_sources'), 'Unexpected additional-source execution context')
controls = {}
for mode, optimize, expected_sha, stage in zip(['normal', 'optimized'], [0, 1],
        ['41e14bff87f943d11df07666f0711503880429c16f803b3055e8578dc0ee45f6',
         '4613fe6342bbf740c1af408b708fbc151fdc994dac849185940c35e08df4e080'], focused['stages']):
    path = R / 'evidence' / PHASES[0] / (mode + '-CONTROLS.json')
    need(digest(path) == expected_sha, 'Original helper control report changed')
    report = read(path)
    need(report['status'] == 'PASS' and report['qualification'] is False and report['optimize'] == optimize
         and report['always_active_checks'] == 1563 and report['cases'] == len(report['records']) == 110
         and report['branch_counts'] == {'fast': 63, 'fallback': 47}
         and report['filesystem_audit_events'] == [], 'Helper control counts or status differ')
    need(report['source_sha256'] == PROPOSAL_CORE_SHA and report['harness_sha256'] == HARNESS_SHA
         and report['pathlib_sha256'] == PATHLIB_SHA and report['helper_ast_sha256'] == HELPER_AST_SHA,
         'Report source/reference binding differs')
    need(sum(row['branch'] == 'fast' for row in report['records']) == 63
         and sum(row['branch'] == 'fallback' for row in report['records']) == 47,
         'Actual fast/fallback record inventory differs')
    command = stage['argv'][-1]
    need(HARNESS_SHA in command and str(harness_path) in command
         and 'raw=p.read_bytes()' in command and "exec(compile(raw,str(p),'exec')" in command,
         'Harness read/hash/compile command binding differs')
    printed = json.loads(raw(R / 'evidence' / PHASES[0] / (stage['label'] + '.log')))
    need(printed == {key: value for key, value in report.items() if key != 'records'},
         'Control report differs from supervised output')
    controls[mode] = report
need(controls['normal']['records'] == controls['optimized']['records'],
     'Normal/optimized helper records differ')
need(not cold['sequence_completed'] and cold['failure'] is not None
     and cold['stages'][0]['returncode'] == -9 and cold['stages'][0]['timed_out']
     and cold['stages'][0]['seconds'] == 10.060284039005637, 'Cold failure differs')
need(plain['sequence_completed'] and plain['failure'] is None
     and plain['stages'][0]['returncode'] == 0 and not plain['stages'][0]['timed_out']
     and plain['stages'][0]['seconds'] == 10.523972423994564, 'Plain diagnostic outcome differs')
need(cold['stages'][0]['argv'] == plain['stages'][0]['argv']
     and cold['stages'][0]['cwd'] == plain['stages'][0]['cwd']
     and plain['stages'][0]['argv'][1] == '-c'
     and 10 < plain['stages'][0]['seconds'] < 30, 'Plain diagnostic body/source/cap boundary differs')

for name in ['run_checkpoint_matrix.py', 'CANDIDATE-V22-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-supervisor-or-source-seal', readable=True)
add(harness_path, 'reproduce/relative_path_equivalence_controls.py', 'exact-command-hash-checked-executed-harness', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-29-path-frozen-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v22' / row['path']
    need(digest(path) == row['sha256'] == source_seal[row['path']]
         and path.stat().st_size == row['bytes'], 'Frozen source changed: ' + row['path'])
    add(path, 'reproduce/source/v22/' + row['path'], 'exact-frozen-v22-manifest-source')
add(PATHLIB_SOURCE, 'reproduce/reference/pathlib.py', 'exact-report-bound-standard-library-reference-source')
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v22' / support) == source_seal[support], 'SDK identity helper changed')
add(R / 'candidate-v22' / support, 'reproduce/source/support/' + support, 'exact-supervisor-sdk-identity-source')

summary = {
    'schema': 1, 'status': 'V22_HELPER_CONTROLS_PASS_COLD_GATE_FAIL_PLAIN_DIAGNOSTIC_COMPLETES',
    'scope': 'Helper-only lexical differential controls pass. Original maintained 10-second real cold gate fails. Separate same-body/source 30-second plain diagnostic completes above ten seconds. No original-cap, operation-level, readiness or broader qualification claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': SOURCE_MANIFEST_SHA,
    'exact_frozen_v22_source_paths': 29, 'proposal_core_sha256': PROPOSAL_CORE_SHA,
    'checked_harness_sha256': HARNESS_SHA, 'helper_ast_sha256': HELPER_AST_SHA,
    'pathlib_reference_sha256': PATHLIB_SHA,
    'focused_helper_controls': {'status': 'PASS_HELPER_ONLY', 'result_sha256': RESULT_SHAS[0],
        'modes': {mode: {'optimize': report['optimize'], 'cases': report['cases'],
                        'always_active_checks': report['always_active_checks'],
                        'branch_counts': report['branch_counts'],
                        'filesystem_audit_events': report['filesystem_audit_events'],
                        'report_sha256': digest(R / 'evidence' / PHASES[0] / (mode + '-CONTROLS.json'))}
                  for mode, report in controls.items()},
        'stage_cap_seconds': 30, 'window_cap_seconds': 180,
        'harness_binding': 'Each original command reads the external harness once, checks its exact SHA-256, and compiles those same bytes. Reports also bind exact helper AST, candidate core and pathlib reference source.',
        'scope_limit': 'Focused helper-only differential fixtures with fresh inputs/callbacks and recorded fast/fallback traces. They do not establish real operation-level source admission, maintained cold-watchdog success or broader qualification.'},
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
        'limit': 'The same exact normal-direct body and frozen source complete at 10.523972424 seconds with exit 0 under a separately authorized 30-second diagnostic cap. This remains above the original ten-second limit and does not replace or pass the failed qualification gate.'},
    'all_phase_source_sdk_unchanged': True, 'all_phase_remaining_owned_descendants': [],
    'stream_capture': 'Original stage logs merge stdout and stderr. Empty cold and plain output is preserved; separate streams were not recorded or invented.',
    'aggregate_supervisor_console_logs_available': supervisor_console_logs,
    'aggregate_console_limit': 'No aggregate supervisor console file is fabricated. All persisted stage START/RESULT/log files, final RESULT, process receipts and WINDOW-bound supervisor source remain preserved. Availability of separately persisted aggregate console output is listed per phase.',
    'source_manifest_time_boundary': 'The original source-only/unqualified manifest remains unchanged. Later receipts retain their distinct helper-control, cold-failure and plain-diagnostic outcomes.',
    'reproduction_boundary': 'All 29 frozen candidate manifest paths, executed harness and supervisor, SDK identity support source and exact pathlib reference source are included. The entire unchanged repository and SDK binaries are not distributed.',
    'evidence_policy': 'Every file in the three terminal phase directories and exact configs, commands, supervisor source, source/SDK seals, checked harness and bound source bytes is preserved. Any available aggregate supervisor console file is preserved without reconstruction. Derived summaries are separate. No private reviews/design notes, secrets, unrelated source, executable binaries, candidate edits, reruns or uploads.'}
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
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-helper-controls-cold-failure-and-plain-diagnostic-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(R / 'decode_lexical_relative_v22_evidence.py'), 'safe-decoder-no-content-execution'),
             ('reproduce/build_lexical_relative_v22_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# V22 lexical helper controls, cold failure and plain diagnostic

Normal and optimized helper-only controls each passed 110 cases and 1,563
always-active checks, with 63 fast and 47 fallback traces and no recorded
filesystem audit events. Exact candidate core, helper AST, pathlib reference
and executed harness identities are retained. These focused helper fixtures
do not establish operation-level or maintained cold-watchdog qualification.

The original maintained ten-second normal-direct cold gate failed at
10.060284039 seconds with exit -9. Normal package and both optimized cold
commands were not run. The separately authorized plain diagnostic used the
same exact argv, command body, working directory and frozen source, without
profiling, and completed at 10.523972424 seconds with exit 0 under 30 seconds.
It remains above the original ten-second bound; no qualification pass or
readiness conclusion is claimed.

Every file in all three terminal evidence directories is preserved, including
START/RESULT/logs, empty output, process receipts, complete helper reports and
source/before-after SDK seals. Exact configs and supervisor source, checked harness,
29 frozen candidate source paths, SDK identity helper and hash-bound pathlib
reference source are included. Private reviews and design notes are omitted.
The summary records whether aggregate supervisor console files were separately
available. Missing aggregate output is not reconstructed; all persisted stage
and final receipts remain intact.

Readable files retain exact bytes. Other original members are base64-encoded
in one JSON container, gzip-compressed with mtime=0 and base64-encoded for
transport. INNER-MEMBER-MANIFEST.json lists every original path, byte length,
SHA-256 and storage. PUBLISHABLE-EVIDENCE-MANIFEST.json seals transport payloads,
excluding itself. Summary and command binding documents are explicitly derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing and rejects traversal, duplicates,
symlinks and existing output. It never executes candidate/harness/reference
content. Full unchanged repository and SDK binaries are not distributed.
No candidate edits, tests/native reruns or uploads are performed by packaging.
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
