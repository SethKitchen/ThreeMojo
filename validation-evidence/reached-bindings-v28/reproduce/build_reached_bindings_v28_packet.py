"""Preserve the actual passing v28 reached-binding sweep without running source.

Only original receipt/source reads, JSON/AST inspection, hashing and reversible
serialization occur. No candidate import, tests, native execution or upload.
"""
from pathlib import Path
import ast
import base64
import collections
import gzip
import hashlib
import json
import re

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-reached-bindings-v28-packet'
PHASE = 'reached-bindings-v28'
SOURCE_SHA = 'fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596'
MANIFEST_SHA = 'd3b1e05667a9d64a9b3f23bcb553ecda4ae65911c4cfac4576e90cd7dc2d5e31'
RESULT_SHA = '58f79b3c379bd910e33ee2234305dad8d599c90e83f0b6507ce5f08fca8c327e'
TEST = 'tools/carla_lane_oracle/test_invariant_operation_inputs.py'
TEST_SHA = '7a818ca0b983e66e89ee9faa4c11fda01394517187bbaf1605ca53e3552c3cf9'
METHOD = 'OperationReachedBindingControls.test_current_cold_routes_preserve_consumed_value_bindings'
ROUTES = ['invariant', 'winner', 'map_loops', 'rtree_loops']
PRIOR_PACKET = 'validation-evidence-reached-bindings-v27-failure-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
PRIOR_SHA = '25c036993ebe62d4350146d8cfbe76a2b55ee42ac7b0c6705be060aa31f2a0f0'
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
need(digest(R / 'CANDIDATE-V28-SOURCE-SEAL.json') == SOURCE_SHA, 'Frozen source seal changed')
need(digest(manifest_path) == MANIFEST_SHA, 'Frozen source manifest changed')
need(digest(E / 'RESULT.json') == RESULT_SHA, 'Actual result changed')
source_seal = read(R / 'CANDIDATE-V28-SOURCE-SEAL.json'); source_manifest = read(manifest_path)
need(source_manifest['source_seal_sha256'] == SOURCE_SHA
     and source_manifest['status'] == 'source_only_unqualified'
     and len(source_manifest['files']) == 31
     and source_manifest['focused_methods'] == [METHOD], 'Frozen source manifest differs')
test_raw = raw(R / 'candidate-v28' / TEST)
need(SHA(test_raw) == source_seal[TEST] == TEST_SHA, 'Executed test source differs')
tree = ast.parse(test_raw)
methods = sorted(c.name + '.' + n.name for c in tree.body if isinstance(c, ast.ClassDef)
                 for n in c.body if isinstance(n, ast.FunctionDef) and n.name.startswith('test_'))
need(len(methods) == source_manifest['total_test_methods'] == 42 and METHOD in methods,
     'Frozen source method inventory differs')
prior_seal = read(R / 'CANDIDATE-V27-SOURCE-SEAL.json')
need(digest(R / 'CANDIDATE-V27-SOURCE-SEAL.json') == 'a36731dcc18ee0757482f613ad6d3b5ef96f0b67c0dd96a80d95105ed46ce8e5'
     and {p for p in source_seal.keys() | prior_seal.keys() if source_seal.get(p) != prior_seal.get(p)} == {TEST},
     'Sealed source delta differs')
need(digest(R / PRIOR_PACKET) == PRIOR_SHA, 'Earlier v27 failure packet changed')
result = read(E / 'RESULT.json'); config = read(R / (PHASE + '.json')); window = read(E / 'WINDOW-START.json')
need(len(result['stages']) == len(config['stages']) == 2
     and result['sequence_completed'] and result['failure'] is None
     and result['source_seal_unchanged'] and result['sdk_identity_unchanged']
     and result['remaining_owned_descendants'] == [], 'Completion/source/SDK/cleanup differs')
need(result['scope'] == config['scope'], 'Phase scope differs')
need(digest(E / 'SOURCE-SEAL.json') == config['source_seal_sha256']
     == window['source_seal_sha256'] == SOURCE_SHA, 'Phase source binding differs')
sdk = raw(E / 'SDK-BEFORE.json')
need(sdk == raw(E / 'SDK-AFTER.json')
     and SHA(sdk) == '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
     'SDK identities differ')
need(window['supervisor_sha256'] == digest(R / 'run_checkpoint_matrix.py')
     == '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
     and window['whole_window_seconds'] == config['window_seconds'] == 10800,
     'Supervisor/window binding differs')
expected_files = {'LATEST.json', 'PROCESSES.jsonl', 'RESULT.json', 'SDK-AFTER.json',
                  'SDK-BEFORE.json', 'SOURCE-SEAL.json', 'WINDOW-START.json'}
stage_rows = []; mode_reports = []; record_sets = []
expected_seconds = [69.64164626400452, 70.29850567900576]
expected_log_shas = ['5816cb13afc8e534c4418b1027cf59ca9d163b200759e616d272f157f8d3a616',
                     '1b2da531ecf82033546f4c093673652f4a856842af5aa31ef7dbebaa98034b17']
for index, (mode, stage, configured) in enumerate(zip(('normal', 'optimized'), result['stages'], config['stages'])):
    label = stage['label']; start = read(E / (label + '-START.json'))
    need(stage == read(E / (label + '-RESULT.json'))
         and all(stage.get(k) == v for k, v in start.items()), 'START/stage/final mismatch')
    need(configured['label'] == label == mode + '-reached-bindings-v28'
         and configured['command'] == ['{python}'] + (['-O'] if mode == 'optimized' else [])
         + ['-B', TEST, '-v', '-f', METHOD], 'Configured focused command differs')
    command = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
               for part in configured['command']]
    need(stage['argv'] == command and stage['cwd'] == config['source'] == str(R / 'candidate-v28'),
         'Exact actual command differs')
    need(stage['returncode'] == 0 and not stage['timed_out'] and stage['leader_reaped']
         and stage['remaining_owned_descendants'] == [] and stage['source_seal_sha256'] == SOURCE_SHA,
         'Passing source/cleanup result differs')
    need(stage['stage_timeout_seconds'] == configured['seconds'] == 1800
         and stage['seconds'] == expected_seconds[index], 'Original cap or timing differs')
    need(stage['test_count'] == stage['expected_tests'] == configured['expected_tests'] == 1
         and stage['skipped_test_count'] == 0, 'Exact zero-skip count differs')
    log_raw = raw(E / (label + '.log')); log = log_raw.decode('utf-8')
    need(SHA(log_raw) == stage['log_sha256'] == expected_log_shas[index] and len(log_raw) == 1827235,
         'Full original log differs')
    need(re.findall(r'^Ran (\d+) tests? in ', log, re.M) == ['1']
         and log.rstrip().endswith('\nOK') and not re.search(r'\b(FAILED|ERROR|FAIL|skipped)\b', log),
         'Raw unittest outcome differs')
    started = re.findall(r'^test_\w+ \(__main__\.([^\n]+)\) \.\.\. ', log, re.M)
    need(started == [METHOD], 'Observed method selection differs')
    records = []; suffixes = []
    for line in log.splitlines():
        if line.startswith('OPERATION_REACHED_BINDINGS '):
            data = line.removeprefix('OPERATION_REACHED_BINDINGS ')
            record, offset = json.JSONDecoder().raw_decode(data)
            records.append(record); suffixes.append(data[offset:])
    need([row['route'] for row in records] == ROUTES and suffixes == ['', '', '', 'ok'],
         'Four original route records or merged unittest suffix differ')
    expected = set(records[0]['reached_sites']) | set(records[0]['residual_unreached_sites'])
    union = set().union(*(set(row['reached_sites']) for row in records))
    need(len(expected) == len(union) == 108 and expected == union
         and all(set(row['reached_sites']) | set(row['residual_unreached_sites']) == expected for row in records),
         'Consumed ID union/residual differs')
    need([len(row['reached_sites']) for row in records] == [73, 102, 19, 19]
         and [len(row['residual_unreached_sites']) for row in records] == [35, 6, 89, 89]
         and [row['original_streams'] for row in records] == [0, 0, 70, 1]
         and all(set(row['site_bindings']) == set(row['reached_sites']) for row in records),
         'Per-owner report inventory differs')
    stream_summaries = []
    for row in records:
        counts = collections.Counter()
        for path, read_phase, binding, match_phase, count in row['stream_binding_counts']:
            need(isinstance(path, str) and type(count) is int and count > 0, 'Stream count shape differs')
            counts[read_phase, binding, match_phase] += count
        expected_counts = ({('pending', 'queued_publish_replay', 'active'): 62,
                            ('active', 'live_original_frame', 'active'): 8} if row['route'] == 'map_loops'
                           else {('active', 'live_original_frame', 'active'): 1} if row['route'] == 'rtree_loops'
                           else {})
        need(dict(counts) == expected_counts and sum(counts.values()) == row['original_streams'],
             'Queued/live stream binding counts differ')
        stream_summaries.append({'route': row['route'], 'reached_sites': len(row['reached_sites']),
                                'residual_unreached_sites': len(row['residual_unreached_sites']),
                                'original_streams': row['original_streams'],
                                'stream_match_counts': [dict(read_phase=k[0], binding=k[1], match_phase=k[2], count=v)
                                                        for k, v in sorted(counts.items())]})
    record_sets.append(records)
    mode_reports.append({'mode': mode, 'method_executions': 1, 'owners': 4, 'skips': 0,
                         'elapsed_seconds': stage['seconds'], 'returncode': 0, 'timed_out': False,
                         'log_bytes': len(log_raw), 'log_sha256': SHA(log_raw),
                         'consumed_id_union_count': 108, 'consumed_id_union': sorted(union),
                         'residual_consumed_ids': [], 'owner_reports': stream_summaries})
    stage_rows.append({'stage': stage, 'start_sha256': digest(E / (label + '-START.json')),
                       'stage_result_sha256': digest(E / (label + '-RESULT.json'))})
    expected_files |= {label + suffix for suffix in ('-START.json', '-RESULT.json', '.log')}
need(record_sets[0] == record_sets[1], 'Mode route report values differ')
console = [json.loads(line) for line in raw(R / (PHASE + '.supervisor.log')).splitlines()]
need(len(console) == 3 and console[-1] == result, 'Original final supervisor console differs')
for emitted, stage in zip(console[:-1], result['stages']):
    need(emitted == {k: v for k, v in stage.items()
                     if k not in ('test_count', 'expected_tests', 'skipped_test_count')},
         'Console differs beyond later-added test inventory annotations')
processes = [json.loads(line) for line in raw(E / 'PROCESSES.jsonl').splitlines()]
need(processes and read(E / 'LATEST.json') == processes[-1], 'Process LATEST differs')
stages = {s['label']: s for s in result['stages']}
need(all(all(p['pgid'] == stages[row['label']]['pgid'] for p in row['owned']) for row in processes),
     'Process group differs')
need({p.name for p in E.iterdir()} == expected_files and len(expected_files) == 13,
     'Original phase inventory differs')
originals = []


def add(path, name, kind, readable=False):
    originals.append({'path': name, 'data': raw(path), 'kind': kind,
                      'original_source': str(path), 'readable': readable})


for name in sorted(expected_files):
    add(E / name, 'actual/' + PHASE + '/' + name, 'original-passing-phase-receipt-or-merged-log',
        readable=name in {'RESULT.json', 'SDK-AFTER.json', 'SDK-BEFORE.json', 'WINDOW-START.json'})
for name in [PHASE + '.json', PHASE + '.supervisor.log', 'run_checkpoint_matrix.py', 'CANDIDATE-V28-SOURCE-SEAL.json']:
    add(R / name, 'reproduce/' + name, 'original-config-console-supervisor-or-source-seal', readable=True)
add(manifest_path, 'reproduce/PUBLISHABLE-SOURCE-MANIFEST.json', 'exact-frozen-31-path-source-manifest', readable=True)
for row in source_manifest['files']:
    path = R / 'candidate-v28' / row['path']; data = raw(path)
    need(SHA(data) == row['sha256'] == source_seal[row['path']] and len(data) == row['bytes'],
         'Frozen source mismatch: ' + row['path'])
    need(hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == row['git_blob'],
         'Source Git blob mismatch')
    add(path, 'reproduce/source/' + row['path'], 'exact-frozen-v28-source',
        readable=row['path'] in {TEST, 'docs/validation/full-audit-721-qualification-policy.md'})
support = 'tools/coverage_toolchain_identity.py'
need(digest(R / 'candidate-v28' / support) == source_seal[support], 'SDK support source changed')
add(R / 'candidate-v28' / support, 'reproduce/source/' + support, 'exact-supervisor-sdk-identity-source')
summary = {
    'schema': 1, 'status': 'PASSED_V28_FOCUSED_REACHED_BINDING_SWEEP_ONLY',
    'scope': 'One selected reached-binding method passed in normal and optimized modes: two method executions, four owner reports per mode, zero skips. Each mode reports union108 consumed IDs with no residual. No full test suite, Python matrix, native coverage, hosted CI or overall completion claim.',
    'source_seal_sha256': SOURCE_SHA, 'source_manifest_sha256': MANIFEST_SHA,
    'exact_frozen_source_manifest_paths': 31, 'executed_test_path': TEST, 'executed_test_sha256': TEST_SHA,
    'source_test_methods': len(methods), 'selected_method': METHOD, 'other_41_methods_selected': False,
    'method_executions': 2, 'unique_executed_methods': 1, 'owner_report_executions': 8,
    'skips': 0, 'all_stages_returncode_zero': True, 'any_stage_timed_out': False,
    'stage_cap_seconds': 1800, 'whole_window_cap_seconds': 10800,
    'window_elapsed_seconds': result['elapsed_seconds'], 'modes': mode_reports,
    'mode_route_report_values_equal': True,
    'consumed_id_boundary': 'The union refers to the 108 consumed-read IDs named by this maintained sweep across the four selected owner routes. Per-owner residuals remain explicit; the union residual is empty. This is not general branch/condition/native coverage or a claim about every possible route/input.',
    'stream_binding_boundary': 'In each mode, the saved Map report counts62 pending streams matched during actual queued publish replay and8 active streams matched in their live original frames; Rtree counts1 active live-frame stream. Full per-path/phase/binding counts remain in the original logs.',
    'source_sdk_unchanged': True, 'remaining_owned_descendants': [], 'sdk_receipt_sha256': SHA(sdk),
    'source_manifest_time_boundary': 'The original source_only_unqualified manifest is preserved unchanged. This packet records only the later focused passing phase. The source seal differs from v27 only at the test file; production/proof bytes are unchanged.',
    'separate_v27_failure_reference': {'packet_path': PRIOR_PACKET, 'packet_manifest_sha256': PRIOR_SHA,
                                     'raw_members_included_here': False,
                                     'limit': 'The earlier v27 failure remains a failed historical run in its separate packet; it is not relabeled by this v28 pass.'},
    'console_binding_limit': 'Actual supervisor console stage records precede later test_count/expected_tests/skipped_test_count annotations; final JSON includes them. No missing console output is reconstructed.',
    'stream_capture': 'Each full1827235-byte log preserves the original merged stdout/stderr, including the literal unittest ok suffix on the Rtree JSON line. Neither logs nor reports are normalized. Separate streams are not invented.',
    'reproduction_boundary': 'Includes all thirteen phase files, actual config/console/supervisor, the full source seal, all31 frozen manifest source paths and SDK support. The full unchanged repository and SDK executable image are not distributed.',
    'qualification_limit': 'The other41 methods, including distinct negative controls, were not selected in this phase. This packet does not establish their results, a full Python matrix, native coverage, hosted CI or overall completion.',
    'evidence_policy': 'Ordinary original receipts/logs/config and exact source bytes only. No private review/design notes, unexecuted proposals, candidate edits, reruns, native execution or upload.'
}
commands = {'schema': 1, 'kind': 'derived-actual-command-and-receipt-binding',
            'phase': PHASE, 'source_seal_sha256': SOURCE_SHA,
            'config_sha256': digest(R / (PHASE + '.json')), 'result_sha256': RESULT_SHA,
            'stages': stage_rows, 'supervisor_console_sha256': digest(R / (PHASE + '.supervisor.log')),
            'configured_but_unrun_stage_labels': []}
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
             ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-passing-focused-reached-sweep-summary'),
             ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-actual-command-and-receipt-binding'),
             ('decode_verify.py', raw(decoder), 'safe-decoder-no-content-execution'),
             ('reproduce/build_reached_bindings_v28_packet.py', raw(Path(__file__)), 'packet-builder-no-candidate-execution')]
guide = '''# V28 focused reached-binding sweep evidence

PASSED: one selected method ran in each mode, two executions with zero skips.
Each mode emitted four owner reports: invariant, winner, Map and Rtree. Their
union contains all108 consumed-read IDs of this sweep with no residual. The
per-owner residuals remain explicit. This does not establish general source,
branch, condition or native coverage, nor results for every possible input.

Each Map report records62 pending streams matched by actual queued publish
replay and8 active streams matched in live original frames. Each Rtree report
records1 active live-frame stream. Both modes preserve the complete per-path
and per-site reports. These are two executions of one method, not eight tests.
The other41 methods in the source file were not selected in this phase.

Stage times were69.641646264 and70.298505679 seconds, exits zero and no timeout.
The original1,800-second stage and10,800-second window caps remain unchanged.
Source/SDK receipts were unchanged and no owned descendants remained. The v27
failure remains separate and failed; its manifest is referenced by path/hash.
No full Python matrix, native coverage, hosted CI or overall pass is claimed.

Both complete1,827,235-byte merged logs are preserved byte-for-byte, including
all four reports, warnings, unittest summaries and the original ok suffix on
the Rtree report line. No original log or JSON report has been normalized.
All thirteen phase files, actual config and supervisor console, exact test,
all31 frozen manifest source paths, full source/SDK seals, supervisor and SDK
support source are retained. The original source-only manifest is unchanged.

Readable originals retain exact bytes. Archived originals, including both
full UTF-8 logs, use per-member base64 inside a JSON container, deterministic
gzip with mtime=0, then base64 transport. The inner manifest records original
paths, byte lengths, hashes and storage. The outer manifest seals payloads
and excludes itself. Summary and command binding are explicitly derived.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory

The decoder verifies bytes before writing; it rejects unsafe paths, duplicates,
symlink payloads and existing output. It never executes decoded content.
The full unchanged repository and SDK executable image are not distributed.
Packaging performs no candidate edit, test/native execution or upload. Private
review/design notes and unexecuted proposals are excluded.
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
