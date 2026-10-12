# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact lexical transport for the #333 current coverage theorem sites.

The pure row checks here grant no admission. The existing operation/capture
mutation suites separately exercise full current-root ownership and receipts.
"""
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch

import coverage_loop_proofs as loops
from carla_lane_oracle import typed_boundary_contracts as typed
from carla_lane_oracle import seed_count_contracts as seed

ROOT = Path(__file__).resolve().parents[1]


def descriptors():
    result = {(module,line): expression for module,line,_,_,expression,_,_,_
              in loops.GUARDED_LOOP_RULES if module.startswith('extensions/carla/')}
    result[loops.REVIEWED_COUNT_MODULE,126] = 'range(count)'
    result['extensions/carla/map',loops.CONSTRUCTION_BOUNDARY_LINE] = 'boundaries'
    return result


class ConditionedLoopRows(unittest.TestCase):
    def setUp(self):
        self.texts = {module:(ROOT/(module+'.mojo')).read_text()
                      for module,_ in descriptors()}

    def test_every_reviewed_site_has_exact_current_owner_and_statement(self):
        for (module,old_line),expression in descriptors().items():
            with self.subTest(module=module,line=old_line):
                text = self.texts[module]
                self.assertTrue(typed.is_current(module+'.mojo',text),
                                'typed source data must be sealed before qualification')
                line = loops._typed_loop_row(module,old_line,expression,text)
                self.assertIsInstance(line,int)
                _,owner,function = loops._TYPED_LOOP_ROWS[module,old_line]
                _,first,last = seed._function_span(text,function,owner)
                self.assertLess(first,line)
                self.assertLessEqual(line,last)
                statements = loops._statements(text)
                matched = [row for row in statements if row[0].start[0] == line]
                self.assertEqual(len(matched),1)
                self.assertEqual(matched[0][0].string,'for')

    def test_unknown_source_owner_and_expression_do_not_get_masks(self):
        module = 'extensions/carla/curve_rounded_arc'
        text = self.texts[module]
        self.assertIsNone(loops._typed_loop_row(module,228,'range(0)',text))
        self.assertIsNone(loops._typed_loop_row(module,999,'range(len(lanes))',text))
        self.assertIsNone(loops._typed_loop_row('extensions/carla/unknown',228,
                                             'range(len(lanes))',text))
        self.assertIsNone(loops._typed_loop_row(module,228,'range(len(lanes))',
                                             text+'\n# unreviewed drift\n'))
        self.assertIsNone(loops._typed_loop_row(module,228,'range(len(lanes))',
                         text.replace('road._check_lane(section, lane)', 'pass',1)))

    def test_loop_inventory_not_just_matching_expression(self):
        module = 'extensions/carla/curve_rounded_arc'
        name = module+'.mojo'
        text = self.texts[module]
        old = typed.historical_source(name,text)
        self.assertEqual(hashlib.sha256(old.encode()).hexdigest(),
                         loops._TYPED_LOOP_MAIN_SHA256[name])
        altered = text.replace('        for position in range(len(lanes)):',
            '        for ignored in range(0):\n            pass\n'
            '        for position in range(len(lanes)):',1)
        self.assertNotEqual(altered,text)
        # Isolate the extra structural obligation from the stronger endpoint
        # seal. Even pretending a changed digest was repinned cannot make a
        # newly added loop inherit the old theorem's source coordinate.
        with patch.object(typed,'is_current',return_value=True), patch.object(
                typed,'historical_source',return_value=old):
            self.assertIsNone(loops._typed_loop_row(module,228,'range(len(lanes))',altered))

    def test_same_expression_in_different_owner_is_not_a_correspondence(self):
        module = 'extensions/carla/curve_rounded_arc'
        text = self.texts[module]
        old = typed.historical_source(module+'.mojo',text)
        moved = text.replace('def _rounded_arc_context(', 'def unrelated_context(',1)
        with patch.object(typed,'is_current',return_value=True), patch.object(
                typed,'historical_source',return_value=old):
            with self.assertRaises(ValueError):
                loops._typed_loop_row(module,228,'range(len(lanes))',moved)

    def test_guarded_row_discriminator_cannot_change_its_physical_endpoint(self):
        module = 'extensions/carla/curve_rounded_arc'
        name = module + '.mojo'
        target = ROOT/name
        current = target.read_text()
        historical = typed.historical_source(name, current)
        rule = next(row for row in loops.GUARDED_LOOP_RULES if row[0] == module)
        original = Path.read_text
        def stale(path, *args, **kwargs):
            return historical if path == target else original(path, *args, **kwargs)
        with patch.object(loops, '_reviewed_dependency_hashes',
                          return_value={name: loops.sha256(current.encode())}), patch.object(
                Path, 'read_text', stale), patch.object(
                loops, '_typed_loop_row', side_effect=AssertionError('row theorem reached')):
            self.assertIsNone(loops.guarded_loop_proof(ROOT, rule))

    def test_named_row_discriminator_cannot_change_its_physical_endpoint(self):
        module = 'extensions/carla/spiral_moment_proof'
        name = module + '.mojo'
        target = ROOT/name
        current = target.read_text()
        # Same lexical tokens still denote different physical bytes. The
        # dependent row cannot silently inherit an earlier physical digest.
        stale = current + '\n# changed after dependency observation\n'
        original = Path.read_text
        def changed(path, *args, **kwargs):
            return stale if path == target else original(path, *args, **kwargs)
        with patch.object(loops, '_reviewed_dependency_hashes',
                          return_value={name: loops.sha256(current.encode())}), patch.object(
                Path, 'read_text', changed):
            self.assertEqual(loops._historical_reviewed_nonempty_loops(ROOT, module), {})

    def test_new_origin_guard_is_present_in_current_rounded_provider(self):
        text = self.texts['extensions/carla/curve_rounded_arc']
        declaration = seed.declaration(text,'_rounded_constant')
        self.assertIn('not _rounded_operand(polynomial.s)',declaration)
        self.assertLess(declaration.index('not _rounded_operand(polynomial.s)'),
                        declaration.index('return _RoundedBox.point(polynomial.a)'))

    def test_construction_still_checks_geometry_and_owns_boundary_list(self):
        road = (ROOT/'extensions/carla/road.mojo').read_text()
        transform = seed.declaration(road,'_lane_transform_si',('Road',))
        self.assertIn('if geometry_at < 0:',transform)
        self.assertIn('raise Error("The road has no geometry at that s")',transform)
        boundaries = seed.declaration(road,'_lane_record_boundaries',('Road',))
        self.assertIn('var result = List[Float64]()',boundaries)
        self.assertIn('for record in self.info.geometries:\n        result.append(record.s)',
                      boundaries)
        construction = seed.declaration(self.texts['extensions/carla/map'],
                                        '_build_transform',('Map',))
        self.assertIn('._lane_transform_si(at[1], at[2], waypoint.s)',construction)


class ConditionedCurrentLoopAdmission(unittest.TestCase):
    """Real current roots, owned admissions, and physical mutation controls.

    These are whole-root integration tests and run in the coordinated runtime
    lane. The small ConditionedLoopRows class above makes no root admission.
    """
    @classmethod
    def setUpClass(cls):
        from carla_lane_oracle import _full_audit_test_fixtures as fixtures
        class Lifetime:
            addCleanup = staticmethod(cls.addClassCleanup)
        cls.root = fixtures.copy_current_root(Lifetime(), ROOT)

    def expected(self, module):
        path = module+'.mojo'
        text = (self.root/path).read_text()
        return {loops._typed_loop_row(module,line,expression,text)
                for (name,line),expression in descriptors().items() if name == module}

    def test_current_rows_bind_new_graph_and_preserve_required_true(self):
        from carla_lane_oracle import conditioned_cubic_contracts as conditioned
        modules = ('extensions/carla/map', 'extensions/carla/curve_rounded_arc',
                   'extensions/carla/curve_rounded_line',
                   'extensions/carla/curve_sample_dispatch',
                   'extensions/carla/lane_refinement',
                   'extensions/carla/junction_bounds', 'extensions/carla/opendrive')
        for module in modules:
            with self.subTest(module=module):
                expected = self.expected(module)
                self.assertNotIn(None,expected)
                actual = loops.reviewed_nonempty_loops(self.root,module)
                self.assertEqual(set(actual),expected)
                for row in actual.values():
                    self.assertEqual((row['required'],row['impossible']),('T','F'))
                    bindings = row['dependency_sha256']
                    for path in (*conditioned.SOURCE_PATHS,
                                 *conditioned.BINDING_INPUTS,
                                 conditioned.LEAF,
                                 'tools/carla_lane_oracle/typed_boundary_contracts.py',
                                 'tools/test_conditioned_coverage_loops.py'):
                        self.assertEqual(bindings[path],loops.file_sha256(self.root/path))
                    manifest = f'B {module} {row["line"]}\nL {module} {row["line"]}\n'.encode()
                    envelope = {'sha256':'model','receipt': {
                        'manifest_sha256':loops.sha256(manifest),
                        'proofs':[{'module':module,**row}]}}
                    masked = loops.masked_manifest(manifest,envelope)
                    self.assertIn(f'R {module} {row["line"]} T '.encode(),masked)
                    self.assertIn(f'L {module} {row["line"]}'.encode(),masked)
        tree = loops.reviewed_nonempty_loops(self.root,'extensions/carla/rtree')
        self.assertEqual(set(tree),{666})
        for path in conditioned.SOURCE_PATHS:
            self.assertEqual(tree[666]['dependency_sha256'][path],
                             loops.file_sha256(self.root/path))

    def test_math_source_native_witness_and_leaf_mutations_revoke_then_restore(self):
        from carla_lane_oracle import conditioned_cubic_contracts as conditioned
        paths = (conditioned.SOURCE_PATHS[0],conditioned.SOURCE_PATHS[-1],
                 *conditioned.NATIVE_TESTS,conditioned.MIGRATION,conditioned.LEAF,
                 'tools/carla_lane_oracle/test_conditioned_cubic_contracts.py')
        module = 'extensions/carla/map'
        for name in paths:
            path = self.root/name
            raw = path.read_bytes()
            with self.subTest(path=name):
                path.write_bytes(raw+b'\n# unreviewed current numerical premise\n')
                try:
                    self.assertEqual(loops.reviewed_nonempty_loops(self.root,module),{})
                finally:
                    path.write_bytes(raw)
        self.assertEqual(set(loops.reviewed_nonempty_loops(self.root,module)),
                         self.expected(module))

    def test_historical_scalar_cannot_mix_with_current_certificates(self):
        name = 'extensions/carla/polynomial.mojo'
        path = self.root/name
        raw = path.read_bytes()
        path.write_text(typed.historical_source(name,raw.decode()))
        try:
            self.assertEqual(loops.reviewed_nonempty_loops(
                self.root,'extensions/carla/map'),{})
        finally:
            path.write_bytes(raw)
        self.assertEqual(set(loops.reviewed_nonempty_loops(
            self.root,'extensions/carla/map')),self.expected('extensions/carla/map'))

    def test_new_constructor_caller_and_compiled_provider_shadow_refuse(self):
        additions = {
            'tests/unreviewed_constructor_caller.mojo':
                b'def call(map):\n    map._add_segment(start, end)\n',
            'extensions/carla/curve_interval.mojopkg': b'unreviewed compiled provider',
        }
        for name,raw in additions.items():
            path = self.root/name
            self.assertFalse(path.exists())
            path.write_bytes(raw)
            try:
                with self.subTest(path=name):
                    self.assertEqual(loops.reviewed_nonempty_loops(
                        self.root,'extensions/carla/map'),{})
            finally:
                path.unlink()
        self.assertEqual(set(loops.reviewed_nonempty_loops(
            self.root,'extensions/carla/map')),self.expected('extensions/carla/map'))


if __name__ == '__main__':
    unittest.main()
