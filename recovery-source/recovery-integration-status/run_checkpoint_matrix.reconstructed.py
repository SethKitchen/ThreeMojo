"""Owned #711 qualification; exact source/SDK seals and per-stage bounds."""
from pathlib import Path
from datetime import datetime, timezone
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
start = time.monotonic()
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
    verify(); t=time.monotonic(); log=E/(label+'.log'); cwd=S if cwd is None else Path(cwd)
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
    if timedout or clean['remaining'] or (p.returncode and not accept_nonzero):raise RuntimeError('Stage failed: '+label)
verify()
sdk=identity.executable_identity(M)
restored=json.loads((R.parent/'restored-toolchain/receipts/mojo-identity.json').read_text())
assert sdk==restored
assert sha(Path(PY).resolve())==sdk['interpreter']['sha256']
dump(E/'SDK-BEFORE.json',sdk)
dump(E/'WINDOW-START.json',{'started':now(),'supervisor_pid':os.getpid(),'supervisor_sha256':sha(__file__),'python_optimize':sys.flags.optimize,'runtime_gate_seconds':5,'sdk_payload_count':len(sdk['payload']),'whole_window_seconds':config.get('window_seconds', 1800),'source_seal_sha256':sha(E/'SOURCE-SEAL.json')})
success=False;failure=None
try:
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
    success=True
except BaseException as error:
    failure=repr(error);dump(E/'FAILURE.json',{'error':failure,'traceback':traceback.format_exc()})
finally:
    clean=cleanup();verify();after=identity.executable_identity(M);dump(E/'SDK-AFTER.json',after)
    result={'sequence_completed':success,'failure':failure,'stages':records,'source_seal_unchanged':True,'sdk_identity_unchanged':sdk==after,'remaining_owned_descendants':clean['remaining'],'known_process_count':len(known),'finished':now(),'elapsed_seconds':time.monotonic()-start,'scope':config['scope']}
    dump(E/'RESULT.json',result);print(json.dumps(result),flush=True)
raise SystemExit(not success or sdk!=after or bool(clean['remaining']))
