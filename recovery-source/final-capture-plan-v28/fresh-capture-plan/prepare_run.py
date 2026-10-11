"""Emit source-bound configs only. Never import or execute repository code."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WORK = ROOT.parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def dump(path, value):
    with Path(path).open('x') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')


def snapshot(root):
    result = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if any(part in ('__pycache__', '.cache') for part in relative.parts):
            continue
        if relative.parts[:2] == ('coverage', 'build'):
            continue
        if path.is_symlink():
            raise ValueError('Unreviewed source symlink: ' + str(path))
        if path.is_file():
            result[str(relative)] = sha(path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--source-seal', type=Path, required=True)
    parser.add_argument('--source-seal-sha256', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'carla-[a-z0-9-]+', args.label):
        parser.error('Use a fresh carla-... label; attempts cannot be overwritten')
    if not re.fullmatch(r'[0-9a-f]{64}', args.source_seal_sha256):
        parser.error('Supply the parent independently recorded final source-seal digest')
    source, seal = args.source_root.resolve(), args.source_seal.resolve()
    if sha(seal) != args.source_seal_sha256:
        raise ValueError('Final source-seal digest differs')
    expected = json.loads(seal.read_text())
    if snapshot(source) != expected:
        raise ValueError('Complete source does not match the explicit seal')
    plan = json.loads((HERE / 'plan-spec.json').read_text())
    for name, digest in plan['frozen_hashes'].items():
        if expected.get(name) != digest:
            raise ValueError('Reviewed native input or target changed: ' + name)
    suites = [suite['path'] for suite in plan['suites']]
    if len(suites) != 19 or len(set(suites)) != 19:
        raise ValueError('All 19 suites are mandatory')
    for suite in plan['suites']:
        count = len(re.findall(r'^def\s+test_\w*\s*\(', (source / suite['path']).read_text(), re.M))
        if count != suite['source_test_definitions']:
            raise ValueError('Static definition inventory differs')
    if sum(s['source_test_definitions'] for s in plan['suites']) != 86:
        raise ValueError('Static inventory differs; runtime counts remain authoritative')

    out = HERE / 'prepared' / args.label
    prepared_seal = HERE / 'prepared' / (args.label + '-SEAL.json')
    phases = ['prepare', 'native-o3', 'native-o0', 'capture', 'finish']
    evidence = {phase: ROOT / 'evidence' / (args.label + '-' + phase) for phase in phases}
    for path in [out, prepared_seal, *evidence.values()]:
        if path.exists():
            raise ValueError('Keep every prior attempt: ' + str(path))
    out.mkdir(parents=True, exist_ok=False)
    # Every executable helper/config/plan byte is in a supervisor-sealed bundle.
    helper = out / 'capture_support.py'
    shutil.copy2(HERE / 'capture_support.py', helper)
    plan_path = out / 'plan.json'
    plan['source_seal_sha256'] = args.source_seal_sha256
    plan['preparation_provenance'] = {
        'generator_sha256': sha(__file__), 'spec_sha256': sha(HERE / 'plan-spec.json'),
        'recovered_helper_sha256': sha(WORK / 'recovery-carla-capture-plan/exact/capture_support.py'),
        'reviewed_integration_context': 'ce7e6e038622792b091ce84d545fb2b8597310bf plus reviewed local overlays',
        'status': 'Prepared only. No native, coverage, denominator, or final anatomy result.'}
    dump(plan_path, plan)
    prep, capture = evidence['prepare'], evidence['capture']
    clone, build = prep / 'source', prep / 'source/coverage/build'
    mojo = WORK / 'restored-toolchain/official-venv/bin/mojo'
    python = mojo.parent / 'python'
    settings_path = out / 'settings.json'
    settings = {'source': str(source), 'source_seal': str(seal),
                'source_seal_sha256': args.source_seal_sha256,
                'clone': str(clone), 'build': str(build), 'prepare': str(prep),
                'native_phases': {opt: str(evidence['native-' + opt]) for opt in ('o3', 'o0')},
                'capture': str(capture), 'evidence_phases': {k: str(v) for k, v in evidence.items()},
                'mojo': str(mojo), 'python': str(python), 'flags': '-I .', 'profile': 'aot-hits',
                'coverage_group_seconds': 9000, 'suites': suites, 'plan': str(plan_path),
                'helper_sha256': sha(helper), 'plan_sha256': sha(plan_path),
                'supervisor': str(ROOT / 'run_stage.py'), 'supervisor_sha256': sha(ROOT / 'run_stage.py'),
                'prepared_bundle': str(out), 'prepared_bundle_seal': str(prepared_seal),
                'platform_scope': {'system': 'Linux', 'machine': 'x86_64', 'arm_qualified': False}}
    dump(settings_path, settings)

    def stage(label, command, seconds=180, cwd=None, accept_nonzero=False):
        item = {'label': label, 'command': list(map(str, command)), 'seconds': seconds}
        if cwd is not None:
            item['cwd'] = str(cwd)
        if accept_nonzero:
            item['accept_nonzero'] = True
        return item

    def support(action, *extra, seconds=180):
        return stage(action + ('-' + extra[-1] if extra else ''),
                     [python, '-B', helper, action, '--settings', settings_path, *extra], seconds)

    def config(suffix, stages, window, generated=False):
        additional = [{'source': str(out), 'seal': str(prepared_seal)}]
        if generated:
            additional += [{'source': str(clone), 'seal': str(seal)},
                           {'source': str(build), 'seal': str(prep / 'STAGED-SEAL.json')},
                           {'source': str(prep / 'frozen-target'), 'seal': str(prep / 'TARGET-SEAL.json')}]
        dump(out / (suffix + '.json'), {
            'source': str(source), 'seal': str(seal), 'phase': args.label + '-' + suffix,
            'window_seconds': window, 'stages': stages, 'additional_sources': additional,
            'scope': 'Fresh 19-suite CARLA qualification on the explicitly sealed snapshot. '
                     'Native O3/O0 and maintained instrumented capture are separate. '
                     'Targeted scope only; no global 100%, Arm, hosted CI, or anatomy-report claim.'})

    config('prepare', [support('copy-source'), support('native-inventory'), support('begin-generation'),
        stage('instrument', [mojo, 'run', '-I', '.', 'coverage/build_cli.mojo', build,
              *plan['measured_modules']], cwd=clone), support('copy-passthrough'),
        support('seal-generation'), support('freeze-targets')], 1200)
    for opt in ('o3', 'o0'):
        native = evidence['native-' + opt]
        controls = []
        for suite in suites:
            name = Path(suite).stem
            binary = native / (name + '-bin')
            controls.append(stage(name + '-build', [python, '-B', clone / 'tools/native_test_support.py',
                'run', '--root', clone, '--suite', clone / suite, '--cache', native / 'fixture-cache',
                '--', mojo, 'build', '-I', clone, '--num-threads', '1',
                '--target-triple=x86_64-unknown-linux-gnu', '--target-cpu=x86-64-v3',
                '-O' + opt[-1], '--Werror', clone / suite, '-o', binary], cwd=clone))
            controls.append(stage(name + '-run', [python, '-B', clone / 'tools/run_suite.py',
                '--seconds', '5', '--suite', clone / suite, '--', binary], 15, clone))
        controls.append(support('native-summary', '--optimization', opt))
        config('native-' + opt, controls, len(suites) * 195 + 300, generated=True)
    config('capture', [
        stage('reporter-build', [mojo, 'build', '--Werror', '-I', build,
              build / 'coverage/report_cli.mojo', '-o', capture / 'reporter'], cwd=build),
        stage('maintained-captures', [python, '-B', clone / 'tools/coverage_io.py', 'group',
              '--seconds', '9000', '--', python, '-B', helper, 'capture-batch',
              '--settings', settings_path], 9030, clone),
        stage('targeted-report', [python, '-B', helper, 'targeted-report', '--settings', settings_path],
              180, clone, accept_nonzero=True),
        stage('whole-measured-modules-report', [python, '-B', helper, 'whole-report',
              '--settings', settings_path], 180, clone)], 10000, generated=True)
    config('finish', [support('final-summary')], 300, generated=True)
    commands = ['Prepared only. The parent owns the serialized execution lane.',
                'Run phases in order. Keep failures and all attempts. Do not reuse old native receipts or hits.',
                'Stop on a failed phase. An ordinary targeted deficit is preserved through the whole report.']
    commands += [f'{python} -B {ROOT / "run_stage.py"} {out / (phase + ".json")}' for phase in phases]
    commands += ['Inspect all five supervisor RESULT.json files and FINAL-TARGETED-RESULT.json.',
                 'The finish phase must complete with unchanged source/SDK and no owned descendants.',
                 'Actual fresh TestSuite counts and frozen manifest obligations are authoritative.',
                 'No command generates the final anatomy report.']
    (out / 'COMMANDS.txt').write_text('\n'.join(commands) + '\n')
    dump(prepared_seal, snapshot(out))
    print(json.dumps({'prepared_bundle': str(out), 'prepared_bundle_seal': str(prepared_seal),
                      'prepared_bundle_seal_sha256': sha(prepared_seal),
                      'source_seal_sha256': args.source_seal_sha256,
                      'status': 'prepared only; no repository code or compiler executed'}, indent=2))


if __name__ == '__main__':
    main()
