"""Package one terminal paired diagnostic; source review/release required first.

Stdlib only. Never imports or executes protocol/candidate code, scans candidates,
reads another phase, runs tests/native tools, uploads, or overwrites output.
Required expected RESULT/console/builder hashes bind the reviewed exact attempt.
"""
from pathlib import Path
from datetime import datetime
import argparse
import base64
import gzip
import hashlib
import json
import re
import stat

R = Path(__file__).resolve().parent
PHASE = 'winner-cli-paired-diagnostic-v28-v35'
E = R / 'evidence' / PHASE
O = R / 'validation-evidence-winner-cli-paired-diagnostic-v28-v35-packet'
RESULT = '2ce6faeb70c769d44428d82280f13ddf79ef95c64dc4f7ee4eced4d888fce226'
CONSOLE = 'ec3ee40729047352631925bce8a5329c7bbf9c031b1b52cd771eb081d07be87a'
CONFIG = '22c2b4e421724f4e655c0ea84c23a871c0add9fe1ca507cd685733f9fc76e1e7'
DRIVER = '2a84aebc0d803d443854ad0d80fddc9c12c01a953229b5336b809bde37986fcb'
PROTOCOL = 'a9b8365038e16fd1e6f0a277652b4727bccc22277f737341e3ef41b72600123c'
SUPERVISOR = '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
SDK = '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
DECODER = 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4'
REVIEW = 'f1a4f2d4e42317e483dfb54475c84bb0f98ba9c1a9b244933275598277ed0edb'
SEALS = {
    '28': 'fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596',
    '35': '020a72e9ceb1e45bf31559b624b5d328fd4a6e6414aafbdba5259b71af9fd7cc',
}
MODULES = {
    '28': 'af05f38675f34284307f2ee896ff0cd6e2594acd739388436d4690454eb10eb5',
    '35': '132f36fb44d44bd84340ff37f82e44cc3fdd3648f298ea2dcd7198ed964e06a5',
}
PUBLICATIONS = {
    '28': ('0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf',
           '031f9f726edb6e9409853fd777af966c8ebba88d', 'd2c9f94523b9c03aa94b04eaad774f73f147cd74'),
    '35': ('9f7159cc980b51da7be9ed5b3822cbb0a8c88977794200cf6b24315f9c4a8e2c',
           '19287a0b1564b9a628f15c96e7675c51413ca1a9', '5c1f67c196fc30d6a323d6d854748b65e3640585'),
}
LABELS = ('v28-normal-cli-winner', 'v35-normal-cli-winner')
WINDOW = 'f0b24171ca7a82c14f95985815f774d3f13df605c245be6bdd555d7b29941a65'
STAGE_RECEIPTS = {
    '28': ('546485d227b208353ae341492cf68eca89605765b9f1799a514e5ba23905da51',
           'a85231dd62329b1d5c37cfe73754e8319af99fbf766ea5997d694089bc1a5681'),
    '35': ('da6174e9f077fc39898df01b2f2c13bd524b055c55a9eba0773fb8987c73be93',
           '0587589275d6d667ab08346ed3bb9bfca2a8045b64180eb39392c86aaab7bbe3'),
}
LIMIT = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def raw(path):
    relative = path.relative_to(R)
    need(relative.parts and all(p not in ('', '.', '..') for p in relative.parts), 'Unsafe input')
    current = R
    for index, part in enumerate(relative.parts):
        current /= part
        mode = current.lstat().st_mode
        need(stat.S_ISREG(mode) if index == len(relative.parts) - 1 else stat.S_ISDIR(mode),
             'Nonregular or symlink input: ' + str(current))
    need(path.stat().st_size <= LIMIT, 'Oversize input: ' + str(path))
    return path.read_bytes()


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-result-sha256', required=True)
    parser.add_argument('--expected-console-sha256', required=True)
    parser.add_argument('--expected-builder-sha256', required=True)
    args = parser.parse_args()
    for name, value in vars(args).items():
        need(re.fullmatch(r'[0-9a-f]{64}', value) is not None, 'Invalid exact hash: ' + name)
    need(args.expected_result_sha256 == RESULT and args.expected_console_sha256 == CONSOLE,
         'Only the reviewed exact terminal paired attempt is supported')
    need((E / 'RESULT.json').is_file(), 'Refuse: terminal RESULT is absent; no polling or partial packaging')
    need(not O.exists() and not O.is_symlink(), 'Create-only output already exists')
    observed = {}

    def read(path, expected=None):
        data = raw(path)
        need(expected is None or SHA(data) == expected, 'Changed exact binding: ' + str(path))
        need(path not in observed or observed[path] == data, 'Input changed: ' + str(path))
        observed[path] = data
        return data

    builder = read(Path(__file__).resolve(), args.expected_builder_sha256)
    result_raw = read(E / 'RESULT.json', args.expected_result_sha256)
    result = parse(result_raw)
    config = parse(read(R / (PHASE + '.json'), CONFIG))
    driver_path = R / 'winner-cli-paired-diagnostic-v35-protocol/probe.py'
    read(driver_path, DRIVER)
    protocol = parse(read(R / 'WINNER-CLI-PAIRED-DIAGNOSTIC-PROTOCOL-SEAL.json', PROTOCOL))
    need(protocol == {'probe.py': DRIVER}, 'Protocol seal contents differ')
    read(R / 'run_checkpoint_matrix.py', SUPERVISOR)
    decoder = read(R / 'validation-evidence-qualification-policy-v23-packet/decode_verify.py', DECODER)
    # Review is a binding check only; no review bytes are included in originals or payloads.
    review = parse(read(R / 'winner-cli-paired-diagnostic-independent-review/AUDIT.json', REVIEW))
    need(review['verdict'] == 'APPROVE_CORRECTED_EXACT_PAIRED_NORMAL_CLI_DIAGNOSTIC_PROTOCOL'
         and review['probe_sha256'] == DRIVER and review['protocol_seal_sha256'] == PROTOCOL
         and review['config_sha256'] == CONFIG and review['supervisor_sha256'] == SUPERVISOR
         and review['child_cap_seconds'] == 30 and review['parent_stage_seconds'] == 45
         and review['window_seconds'] == 120, 'Exact protocol review binding differs')
    methods = ['setUp', 'consumer_script_probe',
               'test_complete_winner_and_parser_consumers_in_real_script_locations']
    need(review['three_maintained_methods_byte_and_AST_identical'] == methods,
         'Protocol review does not attest the exact maintained method identity')
    publications = {}
    for version in ('28', '35'):
        seal = parse(read(R / ('CANDIDATE-V' + version + '-SOURCE-SEAL.json'), SEALS[version]))
        need(seal['tools/test_coverage_loop_proofs.py'] == MODULES[version], 'Maintained module/seal pin differs')
        publication_sha, commit, tree = PUBLICATIONS[version]
        publication = parse(read(R / ('PUBLISHED-V' + version + '-QUALIFICATION-BINDING.json'), publication_sha))
        need(publication['source_seal_sha256'] == SEALS[version]
             and publication['published_commit'] == commit and publication['published_tree'] == tree,
             'Publication/source reference differs')
        publications[version] = dict(binding_sha256=publication_sha, published_commit=commit,
                                     published_tree=tree, source_seal_sha256=SEALS[version])
    need(read(E / 'SOURCE-SEAL.json', SEALS['35']) == observed[R / 'CANDIDATE-V35-SOURCE-SEAL.json'],
         'Executed primary source seal differs')
    sdk_before = read(E / 'SDK-BEFORE.json', SDK)
    sdk_after = read(E / 'SDK-AFTER.json', SDK)
    window = parse(read(E / 'WINDOW-START.json', WINDOW))
    console_path = R / (PHASE + '.supervisor.log')
    console_raw = read(console_path, args.expected_console_sha256)
    lines = console_raw.decode('utf-8').splitlines()
    need(len(lines) == 3 and all(lines), 'Complete console must have exactly two stages plus terminal result')
    console = [parse(line) for line in lines]
    need(console[-1] == result, 'Console terminal result differs')
    need(config['phase'] == PHASE and config['source'] == str(R / 'candidate-v35')
         and config['seal'] == 'CANDIDATE-V35-SOURCE-SEAL.json'
         and config['window_seconds'] == 120, 'Exact paired primary configuration differs')
    need(config['additional_sources'] == [
        dict(source=str(R / 'candidate-v28'), seal=str(R / 'CANDIDATE-V28-SOURCE-SEAL.json')),
        dict(source=str(driver_path.parent), seal=str(R / 'WINNER-CLI-PAIRED-DIAGNOSTIC-PROTOCOL-SEAL.json'))],
         'Exact additional v28/protocol source bindings differ')
    expected_plans = [dict(label=label, command=['{python}', '-B', str(driver_path),
        str(R / ('candidate-v' + version)), MODULES[version]], cwd=str(R / ('candidate-v' + version)),
        expected_tests=1, seconds=45, accept_nonzero=True) for version, label in zip(('28', '35'), LABELS)]
    need(config['stages'] == expected_plans, 'Exactly one normal maintained CLI probe per version is required')
    need(result['scope'] == config['scope'] and result['sequence_completed'] is True
         and result['failure'] is None and result['source_seal_unchanged'] is True
         and result['sdk_identity_unchanged'] is True and sdk_before == sdk_after
         and result['remaining_owned_descendants'] == [] and len(result['stages']) == 2,
         'Terminal collection or original stability/cleanup receipt differs')
    need(window['supervisor_sha256'] == SUPERVISOR and window['source_seal_sha256'] == SEALS['35']
         and window['whole_window_seconds'] == 120 and window['python_optimize'] == 0
         and window['runtime_gate_seconds'] == 5, 'Original window metadata differs')
    need(datetime.fromisoformat(result['finished']) >= datetime.fromisoformat(window['started'])
         and 0 <= result['elapsed_seconds'] < 120, 'Terminal chronology/window differs')
    fixed_names = {'RESULT.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'SOURCE-SEAL.json', 'WINDOW-START.json'}
    stage_names = {label + suffix for label in LABELS for suffix in ('-START.json', '-RESULT.json', '.log')}
    expected_names = fixed_names | stage_names | {'LATEST.json', 'PROCESSES.jsonl'}
    need({p.name for p in E.iterdir()} == expected_names, 'Unexpected terminal phase inventory; stop for review')
    stages = []
    for index, (version, label) in enumerate(zip(('28', '35'), LABELS)):
        receipt = parse(read(E / (label + '-RESULT.json'), STAGE_RECEIPTS[version][1]))
        start = parse(read(E / (label + '-START.json'), STAGE_RECEIPTS[version][0]))
        log_raw = read(E / (label + '.log'), receipt['log_sha256'])
        log = log_raw.decode('utf-8')
        argv = [p.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                for p in expected_plans[index]['command']]
        need(receipt == result['stages'][index]
             and all(receipt.get(k) == v for k, v in start.items()), 'Original START/RESULT/terminal mismatch')
        need(receipt['label'] == label and receipt['argv'] == argv
             and receipt['cwd'] == str(R / ('candidate-v' + version))
             and receipt['source_seal_sha256'] == SEALS['35']
             and receipt['stage_timeout_seconds'] == 45 and receipt['timed_out'] is False
             and receipt['leader_reaped'] is True and receipt['remaining_owned_descendants'] == []
             and receipt['test_count'] == receipt['expected_tests'] == 1
             and receipt['skipped_test_count'] == 0, 'Original command/cap/cleanup/count binding differs')
        printed = {k: v for k, v in receipt.items() if k not in ('test_count', 'expected_tests', 'skipped_test_count')}
        need(console[index] == printed, 'Original pre-count-annotation console stage row differs')
        timing = re.findall(r'^Ran (\d+) tests? in ([0-9.]+)s$', log, re.M)
        need(timing == [('1', '30.068' if version == '28' else '29.796')], 'Wrapper method-count/timing differs')
        if version == '28':
            need(receipt['returncode'] == 1 and 'subprocess.TimeoutExpired:' in log
                 and 'timed out after 30 seconds' in log and '\nFAILED (errors=1)\n' in log,
                 'Original v28 child timeout failure is missing')
            outcome = 'FAILED_MAINTAINED_CHILD_TIMEOUT_30_SECONDS'
        else:
            need(receipt['returncode'] == 0 and '\nOK\n' in log
                 and 'consumer verified winner_sign_contracts cli ' in log,
                 'Original v35 wrapper pass is missing')
            outcome = 'PASSED_SINGLE_DIAGNOSTIC_WRAPPER'
        stages.append(dict(version='v' + version, label=label, outcome=outcome,
            returncode=receipt['returncode'], parent_timed_out=receipt['timed_out'],
            child_timeout_observed=version == '28', maintained_child_cap_seconds=30,
            parent_stage_cap_seconds=45, parent_stage_elapsed_seconds=receipt['seconds'],
            wrapper_reported_elapsed_seconds=float(timing[0][1]), wrapper_reported_methods=1,
            actual_primary_source_seal_sha256=receipt['source_seal_sha256'],
            actual_cwd=receipt['cwd'], candidate_source_seal_sha256=SEALS[version],
            maintained_module_sha256=MODULES[version], log_sha256=receipt['log_sha256'],
            start_sha256=SHA(observed[E / (label + '-START.json')]),
            result_sha256=SHA(observed[E / (label + '-RESULT.json')]),
            remaining_owned_descendants=receipt['remaining_owned_descendants']))

    summary = dict(schema=1, kind='derived-paired-diagnostic-summary',
        status='COLLECTION_COMPLETE_MIXED_DIAGNOSTIC_OUTCOMES', diagnostic_only=True,
        collection_completed=True, pair_passed=False, qualification_passed=False,
        timeout_policy_approval_granted=False, original_sequence_completed=result['sequence_completed'],
        sequence_boundary='sequence_completed=true and failure=null mean both outcomes were collected under accept_nonzero=true; they never mean pair PASS or qualification.',
        result_sha256=RESULT, console_sha256=CONSOLE, config_sha256=CONFIG,
        driver_sha256=DRIVER, protocol_seal_sha256=PROTOCOL, supervisor_sha256=SUPERVISOR,
        protocol_review_sha256=REVIEW, protocol_review_bytes_included=False,
        protocol_review_attribution='Exact hashed protocol review attests identical maintained setUp, consumer_script_probe and complete-consumer method bodies; this packet performs no new candidate-source comparison.',
        primary_source_seal_sha256=SEALS['35'], additional_source_seal_sha256=SEALS['28'],
        seal_attribution='Both stage receipts truthfully carry the v35 primary supervisor seal, including the v28 cwd stage. Config additionally binds the v28 source and probe protocol; their seals are preserved separately.',
        sdk_before_sha256=SHA(sdk_before), sdk_after_sha256=SHA(sdk_after),
        source_seal_unchanged=result['source_seal_unchanged'], sdk_identity_unchanged=result['sdk_identity_unchanged'],
        stability_boundary='Source and SDK stability are original supervisor receipts, not new scans or execution.',
        started=window['started'], finished=result['finished'], elapsed_seconds=result['elapsed_seconds'],
        remaining_owned_descendants=result['remaining_owned_descendants'], stages=stages,
        publications=publications, configured_window_seconds=120,
        configured_parent_stage_cap_seconds=45, maintained_child_cap_seconds=30,
        timing_boundary='30.068s and 29.796s are unittest wrapper-reported durations, not exact child-only durations. Parent stage durations are separately recorded. v28 child timeout is not a supervisor 45-second timeout.',
        inference_boundary='One mixed paired observation does not establish a performance improvement, stable headroom, repeatability, or broader normal/optimized CLI/package/direct success.',
        scope='One terminal diagnostic paired normal CLI winner probe on immutable v28/v35. No overall qualification, timeout-policy approval, native/coverage/CI readiness, merge readiness, or issue-completion claim.',
        exclusions='Private review bytes, polling LATEST/PROCESSES bytes, all other phases including active profiling, candidate source contents, repository/SDK images, and historical evidence outside this pair.')
    commands = dict(schema=1, kind='derived-command-and-cap-index', config_sha256=CONFIG,
        supervisor_sha256=SUPERVISOR, window_seconds=120, maintained_child_cap_seconds=30,
        stages=[dict(position_one_based=i + 1, planned=plan, actual=result['stages'][i])
                for i, plan in enumerate(expected_plans)])
    originals = []

    def add(path, name, kind, readable=False):
        data = read(path)
        data.decode('utf-8')
        originals.append(dict(path=name, data=data, kind=kind, original_source=str(path), readable=readable))

    for name in sorted(fixed_names | stage_names):
        add(E / name, 'actual/' + PHASE + '/' + name, 'complete-original-terminal-paired-evidence',
            name in {'RESULT.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'} or name.endswith('.log'))
    add(console_path, 'actual/' + console_path.name, 'complete-original-terminal-supervisor-console', True)
    for name in [PHASE + '.json', 'winner-cli-paired-diagnostic-v35-protocol/probe.py',
                 'WINNER-CLI-PAIRED-DIAGNOSTIC-PROTOCOL-SEAL.json', 'run_checkpoint_matrix.py',
                 'CANDIDATE-V28-SOURCE-SEAL.json', 'CANDIDATE-V35-SOURCE-SEAL.json',
                 'PUBLISHED-V28-QUALIFICATION-BINDING.json', 'PUBLISHED-V35-QUALIFICATION-BINDING.json']:
        add(R / name, 'reproduce/' + name, 'exact-ordinary-protocol-seal-or-publication-reference',
            name == PHASE + '.json' or name.startswith('PUBLISHED-'))
    need(len(originals) == 20 and len({row['path'] for row in originals}) == 20, 'Exact 20-member scope differs')
    patterns = (rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', rb'gh[pousr]_[A-Za-z0-9]{30,}',
                rb'AKIA[0-9A-Z]{16}', rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
    for row in originals:
        need(not any(re.search(pattern, row['data']) for pattern in patterns), 'Credential pattern: ' + row['path'])
        need(not any(word in row['path'].lower() for word in ('review', 'audit', 'profile', 'scratch', 'dream')),
             'Out-of-scope original name: ' + row['path'])
    archive = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
    payloads, members, archived = [], [], []
    for row in sorted(originals, key=lambda row: row['path']):
        data = row['data']
        member = {key: row[key] for key in ('path', 'kind', 'original_source')}
        member.update(bytes=len(data), sha256=SHA(data))
        if row['readable']:
            payloads.append((row['path'], data, 'byte-exact-readable-original'))
            member.update(storage='readable', transport_path=row['path'])
        else:
            archived.append(dict(path=row['path'], bytes=len(data), sha256=SHA(data),
                                 data_base64=base64.b64encode(data).decode('ascii')))
            member.update(storage='container', transport_path=archive)
        members.append(member)
    container = (json.dumps(dict(schema=1, encoding='base64', members=archived),
                           sort_keys=True, separators=(',', ':')) + '\n').encode()
    need(len(container) < LIMIT, 'Reviewed decoder 64 MiB limit exceeded')
    encoded = base64.b64encode(gzip.compress(container, compresslevel=9, mtime=0)) + b'\n'
    need(gzip.decompress(base64.b64decode(encoded.strip(), validate=True)) == container, 'Transport round-trip differs')
    inner = dict(schema=1, original_member_count=len(members), original_member_bytes=sum(r['bytes'] for r in members),
        container=dict(path=archive, encoding='base64 of deterministic gzip mtime=0 containing JSON',
                       members=len(archived), json_bytes=len(container), json_sha256=SHA(container)), members=members)
    guide = '''# Terminal paired normal CLI winner diagnostic

COLLECTION COMPLETE, MIXED OUTCOMES. v28 failed when the maintained child hit
its unchanged 30-second cap; v35 passed this one wrapper. sequence_completed=true
means both outcomes were collected under accept_nonzero=true. It is not pair PASS,
qualification, timeout-policy approval, merge readiness or broader success.

The original unittest wrappers report 30.068s (v28 failure) and 29.796s (v35 pass).
Those are not exact child-only durations. Supervisor stage durations are separate;
neither supervisor hit its 45-second stage cap. The complete window cap was 120s.
One paired observation cannot establish repeatability, performance improvement or
stable timing headroom. No previous failure is rewritten or replaced.

Both original stage receipts carry the v35 primary source seal. The v28 stage
has v28 cwd; config additionally seals v28 and the probe protocol. Original
source seals, SDK before/after, window, config, driver, supervisor, full logs,
START/RESULT receipts, terminal RESULT and entire console are preserved exactly.
Publication bindings are references, not new repository or remote verification.
Protocol review is cited by exact hash only; private review bytes are excluded.
Method identity is attributed to that review, not a new candidate-source scan.

VALIDATION-SUMMARY.json and COMMAND-RECEIPT-SEAL.json are derived indexes.
INNER-MEMBER-MANIFEST.json identifies every complete original by path, size and
SHA256. Container members are base64 JSON in deterministic gzip mtime=0 then
UTF-8 base64. No evidence is truncated, normalized or replaced by its summary.
The outer manifest seals every payload except itself.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The copied, hash-bound decoder verifies paths, sizes and hashes without executing
or unmarshaling evidence. No profile files are included or read. Builder output is
create-only and requires explicit exact terminal RESULT/console/builder hashes.
'''
    payloads += [(archive, encoded, 'lossless-original-paired-evidence'),
        ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-member-inventory'),
        ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-mixed-diagnostic-summary'),
        ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-exact-command-and-cap-index'),
        ('decode_verify.py', decoder, 'hash-bound-safe-decoder-no-execution'),
        ('reproduce/' + Path(__file__).name, builder, 'source-only-packet-builder'),
        ('README.md', guide.encode(), 'scope-and-safe-transport-guide')]
    need(len(payloads) == len({name for name, _, _ in payloads}) <= 25, 'Payload names/count differ')
    need({p.name for p in E.iterdir()} == expected_names, 'Terminal directory membership changed')
    for path, data in observed.items():
        need(raw(path) == data, 'Consumed input changed during packaging: ' + str(path))
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
        original_members=len(members), archived_members=len(archived), original_bytes=inner['original_member_bytes'],
        status=summary['status'], collection_completed=True, pair_passed=False, qualification_passed=False,
        packet_bytes_including_manifest=sum(row['bytes'] for row in rows) + len(raw(manifest))), sort_keys=True))


if __name__ == '__main__':
    main()
