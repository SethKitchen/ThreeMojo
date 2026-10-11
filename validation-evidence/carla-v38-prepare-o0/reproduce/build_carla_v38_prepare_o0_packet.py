"""Create a local, bounded preparation/O0 evidence packet after explicit release.

Source-only until reviewed. Stdlib only: no project imports, subprocesses,
compiler/native commands, tests, profiler, network, source/SDK tree traversal,
or uploads. Exact terminal RESULT and complete console hashes are mandatory.
A separately reviewed manifest pins every original by relative path/size/hash.
Failure/partial terminal attempts are preserved and cannot become a PASS.
"""
from collections import Counter
from datetime import datetime
from pathlib import Path, PurePosixPath
import argparse
import base64
import gzip
import hashlib
import json
import math
import re
import stat

R = Path(__file__).resolve().parent
O = R / 'validation-evidence-carla-v38-prepare-o0-packet'
INPUT = 'CARLA-V38-PREPARE-O0-TERMINAL-INPUT-MANIFEST.json'
PROTOCOL = 'fresh-capture-plan/prepared/carla-final-v38'
PREP = 'evidence/carla-final-v38-prepare'
NATIVE = 'evidence/carla-final-v38-native-o0'
BUILD = PREP + '/source/coverage/build'
DECODER = 'validation-evidence-qualification-policy-v23-packet/decode_verify.py'
COMMIT = '7b6f7a740208ed1d8d2aa9dd4e359b455188951f'
TREE = '825df51c2d142bb744349c5afb4ff556c626290b'
SOURCE_SHA = '47eb6c57d3d88f116326dfab6bb999d31e909f532a396318b05fd2254dac8537'
SDK_SHA = '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207'
SUPERVISOR_SHA = '9418d41fb962d00dbe4bd53107ef476428ba0c591f4478ac08d332ef907927ce'
PREP_RESULT_SHA = '2eea6b913a9fb365f86587f9f7b4dec18ca4e4628a40a359b5c7a4bf66bc4061'
PREP_CONSOLE_SHA = '27e4c91141ae1025e11695eb455113e3d8bcbd5d4cf653f2e83a33daa6ff74ca'
PINS = {
    'CANDIDATE-V38-SOURCE-SEAL.json': SOURCE_SHA,
    'PUBLISHED-V38-QUALIFICATION-BINDING.json': 'f9f68c2382ef5e1961f092ac9638d2e0a575711a2cffbe89047e93b52d546190',
    PROTOCOL + '-SEAL.json': '5f2958c3fe76b2a383ace2eb026c33dd89bd204b008d2093ed56af58a52f050f',
    'run_stage.py': SUPERVISOR_SHA,
}
PROTOCOL_NAMES = ('COMMANDS.txt', 'capture.json', 'capture_support.py', 'finish.json',
                  'native-o0.json', 'native-o3.json', 'plan.json', 'prepare.json', 'settings.json')
SUITES = tuple('tests/' + name + '.mojo' for name in (
    'test_carla_tight_rounding', 'test_carla_sampled_value_bounds',
    'test_carla_junction_endpoint_refusals', 'test_carla_chord_endpoint_refusals',
    'test_carla_retained_boundary_guards', 'test_carla_width_overflow_admission',
    'test_carla_lane_center_bound_phase', 'test_carla_speed_parser_exceptions',
    'test_carla_lane_proof_fallback_residuals', 'test_carla_lane_cache_scale_residuals',
    'test_carla_lane_search_positive_controls', 'test_carla_lane_search_edge_controls',
    'test_carla_goal_directed', 'test_carla_rounded_arc_witness',
    'test_spiral_lazy_taylor_paths', 'test_carla_optional_followup',
    'test_carla_junction_arithmetic_states', 'test_carla_lane_local_scale_goal',
    'test_spiral_domain_map_integration'))
MODULES = tuple('extensions/carla/' + name + '.mojo' for name in (
    'lane_value_bounds', 'curve_bounds', 'junction_bounds', 'lane_refinement', 'speed_limits'))
PREP_LABELS = ('copy-source', 'native-inventory', 'begin-generation', 'instrument',
               'copy-passthrough', 'seal-generation', 'freeze-targets')
NATIVE_LABELS = tuple(Path(suite).stem + '-' + mode for suite in SUITES
                      for mode in ('build', 'run')) + ('native-summary-o0',)
PHASE_BASE = ('RESULT.json', 'SDK-BEFORE.json', 'SDK-AFTER.json', 'SOURCE-SEAL.json', 'WINDOW-START.json')
PREP_EXTRAS = ('COMPILER-VERSION.txt', 'GENERATION-RESULT.json', 'MATERIALIZATION.json',
               'NATIVE-INVENTORY.json', 'STAGED-SEAL.json', 'TARGET-SEAL.json',
               'frozen-target/FREEZE-RECEIPT.json', 'frozen-target/TARGET-DENOMINATOR.json',
               'frozen-target/target-manifest.txt')
GENERATED = ('generation-inputs.json', 'origins.ready', 'loop-proofs.json', 'manifest.txt') + tuple(
    name + '.cov-origin' for name in MODULES)
LIMIT = 64 * 1024 * 1024
MAX_ORIGINAL_BYTES = 32 * 1024 * 1024
SHA = lambda data: hashlib.sha256(data).hexdigest()
JSON = lambda value: (json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n').encode()
CANON = lambda value: json.dumps(value, ensure_ascii=True, sort_keys=True,
                                separators=(',', ':'), allow_nan=False).encode()


def need(condition, message):
    if not condition:
        raise ValueError(message)


def relative(name):
    need(isinstance(name, str) and name and '\\' not in name and '\0' not in name, 'Invalid relative path')
    path = PurePosixPath(name)
    need(not path.is_absolute() and all(p not in ('', '.', '..') for p in name.split('/'))
         and ':' not in path.parts[0], 'Unsafe relative path')
    return Path(*path.parts)


def raw(name):
    path = R
    parts = relative(name).parts
    for index, part in enumerate(parts):
        path /= part
        mode = path.lstat().st_mode
        need(stat.S_ISREG(mode) if index == len(parts) - 1 else stat.S_ISDIR(mode),
             'Symlink or nonregular input: ' + name)
    need(path.stat().st_size <= LIMIT, 'Oversize input: ' + name)
    data = path.read_bytes()
    need(len(data) <= LIMIT, 'Input grew beyond limit: ' + name)
    data.decode('utf-8', errors='strict')
    return data


def unique(pairs):
    result = {}
    for key, value in pairs:
        need(key not in result, 'Duplicate JSON key')
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite JSON')))


def digest(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def seconds(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def runtime(data):
    """Audit raw TestSuite records as data; mirror the sealed maintained contract."""
    text = re.sub(r'\x1b\[[0-9;]*m', '', data.decode('utf-8'))
    time = r'[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?'
    header = re.compile(r'^\s*Running\s+(\d+)\s+tests?\s+for\s+.+?\s*$')
    result = re.compile(r'^\s*(PASS|FAIL|SKIP)\s*\[\s*(' + time + r')\s*\]\s*(\S+)')
    summary = re.compile(r'^\s*Summary\s*\[\s*' + time + r'\s*\]\s*'
        r'(\d+)\s+tests?\s+run:\s*(\d+)\s+passed\s*,\s*(\d+)\s+failed\s*,\s*(\d+)\s+skipped\s*$')
    headers, summaries, records = [], [], []
    for number, line in enumerate(text.splitlines()):
        if match := header.fullmatch(line):
            headers.append((number, int(match.group(1))))
        if match := summary.fullmatch(line):
            summaries.append((number, tuple(map(int, match.groups()))))
        if match := result.match(line):
            records.append((number, match.group(1), float(match.group(2)), match.group(3)))
    errors = []
    totals = None
    if len(headers) != 1 or len(summaries) != 1:
        errors.append('Expected one complete runtime header and summary')
    else:
        total, passed, failed, skipped = totals = summaries[0][1]
        count = Counter(row[1] for row in records)
        if total <= 0 or total != headers[0][1] or passed + failed + skipped != total:
            errors.append('Header/summary counts disagree or are empty')
        if (count['PASS'], count['FAIL'], count['SKIP']) != (passed, failed, skipped):
            errors.append('Runtime result records disagree with summary')
        if not headers[0][0] < summaries[0][0] or any(
                not headers[0][0] < row[0] < summaries[0][0] for row in records):
            errors.append('Runtime results outside header/summary')
        if failed or skipped:
            errors.append('Failed or skipped runtime tests')
    tests = [row[3] for row in records]
    if len(tests) != len(set(tests)):
        errors.append('Duplicate runtime test identities')
    if any(not math.isfinite(row[2]) or row[2] > 5000 for row in records):
        errors.append('Runtime test exceeds five seconds')
    return dict(valid=not errors, errors=errors, tests=tests, reported_counts=(dict(
        zip(('total', 'passed', 'failed', 'skipped'), totals)) if totals else None),
        result_records=len(records), output_sha256=SHA(data),
        max_reported_test_ms=max((row[2] for row in records if math.isfinite(row[2])), default=None))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('builder', 'input-manifest', 'prepare-result', 'prepare-console', 'o0-result', 'o0-console'):
        parser.add_argument('--expected-' + name + '-sha256', required=True)
    args = parser.parse_args()
    need(all(digest(value) for value in vars(args).values()), 'All six exact SHA256 values are required')
    need(args.expected_prepare_result_sha256 == PREP_RESULT_SHA
         and args.expected_prepare_console_sha256 == PREP_CONSOLE_SHA, 'Reviewed preparation terminal identity differs')
    need(not O.exists() and not O.is_symlink(), 'Create-only output already exists')
    observed = {}

    def read(name, expected):
        need(digest(expected), 'Missing exact digest: ' + name)
        data = raw(name)
        need(SHA(data) == expected, 'Exact input hash mismatch: ' + name)
        need(name not in observed or observed[name] == data, 'Input changed: ' + name)
        observed[name] = data
        return data

    builder = read(Path(__file__).name, args.expected_builder_sha256)
    input_raw = read(INPUT, args.expected_input_manifest_sha256)
    inputs = parse(input_raw)
    need(set(inputs) == {'schema', 'originals'} and inputs['schema'] == 1, 'Unexpected input manifest schema')
    rows = inputs['originals']
    need(isinstance(rows, list) and 1 <= len(rows) <= 240, 'Unbounded original manifest')
    indexed = {}
    for row in rows:
        need(set(row) == {'source', 'bytes', 'sha256'}, 'Unexpected manifest fields')
        relative(row['source'])
        need(row['source'] not in indexed and digest(row['sha256'])
             and type(row['bytes']) is int and 0 <= row['bytes'] <= LIMIT, 'Invalid original metadata')
        indexed[row['source']] = row
    need(sum(row['bytes'] for row in rows) <= MAX_ORIGINAL_BYTES, 'Original inventory exceeds 32 MiB')
    terminal = {PREP + '/RESULT.json': args.expected_prepare_result_sha256,
                NATIVE + '/RESULT.json': args.expected_o0_result_sha256,
                'carla-final-v38-prepare.supervisor.log': args.expected_prepare_console_sha256,
                'carla-final-v38-native-o0.supervisor.log': args.expected_o0_console_sha256}
    for name, value in terminal.items():
        need(name in indexed and indexed[name]['sha256'] == value, 'Terminal manifest pin differs: ' + name)
    # Read exact terminal RESULTs first. No active/polling file is ever read.
    results = {phase: parse(read(phase + '/RESULT.json', terminal[phase + '/RESULT.json']))
               for phase in (PREP, NATIVE)}
    for phase, result in results.items():
        need(type(result['sequence_completed']) is bool and result['finished']
             and datetime.fromisoformat(result['finished']).tzinfo is not None
             and seconds(result['elapsed_seconds']), 'Not a terminal phase result: ' + phase)
        need(isinstance(result['stages'], list), 'Malformed terminal stage list')
    expected = set(PINS) | set(terminal)
    expected.update(PROTOCOL + '/' + name for name in PROTOCOL_NAMES)
    expected.update(PREP + '/' + name for name in PREP_EXTRAS)
    expected.update(BUILD + '/' + name for name in GENERATED)
    for phase, labels in ((PREP, PREP_LABELS), (NATIVE, NATIVE_LABELS)):
        expected.update(phase + '/' + name for name in PHASE_BASE)
        actual_labels = [stage['label'] for stage in results[phase]['stages']]
        need(actual_labels == list(labels[:len(actual_labels)]), 'Stages are not an exact planned prefix')
        if phase == PREP:
            need(tuple(actual_labels) == PREP_LABELS, 'Preparation is incomplete')
        for label in actual_labels:
            expected.update(phase + '/' + label + suffix for suffix in ('-START.json', '-RESULT.json', '.log'))
        if results[phase]['failure'] is not None:
            expected.add(phase + '/FAILURE.json')
        # A failed launch can leave the next log or START without a RESULT.
        if len(actual_labels) < len(labels):
            for suffix in ('-START.json', '.log'):
                name = phase + '/' + labels[len(actual_labels)] + suffix
                if name in indexed:
                    expected.add(name)
    if NATIVE + '/NATIVE-SUMMARY.json' in indexed:
        expected.add(NATIVE + '/NATIVE-SUMMARY.json')
    fixtures = [name for name in indexed if name.startswith(NATIVE + '/fixture-cache/')]
    need(len(fixtures) <= 1 and all(re.fullmatch(re.escape(NATIVE) + r'/fixture-cache/[0-9a-f]{64}\.json',
                                               name) for name in fixtures), 'Unapproved fixture metadata paths')
    expected.update(fixtures)
    need(set(indexed) == expected, 'Manifest differs from the strict terminal original allowlist')
    originals = {}
    for name in sorted(expected):
        row = indexed[name]
        data = read(name, row['sha256'])
        need(len(data) == row['bytes'], 'Original byte length differs: ' + name)
        originals[name] = data

    def obj(name):
        return parse(originals[name])

    for name, value in PINS.items():
        need(SHA(originals[name]) == value, 'Reviewed identity differs: ' + name)
    seal = obj('CANDIDATE-V38-SOURCE-SEAL.json')
    need(len(seal) == 3842 and all(digest(value) for value in seal.values()), 'Incomplete source seal')
    for name in seal:
        relative(name)
    publication = obj('PUBLISHED-V38-QUALIFICATION-BINDING.json')
    need(publication['commit'] == COMMIT and publication['tree'] == TREE
         and publication['source_seal_sha256'] == SOURCE_SHA, 'Published source binding differs')
    bundle = obj(PROTOCOL + '-SEAL.json')
    need(set(bundle) == set(PROTOCOL_NAMES), 'Protocol is not the reviewed nine-file bundle')
    for name, value in bundle.items():
        need(SHA(originals[PROTOCOL + '/' + name]) == value, 'Protocol member changed')
    cfg = obj(PROTOCOL + '/settings.json')
    plan = obj(PROTOCOL + '/plan.json')
    need(tuple(cfg['suites']) == SUITES and tuple(plan['measured_modules']) == MODULES
         and cfg['source_seal_sha256'] == SOURCE_SHA and cfg['supervisor_sha256'] == SUPERVISOR_SHA
         and cfg['helper_sha256'] == bundle['capture_support.py'] and cfg['plan_sha256'] == bundle['plan.json'],
         'Protocol settings binding differs')
    inventory = obj(PREP + '/NATIVE-INVENTORY.json')
    need(inventory['total_inputs'] == 95 and inventory['mojo_inputs'] == 93
         and len(inventory['union']) == 95 and inventory['consumed_module_instances_identical'] is True
         and inventory['native_dependency_inputs_checked_for_all_suites'] is True
         and inventory['source_seal_sha256'] == SOURCE_SHA
         and inventory['suites'] == plan['native_closure']['suites']
         and inventory['union'] == plan['native_closure']['union']
         and all(seal[name] == value for name, value in inventory['union'].items())
         and all(seal[name] == value for name, value in inventory['tool_hashes'].items()), 'Native 95-input closure differs')
    need(obj(PREP + '/MATERIALIZATION.json') == dict(complete=True, file_count=3842,
                                                  source_seal_sha256=SOURCE_SHA), 'Materialization record differs')
    staged = obj(PREP + '/STAGED-SEAL.json')
    for name in GENERATED:
        need(SHA(originals[BUILD + '/' + name]) == staged[name], 'Generated provenance changed: ' + name)
    envelope = obj(BUILD + '/loop-proofs.json')
    proof = envelope['receipt']
    need(set(envelope) == {'receipt', 'sha256'} and SHA(CANON(proof)) == envelope['sha256'], 'Proof envelope hash differs')
    generation = obj(PREP + '/GENERATION-RESULT.json')
    full_manifest = originals[BUILD + '/manifest.txt']
    need(envelope['sha256'] == generation['proof_sha256']
         and SHA(full_manifest) == generation['full_manifest_sha256'] == proof['manifest_sha256']
         and SHA(originals[BUILD + '/origins.ready']) == proof['generation']['index_sha256']
         and SHA(originals[BUILD + '/generation-inputs.json']) == proof['generation']['checkpoint_sha256'],
         'Generation/proof/manifest binding differs')
    checkpoint = obj(BUILD + '/generation-inputs.json')
    need(len(checkpoint['root_inputs']) == 3633 and checkpoint['root_inputs'] == proof['root_inputs']
         and all(seal[name] == value for name, value in checkpoint['root_inputs'].items())
         and tuple(checkpoint['sources']) == MODULES,
         'Generation checkpoint source closure differs')
    expected_sdk = obj(PREP + '/SDK-BEFORE.json')
    for command in (checkpoint['compiler_command'], proof['execution']['compiler']):
        need(len(command) == 1 and command[0]['path'] == cfg['mojo']
             and {key: value for key, value in command[0].items() if key != 'path'} == expected_sdk,
             'Generation/proof full SDK identity differs')
    fragments = []
    for name in MODULES:
        origin = originals[BUILD + '/' + name + '.cov-origin']
        header, payload = origin.split(b'\n', 1)
        fields = header.split()
        need(len(fields) == 5 and fields[0] == b'COVORIGIN1'
             and all(re.fullmatch(rb'[0-9]+', x) for x in fields[1:]), 'Malformed generation origin')
        lengths = list(map(int, fields[1:]))
        need(sum(lengths) == len(payload), 'Origin lengths differ')
        parts, offset = [], 0
        for length in lengths:
            parts.append(payload[offset:offset + length]); offset += length
        need(parts[0].decode() == name and SHA(parts[1]) == seal[name]
             and SHA(parts[2]) == staged[name], 'Original/staged origin identities differ')
        need(proof['generation']['modules'][name] == dict(source=SHA(parts[1]), instrumented=SHA(parts[2]),
             origin_sha256=SHA(origin), fragment_sha256=SHA(parts[3])), 'Proof origin binding differs')
        fragments.append(parts[3])
    need(b''.join(fragments) == full_manifest, 'Five origin fragments do not reconstruct the full manifest')
    target = obj(PREP + '/TARGET-SEAL.json')
    need(set(target) == {'FREEZE-RECEIPT.json', 'TARGET-DENOMINATOR.json', 'target-manifest.txt'}, 'Target seal differs')
    for name, value in target.items():
        need(SHA(originals[PREP + '/frozen-target/' + name]) == value, 'Frozen target binding differs')
    denominator = obj(PREP + '/frozen-target/TARGET-DENOMINATOR.json')
    target_raw = originals[PREP + '/frozen-target/target-manifest.txt']
    counts = Counter(line.split()[0] for line in target_raw.decode().splitlines())
    need(dict(counts) == denominator['kind_counts'] and counts == Counter(B=38, C=30, L=127, M=30, P=1)
         and counts['L'] + 2 * counts['B'] + 2 * counts['C'] + counts['M'] + counts['R']
             == denominator['required_targeted_obligations'] == 293
         and denominator['selected_manifest_sha256'] == SHA(target_raw)
         and denominator['original_manifest_sha256'] == SHA(full_manifest)
         and denominator['current_proof_sha256'] == envelope['sha256']
         and denominator['original_manifest_rows'] == len(full_manifest.decode().splitlines()) == 2955,
         'Frozen scoped denominator differs')
    need(obj(PREP + '/frozen-target/FREEZE-RECEIPT.json') == dict(
        schema='carla-pre-capture-target-freeze-v1', source_seal_sha256=SOURCE_SHA,
        plan_sha256=bundle['plan.json'], helper_sha256=bundle['capture_support.py'],
        manifest_sha256=SHA(target_raw), denominator_sha256=target['TARGET-DENOMINATOR.json'],
        proof_sha256=envelope['sha256'], capture_directory_absent_at_freeze=True), 'Freeze receipt differs')

    phase_reports, runtime_reports = {}, []
    for phase, config_name, labels, window in (
            (PREP, 'prepare.json', PREP_LABELS, 1200), (NATIVE, 'native-o0.json', NATIVE_LABELS, 4005)):
        result = results[phase]
        config = obj(PROTOCOL + '/' + config_name)
        need(tuple(row['label'] for row in config['stages']) == labels
             and config['window_seconds'] == window and result['scope'] == config['scope'], 'Exact phase plan differs')
        before, after = obj(phase + '/SDK-BEFORE.json'), obj(phase + '/SDK-AFTER.json')
        need(SHA(originals[phase + '/SDK-BEFORE.json']) == SDK_SHA
             and originals[phase + '/SOURCE-SEAL.json'] == originals['CANDIDATE-V38-SOURCE-SEAL.json']
             and result['sdk_identity_unchanged'] == (before == after), 'Source/SDK receipt inconsistency')
        start = obj(phase + '/WINDOW-START.json')
        need(start['source_seal_sha256'] == SOURCE_SHA and start['supervisor_sha256'] == SUPERVISOR_SHA
             and start['whole_window_seconds'] == window and start['runtime_gate_seconds'] == 5
             and start['python_optimize'] == 0 and start['sdk_payload_count'] == len(before['payload']) == 13,
             'Supervisor/window identity differs')
        began, ended = datetime.fromisoformat(start['started']), datetime.fromisoformat(result['finished'])
        need(began.tzinfo is not None and began <= ended, 'Phase chronology differs')
        if phase == NATIVE:
            need(datetime.fromisoformat(results[PREP]['finished']) <= began, 'Native phase preceded preparation')
        console_name = Path(phase).name + '.supervisor.log'
        console = [parse(line) for line in originals[console_name].splitlines() if line.strip()]
        need(console == result['stages'] + [result], 'Console is not the exact complete terminal receipt sequence')
        if result['failure'] is not None:
            need(obj(phase + '/FAILURE.json')['error'] == result['failure'], 'Failure receipt differs')
        problems, executed = [], []
        for receipt, planned in zip(result['stages'], config['stages']):
            label = receipt['label']
            prefix = phase + '/' + label
            need(obj(prefix + '-RESULT.json') == receipt, 'Stage RESULT differs from terminal receipt')
            first = obj(prefix + '-START.json')
            need(all(receipt[key] == value for key, value in first.items()), 'Stage START fields changed')
            need(receipt['argv'] == planned['command'] and receipt['cwd'] == planned.get('cwd', cfg['source'])
                 and receipt['stage_timeout_seconds'] == planned['seconds']
                 and receipt['source_seal_sha256'] == SOURCE_SHA and type(receipt['single_cpu']) is int
                 and receipt['single_cpu'] >= 0 and seconds(receipt['seconds'])
                 and receipt['log_sha256'] == SHA(originals[prefix + '.log']), 'Stage commands/caps/log identity differs')
            clean = (receipt['returncode'] == 0 and receipt['timed_out'] is False
                     and receipt['leader_reaped'] is True and receipt['remaining_owned_descendants'] == [])
            need(began <= datetime.fromisoformat(receipt['started']) <= ended, 'Stage outside phase window')
            if phase == NATIVE and label.endswith('-build'):
                need(planned['seconds'] == 180 and '-O0' in receipt['argv'] and '-O3' not in receipt['argv'],
                     'Explicit O0 build control differs')
            if phase == NATIVE and label.endswith('-run'):
                need(planned['seconds'] == 15 and receipt['argv'][3:5] == ['--seconds', '5'],
                     'Native TestSuite/outer runtime gates differ')
            if not clean:
                problems.append('Unsuccessful stage: ' + label)
            if phase == NATIVE and label.endswith('-run'):
                report = runtime(originals[prefix + '.log'])
                report.update(suite='tests/' + label[:-4] + '.mojo', stage_passed=clean)
                runtime_reports.append(report)
                if not report['valid']:
                    problems.append('Runtime contract failed: ' + label)
            executed.append(dict(label=label, argv=receipt['argv'], cwd=receipt['cwd'],
                cap_seconds=receipt['stage_timeout_seconds'], elapsed_seconds=receipt['seconds'],
                returncode=receipt['returncode'], timed_out=receipt['timed_out'],
                log_sha256=receipt['log_sha256'], result_sha256=SHA(originals[prefix + '-RESULT.json'])))
        incomplete = []
        if len(executed) < len(labels):
            label = labels[len(executed)]
            prefix = phase + '/' + label
            if prefix + '-START.json' in originals:
                first = obj(prefix + '-START.json')
                planned = config['stages'][len(executed)]
                need(first['label'] == label and first['argv'] == planned['command']
                     and first['cwd'] == planned.get('cwd', cfg['source'])
                     and first['stage_timeout_seconds'] == planned['seconds']
                     and first['source_seal_sha256'] == SOURCE_SHA,
                     'Partial stage START command binding differs')
            incomplete = [suffix for suffix in ('-START.json', '.log') if prefix + suffix in originals]
        clean_phase = (result['sequence_completed'] is True and result['failure'] is None
                       and result['source_seal_unchanged'] is True and result['sdk_identity_unchanged'] is True
                       and result['remaining_owned_descendants'] == [] and len(executed) == len(labels))
        phase_reports[phase] = dict(status='PASS' if clean_phase and not problems else 'FAILED_OR_PARTIAL',
            terminal_sequence_completed=result['sequence_completed'], failure=result['failure'],
            source_seal_unchanged=result['source_seal_unchanged'], sdk_identity_unchanged=result['sdk_identity_unchanged'],
            remaining_owned_descendants=result['remaining_owned_descendants'], validation_problems=problems,
            executed_stages=len(executed), planned_stages=len(labels),
            next_uncompleted_stage_artifacts=incomplete,
            uncompleted_stage_labels=list(labels[len(executed):]), elapsed_seconds=result['elapsed_seconds'],
            result_sha256=SHA(originals[phase + '/RESULT.json']), console_sha256=SHA(originals[console_name]),
            stages=executed)
    need(phase_reports[PREP]['status'] == 'PASS', 'Pinned preparation no longer validates')
    fixture_identities = {}
    for name in fixtures:
        metadata = obj(name)
        key = Path(name).stem
        inputs_fixture = metadata['inputs']
        need(SHA(json.dumps(inputs_fixture, sort_keys=True).encode()) == key, 'Fixture cache key differs')
        fixture_source = 'tools/fixtures/carla_sum2_fp_state.c'
        compiler = inputs_fixture['compiler']
        need(inputs_fixture['source'] == cfg['clone'] + '/' + fixture_source
             and inputs_fixture['sha256'] == seal[fixture_source] and digest(metadata['object_sha256'])
             and compiler['system'] == 'Linux' and compiler['machine'] == 'x86_64'
             and compiler['flags'] == ['-std=c11', '-O2', '-fPIC', '-Wall', '-Wextra', '-Werror']
             and compiler['files'] == {item['path']: item['sha256'] for item in proof['execution']['native_compiler']},
             'Fixture compiler/source identity differs')
        command = metadata['command']
        need(command[:-1] == compiler['command'] + compiler['flags'] + ['-c', inputs_fixture['source'], '-o']
             and Path(command[-1]).parent == Path(cfg['native_phases']['o0']) / 'fixture-cache'
             and Path(command[-1]).name.startswith(key + '-') and command[-1].endswith('.o'), 'Fixture command differs')
        fixture_identities[key + '.json'] = SHA(originals[name])
        fixture_identities[key + '.o'] = metadata['object_sha256']
    native_summary = None
    if NATIVE + '/NATIVE-SUMMARY.json' in originals:
        native_summary = obj(NATIVE + '/NATIVE-SUMMARY.json')
        need(native_summary['schema'] == 'carla-fresh-native-summary-v1' and native_summary['optimization'] == 'o0'
             and native_summary['source_seal_sha256'] == SOURCE_SHA and native_summary['arm_qualified'] is False
             and native_summary['native_inventory_sha256'] == SHA(originals[PREP + '/NATIVE-INVENTORY.json'])
             and native_summary['fixture_cache_files'] == fixture_identities
             and tuple(row['suite'] for row in native_summary['suites']) == SUITES
             and len(runtime_reports) == 19 and all(row['valid'] and row['stage_passed'] for row in runtime_reports),
             'Emitted native summary does not bind a complete valid O0 run')
        totals = Counter()
        for row, actual in zip(native_summary['suites'], runtime_reports):
            stem = Path(row['suite']).stem
            need(row['actual'] == dict(actual['reported_counts'], tests=actual['tests'],
                 output_sha256=actual['output_sha256'], timing_scope='five seconds per native test')
                 and digest(row['binary_sha256']), 'Native summary runtime/binary identity differs')
            totals.update(actual['reported_counts'])
            for mode in ('build', 'run'):
                path = NATIVE + '/' + stem + '-' + mode
                need(row['stage_receipts'][mode] == dict(path=str(R / (path + '-RESULT.json')),
                     sha256=SHA(originals[path + '-RESULT.json']), log_sha256=SHA(originals[path + '.log'])),
                     'Native summary stage receipt differs')
            if stem == 'test_carla_junction_endpoint_refusals':
                log = originals[NATIVE + '/' + stem + '-run.log'].decode()
                need('LAST_DAZ_CAPABILITY_UNAVAILABLE' not in log and sorted(re.findall(
                     r'^LAST_REFUSAL_LEDGER\s+([56])\s+5\s+5000000005\s+1\s+0\s*$', log, re.M)) == ['5', '6']
                     and re.search(r'^REFUSAL_LEDGER\s+5\s+5000000005\s+1\s+0\s*$', log, re.M)
                     and row['daz_witness'] == dict(last_end_daz_modes=[5, 6], actual_ledgers_verified=True,
                                                  system='Linux', machine='x86_64', arm_qualified=False),
                     'Actual x86 DAZ witness differs')
        need(dict(totals) == native_summary['actual_totals'], 'Native summary aggregate counts differ')
    if phase_reports[NATIVE]['status'] == 'PASS':
        need(native_summary is not None and len(fixtures) == 1, 'Complete O0 requires emitted summary and fixture identity')

    # Narrow terminal directory-name checks ensure no allowed original was omitted.
    # No recursive scans; binaries, polling snapshots and the source clone are not read.
    def phase_inventory(phase, labels):
        folder = R / phase
        need(stat.S_ISDIR(folder.lstat().st_mode), 'Phase directory is not ordinary')
        names = {path.name for path in folder.iterdir()}
        required_names = {name[len(phase) + 1:].split('/')[0] for name in originals if name.startswith(phase + '/')}
        excluded = {'LATEST.json', 'PROCESSES.jsonl'}
        if phase == PREP:
            excluded.add('source')
        else:
            excluded.update(Path(suite).stem + '-bin' for suite in SUITES)
            excluded.add('fixture-cache')
        need(required_names <= names and not names - required_names - excluded, 'Unexpected terminal phase entry')
        for label in labels:
            for suffix in ('-START.json', '-RESULT.json', '.log'):
                name = label + suffix
                need((name in names) == (phase + '/' + name in originals), 'Omitted stage artifact: ' + name)
        if phase == NATIVE and 'fixture-cache' in names:
            cache = folder / 'fixture-cache'
            need(stat.S_ISDIR(cache.lstat().st_mode), 'Fixture cache is not an ordinary directory')
            cache_names = {path.name for path in cache.iterdir()}
            need(cache_names == set(fixture_identities), 'Unexpected or omitted fixture-cache identity')
    phase_inventory(PREP, PREP_LABELS)
    phase_inventory(NATIVE, NATIVE_LABELS)
    patterns = (rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', rb'gh[pousr]_[A-Za-z0-9]{30,}',
                rb'AKIA[0-9A-Z]{16}', rb'(?i)Bearer [A-Za-z0-9._-]{24,}')
    for name, data in originals.items():
        need(not any(re.search(pattern, data) for pattern in patterns), 'Credential pattern in original: ' + name)
    decoder = read(DECODER, 'a8c520204f4bcd9f4dc539df05a9d5afda5bb158e139f9077a3c35811ca020a4')
    archive_name = 'containers/ORIGINAL-EVIDENCE.json.gz.b64'
    archived, members = [], []
    for name, data in sorted(originals.items()):
        path = 'originals/' + name
        row = dict(path=path, bytes=len(data), sha256=SHA(data))
        archived.append(dict(row, data_base64=base64.b64encode(data).decode('ascii')))
        members.append(dict(row, source=name, storage='container', transport_path=archive_name))
    container = CANON(dict(schema=1, encoding='base64', members=archived)) + b'\n'
    need(len(container) <= LIMIT, 'Container exceeds decoder 64 MiB expansion limit')
    encoded = base64.b64encode(gzip.compress(container, compresslevel=9, mtime=0)) + b'\n'
    need(len(encoded) <= LIMIT and gzip.decompress(base64.b64decode(encoded.strip(), validate=True)) == container,
         'Bounded transport round trip differs')
    inner = dict(schema=1, original_member_count=len(members), original_member_bytes=sum(row['bytes'] for row in members),
        container=dict(path=archive_name, members=len(members), json_bytes=len(container), json_sha256=SHA(container)),
        members=members)
    summary = dict(schema=1, status='PREPARATION_PASS_O0_' + phase_reports[NATIVE]['status'],
        source_commit=COMMIT, source_tree=TREE, source_seal_sha256=SOURCE_SHA,
        sdk_identity_sha256=SDK_SHA, protocol_seal_sha256=PINS[PROTOCOL + '-SEAL.json'],
        phases=phase_reports, runtime_suites=runtime_reports,
        actual_totals=native_summary['actual_totals'] if native_summary else None,
        native_summary_emitted=native_summary is not None, fixture_cache_identities=fixture_identities,
        fixture_object_and_binary_bytes_included=False, native_closure_inputs=95,
        frozen_targeted_obligations=293, captured_obligations=None,
        native_o0_qualified=phase_reports[NATIVE]['status'] == 'PASS', full_qualification_claimed=False,
        scope='Linux x86-64 preparation and explicit O0 native controls only. O3, capture, coverage completion, Arm, hosted CI and anatomy-report qualification are not established by this packet.',
        stability_boundary='Source/SDK stability is reported by exact terminal receipts, not a new source or SDK tree scan.',
        source_reproduction='Retrieve the published commit and verify the full source seal. Source clone and compiled binaries are excluded. Five generation-origin records retain embedded source/staged bytes needed for denominator provenance.',
        publication_boundary='The original publication binding retains its earlier pending-qualification status unchanged.')
    guide = ('CARLA v38 preparation and explicit O0 native evidence\n\n'
        'Read VALIDATION-SUMMARY.json for the actual terminal outcome and runtime counts.\n'
        'A failed or partial attempt is preserved; absent stages have no invented receipts.\n'
        'The frozen 293-obligation denominator is preparation provenance, not captured coverage.\n'
        'O3/capture/finish configs are preserved only because they belong to the sealed protocol.\n'
        'Their presence is not execution evidence. No complete CARLA, Arm, hosted CI,\n'
        'anatomy-report, merge-readiness, or performance-headroom claim is made.\n\n'
        'All original receipts/logs and the complete supervisor consoles are byte-exact.\n'
        'Full source/SDK/protocol seals, closure inventory, generation manifests/origins,\n'
        'proof envelope and frozen target records are included. Object/binary identities\n'
        'come from original receipts; their compiled bytes and the source clone are omitted.\n'
        'Only explicit allowlisted originals are packed. No polling or private notes are read.\n'
        'PUBLISHABLE-EVIDENCE-MANIFEST.json seals all payloads except itself.\n'
        'The bounded deterministic gzip/base64 container retains complete original bytes.\n'
        'Verify without writes: python -B decode_verify.py\n'
        'Decode into a new directory: python -B decode_verify.py --output NEW_DIRECTORY\n'
        'The decoder does not execute decoded content. Packaging is local and create-only.\n')
    payloads = [(archive_name, encoded), ('INNER-MEMBER-MANIFEST.json', JSON(inner)),
        ('VALIDATION-SUMMARY.json', JSON(summary)), ('decode_verify.py', decoder), ('README.txt', guide.encode()),
        ('reproduce/' + INPUT, input_raw), ('reproduce/' + Path(__file__).name, builder)]
    # Recheck every consumed byte and terminal inventory before the first output write.
    phase_inventory(PREP, PREP_LABELS)
    phase_inventory(NATIVE, NATIVE_LABELS)
    for name, data in observed.items():
        need(raw(name) == data, 'Input changed during packaging: ' + name)
    O.mkdir(parents=False, exist_ok=False)
    published = []
    for name, data in sorted(payloads):
        path = O / relative(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as target_file:
            target_file.write(data)
        need(raw(str(path.relative_to(R))) == data, 'Written payload differs')
        published.append(dict(path=name, bytes=len(data), sha256=SHA(data)))
    manifest = JSON(dict(schema=1, scope=summary['scope'], files=published))
    with (O / 'PUBLISHABLE-EVIDENCE-MANIFEST.json').open('xb') as target_file:
        target_file.write(manifest)
    need(raw(str(O.relative_to(R)) + '/PUBLISHABLE-EVIDENCE-MANIFEST.json') == manifest, 'Written outer manifest differs')
    print(json.dumps(dict(output=O.name, manifest_sha256=SHA(manifest), status=summary['status'],
        payloads=len(payloads), original_members=len(members), original_bytes=inner['original_member_bytes'],
        native_o0_qualified=summary['native_o0_qualified'], full_qualification_claimed=False), sort_keys=True))


if __name__ == '__main__':
    main()
