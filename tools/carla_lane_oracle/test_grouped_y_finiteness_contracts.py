from pathlib import Path
import unittest
import grouped_y_finiteness_contracts as c
ROOT=Path(__file__).resolve().parents[2]
G='extensions/carla/spiral_grouped_roundoff_proof.mojo';I='extensions/carla/curve_interval.mojo';T='extensions/carla/curve_trig.mojo';D='extensions/carla/geometry.mojo'
class GroupedYFiniteness(unittest.TestCase):
 def setUp(self):self.modules={p:(ROOT/p).read_text() for p in c.EXPECTED}
 def check(self,cases):
  for module,old,new in cases:
   with self.subTest(premise=old):
    self.assertIn(old,self.modules[module]);changed=dict(self.modules);changed[module]=changed[module].replace(old,new,1)
    with self.assertRaises(ValueError):c.verify_text(changed)
 def test_current(self):self.assertEqual(c.verify_text(self.modules)['status'],'PASS')
 def test_comment_spacing(self):self.assertEqual(c.verify_text({p:(t+'\n# comment\n').replace('copies =','copies  =') for p,t in self.modules.items()})['status'],'PASS')
 def test_admission(self):self.check([(G,a,b) for a,b in [('pieces > 64','pieces > 128'),('pieces < 1','pieces < 0'),('geometry.heading != 0.0','False'),('geometry.curvature_start != 0.0','False'),('or d.value.low > d.value.high',''),('or not isfinite(d.error)',''),('or d.error < 0.0',''),('domain.low <= 0.0','domain.low < 0.0')]])
 def test_phase_selector(self):self.check([(G,'phase.magnitude() > _PHASE_LIMIT','False'),(G,'floor(selection.low) != 0.0','False'),(G,'floor(selection.high) != 0.0','False'),(T,'Float64(0.6366197723675814)','Float64(0.4)'),(T,'Float64(1048576.0)','Float64(1e100)')])
 def test_tables(self):self.check([(D,'-0.9061798459386640','-1.0'),(D,'0.2369268850561891','2.0'),(T,'_SIN_COEFFICIENTS: Array[Float64, 11]','_SIN_COEFFICIENTS: Array[Float64, 12]'),(T,'-0.16666666666666666','-2.0')])
 def test_multiplicity_order_and_call(self):self.check([(G,a,b) for a,b in [('1 if weight == 2 else 2','1 if weight == 2 else 640'),('for group in range(4):','for group in range(400):'),('var copies = (high - low) * multiplicity','var copies = 0'),('if not _grouped_term(x, copies, x_ideal, x_magnitude, x_inherited):','if False:'),('_ = _grouped_term(y, copies, y_ideal, y_magnitude, y_inherited)','_ = True'),('var y = factors[weight] * trig[0]','var y = factors[weight] * trig[1]')]])
 def test_arithmetic_errors_and_zero(self):self.check([(I,a,b) for a,b in [('return self.value + _Interval(-self.error, self.error)','return self.value'),('if other.rounded_value().is_finite():','if True:'),('error = other.error','error = 0.0'),('var inherited = _next_up(self.error + other.error)','var inherited = 0.0'),('var residual = fma(one, two, -value)','var residual = 0.0'),('var residual = fma(-value, two, one)','var residual = 0.0')]])
 def test_writes_origins_debits(self):self.check([(G,a,b) for a,b in [('ideal = ideal + copies * term.value','ideal = term.value'),('magnitude = magnitude + copies * _Interval.point(rounded.magnitude())','magnitude = _Interval.point(0.0)'),('inherited = inherited + copies * _Interval.point(term.error)','inherited = _Interval.point(0.0)'),('if not isfinite(x_error) or not isfinite(y_error):','if False:'),('terms += work','terms += 0')]])
 def test_x_before_y_order(self):
  old="            if not _grouped_term(x, copies, x_ideal, x_magnitude, x_inherited):\n                return None"
  early="            _ = _grouped_term(y, copies, y_ideal, y_magnitude, y_inherited)\n"+old
  self.check([(G,old,early)])
if __name__=='__main__':unittest.main()
