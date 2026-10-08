# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One named nonempty proof; mutations retain both original outcomes."""
from pathlib import Path
import tempfile
import unittest

import coverage_loop_proofs as loops
import test_coverage_loop_proofs as protocol

ROOT = Path(__file__).resolve().parents[1]
MODULE = loops.REVIEWED_COUNT_MODULE
SOURCE = MODULE + '.mojo'
DEPENDENCY = 'extensions/carla/curve_bounds.mojo'


class ReviewedCountLoopTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='reviewed count proof ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in (SOURCE, DEPENDENCY):
            path = self.root/name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((ROOT/name).read_bytes())

    def test_exact_named_source_has_only_mandatory_true(self):
        proof = loops.reviewed_nonempty_loops(self.root, MODULE)
        self.assertEqual(set(proof), {126})
        self.assertEqual((proof[126]['required'], proof[126]['impossible']), ('T', 'F'))
        self.assertEqual((proof[126]['cardinality'], proof[126]['maximum_cardinality']), (1, 2))
        self.assertEqual(loops.constant_loops((self.root/SOURCE).read_text()), {})
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, 'other/module'), {})

    def test_guard_count_write_mutable_pass_loop_and_shadow_mutations_reject(self):
        path = self.root/SOURCE;original = path.read_text()
        mutations = [
            original.replace('if count < 1 or count > 2:', 'if count < 0 or count > 2:'),
            original.replace('var count = last - first', 'var count = first - last'),
            original.replace('    var one = 0.0', '    count = 0\n    var one = 0.0'),
            original.replace('    var one = 0.0', '    _mutate_count(count)\n    var one = 0.0')
                + '\ndef _mutate_count(mut value: Int):\n    value = 0\n',
            original.replace('for i in range(count):', 'for i in range(count - 1):'),
            original + '\ndef range(value: Int) -> List[Int]:\n    return []\n',
            original + '\nfrom custom import range\n',
            original + '\nfrom custom import *\n',
            original.replace('        return None\n    var extra = 8 * count', '        pass\n    var extra = 8 * count'),
        ]
        for number, changed in enumerate(mutations):
            self.assertNotEqual(changed, original)
            with self.subTest(mutation=number):
                path.write_text(changed)
                self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})
        path.write_text(original)
        dependency = self.root/DEPENDENCY
        dependency.write_text(dependency.read_text().replace(
            'def _sample_index(geometry: RoadGeometry, d: Float64) -> Int:',
            'def _sample_index(geometry: RoadGeometry, d: Float64) -> Float64:'))
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})

    def test_missing_dependency_and_comment_decoys_do_not_authorize(self):
        (self.root/DEPENDENCY).unlink()
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})
        (self.root/SOURCE).write_text('# for i in range(count):\n')
        self.assertEqual(loops.reviewed_nonempty_loops(self.root, MODULE), {})

    def test_generation_changes_only_this_false_outcome(self):
        # Compiler-free producer model from existing protocol tests. This is
        # a receipt/mask negative control, not native generation evidence.
        fixture = protocol.ProofBindingTests('test_sealed_manifest_retains_potential_and_required_totals')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        for name in (SOURCE, DEPENDENCY):
            for base in (fixture.root, fixture.build):
                path = base/name;path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT/name).read_bytes())
        extra = (f'L {MODULE} 126\nB {MODULE} 126\nL {MODULE} 127\n'
                 f'B {MODULE} 98\nC {MODULE} 98 0\nM {MODULE} 98 0\n')
        manifest = fixture.build/'manifest.txt'
        manifest.write_text(manifest.read_text()+extra)
        original = manifest.read_bytes()
        names = ['module.mojo', SOURCE]
        def seal():
            loops.begin_generation(fixture.root, fixture.build, 'Mojo fixture', '-Werror', sources=names)
            protocol.model_generation(fixture.root, fixture.build, names=names)
            return loops.seal(fixture.root, fixture.build, 'Mojo fixture', '-Werror')
        positive = seal()
        named = [p for p in positive['receipt']['proofs'] if p['module'] == MODULE]
        self.assertEqual(len(named), 1)
        masked = loops.masked_manifest(original, positive).decode().splitlines()
        self.assertIn(f'R {MODULE} 126 T reviewed-nonempty-range 1', masked)
        self.assertNotIn(f'B {MODULE} 126', masked)
        for line in extra.splitlines():
            if line != f'B {MODULE} 126':
                self.assertIn(line, masked)
        self.assertEqual(manifest.read_bytes(), original)
        path = fixture.root/SOURCE
        path.write_text(path.read_text().replace('if count < 1 or count > 2:', 'if count < 0 or count > 2:'))
        # The source mutation invalidates the prior receipt without a reseal.
        with self.assertRaises(ValueError):
            loops.verify(fixture.build/'loop-proofs.json', fixture.root, fixture.build, 'Mojo fixture', '-Werror')
        negative = seal()
        self.assertFalse(any(p['module'] == MODULE for p in negative['receipt']['proofs']))
        self.assertIn(f'B {MODULE} 126', loops.masked_manifest(original, negative).decode().splitlines())
        self.assertEqual(negative['receipt']['denominator']['required_total'],
                         positive['receipt']['denominator']['required_total'] + 1)


if __name__ == '__main__':
    unittest.main()
