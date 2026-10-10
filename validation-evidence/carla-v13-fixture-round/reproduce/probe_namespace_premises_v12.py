"""Independent actual-record topology premises; not a full admission qualification."""
from pathlib import Path
import hashlib,json,sys,unittest
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'tools/carla_lane_oracle'))
import test_full_audit_cleanup_contracts as fixture
cleanup=fixture.cleanup;guard=fixture.guard
class NamespacePremises(unittest.TestCase):
 def test_each_actual_namespace_premise(self):
  root=fixture.fixtures.copy_current_root(self,ROOT);record=cleanup.read_record(root)
  paths=set(record['dependency_inventory'])|set(record['inventory'])|set(record['native_dependency_inventory'])
  protected={Path(p).parts[0].casefold() for p in paths}|{'std'}
  self.assertEqual(protected,{'extensions','loaders','math','std','tests','units'})
  self.assertTrue(cleanup.resolver_unshadowed(root,paths))
  checks=[]
  for name,expected in [('owned_negative_namespace/__init__.mojo',True),('owned_negative_namespace/nested_alpha/quiet.mojo',True),('owned_negative_namespace/tools/quiet.mojo',True),('owned_negative_namespace/tests/quiet.mojo',False)]:
   with self.subTest(path=name),fixture.physical_change(root,name,'# café: negative input\r\n'.encode()):
    self.assertIn(name,{p.relative_to(root).as_posix() for p in guard.production_mojo_paths(root)})
    actual=cleanup.resolver_unshadowed(root,paths);self.assertIs(actual,expected);checks.append({'path':name,'expected':expected,'actual':actual})
   self.assertTrue(cleanup.resolver_unshadowed(root,paths))
  print('NAMESPACE-PREMISES '+json.dumps({'scope':'Independent source-census and actual resolver premises only','record_sha256':hashlib.sha256((root/cleanup.MIGRATION).read_bytes()).hexdigest(),'probe_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'protected':sorted(protected),'cases':checks},sort_keys=True),flush=True)
if __name__=='__main__':unittest.main(verbosity=2)
