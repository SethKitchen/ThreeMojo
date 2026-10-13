# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent exact controls for the conditioned cubic's changed graph.

These checks never execute Mojo and do not stand in for native qualification.
The interval/error model uses exact fractions, independently of production's
outward binary64 operations. Every legal Horner FMA choice is exercised.
"""
from dataclasses import dataclass
from fractions import Fraction as F
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

if __package__:
    from . import conditioned_cubic_contracts as cubic
else:
    import conditioned_cubic_contracts as cubic

ROOT = Path(__file__).resolve().parents[2]
ETA = F(1, 2**1074)


def power(exponent):
    return F(2**exponent) if exponent >= 0 else F(1, 2**-exponent)


def floor_log2(value):
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    return exponent - int(value < power(exponent))


def rho(magnitude):
    # Half a normal binade spacing. Eta covers subnormal rounding. The native
    # _roundoff adds further outward slack to these independent lower bounds.
    if magnitude < power(-1021):
        return ETA
    return power(floor_log2(magnitude) - 53)


@dataclass(frozen=True)
class Interval:
    low: F
    high: F

    @staticmethod
    def point(value):
        return Interval(F(value), F(value))

    @property
    def magnitude(self):
        return max(abs(self.low), abs(self.high))

    def __add__(self, other):
        return Interval(self.low + other.low, self.high + other.high)

    def __neg__(self):
        return Interval(-self.high, -self.low)

    def __sub__(self, other):
        return self + -other

    def __mul__(self, other):
        values = (self.low * other.low, self.low * other.high,
                  self.high * other.low, self.high * other.high)
        return Interval(min(values), max(values))

    def contains(self, value):
        return self.low <= value <= self.high


@dataclass(frozen=True)
class Jet:
    value: Interval
    first: Interval
    second: Interval
    error: F

    @staticmethod
    def constant(value):
        return Jet(Interval.point(value), Interval.point(0), Interval.point(0), F(0))

    @staticmethod
    def variable(low, high):
        return Jet(Interval(F(low), F(high)), Interval.point(1), Interval.point(0), F(0))

    def __neg__(self):
        return Jet(-self.value, -self.first, -self.second, self.error)

    def __sub__(self, other):
        return self + -other

    def __add__(self, other):
        ideal = self.value + other.value
        inherited = self.error + other.error
        error = inherited + rho(ideal.magnitude + inherited)
        # Exact zero additions preserve the other stored value. This matches
        # the mathematical shortcut, without using native source as an oracle.
        if self.value == Interval.point(0) and self.error == 0:
            error = other.error
        elif other.value == Interval.point(0) and other.error == 0:
            error = self.error
        return Jet(ideal, self.first + other.first, self.second + other.second, error)

    def __mul__(self, other):
        ideal = self.value * other.value
        inherited = (self.value.magnitude * other.error
                     + other.value.magnitude * self.error + self.error * other.error)
        error = inherited + rho(ideal.magnitude + inherited)
        if ((self.value == Interval.point(0) and self.error == 0)
                or (other.value == Interval.point(0) and other.error == 0)):
            error = F(0)
        elif self.value == Interval.point(1) and self.error == 0:
            error = other.error
        elif other.value == Interval.point(1) and other.error == 0:
            error = self.error
        first = self.first * other.value + self.value * other.first
        second = (self.second * other.value
                  + Interval.point(2) * self.first * other.first
                  + self.value * other.second)
        return Jet(ideal, first, second, error)

    def contains_scalar(self, value):
        return self.value.low - self.error <= F(value) <= self.value.high + self.error


def polynomial(coefficients, station, argument):
    a, b, c, d = map(Jet.constant, coefficients)
    local = argument - Jet.constant(station)
    return a + local * (b + local * (c + local * d))


def ideal(coefficients, station, x):
    a, b, c, d = map(F, coefficients)
    local = F(x) - F(station)
    return a + local * (b + local * (c + local * d))


def rounded(value):
    try:
        return float(value)
    except OverflowError:
        return -math.inf if value < 0 else math.inf


def scalar(coefficients, station, x, fused):
    local = rounded(F(x) - F(station))
    result = coefficients[-1]
    for depth, coefficient in enumerate(reversed(coefficients[:-1])):
        product = F(local) * F(result)
        if not (fused & (1 << depth)):
            product = F(rounded(product))
        result = rounded(F(coefficient) + product)
    return result


def source_fixture():
    raw = (ROOT / cubic.MIGRATION).read_bytes()
    if hashlib.sha256(raw).hexdigest() != cubic.MIGRATION_SHA256:
        raise ValueError('conditioned source fixture changed')
    record = json.loads(raw, object_pairs_hook=cubic.source.unique_keys)
    if set(record) != {'schema', 'issue', 'scope', 'sources'} or record['schema'] != 1 or record['issue'] != 333:
        raise ValueError('conditioned source fixture scope changed')
    return record['sources']


class SourceContractTests(unittest.TestCase):
    def setUp(self):
        self.after = source_fixture()
        self.before = {path: cubic.predecessor_source(path, text)
                       for path, text in self.after.items()}

    def test_loaded_authority_tables_cannot_be_late_repinned(self):
        cubic.verify_authority()
        names = ('LEAF','MIGRATION','MIGRATION_SHA256','SOURCE_PATHS',
                 'BEFORE_SHA256','AFTER_SHA256','BEFORE_TOKEN_SHA256',
                 'AFTER_TOKEN_SHA256','EDITS','EDITS_SHA256','PROVIDER_INPUTS',
                 'AUDIT_PROVIDER_SHA256','NATIVE_TESTS','GRAPH_SPANS','BINDING_INPUTS')
        for name in names:
            value = getattr(cubic,name)
            changed = (dict(value,unreviewed='late namespace edit')
                       if isinstance(value,dict) else
                       (*value,'unreviewed') if isinstance(value,tuple)
                       else value+'unreviewed')
            with self.subTest(name=name), patch.object(cubic,name,changed):
                with self.assertRaisesRegex(ValueError,'authority namespace'):
                    cubic.verify_authority()
        cubic.verify_authority()

    def test_both_complete_graphs_and_exact_inverses(self):
        self.assertEqual(cubic.verify_sources(self.before), ())
        self.assertEqual(cubic.verify_sources(self.after), cubic.SOURCE_PATHS)
        for path in cubic.SOURCE_PATHS:
            self.assertEqual(cubic.sha(self.before[path]), cubic.BEFORE_SHA256[path])
            self.assertEqual(cubic.sha(self.after[path]), cubic.AFTER_SHA256[path])
        self.assertEqual(set(cubic.edges(cubic.SOURCE_PATHS)), set(cubic.SOURCE_PATHS))

    def test_partial_or_mixed_graphs_are_refused(self):
        for path in cubic.SOURCE_PATHS:
            mixed = dict(self.after)
            mixed[path] = self.before[path]
            with self.assertRaisesRegex(ValueError, 'mixed old/new'):
                cubic.verify_sources(mixed)
            missing = dict(self.after)
            del missing[path]
            with self.assertRaises(ValueError):
                cubic.verify_sources(missing)
        with self.assertRaises(ValueError):
            cubic.edges(cubic.SOURCE_PATHS[:-1])

    def test_each_new_expression_is_a_live_obligation(self):
        for path, spans in cubic.GRAPH_SPANS.items():
            for span in spans:
                changed = self.after[path].replace(span, span.replace(' = ', ' = -', 1)
                    if ' = ' in span else span.replace('local', 'wrong_local', 1), 1)
                if changed == self.after[path]:
                    changed = self.after[path].replace(span, span + span, 1)
                with self.assertRaises(ValueError):
                    cubic.verify_graph(path, changed)
                with self.assertRaises(ValueError):
                    cubic.predecessor_source(path, changed)

    def test_same_tokens_comment_drift_still_refused(self):
        for path in cubic.SOURCE_PATHS:
            changed = self.after[path] + '\n# not the reviewed complete endpoint\n'
            self.assertEqual(cubic.source.token_sha256(changed), cubic.AFTER_TOKEN_SHA256[path])
            with self.assertRaises(ValueError):
                cubic.predecessor_source(path, changed)

    def test_hash_only_repins_cannot_remove_local_subtraction(self):
        path = cubic.SOURCE_PATHS[0]
        changed = self.after[path].replace('var local = x - self.s', 'var local = x + self.s')
        with patch.dict(cubic.AFTER_SHA256, {path: cubic.sha(changed)}), patch.dict(
                cubic.AFTER_TOKEN_SHA256, {path: cubic.source.token_sha256(changed)}):
            with self.assertRaisesRegex(ValueError, 'authority namespace'):
                cubic.predecessor_source(path, changed)
            # Isolate the additional explicit graph obligation from the
            # stronger namespace seal; a hash-only repin still is not enough.
            with patch.object(cubic, 'verify_authority', lambda: None):
                with self.assertRaisesRegex(ValueError, 'current operation'):
                    cubic.predecessor_source(path, changed)

    def test_constant_shortcut_cannot_drop_origin_range_premise(self):
        path = cubic.SOURCE_PATHS[5]
        text = self.after[path]
        changed = text.replace('        not _rounded_operand(polynomial.s)\n'
                               '        or polynomial.b != 0.0',
                               '        polynomial.b != 0.0')
        with patch.dict(cubic.AFTER_SHA256, {path: cubic.sha(changed)}), patch.dict(
                cubic.AFTER_TOKEN_SHA256, {path: cubic.source.token_sha256(changed)}):
            with self.assertRaisesRegex(ValueError, 'authority namespace'):
                cubic.predecessor_source(path, changed)
            # Isolate the additional explicit graph obligation from the
            # stronger namespace seal; a hash-only repin still is not enough.
            with patch.object(cubic, 'verify_authority', lambda: None):
                with self.assertRaisesRegex(ValueError, 'current operation'):
                    cubic.predecessor_source(path, changed)

    def test_inverse_inventory_and_unrelated_changes_are_refused(self):
        path = cubic.SOURCE_PATHS[0]
        with patch.object(cubic, 'EDITS_SHA256', '0' * 64):
            with self.assertRaisesRegex(ValueError, 'authority namespace'):
                cubic.predecessor_source(path, self.after[path])
            with patch.object(cubic, 'verify_authority', lambda: None):
                with self.assertRaisesRegex(ValueError, 'inverse inventory'):
                    cubic.predecessor_source(path, self.after[path])
        with self.assertRaises(ValueError):
            cubic.predecessor_source('extensions/carla/not_owned.mojo', self.after[path])
        with self.assertRaises(ValueError):
            cubic.predecessor_source(path, self.after[path].replace('self.d = d', 'self.d = -d'))

    def test_fail_closed_with_optimized_python(self):
        result = subprocess.run([sys.executable, '-O', '-c',
            'from tools.carla_lane_oracle import conditioned_cubic_contracts as c; '
            'c.verify_sources({})'], cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('incomplete semantic source scope', result.stderr)


class Symbol:
    """Sparse exact multivariate polynomial; no sampled identities."""
    def __init__(self, terms):
        self.terms = {powers: F(value) for powers, value in terms.items() if value}

    @staticmethod
    def constant(value):
        return Symbol({(0,) * 7: value})

    @staticmethod
    def variable(index):
        return Symbol({tuple(int(i == index) for i in range(7)): 1})

    def __add__(self, other):
        if not isinstance(other, Symbol):
            other = Symbol.constant(other)
        values = dict(self.terms)
        for powers, value in other.terms.items():
            values[powers] = values.get(powers, F(0)) + value
        return Symbol(values)

    __radd__ = __add__

    def __neg__(self):
        return Symbol({powers: -value for powers, value in self.terms.items()})

    def __sub__(self, other):
        return self + (-other if isinstance(other, Symbol) else -F(other))

    def __mul__(self, other):
        if not isinstance(other, Symbol):
            other = Symbol.constant(other)
        values = {}
        for a, x in self.terms.items():
            for b, y in other.terms.items():
                powers = tuple(i+j for i,j in zip(a,b))
                values[powers] = values.get(powers, F(0)) + x*y
        return Symbol(values)

    __rmul__ = __mul__

    def __pow__(self, exponent):
        result = Symbol.constant(1)
        for _ in range(exponent):
            result = result * self
        return result

    def derivative(self, index):
        result = {}
        for powers, value in self.terms.items():
            if powers[index]:
                derived = tuple(p-int(i == index) for i,p in enumerate(powers))
                result[derived] = value*powers[index]
        return Symbol(result)


class MathematicalControls(unittest.TestCase):
    def test_exact_symbolic_local_derivative_and_centered_identities(self):
        a,b,c,d,x,s,center = (Symbol.variable(i) for i in range(7))
        local = x-s
        p = a + local*(b + local*(c + local*d))
        first = b + local*(2*c + local*3*d)
        second = 2*c + 6*d*local
        self.assertEqual(p.derivative(4).terms, first.terms)
        self.assertEqual(first.derivative(4).terms, second.terms)
        m = center-s
        delta = x-center
        centered = (a+m*(b+m*(c+m*d))
                    + delta*(b+m*(2*c+m*3*d)
                    + delta*(c+3*m*d+delta*d)))
        self.assertEqual(centered.terms, p.terms)
        # Exact-real re-expansion is algebraically equivalent. Rounding its
        # stored coefficients is exactly why the old numerical graph failed.
        expanded = (a-b*s+c*s*s-d*s*s*s
                    + x*(b-2*c*s+3*d*s*s+x*(c-3*d*s+x*d)))
        self.assertEqual(expanded.terms, p.terms)
        wrong_delta = x-m
        wrong = (a+m*(b+m*(c+m*d))
                 + wrong_delta*(b+m*(2*c+m*3*d)
                 + wrong_delta*(c+3*m*d+wrong_delta*d)))
        self.assertNotEqual(wrong.terms, p.terms)

    def test_centered_interval_contains_same_ideal_and_scalar(self):
        coefficients = (3.5, -.25, .125, -.03125)
        s = 1e6
        low, high = math.nextafter(s, -math.inf), s+2
        center = rounded((F(low)+F(high))/2)
        a,b,c,d = map(Interval.point, coefficients)
        m = Interval.point(center)-Interval.point(s)
        delta = Interval(F(low), F(high))-Interval.point(center)
        value = a + m*(b + m*(c + m*d))
        first = b + m*(Interval.point(2)*c + m*Interval.point(3)*d)
        second = c + Interval.point(3)*m*d
        centered = value + delta*(first + delta*(second + delta*d))
        natural = polynomial(coefficients, s, Jet.variable(low,high))
        low_bound = max(centered.low-natural.error, natural.value.low-natural.error)
        high_bound = min(centered.high+natural.error, natural.value.high+natural.error)
        for x in (low, center, high):
            self.assertTrue(centered.contains(ideal(coefficients,s,x)))
            for fused in range(8):
                result = F(scalar(coefficients,s,x,fused))
                self.assertLessEqual(low_bound,result)
                self.assertGreaterEqual(high_bound,result)

    def test_original_counterexample_is_a_semantic_change(self):
        a, b, c, d, s = 3.5, 0.0, 0.0, 1.0, 1e6
        expanded = (a - b*s + c*s*s - d*s*s*s,
                    b - 2*c*s + 3*d*s*s, c - 3*d*s, d)
        legacy = expanded[0] + s * (expanded[1] + s * (expanded[2] + s * expanded[3]))
        self.assertEqual(legacy, 0.0)
        for fused in range(8):
            self.assertEqual(scalar((a, b, c, d), s, s, fused), 3.5)
        self.assertEqual(ideal((a, b, c, d), s, s), F(7, 2))

    def test_all_horner_contractions_and_exact_derivatives(self):
        cases = [
            ((3.5, 0.0, 0.0, 1.0), 1e6, 1e6, 1e6),
            ((3.5, -.25, .03125, -.0078125), 1e6,
             math.nextafter(1e6, -math.inf), math.nextafter(1e6, math.inf)),
            ((-2., 3., -4., 5.), -1e6, -1e6-3., -1e6+4.),
            ((float(ETA), -float(ETA), 0., float(ETA)), 0., -2., 2.),
            ((1e-300, 1e-250, -1e-200, 1e-150), 1e100, 1e100, math.nextafter(1e100, math.inf)),
            ((1e300, -1e250, 1e200, -1e150), 1e20, 1e20, math.nextafter(1e20, math.inf)),
            ((0., 1., 0., 0.), -float(ETA), float(ETA), float(ETA)),
            ((1., 0., 0., 0.), 2.0**900, 2.0**900, math.nextafter(2.0**900, math.inf)),
        ]
        for coefficients, s, low, high in cases:
            enclosure = polynomial(coefficients, s, Jet.variable(low, high))
            for x in (low, rounded((F(low)+F(high))/2), high):
                local = F(x)-F(s)
                a,b,c,d = map(F, coefficients)
                self.assertTrue(enclosure.value.contains(ideal(coefficients, s, x)))
                self.assertTrue(enclosure.first.contains(b+2*c*local+3*d*local*local))
                self.assertTrue(enclosure.second.contains(2*c+6*d*local))
                for fused in range(8):
                    value = scalar(coefficients, s, x, fused)
                    self.assertTrue(math.isfinite(value))
                    self.assertTrue(enclosure.contains_scalar(value), (coefficients,s,x,fused))

    def test_constant_and_zero_width_intervals(self):
        for constant in (0., -0., 3.5, float(ETA), 1e300):
            bound = polynomial((constant, 0., 0., 0.), 1e6, Jet.variable(1e6, 1e6+100))
            self.assertEqual(bound.value, Interval.point(constant))
            self.assertEqual(bound.first, Interval.point(0))
            self.assertEqual(bound.second, Interval.point(0))
            self.assertEqual(bound.error, 0)
        point = polynomial((3.5, 2., 3., 4.), 1e6, Jet.variable(1e6, 1e6))
        self.assertEqual(point.value, Interval.point(3.5))
        self.assertEqual(point.first, Interval.point(2))
        self.assertEqual(point.second, Interval.point(6))

    def test_local_origin_does_not_mean_lane_section_origin(self):
        # Distinct local width/elevation origins on one world station.
        x = F(1_000_010)
        for origin in (F(1_000_000), F(1_000_008), F(1_000_010)):
            coefficients = (F(7,2), F(1,4), F(-1,8), F(1,16))
            local = x-origin
            self.assertEqual(ideal(coefficients, origin, x),
                             coefficients[0]+coefficients[1]*local+
                             coefficients[2]*local**2+coefficients[3]*local**3)

    def test_finite_oracle_fixture_profiles_use_current_local_model(self):
        town = ET.parse(ROOT/'assets/carla/town.xodr').getroot()
        road = town.find("road[@id='5']")
        self.assertIsNotNone(road)
        elevations = road.findall('elevationProfile/elevation')
        offsets = road.findall('lanes/laneOffset')
        def record(node):
            return tuple(float(node.get(k)) for k in ('a','b','c','d')), float(node.get('s'))
        first_elevation, origin = record(elevations[0])
        self.assertEqual(origin, 0.)
        self.assertEqual(first_elevation, (1.,.02,0.,0.))
        first_offset, origin = record(offsets[0])
        self.assertEqual((first_offset,origin), ((.5,0.,0.,0.),0.))
        section = road.find('lanes/laneSection')
        self.assertEqual(float(section.get('s')),0.)
        for lane,value in ((-1,3.5),(-2,1.5)):
            width = section.find("right/lane[@id='%s']/width" % lane)
            self.assertEqual(tuple(float(width.get(k)) for k in ('sOffset','a','b','c','d')),
                             (0.,value,0.,0.,0.))
        # These are exactly the profiles of the shoulder oracle's first
        # smooth piece and its constant-offset roundoff analysis.
        for x in (0.,4.5865310585259165,10.,math.nextafter(20.,-math.inf)):
            self.assertEqual(ideal(first_elevation,0,x),1+F(.02)*F(x))
            for fused in range(8):
                self.assertEqual(scalar(first_offset,0,x,fused),.5)
        # Poses at s=40 and s=50 already express the original local records.
        second_elevation, origin = record(elevations[1])
        self.assertEqual((second_elevation,origin),((1.6,0.,.001,0.),30.))
        second_offset, offset_origin = record(offsets[1])
        self.assertEqual((second_offset,offset_origin),((.5,.01,0.,0.),20.))
        for x in (40.,50.):
            self.assertEqual(ideal(second_elevation,origin,x), F(1.6)+F(.001)*(F(x)-30)**2)
            self.assertEqual(2*F(.001)*(F(x)-30), F(.002)*(F(x)-30))
            self.assertEqual(ideal(second_offset,offset_origin,x),F(.5)+F(.01)*(F(x)-20))

    def test_later_shoulder_record_bound_uses_local_offset_inequality(self):
        # Binary64 .01 is slightly larger than exact decimal .01; use a
        # deliberately outward rational .88 upper bound, not decimal .87.
        low, high = F(.5), F(.5)+F(.01)*37
        self.assertGreaterEqual(low,F(1,2))
        self.assertLess(high,F(22,25))
        h_low, h_high = F(17,4)-high,F(17,4)-low
        self.assertGreater(h_low,0)
        self.assertLessEqual(h_high,F(15,4))
        center_y_lower = F(105)-h_high
        self.assertEqual((center_y_lower-F(-105))**2,F(680625,16))

    def test_translated_fixture_polynomial_origin_stays_zero(self):
        # That fixture moves geometry and section stations to 1e20. It keeps
        # the constant polynomial's own origin zero, including the later
        # quadratic-field mutation used by the nonprogress control.
        base = 1e20
        for c in (0.,1e-40):
            coefficients = (.0002,0.,c,0.)
            for k in range(6):
                x = base+k*16384.
                for fused in range(8):
                    current = scalar(coefficients,0.,x,fused)
                    self.assertEqual(current, scalar(coefficients,-0.,x,fused))
                    local = x-0.
                    legacy = coefficients[0]+local*(coefficients[1]+local*(c+local*0.))
                    self.assertEqual(scalar(coefficients,0.,x,0),legacy)

    def test_record_coefficients_preserve_input_bits(self):
        # The constructor copies each original binary64 field. This includes
        # signed zero and subnormals; evaluation need not preserve zero's sign.
        for value in (-0., 0., float(ETA), -float(ETA), 1e300):
            original = struct.pack('>d', value)
            copied = struct.pack('>d', float(value))
            self.assertEqual(copied, original)

    def test_rounded_constant_supported_domain_excludes_overflow(self):
        bound = power(400)
        self.assertLessEqual(bound+bound, power(401))
        self.assertLess(power(401), F(sys.float_info.max))
        # Origin guarding must reject each of these even for zero b/c/d.
        for origin in (math.inf, -math.inf, math.nan, sys.float_info.max,
                       -sys.float_info.max, math.nextafter(2.0**400,math.inf)):
            supported = (math.isfinite(origin) and
                         (origin == 0 or 2.0**-400 <= abs(origin) <= 2.0**400))
            self.assertFalse(supported)
        for origin in (-2.0**400, 0., 2.0**400):
            for x in (-2.0**400, 0., 2.0**400):
                self.assertTrue(math.isfinite(x-origin))
                for fused in range(8):
                    self.assertEqual(scalar((3.5,0.,0.,0.),origin,x,fused),3.5)

    def test_finite_inputs_can_still_overflow_local_subtraction(self):
        maximum = sys.float_info.max
        self.assertTrue(math.isinf(rounded(F(maximum)-F(-maximum))))
        # No finite enclosure is claimed. The native witness must establish
        # typed-boundary refusal and uncertified/whole interval propagation.


if __name__ == '__main__':
    unittest.main()
