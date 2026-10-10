import pathlib,sys,tempfile,json
archive=pathlib.Path('/tmp/anatomy-702-review.6AM1Xk');sys.path.insert(0,str(archive/'tools'))
import anatomy_validity as av
from test_anatomy_report_binding import _fixture
root=pathlib.Path(__file__).resolve().parent;results=[]
for fixture in sorted(root.glob('*_as.mojo'))+sorted(root.glob('*_control.mojo')):
 with tempfile.TemporaryDirectory() as folder:
  r=pathlib.Path(folder);_fixture(r)
  (r/'pkg/__init__.mojo').write_text('')
  (r/'tools/anatomy_probe.mojo').write_bytes(fixture.read_bytes())
  dependency='pkg/bound.mojo' if fixture.name.startswith('from') else 'helper.mojo'
  before=av.source_digest(r);paths=av.bound_paths(r)
  (r/dependency).write_text('def value() -> Int:\n    return 99\n')
  row={'fixture':fixture.name,'dependency':dependency,'dependency_bound':dependency in paths,'digest_changed':av.source_digest(r)!=before};results.append(row);print(row)
(root/'binding-mutation-results.json').write_text(json.dumps({'commit':'15759631d496469d23227ca64e9641b1290f83b2','results':results},indent=2)+'\n')
