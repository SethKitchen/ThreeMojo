# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Independent exact-rational and generic-interval checks of Sum2 endpoints."""
import ast
import copy
from fractions import Fraction
import hashlib
import importlib.util
import math
from pathlib import Path
import struct
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parent.parent
REFERENCE = ROOT / 'tests/_spiral_sum2_reference.mojo'
PRODUCTION = ROOT / 'extensions/carla/curve_sum2.mojo'
spec = importlib.util.spec_from_file_location('sum2_reference_source_reader',
    ROOT / 'tools/carla_lane_oracle/check_sampled_values.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


def value(word):
    return struct.unpack('>d', struct.pack('>Q', word))[0]


def word(number):
    return struct.unpack('>Q', struct.pack('>d', number))[0]


class Bitcast:
    def __getitem__(self, dtype):
        if dtype == 'uint64':
            return word
        if dtype == 'float64':
            return value
        raise ValueError('unexpected reference bitcast')


class Infinity:
    def __getitem__(self, dtype):
        if dtype != 'float64':
            raise ValueError('unexpected infinity dtype')
        return lambda: math.inf


class Endpoints:
    """Four-endpoint model restricted to guarded nonnegative Sum2 arithmetic."""
    def __init__(self, low, high):
        self.low, self.high = low, high

    @staticmethod
    def point(number):
        return Endpoints(number, number)

    @staticmethod
    def rounded(low, high):
        return Endpoints(math.nextafter(low, -math.inf),
                         math.nextafter(high, math.inf))

    def is_point(self, number):
        return self.low == number and self.high == number

    def __neg__(self):
        return Endpoints(-self.high, -self.low)

    def __add__(self, other):
        if self.is_point(0.0) and other.is_point(0.0):
            return Endpoints(-0.0, 0.0)
        if self.is_point(0.0):
            return other
        if other.is_point(0.0):
            return self
        return self.rounded(self.low + other.low, self.high + other.high)

    def __sub__(self, other):
        return self + -other

    def __mul__(self, other):
        if self.is_point(1.0):
            return other
        if other.is_point(1.0):
            return self
        if self.is_point(0.0) or other.is_point(0.0):
            return Endpoints(-0.0, 0.0)
        terms = [a * b for a in (self.low, self.high)
                 for b in (other.low, other.high)]
        return self.rounded(min(terms), max(terms))

    def __truediv__(self, other):
        if other.low <= 0 <= other.high:
            return Endpoints(-math.inf, math.inf)
        if other.is_point(1.0):
            return self
        if self.is_point(0.0):
            return Endpoints(-0.0, 0.0)
        terms = [a / b for a in (self.low, self.high)
                 for b in (other.low, other.high)]
        return self.rounded(min(terms), max(terms))


def functions():
    source = reader.syntax_tree(REFERENCE.read_text())
    names = ('_sum2_reference_successor', '_sum2_reference_add_upper',
             '_sum2_reference_error')
    definitions = [copy.deepcopy(reader.unique_function(source, name)) for name in names]
    for node in definitions:
        for call in [item for item in ast.walk(node) if isinstance(item, ast.Call)]:
            if isinstance(call.func, ast.Name) and call.func.id in (*names, 'UInt64', 'Float64'):
                continue
            if (isinstance(call.func, ast.Subscript)
                    and isinstance(call.func.value, ast.Name)
                    and call.func.value.id == 'bitcast'):
                continue
            raise ValueError('unapproved dependency in independent Sum2 reference')
    # Interpret only the checked arithmetic leaf. The live volatile probe is
    # not Python code and is never silently replaced with an always-true test.
    text = PRODUCTION.read_text()
    production = copy.deepcopy(reader.unique_function(
        reader.syntax_tree(reader.function(text, '_sum2_error_checked')),
        '_sum2_error_checked'))
    wrapper = copy.deepcopy(reader.unique_function(
        reader.syntax_tree(reader.function(text, '_sum2_error')), '_sum2_error'))
    allowed_wrapper = reader.syntax_tree('''
def _sum2_error(magnitude: Float64, inherited: Float64, count: Int) -> Float64:
    if not _sum2_supported_environment():
        return inf[DType.float64]()
    return _sum2_error_checked(magnitude, inherited, count)
''')
    if reader.dump(wrapper) != reader.dump(reader.unique_function(allowed_wrapper, '_sum2_error')):
        raise ValueError('Sum2 environment wrapper control flow changed')
    for call in [item for item in ast.walk(production) if isinstance(item, ast.Call)]:
        if isinstance(call.func, ast.Name) and call.func.id in ('Float64', 'isfinite'):
            continue
        if (isinstance(call.func, ast.Attribute) and isinstance(call.func.value, ast.Name)
                and call.func.value.id == '_Interval' and call.func.attr == 'point'):
            continue
        if (isinstance(call.func, ast.Subscript) and isinstance(call.func.value, ast.Name)
                and call.func.value.id == 'inf'):
            continue
        raise ValueError('unapproved dependency in production Sum2 error contract')
    namespace = {'__builtins__': {}, 'Float64': float, 'UInt64': int, 'Int': int,
                 'DType': SimpleNamespace(uint64='uint64', float64='float64'),
                 'bitcast': Bitcast(), '_Interval': Endpoints,
                 'inf': Infinity(), 'isfinite': math.isfinite}
    module = ast.fix_missing_locations(ast.Module(body=definitions + [production, wrapper], type_ignores=[]))
    exec(compile(module, 'restricted-sum2-error-functions', 'exec'), namespace)
    return namespace['_sum2_reference_error'], namespace['_sum2_error_checked']


class SpiralSum2ReferenceTests(unittest.TestCase):
    def test_frozen_full_and_half_references_remain_immutable(self):
        expected = {'_spiral_full_jet_reference.mojo':
                    'a076ca24b4f9f940b0e5e20213ed3a2a3fd370f92d0f1bc043f36f9ae5a7edd8',
                    '_spiral_half_error_reference.mojo':
                    '76b70a95dace9f5a74da9aedfcbc765a5deb060af3d708e638ef10c10a09ece5'}
        for name, digest in expected.items():
            self.assertEqual(hashlib.sha256((ROOT / 'tests' / name).read_bytes()).hexdigest(), digest)

    def test_monotone_upper_matches_generic_four_endpoint_contract(self):
        reference, actual = functions()
        magnitudes = [0.0, -0.0, value(1), value(2), value(0x000FFFFFFFFFFFFF),
                      value(0x0010000000000000), 2.0**-400, 1.0,
                      math.nextafter(1.0, math.inf), 2.0, 2.0**400, 2.0**900]
        inherited = [0.0, -0.0, value(1), 2.0**-100, 1e-14, 1.0, 2.0**1000]
        counts = [1, 2, 3, 7, 10, 100, 320, 65536, 1073741824]
        cases = 0
        for count in counts:
            for magnitude in magnitudes:
                for error in inherited:
                    self.assertEqual(word(reference(magnitude, error, count)),
                                     word(actual(magnitude, error, count)),
                                     (count, word(magnitude), word(error)))
                    cases += 1
        self.assertEqual(cases, 756)

    def test_every_upper_encloses_the_exact_rational_bound(self):
        reference, _ = functions()
        u = Fraction(1, 2**53)
        cases = 0
        for exponent in range(-1074, 901, 17):
            magnitude = math.ldexp(1.0, exponent)
            for count in (1, 2, 3, 10, 320, 1073741824):
                for error in (0.0, value(1), 2.0**-53, 1.0):
                    result = reference(magnitude, error, count)
                    gamma = Fraction(count - 1) * u / (1 - Fraction(count - 1) * u)
                    exact = Fraction(error)
                    if count != 1:
                        exact += (u + gamma * gamma) * Fraction(magnitude)
                    self.assertGreaterEqual(Fraction(result), exact)
                    cases += 1
        self.assertEqual(cases, 2808)

    def test_guards_and_exact_boundary_words(self):
        reference, actual = functions()
        bad = [(-1.0, 0.0, 2), (math.inf, 0.0, 2), (-math.inf, 0.0, 2),
               (math.nan, 0.0, 2), (math.nextafter(2.0**900, math.inf), 0.0, 2),
               (1.0, -1.0, 2), (1.0, math.inf, 2), (1.0, math.nan, 2),
               (1.0, 0.0, 0), (1.0, 0.0, -1), (1.0, 0.0, 1073741825)]
        for args in bad:
            self.assertEqual(word(reference(*args)), 0x7FF0000000000000)
            self.assertEqual(word(actual(*args)), 0x7FF0000000000000)
        for args in ((0.0, 3.0, 2), (-0.0, 3.0, 2), (1.0, 3.0, 1)):
            self.assertEqual(reference(*args), 3.0)
        self.assertTrue(math.isfinite(reference(2.0**900, 0.0, 1073741824)))

    def test_live_wrapper_checks_both_explicit_predicate_outcomes(self):
        reference, checked = functions()
        namespace = checked.__globals__
        wrapper = namespace['_sum2_error']
        self.assertNotIn('_sum2_supported_environment', namespace)
        observations = []
        delegated = []
        def arithmetic(*args):
            delegated.append(args)
            return checked(*args)
        namespace['_sum2_error_checked'] = arithmetic
        # These are explicit modeled predicate outcomes. Native tests/assembly
        # separately establish what the real volatile FP-state probe observes.
        for supported in (True, False, True, False):
            def predicate(supported=supported):
                observations.append(supported)
                return supported
            namespace['_sum2_supported_environment'] = predicate
            for args in ((1.0, 0.0, 2), (0.0, 7.0, 1), (1.0, 0.0, 0)):
                before = len(delegated)
                actual = wrapper(*args)
                expected = reference(*args) if supported else math.inf
                self.assertEqual(word(actual), word(expected))
                self.assertEqual(len(delegated) - before, int(supported))
        self.assertEqual(observations, [True]*3 + [False]*3 + [True]*3 + [False]*3)

    def test_upper_accumulation_preserves_signed_zero_contract(self):
        reference, _ = functions()
        add = reference.__globals__['_sum2_reference_add_upper']
        for one in (0.0, -0.0, value(1), 1.0, math.inf):
            for two in (0.0, -0.0, value(1), 1.0, math.inf):
                expected = (Endpoints.point(one) + Endpoints.point(two)).high
                self.assertEqual(word(add(one, two)), word(expected))

    def test_native_reference_has_no_production_sum2_dependency(self):
        tree = reader.syntax_tree(REFERENCE.read_text())
        for node in tree.body:
            if isinstance(node, ast.ImportFrom):
                self.assertNotIn(node.module, {'extensions.carla.curve_sum2',
                    'extensions.carla.curve_bounds', 'extensions.carla.lane_value_bounds',
                    'extensions.carla.spiral_roundoff_proof'})
        names = {node.id for node in ast.walk(tree) if isinstance(node, ast.Name)}
        self.assertTrue(names.isdisjoint({'_sum2_error', '_sum2_update'}))
        error = reader.unique_function(tree, '_sum2_reference_error')
        self.assertFalse(any(isinstance(node, ast.Name) and node.id == '_Interval'
                             for node in ast.walk(error)))
        spiral = reader.unique_function(tree, '_sum2_reference_spiral')
        calls = [node.func.id for node in ast.walk(spiral)
                 if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)]
        self.assertEqual(calls.count('_reference_half'), 5)
        self.assertEqual(calls.count('_sum2_reference_error'), 2)
        self.assertEqual(calls.count('_sum2_reference_add_upper'), 4)


if __name__ == '__main__':
    unittest.main()
