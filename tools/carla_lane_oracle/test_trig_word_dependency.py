# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep the complete dependency graph while accepting identical stored words."""
from pathlib import Path
import unittest
import reviewed_cleanup_contracts as cleanup

ROOT = Path(__file__).resolve().parents[2]

class TrigWordDependencyTests(unittest.TestCase):
    def test_original_fingerprint_and_equivalent_words(self):
        text = (ROOT/cleanup.TRIG_PATH).read_text()
        self.assertEqual(cleanup.source.token_sha256(text), cleanup.TRIG_TOKEN_SHA256)
        self.assertEqual(cleanup.trig_word_sha256(text), cleanup.TRIG_WORD_SHA256)
        for changed in (text + '\n# comment\n',
                        text.replace('    -0.5,', '    -0.5000000000000,'),
                        text.replace('Float64(1048576.0)', 'Float64(1048576)')):
            cleanup.verify_dependency(cleanup.TRIG_PATH, changed, cleanup.TRIG_TOKEN_SHA256)

    def test_changed_words_graph_and_declarations_fail(self):
        text = (ROOT/cleanup.TRIG_PATH).read_text()
        cases = (
            ('    -0.5,', '    -0.5000000000000001,'),
            ('Float64(1048576.0)', 'Float64(1048577.0)'),
            ('Float64(1048576.0)', 'Float64(1048576.0) + 1.0'),
            ('Float64(1048576.0)', 'Float64(1048576.0 if True else 2.0)'),
            ('comptime _PHASE_LIMIT =', 'comptime _UNBOUND_LIMIT ='),
            ('from std.memory import bitcast', 'from other.memory import bitcast'),
            ('def _curve_sincos(', 'def _changed_sincos('),
            ('    -0.5,', '    -0.5 + 0.0,'),
            ('    -0.5,', '    -0.5, -0.5,'),
            ('    -0.5,', '    0.5,'),
        )
        for before, after in cases:
            self.assertIn(before, text)
            with self.subTest(mutation=after), self.assertRaises(ValueError):
                cleanup.verify_dependency(cleanup.TRIG_PATH, text.replace(before, after, 1),
                                          cleanup.TRIG_TOKEN_SHA256)
        for changed in (text + '\ncomptime _PHASE_LIMIT = Float64(1048576.0)\n',
                        text.replace('comptime _PHASE_LIMIT = Float64(1048576.0)',
                                     'if True:\n    comptime _PHASE_LIMIT = Float64(1048576.0)')):
            with self.assertRaises(ValueError):
                cleanup.verify_dependency(cleanup.TRIG_PATH, changed, cleanup.TRIG_TOKEN_SHA256)

    def test_fallback_cannot_change_other_dependency_or_predecessor(self):
        text = (ROOT/cleanup.TRIG_PATH).read_text().replace('    -0.5,', '    -0.5000000000000,')
        with self.assertRaises(ValueError):
            cleanup.verify_dependency('extensions/carla/road_info.mojo', text, cleanup.TRIG_TOKEN_SHA256)
        with self.assertRaises(ValueError):
            cleanup.verify_dependency(cleanup.TRIG_PATH, text, '0'*64)

if __name__ == '__main__':
    unittest.main()
