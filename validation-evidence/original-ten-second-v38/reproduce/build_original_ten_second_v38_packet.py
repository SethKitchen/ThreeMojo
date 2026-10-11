"""Package only one terminal diagnostic from exact pre-pinned input bytes.

Stdlib-only static packaging. Never imports or executes candidate/protocol code,
runs tests or native tools, reads other phases, uploads, or overwrites output.
"""
from pathlib import Path
import argparse
import base64
import gzip
import hashlib
import json
import re
import stat

R = Path(__file__).resolve().parent
PHASE = 'original-ten-second-v38-diagnostic'
E = R / 'evidence' / PHASE
O = R / 'validation-evidence-original-ten-second-v38-diagnostic-packet'
LOCK_NAME = 'original-ten-second-v38-packet-input-lock.json'
LOCK_SHA = '8f87eda85830d0f225a603d10de84d3547fb7aca076ad30520cf09230567ea0e'
RESULT_SHA = '771e0adec2a55318933d3db57beba6c8aa8d4a84f37c98d1764ebfec7492da09'
CONSOLE_SHA = 'd775e5b59d976eeefbe46f73d6cd8d3486725179675f622d78d121fa67f1fd8e'
SEAL_SHA = '47eb6c57d3d88f116326dfab6bb999d31e909f532a396318b05fd2254dac8537'
DECODER_NAME = 'validation-evidence-qualification-policy-v23-packet/decode_verify.py'
DECODER_SHA = 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4'
REVIEW_SHA = 'a807654e8692f7aaec55bdafaf1cc6a6a0a10b0439eb3e19fa3dd585642de718'
COMMIT = '7b6f7a740208ed1d8d2aa9dd4e359b455188951f'
LIMIT = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def raw(path):
    parts = path.relative_to(R).parts
    need(parts and all(p not in ('', '.', '..') for p in parts), 'Unsafe input')
    current = R
    for index, part in enumerate(parts):
        current /= part
        mode = current.lstat().st_mode
        need(stat.S_ISREG(mode) if index == len(parts) - 1 else stat.S_ISDIR(mode),
             'Symlink or nonregular input: ' + str(path))
    need(path.stat().st_size <= LIMIT, 'Oversize input')
    return path.read_bytes()


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-builder-sha256', required=True)
    args = parser.parse_args()
    need(re.fullmatch('[0-9a-f]{64}', args.expected_builder_sha256), 'Invalid builder hash')
    need(not O.exists() and not O.is_symlink(), 'Create-only output already exists')
    builder = raw(Path(__file__).resolve())
    need(SHA(builder) == args.expected_builder_sha256, 'Changed builder')
    lock_raw = raw(R / LOCK_NAME)
    need(SHA(lock_raw) == LOCK_SHA, 'Changed exact input lock')
    lock = parse(lock_raw)
    need(lock['schema'] == 1, 'Unknown input lock schema')
    observed = {}
    for name, row in lock['inputs'].items():
        data = raw(R / name)
        need(len(data) == row['bytes'] and SHA(data) == row['sha256'], 'Changed exact input: ' + name)
        data.decode('utf-8')
        observed[name] = data
    need(len(observed) == 42, 'Exact input count differs')
    ep = 'evidence/' + PHASE + '/'
    read = lambda name: observed[name]
    obj = lambda name: parse(read(name))
    result = obj(ep + 'RESULT.json')
    config = obj(PHASE + '.json')
    window = obj(ep + 'WINDOW-START.json')
    seal = obj('CANDIDATE-V38-SOURCE-SEAL.json')
    publication = obj('PUBLISHED-V38-QUALIFICATION-BINDING.json')
    protocol = obj('ORIGINAL-TEN-SECOND-V38-PROTOCOL-SEAL.json')
    need(SHA(read(ep + 'RESULT.json')) == RESULT_SHA and
         SHA(read(PHASE + '.supervisor.log')) == CONSOLE_SHA, 'Exact terminal attempt differs')
    need(SHA(read('CANDIDATE-V38-SOURCE-SEAL.json')) == SEAL_SHA and
         read(ep + 'SOURCE-SEAL.json') == read('CANDIDATE-V38-SOURCE-SEAL.json'), 'Source seal differs')
    need(SHA(read(DECODER_NAME)) == DECODER_SHA, 'Reviewed decoder differs')
    need(publication['commit'] == COMMIT and publication['source_seal_sha256'] == SEAL_SHA,
         'Publication/source reference differs')
    need(set(protocol) == {'probe.py', 'check_inventory.py'} and
         all(SHA(read('original-ten-second-v38-protocol/' + n)) == h for n, h in protocol.items()),
         'Protocol source/seal differs')
    need(read(ep + 'SDK-BEFORE.json') == read(ep + 'SDK-AFTER.json'), 'SDK receipts differ')
    need(result['sequence_completed'] is True and result['failure'] is None and
         result['source_seal_unchanged'] is True and result['sdk_identity_unchanged'] is True and
         result['remaining_owned_descendants'] == [] and len(result['stages']) == 8 and
         result['scope'] == config['scope'] and 0 < result['elapsed_seconds'] < 360,
         'Terminal collection, stability or cleanup differs')
    need(window['whole_window_seconds'] == config['window_seconds'] == 360 and
         window['source_seal_sha256'] == SEAL_SHA and window['python_optimize'] == 0 and
         window['supervisor_sha256'] == SHA(read('run_checkpoint_matrix.py')),
         'Window metadata differs')
    need(config['phase'] == PHASE and config['source'] == str(R / 'candidate-v38') and
         config['seal'] == 'CANDIDATE-V38-SOURCE-SEAL.json' and config['additional_sources'] == [
             {'seal': str(R / 'ORIGINAL-TEN-SECOND-V38-PROTOCOL-SEAL.json'),
              'source': str(R / 'original-ten-second-v38-protocol')}], 'Configuration binding differs')
    console = [parse(line) for line in read(PHASE + '.supervisor.log').splitlines()]
    need(len(console) == 9 and console[-1] == result, 'Complete console/RESULT differs')
    stages, children, observation_sets = [], [], []
    expected_names = {'RESULT.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'SOURCE-SEAL.json',
                      'WINDOW-START.json', 'LATEST.json', 'PROCESSES.jsonl'}
    python = str(R.parent / 'restored-toolchain/official-venv/bin/python')
    families = (('invariant', 1, 2, 'tools/carla_lane_oracle/test_coverage_invariant_contracts.py'),
                ('clean-import', 4, 9, 'tools/test_coverage_loop_proofs.py'))
    for mode, optimize in (('normal', 0), ('optimized', 1)):
        for family, tests, child_count, source_name in families:
            label = mode + '-' + family
            obs_name = family + '-' + mode + '-OBSERVATIONS.json'
            expected_names.add(obs_name)
            observations = obj(ep + obs_name)
            need(observations['family'] == family and observations['parent_optimize'] == optimize and
                 observations['actual_child_attempts'] == observations['expected_child_attempts'] ==
                 len(observations['observations']) == child_count and
                 observations['maintained_exit_code'] == 1 and observations['qualification'] is False and
                 observations['source_before_sha256'] == observations['source_after_sha256'] == seal[source_name],
                 'Observation identity/count/exit differs: ' + label)
            observation_sets.append(dict(stage_label=label, original_path='actual/' + PHASE + '/' + obs_name,
                sha256=SHA(read(ep + obs_name)), source_module=source_name,
                source_before_sha256=observations['source_before_sha256'],
                source_after_sha256=observations['source_after_sha256'], actual_child_attempts=child_count))
            for child_index, row in enumerate(observations['observations']):
                need(row['parent_optimize'] == optimize and row['original_timeout_seconds'] == 30 and
                     row['diagnostic_timeout_seconds'] == 10 and row['helper_source_sha256'] == seal[source_name] and
                     row['argv'][0] == python and row['inherited_PYTHONOPTIMIZE'] is None and
                     row['child_O_flag'] == ('-O' in row['argv']) == (family == 'clean-import' and bool(optimize)) and
                     (row['outcome'] == 'timeout' or row['outcome'] == 'returned' and row['returncode'] == 0),
                     'Child mode/guard/outcome differs')
                for stream in ('stdout', 'stderr'):
                    if row.get(stream) is not None:
                        captured = row[stream]
                        need(SHA(base64.b64decode(captured['base64'], validate=True)) == captured['sha256'],
                             'Captured output hash differs')
                selection = ('direct', 'qualified-package')[child_index] if family == 'invariant' else '/'.join(row['argv'][-4:])
                children.append(dict(position_one_based=len(children) + 1, stage_label=label, family=family,
                    attempt_in_stage_one_based=child_index + 1, selection=selection,
                    observation_path='actual/' + PHASE + '/' + obs_name,
                    observation_sha256=SHA(read(ep + obs_name)),
                    **{key: row[key] for key in ('argv', 'cwd', 'parent_optimize', 'child_O_flag',
                       'inherited_PYTHONOPTIMIZE', 'original_timeout_seconds', 'diagnostic_timeout_seconds',
                       'helper', 'helper_source_sha256', 'outcome', 'seconds')},
                    **{key: row[key] for key in ('returncode', 'exception', 'script_sha256') if key in row}))
            for inventory in (False, True):
                current = label + ('-inventory' if inventory else '')
                index = len(stages)
                expected_names.update(current + suffix for suffix in ('-START.json', '-RESULT.json', '.log'))
                start = obj(ep + current + '-START.json')
                receipt = obj(ep + current + '-RESULT.json')
                log = read(ep + current + '.log')
                executable = 'check_inventory.py' if inventory else 'probe.py'
                flags = ['-B'] if inventory or not optimize else ['-O', '-B']
                cmd = ['{python}', *flags, str(R / 'original-ten-second-v38-protocol' / executable),
                       '{evidence}', family] + ([str(optimize)] if inventory else [])
                plan = dict(command=cmd, cwd=str(R / 'candidate-v38'), label=current, seconds=5 if inventory else 180)
                if not inventory:
                    plan.update(accept_nonzero=True, expected_tests=tests)
                actual_argv = [x.replace('{python}', python).replace('{evidence}', str(E)) for x in cmd]
                need(config['stages'][index] == plan and receipt == result['stages'][index] and
                     all(receipt.get(k) == v for k, v in start.items()), 'Plan/START/RESULT differs')
                need(receipt['argv'] == actual_argv and receipt['cwd'] == plan['cwd'] and
                     receipt['source_seal_sha256'] == SEAL_SHA and receipt['stage_timeout_seconds'] == plan['seconds'] and
                     receipt['returncode'] == (0 if inventory else 1) and receipt['timed_out'] is False and
                     receipt['leader_reaped'] is True and receipt['remaining_owned_descendants'] == [] and
                     receipt['log_sha256'] == SHA(log), 'Stage command/outcome/cleanup/log differs')
                need(console[index] == {k: v for k, v in receipt.items()
                     if k not in ('expected_tests', 'test_count', 'skipped_test_count')}, 'Console stage differs')
                timings = re.findall(rb'^Ran (\d+) tests? in ([0-9.]+)s$', log, re.M)
                if not inventory:
                    need(receipt['test_count'] == receipt['expected_tests'] == tests and receipt['skipped_test_count'] == 0
                         and len(timings) == 1 and int(timings[0][0]) == tests and b'FAILED (errors=' in log,
                         'Method failure/count receipt differs')
                else:
                    need(log == b'PASS: complete diagnostic child inventory; individual outcomes remain diagnostic\n',
                         'Inventory checker log differs')
                stages.append(dict(position_one_based=index + 1, planned=plan, actual=receipt,
                    kind='inventory-check' if inventory else 'maintained-method-diagnostic',
                    parent_optimization=0 if inventory else optimize,
                    wrapper_reported_seconds=None if inventory else float(timings[0][1]),
                    start_sha256=SHA(read(ep + current + '-START.json')),
                    result_sha256=SHA(read(ep + current + '-RESULT.json'))))
    need({p.name for p in E.iterdir()} == expected_names, 'Unexpected terminal evidence inventory')
    need(len(children) == 22 and sum(c['outcome'] == 'timeout' for c in children) == 6 and
         sum(c['outcome'] == 'returned' for c in children) == 16, 'Child aggregate differs')
    invariant = [c for c in children if c['family'] == 'invariant']
    clean = [c for c in children if c['family'] == 'clean-import']
    need([c['outcome'] for c in invariant] == ['timeout', 'returned', 'returned', 'timeout'], 'Invariant mixed outcome differs')
    need([c['attempt_in_stage_one_based'] for c in clean if c['outcome'] == 'timeout'] == [1, 4, 1, 4],
         'Clean-import timeout placements differ')
    summary = dict(schema=1, kind='derived-original-ten-second-diagnostic-summary',
        status='COLLECTION_COMPLETE_SIX_CHILD_TIMEOUTS_ALL_FOUR_METHOD_STAGES_FAILED',
        diagnostic_only=True, collection_completed=True, diagnostic_passed=False, qualification_passed=False,
        current_30_second_qualification_established=False, timeout_policy_approval_granted=False,
        collection_boundary='sequence_completed=true and failure=null mean all ordinary outcomes and inventories were collected; accept_nonzero=true does not mean a diagnostic or qualification pass.',
        protocol_review_sha256=REVIEW_SHA, protocol_review_bytes_included=False,
        review_boundary='The independent protocol review is cited by its supplied exact SHA256 only. No private review bytes are included or interpreted by this builder.',
        result_sha256=RESULT_SHA, console_sha256=CONSOLE_SHA,
        config_sha256=SHA(read(PHASE + '.json')), protocol_seal_sha256=SHA(read('ORIGINAL-TEN-SECOND-V38-PROTOCOL-SEAL.json')),
        supervisor_sha256=window['supervisor_sha256'], source_seal_sha256=SEAL_SHA,
        source_seal_unchanged=result['source_seal_unchanged'], sdk_identity_unchanged=result['sdk_identity_unchanged'],
        sdk_before_sha256=SHA(read(ep + 'SDK-BEFORE.json')), sdk_after_sha256=SHA(read(ep + 'SDK-AFTER.json')),
        stability_boundary='Unchanged source/SDK and zero owned descendants are original terminal supervisor receipts; this packet performs no new candidate or SDK scan.',
        publication_reference=publication, publication_binding_sha256=SHA(read('PUBLISHED-V38-QUALIFICATION-BINDING.json')),
        publication_boundary='Preserved publication metadata is a reference, not a new remote or repository verification.',
        started=window['started'], finished=result['finished'], elapsed_seconds=result['elapsed_seconds'],
        window_seconds=360, method_stage_cap_seconds=180, inventory_stage_cap_seconds=5,
        maintained_source_child_timeout_seconds=30, diagnostic_child_timeout_seconds=10,
        timeout_change_scope='Only the two targeted helper subprocess.run timeout arguments were changed from maintained 30s to original 10s in memory; on-disk source was unchanged.',
        actual_child_attempts=22, returned_zero_children=16, timeout_children=6, other_child_outcomes=0,
        method_stages_returning_one=4, inventory_stages_returning_zero=4,
        invariant_outcome='Direct and qualified-package children each timed out once and returned zero once. Successful direct=9.718523084011395s; successful qualified-package=9.99215825900319s.',
        invariant_mode_boundary='All four invariant children had no -O and no inherited PYTHONOPTIMIZE, including those launched from optimized parents.',
        clean_import_outcome='Ordinary CLI and shadowed CLI timed out in both normal and -O child modes. The other fourteen clean-import attempts returned zero.',
        clean_import_mode_boundary='Normal clean-import children have -E -B; optimized clean-import children have -E -B -O. Actual full argv and cwd are indexed per attempt.',
        timing_boundary='Child seconds measure the diagnostic subprocess.run wrapper including timeout handling. Parent stage times and unittest method durations are separate. A timeout records the 10s guard, not eventual unconstrained completion time.',
        remaining_owned_descendants=result['remaining_owned_descendants'], observations=observation_sets,
        child_attempts=children, stages=stages,
        raw_receipts_authoritative=True,
        scope='One original-10-second diagnostic on immutable candidate-v38: five maintained methods per parent mode, 22 child attempts. No current-30-second qualification, owner timeout-policy approval, native/coverage/hosted-CI readiness, merge readiness, or issue-completion claim.',
        exclusions='Private notes/review bytes; polling LATEST.json and PROCESSES.jsonl; all other phases; candidate source contents and SDK images. Full source seals and SDK identity receipts are preserved.')
    originals = []
    for name, data in sorted(observed.items()):
        if name == DECODER_NAME:
            continue
        path = 'actual/' + name[len('evidence/'):] if name.startswith('evidence/') else ('actual/' if name.endswith('.supervisor.log') else 'reproduce/') + name
        need(not any(x in path.lower() for x in ('review', 'audit', 'dream', 'scratch')), 'Private member name')
        originals.append(dict(path=path, data=data, original_source=str(R / name),
                              kind='complete-byte-exact-terminal-evidence-or-reproduction-reference'))
    need(len(originals) == 41 and len({r['path'] for r in originals}) == 41, 'Exact original-member scope differs')
    patterns = (rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', rb'gh[pousr]_[A-Za-z0-9]{30,}',
                rb'AKIA[0-9A-Z]{16}', rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
    for row in originals:
        need(not any(re.search(p, row['data']) for p in patterns), 'Credential pattern: ' + row['path'])
    archive = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
    archived = [dict(path=r['path'], bytes=len(r['data']), sha256=SHA(r['data']),
                     data_base64=base64.b64encode(r['data']).decode('ascii')) for r in originals]
    members = [dict(path=r['path'], original_source=r['original_source'], kind=r['kind'],
                    bytes=len(r['data']), sha256=SHA(r['data']), storage='container', transport_path=archive) for r in originals]
    container = (json.dumps(dict(schema=1, encoding='base64', members=archived), sort_keys=True,
                            separators=(',', ':')) + '\n').encode()
    need(len(container) < LIMIT, 'Decoder archive limit exceeded')
    encoded = base64.b64encode(gzip.compress(container, compresslevel=9, mtime=0)) + b'\n'
    need(gzip.decompress(base64.b64decode(encoded.strip(), validate=True)) == container, 'Transport round-trip differs')
    inner = dict(schema=1, original_member_count=len(members), original_member_bytes=sum(r['bytes'] for r in members),
                 container=dict(path=archive, encoding='base64 of deterministic gzip mtime=0 containing JSON',
                                members=len(archived), json_bytes=len(container), json_sha256=SHA(container)), members=members)
    guide = '''# Original 10-second diagnostic, candidate v38

COLLECTION COMPLETE. 22 actual child attempts: 16 returned zero and 6 timed out.
All four maintained-method stages returned 1; all four inventory checks returned
0. No supervisor stage timed out. Collection took 118.93802166300884 seconds,
with original receipts reporting source/SDK unchanged and zero owned descendants.

Invariant direct and qualified-package children each timed out once and returned
zero once (successful durations 9.718523084011395s and 9.99215825900319s). All four
invariant children ran without -O and without inherited PYTHONOPTIMIZE, even under
optimized parents. Clean-import ordinary CLI and shadowed CLI timed out in normal
and -O modes; the other fourteen clean-import attempts returned zero.

This is only a diagnostic of five maintained methods per parent mode. The two
helper timeout arguments were changed from the maintained 30s to original 10s
only in memory. Source bytes were unchanged. Completion under accept_nonzero=true
is not a pass. This establishes no current-30-second qualification or owner
timeout-policy approval, native/coverage/hosted-CI readiness, merge readiness,
repeatable timing headroom, or issue completion.

VALIDATION-SUMMARY.json is a derived index of every exact child argv, cwd, parent
and child mode, outcome and timing, plus all stage commands/caps/receipts. Raw
originals remain authoritative. Child wrapper timing, unittest timing and parent
supervisor timing are distinct. The original protocol review is cited by exact
hash only; private review bytes are excluded. Publication metadata is preserved
as a reference, without new remote verification. Stability is attributed to the
original receipts; no candidate/SDK scan, import or test was performed here.

All 41 originals are preserved losslessly, including full logs and observations,
all START/RESULT receipts, terminal RESULT, source seals, SDK before/after, window,
config, both protocol files and seal, supervisor source/console, and publication
binding. Only polling LATEST/PROCESSES, private notes/reviews, other phases,
candidate source contents and SDK images are excluded.

INNER-MEMBER-MANIFEST.json lists exact original hashes and byte sizes. Originals
are base64 JSON inside deterministic gzip mtime=0, then UTF-8 base64. The outer
manifest seals every transport payload except itself. Independently compare the
outer-manifest hash with the supplied hash before using the packet.

Verify without writing: python -B decode_verify.py
Decode originals to a NEW directory: python -B decode_verify.py --output /new/directory
The existing byte-identical safe decoder verifies hashes, sizes and paths without
executing or importing evidence. The builder is provided as source only; it was
used for static packaging, not diagnostic execution. Its output is create-only
and all consumed inputs are fixed by the input lock. No remote writes occurred.
'''
    payloads = [(archive, encoded, 'lossless-original-diagnostic-evidence'),
        ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-member-inventory'),
        ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-exact-child-and-stage-index'),
        ('decode_verify.py', read(DECODER_NAME), 'byte-identical-safe-decoder'),
        ('reproduce/' + Path(__file__).name, builder, 'source-only-static-packet-builder'),
        ('reproduce/' + LOCK_NAME, lock_raw, 'exact-input-lock'),
        ('README.md', guide.encode(), 'scope-and-safe-transport-guide')]
    need(len(payloads) == len({name for name, _, _ in payloads}) == 7, 'Transport inventory differs')
    for name, data in observed.items():
        need(raw(R / name) == data, 'Consumed input changed during packaging: ' + name)
    need(raw(R / LOCK_NAME) == lock_raw and raw(Path(__file__).resolve()) == builder, 'Builder/lock changed')
    need({p.name for p in E.iterdir()} == expected_names, 'Terminal inventory changed')
    O.mkdir(parents=False, exist_ok=False)
    rows = []
    for name, data, kind in sorted(payloads):
        path = O / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream:
            stream.write(data)
        need(raw(path) == data, 'Written payload differs')
        rows.append(dict(path=name, local_source=str(path), bytes=len(data), sha256=SHA(data), kind=kind))
    manifest = O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json'
    with manifest.open('xb') as stream:
        stream.write(JSON(dict(schema=1, scope=summary['scope'], files=rows)))
    print(json.dumps(dict(manifest=str(manifest), sha256=SHA(raw(manifest)), payloads=len(rows),
        original_members=len(members), original_bytes=inner['original_member_bytes'],
        packet_bytes_including_manifest=sum(r['bytes'] for r in rows) + len(raw(manifest)),
        diagnostic_passed=False, qualification_passed=False), sort_keys=True))


if __name__ == '__main__':
    main()
