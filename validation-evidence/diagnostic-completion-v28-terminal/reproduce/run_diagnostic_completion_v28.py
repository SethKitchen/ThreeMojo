"""Owned #711 qualification; exact source/SDK seals and per-stage bounds."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import ctypes, hashlib, json, os, re, signal, subprocess, sys, time, traceback

sys.dont_write_bytecode = True
if sys.flags.optimize:
    raise RuntimeError('Supervisor must remain unoptimized')
R = Path(__file__).resolve().parent
config = json.loads(Path(sys.argv[1]).read_text())
S = (R / config['source']).resolve()
E = R / 'evidence' / config['phase']
E.mkdir(parents=True, exist_ok=False)
M = str(R.parent / 'restored-toolchain/official-venv/bin/mojo')
PY = str(R.parent / 'restored-toolchain/official-venv/bin/python')
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
now = lambda: datetime.now(timezone.utc).isoformat()
def dump(path, data):
    Path(path).write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
def snapshot(folder):
    return {str(p.relative_to(folder)):sha(p) for p in sorted(folder.rglob('*')) if p.is_file() and not any(part in ('__pycache__', '.cache') for part in p.relative_to(folder).parts) and p.relative_to(folder).parts[:2] != ('coverage', 'build')}
expected = json.loads((R / config["seal"]).read_text())
dump(E / 'SOURCE-SEAL.json', expected)
additional = [(Path(item['source']).resolve(), json.loads(Path(item['seal']).read_text()))
              for item in config.get('additional_sources', [])]
def verify():
    if snapshot(S) != expected:
        raise RuntimeError('Source or fixture seal changed')
    for folder, bound in additional:
        if snapshot(folder) != bound:
            raise RuntimeError('Additional baseline source seal changed: ' + str(folder))
assert ctypes.CDLL(None, use_errno=True).prctl(36, 1, 0, 0, 0) == 0
for key in list(os.environ):
    if key in ('AFFECTED','MAKEFLAGS','MFLAGS','MAKELEVEL','MAKEFILES','MAKEOVERRIDES','GNUMAKEFLAGS','PYTHONPATH','PYTHONHOME','PYTHONUSERBASE','PYTHONOPTIMIZE','PYTHONPYCACHEPREFIX','THREEMOJO_TEST_TMPDIR','MODULAR_HOME','LD_PRELOAD','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH','DYLD_INSERT_LIBRARIES','MODULAR_MAX_PACKAGE_ROOT','CI_SELECTION_SHA256','THREEMOJO_COVERAGE_DEADLINE') or key.startswith(('MODULAR_MOJO_', 'THREEMOJO_COVERAGE_PHASES')):
        os.environ.pop(key, None)
os.environ['MODULAR_TELEMETRY_ENABLED'] = 'false'
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
os.environ['PATH'] = str(Path(PY).parent) + ':' + os.environ.get('PATH', '')
for key, name in [('HOME','home'),('MODULAR_CACHE_DIR','compiler-cache'),('XDG_CACHE_HOME','xdg-cache'),('XDG_DATA_HOME','xdg-data')]:
    p = R / 'runtime-cache' / name
    p.mkdir(parents=True, exist_ok=True)
    os.environ[key] = str(p)
sys.path.insert(0, str(S / 'tools'))
import coverage_toolchain_identity as identity
cpu = min(os.sched_getaffinity(0))
known = {}
records = []
# Separate diagnostic completion: validate the exact interrupted/unlaunched suffix.
# This independent bound does not extend or relabel either earlier failed attempt.
def checked_provenance(key, relative, expected_sha, parse_json=True):
    if config[key] != relative or config[key + '_sha256'] != expected_sha:
        raise RuntimeError('Diagnostic completion provenance configuration differs: ' + key)
    payload = (R / relative).read_bytes()
    if hashlib.sha256(payload).hexdigest() != expected_sha:
        raise RuntimeError('Diagnostic completion provenance bytes differ: ' + key)
    return json.loads(payload) if parse_json else payload

original_result = checked_provenance('original_matrix_result',
    'evidence/full-python-matrix-final-v28/RESULT.json',
    'a2d054ac36ac97e729d292956a2233f10b479b6f40194fec90c9f088858be844')
prior_result = checked_provenance('prior_diagnostic_result',
    'evidence/full-python-diagnostic-continuation-v28/RESULT.json',
    'ddcd0576ed61827896eac96a52ae44a7d98cbb9f202137d7a38ecb887838359b')
prior_config = checked_provenance('prior_diagnostic_config',
    'full-python-diagnostic-continuation-v28.json',
    'a7282c67969f81b7e323cb685ed635db516aaf79621ea107d3d86ff2ecf1a0b3')
checked_provenance('prior_diagnostic_supervisor', 'run_diagnostic_continuation_v28.py',
    '0c6cf71e8be2fe48be76414cd800449e382569de824424a9e51110e90bc50ffc', False)
completion_inventory = checked_provenance('completion_inventory',
    'DIAGNOSTIC-COMPLETION-14-STAGE-INVENTORY.json',
    '2b29b4ff8e64832e7684f82176a34347f5f0fb9bc9c4e9297ce1ae953f15e7aa')
prior_sdk = checked_provenance('prior_sdk_after',
    'evidence/full-python-diagnostic-continuation-v28/SDK-AFTER.json',
    '7df7b8ba0859f186a2f372435db4dac19a1d08a6f1c724981158d612581ed207')
expected_inventory_payload = Path(config['expected_inventory']).read_bytes()
if (config['expected_inventory'] != str(R / 'FINAL-PYTHON-EXPECTED-INVENTORY-V28.json') or
        config['expected_inventory_sha256'] != '0996f6650319b26da030bcfccf85868e2eba6b755a46063bec9daabfd796a2f9' or
        hashlib.sha256(expected_inventory_payload).hexdigest() != config['expected_inventory_sha256']):
    raise RuntimeError('Original fresh test inventory differs')
expected_inventory = json.loads(expected_inventory_payload)
original_deadline = (datetime.fromisoformat(original_result['finished']) +
                     timedelta(seconds=10800 - original_result['elapsed_seconds']))
if (original_result['sequence_completed'] is not False or not original_result['failure'] or
        original_deadline.isoformat() != config['original_absolute_deadline_utc'] or
        config['original_absolute_deadline_utc'] != '2026-10-11T08:35:38.016452+00:00' or
        prior_result['absolute_deadline_utc'] != config['original_absolute_deadline_utc']):
    raise RuntimeError('Original failed attempts or deadline provenance differ')
if (prior_result['diagnostic_only'] is not True or prior_result['qualification_passed'] is not False or
        prior_result['sequence_completed'] is not False or
        prior_result['source_seal_unchanged'] is not True or prior_result['sdk_identity_unchanged'] is not True or
        prior_result['remaining_owned_descendants'] != [] or
        len(prior_result['stages']) != 124):
    raise RuntimeError('Prior diagnostic terminal receipt is not the reviewed interrupted collection')
prior_labels = [stage['label'] for stage in prior_config['stages']]
recorded_labels = [stage['label'] for stage in prior_result['stages']]
interrupted = prior_result['stages'][-1]
if (recorded_labels != prior_labels[:124] or interrupted['label'] != '70-normal-test_sampled_values' or
        interrupted['timed_out'] is not True or interrupted['returncode'] != -9 or
        interrupted['leader_reaped'] is not True or interrupted['remaining_owned_descendants'] != [] or
        prior_result['unrun_stage_labels'] != prior_labels[124:] or
        completion_inventory['interrupted'] != [interrupted['label']] or
        completion_inventory['never_launched'] != prior_result['unrun_stage_labels'] or
        completion_inventory['original_result_sha256'] != config['prior_diagnostic_result_sha256'] or
        config['stages'] != completion_inventory['stages'] or config['stages'] != prior_config['stages'][123:]):
    raise RuntimeError('Completion plan is not the exact interrupted plus unlaunched suffix')
if (len(config['stages']) != 14 or sum(stage['expected_tests'] for stage in config['stages']) != 286 or
        any(stage['seconds'] != 1800 or stage['accept_nonzero'] is not True for stage in config['stages']) or
        config['window_seconds'] != 7800 or config['diagnostic_only'] is not True or
        config['qualification_passed'] is not False or config['window_policy'] != 'independent-bounded-diagnostic-completion'):
    raise RuntimeError('Independent diagnostic bounds or scope differ')
if (config['source'] != prior_config['source'] or config['seal'] != prior_config['seal'] or
        config['source_seal_sha256'] != prior_config['source_seal_sha256'] or
        config['source_seal_sha256'] != 'fb5449c65d6652cff19c087c1d91422597cbc95bd19b2f6a5d3602032a1cd596' or
        sha(E / 'SOURCE-SEAL.json') != config['source_seal_sha256'] or
        expected_inventory['source_seal_sha256'] != config['source_seal_sha256'] or
        sha(__file__) != config['supervisor_sha256'] or
        config['phase'] != 'full-python-diagnostic-completion-v28'):
    raise RuntimeError('Immutable v28 source or completion supervisor identity differs')
modules = {module['path']: module for module in expected_inventory['modules']}
for stage in config['stages']:
    command = stage['command']
    path = command[command.index('-s') + 1] + '/' + command[command.index('-p') + 1]
    mode = '1' if '-O' in command else '0'
    module = modules[path]
    if (module['sha256'] != expected[path] or module['test_count'] != stage['expected_tests'] or
            module['modes'][mode]['test_count'] != stage['expected_tests']):
        raise RuntimeError('Completion expected test/source inventory differs: ' + path)
# Both clocks begin together, before source/SDK preflight. Pauses consume this
# independent budget. It neither borrows nor replenishes either original window.
start = time.monotonic()
absolute_deadline = datetime.now(timezone.utc) + timedelta(seconds=config['window_seconds'])
config['absolute_deadline_utc'] = absolute_deadline.isoformat()
def descendants():
    rows = {}
    for path in Path('/proc').iterdir():
        if not path.name.isdecimal(): continue
        try:
            f = (path/'stat').read_text().rsplit(')',1)[1].split()
            rows[int(path.name)] = {'pid':int(path.name),'ppid':int(f[1]),'pgid':int(f[2]),'state':f[0],'start_ticks':int(f[19])}
        except (FileNotFoundError,ProcessLookupError): pass
    owned = {os.getpid()}
    prior = None
    while prior != owned:
        prior = set(owned)
        owned.update(pid for pid,row in rows.items() if row['ppid'] in owned)
    result = [row for pid,row in rows.items() if pid in owned and pid != os.getpid()]
    for row in result: known[(row['pid'],row['start_ticks'])] = row
    return result
def kill(row):
    fd = None
    try:
        fd = os.pidfd_open(row['pid'],0)
        f = (Path('/proc')/str(row['pid'])/'stat').read_text().rsplit(')',1)[1].split()
        if int(f[19]) == row['start_ticks']: signal.pidfd_send_signal(fd, signal.SIGKILL)
    except (FileNotFoundError,ProcessLookupError): pass
    finally:
        if fd is not None: os.close(fd)
def reap():
    result=[]
    while True:
        try:
            pid,status=os.waitpid(-1,os.WNOHANG)
            if not pid:return result
            result.append({'pid':pid,'status':status})
        except ChildProcessError:return result
def cleanup():
    adopted=[]
    for _ in range(80):
        owned=descendants()
        if not owned:return {'remaining':[],'reaped':adopted}
        for row in owned:kill(row)
        adopted+=reap();time.sleep(.05)
    return {'remaining':descendants(),'reaped':adopted}
def interrupted(signum, frame): raise InterruptedError(str(signum))
for sig in (signal.SIGINT,signal.SIGTERM):signal.signal(sig,interrupted)
def run(label,command,accept_nonzero=False,seconds=180,cwd=None):
    verify()
    if identity.executable_identity(M) != sdk:
        raise RuntimeError('SDK identity changed before diagnostic stage')
    if time.monotonic() - start >= config['window_seconds'] - 10:
        raise RuntimeError('Independent diagnostic completion window exhausted before launch')
    t=time.monotonic(); log=E/(label+'.log'); cwd=S if cwd is None else Path(cwd)
    record={'label':label,'argv':command,'cwd':str(cwd),'started':now(),'source_seal_sha256':sha(E/'SOURCE-SEAL.json'),'single_cpu':cpu,'stage_timeout_seconds':seconds}
    timedout=False
    with log.open('w') as stream:
        p=subprocess.Popen(['taskset','-c',str(cpu)]+command,cwd=cwd,env=os.environ.copy(),stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
        record.update(pid=p.pid,pgid=os.getpgid(p.pid));dump(E/(label+'-START.json'),record)
        try:
            while p.poll() is None:
                state={'label':label,'at':now(),'owned':descendants()};dump(E/'LATEST.json',state)
                with (E/'PROCESSES.jsonl').open('a') as out:out.write(json.dumps(state)+'\n')
                if time.monotonic()-t > seconds or time.monotonic()-start > config.get('window_seconds', 1800) - 10:timedout=True;break
                time.sleep(.5)
        finally:
            if p.poll() is None:
                for row in descendants():kill(row)
            p.wait();adopted=reap();clean=cleanup()
    record.update(returncode=p.returncode,seconds=time.monotonic()-t,timed_out=timedout,leader_reaped=True,adopted_reaped=adopted+clean['reaped'],remaining_owned_descendants=clean['remaining'],log_sha256=sha(log))
    dump(E/(label+'-RESULT.json'),record);records.append(record);print(json.dumps(record),flush=True);verify()
    if identity.executable_identity(M) != sdk:
        raise RuntimeError('SDK identity changed after diagnostic stage')
    if timedout or clean['remaining'] or (p.returncode and not accept_nonzero):raise RuntimeError('Stage failed: '+label)
verify()
sdk=identity.executable_identity(M)
restored=json.loads((R.parent/'restored-toolchain/receipts/mojo-identity.json').read_text())
assert sdk==restored
if sdk != prior_sdk:
    raise RuntimeError('SDK differs from the sealed prior diagnostic receipt')
assert sha(Path(PY).resolve())==sdk['interpreter']['sha256']
dump(E/'SDK-BEFORE.json',sdk)
dump(E/'WINDOW-START.json',{'started':now(),'supervisor_pid':os.getpid(),'supervisor_sha256':sha(__file__),'python_optimize':sys.flags.optimize,'runtime_gate_seconds':5,'sdk_payload_count':len(sdk['payload']),'whole_window_seconds':config.get('window_seconds', 1800),'source_seal_sha256':sha(E/'SOURCE-SEAL.json')})
success=False;failure=None
try:
    if config['window_seconds'] <= 10:
        raise RuntimeError('Independent diagnostic completion window exhausted before initial collection')
    for stage in config['stages']:
        pause_request = R / config.get('pause_request_file', 'native-lane.pause')
        if pause_request.exists():
            if descendants():
                raise RuntimeError('Cannot yield while owned descendants remain')
            verify()
            if identity.executable_identity(M) != sdk:
                raise RuntimeError('SDK identity changed before lane checkpoint')
            pause_started = time.monotonic()
            pause_record = {'paused': True, 'started': now(),
                            'next_stage': stage['label'],
                            'source_seal_sha256': sha(E / 'SOURCE-SEAL.json'),
                            'remaining_owned_descendants': []}
            dump(E / 'LANE-CHECKPOINT.json', pause_record)
            while pause_request.exists():
                if time.monotonic() - start > config.get('window_seconds', 1800) - 10:
                    raise RuntimeError('Whole-window deadline reached at lane checkpoint')
                time.sleep(1)
            verify()
            if identity.executable_identity(M) != sdk:
                raise RuntimeError('SDK identity changed during lane checkpoint')
            pause_record.update(paused=False, resumed=now(),
                                paused_seconds=time.monotonic()-pause_started)
            dump(E / 'LANE-CHECKPOINT.json', pause_record)
            with (E / 'LANE-HANDOFFS.jsonl').open('a') as output:
                output.write(json.dumps(pause_record) + '\n')
        command = [part.replace('{mojo}', M).replace('{python}', PY).replace('{evidence}', str(E)).replace('{root}', str(R)) for part in stage['command']]
        run(stage['label'], command, stage.get('accept_nonzero', False), stage.get('seconds', 180), stage.get('cwd'))
        if 'expected_tests' in stage:
            log = E / (stage['label'] + '.log')
            text = log.read_text()
            totals = re.findall(r'(?m)^Ran (\d+) tests? in ', text)
            if len(totals) != 1 or int(totals[0]) != stage['expected_tests']:
                raise RuntimeError('Test inventory mismatch: ' + stage['label'])
            records[-1]['test_count'] = int(totals[0])
            records[-1]['expected_tests'] = stage['expected_tests']
            records[-1]['skipped_test_count'] = sum(" ... skipped " in line for line in text.splitlines())
            dump(E / (stage['label'] + '-RESULT.json'), records[-1])
            if records[-1]['skipped_test_count']:
                raise RuntimeError('Unexpected skipped tests: ' + stage['label'])
    success=True
except BaseException as error:
    failure=repr(error);dump(E/'FAILURE.json',{'error':failure,'traceback':traceback.format_exc()})
finally:
    clean=cleanup();verify();after=identity.executable_identity(M);dump(E/'SDK-AFTER.json',after)
    result={'sequence_completed':success,'failure':failure,'stages':records,'source_seal_unchanged':True,'sdk_identity_unchanged':sdk==after,'remaining_owned_descendants':clean['remaining'],'known_process_count':len(known),'finished':now(),'elapsed_seconds':time.monotonic()-start,'scope':config['scope']}
    result.update(diagnostic_only=True, qualification_passed=False,
                  nonzero_stage_labels=[r['label'] for r in records if r['returncode']],
                  unrun_stage_labels=[s['label'] for s in config['stages'][len(records):]],
                  original_matrix=config['original_matrix'], absolute_deadline_utc=config['absolute_deadline_utc'],
                  original_absolute_deadline_utc=config['original_absolute_deadline_utc'],
                  prior_diagnostic_result=config['prior_diagnostic_result'],
                  prior_diagnostic_result_sha256=config['prior_diagnostic_result_sha256'],
                  completion_inventory_sha256=config['completion_inventory_sha256'],
                  window_policy=config['window_policy'], whole_window_seconds=config['window_seconds'])
    dump(E/'RESULT.json',result);print(json.dumps(result),flush=True)
raise SystemExit(not success or sdk!=after or bool(clean['remaining']) or
                 any(r['returncode'] for r in records))
