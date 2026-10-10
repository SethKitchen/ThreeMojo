"""Partial diagnostic profile, no admission cache or qualification result."""
import cProfile, hashlib, json, signal, sys, time, types
from pathlib import Path
OUT=Path(sys.argv[1]);root=Path(sys.argv[2]);payload=json.loads(Path(sys.argv[3]).read_text());command=payload['command'];assert hashlib.sha256(command.encode()).hexdigest()==payload['command_sha256'];route=payload['route'];sys.argv=['-c',str(root),route]
# Match the maintained -c lookup spelling; profiler startup still preloads standard-library instrumentation.
sys.path[0]=''
startup_path=list(sys.path);startup_modules=sorted(sys.modules)
class DiagnosticDeadline(BaseException): pass
def alarm(signum,frame):raise DiagnosticDeadline('115-second diagnostic profile window')
old=signal.signal(signal.SIGALRM,alarm);profile=cProfile.Profile();start=time.monotonic();status='not completed';error=None
try:
 signal.setitimer(signal.ITIMER_REAL,115);profile.enable()
 exec(compile(command,'<string>','exec'),{'__name__':'__main__'})
 status='completed'
except DiagnosticDeadline as e:
 status='diagnostic deadline';error=str(e)
except BaseException as e:
 status='error';error=repr(e)
finally:
 profile.disable();signal.setitimer(signal.ITIMER_REAL,0);signal.signal(signal.SIGALRM,old)
 entries=profile.getstats();ids={id(e.code):i for i,e in enumerate(entries)}
 def identity(code):
  if isinstance(code,str):return {'kind':'builtin','name':code,'object_id':id(code)}
  return {'kind':'code','object_id':id(code),'filename':code.co_filename,'line':code.co_firstlineno,'name':code.co_name,'qualname':code.co_qualname,'bytecode_sha256':hashlib.sha256(code.co_code).hexdigest()}
 rows=[]
 for e in entries:
  rows.append({'id':ids[id(e.code)],'code':identity(e.code),'calls':e.callcount,'recursive_calls':e.reccallcount,'total_seconds':e.totaltime,'self_seconds':e.inlinetime,'callees':[{'id':ids.get(id(c.code)),'code':identity(c.code),'calls':c.callcount,'recursive_calls':c.reccallcount,'total_seconds':c.totaltime,'self_seconds':c.inlinetime} for c in (e.calls or [])]})
 bindings=[]
 for name,module in list(sys.modules.items()):
  filename=getattr(module,'__file__',None)
  if not isinstance(filename,str) or not filename.startswith(str(root)):continue
  for symbol,value in list(vars(module).items()):
   seen=set()
   while hasattr(value,'__wrapped__') and id(value) not in seen:
    seen.add(id(value));value=value.__wrapped__
   code=getattr(value,'__code__',None)
   if isinstance(code,types.CodeType):bindings.append({'module':name,'symbol':symbol,'code_id':ids.get(id(code)),'code_object_id':id(code),'filename':filename})
 report={'scope':'Partial diagnostic profile only; exact maintained source command executed under profiling, not a timing-cap pass','status':status,'error':error,'work_cap_seconds':115,'outer_child_cap_seconds':120,'elapsed_seconds':time.monotonic()-start,'command_sha256':payload['command_sha256'],'raw_code_identities_preserved_before_pstats':True,'route':route,'optimize':sys.flags.optimize,'profile_startup_sys_path':startup_path,'profile_startup_modules':startup_modules,'entries':rows,'module_bindings':bindings}
 (OUT/'RAW-PROFILE.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');profile.dump_stats(str(OUT/'profile.pstats'));print(json.dumps({k:v for k,v in report.items() if k not in ('entries','module_bindings')}),flush=True)
raise SystemExit(status!='completed')
