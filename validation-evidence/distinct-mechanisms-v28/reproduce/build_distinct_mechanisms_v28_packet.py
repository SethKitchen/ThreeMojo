"""Package actual v28 distinct-mechanism receipts; never execute candidate code.

Only original receipt/source reads, JSON/AST inspection, hashing and reversible
serialization occur. No candidate imports, test/native runs, or uploads.
"""
from pathlib import Path
import ast
import base64
import gzip
import hashlib
import json
import re

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-distinct-mechanisms-v28-packet'
PHASE = 'distinct-mechanisms-v28'
SOURCE_SHA = 'fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596'
MANIFEST_SHA = 'd3b1e05667a9d64a9b3f23bcb553ecda4ae65911c4cfac4576e90cd7dc2d5e31'
RESULT_SHA = 'ce78d86a6c5d8bb4c5821b6f93f55c86849a8e295b66e6411904d1ba43aba4c5'
PREREQUISITE_SHA = '2df82dfe2f5d5c189db62f694d3a4774760fc7a02dcdc7c7a266e489e740c28f'
POSITIVE_PACKET = 'validation-evidence-reached-bindings-v28-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
POSITIVE_PACKET_SHA = '4c2fcc460c4c5f5f90e5ad97af0b790a930752603db5cc6cb86ceaca299d227b'
TEST = 'tools/carla_lane_oracle/test_invariant_operation_inputs.py'
TEST_SHA = '7a818ca0b983e66e89ee9faa4c11fda01394517187bbaf1605ca53e3552c3cf9'
NAMES = [
    'test_distinct_pending_observation_reconciles_at_real_publication',
    'test_distinct_grouped_y_batch_reads_all_five_before_observation_refusal',
    'test_distinct_raw_cut_second_json_text_binds_original_checked_bytes',
    'test_distinct_explicit_utf8_pins_and_group_refuse_before_semantics',
    'test_distinct_borrowed_map_observations_delegate_all_five_faults',
    'test_distinct_borrowed_map_local_supplied_text_preserves_its_own_contract',
    'test_distinct_fresh_production_and_known_discoveries_refuse_four_faults',
    'test_distinct_late_map_finalizer_discards_every_real_completed_proof',
]
FOCUSED = ['BoundedOwnerDistinctMechanismControls.' + name for name in NAMES]
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
manifest_path = R / 'test-append-implementation-v28/PUBLISHABLE-SOURCE-MANIFEST.json'
prerequisite_path = R / 'distinct-negative-mechanism-prerequisites-v28.json'
need(digest(R / 'CANDIDATE-V28-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen source seal differs')
need(digest(manifest_path) == MANIFEST_SHA, 'Frozen source manifest differs')
need(digest(E / 'RESULT.json') == RESULT_SHA, 'Actual phase result differs')
need(digest(prerequisite_path) == PREREQUISITE_SHA, 'Original prerequisite audit differs')
need(digest(R / POSITIVE_PACKET) == POSITIVE_PACKET_SHA, 'Separate positive packet differs')
source_seal = read(R / 'CANDIDATE-V28-SOURCE-SEAL.json'); source_manifest = read(manifest_path)
need(source_manifest['source_seal_sha256'] == SOURCE_SHA
     and source_manifest['status'] == 'source_only_unqualified'
     and len(source_manifest['files']) == 31, 'Source inventory/status differs')
test_raw = raw(R / 'candidate-v28' / TEST)
need(SHA(test_raw) == source_seal[TEST] == TEST_SHA, 'Executed test source differs')
tree = ast.parse(test_raw)
methods = sorted(c.name + '.' + n.name for c in tree.body if isinstance(c, ast.ClassDef)
                 for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_'))
need(len(methods) == source_manifest['total_test_methods'] == 42
     and set(FOCUSED) <= set(methods), 'Frozen test-method inventory differs')
selected = next(c for c in tree.body if isinstance(c, ast.ClassDef)
                and c.name == 'BoundedOwnerDistinctMechanismControls')
need([n.name for n in selected.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_')] == NAMES,
     'Selected eight-method class differs')
prerequisite = read(prerequisite_path)
need(prerequisite['source_seal_sha256'] == SOURCE_SHA
     and prerequisite['candidate_negative_class_literal_equals_reviewed_fragment_class']
     and prerequisite['fragment_sha256'] == '7d4bca4d573f2708b71ce87a09309c83170be93211bd4d188db8887663f79a44',
     'Prerequisite source binding differs')
positive_result = read(R / 'evidence/reached-bindings-v28/RESULT.json')
need(positive_result['sequence_completed'] and positive_result['failure'] is None
     and positive_result['source_seal_unchanged'] and positive_result['sdk_identity_unchanged'],
     'Actual prerequisite phase completion differs')
for row, stage in zip(prerequisite['raw_logs'], positive_result['stages']):
    need(digest(R / row['path']) == row['sha256'] == stage['log_sha256']
         and stage['source_seal_sha256'] == SOURCE_SHA and stage['returncode'] == 0,
         'Prerequisite original log/source binding differs')
result = read(E / 'RESULT.json'); config = read(R / (PHASE + '.json')); window = read(E / 'WINDOW-START.json')
need(len(result['stages']) == len(config['stages']) == 2
     and result['sequence_completed'] and result['failure'] is None
     and result['source_seal_unchanged'] and result['sdk_identity_unchanged']
     and result['remaining_owned_descendants'] == [], 'Completion/source/SDK/cleanup differs')
need(result['scope'] == config['scope']
     and config['requires_positive_sweep'] == 'evidence/reached-bindings-v28/RESULT.json',
     'Phase scope or prerequisite config differs')
need(digest(E / 'SOURCE-SEAL.json') == config['source_seal_sha256']
     == window['source_seal_sha256'] == SOURCE_SHA, 'Phase source seal differs')
sdk = raw(E / 'SDK-BEFORE.json')
need(sdk == raw(E / 'SDK-AFTER.json')
     and SHA(sdk) == '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
     'Actual SDK receipts differ')
need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
     == '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
     and window['whole_window_seconds'] == config['window_seconds'] == 10800,
     'Supervisor or original window cap differs')
expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                  'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json'}
stage_rows = []; mode_reports = []
expected_seconds = [85.69784786600212, 88.70138096799928]
expected_logs = ['25fef90c4c4ae91af6ab75fa760e1bb784d14aee8449d996dd39990c7bdd26b5',
                 'd3abb133f63dff0ef54abbf0eac2a12c387273768b648e9725d1158c62eeb78b']
for index, (mode, stage, configured) in enumerate(zip(('normal', 'optimized'), result['stages'], config['stages'])):
    label = stage['label']; start = read(E / (label + '-START.json'))
    need(stage == read(E / (label + '-RESULT.json'))
         and all(stage.get(k) == v for k, v in start.items()), 'START/stage/final mismatch')
    need(configured['label'] == label == mode + '-distinct-mechanisms'
         and configured['command'] == ['{python}'] + (['-O'] if mode == 'optimized' else [])
         + ['-B', TEST, '-v', '-f'] + FOCUSED, 'Configured focused command differs')
    command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
               for part in configured['command']]
    need(stage['argv'] == command and stage['cwd'] == config['source'] == str(R / 'candidate-v28'),
         'Actual command/cwd differs')
    need(stage['returncode'] == 0 and not stage['timed_out'] and stage['leader_reaped']
         and stage['remaining_owned_descendants'] == [] and stage['source_seal_sha256'] == SOURCE_SHA,
         'Passing source/cleanup result differs')
    need(stage['stage_timeout_seconds'] == configured['seconds'] == 1800
         and stage['seconds'] == expected_seconds[index], 'Original cap or timing differs')
    need(stage['test_count'] == stage['expected_tests'] == configured['expected_tests'] == 8
         and stage['skipped_test_count'] == 0, 'Exact zero-skip method count differs')
    log_raw = raw(E / (label + '.log')); log = log_raw.decode('utf-8')
    need(SHA(log_raw) == stage['log_sha256'] == expected_logs[index], 'Original raw log differs')
    need(re.findall(r'^Ran (\d+) tests? in ', log, re.M) == ['8']
         and log.rstrip().endswith('\nOK') and not re.search(r'\b(FAILED|ERROR|FAIL|skipped)\b', log),
         'Raw unittest outcome differs')
    observed = re.findall(r'^test_\w+ \(__main__\.([^\n]+)\) \.\.\. ', log, re.M)
    need(observed == FOCUSED, 'Original method selection/order differs')
    need(len(re.findall(r'^test_.* \.\.\. ok$', log, re.M)) + len(re.findall(r'^ok$', log, re.M)) == 8,
         'Original successful method status count differs')
    stage_rows.append({'stage': stage, 'start_sha256': digest(E / (label + '-START.json')),
                       'stage_result_sha256': digest(E / (label + '-RESULT.json'))})
    mode_reports.append({'mode': mode, 'method_executions': 8, 'skips': 0,
                         'source_defined_owner_subcases': 18, 'elapsed_seconds': stage['seconds'],
                         'returncode': 0, 'timed_out': False, 'log_bytes': len(log_raw),
                         'log_sha256': SHA(log_raw), 'method_names': observed})
    expected_files |= {label + suffix for suffix in ('-START.json', '-RESULT.json', '.log')}
console = [json.loads(line) for line in raw(R / (PHASE + '.supervisor.log')).splitlines()]
need(len(console) == 3 and console[-1] == result, 'Original final supervisor console differs')
for emitted, stage in zip(console[:-1], result['stages']):
    need(emitted == {k: v for k, v in stage.items()
                     if k not in ('test_count', 'expected_tests', 'skipped_test_count')},
         'Console differs beyond later-added method count annotations')
processes = [json.loads(line) for line in raw(E / 'PROCESSES.jsonl').splitlines()]
need(processes and read(E / 'LATEST.json') == processes[-1], 'Original process LATEST differs')
stages = {s['label']: s for s in result['stages']}
need(all(all(p['pgid'] == stages[row['label']]['pgid'] for p in row['owned']) for row in processes),
     'Original process group differs')
need({p.name for p in E.iterdir()} == expected_files and len(expected_files) == 13,
     'Original phase file inventory differs')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


for name in sorted(expected_files):
    add(E / name, 'actual/' + PHASE + '/' + name, 'original-passing-phase-receipt-or-merged-log',
        readable=name in {'RESULT.json', 'SDK-AFTER.json', 'SDK-BEFORE.json', 'WINDOW-START.json'}
                 or name.endswith('.log'))
for name in [PHASE + '.json', PHASE + '.supervisor.log', 'run_checkpoint_matrix.py', 'CANDIDATE-V28-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-config-console-supervisor-or-source-seal', readable=True)
add(prerequisite_path, 'actual/distinct-negative-mechanism-prerequisites-v28.json',
    'original-saved-actual-positive-prerequisite-audit', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-31-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v28' / row['path']; data = raw(path)
    need(SHA(data) == row['sha256'] == source_seal[row['path']] and len(data) == row['bytes'],
         'Frozen source differs: ' + row['path'])
    need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == row['git_blob'],
         'Source Git blob differs')
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v28-source',
        readable=row['path'] in {TEST, 'docs/validation/full-audit-721-qualification-policy.md'})
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v28' / support) == source_seal[support], 'SDK identity support source differs')
add(R / 'candidate-v28' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')
summary = {
    'schema': 1, 'status': 'PASSED_V28_DISTINCT_MECHANISMS_EIGHT_METHODS_ONLY',
    'scope': 'Eight selected distinct-mechanism methods passed in normal and optimized modes: sixteen method executions, zero skips, eighteen source-defined fresh-owner subcases per mode. No complete 42-method suite, full Python matrix, native coverage, hosted CI or overall completion claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 31, 'executed_test_path': TEST, 'executed_test_sha256': TEST_SHA,
    'source_test_methods': len(methods), 'selected_method_names': FOCUSED,
    'other_34_methods_selected': False, 'method_executions': 16, 'unique_executed_methods': 8,
    'source_defined_owner_subcases_per_mode': 18,
    'source_defined_subcase_counts_by_method': dict(zip(FOCUSED, [1, 1, 1, 2, 5, 3, 4, 1])),
    'subcase_boundary': 'The original logs persist eight unittest method outcomes per mode. The eighteen owner subcases are defined by the preserved source and enforced within passing methods; no independent per-subcase runtime receipts are invented.',
    'skips': 0, 'all_stages_returncode_zero': True, 'any_stage_timed_out': False,
    'stage_cap_seconds': 1800, 'whole_window_cap_seconds': 10800,
    'window_elapsed_seconds': result['elapsed_seconds'], 'modes': mode_reports,
    'source_sdk_unchanged': True, 'remaining_owned_descendants': [], 'sdk_receipt_sha256': SHA(sdk),
    'prerequisite_audit_sha256': PREREQUISITE_SHA,
    'separate_positive_evidence_reference': {'packet_path': POSITIVE_PACKET,
        'packet_manifest_sha256': POSITIVE_PACKET_SHA, 'raw_members_included_here': False,
        'limit': 'The exact same-source positive sweep and full raw positive logs remain in their separate packet. The original saved prerequisite audit is included unchanged here. Positive outcomes are not relabeled as negative-test receipts.'},
    'late_finalizer_boundary': 'The prerequisite receipt did not enumerate Map proof IDs. The preserved late-finalizer negative asserts all genuine guarded Map proof IDs plus the construction proof before its mutation; that method passed both modes. No separate proof-ID runtime report is fabricated.',
    'source_manifest_time_boundary': 'The reviewed source_only_unqualified 31-path manifest is preserved byte-exact, including its earlier focused positive method label. COMMAND-RECEIPT-SEAL.json and original config/logs identify the later eight-method execution in this packet.',
    'console_binding_limit': 'Original supervisor console stage records precede later test_count/expected_tests/skipped_test_count annotations; final JSON includes them. No console output is reconstructed.',
    'stream_capture': 'Both full original merged stdout/stderr logs are preserved byte-exact, including warnings. Separate streams are not invented.',
    'reproduction_boundary': 'Includes all thirteen phase files, actual config/console/supervisor, full source/SDK seals, all31 frozen manifest source paths and SDK identity support. The full unchanged repository and SDK executable image are not distributed.',
    'qualification_limit': 'The other34 methods were not selected in this phase. This does not establish a full Python matrix, native coverage, hosted CI or overall completion.',
    'evidence_policy': 'Ordinary original receipts/logs/config, saved source-evidence prerequisite audit and exact source bytes only. No private review/design notes, unexecuted proposals, candidate edits, reruns, native execution or uploads.'
}
commands = {'schema': 1, 'kind': 'derived-actual-command-and-receipt-binding',
            'phase': PHASE, 'source_seal_sha256': SOURCE_SHA,
            'config_sha256': digest(R / (PHASE + '.json')), 'result_sha256': RESULT_SHA,
            'stages': stage_rows, 'supervisor_console_sha256': digest(R / (PHASE + '.supervisor.log')),
            'prerequisite_audit_sha256': PREREQUISITE_SHA, 'configured_but_unrun_stage_labels': []}
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
payloads += [(archive_name, encoded, 'lossless-original-passing-receipts-full-raw-logs-and-source-bytes'),
             ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-path-byte-hash-and-storage-inventory'),
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-passing-eight-method-distinct-mechanism-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(decoder), 'safe-decoder-no-content-execution'),
             ('reproduce/build_distinct_mechanisms_v28_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = """# V28 distinct-mechanism evidence

Eight selected methods passed in each mode: sixteen executions, zero skips.
The preserved source defines eighteen fresh-owner subcases per mode. Original
logs record method outcomes; no separate subcase receipts are reconstructed.
Stage times were 85.697847866 and 88.701380968 seconds. Original 1,800-second
stage and 10,800-second window caps remain unchanged. Source/SDK identities
were unchanged and no owned descendants remained.

All thirteen original phase files, actual console/config/supervisor, the saved
prerequisite audit, the reviewed31-path source union and SDK identity helper
are preserved. The positive sweep remains a separately hash-bound packet.
Its prerequisite audit is preserved unchanged, including the proof-ID limit.
The late-finalizer negative asserts complete genuine Map proof IDs before its
fault; it passed both modes. No separate proof-ID report is invented.

The original source-only manifest is retained unchanged. Its earlier focused
positive label does not describe this phase; actual config/logs and
COMMAND-RECEIPT-SEAL.json identify these eight methods. The other34 methods,
full Python matrix, native coverage, hosted CI and overall completion remain
outside this packet's claim.

PUBLISHABLE-EVIDENCE-MANIFEST.json binds each transport payload.
INNER-MEMBER-MANIFEST.json binds each original member by path, byte count,
SHA-256 and storage. Original raw logs and key receipts are directly readable;
remaining originals are stored losslessly in the deterministic gzip/base64
container. decode_verify.py validates the inventory and safely extracts into
a new directory. It refuses path traversal, symlinks and existing outputs and
never executes decoded content. Full repository/SDK images are not distributed.
No private notes, candidate changes, tests/native reruns or uploads occurred.
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
