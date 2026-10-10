"""One exact maintained consumer child, with unchanged120s bound and fixture."""
import ast, hashlib, importlib, json, subprocess, sys, time
from pathlib import Path
ROOT=Path.cwd(); OUT=Path(sys.argv[1])/'optimized-test-production-inventory-paths'; OUT.mkdir(exist_ok=False)
SELF=Path(__file__).read_bytes(); sha=lambda b:hashlib.sha256(b).hexdigest()
TEST=ROOT/'tools/carla_lane_oracle/test_full_audit_cleanup_contracts.py'
raw=TEST.read_bytes();assert sha(raw)=='8e58c8c8679d93f3a90ee4de0b5c78f88f44f7d9ad7118e421df638d09a03f62'
tree=ast.parse(raw); cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='FullAuditCleanupContracts'); method=next(n for n in cls.body if isinstance(n,ast.FunctionDef) and n.name=='test_consumer_first_import_orders_normal_and_optimized'); command=next(ast.literal_eval(n.value) for n in method.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='command' for t in n.targets));route='test_production_inventory_paths'
# The maintained method uses exactly this subprocess signature and timeout.
runs=[n for n in ast.walk(method) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and isinstance(n.func.value,ast.Name) and n.func.value.id=='subprocess' and n.func.attr=='run'];assert len(runs)==1
assert {k.arg:ast.literal_eval(k.value) for k in runs[0].keywords if k.arg in ('capture_output','text','timeout')}=={'capture_output':True,'text':True,'timeout':120}
sys.path[0]=str(ROOT);sys.path.insert(0,str(ROOT/'tools/carla_lane_oracle'));test=importlib.import_module('test_full_audit_cleanup_contracts');test.FullAuditCleanupContracts.setUpClass();case=test.FullAuditCleanupContracts('test_consumer_first_import_orders_normal_and_optimized');case.setUp()
def snapshot():
 return {str(p.relative_to(case.root)):sha(p.read_bytes()) for p in sorted(case.root.rglob('*')) if p.is_file() and '__pycache__' not in p.parts}
before=snapshot();(OUT/'FIXTURE-SOURCE-SEAL.json').write_text(json.dumps(before,indent=2,sort_keys=True)+'\n');argv=[sys.executable,'-O','-B','-c',command,str(case.root),route];receipt={'scope':'Exact maintained optimized test_production_inventory_paths child; bounded focused control, not a replacement gate','argv':argv,'cwd':str(case.root),'child_cap_seconds':120,'test_source_sha256':sha(raw),'command_sha256':sha(command.encode()),'driver_sha256':sha(SELF),'fixture_source_seal_sha256':sha((OUT/'FIXTURE-SOURCE-SEAL.json').read_bytes())};start=time.monotonic();result=None
try:
 try:
  result=subprocess.run(argv,cwd=case.root,capture_output=True,text=True,timeout=120)
  stdout,stderr=result.stdout,result.stderr;receipt.update(returncode=result.returncode,timed_out=False)
 except subprocess.TimeoutExpired as error:
  stdout,stderr=error.stdout or b'',error.stderr or b'';receipt.update(returncode=None,timed_out=True)
 for name,data in [('stdout',stdout),('stderr',stderr)]:
  p=OUT/('CHILD-'+name+'.log');p.write_bytes(data.encode() if isinstance(data,str) else data);receipt[name+'_sha256']=sha(p.read_bytes())
 receipt['seconds']=time.monotonic()-start;receipt['fixture_unchanged']=snapshot()==before;assert receipt['fixture_unchanged'];assert TEST.read_bytes()==raw;assert Path(__file__).read_bytes()==SELF
 receipt['passed']=not receipt['timed_out'] and receipt['returncode']==0 and 'consumer-first accepted: '+route in (stdout.decode() if isinstance(stdout,bytes) else stdout)
finally:
 case.doCleanups();receipt['fixture_removed']=not case.root.exists();(OUT/'EXACT-CHILD-RESULT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print(json.dumps(receipt),flush=True)
raise SystemExit(not receipt['passed'])
