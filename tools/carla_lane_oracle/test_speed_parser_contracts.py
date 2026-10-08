# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact parser edge keeps actual grammar and correctness tests source-bound."""
from pathlib import Path
import unittest
from unittest.mock import patch
import speed_parser_contracts as parser

ROOT = Path(__file__).resolve().parents[2]


class SpeedParserSuccessorTests(unittest.TestCase):
    def test_exact_parser_edge_and_correctness_tests(self):
        record = parser.verify(ROOT)
        self.assertNotEqual(record['before_sha256'], record['after_sha256'])
        self.assertEqual(record['path'], 'extensions/carla/speed_limits.mojo')
        self.assertEqual(len(record['correctness_tests']), 2)

    def test_grammar_admission_bound_and_exponent_order_mutations_revoke(self):
        path = ROOT/parser.MODULE
        original = path.read_text();read = Path.read_text
        cases = [('if not _speed_decimal_syntax(number):', 'if False:'),
                 ('if byte >= 48 and byte <= 57:', 'if byte >= 48:'),
                 ('if byte >= 49:', 'if byte >= 48:'),
                 ('if byte == 101 or byte == 69:', 'if byte == 69:'),
                 ('mantissa_digits > 0', 'mantissa_digits >= 0')]
        for before, after in cases:
            with self.subTest(before=before):
                self.assertIn(before, original)
                changed=original.replace(before,after,1)
                with patch.object(Path,'read_text',lambda p,*a,**k:changed if p==path else read(p,*a,**k)):
                    with self.assertRaisesRegex(ValueError, 'actual grammar'):
                        parser.verify(ROOT)

    def test_each_bound_correctness_test_and_record_mutation_revoke(self):
        read=Path.read_bytes
        for name in (*parser.TESTS, parser.MIGRATION):
            target=ROOT/name;changed=read(target)+b' '
            with self.subTest(name=name),patch.object(Path,'read_bytes',lambda p,*a,**k:changed if p==target else read(p,*a,**k)):
                with self.assertRaises(ValueError):parser.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
