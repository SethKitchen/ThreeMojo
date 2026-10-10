import os, pathlib, subprocess, json, hashlib, time, shutil
root=pathlib.Path(__file__).resolve().parent
sdk=pathlib.Path('/workspace/scratch/c2bcdb1ca387/restored-toolchain/official-venv/bin/mojo')
env=dict(os.environ)
for key in list(env):
 if key in {'PYTHONPATH','PYTHONHOME','PYTHONUSERBASE','PYTHONOPTIMIZE','MODULAR_HOME','MODULAR_MAX_PACKAGE_ROOT','LD_PRELOAD','LD_LIBRARY_PATH'} or key.startswith(('MODULAR_MOJO_','DYLD_')): env.pop(key)
for key,sub in [('HOME','home'),('MODULAR_CACHE_DIR','modular-cache'),('XDG_CACHE_HOME','xdg-cache'),('XDG_DATA_HOME','xdg-data')]:
 p=root/'runtime'/sub;p.mkdir(parents=True,exist_ok=True);env[key]=str(p)
env['MODULAR_TELEMETRY_ENABLED']='false';env['PYTHONDONTWRITEBYTECODE']='1';env['PATH']=str(sdk.parent)+':'+env.get('PATH','')
(root/'environment.json').write_text(json.dumps({k:env[k] for k in ['HOME','MODULAR_CACHE_DIR','XDG_CACHE_HOME','XDG_DATA_HOME','MODULAR_TELEMETRY_ENABLED','PATH']},indent=2)+'\n')
shutil.copyfile('/workspace/scratch/c2bcdb1ca387/restored-toolchain/receipts/mojo-identity.json',root/'sdk-identity-receipt.json')
results=[]
def call(label,command,timeout):
 start=time.monotonic()
 try:
  p=subprocess.run(command,cwd=root,env=env,capture_output=True,timeout=timeout)
  code=p.returncode;out=p.stdout;err=p.stderr
 except subprocess.TimeoutExpired as e:
  code='timeout';out=e.stdout or b'';err=e.stderr or b''
 (root/(label+'.stdout')).write_bytes(out);(root/(label+'.stderr')).write_bytes(err)
 row={'label':label,'command':command,'timeout_seconds':timeout,'exit_code':code,'elapsed_seconds':time.monotonic()-start};results.append(row)
 (root/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(row,flush=True);return code,out
code,out=call('version',[str(sdk),'--version'],10)
if code!=0 or out.strip()!=b'Mojo 1.1.0 (8189361e)':raise SystemExit('Unexpected toolchain')
(root/'pkg').mkdir(exist_ok=True);(root/'pkg/__init__.mojo').write_text('')
(root/'helper.mojo').write_text('def value() -> Int:\n    return 42\n')
(root/'pkg/bound.mojo').write_text('def value() -> Int:\n    return 42\n')
cases={'plain_control':'import helper as renamed','plain_tab_before_as':'import helper\tas renamed','plain_tab_after_as':'import helper as\trenamed','from_control':'from pkg import bound as renamed','from_tab_before_as':'from pkg import bound\tas renamed','from_tab_after_as':'from pkg import bound as\trenamed'}
for name,statement in cases.items():
 (root/(name+'.mojo')).write_text(statement+'\n\ndef main():\n    print(renamed.value())\n')
 code,_=call(name+'.build',[str(sdk),'build','--Werror','--num-threads','1','-I','.',name+'.mojo','-o',name+'.bin'],60)
 if code==0:call(name+'.run',[str(root/(name+'.bin'))],5)
(root/'source-bytes.json').write_text(json.dumps({str(p.relative_to(root)):{'hex':p.read_bytes().hex(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in root.rglob('*.mojo')},indent=2)+'\n')
