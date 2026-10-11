"""Discover one maintained unittest module without running test bodies."""
from pathlib import Path
import hashlib,json,sys,unittest
path=Path(sys.argv[1]); output=Path(sys.argv[2]); root=Path.cwd(); expected=sys.argv[3]
# Match python -m unittest: the working repository is importable.
sys.path[0] = str(root)
if hashlib.sha256((root/path).read_bytes()).hexdigest()!=expected:raise RuntimeError('Test source identity differs')
loader=unittest.TestLoader(); suite=loader.discover(start_dir=str(path.parent),pattern=path.name)
if loader.errors:raise RuntimeError('\n'.join(loader.errors))
def flatten(s):
 for item in s:
  if isinstance(item,unittest.TestSuite):yield from flatten(item)
  else:yield item
ids=[case.id() for case in flatten(suite)]
if not ids or len(ids)!=len(set(ids)):raise RuntimeError('Empty or duplicate discovery')
if suite.countTestCases()!=len(ids):raise RuntimeError('Discovery count differs')
if hashlib.sha256((root/path).read_bytes()).hexdigest()!=expected:raise RuntimeError('Test source changed')
record={'path':path.as_posix(),'sha256':expected,'optimize':sys.flags.optimize,'test_count':len(ids),'test_ids':ids,'test_bodies_executed':False,'discovery_program_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
with output.open('x') as stream:json.dump(record,stream,indent=2,sort_keys=True);stream.write('\n')
print('DISCOVERY',path,len(ids),'optimize',sys.flags.optimize)
