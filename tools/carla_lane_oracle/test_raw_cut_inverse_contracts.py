# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Source mutations for exact stored-subtraction inverse proof premises."""
from pathlib import Path
from unittest.mock import patch
import unittest
import raw_cut_inverse_contracts as contract

ROOT = Path(__file__).resolve().parents[2]


class RawCutInverseContracts(unittest.TestCase):
    def test_exact_successor(self):
        contract.verify(ROOT)

    def test_independent_operation_mutations_reject(self):
        cases = [
            ('curve_sample_dispatch', 'if not _sum2_supported_environment():', 'if False:'),
            ('curve_sample_dispatch', 'or origin < 0.0', 'or False'),
            ('curve_sample_dispatch', 'or local < 0.0', 'or False'),
            ('curve_sample_dispatch', 'or local >= length', 'or local > length'),
            ('curve_sample_dispatch', 'var start = origin + local', 'var start = origin - local'),
            ('curve_sample_dispatch', 'start <= 0.0', 'start < 0.0'),
            ('curve_sample_dispatch', 'station - origin', 'station + origin'),
            ('curve_sample_dispatch', 'length) > local', 'length) >= local'),
            ('curve_sample_dispatch', 'local, start):', 'local, start + 1.0):'),
            ('curve_sample_dispatch', 'var word = bitcast[DType.uint64](start) + UInt64(1)', 'var word = bitcast[DType.uint64](start) + UInt64(2)'),
            ('curve_sample_dispatch', 'word >= UInt64(0x7FF0000000000000)', 'word > UInt64(0x7FF0000000000000)'),
            ('curve_sample_dispatch', 'local, cut):', 'local, start):'),
            ('curve_sample_dispatch', 'word += UInt64(1)', 'word += UInt64(2)'),
            ('curve_sample_dispatch', 'return bitcast[DType.float64](word)', 'return bitcast[DType.float64](word - UInt64(1))'),
            ('curve_sample_dispatch', 'var extra = 8 * count', 'var extra = 2 * count'),
            ('curve_sample_dispatch', 'after_index != threshold_at', 'after_index == threshold_at'),
            ('curve_sum2', 'def _sum2_supported_environment()', 'def _unchecked_environment()'),
        ]
        read = Path.read_text
        for module, before, after in cases:
            path = ROOT/f'extensions/carla/{module}.mojo';original = path.read_text()
            self.assertIn(before, original)
            changed = original.replace(before, after)
            with self.subTest(module=module, before=before), patch.object(
                    Path, 'read_text', lambda p, *a, **k: changed if p == path else read(p, *a, **k)):
                with self.assertRaises(ValueError):
                    contract.verify_premises(ROOT)

    def test_record_refresh_rejected(self):
        target = ROOT/contract.MIGRATION;read = Path.read_bytes;original = read(target)
        with patch.object(Path, 'read_bytes', lambda p, *a, **k:
                          original+b' ' if p == target else read(p, *a, **k)):
            with self.assertRaisesRegex(ValueError, 'unreviewed migration'):
                contract.verify(ROOT)


if __name__ == '__main__':
    unittest.main()
