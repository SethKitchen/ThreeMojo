from pathlib import Path
import re
import unittest
import selection_finiteness_contracts as c
ROOT=Path(__file__).resolve().parents[2]
class SelectionContracts(unittest.TestCase):
    def setUp(self):
        self.modules={p:c._producer_text(ROOT,p) for p in c.EXPECTED};self.interval=(ROOT/'extensions/carla/curve_interval.mojo').read_text();self.trig=(ROOT/'extensions/carla/curve_trig.mojo').read_text()
    def test_current_producer(self):self.assertEqual(c.verify(ROOT)['status'],'PASS')
    def test_benign_comments(self):self.assertEqual(c.verify_text({p:t+'\n# comment\n' for p,t in self.modules.items()},self.interval+'\n# comment\n',self.trig+'\n# comment\n')['status'],'PASS')
    def test_producer_error_and_guard_mutations(self):
        for p in self.modules:
            for old,new in [('d.error < 0.0','False'),('phase.magnitude() > _PHASE_LIMIT','False'),('floor(selection.low) != 0.0','False'),('floor(selection.high) != 0.0','False'),('var selection =','theta.error = -1.0\n    var selection =')]:
                with self.subTest(module=p,change=old):
                    self.assertIn(old,self.modules[p]);mods=self.modules.copy();mods[p]=mods[p].replace(old,new)
                    with self.assertRaises(ValueError):c.verify_text(mods,self.interval,self.trig)
    def test_order_and_error_dependency_mutations(self):
        for old,new in [('return first.hull(first)','return one'),('var inherited = _next_up(self.error + other.error)','var inherited = -1.0')]:
            with self.subTest(change=old):
                self.assertIn(old,self.interval)
                with self.assertRaises(ValueError):c.verify_text(self.modules,self.interval.replace(old,new),self.trig)
    def test_constant_decoys_and_out_of_bound_words(self):
        for name in ['_INV_HALF_PI','_PHASE_LIMIT']:
            d=re.search(r'comptime '+name+r' = Float64\([^\n]+\)',self.trig).group(0)
            for replacement in ['"""'+d+'"""',d+' if False else Float64(0.0)',d+' + Float64(0.0)',d.replace('Float64(', 'Float64(1e308 + ')]:
                with self.subTest(name=name,mutation=replacement):
                    with self.assertRaises(ValueError):c.verify_text(self.modules,self.interval,self.trig.replace(d,replacement))
    def test_valid_bounded_constant_change(self):
        self.assertEqual(c.verify_text(self.modules,self.interval,self.trig.replace('0.6366197723675814','0.625'))['status'],'PASS')

class SelectionLegacyProjection(unittest.TestCase):
    def test_exact_complete_predecessors_are_restored(self):
        import json
        record=json.loads((ROOT/'tools/carla_lane_oracle/selection-finiteness-contract.json').read_text())
        for path,item in record['modules'].items():
            self.assertEqual(c.source_contracts.token_sha256(c.predecessor_text(ROOT,path)),item['before_token_sha256'])

    def test_actual_mutation_is_rejected_before_projection(self):
        from unittest.mock import patch
        original=Path.read_text
        for path in c.EXPECTED:
            target=ROOT/path
            changed=target.read_text().replace('d.error < 0.0','False')
            def read(p,*a,**k):return changed if p==target else original(p,*a,**k)
            with self.subTest(path=path),patch.object(Path,'read_text',read):
                with self.assertRaises(ValueError):c.predecessor_text(ROOT,path)

    def test_legacy_record_cannot_be_refreshed_without_review(self):
        from unittest.mock import patch
        target=ROOT/'tools/carla_lane_oracle/selection-finiteness-contract.json'
        original=Path.read_bytes;changed=target.read_bytes()+b' '
        def read(p,*a,**k):return changed if p==target else original(p,*a,**k)
        with patch.object(Path,'read_bytes',read):
            with self.assertRaises(ValueError):c.predecessor_text(ROOT,next(iter(c.EXPECTED)))

if __name__=='__main__':unittest.main()
