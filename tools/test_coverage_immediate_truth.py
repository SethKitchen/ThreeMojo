# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep context-specific identity repair separate from selection admission."""
import unittest
import check_coverage_grouping as grouping

class ImmediateTruthTests(unittest.TestCase):
    def test_all_original_positive_trees_stay_positive(self):
        self.assertEqual(grouping.TRUTH_ACCEPTED, (0, 1, 2, 3, 4, 5, 9, 15, 31, 34, 37, 39, 41))
        self.assertEqual(len(grouping.TRUTH_CASES), 43)
        self.assertEqual(tuple(i for i, tree in enumerate(grouping.TRUTH_CASES) if grouping.truth_supported(tree)), grouping.TRUTH_ACCEPTED)
        self.assertEqual(set(grouping.TRUTH_ACCEPTED) | set(grouping.TRUTH_MIXED_REJECTED), set(range(43)))

    def test_original_identity_positive_sources_are_retained(self):
        self.assertEqual(len(grouping.IDENTITY_POSITIVE_CASES), 6)
        self.assertEqual(len(grouping.TEMPORARY_IDENTITY_POSITIVE_CASES), 3)
        self.assertEqual(len(grouping.TEMPORARY_IDENTITY_TYPES), 3)
        for expression, _, _, vector in grouping.IDENTITY_POSITIVE_CASES:
            self.assertIn(f'    if {expression}:', grouping.identity_source(expression))
            self.assertEqual(len(vector), 2)

    def test_last_use_changes_only_the_post_use_suffix(self):
        suffix = '    print("RETAINED", kept.payload)\n    print("ADDRESS", Int(Pointer(to=kept.payload)) == kept.expected)\n'
        for index in (0, 3):
            expression = grouping.IDENTITY_POSITIVE_CASES[index][0]
            self.assertEqual(grouping.identity_source(expression), grouping.identity_last_use_source(expression) + suffix)

if __name__ == '__main__':
    unittest.main()
