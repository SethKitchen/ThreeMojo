"""Create the separate terminal v28 diagnostic-completion packet, without execution.

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
PHASE = 'full-python-diagnostic-completion-v28'
E = R / 'evidence' / PHASE
O = R / 'validation-evidence-diagnostic-completion-v28-terminal-packet'
SEAL = 'fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596'
SDK = '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
SUP = 'df6da89f3b8c3c6790c2c2c1eb414cf3677674165203a30c8224d632f26a3b84'
CONFIG = '7aa23228e0b9ea130fe3c25fe376e5210c105beb761793bab4a40fa2300a1d39'
PRIOR_RESULT = 'ddcd0576ed61827896eac96a52ae44a7d98cbb9f202137d7a38ecb887838359b'
PRIOR_CONFIG = 'a7282c67969f81b7e323cb685ed635db516aaf79621ea107d3d86ff2ecf1a0b3'
PRIOR_SUP = '0c6cf71e8be2fe48be76414cd800449e382569de824424a9e51110e90bc50ffc'
PRIOR_PACKET = 'f917e27571429d65c6a5447c8dced41d61df63a97ac2b11899a84cc454a08de2'
COMPLETION_INVENTORY = '2b29b4ff8e64832e7684f82176a34347f5f0fb9bc9c4e9297ce1ae953f15e7aa' 
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

    # This check precedes every read of the active completion evidence or console.
    # Absence of RESULT never triggers waiting, polling, or partial packaging.
    need((E / 'RESULT.json').is_file(), 'Refuse: completion RESULT.json is absent; collection is not terminal')
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
    read(R / 'run_diagnostic_completion_v28.py', SUP)
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
    need(window['whole_window_seconds'] == config['window_seconds'] == result['whole_window_seconds'] == 7800
         and result['window_policy'] == config['window_policy'] == 'independent-bounded-diagnostic-completion',
         'Independent completion window differs')
    prior_path = R / 'evidence/full-python-diagnostic-continuation-v28/RESULT.json'
    prior = parse(read(prior_path, PRIOR_RESULT))
    prior_config = parse(read(R / 'full-python-diagnostic-continuation-v28.json', PRIOR_CONFIG))
    read(R / 'run_diagnostic_continuation_v28.py', PRIOR_SUP)
    prior_sdk_path = R / 'evidence/full-python-diagnostic-continuation-v28/SDK-AFTER.json'
    need(read(prior_sdk_path, SDK) == sdk_before, 'Completion SDK differs from sealed prior SDK')
    completion_path = R / 'DIAGNOSTIC-COMPLETION-14-STAGE-INVENTORY.json'
    completion_inventory = parse(read(completion_path, COMPLETION_INVENTORY))
    prior_packet_path = R / 'validation-evidence-diagnostic-continuation-v28-terminal-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json'
    read(prior_packet_path, PRIOR_PACKET)
    need(config['prior_diagnostic_result'] == result['prior_diagnostic_result'] == 'evidence/full-python-diagnostic-continuation-v28/RESULT.json'
         and config['prior_diagnostic_result_sha256'] == result['prior_diagnostic_result_sha256'] == PRIOR_RESULT
         and config['prior_diagnostic_config'] == 'full-python-diagnostic-continuation-v28.json'
         and config['prior_diagnostic_config_sha256'] == PRIOR_CONFIG
         and config['prior_diagnostic_supervisor'] == 'run_diagnostic_continuation_v28.py'
         and config['prior_diagnostic_supervisor_sha256'] == PRIOR_SUP
         and config['prior_sdk_after'] == 'evidence/full-python-diagnostic-continuation-v28/SDK-AFTER.json'
         and config['prior_sdk_after_sha256'] == SDK
         and config['completion_inventory'] == 'DIAGNOSTIC-COMPLETION-14-STAGE-INVENTORY.json'
         and config['completion_inventory_sha256'] == result['completion_inventory_sha256'] == COMPLETION_INVENTORY,
         'Exact separate prior diagnostic and completion-plan provenance')
    need(prior['diagnostic_only'] is True and prior['qualification_passed'] is False
         and prior['sequence_completed'] is False and bool(prior['failure'])
         and prior['source_seal_unchanged'] is True and prior['sdk_identity_unchanged'] is True
         and prior['remaining_owned_descendants'] == [] and len(prior['stages']) == 124,
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
         == prior['absolute_deadline_utc'] == prior_config['absolute_deadline_utc'] == DEADLINE,
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
    need(len(plans) == len(set(labels)) == 14 and sum(stage['expected_tests'] for stage in plans) == 286,
         'Exact fourteen-stage, 286-expected-method diagnostic completion inventory')
    need(all(re.fullmatch(r'\d{2}-(normal|optimized)-test_\w+', label) for label in labels), 'Unsafe stage label')
    need(prior_config['stages'] == [dict(stage, accept_nonzero=True) for stage in original_config['stages'][len(original['stages']):]],
         'Prior diagnostic differs from original matrix suffix')
    prior_labels = [stage['label'] for stage in prior_config['stages']]
    last = prior['stages'][-1]
    need([stage['label'] for stage in prior['stages']] == prior_labels[:124]
         and last['label'] == '70-normal-test_sampled_values' and last['timed_out'] is True
         and last['returncode'] == -9 and last['leader_reaped'] is True and last['remaining_owned_descendants'] == []
         and prior['unrun_stage_labels'] == prior_labels[124:]
         and completion_inventory['interrupted'] == [last['label']]
         and completion_inventory['never_launched'] == prior['unrun_stage_labels']
         and completion_inventory['original_result_sha256'] == PRIOR_RESULT
         and plans == completion_inventory['stages'] == prior_config['stages'][123:],
         'Commands/caps are not the exact prior interrupted stage plus thirteen unlaunched successors')
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
        need(planned['seconds'] == 1800 and planned['accept_nonzero'] is True, 'Original stage bound/diagnostic policy')
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
        need(module['sha256'] == seal[module_path] and module['test_count'] == planned['expected_tests']
             and module['modes'][mode]['test_count'] == planned['expected_tests'], 'Expected source/method count')
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
                         and start['stage_timeout_seconds'] == 1800 and start['cwd'] == str(R / 'candidate-v28'),
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
             and receipt['stage_timeout_seconds'] == 1800 and receipt['log_sha256'] == SHA(log_raw),
             'Actual command/source/cap/log binding')
        need(receipt['leader_reaped'] is True and isinstance(receipt['remaining_owned_descendants'], list)
             and type(receipt['timed_out']) is bool and type(receipt['returncode']) is int, 'Terminal process receipt')
        printed = {key: value for key, value in receipt.items()
                   if key not in ('test_count', 'expected_tests', 'skipped_test_count')}
        need(console[index] == printed, 'Actual printed stage row differs')
        totals = re.findall(r'^Ran (\d+) tests? in ', log, re.M)
        need(len(totals) <= 1, 'Ambiguous unittest method-count summary')
        reported_methods = int(totals[0]) if totals else None
        status_lines = re.findall(r'^(?:OK(?: \([^\n]*\))?|FAILED \([^\n]*\))$', log, re.M)
        need(len(status_lines) <= 1, 'Ambiguous unittest status summary')
        status = status_lines[0] if status_lines else None
        details = dict((key, int(value)) for key, value in re.findall(r'(failures|errors|skipped|expected failures|unexpected successes)=(\d+)', status or ''))
        skip_lines = sum(' ... skipped ' in line for line in log.splitlines())
        annotated = 'test_count' in receipt
        if annotated:
            need(receipt['test_count'] == receipt['expected_tests'] == planned['expected_tests'] == reported_methods
                 and receipt['skipped_test_count'] == skip_lines, 'Post-run count annotation mismatch')
        else:
            need(not any(key in receipt for key in ('expected_tests', 'skipped_test_count')), 'Partial count annotation')
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
        add(E / name, 'actual/terminal-completion/' + name,
            'original-terminal-stage-log-receipt-or-collection-binding',
            name in ('RESULT.json', 'FAILURE.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'))
    add(console_path, 'actual/' + console_path.name, 'complete-actual-terminal-supervisor-console')
    for name in (PHASE + '.json', 'run_diagnostic_completion_v28.py',
                 'FINAL-PYTHON-EXPECTED-INVENTORY-V28.json', 'CANDIDATE-V28-SOURCE-SEAL.json',
                 'PUBLISHED-V28-QUALIFICATION-BINDING.json'):
        add(R / name, 'reproduce/' + name, 'exact-protocol-inventory-source-or-published-binding',
            name in (PHASE + '.json', 'run_diagnostic_completion_v28.py', 'PUBLISHED-V28-QUALIFICATION-BINDING.json'))
    add(R / 'evidence/python-discovery-final-v28/RESULT.json', 'provenance/discovery/RESULT.json',
        'original-fresh-discovery-receipt-linked-by-inventory')
    add(original_path, 'provenance/original-failed-matrix/RESULT.json', 'separate-original-qualification-failure')
    add(R / 'full-python-matrix-final-v28.json', 'provenance/original-failed-matrix/config.json',
        'separate-original-qualification-config')
    add(R / 'validation-evidence-full-matrix-v28-failure-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json',
        'provenance/original-failed-matrix/PUBLISHABLE-EVIDENCE-MANIFEST.json',
        'separate-failed-packet-identity-reference-not-recursive-payload')
    add(prior_path, 'provenance/prior-terminal-continuation/RESULT.json', 'separate-prior-failed-diagnostic-receipt')
    add(R / 'full-python-diagnostic-continuation-v28.json', 'provenance/prior-terminal-continuation/config.json',
        'separate-prior-diagnostic-config')
    add(R / 'run_diagnostic_continuation_v28.py', 'provenance/prior-terminal-continuation/supervisor.py',
        'separate-prior-diagnostic-supervisor')
    add(prior_sdk_path, 'provenance/prior-terminal-continuation/SDK-AFTER.json', 'sealed-prior-sdk-binding')
    add(prior_packet_path, 'provenance/prior-terminal-continuation/PUBLISHABLE-EVIDENCE-MANIFEST.json',
        'separate-prior-packet-identity-reference-not-recursive-payload')
    add(completion_path, 'reproduce/DIAGNOSTIC-COMPLETION-14-STAGE-INVENTORY.json',
        'exact-reviewed-interrupted-and-unlaunched-plan', True)
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
                   configured_window_seconds=7800, recorded_window_seconds=window['whole_window_seconds'],
                   window_policy=result['window_policy'],
                   configured_stage_count=14, configured_expected_method_executions=286, recorded_terminal_stage_count=len(stages),
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
                       interrupted_stage='70-normal-test_sampled_values', never_launched_stage_count=13,
                       status='FAILED; unchanged separate provenance; independent completion outcomes are never backfilled into prior receipts'),
                   deadline_boundary='The new 7800-second monotonic budget belongs only to this independent completion. Its runtime absolute deadline is preserved as reported by the exact sealed supervisor; the old 08:35:38.016452 deadline is separate provenance, not extended.',
                   scope='Terminal evidence for the separate fourteen-stage v28 diagnostic completion only. Collection completion, even with all stages passing, does not establish passing qualification. Both prior failed attempts and later repaired candidates remain separate.', 
                   excluded='LATEST.json and PROCESSES.jsonl polling snapshots, private notes, later candidate/focused-run evidence, repository and SDK payload images. Completed terminal handoffs are retained only as the actual independent completion records.',
                   evidence_policy='Original complete receipt/log/console bytes plus explicitly derived inventories and summary. No candidate imports, scans, tests/native runs, edits, uploads or invented receipts.')
    commands = dict(schema=1,kind='derived-terminal-command-and-cap-index',source_seal_sha256=SEAL,
                    config_sha256=CONFIG,supervisor_sha256=SUP,absolute_deadline_utc=result['absolute_deadline_utc'],
                    original_absolute_deadline_utc=DEADLINE,independent_window_seconds=7800,
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
    guide='''# Independent v28 diagnostic completion evidence

This packet preserves the separate fourteen-stage diagnostic completion. Its terminal RESULT
and complete console are exact supplied-hash inputs. Read VALIDATION-SUMMARY.json
for actual completion, failures, timeouts, counts and final source/SDK/descendant
receipts. Qualification remains failed regardless of whether collection completed.
The original failed matrix is separately identified under provenance; its full
raw-evidence packet has its own unchanged manifest and is not recursively bundled.
The prior terminal continuation remains failed and separately bound by its exact
RESULT, config, supervisor, SDK-after receipt and frozen packet manifest. Its
interrupted stage is rerun here; thirteen unlaunched successors follow unchanged.
The exact plan contains fourteen stages and 286 expected method executions.

All actual configured-stage START/RESULT receipts and complete raw UTF-8 logs
are retained. An interrupted stage remains interrupted; an incomplete launch
without a terminal stage receipt is disclosed. UNRUN-INVENTORY.json lists the
exact supervisor suffix with expected method counts, not invented execution counts.
Ran N counts methods. Failure/error record totals may include subtests and are
never treated as distinct failed-method totals. No absent status is inferred.

Original commands and 1800-second stage caps remain unchanged. This independent
completion has a separate 7800-second budget, with its actual runtime deadline
preserved in RESULT. The original 2026-10-11T08:35:38.016452Z deadline remains only
prior-failure provenance and is never extended or rewritten. Terminal SDK before/after,
source seal, cleanup, failure traceback and completed lane handoff records are
preserved as applicable. Polling-only LATEST/PROCESSES and private notes are
excluded. The builder performs no candidate-tree scan, project import or execution.

Each original is indexed by path, source, byte size, SHA256 and storage. Archived
members are base64 JSON compressed with deterministic gzip mtime=0 and encoded as
UTF-8 base64. No original is truncated, normalized or replaced by a summary.
The outer manifest seals every payload except itself. The summary, command index
and unrun inventory are explicitly derived from original bytes.

Verify without writing: python -B decode_verify.py
Decode to a new directory: python -B decode_verify.py --output /path/to/new-directory
The reviewed decoder verifies safe paths, sizes and hashes, rejects symlinks and
existing output, and never executes decoded content. Full source and SDK images,
later repairs, full-matrix readiness, native/coverage and hosted CI are outside
this packet's claims. Publication/upload requires the parent's separate workflow.
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
