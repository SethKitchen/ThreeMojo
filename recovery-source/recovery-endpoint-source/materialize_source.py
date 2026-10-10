"""Reconstruct a source-only endpoint snapshot; never invoke native tools.

This is a portable reconstruction of the original materialization recipe,
not a byte-exact recovery of the lost Python script. Git and overlay inputs
are hash-bound. Destination must not exist. No shared worktree is changed.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,default=Path('ThreeMojo-restored'));p.add_argument('--commit',default='a45ec12b3f5a1f28082494a15d9628a05d0971c0');p.add_argument('--destination',type=Path,required=True);p.add_argument('--cleanup',type=Path,default=Path('recovery-pr711-assembly/assessment-original/original-cleanup'));a=p.parse_args()
R=Path(__file__).resolve().parent;out=a.destination;out.mkdir(parents=True,exist_ok=False)
sha=lambda b:hashlib.sha256(b).hexdigest()
paths=subprocess.check_output(['git','-C',str(a.repo),'ls-tree','-r','--name-only',a.commit],text=True).splitlines()
paths=[n for n in paths if n.endswith('.mojo') and not n.startswith(('tests/','examples/','tools/','coverage/'))]
paths+=['tools/fixtures/carla_sum2_fp_state.c','tools/native_test_support.py','tools/run_suite.py','tools/coverage_toolchain_identity.py','tools/test_environment.py']
paths += ['coverage/'+n+'.mojo' for n in ('__init__','build_cli','instrument','mcdc','report','report_cli','runtime','scanner')]
base={}
for n in paths:
 b=subprocess.check_output(['git','-C',str(a.repo),'show',a.commit+':'+n]);dest=out/n;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b);base[n]=sha(b)
expected={'curve_bounds':'a5f662df6bc146010b065341143c75223151289dc0cc633590d96b0a199ab8f5','lane_value_bounds':'9028d65fdcb680ec5363f7fc974d8d46532b0f50397d7a348fc16e33821f4121','junction_bounds':'d8b7a6de8e495ab16f0cbe9688459eb544ac9ef6c8ec0c44c952ed5b4743a615','lane_refinement':'370dee032a5e126e727c46d0ceb7103359f1ad7fba8151e341b594df0c7d0e30'}
overlays={}
for name,h in expected.items():
 n='extensions/carla/'+name+'.mojo';origin=(R/'endpoint-current'/n) if name=='lane_refinement' else a.cleanup/n;b=origin.read_bytes();assert sha(b)==h,(n,sha(b));(out/n).write_bytes(b);overlays[n]={'source':str(origin),'sha256':h}
for source in (R/'maintained/tests').glob('*.mojo'):
 n='tests/'+source.name;b=source.read_bytes();dest=out/n;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b);overlays[n]={'source':str(source),'sha256':sha(b),'status':'reconstructed from retained text; new native qualification required'}
manifest={'commit':a.commit,'base':base,'overlays':overlays,'final':{str(x.relative_to(out)):sha(x.read_bytes()) for x in out.rglob('*') if x.is_file()},'native_execution':False,'scope':'Source-only endpoint snapshot; excludes later center changes and does not replace the integrator final candidate.'}
(out/'SOURCE-RECOVERY-SEAL.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(str(out))
