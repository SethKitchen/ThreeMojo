# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""A repeated coverage receipt key fails before the receipt is parsed."""
import json
import tempfile
import unittest
from pathlib import Path

import coverage_loop_proofs as proofs


class ReceiptKeyTests(unittest.TestCase):
    def test_a_repeated_receipt_key_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'receipt.json'
            path.write_text('{"a": 1, "a": 2}', encoding='utf-8')
            with self.assertRaisesRegex(
                    ValueError, 'Duplicate receipt key: a'):
                proofs._load_json(path)
            path.write_text('{"a": 1}', encoding='utf-8')
            self.assertEqual(proofs._load_json(path), {'a': 1})
            path.write_text('{', encoding='utf-8')
            with self.assertRaises(json.JSONDecodeError):
                proofs._load_json(path)


if __name__ == '__main__':
    unittest.main()
