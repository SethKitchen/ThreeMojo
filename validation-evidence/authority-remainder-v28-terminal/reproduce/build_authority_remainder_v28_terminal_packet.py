"""Create the separate terminal v28 remaining-authority diagnostic packet, without execution.

Run ONLY after terminal notification and independent review. Required expected
RESULT and console hashes are supplied from that completed run, never inferred.
No candidate-tree access, project imports, tests, native tools, or uploads.
"""
from pathlib import Path
from datetime import datetime, timedelta
import argparse
import base64
from collections import Counter
import gzip
import hashlib
import json
import re
import stat

R = Path(__file__).resolve().parent
PHASE = 'full-authority-remainder-diagnostic-v28'
E = R / 'evidence' / PHASE
O = R / 'validation-evidence-authority-remainder-v28-terminal-packet'
SEAL = 'fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596'
SDK = '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
SUP = 'babd45e70e47e356406a44c22bc9e4cc1174375b580358dcf3ad52cfe97209fa'
CONFIG = 'da984c94b930ae80ad1ce8fdfc5b0cf488e737648612457c9ad5bfccf4a89712'
PRIOR_RESULT = '0e76f5398b6bb4244b9b7f65c76408d26e40ccfaf7b1b35d31589f07fbc3d493'
PRIOR_CONFIG = '7aa23228e0b9ea130fe3c25fe376e5210c105beb761793bab4a40fa2300a1d39'
PRIOR_SUP = 'df6da89f3b8c3c6790c2c2c1eb414cf3677674165203a30c8224d632f26a3b84'
PRIOR_PACKET = '63cbcc7b6b81e15c723be42c53f8070c324a202e2c63f5b5ce857b3c2a90ab2e'
COMPLETION_INVENTORY = '99654f1fd1b274373585a63afd2e058f037963866d5919ac77500384e7151a41' 
PRIOR_LOG = '4e5b2afbede85bc9565f73e69086853d83d140835d30f2a0cc390b2ace8716e8'
PROTOCOL_REVIEW = '8453bee485a28022bb1641611cf2fe38b0cf9fdac15ff97d88fe0ce3e395fa28'
PROTOCOL_AUDIT = '042aaa7eba668ed8ff720fd7b6a606f7145e36c2a7f2db8840cd0ba15f754cc6'
INVENTORY = '0996f6650319b26da030bcfccf85868e2eba6b755a46063bec9daabfd796a2f9'
ORIGINAL_RESULT = 'a2d054ac36ac97e729d292956a2233f10b479b6f40194fec90c9f088858be844'
ORIGINAL_CONFIG = 'b078e691b04f3e2acfee6c1ddcd4f0ca934b500062593bb72d24592e882e7f5a'
ORIGINAL_PACKET = '383041f192e2537a1071baec1fb691d52490fb187f84350ce05843fcd61f4a78'
PUBLICATION = '0df492bd6c870ecb2e8a6d3cb66167c2d5042aa7ba0a70d4b42f02f71eef8bdf'
DECODER = 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4'
DISCOVERY = '983724ca988e0cabee988c5f8dc4c2cf47613f5afe73c9dd4d743729d5c6a9c1'
DEADLINE = '2026-10-11T08:35:38.016452+00:00'
LIMIT = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def raw(path):
    need(stat.S_ISREG(path.lstat().st_mode), 'Not a regular non-symlink file: ' + str(path))
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

    # This check precedes every read of the active authority remainder evidence or console.
    # Absence of RESULT never triggers waiting, polling, or partial packaging.
    need((E / 'RESULT.json').is_file(), 'Refuse: authority remainder RESULT.json is absent; collection is not terminal')
    need(not O.exists() and not O.is_symlink(), 'Never overwrite an evidence packet')
    observed = {}

    def read(path, expected=None):
        data = raw(path)
        if expected is not None:
            need(SHA(data) == expected, 'Changed exact binding: ' + str(path))
        if path in observed:
            need(observed[path] == data, 'Input changed while reading: ' + str(path))
        observed[path] = data
        return data

    builder = read(Path(__file__).resolve(), args.expected_builder_sha256)
    result_raw = read(E / 'RESULT.json', args.expected_result_sha256)
    result = parse(result_raw)
    config_raw = read(R / (PHASE + '.json'), CONFIG)
    config = parse(config_raw)
    read(R / 'run_authority_remainder_diagnostic_v28.py', SUP)
    seal_raw = read(R / 'CANDIDATE-V28-SOURCE-SEAL.json', SEAL)
    seal = parse(seal_raw)
    need(read(E / 'SOURCE-SEAL.json', SEAL) == seal_raw, 'Executed source seal differs')
    window = parse(read(E / 'WINDOW-START.json'))
    sdk_before = read(E / 'SDK-BEFORE.json', SDK)
    sdk_after = read(E / 'SDK-AFTER.json')
    console_path = R / (PHASE + '.supervisor.log')
    console_raw = read(console_path, args.expected_console_sha256)
    console_lines = console_raw.decode('utf-8').splitlines()
    need(bool(console_lines) and all(console_lines), 'Empty console or blank console row')
    console = [parse(line) for line in console_lines]
    need(console[-1] == result, 'Refuse: exact console has no matching terminal result row')
    need(result['diagnostic_only'] is True and result['qualification_passed'] is False,
         'Terminal receipt must remain diagnostic only')
    need(type(result['sequence_completed']) is bool and result['scope'] == config['scope'], 'Terminal scope')
    need(result['source_seal_unchanged'] is True, 'Supervisor did not attest unchanged source')
    need(result['sdk_identity_unchanged'] is (parse(sdk_before) == parse(sdk_after)), 'SDK comparison differs')
    need(isinstance(result['remaining_owned_descendants'], list), 'Missing final descendant receipt')
    need(config['phase'] == PHASE and config['diagnostic_only'] is True and config['qualification_passed'] is False,
         'Exact diagnostic configuration')
    need(config['source'] == str(R / 'candidate-v28') and config['seal'] == 'CANDIDATE-V28-SOURCE-SEAL.json'
         and config['source_seal_sha256'] == SEAL, 'Source configuration binding')
    need(window['supervisor_sha256'] == config['supervisor_sha256'] == SUP
         and window['source_seal_sha256'] == SEAL and window['python_optimize'] == 0
         and window['runtime_gate_seconds'] == 5, 'Original supervisor/window identity')
    need(window['whole_window_seconds'] == config['window_seconds'] == result['whole_window_seconds'] == 6000
         and result['window_policy'] == config['window_policy'] == 'independent-bounded-authority-remainder',
         'Independent completion window differs')
    prior_path = R / 'evidence/full-python-diagnostic-completion-v28/RESULT.json'
    prior = parse(read(prior_path, PRIOR_RESULT))
    prior_config = parse(read(R / 'full-python-diagnostic-completion-v28.json', PRIOR_CONFIG))
    read(R / 'run_diagnostic_completion_v28.py', PRIOR_SUP)
    prior_sdk_path = R / 'evidence/full-python-diagnostic-completion-v28/SDK-AFTER.json'
    need(read(prior_sdk_path, SDK) == sdk_before, 'Completion SDK differs from sealed prior SDK')
    completion_path = R / 'full-authority-v28-timeout-inventory/INVENTORY.json'
    completion_inventory = parse(read(completion_path, COMPLETION_INVENTORY))
    prior_log_path = R / 'evidence/full-python-diagnostic-completion-v28/76-normal-test_full_audit_cleanup_contracts.log'
    prior_log = read(prior_log_path, PRIOR_LOG)
    need(config['prior_authority_log'] == str(prior_log_path.relative_to(R))
         and config['prior_authority_log_sha256'] == PRIOR_LOG, 'Exact prior interrupted authority log')
    protocol_review_path = R / 'authority-remainder-diagnostic-v28-independent-review/FINAL-REVIEW.json'
    protocol_audit_path = R / 'authority-remainder-diagnostic-v28-independent-review/AUDIT.json'
    protocol_review = parse(read(protocol_review_path, PROTOCOL_REVIEW))
    read(protocol_audit_path, PROTOCOL_AUDIT)
    need(protocol_review['supervisor_sha256'] == SUP and protocol_review['config_sha256'] == CONFIG
         and protocol_review['independent_actual_diff_audit_sha256'] == PROTOCOL_AUDIT,
         'Reviewed authority protocol identity')
    prior_packet_path = R / 'validation-evidence-diagnostic-completion-v28-terminal-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
    read(prior_packet_path, PRIOR_PACKET)
    need(config['prior_diagnostic_result'] == result['prior_diagnostic_result'] == 'evidence/full-python-diagnostic-completion-v28/RESULT.json'
         and config['prior_diagnostic_result_sha256'] == result['prior_diagnostic_result_sha256'] == PRIOR_RESULT
         and config['prior_diagnostic_config'] == 'full-python-diagnostic-completion-v28.json'
         and config['prior_diagnostic_config_sha256'] == PRIOR_CONFIG
         and config['prior_diagnostic_supervisor'] == 'run_diagnostic_completion_v28.py'
         and config['prior_diagnostic_supervisor_sha256'] == PRIOR_SUP
         and config['prior_sdk_after'] == 'evidence/full-python-diagnostic-completion-v28/SDK-AFTER.json'
         and config['prior_sdk_after_sha256'] == SDK
         and config['completion_inventory'] == 'full-authority-v28-timeout-inventory/INVENTORY.json'
         and config['completion_inventory_sha256'] == result['completion_inventory_sha256'] == COMPLETION_INVENTORY,
         'Exact separate prior diagnostic and completion-plan provenance')
    need(prior['diagnostic_only'] is True and prior['qualification_passed'] is False
         and prior['sequence_completed'] is False and bool(prior['failure'])
         and prior['source_seal_unchanged'] is True and prior['sdk_identity_unchanged'] is True
         and prior['remaining_owned_descendants'] == [] and len(prior['stages']) == 13,
         'Prior interrupted collection remains failed and separately bound')
    original_path = R / 'evidence/full-python-matrix-final-v28/RESULT.json'
    original = parse(read(original_path, ORIGINAL_RESULT))
    original_config = parse(read(R / 'full-python-matrix-final-v28.json', ORIGINAL_CONFIG))
    read(R / 'validation-evidence-full-matrix-v28-failure-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json', ORIGINAL_PACKET)
    need(original['sequence_completed'] is False and bool(original['failure']), 'Original qualification failure changed')
    need(config['original_matrix_result_sha256'] == ORIGINAL_RESULT
         and config['original_matrix_config_sha256'] == ORIGINAL_CONFIG
         and result['original_matrix'] == config['original_matrix'] == 'evidence/full-python-matrix-final-v28'
         and config['original_matrix_result'] == 'evidence/full-python-matrix-final-v28/RESULT.json',
         'Separate original matrix provenance')
    computed_deadline = datetime.fromisoformat(original['finished']) + timedelta(seconds=10800-original['elapsed_seconds'])
    need(computed_deadline.isoformat() == result['original_absolute_deadline_utc'] == config['original_absolute_deadline_utc']
         == prior['original_absolute_deadline_utc'] == prior_config['original_absolute_deadline_utc'] == DEADLINE,
         'Original failed-attempt deadline provenance changed')
    need(datetime.fromisoformat(result['absolute_deadline_utc']).tzinfo is not None
         and 'absolute_deadline_utc' not in config, 'Independent deadline must be the actual runtime receipt value')
    need(datetime.fromisoformat(result['finished']) >= datetime.fromisoformat(window['started']), 'Terminal chronology')
    need(type(result['elapsed_seconds']) in (float, int) and result['elapsed_seconds'] >= 0, 'Terminal elapsed time')
    inventory_path = R / 'FINAL-PYTHON-EXPECTED-INVENTORY-V28.json'
    inventory = parse(read(inventory_path, INVENTORY))
    need(config['expected_inventory_sha256'] == INVENTORY and config['expected_inventory'] == str(inventory_path)
         and inventory['source_seal_sha256'] == SEAL, 'Fresh discovery/inventory binding')
    discovery = parse(read(R / 'evidence/python-discovery-final-v28/RESULT.json', DISCOVERY))
    need(inventory['discovery_result_sha256'] == DISCOVERY and discovery['sequence_completed'] is True,
         'Fresh discovery receipt')
    publication = parse(read(R / 'PUBLISHED-V28-QUALIFICATION-BINDING.json', PUBLICATION))
    need(publication['source_seal_sha256'] == SEAL and publication['inventory_sha256'] == INVENTORY,
         'Published source binding')

    plans = config['stages']
    labels = [stage['label'] for stage in plans]
    need(len(plans) == len(set(labels)) == 2 and sum(stage['expected_tests'] for stage in plans) == 107,
         'Exact two-stage, 107-expected-method authority diagnostic inventory')
    need(labels == ['76-normal-remaining-test_full_audit_cleanup_contracts',
                    '76-optimized-test_full_audit_cleanup_contracts'], 'Exact safe stage labels')
    need(prior_config['stages'][-2:] == [dict(stage, accept_nonzero=True) for stage in original_config['stages'][-2:]],
         'Prior authority commands/caps differ from original matrix')
    prior_labels = [stage['label'] for stage in prior_config['stages']]
    last = prior['stages'][-1]
    need([stage['label'] for stage in prior['stages']] == prior_labels[:13]
         and last == completion_inventory['batch_result']
         and last['label'] == '76-normal-test_full_audit_cleanup_contracts' and last['timed_out'] is True
         and last['returncode'] == -9 and last['stage_timeout_seconds'] == 1800
         and last['leader_reaped'] is True and last['remaining_owned_descendants'] == []
         and prior['unrun_stage_labels'] == prior_labels[13:] == ['76-optimized-test_full_audit_cleanup_contracts']
         and last['log_sha256'] == PRIOR_LOG, 'Prior interrupted and unlaunched authority receipt differs')
    for suffix, digest in (('-START.json', '17c5d3b9a8028d8a060bf866916efec7edd55ef700a0faba5a8c3634f97157b8'),
                           ('-RESULT.json', '37fbc056cee15f33f3067e6d7059a9c815ab1c039b2f9f4fe348d835bb9f0224')):
        payload = parse(read(prior_log_path.with_name('76-normal-test_full_audit_cleanup_contracts' + suffix), digest))
        need(all(last.get(key) == value for key, value in payload.items()), 'Prior START/RESULT authority mismatch')
    authority_path = 'tools/carla_lane_oracle/test_full_audit_cleanup_contracts.py'
    authority = next(row for row in inventory['modules'] if row['path'] == authority_path)
    all_ids = authority['modes']['0']['test_ids']
    methods = completion_inventory['methods']
    need(authority['sha256'] == seal[authority_path] == completion_inventory['source_sha256']
         and completion_inventory['source_path'] == authority_path
         and authority['test_count'] == authority['modes']['0']['test_count'] == authority['modes']['1']['test_count'] == 95
         and len(all_ids) == len(set(all_ids)) == 95 and authority['modes']['1']['test_ids'] == all_ids
         and [row['test_id'] for row in methods] == all_ids
         and [row['normal_status'] for row in methods] == ['completed_ok'] * 83 + ['interrupted_no_completion_event'] + ['unstarted'] * 11
         and all(row['optimized_status'] == 'unstarted_stage_not_launched' for row in methods),
         'Sealed source and 83/1/11 authority selection inventory differs')
    header_pattern = r'(?m)^test_[A-Za-z0-9_]+ \((test_full_audit_cleanup_contracts\.[A-Za-z0-9_]+\.test_[A-Za-z0-9_]+)\) \.\.\. '
    need(re.findall(header_pattern, prior_log.decode('utf-8')) == all_ids[:84], 'Prior actual authority headers differ')
    remaining_ids = all_ids[83:]
    need(len(remaining_ids) == 12 and all([item for item in all_ids if selector in item] == [selector]
         for selector in remaining_ids), 'Normal full-qualified selectors collide or differ')
    normal_command = list(prior_config['stages'][-2]['command'])
    normal_command[-1:-1] = [part for selector in remaining_ids for part in ('-k', selector)]
    required_stages = [
        dict(label=labels[0], command=normal_command, expected_tests=12, expected_test_ids=remaining_ids,
             accept_nonzero=True, seconds=1800),
        dict(label=labels[1], command=prior_config['stages'][-1]['command'], expected_tests=95,
             expected_test_ids=all_ids, accept_nonzero=True, seconds=3600)]
    need(plans == required_stages, 'Exact selected/full commands, identities and individual stage caps differ')
    stages = result['stages']
    need(isinstance(stages, list) and len(stages) <= len(plans), 'Invalid terminal recorded prefix')
    need([stage['label'] for stage in stages] == labels[:len(stages)], 'Recorded stages are not the exact configured prefix')
    need(result['unrun_stage_labels'] == labels[len(stages):], 'Receipt unrun suffix differs')
    need(result['nonzero_stage_labels'] == [stage['label'] for stage in stages if stage['returncode']],
         'Nonzero label list differs')
    need(len(console) == len(stages) + 1, 'Console does not contain each stage plus final result exactly once')
    modules = {row['path']: row for row in inventory['modules']}
    need(len(modules) == inventory['module_count'] == 77, 'Fresh module inventory differs')
    original_names = set()
    stage_summaries = []
    unrun = []
    missing_count_annotations = []
    for index, planned in enumerate(plans):
        label = planned['label']
        need(planned['seconds'] == (1800, 3600)[index] and planned['accept_nonzero'] is True,
             'Selected authority stage bound/diagnostic policy')
        argv = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                .replace('{mojo}', str(R.parent / 'restored-toolchain/official-venv/bin/mojo'))
                .replace('{evidence}', str(E)).replace('{root}', str(R)) for part in planned['command']]
        command = planned['command']
        need(command[0] == '{python}' and command[-1] == '-v' and command.count('-p') == 1
             and command.count('-s') == 1 and '-m' in command and 'unittest' in command and 'discover' in command,
             'Unexpected configured command')
        module_path = command[command.index('-s')+1] + '/' + command[command.index('-p')+1]
        module = modules[module_path]
        mode = '1' if '-O' in command else '0'
        need(module_path == authority_path and module['sha256'] == seal[module_path]
             and planned['expected_test_ids'] == (remaining_ids if mode == '0' else all_ids)
             and planned['expected_tests'] == len(planned['expected_test_ids']), 'Expected source/selected method identities')
        files = {suffix: E / (label + suffix) for suffix in ('-START.json', '-RESULT.json', '.log')}
        present = {suffix: path for suffix, path in files.items() if path.exists() or path.is_symlink()}
        original_names.update(path.name for path in present.values())
        for path in present.values():
            read(path)  # Every existing stage byte is retained, even an incomplete terminal launch.
        if index >= len(stages):
            need('-RESULT.json' not in present, 'Unindexed terminal stage result')
            if present:
                need(index == len(stages) and '.log' in present, 'Unexpected out-of-prefix stage artifacts')
                if '-START.json' in present:
                    start = parse(observed[files['-START.json']])
                    need(start['label'] == label and start['argv'] == argv and start['source_seal_sha256'] == SEAL
                         and start['stage_timeout_seconds'] == planned['seconds'] and start['cwd'] == str(R / 'candidate-v28'),
                         'Incomplete launch START binding')
                observed[files['.log']].decode('utf-8')
            unrun.append(dict(position_one_based=index+1, label=label, module=module_path,
                              command=argv, expected_methods=planned['expected_tests'], mode=int(mode),
                              supervisor_marks_unrun=True, actual_artifacts=sorted(path.name for path in present.values()),
                              disposition='launch artifacts exist without a terminal stage receipt' if present else 'not launched'))
            continue
        need(set(present) == set(files), 'Recorded stage lacks full START/RESULT/log evidence')
        receipt = parse(observed[files['-RESULT.json']])
        start = parse(observed[files['-START.json']])
        log_raw = observed[files['.log']]
        log = log_raw.decode('utf-8')
        need(receipt == stages[index] and all(receipt.get(key) == value for key, value in start.items()),
             'Terminal/individual START/RESULT disagreement')
        need(receipt['label'] == label and receipt['argv'] == argv
             and receipt['cwd'] == str(R / 'candidate-v28') and receipt['source_seal_sha256'] == SEAL
             and receipt['stage_timeout_seconds'] == planned['seconds'] and receipt['log_sha256'] == SHA(log_raw),
             'Actual command/source/cap/log binding')
        need(receipt['leader_reaped'] is True and isinstance(receipt['remaining_owned_descendants'], list)
             and type(receipt['timed_out']) is bool and type(receipt['returncode']) is int, 'Terminal process receipt')
        printed = {key: value for key, value in receipt.items()
                   if key not in ('test_count', 'expected_tests', 'skipped_test_count', 'test_ids')}
        need(console[index] == printed, 'Actual printed stage row differs')
        totals = re.findall(r'^Ran (\d+) tests? in ', log, re.M)
        need(len(totals) <= 1, 'Ambiguous unittest method-count summary')
        reported_methods = int(totals[0]) if totals else None
        status_lines = re.findall(r'^(?:OK(?: \([^\n]*\))?|FAILED \([^\n]*\))$', log, re.M)
        need(len(status_lines) <= 1, 'Ambiguous unittest status summary')
        status = status_lines[0] if status_lines else None
        details = dict((key, int(value)) for key, value in re.findall(r'(failures|errors|skipped|expected failures|unexpected successes)=(\d+)', status or ''))
        skip_lines = max(sum(' ... skipped ' in line for line in log.splitlines()), details.get('skipped', 0))
        observed_ids = re.findall(header_pattern, log)
        annotated = 'test_count' in receipt
        if annotated:
            need(receipt['test_count'] == receipt['expected_tests'] == planned['expected_tests'] == reported_methods
                 and receipt['skipped_test_count'] == skip_lines
                 and receipt['test_ids'] == observed_ids == planned['expected_test_ids'],
                 'Post-run exact method identity/count annotation mismatch')
        else:
            need(not any(key in receipt for key in ('expected_tests', 'skipped_test_count', 'test_ids')), 'Partial count annotation')
            missing_count_annotations.append(label)
        if receipt['timed_out']:
            outcome = 'timed_out'
        elif receipt['remaining_owned_descendants']:
            outcome = 'descendant_cleanup_failure'
        elif receipt['returncode']:
            outcome = 'nonzero_diagnostic_stage'
        elif not annotated or reported_methods != planned['expected_tests'] or skip_lines:
            outcome = 'zero_return_without_complete_expected_inventory'
        else:
            need(status == 'OK', 'Zero-return stage does not report ordinary zero-skip OK')
            outcome = 'passed_diagnostic_stage'
        stage_summaries.append(dict(position_one_based=index+1, label=label, module=module_path, mode=int(mode),
                                    outcome=outcome, expected_methods=planned['expected_tests'],
                                    expected_test_ids=planned['expected_test_ids'], observed_method_headers=observed_ids,
                                    reported_methods=reported_methods, unittest_status_line=status,
                                    reported_failure_records=details.get('failures', 0) if status else None,
                                    reported_error_records=details.get('errors', 0) if status else None,
                                    reported_skips=details.get('skipped', 0) if status else None,
                                    count_annotations_present=annotated, returncode=receipt['returncode'],
                                    timed_out=receipt['timed_out'], elapsed_seconds=receipt['seconds'],
                                    stage_timeout_seconds=receipt['stage_timeout_seconds'],
                                    log_bytes=len(log_raw), log_sha256=SHA(log_raw)))
    if result['sequence_completed']:
        need(len(stages) == len(plans) and result['failure'] is None and not missing_count_annotations,
             'Completed sequence has a missing stage, annotation or failure')
    else:
        need(bool(result['failure']), 'Incomplete sequence lacks failure')

    fixed_required = {'RESULT.json', 'SOURCE-SEAL.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'}
    fixed_optional = {'FAILURE.json', 'LANE-CHECKPOINT.json', 'LANE-HANDOFFS.jsonl'}
    omitted_polling = {'LATEST.json', 'PROCESSES.jsonl'}
    actual_names = {path.name for path in E.iterdir()}
    need(fixed_required <= actual_names and actual_names <= fixed_required | fixed_optional | omitted_polling | original_names,
         'Unknown phase file or missing final binding; review required')
    for name in sorted(fixed_optional & actual_names):
        read(E / name)
    if result['failure'] is not None:
        need('FAILURE.json' in actual_names and parse(observed[E / 'FAILURE.json'])['error'] == result['failure'],
             'Final failure lacks its actual traceback receipt')
    else:
        need('FAILURE.json' not in actual_names, 'Unexpected failure receipt')
    if 'LANE-HANDOFFS.jsonl' in actual_names:
        for line in observed[E / 'LANE-HANDOFFS.jsonl'].decode().splitlines():
            row = parse(line)
            need(row['paused'] is False and row['source_seal_sha256'] == SEAL
                 and row['remaining_owned_descendants'] == [] and row['next_stage'] in labels
                 and datetime.fromisoformat(row['resumed']) <= datetime.fromisoformat(result['finished']),
                 'Invalid completed lane handoff')
    originals = []

    def add(path, name, kind, readable=False):
        data = read(path)
        data.decode('utf-8')  # Preserve complete UTF-8 bytes, never normalize or truncate logs.
        originals.append(dict(path=name, data=data, original_source=str(path), kind=kind, readable=readable))

    for name in sorted(original_names | fixed_required | (fixed_optional & actual_names)):
        add(E / name, 'actual/terminal-authority-remainder/' + name,
            'original-terminal-stage-log-receipt-or-collection-binding',
            name in ('RESULT.json', 'FAILURE.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'))
    add(console_path, 'actual/' + console_path.name, 'complete-actual-terminal-supervisor-console')
    for name in (PHASE + '.json', 'run_authority_remainder_diagnostic_v28.py',
                 'FINAL-PYTHON-EXPECTED-INVENTORY-V28.json', 'CANDIDATE-V28-SOURCE-SEAL.json',
                 'PUBLISHED-V28-QUALIFICATION-BINDING.json'):
        add(R / name, 'reproduce/' + name, 'exact-protocol-inventory-source-or-published-binding',
            name in (PHASE + '.json', 'run_authority_remainder_diagnostic_v28.py', 'PUBLISHED-V28-QUALIFICATION-BINDING.json'))
    add(R / 'evidence/python-discovery-final-v28/RESULT.json', 'provenance/discovery/RESULT.json',
        'original-fresh-discovery-receipt-linked-by-inventory')
    add(original_path, 'provenance/original-failed-matrix/RESULT.json', 'separate-original-qualification-failure')
    add(R / 'full-python-matrix-final-v28.json', 'provenance/original-failed-matrix/config.json',
        'separate-original-qualification-config')
    add(R / 'validation-evidence-full-matrix-v28-failure-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json',
        'provenance/original-failed-matrix/PUBLISHABLE-EVIDENCE-MANIFEST.json',
        'separate-failed-packet-identity-reference-not-recursive-payload')
    add(prior_path, 'provenance/prior-terminal-completion/RESULT.json', 'separate-prior-failed-diagnostic-receipt')
    add(R / 'full-python-diagnostic-completion-v28.json', 'provenance/prior-terminal-completion/config.json',
        'separate-prior-diagnostic-config')
    add(R / 'run_diagnostic_completion_v28.py', 'provenance/prior-terminal-completion/supervisor.py',
        'separate-prior-diagnostic-supervisor')
    add(prior_sdk_path, 'provenance/prior-terminal-completion/SDK-AFTER.json', 'sealed-prior-sdk-binding')
    add(prior_packet_path, 'provenance/prior-terminal-completion/PUBLISHABLE-EVIDENCE-MANIFEST.json',
        'separate-prior-packet-identity-reference-not-recursive-payload')
    add(completion_path, 'reproduce/full-authority-v28-timeout-inventory/INVENTORY.json',
        'exact-reviewed-authority-method-selection-inventory', True)
    for suffix in ('-START.json', '-RESULT.json', '.log'):
        path = prior_log_path.with_name('76-normal-test_full_audit_cleanup_contracts' + suffix)
        add(path, 'provenance/prior-terminal-completion/' + path.name,
            'separate-original-authority-timeout-log-or-receipt')
    add(protocol_review_path, 'reproduce/PROTOCOL-FINAL-REVIEW.json', 'exact-independent-protocol-review')
    add(protocol_audit_path, 'reproduce/PROTOCOL-ACTUAL-DIFF-AUDIT.json', 'exact-independent-protocol-audit')
    original_outcomes = Counter(row['outcome'] for row in stage_summaries)
    unrun_inventory = dict(schema=1,kind='derived-exact-supervisor-unrun-suffix',stages=unrun,
                           stage_count=len(unrun), expected_methods=sum(row['expected_methods'] for row in unrun),
                           boundary='These expected method counts are not executed-test counts. A last incomplete launch is explicitly distinguished from an unlaunched stage.')
    summary = dict(schema=1, status='TERMINAL_DIAGNOSTIC_COLLECTION_NOT_QUALIFICATION',
                   diagnostic_only=True, qualification_passed=False,
                   sequence_completed=result['sequence_completed'], collection_failure=result['failure'],
                   finished=result['finished'], elapsed_seconds=result['elapsed_seconds'],
                   source_seal_sha256=SEAL, source_seal_unchanged=result['source_seal_unchanged'],
                   sdk_before_sha256=SHA(sdk_before), sdk_after_sha256=SHA(sdk_after),
                   sdk_identity_unchanged=result['sdk_identity_unchanged'],
                   remaining_owned_descendants=result['remaining_owned_descendants'],
                   published_commit=publication['published_commit'], published_tree=publication['published_tree'],
                   config_sha256=CONFIG, supervisor_sha256=SUP, result_sha256=SHA(result_raw),
                   console_sha256=SHA(console_raw), original_absolute_deadline_utc=DEADLINE,
                   independent_absolute_deadline_utc=result['absolute_deadline_utc'],
                   configured_window_seconds=6000, recorded_window_seconds=window['whole_window_seconds'],
                   window_policy=result['window_policy'],
                   configured_stage_count=2, configured_expected_method_executions=107, recorded_terminal_stage_count=len(stages),
                   stage_outcome_counts=dict(original_outcomes), stage_outcomes=stage_summaries,
                   reported_method_count=sum(row['reported_methods'] or 0 for row in stage_summaries),
                   stages_without_unittest_method_summary=[row['label'] for row in stage_summaries if row['reported_methods'] is None],
                   stages_without_post_run_count_annotations=missing_count_annotations,
                   unrun_inventory='UNRUN-INVENTORY.json', unrun_stage_count=len(unrun),
                   counting_boundary='Ran N counts methods, while unittest failures/errors may include subtests. Failure-record counts are never subtracted from method counts; interrupted logs may lack a method total. A nonzero accepted diagnostic stage remains failed.',
                   stability_boundary='Primary source stability and SDK before/after equality are the exact sealed supervisor receipts. This builder does not rescan the candidate or installed SDK. Missing post-run annotations are disclosed rather than inferred as successful post-stage checks.',
                   original_failed_matrix=dict(result_sha256=ORIGINAL_RESULT, config_sha256=ORIGINAL_CONFIG,
                       packet_manifest_sha256=ORIGINAL_PACKET, status='FAILED; unchanged separate provenance; never relabeled by completion'),
                   prior_failed_diagnostic=dict(result_sha256=PRIOR_RESULT, config_sha256=PRIOR_CONFIG,
                       supervisor_sha256=PRIOR_SUP, packet_manifest_sha256=PRIOR_PACKET,
                       interrupted_stage='76-normal-test_full_audit_cleanup_contracts', never_launched_stage_count=1,
                       earlier_normal_method_events=dict(completed_ok=83, interrupted=1, unstarted=11),
                       prior_authority_log_sha256=PRIOR_LOG,
                       status='FAILED; unchanged separate provenance; independent completion outcomes are never backfilled into prior receipts'),
                   deadline_boundary='The new 6000-second monotonic budget belongs only to this independent authority remainder. Its runtime absolute deadline is preserved as reported by the exact sealed supervisor; the old 08:35:38.016452 deadline is separate provenance, not extended.',
                   authority_cap_boundary='Twelve selected normal methods retain 1800 seconds; the never-launched full optimized authority batch uses the specifically approved 3600-second external batch allowance. Maintained test and child bounds are unchanged.',
                   normal_scope_boundary='The earlier 83 ok events and this twelve-method remainder are not a fresh complete normal module qualification.',
                   protocol_review_sha256=PROTOCOL_REVIEW, protocol_audit_sha256=PROTOCOL_AUDIT,
                   scope='Terminal evidence for the separate two-stage v28 authority remainder diagnostic only. Collection completion, even with all stages passing, does not establish passing qualification. Both prior failed attempts and later repaired candidates remain separate.', 
                   excluded='LATEST.json and PROCESSES.jsonl polling snapshots, private notes, later candidate/focused-run evidence, repository and SDK payload images. Completed terminal handoffs are retained only as the actual independent completion records.',
                   evidence_policy='Original complete receipt/log/console bytes plus explicitly derived inventories and summary. No candidate imports, scans, tests/native runs, edits, uploads or invented receipts.')
    commands = dict(schema=1,kind='derived-terminal-command-and-cap-index',source_seal_sha256=SEAL,
                    config_sha256=CONFIG,supervisor_sha256=SUP,absolute_deadline_utc=result['absolute_deadline_utc'],
                    original_absolute_deadline_utc=DEADLINE,independent_window_seconds=6000,
                    completion_inventory_sha256=COMPLETION_INVENTORY,prior_diagnostic_result_sha256=PRIOR_RESULT,
                    stages=[dict(position_one_based=i+1, planned=planned,
                                 actual=stages[i] if i < len(stages) else None)
                            for i, planned in enumerate(plans)])

    archive = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
    payloads = []
    members = []
    archived = []
    need(len(originals) == len({row['path'] for row in originals}), 'Duplicate original names')
    for row in sorted(originals, key=lambda row: row['path']):
        data = row['data']
        member = {key:row[key] for key in ('path','kind','original_source')}
        member.update(bytes=len(data),sha256=SHA(data))
        if row['readable']:
            payloads.append((row['path'],data,'byte-exact-readable-original'))
            member.update(storage='readable',transport_path=row['path'])
        else:
            archived.append(dict(path=row['path'],bytes=len(data),sha256=SHA(data),
                                 data_base64=base64.b64encode(data).decode()))
            member.update(storage='container',transport_path=archive)
        members.append(member)
    container=(json.dumps(dict(schema=1,encoding='base64',members=archived),sort_keys=True,separators=(',',':'))+'\n').encode()
    need(len(container) < LIMIT, 'Reviewed decoder 64 MiB limit exceeded; stop for chunking review')
    packed=gzip.compress(container,compresslevel=9,mtime=0)
    encoded=base64.b64encode(packed)+b'\n'
    need(gzip.decompress(base64.b64decode(encoded,validate=False)) == container, 'Container round-trip differs')
    inner=dict(schema=1,original_member_count=len(members),original_member_bytes=sum(row['bytes'] for row in members),
               container=dict(path=archive,encoding='base64 of deterministic gzip mtime=0 containing JSON',
                              members=len(archived),json_bytes=len(container),json_sha256=SHA(container)),members=members)
    decoder=read(R / 'validation-evidence-qualification-policy-v23-packet/decode_verify.py',DECODER)
    guide='''# Frozen v28 remaining-authority diagnostic evidence

This packet preserves the separate two-stage authority remainder diagnostic.
The normal command selects exactly twelve qualified method IDs: the previously
interrupted method and eleven unstarted methods. The optimized command retains
the full original 95-method inventory. The planned total is 107 executions.
The earlier 83 normal ok events plus this remainder are never represented as a
fresh complete normal authority qualification. Qualification remains false.

Terminal RESULT and complete console are supplied-hash inputs. Read the derived
VALIDATION-SUMMARY.json for actual failures, timeouts, counts, exact observed IDs
and final source/SDK/descendant receipts. Every existing configured-stage START,
RESULT and complete UTF-8 log is retained. Missing summaries are not inferred.
UNRUN-INVENTORY.json discloses the exact unlaunched or incomplete-launch suffix.
Failure/error totals may include subtests and are not failed-method totals.

The selected normal stage retains 1800 seconds. The full optimized authority
stage uses the specifically approved 3600-second external authority-batch cap.
The independent window is 6000 seconds. All maintained child/test/native limits
stay as in frozen v28. Original failed matrix and prior timed-out completion
receipts are separate immutable provenance; neither deadline nor failure is
rewritten. The prior authority raw log and receipt and exact method-selection
inventory are included, along with the new protocol's independent review.

Original files are indexed by path, source, size and SHA256. Archived members
are base64 JSON compressed with deterministic gzip mtime=0, then UTF-8 base64.
No original is truncated, normalized or replaced with a summary. The outer
manifest seals each payload except itself. Derived data is labeled explicitly.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The decoder checks safe paths, sizes and hashes and never executes contents.
Polling-only LATEST/PROCESSES, private notes, repository/SDK payload images and
later candidate outcomes are excluded. This builder neither imports nor scans
candidate sources. Publication requires the parent's separate workflow.
'''
    payloads.extend([(archive,encoded,'lossless-original-terminal-evidence'),
                     ('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),
                     ('VALIDATION-SUMMARY.json',JSON(summary),'derived-diagnostic-only-summary'),
                     ('UNRUN-INVENTORY.json',JSON(unrun_inventory),'derived-explicit-unrun-inventory'),
                     ('COMMAND-RECEIPT-SEAL.json',JSON(commands),'derived-command-binding-index'),
                     ('decode_verify.py',decoder,'reviewed-safe-decoder-no-execution'),
                     ('reproduce/'+Path(__file__).name,builder,'source-only-packet-builder'),
                     ('README.md',guide.encode(),'scope-and-safe-transport-guide')])
    need(len(payloads)==len({name for name,_,_ in payloads})<=35,'Payload names/count')
    patterns=(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',rb'gh[pousr]_[A-Za-z0-9]{30,}',
              rb'AKIA[0-9A-Z]{16}',rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
    for row in originals:
        need(not any(re.search(pattern,row['data']) for pattern in patterns),'Credential pattern: '+row['path'])
    # Recheck every consumed original, protocol byte and terminal directory member.
    # This does not inspect candidate source or live process state.
    need({path.name for path in E.iterdir()} == actual_names, 'Terminal directory membership changed')
    for path,data in observed.items():
        need(raw(path)==data,'Input changed during packaging: '+str(path))
    O.mkdir()
    rows=[]
    for name,data,kind in sorted(payloads):
        path=O/name
        path.parent.mkdir(parents=True,exist_ok=True)
        with path.open('xb') as stream:
            stream.write(data)
        need(raw(path)==data,'Output copy differs')
        rows.append(dict(path=name,local_source=str(path),bytes=len(data),sha256=SHA(data),kind=kind))
    manifest=O/'PUBLISHABLE-EVIDENCE-MANIFEST.json'
    with manifest.open('xb') as stream:
        stream.write(JSON(dict(schema=1,scope=summary['scope'],files=rows)))
    print(json.dumps(dict(manifest=str(manifest),sha256=SHA(raw(manifest)),payloads=len(rows),
                          original_members=len(members),archived_members=len(archived),
                          recorded_stages=len(stages),unrun_stages=len(unrun),
                          qualification_passed=False,original_bytes=inner['original_member_bytes'],
                          packet_bytes_including_manifest=sum(row['bytes'] for row in rows)+len(raw(manifest)))))


if __name__ == '__main__':
    main()
