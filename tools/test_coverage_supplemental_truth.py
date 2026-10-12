# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Keep supplemental truth controls independent of selection admission."""
import ast
import inspect
import unittest
import check_coverage_grouping as grouping


class SupplementalTruthTests(unittest.TestCase):
    def test_repeated_probe_has_native_baseline_and_post_use_lifetimes(self):
        for probe in (False, True):
            source = grouping.repeated_truth_source(probe)
            target = 'observed' if probe else 'kept'
            first = f'    print("FIRST", {target}.__bool__())\n'
            second = f'    print("SECOND", {target}.__bool__())\n'
            retained = '    print("COUNT", count, kept.count[])\n'
            self.assertEqual(source.count(first), 1)
            self.assertEqual(source.count(second), 1)
            self.assertEqual(source.count(retained), 1)
            self.assertLess(source.index(first), source.index(second))
            self.assertLess(source.index(second), source.index(retained))
            self.assertIn('@inline(.never)\n    def __bool__', source)
            if probe:
                self.assertIn('comptime assert _borrowed(reflect[type_of(observed)].name())', source)
                self.assertLess(source.index('    _ = observed^\n'), source.index(retained))
                self.assertIn('var observed = leaf(kept, values, "repeat:1.0", 0)', source)
            else:
                self.assertNotIn('coverage.runtime', source)
                self.assertNotIn('observed', source)

    def test_isolated_generic_preserves_the_exact_original_function(self):
        source, widths, line, signature = grouping.two_parameter_generic_source()
        def body(text):
            return (signature + text.split(signature, 1)[1].split('\n\ndef ', 1)[0]).rstrip()
        self.assertEqual(body(source), body(grouping.TRUTH_TWO_PARAMETER_CONTROLS))
        header = 'if A.make(0, state) or B.make(1, state) and A.make(2, state):'
        self.assertEqual(widths, {header: 3})
        self.assertEqual(source.splitlines()[line - 1].strip(), header)
        self.assertIn('    _ = cell^\n', source)
        self.assertIn('run_pair[Probe, Probe]("Probe", mask, changing)', source)
        self.assertIn('run_pair[Other, Other]("Other", mask, changing)', source)
        checker = ast.parse(inspect.getsource(grouping.check_two_parameter_generic_truth)).body[0]
        tree = ast.literal_eval(next(node.value for node in checker.body
                                    if isinstance(node, ast.Assign)
                                    and any(isinstance(target, ast.Name) and target.id == 'tree'
                                            for target in node.targets)))
        cases = 0
        for changing in (False, True):
            for mask in range(16):
                for _ in ('Probe', 'Other'):
                    model = grouping.GenericTruthModel(tree, mask, -1, changing, line)
                    log, _, vector = model.run()
                    first, second, third = (bool(mask & (1 << index)) for index in range(3))
                    self.assertEqual(log.endswith('|T'), first or (second and third))
                    self.assertEqual([model.counts[index] for index in range(3)],
                                     [1, int(not first), int(not first and second)])
                    self.assertIsNotNone(vector)
                    cases += 1
        self.assertEqual(cases, 64)


if __name__ == '__main__':
    unittest.main()
