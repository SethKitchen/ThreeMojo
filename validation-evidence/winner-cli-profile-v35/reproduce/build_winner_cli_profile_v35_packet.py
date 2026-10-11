"""Freeze one completed diagnostic profile as byte-exact, create-only transport.

Source review and explicit release are required before execution. Stdlib only;
never imports/executes protocol or candidate code, scans candidates, runs tests,
starts a new profile, reads polling bytes, or reads another evidence phase.
profile.pstats is opaque bytes only: never loaded, unmarshaled, or unpickled.
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
PHASE = 'winner-cli-profile-v35'
E = R / 'evidence' / PHASE
O = R / 'validation-evidence-winner-cli-profile-v35-terminal-packet'
LABEL = 'v35-normal-cli-winner-profile'
DECODER_SOURCE = 'validation-evidence-qualification-policy-v23-packet/decode_verify.py'
FINAL_REVIEW = 'winner-cli-profile-v35-independent-review/FINAL-REVIEW.json'
SOURCE_REVIEW = 'winner-cli-profile-v35-independent-review/SOURCE-AUDIT.json'
LIMIT = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()

PHASE_NAMES = ['CHILD-stderr.log',
 'CHILD-stdout.log',
 'EXACT-PROFILE-RESULT.json',
 'EXACT-PROFILE-START.json',
 'FIXTURE-SOURCE-SEAL.json',
 'MAINTAINED-CHILD.json',
 'RAW-PROFILE.json',
 'RESULT.json',
 'SDK-AFTER.json',
 'SDK-BEFORE.json',
 'SOURCE-SEAL.json',
 'WINDOW-START.json',
 'profile.pstats',
 'v35-normal-cli-winner-profile-RESULT.json',
 'v35-normal-cli-winner-profile-START.json',
 'v35-normal-cli-winner-profile.log']
ORIGINAL_NAMES = ['evidence/winner-cli-profile-v35/CHILD-stderr.log',
 'evidence/winner-cli-profile-v35/CHILD-stdout.log',
 'evidence/winner-cli-profile-v35/EXACT-PROFILE-RESULT.json',
 'evidence/winner-cli-profile-v35/EXACT-PROFILE-START.json',
 'evidence/winner-cli-profile-v35/FIXTURE-SOURCE-SEAL.json',
 'evidence/winner-cli-profile-v35/MAINTAINED-CHILD.json',
 'evidence/winner-cli-profile-v35/RAW-PROFILE.json',
 'evidence/winner-cli-profile-v35/RESULT.json',
 'evidence/winner-cli-profile-v35/SDK-AFTER.json',
 'evidence/winner-cli-profile-v35/SDK-BEFORE.json',
 'evidence/winner-cli-profile-v35/SOURCE-SEAL.json',
 'evidence/winner-cli-profile-v35/WINDOW-START.json',
 'evidence/winner-cli-profile-v35/profile.pstats',
 'evidence/winner-cli-profile-v35/v35-normal-cli-winner-profile-RESULT.json',
 'evidence/winner-cli-profile-v35/v35-normal-cli-winner-profile-START.json',
 'evidence/winner-cli-profile-v35/v35-normal-cli-winner-profile.log',
 'winner-cli-profile-v35.supervisor.log',
 'winner-cli-profile-v35.json',
 'winner-cli-profile-v35-protocol/driver.py',
 'winner-cli-profile-v35-protocol/profile_child.py',
 'WINNER-CLI-PROFILE-V35-PROTOCOL-SEAL.json',
 'CANDIDATE-V35-SOURCE-SEAL.json',
 'run_checkpoint_matrix.py',
 'PUBLISHED-V35-QUALIFICATION-BINDING.json']
PINS = {'evidence/winner-cli-profile-v35/CHILD-stderr.log': '3628f785e24fcdeb92c7419e238211e53a0a4ab061a547f8bc7b05606d3bc15c',
 'evidence/winner-cli-profile-v35/CHILD-stdout.log': '8c38b472857aa0cbfe21761c5e657bd4607a2730d176f775d562de6c63ec8605',
 'evidence/winner-cli-profile-v35/EXACT-PROFILE-RESULT.json': '65c6ae65a2213835f45dffb5ca2a121e47b2f08301632c657b881ecd1d64d6dd',
 'evidence/winner-cli-profile-v35/EXACT-PROFILE-START.json': 'd3a3cb2cdadf93b0ee267d25ab60540f1ae2623f39f8fd6cef65df8b42b522d7',
 'evidence/winner-cli-profile-v35/FIXTURE-SOURCE-SEAL.json': 'c26ac411494c0b56cea87bd5bc82902f0108801c83ee1ba689d2ceddb7d6da0f',
 'evidence/winner-cli-profile-v35/MAINTAINED-CHILD.json': '146aaa7ec224e825783cdcc92c97b8df551c1d8a990567ba6624dca2f8af2c55',
 'evidence/winner-cli-profile-v35/RAW-PROFILE.json': '68cffda4850cb4f502b434bfc3408e24e67de64090e8dac58c2c11388ba1aaa6',
 'evidence/winner-cli-profile-v35/RESULT.json': '380b86448d34aeca2ae7664f9f9733859570bb3b52c19d36c94798c365faa517',
 'evidence/winner-cli-profile-v35/SDK-AFTER.json': '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
 'evidence/winner-cli-profile-v35/SDK-BEFORE.json': '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207',
 'evidence/winner-cli-profile-v35/SOURCE-SEAL.json': '020a72e9ceb1e45bf31559b624b5d328fd4a6e6414aafbdba5259b71af9fd7cc',
 'evidence/winner-cli-profile-v35/WINDOW-START.json': '8a1a1d11f651af687ce27ba1ea8f765e6d7350a8212718aca237051e4c305c9a',
 'evidence/winner-cli-profile-v35/profile.pstats': '742788c8526c299403735f3658bc8bf0f1b183e3107ed065cdf7607db6f5700d',
 'evidence/winner-cli-profile-v35/v35-normal-cli-winner-profile-RESULT.json': '7242dc38e0532406b6b1b4be8044941a9f51f0f032b63cb2a370e9d7c8e4f399',
 'evidence/winner-cli-profile-v35/v35-normal-cli-winner-profile-START.json': '5ab67d918757f91f834a5fb7c8f4f0242ca7d2a4507179eb6d2a707b8deeec89',
 'evidence/winner-cli-profile-v35/v35-normal-cli-winner-profile.log': '7e21d40579b568c28bc3dad5d9f8460395bd97a0035b9cab492911a0d5f8ea11',
 'winner-cli-profile-v35.supervisor.log': '9549db47ba01a78717df70204661b0ec38121c054d6a5fe778f3df9d11efbad6',
 'winner-cli-profile-v35.json': '396f03afe2320cf05950be381b8dc21a90255e74c6af62d48177f4df9c6e1015',
 'winner-cli-profile-v35-protocol/driver.py': 'f5aacc65696f58bed07cbbf676660505affac39721988cf030d72c1ec84ff306',
 'winner-cli-profile-v35-protocol/profile_child.py': '35f771217ff71d6a8926f4fc6ca2cf9b3e98d77082e573110a36ba60c93d0cdd',
 'WINNER-CLI-PROFILE-V35-PROTOCOL-SEAL.json': '883fbbe9824ae72a862af6e49dc3c000942bf7089f505aa8aeb00435484f6784',
 'CANDIDATE-V35-SOURCE-SEAL.json': '020a72e9ceb1e45bf31559b624b5d328fd4a6e6414aafbdba5259b71af9fd7cc',
 'run_checkpoint_matrix.py': '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032',
 'PUBLISHED-V35-QUALIFICATION-BINDING.json': '9f7159cc980b51da7be9ed5b3822cbb0a8c88977794200cf6b24315f9c4a8e2c',
 'validation-evidence-qualification-policy-v23-packet/decode_verify.py': 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4',
 'winner-cli-profile-v35-independent-review/FINAL-REVIEW.json': '41faeb392a8bc7bb735ddad72cb54dc284e1b31323cf72fe113b84876318858d',
 'winner-cli-profile-v35-independent-review/SOURCE-AUDIT.json': '42370393b2c18697969db246da9ed92e465639c4184bd2433878d90764aaca11'}


def need(condition, message):
    if not condition:
        raise ValueError(message)


def raw(path):
    relative = path.relative_to(R)
    need(relative.parts and all(p not in ('', '.', '..') for p in relative.parts), 'Unsafe path')
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
    prefix = 'evidence/' + PHASE + '/'
    need(args.expected_result_sha256 == PINS[prefix + 'RESULT.json']
         and args.expected_console_sha256 == PINS[PHASE + '.supervisor.log'],
         'Only the reviewed exact completed profile attempt is supported')
    need(not O.exists() and not O.is_symlink(), 'Create-only output already exists')
    observed = {}

    def read(name):
        need(name in PINS, 'Input not on the exact read allowlist: ' + name)
        data = raw(R / name)
        need(SHA(data) == PINS[name], 'Changed exact input binding: ' + name)
        need(name not in observed or observed[name] == data, 'Input changed: ' + name)
        observed[name] = data
        return data

    def evidence(name):
        return read(prefix + name)

    # Read terminal receipt first. No polling or partial packaging is supported.
    result = parse(evidence('RESULT.json'))
    builder_path = Path(__file__).resolve()
    builder = raw(builder_path)
    need(SHA(builder) == args.expected_builder_sha256, 'Reviewed builder hash differs')
    expected_names = set(PHASE_NAMES) | {'LATEST.json', 'PROCESSES.jsonl'}
    need(len(PHASE_NAMES) == 16 and {p.name for p in E.iterdir()} == expected_names,
         'Unexpected terminal phase inventory; stop for review')
    originals = []
    readable_phase = {'RESULT.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json',
                     'EXACT-PROFILE-START.json', 'EXACT-PROFILE-RESULT.json', 'MAINTAINED-CHILD.json',
                     LABEL + '-START.json', LABEL + '-RESULT.json',
                     'CHILD-stdout.log', 'CHILD-stderr.log', LABEL + '.log'}
    for name in ORIGINAL_NAMES:
        data = read(name)
        is_phase = name.startswith(prefix)
        leaf = name[len(prefix):] if is_phase else name
        binary = name == prefix + 'profile.pstats'
        if not binary:
            data.decode('utf-8')
        target = ('actual/' + PHASE + '/' + leaf if is_phase else
                  'actual/' + name if name == PHASE + '.supervisor.log' else 'reproduce/' + name)
        readable = (is_phase and leaf in readable_phase) or name in {
            PHASE + '.supervisor.log', PHASE + '.json', 'PUBLISHED-V35-QUALIFICATION-BINDING.json'}
        originals.append(dict(path=target, data=data, original_source=str(R / name),
            readable=readable, kind='opaque-binary-profile-original' if binary else 'byte-exact-original',
            identity_basis='newly-frozen-transport-identity-not-generation-time-receipt' if binary
                           else 'frozen-original-byte-identity'))
    need(len(originals) == len({row['path'] for row in originals}) == 24,
         'Exact 24-original inventory differs')
    decoder = read(DECODER_SOURCE)
    # These two source reviews are checked and cited only; their bytes are excluded.
    review = parse(read(FINAL_REVIEW))
    source_review = parse(read(SOURCE_REVIEW))
    config = parse(read(PHASE + '.json'))
    protocol = parse(read('WINNER-CLI-PROFILE-V35-PROTOCOL-SEAL.json'))
    driver = PINS['winner-cli-profile-v35-protocol/driver.py']
    child = PINS['winner-cli-profile-v35-protocol/profile_child.py']
    seal_hash = PINS['CANDIDATE-V35-SOURCE-SEAL.json']
    supervisor = PINS['run_checkpoint_matrix.py']
    sdk_hash = PINS[prefix + 'SDK-BEFORE.json']
    need(protocol == {'driver.py': driver, 'profile_child.py': child}, 'Protocol seal differs')
    need(review['verdict'] == 'APPROVE_EXACT_ONE_PROFILE_OUTER_CONFIGURATION_FOR_PARENT_AUTHORIZED_LAUNCH'
         and review['config_sha256'] == PINS[PHASE + '.json']
         and review['source_audit_sha256'] == PINS[SOURCE_REVIEW]
         and review['protocol_seal_sha256'] == PINS['WINNER-CLI-PROFILE-V35-PROTOCOL-SEAL.json']
         and review['source_seal_sha256'] == seal_hash and review['supervisor_sha256'] == supervisor
         and review['sdk_receipt_sha256'] == sdk_hash
         and [review[k] for k in ('profile_alarm_seconds', 'driver_child_seconds',
                                 'one_normal_stage_seconds', 'orchestration_window_seconds')]
             == [100, 112, 120, 150], 'Exact final protocol review binding differs')
    need(source_review['driver_sha256'] == driver and source_review['profile_child_sha256'] == child,
         'Exact source review binding differs')
    source_seal = parse(read('CANDIDATE-V35-SOURCE-SEAL.json'))
    need(evidence('SOURCE-SEAL.json') == read('CANDIDATE-V35-SOURCE-SEAL.json'), 'Original source seals differ')
    need(evidence('SDK-BEFORE.json') == evidence('SDK-AFTER.json'), 'Original SDK receipts differ')
    publication = parse(read('PUBLISHED-V35-QUALIFICATION-BINDING.json'))
    need(publication['source_seal_sha256'] == seal_hash
         and publication['published_commit'] == '19287a0b1564b9a628f15c96e7675c51413ca1a9'
         and publication['published_tree'] == '5c1f67c196fc30d6a323d6d854748b65e3640585',
         'Publication/source reference differs')
    driver_path = R / 'winner-cli-profile-v35-protocol/driver.py'
    plan = dict(label=LABEL, command=['{python}', '-B', str(driver_path), '{evidence}'], seconds=120)
    need(config['phase'] == PHASE and config['source'] == str(R / 'candidate-v35')
         and config['seal'] == 'CANDIDATE-V35-SOURCE-SEAL.json'
         and config['window_seconds'] == 150 and config['stages'] == [plan]
         and config['additional_sources'] == [dict(source=str(driver_path.parent),
              seal=str(R / 'WINNER-CLI-PROFILE-V35-PROTOCOL-SEAL.json'))], 'Exact one-stage config differs')
    window = parse(evidence('WINDOW-START.json'))
    outer_start = parse(evidence(LABEL + '-START.json'))
    outer = parse(evidence(LABEL + '-RESULT.json'))
    exact_start = parse(evidence('EXACT-PROFILE-START.json'))
    exact = parse(evidence('EXACT-PROFILE-RESULT.json'))
    payload = parse(evidence('MAINTAINED-CHILD.json'))
    fixture_seal = parse(evidence('FIXTURE-SOURCE-SEAL.json'))
    profile = parse(evidence('RAW-PROFILE.json'))
    console_lines = read(PHASE + '.supervisor.log').decode('utf-8').splitlines()
    need(len(console_lines) == 2 and all(console_lines), 'Full console requires one stage and terminal result')
    need([parse(line) for line in console_lines] == [outer, result], 'Console receipts differ')
    need(result['stages'] == [outer] and all(outer.get(k) == v for k, v in outer_start.items()),
         'Outer START/RESULT/terminal bindings differ')
    need(result['scope'] == config['scope'] and result['sequence_completed'] is True
         and result['failure'] is None and result['source_seal_unchanged'] is True
         and result['sdk_identity_unchanged'] is True and result['remaining_owned_descendants'] == [],
         'Terminal completion/stability/cleanup receipt differs')
    python = str(R.parent / 'restored-toolchain/official-venv/bin/python')
    need(outer['argv'] == [python, '-B', str(driver_path), str(E)]
         and outer['cwd'] == str(R / 'candidate-v35') and outer['label'] == LABEL
         and outer['stage_timeout_seconds'] == 120 and outer['source_seal_sha256'] == seal_hash
         and outer['returncode'] == 0 and outer['timed_out'] is False
         and outer['leader_reaped'] is True and outer['remaining_owned_descendants'] == []
         and outer['log_sha256'] == PINS[prefix + LABEL + '.log'], 'Outer command/cap/result differs')
    need(window['supervisor_sha256'] == supervisor and window['source_seal_sha256'] == seal_hash
         and window['whole_window_seconds'] == 150 and window['python_optimize'] == 0
         and window['runtime_gate_seconds'] == 5, 'Original window receipt differs')
    need(datetime.fromisoformat(result['finished']) >= datetime.fromisoformat(window['started'])
         and 0 <= result['elapsed_seconds'] < 150 and 0 <= outer['seconds'] < 120,
         'Terminal chronology/window differs')
    need(all(exact.get(k) == v for k, v in exact_start.items())
         and parse(evidence(LABEL + '.log')) == exact, 'Exact START/RESULT/full log differ')
    need(exact['diagnostic_completed'] is True and exact['diagnostic_only'] is True
         and exact['qualification_passed'] is False and exact['returncode'] == 0
         and exact['timed_out'] is False and exact['profile_status'] == 'completed'
         and exact['profile_error'] is None and exact['fixture_unchanged'] is True
         and exact['fixture_removed'] is True and 'driver_error' not in exact
         and 'cleanup_error' not in exact, 'Completed diagnostic/cleanup receipt differs')
    need([exact[k] for k in ('profile_work_cap_seconds', 'driver_child_cap_seconds',
                            'outer_supervisor_cap_seconds', 'maintained_child_cap_seconds')]
         == [100, 112, 120, 30], 'Profile/driver/outer/historical-maintained caps differ')
    for key, expected in dict(driver_sha256=driver, profiler_sha256=child,
        source_seal_sha256=seal_hash, sdk_before_receipt_sha256=sdk_hash,
        test_source_sha256=source_seal['tools/test_coverage_loop_proofs.py'],
        helper_sha256=source_review['helper_sha256'], script_sha256=source_review['embedded_script_sha256'],
        payload_sha256=PINS[prefix + 'MAINTAINED-CHILD.json'],
        fixture_source_seal_sha256=PINS[prefix + 'FIXTURE-SOURCE-SEAL.json'],
        raw_profile_sha256=PINS[prefix + 'RAW-PROFILE.json'],
        stdout_sha256=PINS[prefix + 'CHILD-stdout.log'], stderr_sha256=PINS[prefix + 'CHILD-stderr.log']).items():
        need(exact[key] == expected, 'Exact child input/output binding differs: ' + key)
    need(payload['mode'] == 'normal' and payload['consumer'] == 'winner_sign_contracts'
         and payload['root'] == str(R / 'candidate-v35')
         and payload['original_command'] == exact['maintained_argv']
         and payload['original_command'] == [python, '-E', '-B'] + payload['maintained_argv']
         and payload['cwd'] == exact['cwd'] and payload['script_sha256'] == exact['script_sha256']
         and len(fixture_seal) == 196
         and fixture_seal['tools/probe_consumers.py'] == exact['script_sha256'],
         'Historical maintained payload/fixture binding differs')
    need(profile['status'] == 'completed' and profile['error'] is None and profile['optimize'] == 0
         and profile['raw_code_identities_preserved_before_pstats'] is True
         and profile['maintained_argv'] == payload['maintained_argv']
         and profile['payload_sha256'] == exact['payload_sha256']
         and profile['script_sha256'] == exact['script_sha256']
         and profile['profiled_work_elapsed_seconds'] == exact['profiled_work_elapsed_seconds']
         and [profile[k] for k in ('work_cap_seconds', 'driver_child_cap_seconds',
                                  'outer_supervisor_cap_seconds')] == [100, 112, 120]
         and len(profile['entries']) == 1023 and len(profile['module_bindings']) == 1325,
         'Raw identity-preserving profile metadata differs')
    need(b'consumer verified winner_sign_contracts cli ' in evidence('CHILD-stdout.log'),
         'Maintained child success marker absent')
    need(evidence('CHILD-stderr.log').startswith(b'Timeout (0:00:50)!'),
         'Original scheduled faulthandler diagnostic is absent')
    # Raw profile JSON is retained as its exact original bytes, never regenerated
    # from this parsed metadata. The binary file is never parsed or text-decoded.
    summary = dict(schema=1, kind='derived-single-profile-diagnostic-summary',
        status='COMPLETED_SINGLE_PROFILE_DIAGNOSTIC_ONLY', diagnostic_only=True,
        collection_completed=True, diagnostic_completed=True, qualification_passed=False,
        maintained_30_second_acceptance_credit=False, stable_timing_headroom_credit=False,
        timeout_policy_approval_granted=False, source_seal_sha256=seal_hash,
        result_sha256=PINS[prefix + 'RESULT.json'], console_sha256=PINS[PHASE + '.supervisor.log'],
        config_sha256=PINS[PHASE + '.json'], driver_sha256=driver, profile_child_sha256=child,
        protocol_seal_sha256=PINS['WINNER-CLI-PROFILE-V35-PROTOCOL-SEAL.json'],
        supervisor_sha256=supervisor, protocol_final_review_sha256=PINS[FINAL_REVIEW],
        protocol_source_review_sha256=PINS[SOURCE_REVIEW], private_review_bytes_included=False,
        raw_profile_sha256=PINS[prefix + 'RAW-PROFILE.json'], raw_profile_bytes=len(evidence('RAW-PROFILE.json')),
        raw_profile_entries=1023, raw_profile_module_bindings=1325,
        raw_code_identities_preserved_before_pstats=profile['raw_code_identities_preserved_before_pstats'],
        raw_identity_attribution='Byte-exact original RAW-PROFILE.json and hash-bound profiler source preserve the recorded per-entry/code-object and caller/callee identities; no pstats reconstruction or code-tuple coalescing is performed.',
        counts_boundary='Profile entered-call counts are not completed admissions; repeated names may be different code identities. No aggregate hotspot or admission inference is made.',
        pstats=dict(bytes=len(evidence('profile.pstats')), sha256=PINS[prefix + 'profile.pstats'],
            representation='opaque binary in base64 member transport', content_loaded_or_executed=False,
            identity_basis='Newly frozen terminal transport identity; driver RESULT records no generation-time pstats digest.'),
        profile_work_cap_seconds=100, driver_child_cap_seconds=112, outer_stage_cap_seconds=120,
        window_cap_seconds=150, historical_maintained_qualification_cap_seconds=30,
        profiled_work_elapsed_seconds=exact['profiled_work_elapsed_seconds'],
        driver_elapsed_seconds=exact['seconds'], outer_stage_elapsed_seconds=outer['seconds'],
        whole_window_elapsed_seconds=result['elapsed_seconds'], started=window['started'], finished=result['finished'],
        source_seal_unchanged=result['source_seal_unchanged'], sdk_identity_unchanged=result['sdk_identity_unchanged'],
        sdk_before_sha256=sdk_hash, sdk_after_sha256=PINS[prefix + 'SDK-AFTER.json'],
        fixture_unchanged=exact['fixture_unchanged'], fixture_removed=exact['fixture_removed'],
        fixture_sealed_members=196, scheduled_faulthandler_dump_seconds=50,
        stderr_boundary='Full stderr contains the scheduled faulthandler Timeout (0:00:50)! stack dump. This is a diagnostic traceback, not an enforced timeout; raw status is completed and driver timed_out=false.',
        remaining_owned_descendants=result['remaining_owned_descendants'],
        stability_boundary='Source/SDK/fixture stability and cleanup are original receipts; packaging makes no new candidate, SDK, process, or removed-fixture checks.',
        historical_maintained_script=dict(path=payload['script'], sha256=payload['script_sha256'],
            bytes_included=False, reconstructed=False, attribution='Removed temporary script identity and argv retained only as original historical receipts; exact driver/child means the two protocol source files.'),
        publication_reference=dict(binding_sha256=PINS['PUBLISHED-V35-QUALIFICATION-BINDING.json'],
            commit=publication['published_commit'], tree=publication['published_tree'],
            attribution='Preserved reference only; no new repository or remote verification.'),
        timing_boundary='Instrumentation affects timing. The measured profile, driver, outer-stage and whole-window intervals are distinct; none gives plain maintained 30-second acceptance or timing headroom credit.',
        scope='One completed normal CLI winner diagnostic profile on v35; no overall qualification, maintained 30-second acceptance, performance improvement, timeout-policy approval, native/coverage/CI readiness, merge readiness, or issue completion.',
        exclusions='Polling LATEST/PROCESSES bytes, private review/design bytes, all other phases, candidate source contents, SDK images, and removed temporary maintained script bytes.')
    commands = dict(schema=1, kind='derived-command-cap-and-original-receipt-index',
        config_sha256=PINS[PHASE + '.json'], supervisor_sha256=supervisor,
        planned_outer_stage=plan, original_outer_start=outer_start, original_outer_result=outer,
        original_exact_profile_start=exact_start, original_exact_profile_result=exact,
        original_maintained_payload=payload, window_seconds=150,
        profile_work_cap_seconds=100, driver_child_cap_seconds=112, outer_stage_cap_seconds=120,
        historical_maintained_qualification_cap_seconds=30, qualification_passed=False)
    patterns = (rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', rb'gh[pousr]_[A-Za-z0-9]{30,}',
                rb'AKIA[0-9A-Z]{16}', rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
    for row in originals:
        need(not any(re.search(pattern, row['data']) for pattern in patterns), 'Credential pattern: ' + row['path'])
        need(not any(word in row['path'].lower() for word in ('review', 'audit', 'scratch', 'dream')),
             'Private original name: ' + row['path'])
    archive = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
    payloads, members, archived = [], [], []
    for row in sorted(originals, key=lambda row: row['path']):
        data = row['data']
        member = {key: row[key] for key in ('path', 'kind', 'original_source', 'identity_basis')}
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
    need(gzip.decompress(base64.b64decode(encoded.strip(), validate=True)) == container,
         'Transport round-trip differs')
    inner = dict(schema=1, original_member_count=len(members), original_member_bytes=sum(r['bytes'] for r in members),
        container=dict(path=archive, encoding='base64 of deterministic gzip mtime=0 containing JSON',
                       members=len(archived), json_bytes=len(container), json_sha256=SHA(container)), members=members)
    guide = '''# Completed single normal CLI winner profile diagnostic

COMPLETED DIAGNOSTIC ONLY. qualification_passed=false. The profile used a
100-second work alarm, 112-second driver watchdog, 120-second outer stage,
and 150-second whole window. The maintained qualification cap remains 30 seconds.
Instrumented completion provides no maintained 30-second acceptance, timing
headroom, repeatability, performance improvement, readiness, or policy credit.
Earlier failures remain unchanged. Full stderr includes the scheduled 50-second
faulthandler stack dump labeled Timeout (0:00:50)!. It is not an enforced timeout;
the raw profile completed and the driver recorded timed_out=false.

All 16 terminal phase originals except polling LATEST/PROCESSES are preserved,
plus full supervisor console, exact config, two protocol source files, protocol
seal, v35 source seal, supervisor, and publication reference: 24 originals.
Exact driver/child means driver.py and profile_child.py. The removed temporary
maintained script is historical argv/hash evidence only, never reconstructed.
Private source-review bytes are excluded and their hashes only are cited.
Source/SDK/fixture stability and cleanup are original receipts, not fresh scans.

RAW-PROFILE.json is preserved byte for byte with 1,023 raw entries and 1,325
module bindings, including code-object/per-entry and caller/callee identities.
The original profile source writes raw identities before pstats. Entered calls
must not be treated as completed admissions or coalesced by filename/line/name.
profile.pstats is an opaque binary base64 member, never loaded, unmarshaled,
unpickled, or executed. Its size/hash are newly frozen transport identity;
the driver did not record a generation-time pstats digest.

VALIDATION-SUMMARY.json and COMMAND-RECEIPT-SEAL.json are derived indexes.
INNER-MEMBER-MANIFEST.json lists every complete original path, size, and SHA256.
Archived originals use base64 JSON in deterministic gzip mtime=0, then UTF-8
base64. No original is truncated, normalized, or replaced with its summary.
The outer manifest seals every payload except itself.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The unchanged hash-bound decoder verifies transport paths, sizes, and hashes
without executing or interpreting original source or binary profile evidence.
Builder output is create-only and requires exact RESULT/console/builder hashes.
'''
    payloads += [(archive, encoded, 'lossless-original-profile-evidence'),
        ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-member-inventory'),
        ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-completed-diagnostic-summary'),
        ('COMMAND-RECEIPT-SEAL.json', JSON(commands), 'derived-command-cap-and-receipt-index'),
        ('decode_verify.py', decoder, 'unchanged-hash-bound-safe-decoder'),
        ('reproduce/' + builder_path.name, builder, 'source-only-packet-builder'),
        ('README.md', guide.encode(), 'scope-and-safe-transport-guide')]
    need(len(payloads) == len({name for name, _, _ in payloads}) <= 25, 'Payload names/count differ')
    need(set(observed) == set(PINS), 'Read allowlist inventory differs')
    need({p.name for p in E.iterdir()} == expected_names, 'Terminal directory membership changed')
    for name, data in observed.items():
        need(raw(R / name) == data, 'Consumed input changed during packaging: ' + name)
    need(raw(builder_path) == builder, 'Builder changed during packaging')
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
        status=summary['status'], diagnostic_completed=True, qualification_passed=False,
        content_executed_or_unmarshaled=False,
        packet_bytes_including_manifest=sum(row['bytes'] for row in rows) + len(raw(manifest))), sort_keys=True))


if __name__ == '__main__':
    main()
