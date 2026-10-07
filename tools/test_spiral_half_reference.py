# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the independent native half-error oracle against exact binary rationals."""
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
SCRIPT = ROOT / 'tools/carla_lane_oracle/check_sampled_values.py'
spec = importlib.util.spec_from_file_location('half_reference_source_reader', SCRIPT)
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
REFERENCE = ROOT / 'tests/_spiral_half_error_reference.mojo'
FROZEN = ROOT / 'tests/_spiral_full_jet_reference.mojo'
FROZEN_SHA256 = 'a076ca24b4f9f940b0e5e20213ed3a2a3fd370f92d0f1bc043f36f9ae5a7edd8'


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


def error_reference():
    # Execute the actual Mojo reference's integer/control-flow AST, not a
    # second hand-transcribed implementation of its word algorithm. Only
    # this small function is compiled; imports and unrelated code never run.
    tree = reader.syntax_tree(REFERENCE.read_text())
    node = copy.deepcopy(reader.unique_function(tree, '_reference_half_error'))
    calls = [call.func for call in ast.walk(node) if isinstance(call, ast.Call)]
    for call in calls:
        if isinstance(call, ast.Name) and call.id == 'UInt64':
            continue
        if (isinstance(call, ast.Subscript) and isinstance(call.value, ast.Name)
                and call.value.id == 'bitcast'):
            continue
        raise ValueError('unexpected executable dependency in half-error reference')
    module = ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[]))
    namespace = {'__builtins__': {}, 'Float64': float, 'UInt64': int,
                 'DType': SimpleNamespace(uint64='uint64', float64='float64'),
                 'bitcast': Bitcast()}
    exec(compile(module, str(REFERENCE), 'exec'), namespace)
    return namespace['_reference_half_error']


class SpiralHalfReferenceTests(unittest.TestCase):
    def test_original_full_jet_oracle_is_frozen(self):
        self.assertEqual(hashlib.sha256(FROZEN.read_bytes()).hexdigest(), FROZEN_SHA256)

    def test_native_word_algorithm_matches_exact_halves_at_every_exponent(self):
        reference = error_reference()
        mantissas = (0, 1, 2, 3, (1 << 51) - 1, 1 << 51,
                     (1 << 52) - 3, (1 << 52) - 2, (1 << 52) - 1)
        cases = 0
        for exponent in range(2047):
            for mantissa in mantissas:
                source_word = (exponent << 52) | mantissa
                source = value(source_word)
                exact = Fraction(source) / 2
                # Python converts a rational independently of Mojo's word
                # shifts. Existing interval zero/identity shortcuts are exact;
                # all other high endpoints are the successor of nearest-even.
                expected = (source / 2 if source in (0.0, 1.0)
                            else math.nextafter(float(exact), math.inf))
                actual = reference(source)
                self.assertEqual(word(actual), word(expected), hex(source_word))
                self.assertGreaterEqual(Fraction(actual), exact, hex(source_word))
                cases += 1
        self.assertEqual(cases, 18423)
        self.assertEqual(word(reference(-0.0)), 0)

    def test_tightened_reference_does_not_call_the_production_helper(self):
        tree = reader.syntax_tree(REFERENCE.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.Name):
                self.assertNotIn(node.id, {'_stored_half', '_stored_blend_error',
                                          '_spiral_expression', '_spiral_jet'})
        function = reader.unique_function(tree, '_half_reference_spiral')
        calls = [node for node in ast.walk(function) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Name) and node.func.id == '_reference_half']
        self.assertEqual(len(calls), 5)

    def test_union_is_exact_endpoint_reconstruction_from_child_bounds(self):
        tree = reader.syntax_tree(REFERENCE.read_text())
        node = reader.unique_function(tree, '_independent_child_hull')
        for item in ast.walk(node):
            if isinstance(item, ast.Attribute):
                self.assertNotEqual(item.attr, 'hull')
            if isinstance(item, ast.Name):
                self.assertNotIn(item.id, {'_union_points', '_full_union_points'})
        returned = [item for item in node.body if isinstance(item, ast.Return)]
        self.assertEqual(len(returned), 1)
        result = returned[0].value
        self.assertIsInstance(result, ast.Call)
        self.assertEqual(result.func.id, '_FullJet')
        expected = ast.parse(
            '_FullJet(_Interval(min(first.low, second.low), '
            'max(first.high, second.high)), _Interval.whole(), '
            '_Interval.whole(), 0.0)', mode='eval').body
        self.assertEqual(reader.dump(result), reader.dump(expected))


if __name__ == '__main__':
    unittest.main()
