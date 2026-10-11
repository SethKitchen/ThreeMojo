"""Compare fresh paired observer logs. This program never runs native code.

Accept only one completed passing TestSuite test and its complete CASE/END
record. Remove only TestSuite framing; retain every other byte of observation.
"""
from pathlib import Path
import argparse, hashlib, json, re

HEADER = re.compile(rb'^Running 1 tests? for .+\s*$')
PASS = re.compile(rb'^    PASS \[\s*[0-9]+(?:\.[0-9]+)?\s*\] test_selected_case\s*$')
SUMMARY = re.compile(rb'^Summary \[\s*[0-9]+(?:\.[0-9]+)?\s*\] 1 tests? run: 1 passed , 0 failed , 0 skipped\s*$')


OBSERVATION_TAGS = {
    b'CERT', b'CELL', b'STATUS', b'ERROR', b'DELTA', b'LIMITS', b'PENDING',
    b'TASK', b'TERMINAL', b'INPUT_CELL', b'GOAL', b'EXTERNAL', b'GOAL_EXCLUDES',
    b'RESUME_AFTER_EXCEPTION', b'SUPPORT',
}


def validate_payload(block: bytes, case: str):
    """Validate the driver's complete ordered grammar without rewriting bytes."""
    lines = block.splitlines(keepends=True)
    position = 1  # CASE and END identity already checked by observations().

    def take(tag, count=None):
        nonlocal position
        if position >= len(lines) - 1:
            raise ValueError('Missing ' + tag + ' in ' + case)
        line = lines[position]
        position += 1
        if not line.endswith(b'\n') or line.endswith(b'\r\n'):
            raise ValueError('Malformed observation newline')
        fields = line[:-1].split(b' ')
        if fields[0] != tag.encode() or (count is not None and len(fields) != count + 1):
            raise ValueError('Malformed or out-of-order ' + tag + ' in ' + case)
        return fields[1:]

    def number(word, maximum=(1 << 63) - 1):
        if not re.fullmatch(rb'0|[1-9][0-9]*', word) or int(word) > maximum:
            raise ValueError('Invalid unsigned observation integer: ' + repr(word))
        return int(word)

    def boolean(word):
        if word not in (b'True', b'False'):
            raise ValueError('Invalid observation Bool')

    def words(values):
        for value in values:
            number(value, (1 << 64) - 1)

    def cells(tag, count):
        for index in range(count):
            values = take(tag, 6)
            if number(values[0]) != index:
                raise ValueError('Cell index/order mismatch')
            words(values[1:3] + values[4:6])
            number(values[3])

    def certificate(label):
        values = take('CERT', 12)
        if values[0] != label.encode():
            raise ValueError('Unexpected certificate label')
        words(values[1:8])
        boolean(values[8])
        nodes, terms, count = map(number, values[9:12])
        cells('CELL', count)
        return nodes, terms

    def result(before):
        status = take('STATUS', 1)[0]
        if status not in (b'ok', b'exception'):
            raise ValueError('Invalid result status')
        # ERROR text may contain spaces. Keep all bytes after its length prefix.
        error = take('ERROR')
        if len(error) < 2:
            raise ValueError('Missing ERROR text field')
        length = number(error[0])
        message = b' '.join(error[1:])
        message.decode('utf-8', errors='strict')
        if length != len(message) or (status == b'ok') != (length == 0):
            raise ValueError('ERROR length/status mismatch')
        delta = tuple(map(number, take('DELTA', 2)))
        after = certificate('after')
        if delta != tuple(a - b for a, b in zip(after, before)):
            raise ValueError('DELTA disagrees with certificate ledgers')
        return after

    refine = {'ordinary-no-proof', 'cached-proof', 'enlarged-proof',
              'stale-proof', 'thin-width-proof', 'above-eager-threshold'}
    goals = {'goal-cached', 'goal-stale', 'goal-grouped-interior', 'goal-grouped-endpoint'}
    resumes = {'resume-cached-exact', 'resume-cached-one-short',
               'resume-enlarged-exact', 'resume-enlarged-one-short',
               'headroom-480', 'headroom-489', 'headroom-490',
               'enlarged-headroom-489', 'node-one-short'}
    observe = {'grouped-endpoint-partition', 'grouped-interior-partition',
               'depth-zero-grouped', 'cache-line-edge-seed', 'cache-line-center-seed',
               'cache-spiral-edge-seed', 'cache-spiral-center-seed',
               'frozen-node-headroom', 'frozen-term-headroom', 'frozen-full-headroom',
               'frozen-active-zero-gap', 'support-depth-0', 'support-depth-1', 'support-depth-2',
               'sampled-depth-0', 'sampled-depth-1', 'sampled-depth-3', 'sampled-partition-depth-1'}
    observe |= {prefix + str(i) for prefix in ('order-prefix-', 'order-reversed-prefix-')
                for i in range(1, 7)}
    if case in refine:
        result((0, 0))
    elif case in goals:
        before = certificate('before')
        goal = take('GOAL', 3)
        words(goal[:2])
        boolean(goal[2])
        words(take('EXTERNAL', 3))
        result(before)
        boolean(take('GOAL_EXCLUDES', 1)[0])
    elif case in resumes:
        before = certificate('before')
        for value in take('LIMITS', 3):
            number(value)
        after = result(before)
        if case in {'resume-cached-one-short', 'resume-enlarged-one-short'}:
            take('RESUME_AFTER_EXCEPTION', 0)
            resumed = certificate('before-resume')
            if resumed != after:
                raise ValueError('Resume reset published ledgers')
            result(resumed)
    elif case in observe:
        if case.startswith('support-depth-'):
            words(take('SUPPORT', 2))
        before = certificate('before')
        for value in take('LIMITS', 3):
            number(value)
        pending = number(take('PENDING', 1)[0])
        expected_pending = 1
        if case.startswith('order-') or case == 'grouped-interior-partition':
            expected_pending = 3
        elif case in {'grouped-endpoint-partition', 'sampled-partition-depth-1'}:
            expected_pending = 2
        elif case in {'frozen-node-headroom', 'frozen-term-headroom', 'frozen-full-headroom'}:
            expected_pending = 0
        if pending != expected_pending:
            raise ValueError('Missing or extra fixture pending tasks')
        for index in range(pending):
            task = take('TASK', 4)
            if number(task[0]) != index:
                raise ValueError('Task index/order mismatch')
            words(task[1:3])
            number(task[3])
        terminal = number(take('TERMINAL', 1)[0])
        if terminal != (1 if expected_pending == 0 else 0):
            raise ValueError('Missing or extra fixture terminal cells')
        cells('INPUT_CELL', terminal)
        result(before)
    else:
        raise ValueError('Undeclared case grammar: ' + case)
    if position != len(lines) - 1:
        raise ValueError('Extra or duplicated observation records in ' + case)


def observations(data: bytes, case: str) -> bytes:
    headers = passes = summaries = separators = 0
    first = ('CASE ' + case + '\n').encode()
    last = ('END ' + case + '\n').encode()
    kept = []
    in_case = ended = False
    for line in data.splitlines(keepends=True):
        stripped = line.rstrip(b'\r\n')
        if line == first:
            if in_case or ended:
                raise ValueError('Duplicate case record: ' + case)
            in_case = True
            kept.append(line)
        elif in_case:
            if line == last:
                in_case = False
                ended = True
            elif stripped.split(b' ', 1)[0] not in OBSERVATION_TAGS:
                raise ValueError('Unknown or malformed observation line: ' + repr(line))
            kept.append(line)
        elif not stripped.strip():
            continue
        elif HEADER.fullmatch(stripped):
            headers += 1
        elif PASS.fullmatch(stripped):
            passes += 1
        elif SUMMARY.fullmatch(stripped):
            summaries += 1
        elif stripped == b'--------':
            separators += 1
        else:
            raise ValueError('Unexpected data outside observation block: ' + repr(line))
    if in_case or not ended:
        raise ValueError('Missing complete case record: ' + case)
    if (headers, passes, summaries, separators) != (1, 1, 1, 1):
        raise ValueError('Missing or duplicate complete passing TestSuite frame: ' + case)
    # Observation bytes are never trimmed, normalized, parsed and rerendered,
    # or sorted. Matching crashes or merely matching END tags are not enough.
    block = b''.join(kept)
    validate_payload(block, case)
    return block


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--cases', required=True, type=Path)
    parser.add_argument('--mode', required=True, choices=['O3', 'O0'])
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--contract', required=True, type=Path)
    args = parser.parse_args()
    cases = json.loads(args.cases.read_text())
    if not isinstance(cases, list) or len(cases) != 49 or len(set(cases)) != 49:
        raise ValueError('Expected all 49 distinct declared cases')
    contract = json.loads(args.contract.read_text())
    source_seal = args.evidence / 'SOURCE-SEAL.json'
    if hashlib.sha256(source_seal.read_bytes()).hexdigest() != contract['receipt_source_seal_sha256']:
        raise ValueError('Executing supervisor source seal differs from planned candidate')
    build_records = {}
    for side in ['before', 'after']:
        label = f'{side}-{args.mode}-build'
        status_path = args.evidence / (label + '-RESULT.json')
        status = json.loads(status_path.read_text())
        binary = args.evidence / (side + '-' + args.mode + '-bin')
        expected_command = [contract['mojo'], 'build', '-I', contract[side + '_root'],
                            '--num-threads', '1', '--target-triple=x86_64-unknown-linux-gnu',
                            '--target-cpu=x86-64-v3', '--Werror', '-' + args.mode,
                            contract['driver'], '-o', str(binary)]
        if (status.get('argv') != expected_command or status.get('returncode') != 0
                or status.get('timed_out') or status.get('remaining_owned_descendants')
                or not status.get('leader_reaped') or status.get('stage_timeout_seconds') != 180
                or status.get('source_seal_sha256') != contract['receipt_source_seal_sha256']):
            raise ValueError('Build does not establish the declared side: ' + label)
        build_log = args.evidence / (label + '.log')
        build_log_digest = hashlib.sha256(build_log.read_bytes()).hexdigest()
        if build_log_digest != status.get('log_sha256'):
            raise ValueError('Build log changed after supervised execution: ' + label)
        build_records[side] = {
            'log_sha256': build_log_digest,
            'status_sha256': hashlib.sha256(status_path.read_bytes()).hexdigest(),
            'binary_sha256_after_runs': hashlib.sha256(binary.read_bytes()).hexdigest(),
            'command': expected_command,
        }
    rows = []
    ok = True
    for index, case in enumerate(cases):
        row = {'case': case, 'index': index, 'mode': args.mode}
        values = {}
        for side in ['before', 'after']:
            label = f'{side}-{args.mode}-case-{index:02d}'
            status_path = args.evidence / (label + '-RESULT.json')
            status = json.loads(status_path.read_text())
            expected_command = [contract['python'], contract['runner'], '--seconds', '5',
                                '--suite', contract['driver'], '--', '/usr/bin/env',
                                'THREEMOJO_LANE_PHASE_CASE=' + case,
                                str(args.evidence / (side + '-' + args.mode + '-bin'))]
            if (status.get('argv') != expected_command
                    or status.get('stage_timeout_seconds') != 15
                    or status.get('source_seal_sha256') != contract['receipt_source_seal_sha256']
                    or status.get('returncode') != 0 or status.get('timed_out')
                    or status.get('remaining_owned_descendants')
                    or not status.get('leader_reaped')):
                raise ValueError('Unsuccessful or unclean native case: ' + label)
            path = args.evidence / (label + '.log')
            raw = path.read_bytes()
            digest = hashlib.sha256(raw).hexdigest()
            if digest != status.get('log_sha256'):
                raise ValueError('Log changed after supervised execution: ' + label)
            values[side] = observations(raw, case)
            row[side] = {'log_sha256': digest,
                         'observation_sha256': hashlib.sha256(values[side]).hexdigest(),
                         'status_sha256': hashlib.sha256(status_path.read_bytes()).hexdigest()}
        row['equal'] = values['before'] == values['after']
        ok &= row['equal']
        rows.append(row)
    result = {'complete': True, 'all_equal': ok, 'mode': args.mode,
              'paired_cases': len(rows), 'pairs': rows, 'builds': build_records,
              'scope': 'Fresh exported observations only; no internal traversal trace or old full-search count-refusal reachability claim.'}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    if not ok:
        raise SystemExit('One or more exact observation pairs differ')
    print(f'{args.mode}: all {len(rows)} exact observable pairs match')


if __name__ == '__main__':
    main()
