from pathlib import Path
import unittest
import distance_validation_contracts as c
ROOT=Path(__file__).resolve().parents[2]
class DistanceValidationContracts(unittest.TestCase):
    def setUp(self):self.module=(ROOT/c.MODULE).read_text();self.interval=(ROOT/'extensions/carla/curve_interval.mojo').read_text()
    def test_current(self):self.assertEqual(c.verify(ROOT)['status'],'PASS')
    def test_benign_comment_and_spacing(self):self.assertEqual(c.verify_text((self.module+'\n# comment\n').replace('d.error < 0.0','d.error  <  0.0'),self.interval+'\n# comment\n')['status'],'PASS')
    def test_raw_order_and_error_mutations(self):
        for token in ['or captured.d.value.low > captured.d.value.high','or d.value.low > d.value.high','or not isfinite(captured.d.error)','or captured.d.error < 0.0','or not isfinite(d.error)','or d.error < 0.0']:
            with self.subTest(guard=token):
                self.assertIn(token,self.module)
                with self.assertRaises(ValueError):c.verify_text(self.module.replace(token,''),self.interval)
    def test_debit_and_derivative_association_mutations(self):
        for old,new in [('construction_terms += extra','construction_terms += 0'),('proof_units += extra','proof_units += 0'),('or not captured.d.first.is_finite()',''),('or not d.second.is_finite()',''),('record_at != proof.record_at','False')]:
            with self.subTest(change=old):
                self.assertIn(old,self.module)
                with self.assertRaises(ValueError):c.verify_text(self.module.replace(old,new),self.interval)
    def test_rounding_route_mutations(self):
        for old,new in [('var domain = captured.d.rounded_value()','var domain = captured.d.value'),('var domain = d.rounded_value()','var domain = d.value')]:
            with self.assertRaises(ValueError):c.verify_text(self.module.replace(old,new),self.interval)
    def test_widening_order_mutation(self):
        text=self.interval.replace('return self.value + _Interval(-self.error, self.error)','return self.value + _Interval(self.error, -self.error)')
        with self.assertRaises(ValueError):c.verify_text(self.module,text)
if __name__=='__main__':unittest.main()
