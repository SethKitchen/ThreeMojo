import hashlib,json,os,pathlib,signal,subprocess,sys,time,datetime
from mojo.run import _mojo_env
ENV = _mojo_env() | {'MODULAR_TELEMETRY_ENABLED':'false','PYTHONDONTWRITEBYTECODE':'1'}
BASE=pathlib.Path(__file__).resolve().parent; SRC=BASE/'src'; E=BASE/'evidence'; BIN=BASE/'bin'; BIN.mkdir(exist_ok=True)

for key, leaf in [('HOME','home'),('MODULAR_CACHE_DIR','modular-cache'),('XDG_CACHE_HOME','xdg-cache'),('XDG_DATA_HOME','xdg-data')]:
    directory=BASE/leaf; directory.mkdir(exist_ok=True); ENV[key]=str(directory)
WORK=BASE.parent; PY=WORK/'restored-toolchain/official-venv/bin/python'; SDK=WORK/'restored-toolchain/official-venv/lib/python3.12/site-packages'; MOJO=SDK/'modular/bin/mojo'
sys.path.insert(0,str(SRC/'tools')); from compiler_telemetry import ProcReader, identity
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
commit='d06143b149ba31ab44afaa690c93289b57bc1778'; donor=WORK/'ThreeMojo-restored'
def git(*args):return subprocess.check_output(['git','-C',str(donor),*args])
entries=git('ls-tree','-r','--full-tree',commit).decode().splitlines(); mismatch=[]
for line in entries:
    meta,name=line.split('\t',1); mode,kind,obj=meta.split()
    if kind=='blob' and subprocess.check_output(['git','hash-object',str(SRC/name)]).decode().strip()!=obj:mismatch.append(name)
receipt=json.loads((WORK/'restored-toolchain/receipts/mojo-identity.json').read_text()); checks={name:sha(SDK/name)==expected for name,expected in receipt['payload'].items()}
record={'commit':git('rev-parse',commit).decode().strip(),'tree':git('rev-parse',commit+'^{tree}').decode().strip(),'archive_files':len(entries),'archive_mismatches':mismatch,'donor_status_before':git('status','--porcelain').decode(),'mojo_version':subprocess.check_output([MOJO,'--version'],env=ENV).decode().strip(),'python_version':sys.version,'sdk_payload_receipt_matches':checks,'mojo_sha256':sha(MOJO),'python_sha256':sha(pathlib.Path(sys.executable).resolve()),'maintained_test_seconds':5,'compile_outer_budget_seconds':300,'gpu_claim':False,'explicit_sdk_environment':{k:v for k,v in ENV.items() if k.startswith('MODULAR_') or k in ['HOME','XDG_CACHE_HOME','XDG_DATA_HOME']}}
(E/'identity.json').write_text(json.dumps(record,indent=2)); assert not mismatch and all(checks.values()); assert record['mojo_version']=='Mojo 1.1.0 (8189361e)'; assert record['donor_status_before']==''
results=[]
def run(label,cmd,budget):
    start=time.monotonic(); rec={'label':label,'command':list(map(str,cmd)),'cwd':str(SRC),'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'outer_budget_seconds':budget}; observed={}; reader=ProcReader()
    with (E/(label+'.log')).open('w') as log,(E/(label+'.descendants.jsonl')).open('w') as trace:
        p=subprocess.Popen(cmd,cwd=SRC,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,env=ENV)
        rec['pid']=p.pid; deadline=start+budget
        while p.poll() is None:
            snap=reader.tree(p.pid)
            for s in snap:observed[identity(s)]=s
            trace.write(json.dumps({'elapsed_seconds':time.monotonic()-start,'tree':snap})+'\n');trace.flush()
            if time.monotonic()>deadline:
                rec['timed_out']=True;os.killpg(p.pid,signal.SIGKILL);p.wait();break
            time.sleep(.5)
        rec['exitcode']=p.wait()
        try: os.killpg(p.pid,0); group_exists=True
        except ProcessLookupError:group_exists=False
        rec['process_group_remaining_before_cleanup']=group_exists
        if group_exists:os.killpg(p.pid,signal.SIGKILL)
        rec['observed_descendants_remaining']=[s for (pid,startid),s in observed.items() if (now:=reader.stat(pathlib.Path(str(pid)))) and identity(now)==(pid,startid) and now['state']!='Z']
        rec['elapsed_seconds']=time.monotonic()-start
    results.append(rec); (E/'results.json').write_text(json.dumps(results,indent=2)); print(json.dumps(rec),flush=True); return rec['exitcode']==0
for suite in ['test_wide_line_workers','test_wide_lines','test_renderer_resources']:
    source='tests/'+suite+'.mojo'; output=BIN/suite
    command=[PY,'tools/compiler_telemetry.py','--suite',source,'--',PY,'tools/native_test_support.py','run','--root','.','--suite',source,'--cache',str(BASE/'native'),'--',MOJO,'build','-I','.','--Werror','-o',output,source]
    if run(suite+'.build',command,300):run(suite+'.run',[PY,'tools/run_suite.py','--seconds','5','--suite',source,'--',output],5*(sum(line.startswith('def test_') for line in (SRC/source).read_text().splitlines())+1)+5)
record['donor_status_after']=git('status','--porcelain').decode(); record['source_files_unchanged_after']=all(subprocess.check_output(['git','hash-object',str(SRC/line.split('\t',1)[1])]).decode().strip()==line.split()[2] for line in entries if line.split()[1]=='blob');(E/'identity.json').write_text(json.dumps(record,indent=2))
