# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the independent phase fixture and its Float32 neighbor selection."""

from decimal import Decimal, localcontext
import math
import struct
import unittest

import reference_sine_phases as reference


class SinePhaseReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.groups = reference.generate(140)

    def test_generated_block_matches_at_two_precisions(self):
        self.assertEqual(self.groups, reference.generate(200))
        saved = reference.FIXTURE.read_text()
        start = saved.index(reference.BEGIN)
        end = saved.index(reference.END, start) + len(reference.END)
        self.assertEqual(saved[start:end], reference.render(self.groups))

    def test_exact_binary32_decoding_and_ties_to_even(self):
        self.assertEqual(reference.exact_float32(0x3F800000), Decimal(1))
        self.assertEqual(reference.exact_float32(0xC0000000), Decimal(-2))
        with localcontext() as context:
            context.prec = 200
            self.assertEqual(reference.exact_float32(1), Decimal(2) ** -149)
            for lower in (0x3F800000, 0x3F800001):
                midpoint = (reference.exact_float32(lower)
                            + reference.exact_float32(lower + 1)) / 2
                expected = lower + (lower & 1)
                self.assertEqual(reference.rounded_bits(midpoint), expected)
                self.assertEqual(reference.rounded_bits(-midpoint),
                                 expected | 0x80000000)

    def test_negative_decoding_is_exact_under_default_and_low_precision(self):
        # Decimal unary minus rounds under the caller's context. Decode
        # through Float64 only for this control: it holds every Float32
        # exactly, and Decimal.from_float preserves its exact value.
        for precision in (28, 6):
            with localcontext() as context:
                context.prec = precision
                for bits in (0x80000000, 0x80000001, 0x807FFFFF,
                             0x80800001, 0xBEAAAAAB, 0xFF7FFFFF):
                    with self.subTest(precision=precision, bits=hex(bits)):
                        value = struct.unpack("!f", struct.pack("!I", bits))[0]
                        expected = Decimal.from_float(value)
                        actual = reference.exact_float32(bits)
                        self.assertEqual(actual, expected)
                        self.assertTrue(actual.is_signed())

    def test_neighbors_bracket_targets_and_increment_boundaries(self):
        self.assertEqual(len(self.groups), 72)
        self.assertEqual({group[0] for group in self.groups},
                         set(reference.EXPONENTS))
        with localcontext() as context:
            context.prec = 156
            half_pi = reference.machin_pi(140) / 2
            for exponent, multiple, midpoint, rows in self.groups:
                with self.subTest(exponent=exponent, multiple=multiple,
                                  midpoint=midpoint):
                    target = (Decimal(multiple)
                              + (Decimal("0.5") if midpoint else 0)) * half_pi
                    self.assertEqual([row[0] for row in rows],
                                     list(range(rows[0][0], rows[0][0] + 4)))
                    self.assertLess(reference.exact_float32(rows[1][0]), target)
                    self.assertGreater(reference.exact_float32(rows[2][0]), target)
                    if midpoint and exponent <= 23:
                        self.assertEqual(rows[1][4], multiple)
                        self.assertEqual(rows[2][4], multiple + 1)

    def test_all_quadrants_and_remainder_signs_in_each_exponent_band(self):
        for exponent in reference.EXPONENTS:
            rows = [row for group in self.groups if group[0] == exponent
                    for row in group[3]]
            self.assertEqual({row[1] for row in rows}, {0, 1, 2, 3})
            self.assertEqual({bool(row[2] & 0x80000000) for row in rows},
                             {False, True})

    def test_independent_taylor_reference_agrees_with_host_libm(self):
        for _, _, _, rows in self.groups:
            for bits, _, _, sine, _ in rows:
                value = struct.unpack("!f", struct.pack("!I", bits))[0]
                expected = struct.unpack("!f", struct.pack("!I", sine))[0]
                self.assertLessEqual(abs(expected - math.sin(value)), 3e-8)


if __name__ == "__main__":
    unittest.main()
