#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Stdlib-only controls: python3 -B tools/carla_lane_oracle/test_spiral_moments.py."""
import contextlib
from fractions import Fraction as F
import io
import json
import math
import os
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import spiral_moments as m


def sparse_add(left, right):
    out = left.copy()
    for power, coefficient in right.items():
        out[power] = out.get(power, F(0)) + coefficient
    return {power: value for power, value in out.items() if value}


def sparse_multiply(left, right):
    out = {}
    for (d1, beta1), c1 in left.items():
        for (d2, beta2), c2 in right.items():
            power = d1 + d2, beta1 + beta2
            out[power] = out.get(power, F(0)) + c1 * c2
    return {power: value for power, value in out.items() if value}


def constant(value):
    return {(0, 0): F(value)}


def horner(coefficients, variable):
    out = constant(coefficients[-1])
    for value in reversed(coefficients[:-1]):
        out = sparse_add(sparse_multiply(out, variable), constant(value))
    return out


def literal_coefficients(count, constants):
    """Distribute literal GL/trig expressions with symbolic d AND beta.

    No moment routine, prefix sum, endpoint helper, or stored expected table
    enters this route. beta = stored_rate/2 is an exact symbolic parameter.
    """
    step = {(1, 0): F(1, count)}
    beta = {(0, 1): F(1)}
    x, y = {}, {}
    for piece in range(count):
        start = sparse_multiply(step, constant(piece))
        for node, weight in zip(constants['node_sums'], constants['_GL_WEIGHTS']):
            offset = sparse_multiply(sparse_multiply(step, constant(F(1, 2))),
                                     constant(node))
            t = sparse_add(start, offset)
            theta = sparse_multiply(t, sparse_multiply(beta, t))
            square = sparse_multiply(theta, theta)
            cosine = horner(constants['_COS_COEFFICIENTS'], square)
            sine = sparse_multiply(theta, horner(constants['_SIN_COEFFICIENTS'], square))
            factor = sparse_multiply(sparse_multiply(step, constant(F(1, 2))),
                                     constant(weight))
            x = sparse_add(x, sparse_multiply(factor, cosine))
            y = sparse_add(y, sparse_multiply(factor, sine))
    if set(x) != {(4*j + 1, 2*j) for j in range(11)}:
        raise AssertionError('unexpected cosine polynomial support')
    if set(y) != {(4*j + 3, 2*j + 1) for j in range(11)}:
        raise AssertionError('unexpected sine polynomial support')
    return ([x[4*j + 1, 2*j] for j in range(11)],
            [y[4*j + 3, 2*j + 1] for j in range(11)])


class RoundingTests(unittest.TestCase):
    def test_stored_words_round_trip(self):
        for word in [0, 1, (1 << 52)-1, 1 << 52, 0x3FEFFFFFFFFFFFFF,
                     0x3FF0000000000000, 0x3FF0000000000001, m.MAX_FINITE]:
            for sign in (0, m.SIGN):
                signed = word | sign
                value = m.fraction_of_word(signed)
                expected = (m.SIGN, 0) if not value else (signed, signed)
                self.assertEqual(m.bracket(value), expected)

    def test_halfway_rounding_is_even(self):
        for low in [0, 1, (1 << 52)-1, 1 << 52, 0x3FEFFFFFFFFFFFFF,
                    0x3FF0000000000000, 0x3FF0000000000001]:
            mid = (m.fraction_of_word(low) + m.fraction_of_word(low+1))/2
            even = low if low % 2 == 0 else low+1
            self.assertEqual(m.nearest_even(mid), even)
            self.assertEqual(m.nearest_even(-mid), even | m.SIGN)

    def test_decimal_sign_and_exact_rounding(self):
        self.assertEqual(m.decimal_word('-0.0'), m.SIGN)
        self.assertEqual(m.decimal_word('0.0'), 0)
        self.assertEqual(m.decimal_word('0.1'), 0x3FB999999999999A)
        self.assertEqual(m.decimal_word('-0.1'), 0xBFB999999999999A)

    def test_subnormal_underflow_brackets(self):
        tiny = F(1, 1 << 1076)
        self.assertEqual(m.bracket(tiny), (0, 1))
        self.assertEqual(m.bracket(-tiny), (m.SIGN | 1, m.SIGN))

    def test_bad_and_nonfinite_words_rejected(self):
        for word in [-1, 1 << 64, m.INFINITY, m.INFINITY + 1, m.SIGN | m.INFINITY]:
            with self.subTest(word=word), self.assertRaises(m.CheckError):
                m.fraction_of_word(word)
        with self.assertRaises(m.CheckError):
            m.bracket(m.fraction_of_word(m.MAX_FINITE) * 2)

    def test_enclosing_but_wide_endpoint_rejected(self):
        with self.assertRaises(m.CheckError):
            m.verify_bracket(F(1), 0x3FEFFFFFFFFFFFFF, 0x3FF0000000000001)


class TableTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.constants, cls.pins = m.verify_inputs(m.ROOT)
        cls.rows = m.derive_coefficients(cls.constants)
        cls.source = m.generate_source(cls.rows)
        cls.original = (m.ROOT/m.DATA).read_bytes()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)/'repo'
        paths = {m.PINS, m.DATA}
        paths.update(Path(record['path']) for group in ('arrays', 'scalars', 'blocks')
                     for record in self.pins[group].values())
        for path in paths:
            destination = self.root/path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(m.ROOT/path, destination)

    def change(self, path, before, after):
        target = self.root/path
        content = target.read_text()
        self.assertIn(before, content)
        target.write_text(content.replace(before, after, 1))

    def run_main(self, arguments):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return m.main(['--repo-root', str(self.root)] + arguments)

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes()
                for p in self.root.rglob('*') if p.is_file()}

    def test_all_endpoints_and_canonical_bytes(self):
        self.assertEqual(len(m.verify_table(self.original, self.rows)), 2816)
        for row in self.rows:
            for side in ('cosine', 'sine'):
                for coefficient in row[side]:
                    exact = F(coefficient['exact'])
                    low, high = map(lambda w: int(w, 16), coefficient['words'])
                    m.verify_bracket(exact, low, high)
                    # Independent host conversion/nextafter cross-check.
                    nearest = float(exact)
                    lo = math.nextafter(nearest, -math.inf) if F(nearest)>exact else nearest
                    hi = math.nextafter(nearest, math.inf) if F(nearest)<exact else nearest
                    words = [struct.unpack('>Q', struct.pack('>d', value))[0] for value in (lo,hi)]
                    self.assertEqual(words, [low, high])
        payload = b''.join(struct.pack('>Q', w) for w in m.words_from_rows(self.rows))
        self.assertEqual(m.digest(payload), '72f5e5d09a6f4091e1a537aa89bf80493a427576b5ff86619830721edbc5f446')

    def test_literal_bivariate_graph_independent(self):
        for count in range(1, 65):
            with self.subTest(count=count):
                cosine, sine = literal_coefficients(count, self.constants)
                row = self.rows[count-1]
                self.assertEqual(cosine, [F(c['exact']) for c in row['cosine']])
                self.assertEqual(sine, [F(c['exact']) for c in row['sine']])

    def test_canonical_source_matches_retained_formatter_output(self):
        self.assertEqual(m.digest(self.source),
                         '63b07b8aa1567ad3e1c8b09a71e5619073e5255b4dc6f733d4ef6bf6b7088c8c')

    def test_paired_endpoint_layout_is_noncanonical(self):
        paired = self.source.replace(b'),\n    UInt64(', b'), UInt64(', 1)
        self.assertNotEqual(paired, self.source)
        self.assertEqual(m.parse_table(paired), m.parse_table(self.source))
        with self.assertRaisesRegex(m.CheckError, 'not canonical'):
            m.verify_table(paired, self.rows)

    def test_zeroth_moment_is_not_one(self):
        expected = F(1) + F(3, 1 << 55)
        self.assertNotEqual(expected, 1)
        for row in self.rows:
            self.assertEqual(F(row['cosine'][0]['exact']), expected)
            self.assertEqual(row['cosine'][0]['words'], ['0x3FF0000000000000', '0x3FF0000000000001'])

    def test_one_plus_node_is_rounded_first(self):
        nodes = self.constants['_GL_NODES']
        sums = self.constants['node_sums']
        self.assertTrue(any(F(1)+node != total for node,total in zip(nodes,sums)))
        for node,total in zip(nodes,sums):
            self.assertEqual(total, m.fraction_of_word(m.nearest_even(F(1)+node)))
            self.assertEqual(total, F(1.0 + float(node)))

    def test_corrupted_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'endpoint differs'):
            m.verify_table(self.source.replace(b'0x3FF0000000000000', b'0x3FF0000000000001',1), self.rows)

    def test_missing_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'missing or extra'):
            m.verify_table(self.source.replace(b'UInt64(0x3FF0000000000000),', b'',1), self.rows)

    def test_extra_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'missing or extra'):
            m.verify_table(self.source.replace(b'\n]\n', b'\nUInt64(0x0000000000000000),\n]\n'), self.rows)

    def test_wrong_shape_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'declaration shape'):
            m.verify_table(self.source.replace(b'Array[UInt64, 2816]',b'Array[UInt64, 2815]'), self.rows)

    def test_malformed_word_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'malformed coefficient'):
            m.verify_table(self.source.replace(b'0x3FF0000000000000',b'0x3FF000000000000',1), self.rows)

    def test_same_words_noncanonical_format_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'not canonical'):
            m.verify_table(self.source + b'# extra comment\n', self.rows)

    def test_executable_trailer_rejected(self):
        with self.assertRaisesRegex(m.CheckError, 'malformed table declaration'):
            m.verify_table(self.source + b'comptime unexpected = 1\n', self.rows)

    def test_changed_weight_rejected(self):
        self.change('extensions/carla/geometry.mojo', '0.2369268850561891,', '0.2369268850561892,')
        with self.assertRaisesRegex(m.CheckError, 'constant words changed'):
            m.verify_inputs(self.root)

    def test_signed_zero_constant_change_rejected(self):
        self.change('extensions/carla/geometry.mojo', '    0.0,\n    0.5384693101056831', '    -0.0,\n    0.5384693101056831')
        with self.assertRaisesRegex(m.CheckError, 'constant words changed'):
            m.verify_inputs(self.root)

    def test_same_stored_constant_spelling_allowed(self):
        self.change('extensions/carla/geometry.mojo', '0.2369268850561891,', '0.23692688505618910000,')
        m.verify_inputs(self.root)

    def test_changed_phase_scalar_rejected(self):
        self.change('extensions/carla/curve_trig.mojo', '_PHASE_LIMIT = Float64(1048576.0)', '_PHASE_LIMIT = Float64(1048577.0)')
        with self.assertRaisesRegex(m.CheckError, 'scalar word changed'):
            m.verify_inputs(self.root)

    def test_changed_scalar_phase_graph_rejected(self):
        self.change('extensions/carla/geometry.mojo', 'start + step * 0.5 * (1.0 + nodes[i])', 'start + step * 0.25 * (1.0 + nodes[i])')
        with self.assertRaisesRegex(m.CheckError, 'operation graph changed'):
            m.verify_inputs(self.root)

    def test_changed_ideal_graph_rejected(self):
        self.change('extensions/carla/curve_bounds.mojo', 'Expression.constant(1.0 + nodes[i])', 'Expression.constant(nodes[i])')
        with self.assertRaisesRegex(m.CheckError, 'operation graph changed'):
            m.verify_inputs(self.root)

    def test_unrelated_module_comment_allowed(self):
        target = self.root/'extensions/carla/geometry.mojo'
        target.write_text('# Unrelated documentation.\n' + target.read_text())
        m.verify_inputs(self.root)

    def test_removed_graph_pin_rejected(self):
        pins = json.loads((self.root/m.PINS).read_text())
        del pins['blocks']['scalar_spiral']
        (self.root/m.PINS).write_text(json.dumps(pins))
        with self.assertRaisesRegex(m.CheckError, 'pin set'):
            m.verify_inputs(self.root)

    def test_missing_table_is_cli_failure(self):
        (self.root/m.DATA).unlink()
        self.assertEqual(self.run_main([]), 1)

    def test_default_and_check_never_write(self):
        before = self.snapshot()
        output = Path(self.temp.name)/'should-not-exist'
        with patch.dict(os.environ, {'CARLA_LANE_ORACLE_OUTPUT':str(output)}):
            self.assertEqual(self.run_main([]), 0)
            self.assertEqual(self.run_main(['--check']), 0)
        self.assertFalse(output.exists())
        self.assertEqual(self.snapshot(), before)

    def test_check_cannot_request_report(self):
        with self.assertRaises(SystemExit) as raised:
            self.run_main(['--check', '--report'])
        self.assertEqual(raised.exception.code, 2)

    def test_generate_explicit_outputs_using_existing_env(self):
        output = Path(self.temp.name)/'generated'
        (self.root/m.DATA).unlink()
        before = self.snapshot()
        with patch.dict(os.environ, {'CARLA_LANE_ORACLE_OUTPUT':str(output)}):
            self.assertEqual(self.run_main(['--generate']), 0)
        self.assertEqual((output/m.DATA.name).read_bytes(), self.source)
        self.assertEqual(len((output/'spiral_moment_words.be64').read_bytes()), 22528)
        self.assertEqual(self.snapshot(), before)

    def test_generate_cannot_overwrite_source(self):
        before = self.snapshot()
        self.assertEqual(self.run_main(['--generate', '--output', str(self.root/m.DATA.parent)]), 1)
        self.assertEqual(self.snapshot(), before)

    def test_report_is_explicit_and_bounded(self):
        output = Path(self.temp.name)/'report'
        self.assertEqual(self.run_main(['--report','--output',str(output)]), 0)
        self.assertEqual([p.name for p in output.iterdir()], ['spiral-moment-report.json'])


if __name__ == '__main__':
    unittest.main()
