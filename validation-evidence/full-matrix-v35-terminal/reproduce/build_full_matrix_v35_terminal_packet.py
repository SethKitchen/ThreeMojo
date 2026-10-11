"""Preserve terminal v35 full-matrix evidence, with policy acceptance separate.

Run ONLY after terminal notification and independent review. Required expected
RESULT and console hashes are supplied from that completed run, never inferred.
Only named seal-bound source files are read after terminal approval. No candidate-tree scans, project imports, tests, native tools, or uploads.
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
PHASE = 'full-python-matrix-final-v35'
DISC = 'python-discovery-final-v35'
E = R / 'evidence' / PHASE
DE = R / 'evidence' / DISC
O = R / 'validation-evidence-full-matrix-v35-terminal-packet'
SEAL = '020a72e9ceb1e45bf31559b624b5d328fd4a6e6414aafbdba5259b71af9fd7cc'
SDK = '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
SUP = '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
CONFIG = '848e38cd12efb3807cb92f8ccd07144133b4837e28edf9bc7f26ee2eb4d0737b'
INVENTORY = '43ea211d82c5a2ab09ba692d07697815a1f9c9479494c8aa85d74c7f39723841'
PUBLICATION = '9f7159cc980b51da7be9ed5b3822cbb0a8c88977794200cf6b24315f9c4a8e2c'
PUBLISHED_COMMIT = '19287a0b1564b9a628f15c96e7675c51413ca1a9'
PUBLISHED_TREE = '5c1f67c196fc30d6a323d6d854748b65e3640585'
PUBLICATION_MANIFEST = '6f9bb381b2e8063747c5a4b50e47e4fa25f296ff8dc0762446d05667ab2c6162'
SOURCE_MANIFEST = '72a2cb57d9212ba96683bd6ca7baf1c7066f29ef9df989c9725623c6fb80930f'
DISCOVERY = 'c11f3d118386028a24733ab8fd161f93a95894dd82b0e6b3777dc286e0371622'
DISCOVERY_CONFIG = 'b9765024383151f2f3f6f2108dfaaf2717caed3be452e9ded4d7f82e5f458a24'
DISCOVERY_CONSOLE = '832137d3ef9c56a3f58e0d551602f0b399c7080f33cab81284a969f66a9ece77'
DISCOVERY_PROGRAM = '702838da94b1f8b6e868e85dba87932288d1fd5af501e515882eafdc53c96bfe'
PLAN = '59000ef1d8cfc7d4fd77f9631ca1552177f1c45aef14608c05ff8061434dd78b'
DISCOVERY_PREPARER = '2ff9589131de7fac106a9462d1a0e6ce4c6f727e28d59082fddcdd0e8c45c16d'
MATRIX_PREPARER = 'c3e1876004fa8dae38a82c6cf3d3de3d7aab983976644b09b89c210b4020bd25'
POLICY = '1aad53905c18fdd8020c72a75d4faa6caddf2752097896fd5fe055fa578b202f'
REPORT = 'bd9409445d98517a99a84b2082ac9401f40332b2944828eee74de73496f74ca2'
ORIGINAL_RESULT = 'a2d054ac36ac97e729d292956a2233f10b479b6f40194fec90c9f088858be844'
ORIGINAL_CONFIG = 'b078e691b04f3e2acfee6c1ddcd4f0ca934b500062593bb72d24592e882e7f5a'
ORIGINAL_PACKET = '383041f192e2537a1071baec1fb691d52490fb187f84350ce05843fcd61f4a78'
PRIOR_CONTINUATION_RESULT = 'ddcd0576ed61827896eac96a52ae44a7d98cbb9f202137d7a38ecb887838359b'
PRIOR_CONTINUATION_PACKET = 'f917e27571429d65c6a5447c8dced41d61df63a97ac2b11899a84cc454a08de2'
PRIOR_COMPLETION_RESULT = '0e76f5398b6bb4244b9b7f65c76408d26e40ccfaf7b1b35d31589f07fbc3d493'
PRIOR_COMPLETION_PACKET = '63cbcc7b6b81e15c723be42c53f8070c324a202e2c63f5b5ce857b3c2a90ab2e'
DECODER = 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4'
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

    # This check precedes every read of the active matrix evidence or console.
    # Absence of RESULT never triggers waiting, polling, or partial packaging.
    need((E / 'RESULT.json').is_file(), 'Refuse: matrix RESULT.json is absent; execution is not terminal')
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
    read(R / 'run_checkpoint_matrix.py', SUP)
    seal_raw = read(R / 'CANDIDATE-V35-SOURCE-SEAL.json', SEAL)
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
    need(type(result['sequence_completed']) is bool and result['scope'] == config['scope'], 'Terminal scope')
    need(result['source_seal_unchanged'] is True, 'Supervisor did not attest unchanged source')
    need(result['sdk_identity_unchanged'] is (parse(sdk_before) == parse(sdk_after)), 'SDK comparison differs')
    need(isinstance(result['remaining_owned_descendants'], list), 'Missing final descendant receipt')
    need(config['phase'] == PHASE and config['source'] == str(R / 'candidate-v35')
         and config['seal'] == 'CANDIDATE-V35-SOURCE-SEAL.json' and config['source_seal_sha256'] == SEAL,
         'Exact matrix source configuration')
    need(config['two_probe_owner_approval'] == 'pending; separate explicit owner approval required'
         and config['launch_authorized'] is False, 'Preserve original prepared policy metadata')
    need(window['supervisor_sha256'] == config['supervisor_sha256'] == SUP
         and window['source_seal_sha256'] == SEAL and window['python_optimize'] == 0
         and window['runtime_gate_seconds'] == 5, 'Original supervisor/window identity')
    need(window['whole_window_seconds'] == config['window_seconds'] == 21600,
         'Exact aggregate orchestration budget')
    need(datetime.fromisoformat(result['finished']) >= datetime.fromisoformat(window['started']), 'Terminal chronology')
    need(type(result['elapsed_seconds']) in (float, int) and result['elapsed_seconds'] >= 0, 'Terminal elapsed time')
    inventory_path = R / 'FINAL-PYTHON-EXPECTED-INVENTORY-V35.json'
    inventory = parse(read(inventory_path, INVENTORY))
    need(config['expected_inventory_sha256'] == INVENTORY and config['expected_inventory'] == str(inventory_path)
         and inventory['source_seal_sha256'] == SEAL, 'Fresh discovery/inventory binding')
    need(inventory['module_count'] == 77 and inventory['consumer_module_count'] == 76
         and inventory['test_count_per_mode'] == 1343 and inventory['expected_executions_both_modes'] == 2686
         and inventory['authority_test_count_per_mode'] == 95, 'Fresh final inventory counts')
    need(inventory['supervisor_sha256'] == SUP and inventory['pinned_sdk_receipt_sha256'] == SDK
         and inventory['preparer_sha256'] == MATRIX_PREPARER
         and inventory['frozen_report_bytes_sha256'] == config['frozen_report_bytes_sha256'] == REPORT
         and config['policy_source_sha256'] == POLICY, 'Inventory policy, producer and SDK bindings')
    publication = parse(read(R / 'PUBLISHED-V35-QUALIFICATION-BINDING.json', PUBLICATION))
    need(publication['source_seal_sha256'] == SEAL and publication['inventory_sha256'] == INVENTORY
         and publication['matrix_config_sha256'] == CONFIG and publication['manifest_sha256'] == PUBLICATION_MANIFEST
         and publication['published_commit'] == PUBLISHED_COMMIT and publication['published_tree'] == PUBLISHED_TREE
         and publication['published_parent'] == '031f9f726edb6e9409853fd777af966c8ebba88d'
         and publication['separate_two_probe_owner_approval'] == 'pending', 'Published exact-source binding')
    read(R / 'PUBLISHABLE-V35-12-PATH-MANIFEST.json', PUBLICATION_MANIFEST)
    source_manifest_path = R / 'policy-implementation-v35/CUMULATIVE-TWELVE-PATH-SOURCE-MANIFEST.json'
    source_manifest = parse(read(source_manifest_path, SOURCE_MANIFEST))
    need(source_manifest['source_seal_sha256'] == SEAL and source_manifest['delta_count'] == 12
         and len(source_manifest['files']) == 12 and source_manifest['policy_source_sha256'] == POLICY,
         'Cumulative reviewed source manifest')
    plans = config['stages']
    labels = [stage['label'] for stage in plans]
    need(len(plans) == len(set(labels)) == 154 and sum(stage['expected_tests'] for stage in plans) == 2686,
         'Exact full-matrix stage and execution inventory')
    need(all(re.fullmatch(r'\d{2}-(normal|optimized)-test_\w+', label) for label in labels), 'Unsafe stage label')
    modules = {row['path']: row for row in inventory['modules']}
    need(len(modules) == len(inventory['modules']) == 77, 'Fresh module inventory differs')
    authority_path = 'tools/carla_lane_oracle/test_full_audit_cleanup_contracts.py'
    ordered_modules = [row for row in inventory['modules'] if row['path'] != authority_path] + [modules[authority_path]]
    required_plans = []
    for index, module in enumerate(ordered_modules):
        directory, filename = module['path'].rsplit('/', 1)
        for mode, name in ((0, 'normal'), (1, 'optimized')):
            required_plans.append(dict(label=f"{index:02d}-{name}-{filename[:-3]}",
                command=['{python}'] + (['-O'] if mode else []) +
                    ['-B', '-m', 'unittest', 'discover', '-s', directory, '-p', filename, '-v'],
                expected_tests=module['test_count'], seconds=3600 if module['path'] == authority_path else 1800))
    need(plans == required_plans, 'Exact full union, mode commands, authority-last order or stage caps differ')

    # All fresh discovery evidence is already terminal and remains distinct from test bodies.
    discovery_config = parse(read(R / (DISC + '.json'), DISCOVERY_CONFIG))
    discovery = parse(read(DE / 'RESULT.json', DISCOVERY))
    need(config['discovery_result_sha256'] == inventory['discovery_result_sha256'] == DISCOVERY
         and inventory['discovery_config_sha256'] == DISCOVERY_CONFIG
         and inventory['discovery_program_sha256'] == DISCOVERY_PROGRAM
         and inventory['module_plan_sha256'] == PLAN, 'Fresh discovery protocol pins')
    read(R / 'discover_python_module_v2.py', DISCOVERY_PROGRAM)
    read(R / 'FINAL-PYTHON-MODULE-PLAN-V35.json', PLAN)
    read(R / 'prepare_final_python_discovery_v35.py', DISCOVERY_PREPARER)
    read(R / 'prepare_final_python_matrix_v35.py', MATRIX_PREPARER)
    need(discovery['sequence_completed'] is True and discovery['failure'] is None
         and discovery['source_seal_unchanged'] is True and discovery['sdk_identity_unchanged'] is True
         and discovery['remaining_owned_descendants'] == [] and len(discovery['stages']) == 154,
         'Completed fresh discovery receipt')
    for name, digest in inventory['discovery_evidence_sha256'].items():
        need(name in {'RESULT.json', 'SOURCE-SEAL.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'},
             'Unexpected discovery fixed evidence path')
        read(DE / name, digest)
    need(read(DE / 'SDK-BEFORE.json', SDK) == read(DE / 'SDK-AFTER.json', SDK) == sdk_before
         and read(DE / 'SOURCE-SEAL.json', SEAL) == seal_raw, 'Discovery/matrix source and SDK binding')
    discovery_window = parse(read(DE / 'WINDOW-START.json'))
    need(discovery_config['source_seal_sha256'] == discovery_window['source_seal_sha256'] == SEAL
         and discovery_window['supervisor_sha256'] == SUP
         and discovery_window['whole_window_seconds'] == discovery_config['window_seconds'] == 1800,
         'Discovery source/supervisor/window')
    discovery_names = {'RESULT.json', 'SOURCE-SEAL.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'}
    discovery_receipts = {}
    for index, receipt in enumerate(discovery['stages']):
        planned = discovery_config['stages'][index]
        label = receipt['label']
        need(label == planned['label'] and re.fullmatch(r'discover-(normal|optimized)-\d{2}', label),
             'Discovery stage label/order')
        argv = [part.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python'))
                .replace('{mojo}', str(R.parent / 'restored-toolchain/official-venv/bin/mojo'))
                .replace('{evidence}', str(DE)).replace('{root}', str(R)) for part in planned['command']]
        need(receipt['argv'] == argv and receipt['cwd'] == str(R / 'candidate-v35')
             and receipt['source_seal_sha256'] == SEAL and receipt['stage_timeout_seconds'] == planned['seconds'] == 180
             and receipt['returncode'] == 0 and receipt['timed_out'] is False and receipt['leader_reaped'] is True
             and receipt['remaining_owned_descendants'] == [], 'Discovery actual command/outcome/cap')
        for suffix in ('-START.json', '-RESULT.json', '.log'):
            discovery_names.add(label + suffix)
            read(DE / (label + suffix))
        need(parse(observed[DE / (label + '-RESULT.json')]) == receipt, 'Discovery receipt mismatch')
        need(all(receipt.get(key) == value for key, value in parse(observed[DE / (label + '-START.json')]).items()),
             'Discovery START mismatch')
        need(SHA(observed[DE / (label + '.log')]) == receipt['log_sha256'], 'Discovery log mismatch')
        discovery_receipts[label] = receipt
    seen_ids = {0: set(), 1: set()}
    for module in inventory['modules']:
        need(module['sha256'] == seal[module['path']], 'Discovered source/seal identity')
        for mode in (0, 1):
            row = module['modes'][str(mode)]
            record_path = Path(row['discovery_record'])
            log_path = Path(row['discovery_log'])
            receipt_path = Path(row['discovery_stage_receipt'])
            need(record_path.parent == log_path.parent == receipt_path.parent == DE
                 and record_path.suffix == '.json' and log_path.suffix == '.log'
                 and receipt_path.name == record_path.stem + '-RESULT.json'
                 and log_path.stem == record_path.stem, 'Exact discovery member paths')
            discovery_names.add(record_path.name)
            record = parse(read(record_path, row['discovery_record_sha256']))
            need(all(row[key] == value for key, value in record.items())
                 and record['test_bodies_executed'] is False and record['optimize'] == mode
                 and record['test_count'] == len(record['test_ids']) == module['test_count']
                 and len(set(record['test_ids'])) == len(record['test_ids'])
                 and record['path'] == module['path'] and record['sha256'] == module['sha256'],
                 'Actual discovery IDs/count/mode/source')
            need(not seen_ids[mode].intersection(record['test_ids']), 'Duplicate global discovery IDs')
            seen_ids[mode].update(record['test_ids'])
            read(log_path, row['discovery_log_sha256'])
            need(parse(read(receipt_path, row['discovery_stage_receipt_sha256'])) == discovery_receipts[record_path.stem],
                 'Inventory/discovery stage binding')
            read(DE / (record_path.stem + '-START.json'), row['discovery_stage_start_sha256'])
        need(module['modes']['0']['test_ids'] == module['modes']['1']['test_ids'], 'Mode test identities differ')
    need(len(seen_ids[0]) == len(seen_ids[1]) == 1343, 'Global discovery identity count')
    discovery_console_path = R / (DISC + '.supervisor.log')
    discovery_console = [parse(line) for line in read(discovery_console_path, DISCOVERY_CONSOLE).decode().splitlines()]
    need(discovery_console == discovery['stages'] + [discovery], 'Complete original discovery console')
    discovery_actual_names = {path.name for path in DE.iterdir()}
    need(discovery_actual_names == discovery_names | {'LATEST.json', 'PROCESSES.jsonl'},
         'Unexpected or missing completed discovery files')

    # Preserve earlier failed attempts as immutable provenance, never backfill outcomes.
    prior_files = [
        ('evidence/full-python-matrix-final-v28/RESULT.json', ORIGINAL_RESULT, 'original-failed-matrix/RESULT.json'),
        ('full-python-matrix-final-v28.json', ORIGINAL_CONFIG, 'original-failed-matrix/config.json'),
        ('validation-evidence-full-matrix-v28-failure-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json', ORIGINAL_PACKET,
         'original-failed-matrix/PUBLISHABLE-EVIDENCE-MANIFEST.json'),
        ('evidence/full-python-diagnostic-continuation-v28/RESULT.json', PRIOR_CONTINUATION_RESULT, 'prior-continuation/RESULT.json'),
        ('validation-evidence-diagnostic-continuation-v28-terminal-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json', PRIOR_CONTINUATION_PACKET,
         'prior-continuation/PUBLISHABLE-EVIDENCE-MANIFEST.json'),
        ('evidence/full-python-diagnostic-completion-v28/RESULT.json', PRIOR_COMPLETION_RESULT, 'prior-completion/RESULT.json'),
        ('validation-evidence-diagnostic-completion-v28-terminal-packet/PUBLISHABLE-EVIDENCE-MANIFEST.json', PRIOR_COMPLETION_PACKET,
         'prior-completion/PUBLISHABLE-EVIDENCE-MANIFEST.json')]
    for relative, digest, name in prior_files:
        value = parse(read(R / relative, digest))
        if name.endswith('/RESULT.json'):
            need(value['sequence_completed'] is False and bool(value['failure']), 'Prior failure changed')
    stages = result['stages']
    need(isinstance(stages, list) and len(stages) <= len(plans), 'Invalid terminal recorded prefix')
    need([stage['label'] for stage in stages] == labels[:len(stages)], 'Recorded stages are not the exact configured prefix')
    need(len(console) == len(stages) + 1, 'Console does not contain each stage plus final result exactly once')
    modules = {row['path']: row for row in inventory['modules']}
    need(len(modules) == inventory['module_count'] == 77, 'Fresh module inventory differs')
    original_names = set()
    stage_summaries = []
    unrun = []
    missing_count_annotations = []
    for index, planned in enumerate(plans):
        label = planned['label']
        need(planned['seconds'] == (3600 if index >= 152 else 1800)
             and not planned.get('accept_nonzero', False), 'Original matrix cap/failure-stop policy')
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
                         and start['stage_timeout_seconds'] == planned['seconds'] and start['cwd'] == str(R / 'candidate-v35'),
                         'Incomplete launch START binding')
                observed[files['.log']].decode('utf-8')
            unrun.append(dict(position_one_based=index+1, label=label, module=module_path,
                              command=argv, expected_methods=planned['expected_tests'], mode=int(mode),
                              derived_unrun_from_recorded_prefix=True, actual_artifacts=sorted(path.name for path in present.values()),
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
             and receipt['cwd'] == str(R / 'candidate-v35') and receipt['source_seal_sha256'] == SEAL
             and receipt['stage_timeout_seconds'] == planned['seconds'] and receipt['log_sha256'] == SHA(log_raw),
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
        observed_skips = max(skip_lines, details.get('skipped', 0))
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
            outcome = 'nonzero_matrix_stage'
        elif not annotated or reported_methods != planned['expected_tests'] or observed_skips:
            outcome = 'zero_return_without_complete_expected_inventory'
        else:
            need(status == 'OK', 'Zero-return stage does not report ordinary zero-skip OK')
            outcome = 'passed_matrix_stage'
        stage_summaries.append(dict(position_one_based=index+1, label=label, module=module_path, mode=int(mode),
                                    outcome=outcome, expected_methods=planned['expected_tests'],
                                    reported_methods=reported_methods, unittest_status_line=status,
                                    reported_failure_records=details.get('failures', 0) if status else None,
                                    reported_error_records=details.get('errors', 0) if status else None,
                                    reported_skips=details.get('skipped', 0) if status else None,
                                    inline_skipped_events=skip_lines, observed_skips=observed_skips,
                                    count_annotations_present=annotated, returncode=receipt['returncode'],
                                    timed_out=receipt['timed_out'], elapsed_seconds=receipt['seconds'],
                                    stage_timeout_seconds=receipt['stage_timeout_seconds'],
                                    log_bytes=len(log_raw), log_sha256=SHA(log_raw)))
    # Match the original supervisor's fail-stop predicates, independently of
    # the stricter derived summary-skip observation used to decide matrix PASS.
    need(all(row['returncode'] == 0 and row['timed_out'] is False
             and stages[index]['remaining_owned_descendants'] == []
             and row['count_annotations_present'] and row['inline_skipped_events'] == 0
             for index, row in enumerate(stage_summaries[:-1])),
         'Matrix continued after an original supervisor fatal condition')
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
        add(E / name, 'actual/' + PHASE + '/' + name, 'original-terminal-matrix-log-receipt-or-binding',
            name in ('RESULT.json', 'FAILURE.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'WINDOW-START.json'))
    add(console_path, 'actual/' + console_path.name, 'complete-actual-terminal-matrix-console')
    for name in sorted(discovery_names):
        add(DE / name, 'actual/' + DISC + '/' + name, 'original-fresh-discovery-no-test-body-evidence')
    add(discovery_console_path, 'actual/' + discovery_console_path.name, 'complete-actual-discovery-console')
    for name in (PHASE + '.json', DISC + '.json', 'run_checkpoint_matrix.py', 'discover_python_module_v2.py',
                 'prepare_final_python_discovery_v35.py', 'prepare_final_python_matrix_v35.py',
                 'FINAL-PYTHON-MODULE-PLAN-V35.json', 'FINAL-PYTHON-EXPECTED-INVENTORY-V35.json',
                 'CANDIDATE-V35-SOURCE-SEAL.json', 'PUBLISHED-V35-QUALIFICATION-BINDING.json',
                 'PUBLISHABLE-V35-12-PATH-MANIFEST.json'):
        add(R / name, 'reproduce/' + name, 'exact-protocol-inventory-source-or-published-binding',
            name in (PHASE + '.json', 'run_checkpoint_matrix.py', 'PUBLISHED-V35-QUALIFICATION-BINDING.json'))
    add(source_manifest_path, 'reproduce/CUMULATIVE-TWELVE-PATH-SOURCE-MANIFEST.json', 'exact-frozen-source-manifest')
    for relative, digest, name in prior_files:
        add(R / relative, 'provenance/' + name, 'separate-unchanged-prior-failure-provenance')
    source_paths = {row['path'] for row in source_manifest['files']} | set(modules) | {
        'tools/coverage_toolchain_identity.py', 'tools/carla_lane_oracle/runtime-source-pins.json'}
    for relative in sorted(source_paths):
        path = R / 'candidate-v35' / relative
        read(path, seal[relative])
        add(path, 'reproduce/source/' + relative, 'exact-named-seal-bound-reproducible-source')
    need(seal['docs/validation/full-audit-721-qualification-policy.md'] == POLICY, 'Policy source binding')
    outcomes = Counter(row['outcome'] for row in stage_summaries)
    matrix_passed = (result['sequence_completed'] is True and result['failure'] is None
        and len(stages) == 154 and outcomes == {'passed_matrix_stage': 154}
        and result['source_seal_unchanged'] is True and result['sdk_identity_unchanged'] is True
        and result['remaining_owned_descendants'] == []
        and sum(row['reported_methods'] or 0 for row in stage_summaries) == 2686)
    unrun_inventory = dict(schema=1, kind='derived-configured-unrun-suffix', stages=unrun,
        stage_count=len(unrun), expected_methods=sum(row['expected_methods'] for row in unrun),
        boundary='Expected counts are not executed-test counts. Incomplete launch artifacts are distinct from never-launched stages; standard RESULT has no unrun field, so this suffix is derived from its exact recorded prefix.')
    summary = dict(schema=1,
        status='COMPLETE_MATRIX_EXECUTION_PASS_POLICY_ACCEPTANCE_PENDING' if matrix_passed else 'MATRIX_EXECUTION_FAILED_OR_INCOMPLETE',
        matrix_test_execution_passed=matrix_passed, qualification_passed=False,
        two_probe_owner_approval='pending; not granted or inferred by this packet',
        policy_acceptance_boundary='The exact run can pass its configured matrix while the separate two-probe policy approval remains pending. This builder never supplies that approval or overall qualification credit. Any later approval requires its own original evidence.',
        sequence_completed=result['sequence_completed'], failure=result['failure'],
        finished=result['finished'], elapsed_seconds=result['elapsed_seconds'],
        source_seal_sha256=SEAL, source_seal_unchanged=result['source_seal_unchanged'],
        sdk_before_sha256=SHA(sdk_before), sdk_after_sha256=SHA(sdk_after), sdk_identity_unchanged=result['sdk_identity_unchanged'],
        remaining_owned_descendants=result['remaining_owned_descendants'],
        published_commit=PUBLISHED_COMMIT, published_tree=PUBLISHED_TREE, published_binding_sha256=PUBLICATION,
        config_sha256=CONFIG, supervisor_sha256=SUP, result_sha256=SHA(result_raw), console_sha256=SHA(console_raw),
        inventory_sha256=INVENTORY, configured_window_seconds=21600,
        caps=dict(ordinary_module_seconds=1800, authority_module_seconds=3600, authority_module=authority_path,
                  authority_child_seconds=120, maintained_individual_limits='Exact source policy retained; two named 10-to-30 changes await separate owner approval', native_runtime_gate_metadata_seconds=5),
        configured_module_count=77, configured_stage_count=154, configured_expected_method_executions=2686,
        configured_methods_per_mode=1343, recorded_terminal_stage_count=len(stages),
        stage_outcome_counts=dict(outcomes), stage_outcomes=stage_summaries,
        reported_method_count=sum(row['reported_methods'] or 0 for row in stage_summaries),
        passing_method_executions_in_complete_stages=sum(row['reported_methods'] for row in stage_summaries if row['outcome']=='passed_matrix_stage'),
        stages_without_unittest_method_summary=[row['label'] for row in stage_summaries if row['reported_methods'] is None],
        stages_without_post_run_count_annotations=missing_count_annotations,
        unrun_inventory='UNRUN-INVENTORY.json', unrun_stage_count=len(unrun),
        fresh_discovery=dict(phase=DISC, result_sha256=DISCOVERY, config_sha256=DISCOVERY_CONFIG,
            console_sha256=DISCOVERY_CONSOLE, stages_completed=154, expected_ids_per_mode=1343, test_bodies_executed=False),
        previous_failed_attempts=[dict(original_path=relative, sha256=digest) for relative,digest,name in prior_files if name.endswith('/RESULT.json')],
        frozen_source_payload_count=len(source_paths),
        counting_boundary='Ran N counts methods, while failure/error records may include subtests. These record counts are not subtracted from method counts. Interrupted logs may have no total. Supervisor inline skip annotations are preserved; an additional summary skip observation is separately disclosed.',
        stability_boundary='Source and SDK stability are original sealed supervisor receipts, not a new candidate or SDK scan. Named included source bytes are checked against the source seal at packaging; missing annotations never imply completed post-stage checks.',
        launch_metadata_boundary='The original prepared config retains launch_authorized=false and its prepared scope text. The later exact published binding records parent release for evidence collection. Neither is rewritten or treated as two-probe policy approval.',
        scope='Terminal evidence for the complete configured v35 Python matrix attempt, with actual run outcome and pending policy acceptance kept separate. Prior failures remain failures; native, coverage, hosted CI, readiness and issue completion are outside this packet.',
        excluded='Polling-only LATEST/PROCESSES, private review/design notes, active or later run files, full repository and SDK images.',
        evidence_policy='Complete original terminal logs/receipts/consoles and fresh discovery evidence, named sealed sources/protocol, separate historical failure bindings, and explicitly derived summaries. No tests, native execution, candidate scans or edits, uploads, or invented receipts.')
    commands = dict(schema=1, kind='derived-terminal-command-and-cap-index', source_seal_sha256=SEAL,
        config_sha256=CONFIG, supervisor_sha256=SUP, inventory_sha256=INVENTORY, whole_window_seconds=21600,
        stages=[dict(position_one_based=i+1, planned=planned, actual=stages[i] if i<len(stages) else None)
                for i,planned in enumerate(plans)])

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
    guide='''# Terminal v35 full-matrix evidence

Read VALIDATION-SUMMARY.json for the actual complete PASS or preserved failure.
Matrix test execution and policy acceptance are separate: the two named Python
10-to-30-second changes still lack owner approval in this frozen protocol.
Even a complete 2,686-execution matrix PASS does not grant that approval or
establish overall qualification, native/coverage/CI readiness or issue completion.

This exact published v35 attempt configures 77 modules, 154 stages and 1,343
methods per mode. All 76 consumer modules precede the full 95-method authority
module. Only those two authority stages use 3,600 seconds; other stages retain
1,800 seconds. The aggregate window is 21,600 seconds. Original prepared config
and later published release binding are retained unchanged, including their
original launch/policy wording. No historical failure is rewritten.

Every existing planned matrix START/RESULT/log and the complete terminal console
is preserved. Missing stage summaries or annotations remain missing. An incomplete
launch must have its log and any START must match its exact command/source/cap.
UNRUN-INVENTORY.json derives the exact unexecuted suffix from original receipts.
Failure/error records may include subtests and are not distinct failed methods.
Zero skips are required for the derived complete matrix execution PASS.

All completed fresh discovery IDs/receipts/logs and console are separately bound;
discovery runs no test bodies and adds no passing execution credit. Named source
payloads include every selected test module, twelve changed paths and SDK support.
Unchanged full repository and SDK images are referenced by commit/seal, not bundled.
Earlier failed matrix and diagnostics retain their own RESULT and packet identity.
Active or later authority remainder evidence and private review notes are excluded.

Original bytes are indexed by path, source, size and SHA256. Archived members are
base64 JSON compressed with deterministic gzip mtime=0, then UTF-8 base64. No log
is truncated, normalized or replaced by a summary. The outer manifest seals all
payloads except itself. Summary, command and unrun indexes are labeled derived.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The decoder verifies safe paths, hashes and sizes and never executes contents.
This builder requires supplied exact terminal RESULT/console/builder hashes and
performs no candidate-tree scan, repository import, test, native run or upload.
'''
    payloads.extend([(archive,encoded,'lossless-original-terminal-evidence'),
                     ('INNER-MEMBER-MANIFEST.json',JSON(inner),'complete-original-member-inventory'),
                     ('VALIDATION-SUMMARY.json',JSON(summary),'derived-matrix-outcome-and-policy-scope-summary'),
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
        need(not any(word in row['path'].lower() for word in ('dream_notes', 'scratch_notes', 'independent-review', 'independent-audit')),
             'Private note path: ' + row['path'])
    # Recheck every consumed original, protocol byte and terminal directory member.
    # This does not inspect candidate source or live process state.
    need({path.name for path in E.iterdir()} == actual_names, 'Terminal directory membership changed')
    need({path.name for path in DE.iterdir()} == discovery_actual_names, 'Discovery directory membership changed')
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
                          matrix_test_execution_passed=matrix_passed,qualification_passed=False,original_bytes=inner['original_member_bytes'],
                          packet_bytes_including_manifest=sum(row['bytes'] for row in rows)+len(raw(manifest)))))


if __name__ == '__main__':
    main()
