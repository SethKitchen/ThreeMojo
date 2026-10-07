# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent exact-rational checks for the original sampled blend graph.

The proof is algebraic for every rate in the interval. These controls exercise
all permitted product/sum contraction patterns without using production code.
"""
from fractions import Fraction as F
import math,random,sys,unittest

MIN=F(float.fromhex('0x1p-400'));MAX=F(float.fromhex('0x1p400'))

def rounding(m):
    if m<0 or m>MAX*MAX*4:return None
    if m==0:return F(0)
    rounded=float(m)
    if F(rounded)<m:rounded=math.nextafter(rounded,math.inf)
    # Exact-rational half-spacing oracle. Production uses an outward bound.
    return F(math.ulp(rounded))/2

def bound(low,high,error,a,b):
    low,high,error,a,b=map(F,(low,high,error,a,b))
    if low>high or error<0:return None
    endpoints=[low-error,high+error,a,b]
    if any(x and not MIN<=abs(x)<=MAX for x in endpoints):return None
    mr=max(abs(low-error),abs(high+error))
    mc0=max(abs(1-low+error),abs(1-high-error))
    ec=rounding(mc0);mc=mc0+ec
    ep=rounding(abs(a)*mr);eq=rounding(abs(b)*mc)
    ez=rounding(abs(a)*mr+abs(b)*mc+ep+eq)
    return abs(a-b)*error+abs(b)*ec+ep+eq+ez

def graphs(rate,a,b):
    complement=float(1-F(rate))
    p=float(F(rate)*F(a));q=float(F(complement)*F(b))
    return [float(F(p)+F(q)),float(F(rate)*F(a)+F(q)),
            float(F(complement)*F(b)+F(p))]

class CoupledBlendProofTests(unittest.TestCase):
    def check(self,rates,a,b,error):
        low=min(F(x) for x in rates)-error;high=max(F(x) for x in rates)+error
        limit=bound(low,high,error,a,b)
        self.assertIsNotNone(limit)
        for rate in rates:
            for sign in (-1,0,1):
                ideal=F(rate)+sign*error
                exact=ideal*F(a)+(1-ideal)*F(b)
                for result in graphs(rate,a,b):
                    self.assertLessEqual(abs(F(result)-exact),limit,
                                         (rate,a,b,error,result,limit))

    def test_equal_constants_retain_complement_and_rounding_errors(self):
        self.check([.1,.3,.5,.9],9.,9.,F(1,10**12))
        self.assertGreater(bound(.3,.3,F(0),9.,9.),0)

    def test_signs_and_extrapolation(self):
        for a,b in [(8.7,9.),(-8.7,-9.),(8.7,-9.),(-8.7,9.),(0.,9.),(9.,0.)]:
            self.check([-3.,-.01,.2,.5,.9,1.1,3.],a,b,F(1,10**14))

    def test_shared_error_cancels_algebraically(self):
        error=F(1,10**12)
        coupled=bound(.3,.3,error,8.7,9.)
        old_inherited=(F(8.7)+F(9.))*error
        self.assertLess(coupled,old_inherited/50)

    def test_binade_edges_and_adjacent_floats(self):
        for x in [.5,1.,2.,16.]:
            self.check([math.nextafter(x,-math.inf),x,math.nextafter(x,math.inf)],
                       math.nextafter(32.,-math.inf),32.,F(1,2**52))

    def test_deterministic_broad_finite_graphs(self):
        rng=random.Random(594)
        for _ in range(500):
            r=math.ldexp(rng.uniform(-2,2),rng.randrange(-10,10))
            a=math.ldexp(rng.uniform(-2,2),rng.randrange(-100,100))
            b=math.ldexp(rng.uniform(-2,2),rng.randrange(-100,100))
            self.check([r],a,b,F(math.ulp(r))*4)

    def test_extreme_domains_fall_back(self):
        for r,a,b in [(5e-324,1.,1.),(1e-300,1.,1.),(.5,1e308,-1e308),
                      (.5,1e-300,1.),(1e200,1.,1.)]:
            self.assertIsNone(bound(r,r,F(0),a,b))
        self.assertIsNone(bound(2,1,0,1,1))
        self.assertIsNone(bound(0,1,-1,1,1))




class StoredArithmeticExactControls(unittest.TestCase):
    """Independent premises and algebra, not an interpreter of production.

    Python float is used only as an IEEE round-to-nearest binary64 operation;
    Fraction evaluates the exact before/after expressions and identities.
    Production outward bounds and caller provenance require separate native
    tests. In particular these controls cannot qualify arbitrary new calls.
    """
    def test_supported_half_is_exact_for_normal_boundary_words(self):
        values = set()
        for exponent in range(-400, 401, 13):
            value = math.ldexp(1.0, exponent)
            values.update((value, math.nextafter(value, math.inf),
                           math.nextafter(value, -math.inf)))
        values.update((float(MIN), float(MAX), 0.0))
        for value in values:
            if value and not MIN <= F(value) <= MAX:
                continue
            for sign in (-1, 1):
                actual = value * sign
                self.assertEqual(F(actual * 0.5), F(actual) / 2)

    def test_half_error_can_need_gradual_underflow_successor(self):
        # The operand may be safely normal while its inherited error is tiny.
        # A floor-to-zero error is unsound; outward scaling must enclose eta/2.
        eta = math.ulp(0.0)
        exact = F(eta) / 2
        rounded = eta * 0.5
        self.assertEqual(rounded, 0.0)
        self.assertLess(F(rounded), exact)
        self.assertGreaterEqual(F(math.nextafter(rounded, math.inf)), exact)

    def test_sterbenz_supported_boundary_subtractions_are_exact(self):
        for exponent in range(-399, 400, 17):
            right = math.ldexp(1.5, exponent)
            for left in (right/2, math.nextafter(right/2, math.inf),
                         math.nextafter(right, -math.inf), right,
                         math.nextafter(right, math.inf),
                         math.nextafter(right*2, -math.inf), right*2):
                self.assertTrue(MIN <= F(left) <= MAX and MIN <= F(right) <= MAX)
                self.assertTrue(F(right)/2 <= F(left) <= 2*F(right))
                self.assertEqual(F(left-right), F(left)-F(right))

    def test_difference_inherited_error_requires_sum(self):
        one, two = F(3, 2), F(1)
        e1, e2 = F(1, 2**52), F(1, 2**53)
        computed = (one+e1) - (two-e2)
        self.assertEqual(abs(computed-(one-two)), e1+e2)
        self.assertGreater(abs(computed-(one-two)), e1-e2)

    def test_coupled_identity_keeps_every_error_and_correct_weight(self):
        rng = random.Random(5942026)
        for _ in range(200):
            r, a, b, er, ec, ep, eq, ez = [F(rng.randrange(-100, 101), 16)
                                          for _ in range(8)]
            rate = r+er
            complement = 1-rate+ec
            first = rate*a+ep
            second = complement*b+eq
            result = first+second+ez
            self.assertEqual(result-(r*a+(1-r)*b),
                             (a-b)*er+b*ec+ep+eq+ez)

    def test_broad_supported_interval_contains_subnormal_actual_rates(self):
        # Endpoint support must not be mistaken for an interior normality proof.
        # A rate interval [-1,1] supports both subnormal and zero operands.
        eta = math.ulp(0.0)
        limit = bound(-1., 1., 0, .5, -.5)
        self.assertIsNotNone(limit)
        for rate in (-eta, 0., eta):
            exact = F(rate)*F(.5)+(1-F(rate))*F(-.5)
            for result in graphs(rate, .5, -.5):
                self.assertLessEqual(abs(F(result)-exact), limit)
        self.assertEqual(float(F(eta)*F(.5)), 0.0)
        self.assertGreater(rounding(F(eta)*F(.5)), 0)

    def test_half_wrong_factor_and_error_reset_are_counterexamples(self):
        self.assertNotEqual(F(8.)/4, F(8.)/2)
        value, error = F(8), F(1, 2**40)
        self.assertEqual(abs((value+error)/2-value/2), error/2)
        self.assertGreater(error/2, 0)


if __name__ == '__main__':
    unittest.main()
