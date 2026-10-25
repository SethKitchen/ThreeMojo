from pathlib import Path
import unittest
import grouped_y_finiteness_contracts as c
ROOT=Path(__file__).resolve().parents[2]


# This module's fixed byte/line/body assertions describe the historical main
# graph. The #333 current graph has separate physical admission/mutation tests.
_CURRENT_SOURCE_ROOT = ROOT


def setUpModule():
    global ROOT
    import _full_audit_test_fixtures as historical_fixtures
    owner = type('HistoricalModuleFixture', (), {
        'addCleanup': staticmethod(unittest.addModuleCleanup)})()
    ROOT = historical_fixtures.copy_historical_boundary_root(owner, _CURRENT_SOURCE_ROOT)
    unittest.addModuleCleanup(globals().__setitem__, 'ROOT', _CURRENT_SOURCE_ROOT)
I='extensions/carla/curve_interval.mojo';T='extensions/carla/curve_trig.mojo';D='extensions/carla/geometry.mojo'
class GroupedYFiniteness(unittest.TestCase):
 def setUp(self):self.modules={p:(ROOT/p).read_text() for p in c.EXPECTED}
 def check(self,cases):
  for module,old,new in cases:
   with self.subTest(premise=old):
    self.assertIn(old,self.modules[module]);changed=dict(self.modules);changed[module]=changed[module].replace(old,new,1)
    with self.assertRaises(ValueError):c.verify_text(changed)
 def test_current(self):self.assertEqual(c.verify_text(self.modules)['status'],'PASS')
 def test_comment_spacing(self):self.assertEqual(c.verify_text({p:(t+'\n# comment\n').replace('copies =','copies  =') for p,t in self.modules.items()})['status'],'PASS')
 def test_phase_selector(self):self.check([(T,'Float64(0.6366197723675814)','Float64(0.4)'),(T,'Float64(1048576.0)','Float64(1e100)')])
 def test_tables(self):self.check([(D,'-0.9061798459386640','-1.0'),(D,'0.2369268850561891','2.0'),(T,'_SIN_COEFFICIENTS: Array[Float64, 11]','_SIN_COEFFICIENTS: Array[Float64, 12]'),(T,'-0.16666666666666666','-2.0')])
 def test_arithmetic_errors_and_zero(self):self.check([(I,a,b) for a,b in [('return self.value + _Interval(-self.error, self.error)','return self.value'),('if other.rounded_value().is_finite():','if True:'),('error = other.error','error = 0.0'),('var inherited = _next_up(self.error + other.error)','var inherited = 0.0'),('var residual = fma(one, two, -value)','var residual = 0.0'),('var residual = fma(-value, two, one)','var residual = 0.0')]])
if __name__=='__main__':unittest.main()
