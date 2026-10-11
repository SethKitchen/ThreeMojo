"""Package exactly four terminal lexical focused phases after review and release.

Stdlib only. Reads a closed, hash-bound 58-original allowlist. Never imports or
executes candidate/protocol code, traverses candidates, runs tests/profilers,
reads another phase, uploads, or overwrites output. AST inspection is source-only.
Both exact CLI hashes are required; the input manifest pins every original,
including all four terminal RESULTs and complete supervisor consoles.
"""
from pathlib import Path, PurePosixPath
from datetime import datetime
import argparse
import ast
import base64
import gzip
import hashlib
import json
import re
import stat

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-lexical-focused-v36-v37-packet'
INPUT = 'LEXICAL-FOCUSED-V36-V37-INPUT-MANIFEST.json'
INPUT_SHA = '550ea80253312dc3ca463baee4b57adda690667e139f9c564699ad6bb5747eb0'
DECODER_PATH = 'validation-evidence-qualification-policy-v23-packet/decode_verify.py'
DECODER = 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4'
SUPERVISOR = '6727063772b92efdd559328b302db613626025bc6df5159937af56882f67e032'
SDK = '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
DRIVER_PATH = 'winner-cli-paired-diagnostic-v35-protocol/probe.py'
DRIVER = '2a84aebc0d803d443854ad0d80fddc9c12c01a953229b5336b809bde37986fcb'
PROTOCOL = 'a9b8365038e16fd1e6f0a277652b4727bccc22277f737341e3ef41b72600123c'
SEALS = {
    '36': 'd99455479cff76a44adcce2517b5d00e977c0a466046e0ad68c9c4e05f9f707f',
    '37': '5c36727fbd5393d49b9efa1a25edc8621fb4b308ed6ecf61630c30c4992db448',
}
SOURCE_MANIFEST = 'f3ce07626dd86f63c810522a22ad6d34752febdd189f4d14f6de2e45e83b8dd0'
SOURCES = {
    'candidate-v37/tools/carla_lane_oracle/full_audit_cleanup_contracts.py':
        '993496a159a84a9515ee3284cb6a36a8f411820ba4d4d4df0fe5e6766cb74498',
    'candidate-v37/tools/carla_lane_oracle/test_invariant_operation_inputs.py':
        '214a6354c8a2022e04302da022c3afaa79e63446745049fec5aa37942dcacab2',
    'candidate-v36/tools/carla_lane_oracle/test_invariant_operation_inputs.py':
        'a26fa27e426dd13b539fab1dde0251cb40aef2730abed46d66b5127d593cec23',
    'candidate-v37/tools/test_coverage_loop_proofs.py':
        '132f36fb44d44bd84340ff37f82e44cc3fdd3648f298ea2dcd7198ed964e06a5',
}
CONSUMER_PATH = 'candidate-v37/tools/test_coverage_loop_proofs.py'
CONSUMER_METHODS = (
    'test_complete_winner_and_parser_consumers_in_real_script_locations',
    'test_complete_consumers_ignore_foreign_direct_module_shadows',
)
# Phase identities, executed labels, and chronology remain independent.
PHASES = (
    ('root-text-conversion-controls-v36', '36', ('normal-root-text-mechanics',), False, 420, 180, 4, ('0.445',)),
    ('root-text-conversion-controls-v37', '37', ('normal-root-text-mechanics', 'optimized-root-text-mechanics'), True, 420, 180, 4, ('0.470', '0.475')),
    ('winner-cli-root-text-probe-v37', '37', ('v37-normal-cli-winner',), True, 70, 45, 1, ('28.203',)),
    ('winner-consumer-variants-v37', '37', ('normal-maintained-consumer-variants', 'optimized-maintained-consumer-variants'), True, 1900, 900, 2, ('170.075', '171.006')),
)
REFERENCES = (
    'ROOT-TEXT-CONVERSION-V37-SOURCE-MANIFEST.json',
    'CANDIDATE-V36-SOURCE-SEAL.json', 'CANDIDATE-V37-SOURCE-SEAL.json',
    'PUBLISHED-V35-QUALIFICATION-BINDING.json',
    'WINNER-CLI-PAIRED-DIAGNOSTIC-PROTOCOL-SEAL.json', DRIVER_PATH,
    'run_checkpoint_matrix.py',
)
LIMIT = 64 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def relative(name):
    need(isinstance(name, str) and name and '\\' not in name and '\0' not in name, 'Invalid path')
    path = PurePosixPath(name)
    need(not path.is_absolute() and all(p not in ('', '.', '..') for p in name.split('/'))
         and ':' not in path.parts[0], 'Unsafe path')
    return Path(*path.parts)


def raw(path):
    parts = path.relative_to(R).parts
    need(parts and all(p not in ('', '.', '..') for p in parts), 'Unsafe input')
    current = R
    for index, part in enumerate(parts):
        current /= part
        mode = current.lstat().st_mode
        need(stat.S_ISREG(mode) if index == len(parts) - 1 else stat.S_ISDIR(mode),
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


def phase_names(labels, passed):
    names = {'RESULT.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'SOURCE-SEAL.json', 'WINDOW-START.json'}
    names.update(label + suffix for label in labels for suffix in ('-START.json', '-RESULT.json', '.log'))
    if not passed:
        names.add('FAILURE.json')
    return names


def phase_inventory(phase, names):
    # Enumerate only the exact authorized terminal phase, never candidate trees.
    path = R / 'evidence' / phase
    need(stat.S_ISDIR((R / 'evidence').lstat().st_mode)
         and stat.S_ISDIR(path.lstat().st_mode), 'Phase directory must not be a symlink')
    need({p.name for p in path.iterdir()} == names | {'LATEST.json', 'PROCESSES.jsonl'},
         'Unexpected terminal phase inventory: ' + phase)


def expected_plans(phase, version):
    source = R / ('candidate-v' + version)
    if phase.startswith('root-text-conversion-'):
        return [dict(label=mode + '-root-text-mechanics', command=['{python}', '-B']
            + (['-O'] if mode == 'optimized' else []) + ['-m', 'unittest', '-v',
                'test_invariant_operation_inputs.ReviewedAbsoluteRootTextMechanics'],
            cwd=str(source / 'tools/carla_lane_oracle'), expected_tests=4, seconds=180)
            for mode in ('normal', 'optimized')]
    if phase == 'winner-cli-root-text-probe-v37':
        return [dict(label='v37-normal-cli-winner', command=['{python}', '-B', str(R / DRIVER_PATH),
            str(source), SOURCES[CONSUMER_PATH]], cwd=str(source), expected_tests=1, seconds=45)]
    need(phase == 'winner-consumer-variants-v37', 'Unapproved phase')
    return [dict(label=mode + '-maintained-consumer-variants', command=['{python}', '-B']
        + (['-O'] if mode == 'optimized' else []) + ['-m', 'unittest', '-v']
        + ['test_coverage_loop_proofs.MapSuccessorLoopTests.' + method for method in CONSUMER_METHODS],
        cwd=str(source / 'tools'), expected_tests=2, seconds=900) for mode in ('normal', 'optimized')]


def source_variant_index(data):
    # Parse fixed source as data; do not compile, import, eval, or execute it.
    tree = ast.parse(data)
    owner = next(node for node in tree.body if isinstance(node, ast.ClassDef)
                 and node.name == 'MapSuccessorLoopTests')
    methods = {node.name: node for node in owner.body if isinstance(node, ast.FunctionDef)}
    helper = methods['consumer_script_probe']
    runs = [node for node in ast.walk(helper) if isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name)
            and node.func.value.id == 'subprocess' and node.func.attr == 'run']
    need(len(runs) == 1 and [(k.arg, ast.literal_eval(k.value)) for k in runs[0].keywords
         if k.arg == 'timeout'] == [('timeout', 30)], 'Maintained child cap differs')
    variants, definitions = [], []
    for name, modes, shadow in zip(CONSUMER_METHODS, (('cli', 'package', 'direct'), ('cli', 'package')), (False, True)):
        method = methods[name]
        loops = [node for node in ast.walk(method) if isinstance(node, ast.For)]
        need(len(loops) == 2 and ast.literal_eval(loops[0].iter) == ('winner_sign_contracts', 'border_parser_contracts')
             and ast.literal_eval(loops[1].iter) == modes, 'Exact consumer variant loops differ')
        calls = [node for node in ast.walk(method) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Attribute) and node.func.attr == 'consumer_script_probe']
        need(len(calls) == 1 and [(k.arg, ast.literal_eval(k.value)) for k in calls[0].keywords]
             == ([('shadow', True)] if shadow else []), 'Exact consumer shadow call differs')
        definitions.append(dict(method=name, source_line_start=method.lineno, source_line_end=method.end_lineno,
                                variants_per_interpreter_mode=2 * len(modes)))
        for interpreter_mode in ('normal', 'optimized'):
            for consumer in ('winner_sign_contracts', 'border_parser_contracts'):
                for mode in modes:
                    variants.append(dict(method=name, interpreter_mode=interpreter_mode,
                                         consumer=consumer, import_mode=mode, foreign_direct_module_shadow=shadow))
    need(len(variants) == 20, 'Source-defined child variant count differs')
    return dict(schema=1, kind='derived-source-defined-child-variant-index', source=CONSUMER_PATH,
        source_sha256=SOURCES[CONSUMER_PATH], helper_line_start=helper.lineno, helper_line_end=helper.end_lineno,
        maintained_child_cap_seconds=30, variants_per_interpreter_mode=10,
        methods_per_interpreter_mode=2, interpreter_modes=['normal', 'optimized'],
        total_method_executions=4, source_defined_child_variants=20, definitions=definitions, variants=variants,
        attribution='The exact sealed source defines 6 real-script and 4 CLI/package shadow child variants per mode. Two passing methods per mode are logged; no separate per-child receipts or durations are invented. Shadow mode does not include direct.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-input-manifest-sha256', required=True)
    parser.add_argument('--expected-builder-sha256', required=True)
    args = parser.parse_args()
    for name, value in vars(args).items():
        need(re.fullmatch(r'[0-9a-f]{64}', value) is not None, 'Invalid exact hash: ' + name)
    need(args.expected_input_manifest_sha256 == INPUT_SHA, 'Only the reviewed 58-original terminal allowlist is supported')
    need(not O.exists() and not O.is_symlink(), 'Create-only output already exists')
    observed = {}

    def read(name, expected=None):
        path = R / relative(name)
        data = raw(path)
        need(expected is None or SHA(data) == expected, 'Changed exact binding: ' + name)
        need(path not in observed or observed[path] == data, 'Input changed: ' + name)
        observed[path] = data
        return data

    builder = read(Path(__file__).name, args.expected_builder_sha256)
    input_raw = read(INPUT, INPUT_SHA)
    inputs = parse(input_raw)
    need(inputs['schema'] == 1 and inputs['original_member_count'] == 58
         and inputs['original_member_bytes'] == 3290228, 'Exact input inventory differs')
    need(inputs['decoder'] == dict(source=DECODER_PATH, sha256=DECODER), 'Decoder binding differs')
    decoder = read(DECODER_PATH, DECODER)
    expected_sources = set(REFERENCES) | set(SOURCES)
    for phase, version, labels, passed, window, cap, count, timings in PHASES:
        names = phase_names(labels, passed)
        phase_inventory(phase, names)
        expected_sources.update('evidence/' + phase + '/' + name for name in names)
        expected_sources.update((phase + '.json', phase + '.supervisor.log'))
    originals, by_source, destinations = [], {}, set()
    for row in inputs['originals']:
        name, destination = row['source'], row['path']
        relative(destination)
        need(name in expected_sources and name not in by_source and destination not in destinations, 'Unexpected or duplicate original')
        expected_destination = ('actual/' + name[len('evidence/'):] if name.startswith('evidence/')
            else 'actual/' + name if name.endswith('.supervisor.log') else 'reproduce/' + name)
        need(destination == expected_destination, 'Original destination differs')
        need(type(row['bytes']) is int and type(row['readable']) is bool, 'Invalid member metadata')
        data = read(name, row['sha256'])
        need(len(data) == row['bytes'], 'Original byte count differs: ' + name)
        data.decode('utf-8')
        by_source[name] = data
        destinations.add(destination)
        originals.append(dict(row, data=data))
    need(set(by_source) == expected_sources and len(originals) == 58
         and sum(len(row['data']) for row in originals) == inputs['original_member_bytes'], 'Incomplete allowlist')

    def content(name, expected=None):
        need(name in by_source, 'Read outside original allowlist')
        data = by_source[name]
        need(expected is None or SHA(data) == expected, 'Original binding differs: ' + name)
        return data

    seals = {version: parse(content('CANDIDATE-V' + version + '-SOURCE-SEAL.json', seal))
             for version, seal in SEALS.items()}
    for name, digest in SOURCES.items():
        content(name, digest)
        candidate, relative_source = name.split('/', 1)
        need(seals[candidate.removeprefix('candidate-v')][relative_source] == digest, 'Source/seal identity differs')
    test_relative = 'tools/carla_lane_oracle/test_invariant_operation_inputs.py'
    seal_changes = sorted(name for name in set(seals['36']) | set(seals['37'])
                          if seals['36'].get(name) != seals['37'].get(name))
    need(seal_changes == [test_relative], 'Unexpected v36-to-v37 sealed source transition')
    old_test, new_test = content('candidate-v36/' + test_relative), content('candidate-v37/' + test_relative)
    need(new_test.count(b'_root_text_outcome') == 7
         and new_test.replace(b'_root_text_outcome', b'_outcome') == old_test,
         'Exact seven-token test-helper repair differs')
    source_manifest = parse(content('ROOT-TEXT-CONVERSION-V37-SOURCE-MANIFEST.json', SOURCE_MANIFEST))
    final_paths = ['tools/carla_lane_oracle/full_audit_cleanup_contracts.py', 'tools/carla_lane_oracle/test_invariant_operation_inputs.py']
    need(source_manifest['candidate_source_seal_sha256'] == SEALS['37']
         and [row['path'] for row in source_manifest['files']] == final_paths, 'Final two-path source manifest differs')
    for row in source_manifest['files']:
        name = 'candidate-v37/' + row['path']
        need(row['sha256'] == SOURCES[name] and row['bytes'] == len(content(name))
             and row['source'] == str(R / name), 'Final source-manifest member differs')
    publication = parse(content('PUBLISHED-V35-QUALIFICATION-BINDING.json',
        '9f7159cc980b51da7be9ed5b3822cbb0a8c88977794200cf6b24315f9c4a8e2c'))
    need(source_manifest['base_commit'] == publication['published_commit']
         == '19287a0b1564b9a628f15c96e7675c51413ca1a9'
         and publication['published_tree'] == '5c1f67c196fc30d6a323d6d854748b65e3640585', 'Base reference differs')
    content(DRIVER_PATH, DRIVER)
    need(parse(content('WINNER-CLI-PAIRED-DIAGNOSTIC-PROTOCOL-SEAL.json', PROTOCOL)) == {'probe.py': DRIVER}, 'Protocol seal differs')
    content('run_checkpoint_matrix.py', SUPERVISOR)
    variants = source_variant_index(content(CONSUMER_PATH))
    phases, commands = [], []
    for phase, version, labels, passed, window_seconds, cap, count, timings in PHASES:
        prefix = 'evidence/' + phase + '/'
        result = parse(content(prefix + 'RESULT.json'))
        config = parse(content(phase + '.json'))
        window = parse(content(prefix + 'WINDOW-START.json'))
        plans = expected_plans(phase, version)
        need(config['phase'] == phase and config['source'] == str(R / ('candidate-v' + version))
             and config['seal'] == 'CANDIDATE-V' + version + '-SOURCE-SEAL.json'
             and config['window_seconds'] == window_seconds and config['stages'] == plans, 'Exact phase plan differs')
        additional = [dict(source=str(R / Path(DRIVER_PATH).parent),
            seal=str(R / 'WINNER-CLI-PAIRED-DIAGNOSTIC-PROTOCOL-SEAL.json'))] if phase == 'winner-cli-root-text-probe-v37' else []
        need(config.get('additional_sources', []) == additional, 'Additional source bindings differ')
        need(content(prefix + 'SOURCE-SEAL.json', SEALS[version]) == content('CANDIDATE-V' + version + '-SOURCE-SEAL.json'), 'Executed source seal differs')
        before, after = content(prefix + 'SDK-BEFORE.json', SDK), content(prefix + 'SDK-AFTER.json', SDK)
        need(before == after and result['source_seal_unchanged'] is True and result['sdk_identity_unchanged'] is True
             and result['remaining_owned_descendants'] == [] and result['scope'] == config['scope']
             and result['sequence_completed'] is passed and len(result['stages']) == len(labels), 'Terminal stability/outcome differs')
        need(window['supervisor_sha256'] == SUPERVISOR and window['source_seal_sha256'] == SEALS[version]
             and window['whole_window_seconds'] == window_seconds and window['python_optimize'] == 0
             and window['runtime_gate_seconds'] == 5, 'Original window binding differs')
        need(datetime.fromisoformat(result['finished']) >= datetime.fromisoformat(window['started'])
             and 0 <= result['elapsed_seconds'] < window_seconds, 'Terminal chronology/window differs')
        console_lines = content(phase + '.supervisor.log').decode('utf-8').splitlines()
        need(len(console_lines) == len(labels) + 1 and all(console_lines), 'Complete console row count differs')
        console = [parse(line) for line in console_lines]
        need(console[-1] == result, 'Console terminal result differs')
        if passed:
            need(result['failure'] is None, 'Unexpected terminal failure')
        else:
            failure = parse(content(prefix + 'FAILURE.json'))
            need(result['failure'] == failure['error'] == "RuntimeError('Stage failed: normal-root-text-mechanics')", 'Original v36 failure differs')
        stages = []
        for index, label in enumerate(labels):
            receipt = parse(content(prefix + label + '-RESULT.json'))
            start = parse(content(prefix + label + '-START.json'))
            log = content(prefix + label + '.log', receipt['log_sha256']).decode('utf-8')
            plan = plans[index]
            argv = [item.replace('{python}', str(R.parent / 'restored-toolchain/official-venv/bin/python')) for item in plan['command']]
            need(receipt == result['stages'][index] and all(receipt.get(k) == v for k, v in start.items()), 'Original START/RESULT/terminal mismatch')
            need(receipt['label'] == label and receipt['argv'] == argv and receipt['cwd'] == plan['cwd']
                 and receipt['source_seal_sha256'] == SEALS[version] and receipt['stage_timeout_seconds'] == cap
                 and receipt['timed_out'] is False and receipt['leader_reaped'] is True
                 and receipt['remaining_owned_descendants'] == [] and receipt['returncode'] == (0 if passed else 1), 'Original stage execution/cleanup differs')
            printed = {k: v for k, v in receipt.items() if k not in ('test_count', 'expected_tests', 'skipped_test_count')}
            need(console[index] == printed, 'Original console stage row differs')
            need(re.findall(r'^Ran (\d+) tests? in ([0-9.]+)s$', log, re.M) == [(str(count), timings[index])], 'Wrapper count/timing differs')
            if passed:
                need(receipt['test_count'] == receipt['expected_tests'] == count and receipt['skipped_test_count'] == 0
                     and log.endswith('\nOK\n'), 'Original passing method/skip count differs')
            else:
                need(not any(k in receipt for k in ('test_count', 'expected_tests', 'skipped_test_count'))
                     and log.endswith('\nFAILED (failures=1, errors=51)\n')
                     and len(re.findall(r'^ERROR: ', log, re.M)) == 51
                     and len(re.findall(r'^FAIL: ', log, re.M)) == 1, 'Byte-exact v36 failure accounting differs')
            stages.append(dict(label=label, outcome='PASSED' if passed else 'FAILED',
                methods_reported=count, wrapper_reported_seconds=float(timings[index]),
                parent_stage_elapsed_seconds=receipt['seconds'], parent_stage_cap_seconds=cap,
                parent_timed_out=False, returncode=receipt['returncode'], log_sha256=receipt['log_sha256'],
                start_sha256=SHA(content(prefix + label + '-START.json')),
                result_sha256=SHA(content(prefix + label + '-RESULT.json')),
                source_seal_sha256=SEALS[version], remaining_owned_descendants=[]))
        phases.append(dict(phase=phase, version='v' + version, phase_passed=passed,
            original_sequence_completed=result['sequence_completed'], original_failure=result['failure'],
            result_sha256=SHA(content(prefix + 'RESULT.json')), console_sha256=SHA(content(phase + '.supervisor.log')),
            config_sha256=SHA(content(phase + '.json')), source_seal_sha256=SEALS[version],
            source_seal_unchanged=True, sdk_identity_unchanged=True, sdk_before_sha256=SHA(before), sdk_after_sha256=SHA(after),
            started=window['started'], finished=result['finished'], elapsed_seconds=result['elapsed_seconds'],
            configured_window_seconds=window_seconds, remaining_owned_descendants=[], stages=stages,
            unrun_configured_stages=plans[len(labels):], original_scope=result['scope']))
        commands.append(dict(phase=phase, config_sha256=SHA(content(phase + '.json')),
            stages=[dict(position_one_based=i + 1, planned=plan,
                         actual=result['stages'][i] if i < len(labels) else None,
                         execution_state='EXECUTED' if i < len(labels) else 'NEVER_LAUNCHED')
                    for i, plan in enumerate(plans)]))

    summary = dict(schema=1, kind='derived-four-phase-focused-evidence-summary',
        status='TERMINAL_V36_FAILURE_PRESERVED_AND_THREE_V37_FOCUSED_PHASES_PASSED',
        all_phases_passed=False, qualification_passed=False, full_matrix_passed=False,
        hosted_qualification_passed=False, timing_robustness_established=False,
        source_only_packaging=True, input_manifest_sha256=INPUT_SHA, phases=phases,
        successful_v37_method_or_wrapper_executions=13, earlier_v36_methods_reported=4,
        v36_optimized_methods_never_launched=4,
        v36_failure_accounting=dict(ordinary_passed_methods=1, ordinary_error_records=2,
            differential_subtest_error_records=49, failure_records=1, error_records_total=51,
            affected_methods=3, boundary='49 subtest errors and the single failure belong to the same differential method. These are not 52 failed methods. Optimized v36 never launched.'),
        mechanics_differential_cases=dict(per_differential_method_execution=49, fast_cases=19,
            fallback_cases=30, attribution='Source-defined inventory for one of four mechanics methods per interpreter mode; not 49 cases in every method.'),
        consumer_variants=dict(source_defined_count=20, method_executions=4, variants_per_mode=10,
            maintained_child_cap_seconds=30, boundary=variants['attribution']),
        cli_probe=dict(wrapper_reported_seconds=28.203, parent_stage_elapsed_seconds=28.635078032995807,
            maintained_child_cap_seconds=30, parent_stage_cap_seconds=45,
            boundary='28.203s is one unittest wrapper duration, not a raw child-only duration or stable performance headroom.'),
        final_source_manifest_sha256=SOURCE_MANIFEST,
        source_manifest_status_preserved=source_manifest['status'],
        source_manifest_chronology='The original source manifest says affected variants were ongoing. Its bytes remain unchanged; later terminal variant receipts establish the focused outcome.',
        final_changed_source_paths=final_paths,
        v36_to_v37_source_transition=dict(seal_changed_paths=seal_changes,
            exact_test_repair='Replacing the seven _root_text_outcome tokens in v37 test bytes with _outcome exactly reconstructs the preserved v36 test bytes.',
            production_core_sha256=SOURCES['candidate-v37/tools/carla_lane_oracle/full_audit_cleanup_contracts.py'],
            production_core_unchanged_in_both_seals=True,
            boundary='The two complete source-seal mappings differ only in the test file. This is a bounded comparison of supplied seals and named source bytes, not a candidate tree scan.'),
        source_original_roles='Two final v37 changed files, the failed v36 test file, and the unchanged sealed v37 consumer support module. Four originals do not mean four final changed files.',
        base_publication_reference=dict(binding_sha256=SHA(content('PUBLISHED-V35-QUALIFICATION-BINDING.json')),
            published_commit=publication['published_commit'], published_tree=publication['published_tree'],
            boundary='Historical base reference only. No new remote check or v37 source-backup binding is asserted.'),
        stability_boundary='Source/SDK stability and process cleanup are original terminal supervisor receipts; this builder performs no new candidate or SDK scans.',
        scope=inputs['scope'], exclusions=inputs['exclusions'])
    patterns = (rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', rb'gh[pousr]_[A-Za-z0-9]{30,}',
                rb'AKIA[0-9A-Z]{16}', rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
    for row in originals:
        need(not any(re.search(pattern, row['data']) for pattern in patterns), 'Credential pattern: ' + row['path'])
    archive = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
    payloads, members, archived = [], [], []
    for row in sorted(originals, key=lambda item: item['path']):
        data = row['data']
        member = dict(path=row['path'], kind=row['kind'], original_source=str(R / row['source']),
                      bytes=len(data), sha256=SHA(data))
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
    guide = '''# Four distinct terminal lexical focused phases

The earlier v36 normal attempt failed: 4 methods ran, 1 failure and 51 error
records. Its full raw log and FAILURE receipt remain byte-exact. One method
passed; two methods had ordinary errors; the differential method had 49 subtest
errors plus the failure. Those records affect 3 methods, not 52 methods. The
configured optimized v36 stage never launched and has no invented receipt.

Three later v37 focused phases passed independently: 4 normal + 4 optimized
mechanics methods; one normal CLI wrapper (28.203s); and two maintained consumer
methods in each interpreter mode (4 method executions). This is 13 successful
v37 method/wrapper executions, not a full matrix or hosted qualification.

Exactly one mechanics method defines 49 differential cases (19 fast, 30
fallback) per interpreter mode. The sealed consumer source defines 6 real-script
variants and 4 CLI/package shadow variants per mode, 20 child variants overall.
Logs report 2 consumer methods per mode; they do not contain individual child
timings. Shadow variants do not include direct mode. The child cap remains 30s.
The standalone CLI wrapper's 28.203s is not a raw child duration or proof of
repeatable timing headroom; its parent-stage duration and 45s cap are separate.

The four phase identities, source seals, configs, complete consoles, logs,
START/RESULT/FAILURE records, SDK before/after, and window records are preserved.
The source manifest's older 'variants ongoing' status is deliberately unchanged
beside the later terminal receipts. Exactly two final changed source files are
bound by that manifest; the failed v36 test and unchanged v37 consumer support
source are additional audit originals. The v35 publication binding is only a
historical base reference. No v37 remote or source-backup binding is invented.

VALIDATION-SUMMARY, COMMAND-RECEIPT-SEAL and SOURCE-VARIANT-INDEX are derived.
INNER-MEMBER-MANIFEST inventories every one of 58 complete originals by path,
size and SHA256. Archived members are lossless base64 JSON in deterministic gzip
(mtime=0), then base64 text. Evidence is never truncated or replaced by a summary.
The outer manifest seals every payload except itself. LATEST/PROCESSES polling
bytes, private review/design notes, and all other phases are excluded.

Verify without writing: python -B decode_verify.py
Decode into a new directory: python -B decode_verify.py --output /new/directory
The unchanged hash-bound decoder verifies paths, lengths and hashes. It does not
execute or unmarshal content. Builder output is create-only and requires the
reviewed builder and exact input-manifest hashes. Candidate/protocol code and
tests are never imported or executed by packaging. Original source/SDK stability
is attributed to terminal receipts, not new scans. No readiness, merge approval,
issue completion, timing-robustness or broader qualification is claimed.
'''
    payloads += [(archive, encoded, 'lossless-complete-original-evidence'),
        ('INNER-MEMBER-MANIFEST.json', JSON(inner), 'complete-original-member-inventory'),
        ('VALIDATION-SUMMARY.json', JSON(summary), 'derived-four-phase-focused-summary'),
        ('COMMAND-RECEIPT-SEAL.json', JSON(dict(schema=1, supervisor_sha256=SUPERVISOR, phases=commands)), 'derived-command-cap-and-execution-index'),
        ('SOURCE-VARIANT-INDEX.json', JSON(variants), 'derived-sealed-source-variant-index'),
        ('decode_verify.py', decoder, 'unchanged-hash-bound-safe-decoder'),
        ('reproduce/' + INPUT, input_raw, 'source-only-strict-original-allowlist'),
        ('reproduce/' + Path(__file__).name, builder, 'source-only-packet-builder'),
        ('README.md', guide.encode(), 'scope-and-safe-transport-guide')]
    need(len(payloads) == len({name for name, _, _ in payloads}) == 24, 'Exact compact payload count differs')
    for phase, version, labels, passed, window, cap, count, timings in PHASES:
        phase_inventory(phase, phase_names(labels, passed))
    for path, data in observed.items():
        need(raw(path) == data, 'Consumed input changed during packaging: ' + str(path))
    O.mkdir(parents=False, exist_ok=False)
    rows = []
    for name, data, kind in sorted(payloads):
        path = O / relative(name)
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
        status=summary['status'], all_phases_passed=False, qualification_passed=False,
        packet_bytes_including_manifest=sum(row['bytes'] for row in rows) + len(raw(manifest))), sort_keys=True))


if __name__ == '__main__':
    main()
