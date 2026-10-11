import hashlib,json,subprocess,time,os
from pathlib import Path
BASE=Path(__file__).resolve().parent
ROOT=BASE/'native-safe'
ROOT.mkdir()
MOJO=BASE.parent/'restored-toolchain/official-venv/bin/mojo'
for key in list(os.environ):
    if key in ('AFFECTED','MAKEFLAGS','MFLAGS','MAKELEVEL','MAKEFILES','MAKEOVERRIDES','GNUMAKEFLAGS','PYTHONPATH','PYTHONHOME','PYTHONUSERBASE','PYTHONOPTIMIZE','PYTHONPYCACHEPREFIX','THREEMOJO_TEST_TMPDIR','MODULAR_HOME','LD_PRELOAD','LD_LIBRARY_PATH','DYLD_LIBRARY_PATH','DYLD_INSERT_LIBRARIES','MODULAR_MAX_PACKAGE_ROOT','CI_SELECTION_SHA256','THREEMOJO_COVERAGE_DEADLINE') or key.startswith(('MODULAR_MOJO_', 'THREEMOJO_COVERAGE_PHASES')):
        os.environ.pop(key,None)
os.environ['MODULAR_TELEMETRY_ENABLED']='false'
os.environ['PYTHONDONTWRITEBYTECODE']='1'
os.environ['PATH']=str(MOJO.parent)+':'+os.environ.get('PATH','')
for key,name in [('HOME','home'),('MODULAR_CACHE_DIR','compiler-cache'),('XDG_CACHE_HOME','xdg-cache'),('XDG_DATA_HOME','xdg-data')]:
    path=ROOT/'runtime-cache'/name
    path.mkdir(parents=True,exist_ok=True)
    os.environ[key]=str(path)
(ROOT/'environment.json').write_text(json.dumps({key:os.environ[key] for key in ['MODULAR_TELEMETRY_ENABLED','PYTHONDONTWRITEBYTECODE','HOME','MODULAR_CACHE_DIR','XDG_CACHE_HOME','XDG_DATA_HOME']},indent=2)+'\n')
value=lambda n:f'def value() -> Int:\n    return {n}\n'
probe='from pkg.one import value\n\ndef main():\n    print(value())\n'
base={'tools/probe.mojo':probe,'pkg/one.mojo':'from helper import value\n','helper.mojo':value(10),'pkg/helper.mojo':value(20)}
cases=[]
def add(name,changes,expected,diagnostic=None):
    files=dict(base)
    for k,v in changes.items():
        if v is None: files.pop(k,None)
        else: files[k]=v
    cases.append((name,files,expected,diagnostic))
add('root_transitive',{},'10')
add('root_transitive_with_init',{'pkg/__init__.mojo':''},'10')
add('entry_transitive',{'tools/helper.mojo':value(30)},'30')
add('entry_direct',{'tools/probe.mojo':'from helper import value\n\ndef main():\n    print(value())\n','tools/helper.mojo':value(30)},'30')
add('missing_root',{'helper.mojo':None},None,"unable to locate module 'helper'")
add('missing_root_with_init',{'helper.mojo':None,'pkg/__init__.mojo':''},None,"unable to locate module 'helper'")
add('entry_package_hides_root',{'tools/pkg/__init__.mojo':''},None,"unable to locate module 'one'")
add('entry_module_hides_root',{'tools/pkg.mojo':value(30)},None,"unable to locate module 'one'")
add('plain_entry_namespace',{'tools/pkg/other.mojo':value(30)},'10')
add('ambiguous_namespace',{'tools/pkg/one.mojo':value(30)},None,"ambiguous import 'one'")
results=[]
for name,files,expected,diagnostic in cases:
    root=ROOT/name;root.mkdir()
    for path,source in files.items():
        p=root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(source)
    cmd=[str(MOJO),'build','--Werror','--num-threads','1','-I','.','tools/probe.mojo','-o','probe.bin']
    start=time.monotonic();build=subprocess.run(cmd,cwd=root,capture_output=True,text=True,timeout=60)
    (root/'build.stdout').write_text(build.stdout);(root/'build.stderr').write_text(build.stderr)
    run=subprocess.run([str(root/'probe.bin')],cwd=root,capture_output=True,text=True,timeout=5) if build.returncode==0 else None
    passed=(build.returncode==0 and run.returncode==0 and run.stdout.strip()==expected) if expected else (build.returncode!=0 and diagnostic in build.stderr)
    record={'case':name,'argv':cmd,'source_sha256':{p:hashlib.sha256(s.encode()).hexdigest() for p,s in files.items()},'build_exit':build.returncode,'run_exit':run.returncode if run else None,'stdout':run.stdout if run else None,'expected':expected,'diagnostic':diagnostic,'passed':passed,'elapsed':time.monotonic()-start}
    results.append(record);(ROOT/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(name,passed,flush=True)
assert all(x['passed'] for x in results)
