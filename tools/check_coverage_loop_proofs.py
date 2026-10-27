# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Native protocol and mutation qualification for constant-loop reporting.

Runtime probes remain those of the original instrumenter. Each executable
keeps the five-second limit; this harness never treats compiler failure as a
passing runtime test. The real raw capture retains compilation, with a new
180-second integration cap and a native alarm(5) before production calls.
Capture and report use `tools/coverage_io.mojo`. The fixture receipts are
sealed and checked by `tools/coverage_loop_seal.mojo`.
Use after the compiler-free normal and -O controls.
The generated include-root inventory runs in
`tools/check_coverage_include_root.mojo`.
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
# Coverage tools import these shared leaves. Keep the small native fixture
# isolated: do not copy all core sources or add the repository include root.
_LOOP_LABELS = None


def _loop_labels():
    """Return the coverage-loop qualification labels."""
    global _LOOP_LABELS
    if _LOOP_LABELS is not None:
        return _LOOP_LABELS
    import os
    import subprocess
    root = Path(__file__).resolve().parents[1]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_coverage_loop_labels'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _LOOP_LABELS = json.loads(result.stdout)
    return _LOOP_LABELS


def _commands():
    """Return the coverage command and file names."""
    return _loop_labels()['commands']


_LOOP_DRIVERS = None


def _loop_drivers():
    """Return the native loop source and the production drivers."""
    global _LOOP_DRIVERS
    if _LOOP_DRIVERS is not None:
        return _LOOP_DRIVERS
    import os
    import subprocess
    root = Path(__file__).resolve().parents[1]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_coverage_loop_drivers'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _LOOP_DRIVERS = json.loads(result.stdout)
    return _LOOP_DRIVERS


def __getattr__(name):
    if name == 'NATIVE_TOOL_DEPENDENCIES':
        return tuple(_loop_labels()['dependencies'])
    if name == 'PRODUCTION_DRIVER':
        return _loop_drivers()['production']
    if name == 'HANG_DRIVER':
        return _loop_drivers()['hang']
    if name == 'COMPILE_ERROR_DRIVER':
        return _loop_drivers()['compile_error']
    if name == 'SOURCE':
        return _loop_drivers()['source']
    if name == 'RUNTIME_SECONDS':
        return _loop_labels()['runtime_seconds']
    if name == 'INTEGRATION_SECONDS':
        return _loop_labels()['integration_seconds']
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def copy_native_tool_dependencies(root, destination):
    """Copy the explicit coverage-tool leaf closure into the native fixture."""
    labels = _loop_labels()
    for name in labels['dependencies']:
        source = Path(root) / name
        target = Path(destination) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        require(target.read_bytes() == source.read_bytes(),
                labels['copy_message'] + name)


# This new finite harness-only bound includes compilation and capture setup.
# It does not replace the runtime alarm or change production capture budgets.


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
    admission = _loop_labels()['admission']
    require(signal.getsignal(signal.SIGALRM) == signal.SIG_DFL,
            admission['alarm_default'])
    require(signal.SIGALRM not in signal.pthread_sigmask(signal.SIG_BLOCK, []),
            admission['alarm_blocked'])


def coverage_io_argv(mojo, mode):
    """Return the production Mojo coverage tool command."""
    commands = _commands()
    return [commands['shell'], str(ROOT / commands['tool']), mojo,
            commands['coverage_io'], mode]


def _mojo_seal_command(root, stage, compiler, flags, mojo, suites=None, *, verify=False):
    commands = _commands()
    command = [commands['shell'], str(ROOT / commands['tool']), mojo,
               commands['seal']]
    if verify:
        command.append(commands['verify'])
    options = commands['options']
    command += [options['root'], str(root), options['build'], str(stage),
                options['compiler'], compiler, options['flags'], flags,
                options['mojo'], mojo]
    if suites is not None:
        command += [options['suites'], *suites]
    return command


def mojo_begin(root, stage, compiler, flags, mojo, names):
    """Write the generation checkpoint with the Mojo begin tool."""
    commands = _commands()
    options = commands['options']
    run([commands['shell'], str(ROOT / commands['tool']), mojo, commands['begin'],
         options['root'], str(root), options['build'], str(stage),
         options['compiler'], compiler, options['flags'], flags,
         options['mojo'], mojo, options['sources'], *names])


def mojo_seal(root, stage, compiler, flags, mojo, suites=None, *, success=True):
    """Seal with the Mojo tool and return the receipt, or the failed process."""
    result = run(_mojo_seal_command(root, stage, compiler, flags, mojo, suites),
                 success=success)
    if not success:
        return result
    return proofs.read_receipt(Path(stage) / _commands()['receipt'])


def mojo_verify(root, stage, compiler, flags, mojo, suites=None, *, success=True):
    """Rederive the receipt with the Mojo tool and require the saved file."""
    return run(
        _mojo_seal_command(root, stage, compiler, flags, mojo, suites, verify=True),
        success=success,
    )


def capture_with_compiler_budget(command, output, capture, *, mojo, loop_proof=None,
                                 source_root=None, success=True,
                                 seconds=None):
    """Retain the real sealed raw command and its owned-group supervision."""
    require_runtime_alarm()
    admission = _loop_labels()['admission']
    if seconds is None:
        seconds = _loop_labels()['integration_seconds']
    require((loop_proof is None) == (source_root is None), admission['proof_pair'])
    require(type(seconds) in (int, float)
            and 0 < seconds <= _loop_labels()['integration_seconds'],
            admission['bound'])
    deadline = time.monotonic() + seconds
    inherited = coverage_io.shared_deadline()
    if inherited is not None:
        deadline = min(deadline, inherited)
    environment = os.environ.copy()
    environment[coverage_io.DEADLINE_ENV] = repr(deadline)
    options = _commands()['options']
    arguments = [*coverage_io_argv(mojo, _commands()['capture']),
                 options['out'], str(output), options['err'], str(capture)]
    if loop_proof is not None:
        arguments += [options['loop_proof'], str(loop_proof),
                      options['loop_proof_root'], str(source_root)]
    # Do not use an outer SIGKILL timeout: capture owns a separate child group
    # and its existing absolute-deadline watchdog must reap that whole group.
    return run([*arguments, options['separator'], *command], success=success, env=environment)


def line_of(fragment):
    import os
    import subprocess
    root = Path(__file__).resolve().parents[1]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_coverage_loop_line', fragment],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise RuntimeError(message)
    return int(result.stdout.strip())


def capture_result(result, stem, envelope, command):
    """Keep raw/reduced diagnostic bytes; these are not production captures."""
    require(result.returncode == 0, _loop_labels()['admission']['failed_capture'])
    commands = _commands()
    raw = Path(str(stem) + commands['raw_suffix'])
    raw.parent.mkdir(parents=True, exist_ok=True)
    output = Path(str(stem) + commands['out_suffix'])
    reduced = Path(str(stem) + commands['reduced_suffix'])
    raw.write_text(result.stderr)
    output.write_text(result.stdout)
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[1]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = result.stderr.encode() if isinstance(result.stderr, str) else result.stderr
    with tempfile.TemporaryDirectory(prefix='reduce-capture-') as directory:
        source = Path(directory) / 'stderr.txt'
        source.write_bytes(payload)
        reduced_text = subprocess.run(
            [commands['shell'], str(root / commands['tool']), mojo,
             'carla_reduce_capture', str(source)],
            capture_output=True)
    if reduced_text.returncode != 0:
        errors = [line.strip() for line in reduced_text.stderr.splitlines()
                  if line.strip() and b'Crashpad' not in line]
        message = (errors[-1] if errors else reduced_text.stdout).decode()
        raise RuntimeError(message)
    with gzip.open(reduced, 'wb') as stream:
        stream.write(reduced_text.stdout)
    return raw, reduced


def mojo_mask(mojo, stage):
    """Return the masked manifest from the Mojo seal."""
    commands = _commands()
    target = Path(stage) / commands['masked']
    options = commands['options']
    run([commands['shell'], str(ROOT / commands['tool']), mojo, commands['seal'],
         commands['mask'],
         options['build'], str(stage), options['output'], str(target)])
    return target.read_bytes()


def diagnostic_manifest(masked, module, lines):
    """Project only the loop outcomes for native reporter unit controls.

    Never mutate the original manifest/origin or claim an aggregate gate.
    """
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[1]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='diagnostic-manifest-') as directory:
        path = Path(directory) / 'manifest.txt'
        path.write_bytes(masked)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_diagnostic_manifest', str(path), module,
             *[str(line) for line in lines]],
            capture_output=True)
    if result.returncode != 0:
        errors = [line.strip() for line in result.stderr.splitlines()
                  if line.strip() and b'Crashpad' not in line]
        message = (errors[-1] if errors else result.stdout).decode()
        raise RuntimeError(message)
    return result.stdout


def check_generated_receipt_owner(stage, mojo, compiler, flags, *, mutable_source=None):
    """Real receipt counts and optional separately provisioned mutation fixture.

    The optional source is a byte-copy admitted by the coordinated plan. This
    helper never copies or changes the sealed checkout, nor changes any timeout.
    """
    from carla_lane_oracle import full_audit_cleanup_contracts as audit
    from carla_lane_oracle import typed_boundary_contracts as typed
    root = ROOT if mutable_source is None else Path(mutable_source).resolve()
    stage = Path(stage).resolve()
    expected = proofs.read_receipt(stage / _commands()['receipt'])['receipt']
    admission = _loop_labels()['admission']
    profile = _loop_labels()['profile']
    require(proofs.maintained_inputs(root, exclude=stage) == expected['root_inputs'],
            admission['fixture'])
    if mutable_source is not None:
        require(root != ROOT.resolve() and not root.is_relative_to(ROOT.resolve()),
                admission['writable'])
    settings = {'mojo': [mojo], 'suites': expected['execution']['suites'],
                'capture_cache': proofs._expand_path(expected['execution']['cache'], root, stage)}
    def derive():
        return proofs.build_receipt(root, stage, compiler, flags, **settings)
    @contextlib.contextmanager
    def trace(callback=None):
        require(sys.getprofile() is None, admission['unprofiled'])
        counts, owners, binding_maps = defaultdict(int), [], []
        def profile(frame, event, value):
            if event not in (profile['call'], profile['return']):
                return
            if event == profile['call'] and frame.f_code is audit.verify.__code__:
                counts[profile['full']] += 1
            if event == profile['call'] and frame.f_code is typed.verify_sources.__code__:
                counts[profile['typed']] += 1
            if event == profile['return'] and frame.f_code is audit._receipt_operation_enter.__code__:
                owners.append(value)
            if (event == profile['return'] and frame.f_code is audit._InvariantInputs._receipt_bindings.__code__
                    and type(value) is dict):
                binding_maps.append(dict(value))
            if callback is not None:
                callback(frame, event, value, owners)
        sys.setprofile(profile)
        try:
            yield counts, owners, binding_maps
        finally:
            sys.setprofile(None)
    # PR760 composes the historical scaled edge only after the complete
    # physical gate admits the same owner. Historical endpoints retain their
    # supplemental pending-only path. Neither path may borrow stage bytes.
    current_cohort = audit._pr760_select(root)
    positives, observed_maps = [], []
    # The supplemental derivation runs inside a profile callback, where
    # nested calls are not profiled. Count two additional ordinary derivations
    # independently, without recursive profiling or inferred counter values.
    for attempt in range(3):
        supplements = []
        def pending_supplements(frame, event, value, owners):
            if attempt != 0 or event != profile['return']:
                return
            if (not supplements and frame.f_code is
                    audit._InvariantInputs._receipt_inputs_check.__code__):
                require(len(owners) == 1 and owners[0]._state == profile['pending'],
                        admission['pending'])
                owner = owners[0]
                supplements.append('scaled')
                scaled = audit.scaled_float32_proof_bindings(
                    root, include_roots=(stage,), _operation=owner)
                require(scaled and owner._state == (profile['active'] if current_cohort else profile['pending'])
                        and owner._scaled_resolver_paths == audit.scaled_float32.NATIVE_CLOSURE,
                        admission['scaled'])
                observed = (owner._raw.keys() if current_cohort else
                    {path for location, path, raw, mode in owner._receipt_observations
                     if location == owner._root})
                require(scaled.keys() <= observed,
                        admission['borrowed'])
            elif (supplements == ['scaled'] and frame.f_code is
                    audit._InvariantInputs._receipt_bindings.__code__):
                owner = owners[0]
                require(owner._state == profile['active'], admission['render_state'])
                supplements.append('render')
                # Current render fixtures themselves require typed admission.
                # Exercise their owned include path after the normal root gate.
                helpers = audit.shared_helper_proof_bindings(root,
                    paths=tuple(admission['helpers']),
                    include_roots=(stage,), _operation=owner)
                require(helpers and any(path.startswith('render/') for path in helpers)
                        and {path for path in helpers if path.endswith('.mojo')} <= owner._raw.keys()
                        and owner._scaled_resolver_paths == audit.scaled_float32.NATIVE_CLOSURE,
                        admission['domains'])
        with trace(pending_supplements) as (counts, owners, binding_maps):
            actual = derive()
        require(supplements == (admission['steps'] if attempt == 0 else []),
                admission['once'])
        require(proofs.canonical(actual) == proofs.canonical(expected),
                admission['receipt'])
        if attempt > 0:
            require(dict(counts) == {profile['full']: profile['full_count'],
                                      profile['typed']: profile['typed_count']},
                    admission['replay'])
        require(len(owners) == 1 and owners[0]._state == profile['closed']
                and not owners[0]._failed and owners[0]._owner_frame is None,
                admission['closed'])
        require(binding_maps, admission['binding'])
        observed_maps.extend(binding_maps)
        positives.append(owners[0])
    require(len({id(owner) for owner in positives}) == 3,
            admission['reused'])
    # A separately derived old path remains the exact dependency-map oracle.
    standalone = audit.proof_bindings(root, include_roots=(stage,))
    require(all(list(value.items()) == list(standalone.items()) for value in observed_maps),
            admission['cache'])
    print(_loop_labels()['owner_print'], flush=True)
    # A restored live-table mutation must still poison this real active owner.
    # This uses no writable source fixture and runs in the maintained entrypoint.
    labels = _loop_labels()
    conditioned = labels['conditioned']
    mutation = labels['mutation']
    conditioned_refusals = []
    def conditioned_authority_mutation(frame, event, value, owners):
        if (conditioned_refusals or event != profile['return']
                or frame.f_code is not audit._InvariantInputs._receipt_bindings.__code__):
            return
        require(len(owners) == 1 and frame.f_locals.get('self') is owners[0]
                and owners[0]._kind == profile['generated'] and owners[0]._state == profile['active']
                and not owners[0]._capturing,
                conditioned['active'])
        owner = owners[0]
        conditioned_refusals.append(profile['active'])
        old_bindings = audit.conditioned_cubic.BINDING_INPUTS
        try:
            audit.conditioned_cubic.BINDING_INPUTS = {**old_bindings, 'unreviewed': mutation['blank']}
            try:
                audit._typed_boundary_bindings(root, _operation=owner)
            except audit._OperationCoherenceError as error:
                require(str(error) == conditioned['error'], conditioned['immediate'])
                conditioned_refusals.append('refused')
            else:
                raise RuntimeError(conditioned['accepted'])
        finally:
            audit.conditioned_cubic.BINDING_INPUTS = old_bindings
        require(audit.conditioned_cubic.BINDING_INPUTS is old_bindings,
                conditioned['restore'])
        try:
            audit._operation_check(owner, root)
        except audit._OperationCoherenceError as error:
            require(str(error) == conditioned['error'], conditioned['sticky'])
            conditioned_refusals.append('sticky')
        else:
            raise RuntimeError(conditioned['revived'])
    with trace(conditioned_authority_mutation) as (_, owners, _):
        try:
            derive()
        except audit._OperationCoherenceError as error:
            require(str(error) == conditioned['error'], conditioned['unrelated'])
        else:
            raise RuntimeError(conditioned['receipt'])
    require(conditioned_refusals == conditioned['steps']
            and len(owners) == 1 and owners[0]._failed and owners[0]._state == profile['closed']
            and owners[0]._owner_frame is None and owners[0]._receipt_seed is None,
            conditioned['close'])
    print(conditioned['print'], flush=True)
    if mutable_source is None:
        return dict(_loop_labels()['owner'])

    # These mutations require only the separately admitted writable source and
    # generated stage. The complete positive producer relation is rechecked
    # before every case. No saved source receipt is modified or rebound.
    source_name = mutation['source']
    include_name = mutation['include']
    def replace_file(path, data, location):
        require(path.is_file() and not path.is_symlink()
                and path.resolve().is_relative_to(location) and path.stat().st_nlink == 1,
                mutation['ordinary'])
        original = ROOT/path.relative_to(location)
        if original.exists():
            require((path.stat().st_dev, path.stat().st_ino)
                    != (original.stat().st_dev, original.stat().st_ino),
                    mutation['inode'])
        path.unlink()
        with path.open('xb') as stream:
            stream.write(data)
    faults = mutation['faults']
    completed = []
    for fault in faults:
        require(proofs.maintained_inputs(root, exclude=stage) == expected['root_inputs'],
                mutation['restored_before'])
        proofs.check_capture_inputs({'receipt': expected}, root, stage)
        restored, fired, caught = [], [], []
        def write(path, data, location):
            raw = path.read_bytes()
            replace_file(path, data, location)
            restored.append(lambda: replace_file(path, raw, location))
        def profile(frame, event, value, owners):
            if fired or event != profile['return'] or frame.f_code is not audit._InvariantInputs._receipt_bindings.__code__:
                return
            fired.append(True)
            require(len(owners) == 1 and owners[0]._state == profile['active'], mutation['admission'])
            owner = owners[0]
            if fault.startswith('source') and fault != 'source-root':
                target = root/source_name
                raw = target.read_bytes()
                write(target, raw + mutation['changed_source'].encode(), root)
                if fault == 'source-transient-read':
                    consumed = target.read_bytes()
                    restored.pop()()
                    try:
                        audit._observe_bytes(root, source_name, consumed, _operation=owner)
                    except ValueError as error:
                        require(mutation['consumed_prefix'] + source_name in str(error),
                                mutation['transient'])
                        caught.append(True)
                    else:
                        raise RuntimeError(mutation['accepted_transient'])
            elif fault in ('include', 'include-entry'):
                target = stage/include_name
                suffix = (mutation['include_entry'] if fault == 'include-entry'
                          else mutation['unsealed']).encode()
                write(target, target.read_bytes()+suffix, stage)
            elif fault == 'authority':
                old = typed.BINDING_INPUTS
                typed.BINDING_INPUTS = {**old, 'unreviewed': mutation['blank']}
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
                        result = proofs.reviewed_nonempty_loops(root, mutation['map'],
                            include_roots=(stage,), _operation=owner)
                        require(result == {} and owner._failed, mutation['borrower'])
                        raise ValueError(mutation['sticky_public'])
                except ValueError:
                    caught.append(True)
                else:
                    raise RuntimeError(mutation['foreign'])
            elif fault in ('lookup-shadow', 'compiled-shadow'):
                target = stage/(mutation['lookup_shadow'] if fault == 'lookup-shadow'
                                else mutation['compiled_shadow'])
                require(not target.exists(), mutation['shadow_collision'])
                target.write_bytes(mutation['shadow_body'].encode())
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
                write(target, target.read_bytes() + mutation['origin_change'].encode(), stage)
            elif fault == 'checker':
                name = mutation['checker']
                require(owner._checker_receipt and name in owner._executing and name not in owner._raw,
                        mutation['checker_domain'])
                target = root/name
                write(target, target.read_bytes() + mutation['checker_change'].encode(), root)
            elif fault == 'nested-owner':
                from unittest.mock import patch
                original_read = Path.read_text
                inner_seen = []
                def nested_read(path, *args, **kwargs):
                    if not inner_seen and path == root/source_name:
                        current = sys._getframe(1)
                        while current is not None and current.f_code is not proofs.build_receipt.__code__:
                            current = current.f_back
                        require(current is not None, mutation['nested_absent'])
                        inner = current.f_locals.get('_operation')
                        require(inner is not owner and inner._kind == profile['generated'],
                                mutation['nested_reused'])
                        inner_seen.append(inner)
                        try:
                            audit._operation_check(owner, root)
                        except ValueError as error:
                            require(mutation['nearer'] in str(error),
                                    mutation['nested_boundary'])
                            caught.append(True)
                        else:
                            raise RuntimeError(mutation['nested_borrowed'])
                    return original_read(path, *args, **kwargs)
                with patch.object(Path, 'read_text', nested_read):
                    inner_result = derive()
                require(len(inner_seen) == 1 and inner_seen[0]._state == profile['closed']
                        and not inner_seen[0]._failed
                        and proofs.canonical(inner_result) == proofs.canonical(expected),
                        mutation['nested_fresh'])
            if caught:
                try:
                    audit._operation_check(owner, root)
                except ValueError:
                    pass
                else:
                    raise RuntimeError(mutation['poison'])
        try:
            with trace(profile) as (_, owners, _):
                try:
                    derive()
                except ValueError:
                    pass
                else:
                    raise RuntimeError(mutation['receipt_prefix'] + fault)
            require(fired == [True] and len(owners) == 1 and owners[0]._failed
                    and owners[0]._state == profile['closed'] and owners[0]._owner_frame is None,
                    mutation['close_prefix'] + fault)
        finally:
            for restore in reversed(restored):
                restore()
        completed.append(fault)
    require(proofs.maintained_inputs(root, exclude=stage) == expected['root_inputs'],
            mutation['fixture_restored'])
    proofs.check_capture_inputs({'receipt': expected}, root, stage)
    print(_loop_labels()['refusals_print'], ', '.join(completed), flush=True)
    result = dict(_loop_labels()['owner'])
    result[_loop_labels()['mutation_key']] = completed
    return result



def check_current_generated_include_root(stage, mojo, compiler, flags):
    """Exercise real maintained generation with the complete passthrough layout."""
    commands = _commands()
    options = commands['options']
    run([commands['shell'], str(ROOT / commands['tool']), mojo,
         commands['include_root'], options['mojo'], mojo, options['stage'], str(stage),
         options['compiler'], compiler, options['flags'], flags], cwd=ROOT)
    owner_result = check_generated_receipt_owner(stage, mojo, compiler, flags)
    labels = _loop_labels()
    require(owner_result == labels['owner'], labels['owner_message'])
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
    require(root_only == _loop_labels()['root_only'],
            _loop_labels()['root_message'])
    return 6



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    options = _commands()['options']
    parser.add_argument(options['mojo'], default=str(ROOT / '.venv/bin/mojo'))
    parser.add_argument(options['output'], type=Path)
    args = parser.parse_args()
    mojo = str(Path(args.mojo).resolve())
    compiler = run([mojo, options['version']]).stdout.strip()
    commands = _commands()
    flags = commands['flags']

    if args.output is None:
        workspace = tempfile.TemporaryDirectory(prefix=commands['workspace_prefix'])
    else:
        retained = args.output.resolve() / commands['attempt']
        retained.mkdir(parents=True, exist_ok=False)
        workspace = contextlib.nullcontext(str(retained))
    with workspace as directory:
        work = Path(directory)
        current_rows = check_current_generated_include_root(
            work/commands['current'], mojo, compiler, flags)
        print(_loop_labels()['theorems'], current_rows, flush=True)
        require_runtime_alarm()
        run([commands['shell'], str(ROOT / commands['tool']), mojo,
             commands['fixture'], options['mojo'], mojo])
        results = _loop_labels()['results']
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            (args.output / commands['native_source']).write_text(_loop_drivers()['source'])
            (args.output / commands['qualification']).write_text(json.dumps(results, indent=2) + '\n')
        print(_loop_labels()['pass_line'])


if __name__ == '__main__':
    main()
