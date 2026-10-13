# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Native protocol and mutation qualification for constant-loop reporting.

Runtime probes remain those of the original instrumenter. Each executable
keeps the five-second limit; this harness never treats compiler failure as a
passing runtime test. The real raw capture retains compilation, with a new
180-second integration cap and a native alarm(5) before production calls.
Use after the compiler-free normal and -O controls.
"""

import argparse
from collections import defaultdict
import contextlib
import gzip
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import coverage_io
import coverage_loop_proofs as proofs


ROOT = Path(__file__).resolve().parent.parent
RUNTIME_SECONDS = 5
# This new finite harness-only bound includes compilation and capture setup.
# It does not replace the runtime alarm or change production capture budgets.
INTEGRATION_SECONDS = 180
# Full maintained generation copies and authenticates the complete include
# layout, unlike the small180-second fixture compiler/capture calls below.
# Keep its separately reviewed finite cap and the unchanged native alarm.
CURRENT_INCLUDE_SECONDS = 1200
PRODUCTION_DRIVER = '''from production import total
from std.testing import assert_equal
from std.ffi import external_call

def main() raises:
    assert_equal(external_call["alarm", UInt32](UInt32(5)), UInt32(0))
    assert_equal(total(0), 1)
    assert_equal(total(2), 2)
    print("RESULT production capture")
'''
HANG_DRIVER = PRODUCTION_DRIVER.replace(
    '    assert_equal(total(2), 2)\n    print("RESULT production capture")\n',
    '    while True:\n        _ = external_call["pause", Int32]()\n')
COMPILE_ERROR_DRIVER = 'from production import total\n\ndef main() raises:\n    var broken =\n'
SOURCE = '''from std.testing import assert_equal
from std.sys import argv

def fixed(leave: Int) raises -> Int:
    var total = 0
    for index in range(3):
        if leave == 1:
            break
        if leave == 2:
            return total
        if leave == 3:
            raise Error("expected body")
        if index == 0:
            continue
        total += index
    else:
        total += 10
    return total

def empty() -> Int:
    for index in range(0):
        return index
    else:
        return 7

def mark(value: Int, mut order: String) -> Int:
    order += String(value)
    return value

def literal() raises -> Int:
    var total = 0
    var order = String("")
    for value in [mark(1, order), mark(2, order), mark(3, order)]:
        assert_equal(order, "123")
        total += value
    return total

def dynamic(n: Int) -> Int:
    var total = 0
    for index in range(n):
        total += index
    return total

def main() raises:
    var mode = Int(String(argv()[1]))
    assert_equal(fixed(0), 13)
    assert_equal(fixed(1), 0)
    assert_equal(fixed(2), 0)
    var caught = False
    try:
        _ = fixed(3)
    except error:
        caught = String(error) == "expected body"
    assert_equal(caught, True)
    assert_equal(empty(), 7)
    assert_equal(literal(), 6)
    assert_equal(dynamic(2), 1)
    if mode == 0:
        assert_equal(dynamic(0), 0)
    print("RESULT constant loops")
'''


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(command, *, success=True, timeout=None, cwd=None, env=None):
    process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, cwd=cwd,
                               start_new_session=True, env=env)
    try:
        output, error = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    result = subprocess.CompletedProcess(command, process.returncode, output, error)
    if success and result.returncode:
        raise RuntimeError(f'{command}:\n{result.stdout}\n{result.stderr}')
    return result


def require_runtime_alarm():
    """Refuse inherited signal settings that can disable the native guard."""
    require(signal.getsignal(signal.SIGALRM) == signal.SIG_DFL,
            'Runtime alarm needs the default inherited SIGALRM disposition')
    require(signal.SIGALRM not in signal.pthread_sigmask(signal.SIG_BLOCK, []),
            'Runtime alarm must not be blocked')


def capture_with_compiler_budget(command, output, capture, *, loop_proof=None,
                                 source_root=None, success=True,
                                 seconds=INTEGRATION_SECONDS):
    """Retain the real sealed raw command and its owned-group supervision."""
    require_runtime_alarm()
    require((loop_proof is None) == (source_root is None),
            'Both proof and source root must be supplied together')
    require(type(seconds) in (int, float) and 0 < seconds <= INTEGRATION_SECONDS,
            'Invalid compiler/integration bound')
    deadline = time.monotonic() + seconds
    inherited = coverage_io.shared_deadline()
    if inherited is not None:
        deadline = min(deadline, inherited)
    environment = os.environ.copy()
    environment[coverage_io.DEADLINE_ENV] = repr(deadline)
    arguments = [sys.executable, str(ROOT/'tools/coverage_io.py'), 'capture',
                 '--out', str(output), '--err', str(capture)]
    if loop_proof is not None:
        arguments += ['--loop-proof', str(loop_proof), '--loop-proof-root', str(source_root)]
    # Do not use an outer SIGKILL timeout: capture owns a separate child group
    # and its existing absolute-deadline watchdog must reap that whole group.
    return run([*arguments, '--', *command], success=success, env=environment)


def line_of(fragment):
    matches = [number for number, line in enumerate(SOURCE.splitlines(), 1)
               if fragment in line]
    require(len(matches) == 1, 'Fixture identity is not unique: ' + fragment)
    return matches[0]


def capture_result(result, stem, envelope, command):
    """Keep raw/reduced diagnostic bytes; these are not production captures."""
    require(result.returncode == 0, 'Cannot record a failed native capture')
    raw = Path(str(stem) + '.raw.txt')
    raw.parent.mkdir(parents=True, exist_ok=True)
    output = Path(str(stem) + '.out')
    reduced = Path(str(stem) + '.txt.gz')
    raw.write_text(result.stderr)
    output.write_text(result.stdout)
    with gzip.open(reduced, 'wb') as stream:
        reducer = coverage_io.Reducer(stream.write)
        for record in result.stderr.encode().splitlines(keepends=True):
            reducer.feed(record)
    return raw, reduced


def diagnostic_manifest(original, envelope, module, lines):
    """Project only the loop outcomes for native reporter unit controls.

    Never mutate the original manifest/origin or claim an aggregate gate.
    """
    rows = []
    seen = set()
    for row in proofs.masked_manifest(original, envelope).splitlines():
        fields = row.split()
        if fields and fields[0] == b'P':
            rows.append(row)
        elif (len(fields) >= 3 and fields[0] in {b'B', b'R'}
              and fields[1].decode() == module and int(fields[2]) in lines):
            rows.append(row)
            seen.add(int(fields[2]))
    require(seen == set(lines), 'Diagnostic loop identity is missing')
    return b'\n'.join(rows) + b'\n'


def check_generated_receipt_owner(stage, mojo, compiler, flags, *, mutable_source=None):
    """Real receipt counts and optional separately provisioned mutation fixture.

    The optional source is a byte-copy admitted by the coordinated plan. This
    helper never copies or changes the sealed checkout, nor changes any timeout.
    """
    from carla_lane_oracle import full_audit_cleanup_contracts as audit
    from carla_lane_oracle import typed_boundary_contracts as typed
    root = ROOT if mutable_source is None else Path(mutable_source).resolve()
    stage = Path(stage).resolve()
    expected = proofs.read_receipt(stage/'loop-proofs.json')['receipt']
    require(proofs.maintained_inputs(root, exclude=stage) == expected['root_inputs'],
            'Owner fixture differs from the genuine producer source image')
    if mutable_source is not None:
        require(root != ROOT.resolve() and not root.is_relative_to(ROOT.resolve()),
                'Writable fixture must be independent of the sealed source')
    settings = {'mojo': [mojo], 'suites': expected['execution']['suites'],
                'capture_cache': proofs._expand_path(expected['execution']['cache'], root, stage)}
    def derive():
        return proofs.build_receipt(root, stage, compiler, flags, **settings)
    @contextlib.contextmanager
    def trace(callback=None):
        require(sys.getprofile() is None, 'Owner controls require an unprofiled test thread')
        counts, owners, binding_maps = defaultdict(int), [], []
        def profile(frame, event, value):
            if event not in ('call', 'return'):
                return
            if event == 'call' and frame.f_code is audit.verify.__code__:
                counts['full'] += 1
            if event == 'call' and frame.f_code is typed.verify_sources.__code__:
                counts['typed'] += 1
            if event == 'return' and frame.f_code is audit._receipt_operation_enter.__code__:
                owners.append(value)
            if (event == 'return' and frame.f_code is audit._InvariantInputs._receipt_bindings.__code__
                    and type(value) is dict):
                binding_maps.append(dict(value))
            if callback is not None:
                callback(frame, event, value, owners)
        sys.setprofile(profile)
        try:
            yield counts, owners, binding_maps
        finally:
            sys.setprofile(None)
    positives, observed_maps = [], []
    for attempt in range(2):
        supplements = []
        def pending_supplements(frame, event, value, owners):
            if attempt != 0 or event != 'return':
                return
            if (not supplements and frame.f_code is
                    audit._InvariantInputs._receipt_inputs_check.__code__):
                require(len(owners) == 1 and owners[0]._state == 'pending',
                        'Supplemental control missed the pending generated owner')
                owner = owners[0]
                supplements.append('scaled')
                scaled = audit.scaled_float32_proof_bindings(root, include_roots=(stage,), _operation=owner)
                require(scaled and owner._state == 'pending'
                        and owner._scaled_resolver_paths == audit.scaled_float32.NATIVE_CLOSURE,
                        'Pending scaled admission lost its independent resolver context')
                observed = {path for location, path, raw, mode in owner._receipt_observations
                            if location == owner._root}
                require(scaled.keys() <= observed,
                        'Pending scaled admission borrowed generated rather than source observations')
            elif (supplements == ['scaled'] and frame.f_code is
                    audit._InvariantInputs._receipt_bindings.__code__):
                owner = owners[0]
                require(owner._state == 'active', 'Render helper missed current admission')
                supplements.append('render')
                # Current render fixtures themselves require typed admission.
                # Exercise their owned include path after the normal root gate.
                helpers = audit.shared_helper_proof_bindings(root,
                    paths=('extensions/carla/render_sky.mojo', 'extensions/carla/render_weather.mojo'),
                    include_roots=(stage,), _operation=owner)
                require(helpers and any(path.startswith('render/') for path in helpers)
                        and {path for path in helpers if path.endswith('.mojo')} <= owner._raw.keys()
                        and owner._scaled_resolver_paths == audit.scaled_float32.NATIVE_CLOSURE,
                        'Supplemental helper admission replaced or mixed physical domains')
        with trace(pending_supplements) as (counts, owners, binding_maps):
            actual = derive()
        require(supplements == (['scaled', 'render'] if attempt == 0 else []),
                'Supplemental admission controls did not run exactly once')
        require(proofs.canonical(actual) == proofs.canonical(expected),
                'Invocation-local ownership changed a genuine receipt')
        require(dict(counts) == {'full': 1, 'typed': 1},
                'Generated rows replayed source semantics or skipped initial admission')
        require(len(owners) == 1 and owners[0]._state == 'closed'
                and not owners[0]._failed and owners[0]._owner_frame is None,
                'Successful generated owner did not close')
        require(binding_maps, 'Receipt did not exercise current binding-map reuse')
        observed_maps.extend(binding_maps)
        positives.append(owners[0])
    require(positives[0] is not positives[1], 'Independent receipts reused an admission')
    # A separately derived old path remains the exact dependency-map oracle.
    standalone = audit.proof_bindings(root, include_roots=(stage,))
    require(all(list(value.items()) == list(standalone.items()) for value in observed_maps),
            'Cached dependency keys or overwrite order differ from standalone admission')
    print('Generated owner: two fresh receipts, one full and one typed admission each', flush=True)
    # A restored live-table mutation must still poison this real active owner.
    # This uses no writable source fixture and runs in the maintained entrypoint.
    conditioned_refusals = []
    def conditioned_authority_mutation(frame, event, value, owners):
        if (conditioned_refusals or event != 'return'
                or frame.f_code is not audit._InvariantInputs._receipt_bindings.__code__):
            return
        require(len(owners) == 1 and frame.f_locals.get('self') is owners[0]
                and owners[0]._kind == 'generated_receipt' and owners[0]._state == 'active'
                and not owners[0]._capturing,
                'Conditioned mutation missed the active generated owner')
        owner = owners[0]
        conditioned_refusals.append('active')
        old_bindings = audit.conditioned_cubic.BINDING_INPUTS
        try:
            audit.conditioned_cubic.BINDING_INPUTS = {**old_bindings, 'unreviewed': '0'*64}
            try:
                audit._typed_boundary_bindings(root, _operation=owner)
            except audit._OperationCoherenceError as error:
                require(str(error) == 'conditioned cubic authority namespace changed',
                        'Conditioned mutation missed the immediate authority refusal')
                conditioned_refusals.append('refused')
            else:
                raise RuntimeError('Active generated owner accepted changed conditioned authority')
        finally:
            audit.conditioned_cubic.BINDING_INPUTS = old_bindings
        require(audit.conditioned_cubic.BINDING_INPUTS is old_bindings,
                'Conditioned mutation did not restore its original table')
        try:
            audit._operation_check(owner, root)
        except audit._OperationCoherenceError as error:
            require(str(error) == 'conditioned cubic authority namespace changed',
                    'Restored conditioned mutation lost its exact sticky refusal')
            conditioned_refusals.append('sticky')
        else:
            raise RuntimeError('Restored conditioned authority revived its failed owner')
    with trace(conditioned_authority_mutation) as (_, owners, _):
        try:
            derive()
        except audit._OperationCoherenceError as error:
            require(str(error) == 'conditioned cubic authority namespace changed',
                    'Conditioned mutation escaped with an unrelated refusal')
        else:
            raise RuntimeError('Conditioned authority mutation received a receipt')
    require(conditioned_refusals == ['active', 'refused', 'sticky']
            and len(owners) == 1 and owners[0]._failed and owners[0]._state == 'closed'
            and owners[0]._owner_frame is None and owners[0]._receipt_seed is None,
            'Conditioned mutation did not refuse, restore and close its real owner')
    print('Generated owner: transient conditioned authority refused and restored', flush=True)
    if mutable_source is None:
        return {'fresh_receipts': 2, 'full_per_receipt': 1, 'typed_per_receipt': 1,
                'conditioned_authority_refusal': True}

    # These mutations require only the separately admitted writable source and
    # generated stage. The complete positive producer relation is rechecked
    # before every case. No saved source receipt is modified or rebound.
    source_name = 'extensions/carla/curve_rounded_arc.mojo'
    include_name = 'extensions/animals/anatomy/render.mojo'
    def replace_file(path, data, location):
        require(path.is_file() and not path.is_symlink()
                and path.resolve().is_relative_to(location) and path.stat().st_nlink == 1,
                'Mutation target is not an ordinary owned fixture file')
        original = ROOT/path.relative_to(location)
        if original.exists():
            require((path.stat().st_dev, path.stat().st_ino)
                    != (original.stat().st_dev, original.stat().st_ino),
                    'Fixture aliases a sealed source inode')
        path.unlink()
        with path.open('xb') as stream:
            stream.write(data)
    faults = ('source', 'source-transient-read', 'include', 'include-entry', 'authority',
              'seed', 'include-root', 'source-root', 'public-borrow',
              'lookup-shadow', 'compiled-shadow', 'symlink', 'origin', 'checker', 'nested-owner')
    completed = []
    for fault in faults:
        require(proofs.maintained_inputs(root, exclude=stage) == expected['root_inputs'],
                'Source fixture was not restored before next control')
        proofs.check_capture_inputs({'receipt': expected}, root, stage)
        restored, fired, caught = [], [], []
        def write(path, data, location):
            raw = path.read_bytes()
            replace_file(path, data, location)
            restored.append(lambda: replace_file(path, raw, location))
        def profile(frame, event, value, owners):
            if fired or event != 'return' or frame.f_code is not audit._InvariantInputs._receipt_bindings.__code__:
                return
            fired.append(True)
            require(len(owners) == 1 and owners[0]._state == 'active', 'Mutation missed real current admission')
            owner = owners[0]
            if fault.startswith('source') and fault != 'source-root':
                target = root/source_name
                raw = target.read_bytes()
                write(target, raw+b'\n# changed after current admission\n', root)
                if fault == 'source-transient-read':
                    consumed = target.read_bytes()
                    restored.pop()()
                    try:
                        audit._observe_bytes(root, source_name, consumed, _operation=owner)
                    except ValueError as error:
                        require('consumed operation bytes changed: '+source_name in str(error),
                                'Transient read did not reach the consumed-byte comparison')
                        caught.append(True)
                    else:
                        raise RuntimeError('Restored transient source observation was accepted')
            elif fault in ('include', 'include-entry'):
                target = stage/include_name
                suffix = b'\ndef main():\n    pass\n' if fault == 'include-entry' else b'\n# unsealed bytes\n'
                write(target, target.read_bytes()+suffix, stage)
            elif fault == 'authority':
                old = typed.BINDING_INPUTS
                typed.BINDING_INPUTS = {**old, 'unreviewed': '0'*64}
                restored.append(lambda: setattr(typed, 'BINDING_INPUTS', old))
            elif fault == 'seed':
                owner._owner_frame.f_locals['_receipt_seed']['flags'] += ' changed'
            elif fault in ('include-root', 'source-root', 'public-borrow'):
                try:
                    if fault == 'include-root':
                        owner._receipt_bindings(root, (stage/'foreign',))
                    elif fault == 'source-root':
                        owner._receipt_bindings(root/'foreign', (stage,))
                    else:
                        result = proofs.reviewed_nonempty_loops(root, 'extensions/carla/map',
                            include_roots=(stage,), _operation=owner)
                        require(result == {} and owner._failed, 'Direct public borrower was admitted')
                        raise ValueError('Expected sticky public refusal')
                except ValueError:
                    caught.append(True)
                else:
                    raise RuntimeError('Foreign current owner context was accepted')
            elif fault in ('lookup-shadow', 'compiled-shadow'):
                target = stage/('tests/render.mojo' if fault == 'lookup-shadow'
                                else 'extensions/carla/map.mojopkg')
                require(not target.exists(), 'Shadow control collides with maintained input')
                target.write_bytes(b'def main():\n    pass\n')
                restored.append(target.unlink)
            elif fault == 'symlink':
                target = stage/include_name
                raw = target.read_bytes()
                target.unlink()
                target.symlink_to(stage/expected['execution']['suites'][0])
                def restore_link():
                    target.unlink()
                    with target.open('xb') as stream:
                        stream.write(raw)
                restored.append(restore_link)
            elif fault == 'origin':
                target = stage/(source_name+'.cov-origin')
                write(target, target.read_bytes()+b'\nchanged', stage)
            elif fault == 'checker':
                name = 'tools/carla_lane_oracle/full_audit_cleanup_contracts.py'
                require(owner._checker_receipt and name in owner._executing and name not in owner._raw,
                        'Current owner did not retain its separate supplied-checker domain')
                target = root/name
                write(target, target.read_bytes()+b'\n# changed supplied checker after admission\n', root)
            elif fault == 'nested-owner':
                from unittest.mock import patch
                original_read = Path.read_text
                inner_seen = []
                def nested_read(path, *args, **kwargs):
                    if not inner_seen and path == root/source_name:
                        current = sys._getframe(1)
                        while current is not None and current.f_code is not proofs.build_receipt.__code__:
                            current = current.f_back
                        require(current is not None, 'Nested receipt frame is absent')
                        inner = current.f_locals.get('_operation')
                        require(inner is not owner and inner._kind == 'generated_receipt',
                                'Nested receipt reused the outer owner')
                        inner_seen.append(inner)
                        try:
                            audit._operation_check(owner, root)
                        except ValueError as error:
                            require('nearer independent operation blocks borrowing' in str(error),
                                    'Nested-owner control missed its frame boundary')
                            caught.append(True)
                        else:
                            raise RuntimeError('Nested receipt borrowed the outer admission')
                    return original_read(path, *args, **kwargs)
                with patch.object(Path, 'read_text', nested_read):
                    inner_result = derive()
                require(len(inner_seen) == 1 and inner_seen[0]._state == 'closed'
                        and not inner_seen[0]._failed
                        and proofs.canonical(inner_result) == proofs.canonical(expected),
                        'Fresh nested receipt failed independently of refused outer reuse')
            if caught:
                try:
                    audit._operation_check(owner, root)
                except ValueError:
                    pass
                else:
                    raise RuntimeError('Caught refusal did not poison the current owner')
        try:
            with trace(profile) as (_, owners, _):
                try:
                    derive()
                except ValueError:
                    pass
                else:
                    raise RuntimeError('Current generated mutation received a receipt: '+fault)
            require(fired == [True] and len(owners) == 1 and owners[0]._failed
                    and owners[0]._state == 'closed' and owners[0]._owner_frame is None,
                    'Current mutation did not fail and close its actual owner: '+fault)
        finally:
            for restore in reversed(restored):
                restore()
        completed.append(fault)
    require(proofs.maintained_inputs(root, exclude=stage) == expected['root_inputs'],
            'Current source mutation controls did not restore the fixture')
    proofs.check_capture_inputs({'receipt': expected}, root, stage)
    print('Generated owner current refusals:', ', '.join(completed), flush=True)
    return {'fresh_receipts': 2, 'full_per_receipt': 1, 'typed_per_receipt': 1,
            'conditioned_authority_refusal': True, 'current_mutation_controls': completed}



def check_current_generated_include_root(stage, mojo, compiler, flags):
    """Exercise real maintained generation with the complete passthrough layout."""
    modules = ('extensions/carla/curve_rounded_arc',
               'extensions/carla/curve_rounded_line',
               'extensions/carla/curve_sample_dispatch',
               'extensions/carla/map')
    suite = 'tests/test_carla_lane_geometry_guard_controls.mojo'
    require(not stage.exists(), 'Generated include regression needs a fresh stage')
    run(['make', '--no-print-directory', 'coverage-instrument',
         'COV_DIR='+str(stage), 'MOJO='+mojo, 'TOOLCHAIN='+compiler,
         'MOJOFLAGS='+flags, 'COVERED='+' '.join(name+'.mojo' for name in modules),
         'COVERAGE_TESTS='+suite], cwd=ROOT, timeout=CURRENT_INCLUDE_SECONDS)
    for name in ('extensions/animals/anatomy/render.mojo',
                 'extensions/building/views/render.mojo'):
        require((stage/name).read_bytes() == (ROOT/name).read_bytes(),
                'Maintained nested-render passthrough is missing')
    envelope = proofs.read_receipt(stage/'loop-proofs.json')
    # Close the complete four-module census. Map exercises historical station
    # borrowing during normal profiled derivation, not a profile callback.
    rows = {
        ('extensions/carla/curve_rounded_arc',235): (
            'rounded-arc-validated-lane-list','range(len(lanes))','reviewed-nonempty-range',None,
            'f17bf9a6a744971ea6e792a24b27d6157691e70d50c438880abcf88db2a9123d'),
        ('extensions/carla/curve_rounded_line',93): (
            'rounded-line-validated-lane-list','range(len(lanes))','reviewed-nonempty-range',None,
            '22b70ec9febc6f3d21a8a4d9f1a74650d676e34782fab2812004a1a3aadeb698'),
        ('extensions/carla/curve_sample_dispatch',126): (
            'sample-dispatch-count-1-or-2','range(count)','reviewed-nonempty-range',2,
            '04ff45c12cefcb4dbe3a7b136e77b6baaf02cff52325f6599d99250f820fdebb'),
        ('extensions/carla/map',5020): (
            'construction-geometry-boundary-list','boundaries','reviewed-nonempty-iterator',None,
            'b3862a55a54927b2a1e50186af82f64bdf145adbef5cef9f31ab19d9585749df'),
    }
    ordinary = {
        ('extensions/carla/map',line): {
            'module':'extensions/carla/map', 'line':line,
            'kind':'literal-range', 'cardinality':count, 'required':'T', 'impossible':'F',
            'expression':expression,
            'source_sha256':'b3862a55a54927b2a1e50186af82f64bdf145adbef5cef9f31ab19d9585749df'}
        for line,count,expression in ((2170,3,'range (3 )'),(2201,8,'range (8 )'))}
    expected = set(rows) | set(ordinary)
    observed = {(row['module'],row['line']):row for row in envelope['receipt']['proofs']}
    require(len(observed) == len(envelope['receipt']['proofs']) == 6
            and set(observed) == expected, 'Closed six-row proof inventory differs')
    require({key for key,row in observed.items() if 'proof_id' in row} == set(rows),
            'Reviewed and ordinary proof inventories differ')
    for key,(proof_id,expression,kind,maximum,digest) in rows.items():
        raw = (ROOT/(key[0]+'.mojo')).read_bytes()
        require(proofs.sha256(raw) == digest, 'Current integration source endpoint changed')
        row = observed[key]
        require((row['proof_id'],row['expression'],row['kind'],row['cardinality'],
                 row['maximum_cardinality'],row['required'],row['impossible'],row['source_sha256'])
                == (proof_id,expression,kind,1,maximum,'T','F',digest),
                'Current proof contract or required True outcome differs')
        constants = {line:{field:value for field,value in item.items()
                           if field not in ('module','source_sha256')}
                     for (module,line),item in ordinary.items() if module == key[0]}
        require(proofs.constant_loops(raw.decode('utf-8')) == constants,
                'Ordinary proof census differs from the reviewed exact set')
    require(observed['extensions/carla/map',5020]['minimum_cardinality'] == 1,
            'Constructor boundary minimum changed')
    require(all(observed[key] == row for key,row in ordinary.items()),
            'Ordinary literal-range proof contract differs')
    original = (stage/'manifest.txt').read_bytes()
    require({fields[1] for fields in (line.split() for line in original.decode().splitlines())
             if fields and fields[0] in ('L','B','C','M')} == set(modules),
            'Original selected-module denominator differs')
    # Preserve the source's existing branch exclusions explicitly. None is
    # evidence for a new proof or permission to discard another obligation.
    map_exclusions = (1223,1766,2205,3003,3010,3032,3104,3109,3118,3127,4903,5328,5348)
    require(all(f'B extensions/carla/map {line}'.encode() not in original.splitlines()
                for line in map_exclusions), 'Existing Map branch exclusion changed')
    masked = proofs.masked_manifest(original,envelope)
    # Independently reconstruct every line, including unrelated obligations.
    # Only the single receipt header and authenticated B-to-R substitutions differ.
    expected_rows = ['P '+proofs.SCHEMA+' '+envelope['sha256']]
    used = set()
    for original_row in original.decode('utf-8').splitlines():
        fields = original_row.split()
        key = (fields[1],int(fields[2])) if len(fields) >= 3 and fields[0] == 'B' else None
        if key in observed:
            row = observed[key]
            expected_rows.append(' '.join(('R',key[0],str(key[1]),row['required'],
                                            row['kind'],str(row['cardinality']))))
            used.add(key)
        else:
            expected_rows.append(original_row)
    require(used == set(observed), 'Proof does not identify an original branch')
    require(masked == ('\n'.join(expected_rows)+'\n').encode(),
            'An unrelated manifest row or its order changed')
    for module,line in expected:
        require((module,line) in observed, 'Current generated-layout theorem was refused')
        require((observed[module,line]['required'],observed[module,line]['impossible']) == ('T','F'),
                'Current theorem weakened its required true outcome')
        require(f'B {module} {line}'.encode() in original.splitlines(), 'Missing original branch')
        require(f'L {module} {line}'.encode() in masked.splitlines(), 'Original line was removed')
    # Exercise unsealed same-path bytes, a novel entry context, and an unknown
    # actual lookup-root provider through the real generation owner.
    changed = stage/'extensions/animals/anatomy/render.mojo'
    raw = changed.read_bytes()
    def replace_generated_passthrough(data):
        require(not changed.is_symlink() and changed.is_file()
                and changed.resolve().is_relative_to(stage.resolve()),
                'Mutation target is not a regular contained generated file')
        source = ROOT/'extensions/animals/anatomy/render.mojo'
        generated_stat, source_stat = changed.stat(), source.stat()
        require((generated_stat.st_dev,generated_stat.st_ino)
                != (source_stat.st_dev,source_stat.st_ino),
                'Generated mutation target aliases the sealed source')
        changed.unlink()
        with changed.open('xb') as stream:
            stream.write(data)
    for suffix in (b'\n# unsealed same-path change\n', b'\ndef main():\n    pass\n'):
        replace_generated_passthrough(raw+suffix)
        try:
            try:
                proofs.build_receipt(ROOT,stage,compiler,flags,mojo=[mojo],suites=[suite])
            except ValueError as error:
                require('Staged input differs' in str(error), 'Unexpected same-path rejection')
            else:
                raise RuntimeError('Unsealed staged provider received proof admission')
        finally:
            replace_generated_passthrough(raw)
    shadow = stage/'tests/render.mojo'
    require(not shadow.exists(), 'Lookup-shadow fixture collides with maintained source')
    shadow.write_text('def main():\n    pass\n')
    try:
        try:
            proofs.build_receipt(ROOT,stage,compiler,flags,mojo=[mojo],suites=[suite])
        except ValueError as error:
            require('Unmaintained executable input' in str(error), 'Unexpected new-provider rejection')
        else:
            raise RuntimeError('Unknown lookup-root provider received proof admission')
    finally:
        shadow.unlink()
    require((stage/'manifest.txt').read_bytes() == original, 'Original denominator changed')
    owner_result = check_generated_receipt_owner(stage, mojo, compiler, flags)
    require(owner_result == {'fresh_receipts': 2, 'full_per_receipt': 1,
                             'typed_per_receipt': 1, 'conditioned_authority_refusal': True},
            'Maintained generated owner controls did not complete')
    # Reuse this genuine stage for root-only borrowing and final-stage guards.
    # Test-module import support is local to this explicit maintained entrypoint.
    saved_path = list(sys.path)
    try:
        sys.path.insert(0, str(ROOT/'tools/carla_lane_oracle'))
        from carla_lane_oracle import test_invariant_operation_inputs as owner_controls
    finally:
        sys.path[:] = saved_path
    root_only = owner_controls.check_generated_root_only_borrowing(
        ROOT, stage, mojo, compiler, flags)
    require(root_only == {'completed': [
        'root-only-seed-and-shared-positive', 'root-only-wrong-nonempty-root',
        'root-only-stage-tamper-at-finish'], 'fresh_receipts': 3},
        'Maintained root-only receipt controls did not complete')
    return len(expected)



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mojo', default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    mojo = str(Path(args.mojo).resolve())
    compiler = run([mojo, '--version']).stdout.strip()
    flags = '-Werror -I .'

    def generate(root, stage, names, *, success=True, remove_after_begin=None):
        # The checkpoint precedes the command that loads the producer source.
        # A previously compiled unbound generator cannot attest current tools.
        proofs.begin_generation(root, stage, compiler, flags, mojo=[mojo], sources=names)
        if remove_after_begin is not None:
            (root / remove_after_begin).unlink()
        return run([mojo, 'run', '-Werror', '-I', '.', 'coverage/build_cli.mojo',
                    str(stage), *names], cwd=root, success=success)

    if args.output is None:
        workspace = tempfile.TemporaryDirectory(prefix='threemojo-loop-proofs-')
    else:
        retained = args.output.resolve() / 'attempt-work'
        retained.mkdir(parents=True, exist_ok=False)
        workspace = contextlib.nullcontext(str(retained))
    with workspace as directory:
        work = Path(directory)
        current_rows = check_current_generated_include_root(
            work/'current-generated', mojo, compiler, flags)
        print('Current generated include-root theorems:', current_rows, flush=True)
        native, rewritten = work / 'native', work / 'rewritten'
        native.mkdir()
        rewritten.mkdir()
        for name in proofs.TOOL_INPUTS:
            target = native / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        shutil.copytree(ROOT / 'coverage', rewritten / 'coverage',
                        ignore=shutil.ignore_patterns('build'))
        # Copy any remaining coverage package source too, matching the normal
        # uninstrumented tool copy-through contract.
        shutil.copytree(ROOT / 'coverage', native / 'coverage', dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('build'))
        shutil.copytree(ROOT / 'tools', native / 'tools', dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns('__pycache__'))
        (native / 'fixture.mojo').write_text(SOURCE)
        reporter = work / 'report'
        run([mojo, 'build', '-Werror', '-I', str(ROOT), str(ROOT / 'coverage/report_cli.mojo'), '-o', str(reporter)])
        generate(native, rewritten, ['fixture.mojo'])
        full_manifest = (rewritten / 'manifest.txt').read_bytes()
        identities = {name: line_of(fragment) for name, fragment in {
            'fixed': 'for index in range(3)', 'empty': 'for index in range(0)',
            'literal': 'for value in [mark(1, order)', 'dynamic': 'for index in range(n)',
        }.items()}
        # A branch-only fixture manifest isolates outcome completeness from
        # intentionally unreachable literal-empty body lines. The untouched
        # full native manifest is retained as separate evidence.
        selected = ''.join(f'B fixture {line}\n' for line in identities.values()).encode()
        for record in selected.splitlines():
            require(record in full_manifest.splitlines(), 'Missing original fixture decision')
        envelope = proofs.seal(native, rewritten, compiler, flags, mojo=[mojo])
        require(len(envelope['receipt']['proofs']) == 3, 'Expected exactly three constant loops')
        totals = envelope['receipt']['denominator']
        require(totals['potential_total'] - totals['required_total'] == 3, 'Reachable outcome removed')
        evidence = work / 'evidence'
        evidence.mkdir()
        derived = evidence / 'derived-manifest.txt'
        derived.write_bytes(diagnostic_manifest(full_manifest, envelope, 'fixture', identities.values()))
        binaries = []
        for folder in [native, rewritten]:
            binary = folder / 'fixture'
            run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / 'fixture.mojo'), '-o', str(binary)])
            binaries.append(binary)
        results = {}
        for mode in [0, 1]:
            plain = run([str(binaries[0]), str(mode)], timeout=5)
            instrumented = run([str(binaries[1]), str(mode)], timeout=5)
            require(plain.stdout == instrumented.stdout == 'RESULT constant loops\n', 'Native output changed')
            require(not plain.stderr, 'Native program unexpectedly emitted probe records')
            by_line = defaultdict(list)
            for record in instrumented.stderr.splitlines():
                fields = record.split(':')
                if len(fields) == 4 and fields[:2] == ['COVLINE', 'fixture']:
                    by_line[int(fields[2])].append(fields[3])
            expected = {'fixed': 'TTTTTTT', 'empty': 'F', 'literal': 'TTTT',
                        'dynamic': 'TTTF' if mode == 0 else 'TTT'}
            for name, outcomes in expected.items():
                require(by_line[identities[name]] == list(outcomes), f'Loop protocol changed: {name}: {by_line[identities[name]]}')
            raw, reduced = capture_result(instrumented, evidence / f'case-{mode}' / 'result', envelope, [str(binaries[1]), str(mode)])
            reported = run([str(reporter), str(derived), str(raw)], success=False, timeout=5)
            require((reported.returncode == 0) == (mode == 0), 'Missing dynamic-empty obligation was lost')
            if mode == 0:
                require('TOTAL' in reported.stdout and '5/5' in reported.stdout, 'Positive report is incomplete')
                require('DENOMINATOR potential 8, required 5, proven impossible 3' in reported.stdout, 'Denominator lineage missing')
            else:
                require('never evaluated False' in reported.stdout, 'Dynamic-empty failure not explained')
            (evidence / f'report-{mode}.out').write_text(reported.stdout + reported.stderr)
            replayed = run([
                sys.executable, str(ROOT / 'tools/coverage_io.py'), 'report',
                '--capture-dir', str(reduced.parent), '--', str(reporter), str(derived),
            ], success=False, timeout=5)
            require((replayed.returncode == 0) == (mode == 0), 'Diagnostic raw/reduced reporting changed the result: ' + replayed.stdout + replayed.stderr)
            results[f'mode-{mode}'] = {'status': reported.returncode, 'expected': 'complete' if mode == 0 else 'dynamic-empty-missing'}
        # Mutation control: corrupt the actual native emitted entry probe of
        # a proved nonempty loop. It must be rejected, never discarded as
        # an infeasible hit. Counter/closer emissions remain unchanged.
        source_path = rewritten / 'fixture.mojo'
        original_instrumented = source_path.read_text()
        needle = f'_cov_branch("fixture:{identities["fixed"]}", True)'
        require(needle in original_instrumented, 'Mutation target absent')
        source_path.write_text(original_instrumented.replace(needle, needle.replace('True', 'False')))
        try:
            proofs.seal(native, rewritten, compiler, flags, mojo=[mojo])
        except ValueError as error:
            require('generation origin' in str(error), 'Unexpected mutation rejection')
        else:
            raise RuntimeError('Modified stage was accepted against the original source')
        mutant = rewritten / 'mutant'
        run([mojo, 'build', '-Werror', '-I', str(rewritten), str(source_path), '-o', str(mutant)])
        mutant_result = run([str(mutant), '0'], timeout=5)
        raw, _ = capture_result(mutant_result, evidence / 'mutation-capture' / 'result', envelope, [str(mutant), '0'])
        failed = run([str(reporter), str(derived), str(raw)], success=False, timeout=5)
        require(failed.returncode != 0 and 'Constant-loop proof contradicted' in failed.stderr,
                'Contradictory native probe was accepted')
        (evidence / 'mutant-report.out').write_text(failed.stdout + failed.stderr)
        mutated_source = source_path.read_text()
        source_path.write_text(original_instrumented)
        proofs.verify(rewritten / 'loop-proofs.json', native, rewritten, compiler, flags, mojo=[mojo])
        results['entry-probe-mutation'] = 'rejected contradictory actual native probe'
        # An explicit imported binding supplies an empty iterable even though
        # the call is spelled range(3). It must keep the original two-outcome
        # obligation, with a real F observation and no fabricated T.
        factory = 'def custom_range(n: Int) -> List[Int]:\n    return List[Int]()\n'
        shadow_source = '''from std.testing import assert_equal
from shadow_factory import custom_range as range

def main() raises:
    var visits = 0
    for item in range(3):
        visits += item + 1
    assert_equal(visits, 0)
    print("RESULT shadowed range")
'''
        (native / 'shadow.mojo').write_text(shadow_source)
        shadow_build = work / 'shadow-stage'
        shadow_build.mkdir()
        shutil.copytree(ROOT / 'coverage', shadow_build / 'coverage', ignore=shutil.ignore_patterns('build'))
        for folder in [native, shadow_build]:
            (folder / 'shadow_factory.mojo').write_text(factory)
        generate(native, shadow_build, ['shadow.mojo'])
        shadow_line = next(number for number, row in enumerate(shadow_source.splitlines(), 1)
                           if 'for item in range(3)' in row)
        shadow_selected = f'B shadow {shadow_line}\n'.encode()
        shadow_original = (shadow_build / 'manifest.txt').read_bytes()
        require(shadow_selected.strip() in shadow_original.splitlines(),
                'Shadow fixture original loop missing')
        shadow_proof = proofs.seal(native, shadow_build, compiler, flags, mojo=[mojo])
        require(not shadow_proof['receipt']['proofs'], 'Shadowed range incorrectly proved builtin')
        shadow_manifest = evidence / 'shadow-manifest.txt'
        shadow_manifest.write_bytes(diagnostic_manifest(shadow_original, shadow_proof, 'shadow', [shadow_line]))
        shadow_results = []
        for folder in [native, shadow_build]:
            binary = folder / 'shadow'
            run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / 'shadow.mojo'), '-o', str(binary)])
            shadow_results.append(run([str(binary)], timeout=5))
        require(shadow_results[0].stdout == shadow_results[1].stdout == 'RESULT shadowed range\n',
                'Shadowed range native semantics changed')
        require(not shadow_results[0].stderr, 'Unexpected native shadow probe')
        shadow_records = [row for row in shadow_results[1].stderr.splitlines()
                          if row.startswith(f'COVLINE:shadow:{shadow_line}:')]
        require(shadow_records == [f'COVLINE:shadow:{shadow_line}:F'], 'Shadowed range must emit only F')
        shadow_raw, _ = capture_result(shadow_results[1], evidence / 'shadow-capture' / 'result',
                                       shadow_proof, [str(shadow_build / 'shadow')])
        shadow_report = run([str(reporter), str(shadow_manifest), str(shadow_raw)], success=False, timeout=5)
        require(shadow_report.returncode != 0 and 'branches 1/2' in shadow_report.stdout,
                'Shadowed loop lost a reachable/unknown obligation')
        (evidence / 'shadow-report.out').write_text(shadow_report.stdout + shadow_report.stderr)
        results['shadowed-range'] = 'native empty custom iterable; both obligations retained; T remains missing'
        (native / 'shadow.mojo').write_text(shadow_source.replace(
            'from shadow_factory import custom_range as range', '# same-line builtin alias drift'))
        try:
            proofs.seal(native, shadow_build, compiler, flags, mojo=[mojo])
        except ValueError as error:
            require('generation origin' in str(error), 'Unexpected alias-drift rejection')
        else:
            raise RuntimeError('Same-line source alias drift was accepted')
        (native / 'shadow.mojo').write_text(shadow_source)
        results['native-alias-drift'] = 'rejected original/staged mismatch'
        # Actual CR/LF/UTF-8 generation records must retain the exact native
        # input and rewritten bytes; the original manifest remains unchanged.
        physical = 'from std.testing import assert_equal\n\ndef main() raises:\n    var text = String("é\tλ")\n    var total = 0\n    for index in range(2):\n        total += index\n    assert_equal(total, 1)\n    assert_equal(text, "é\tλ")\n    print("RESULT physical")\n'
        for number, ending in enumerate(['\n', '\r\n', '\r']):
            name = f'physical_{number}.mojo'
            original = physical.replace('\n', ending).encode()
            (native / name).write_bytes(original)
            stage = work / f'physical-{number}'
            stage.mkdir()
            shutil.copytree(ROOT / 'coverage', stage / 'coverage', ignore=shutil.ignore_patterns('build'))
            generate(native, stage, [name])
            bound = proofs.seal(native, stage, compiler, flags, mojo=[mojo])
            require(bound['receipt']['generation']['modules'][name]['source'] == proofs.sha256(original), 'Physical source bytes changed')
            observed = []
            for folder in [native, stage]:
                binary = folder / f'physical-{number}'
                run([mojo, 'build', '-Werror', '-I', str(folder), str(folder / name), '-o', str(binary)])
                observed.append(run([str(binary)], timeout=5))
            require(observed[0].stdout == observed[1].stdout == 'RESULT physical\n', 'Physical-byte native parity failed')
            target = evidence / f'physical-{number}'
            target.mkdir()
            for record in [name, name + '.cov-origin', 'origins.ready', 'generation-inputs.json', 'manifest.txt', 'loop-proofs.json']:
                shutil.copyfile(stage / record, target / record)
        results['generation-byte-correspondence'] = 'native LF, CRLF, CR and UTF-8 pairs verified'
        # One complete original manifest goes through the maintained capture
        # wrapper and the official proof-aware reporting boundary end to end.
        production = 'def total(n: Int) -> Int:\n    var value = 0\n    for index in range(2):\n        value += index\n    for index in range(n):\n        value += index\n    return value\n'
        (native / 'production.mojo').write_text(production)
        (native / 'tests').mkdir(exist_ok=True)
        suite_name = 'tests/test_production.mojo'
        hang_name = 'tests/test_production_hang.mojo'
        failure_name = 'tests/test_production_compile_error.mojo'
        drivers = {suite_name: PRODUCTION_DRIVER, hang_name: HANG_DRIVER,
                   failure_name: COMPILE_ERROR_DRIVER}
        production_stage = work / 'production-stage'
        production_stage.mkdir()
        shutil.copytree(ROOT / 'coverage', production_stage / 'coverage', ignore=shutil.ignore_patterns('build'))
        (production_stage / 'tests').mkdir()
        for name, driver in drivers.items():
            (native/name).write_text(driver)
            (production_stage/name).write_text(driver)
        generate(native, production_stage, ['production.mojo'])
        production_proof = proofs.seal(native, production_stage, compiler, flags,
                                       mojo=[mojo], suites=list(drivers))
        # Build first, then enforce the unchanged executable runtime limit.
        # The real raw-profile invocation below still includes JIT startup.
        require_runtime_alarm()
        executions = []
        for number, folder in enumerate((native, production_stage)):
            binary = work/f'production-runtime-{number}'
            run([mojo, 'build', '-Werror', '-I', str(folder),
                 str(folder/suite_name), '-o', str(binary)])
            executions.append(run([str(binary)], timeout=RUNTIME_SECONDS))
        require(executions[0].stdout == executions[1].stdout == 'RESULT production capture\n',
                'Prebuilt production runtime output changed')
        require(not executions[0].stderr, 'Uninstrumented production emitted probes')
        expected_records = bytearray()
        reducer = coverage_io.Reducer(expected_records.extend)
        for line in executions[1].stderr.encode().splitlines(keepends=True):
            reducer.feed(line)
        hits = production_stage / 'hits'
        hits.mkdir()
        command = [proofs._expand_path(word, native, production_stage) for word in
                   proofs.expected_capture_command(production_proof['receipt']['execution'], suite_name, 'raw')]
        capture = hits / 'test_production.txt.gz'
        output = hits / 'test_production.out'
        captured = capture_with_compiler_budget(command, output, capture,
                        loop_proof=production_stage/'loop-proofs.json', source_root=native)
        require(output.read_text() == 'RESULT production capture\n', 'Production capture output changed')
        require(gzip.decompress(capture.read_bytes()) == bytes(expected_records),
                'Real raw-profile and prebuilt runtime probe evidence differ')
        reported = run([sys.executable, str(ROOT / 'tools/coverage_io.py'), 'report',
                        '--capture-dir', str(hits), '--loop-proof-root', str(native),
                        '--loop-proof-build', str(production_stage), '--compiler=' + compiler,
                        '--flags=' + flags, '--mojo', mojo, '--suites', *drivers, '--',
                        str(reporter), str(production_stage / 'manifest.txt')], timeout=5)
        require('100%' in reported.stdout and 'proven impossible 1' in reported.stdout,
                'Full original manifest failed the proof-aware production report')
        target = evidence / 'production'
        shutil.copytree(production_stage, target)
        for number, execution in enumerate(executions):
            (target/f'prebuilt-{number}.out').write_text(execution.stdout)
            (target/f'prebuilt-{number}.raw.txt').write_text(execution.stderr)
        (target / 'capture-process.out').write_text(captured.stdout + captured.stderr)
        (target / 'report-process.out').write_text(reported.stdout + reported.stderr)
        results['production-wrapper'] = ('actual sealed raw capture and full original-manifest report; '
                                         'prebuilt executables retain 5s; raw main retains alarm(5); '
                                         'exact stdout and reduced evidence parity')
        # These actual raw captures must fail and never leave success receipts.
        # The alarm stays armed through process exit; pause cannot outlive it.
        for name, expected in ((hang_name, 128+signal.SIGALRM), (failure_name, None)):
            stem = Path(name).stem
            bad_capture, bad_output = hits/(stem+'.txt.gz'), hits/(stem+'.out')
            receipt_path = proofs.capture_receipt_path(bad_capture)
            receipt_path.write_text('stale success must be removed')
            negative_command = [proofs._expand_path(word, native, production_stage) for word in
                proofs.expected_capture_command(production_proof['receipt']['execution'], name, 'raw')]
            failed = capture_with_compiler_budget(negative_command,bad_output,bad_capture,
                loop_proof=production_stage/'loop-proofs.json',source_root=native,success=False)
            require(failed.returncode != 0 and failed.returncode != 124,
                    'Runtime alarm or compiler refusal was not observed')
            if expected is not None:
                require(failed.returncode == expected, 'Raw runtime did not terminate with SIGALRM')
                require(b'COVLINE:production:' in gzip.decompress(bad_capture.read_bytes()),
                        'Forced hang never entered the actual production workload')
            else:
                errors = gzip.decompress(bad_capture.read_bytes())
                require(b'error:' in errors and Path(name).name.encode() in errors,
                        'Failure was not the actual fixture compiler refusal')
            require(not receipt_path.exists(), 'Failed raw capture left a success receipt')
            results[stem] = {'status':failed.returncode,'success_receipt':False}
            negative = evidence/'production-negatives'/stem
            negative.mkdir(parents=True)
            shutil.copyfile(bad_capture, negative/bad_capture.name)
            shutil.copyfile(bad_output, negative/bad_output.name)
            (negative/'capture-process.out').write_text(failed.stdout+failed.stderr)
            (negative/'command.json').write_text(json.dumps(negative_command)+'\n')
        expired = evidence/'production-deadline'
        expired.mkdir()
        expired_capture = expired/'test_production.txt.gz'
        expired_output = expired/'test_production.out'
        expired_receipt = proofs.capture_receipt_path(expired_capture)
        expired_receipt.write_text('stale success must be removed')
        # An already elapsed inherited deadline cannot start a new suite or
        # retain an earlier success. Live descendant cleanup has a separate
        # compiler-free watchdog control.
        with contextlib.ExitStack() as scope:
            old_deadline = os.environ.get(coverage_io.DEADLINE_ENV)
            def restore_deadline():
                if old_deadline is None:
                    os.environ.pop(coverage_io.DEADLINE_ENV, None)
                else:
                    os.environ[coverage_io.DEADLINE_ENV] = old_deadline
            scope.callback(restore_deadline)
            os.environ[coverage_io.DEADLINE_ENV] = repr(time.monotonic()-1)
            exhausted = capture_with_compiler_budget(command, expired_output, expired_capture,
                loop_proof=production_stage/'loop-proofs.json', source_root=native, success=False)
        require(exhausted.returncode == 124, 'Expired integration deadline was extended')
        require(not expired_receipt.exists(), 'Expired capture retained a success receipt')
        (expired/'capture-process.out').write_text(exhausted.stdout+exhausted.stderr)
        results['production-deadline'] = {'status':124,'success_receipt':False}
        (native / 'missing.mojo').write_text('def main():\n    pass\n')
        failed_generation = generate(native, shadow_build, ['shadow.mojo', 'missing.mojo'],
                                     success=False, remove_after_begin='missing.mojo')
        require(failed_generation.returncode != 0, 'Missing source regeneration unexpectedly succeeded')
        require((shadow_build / 'origins.ready').read_bytes() == b'', 'Failed generation left a usable prior index')
        results['interrupted-generation'] = 'old origin index invalidated before failing writes'
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            (args.output / 'full-original-manifest.txt').write_bytes(full_manifest)
            (args.output / 'original-loop-proofs.json').write_bytes(proofs.canonical(envelope) + b'\n')
            (args.output / 'shadow-loop-proofs.json').write_bytes(proofs.canonical(shadow_proof) + b'\n')
            (args.output / 'native-source.mojo').write_text(SOURCE)
            (args.output / 'original-instrumented.mojo').write_text(original_instrumented)
            (args.output / 'mutant-instrumented.mojo').write_text(mutated_source)
            for pattern in ['*.raw.txt', '*.out', '*.txt.gz', '*.proof.json', '*manifest.txt']:
                for path in evidence.rglob(pattern):
                    target = args.output / path.relative_to(evidence)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, target)
            (args.output / 'qualification.json').write_text(json.dumps(results, indent=2) + '\n')
            shutil.copytree(evidence, args.output / 'diagnostics', dirs_exist_ok=True)
        print('PASS: unchanged native loop streams; constant reachable outcomes; dynamic-empty negative; raw/reduced report parity; actual native entry-probe mutation rejected; shadowed range stays unknown')


if __name__ == '__main__':
    main()
