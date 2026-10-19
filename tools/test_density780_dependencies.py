# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact local density dependency successors, with physical receipt controls."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import coverage_loop_proofs as loops
import test_density760_loops as density760
from carla_lane_oracle import full_audit_cleanup_contracts as audit
from carla_lane_oracle import pr780_source_successor as successor

ROOT = Path(__file__).resolve().parents[1]
DENSITY = loops.DENSITY_SOURCE.removesuffix('.mojo')
ROWS = {131, 167, 178, 245}


class Density780DependencyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='density780-local-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        for name in loops.DENSITY760_INPUTS:
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/name).read_bytes())
        self.current = {name: (self.root/name).read_bytes()
                        for name in loops.DENSITY780_DEPENDENCY_SHA256}
        self.historical = {name: successor.predecessor_bytes(name, raw)
                           for name, raw in self.current.items()}

    def assert_rows(self, rows):
        self.assertEqual(set(rows), ROWS)
        physical = {name: loops.sha256((self.root/name).read_bytes())
                    for name in loops.DENSITY760_INPUTS}
        for line, minimum, maximum, expression, proof_id in loops.DENSITY760_RULES:
            self.assertEqual(rows[line], {
                'line': line, 'kind': 'reviewed-nonempty-range', 'cardinality': 1,
                'minimum_cardinality': minimum, 'maximum_cardinality': maximum,
                'required': 'T', 'impossible': 'F', 'expression': expression,
                'proof_id': proof_id, 'dependency_sha256': physical,
            })
        return physical

    def test_current_local_closure_needs_no_whole_carla_admission(self):
        self.assertFalse((self.root/'extensions/carla/map.mojo').exists())
        calls = []
        def observe(frame, event, value):
            if event == 'call' and frame.f_code is audit.verify.__code__:
                calls.append(True)
        self.assertIsNone(sys.getprofile())
        sys.setprofile(observe)
        try:
            rows = loops.density760_loops(self.root)
        finally:
            sys.setprofile(None)
        physical = self.assert_rows(rows)
        self.assertFalse(calls)
        changed = {name: digest for name, digest in physical.items()
                   if digest != loops.DENSITY760_INPUTS[name]}
        self.assertEqual(changed, loops.DENSITY780_DEPENDENCY_SHA256)
        for name, raw in self.historical.items():
            self.assertEqual(loops.sha256(raw), loops.DENSITY760_INPUTS[name])

    def test_original_closure_and_theorem_rows_remain_exact(self):
        self.assertEqual(len(loops.DENSITY760_INPUTS), 345)
        self.assertEqual(loops.sha256(loops.canonical(loops.DENSITY760_INPUTS)),
            'c04c634cde2aa332034e8402791072fe738bacf71204355bf190bc49d5471e90')
        self.assertEqual(loops.DENSITY760_RULES, (
            (131, 64, 262144, 'range(count)', 'density-validated-positive-cube-count'),
            (167, 1, None, 'range(len(groom))', 'density-partitioned-nonempty-groom'),
            (178, 1, None, 'range(samples)', 'density-checked-representable-positive-samples'),
            (245, 16, 256, 'range(self.resolution * 4)', 'density-query-validated-positive-step-count'),
        ))
        self.assertEqual(set(loops.DENSITY780_DEPENDENCY_SHA256), {
            'core/extent.mojo', 'geometries/surface.mojo', 'loaders/bytes.mojo',
            'math/matrix4.mojo', 'math/square_matrix.mojo', 'math/vector4.mojo',
        })

    def test_historical_local_cohort_keeps_original_receipt_digests(self):
        for name, raw in self.historical.items():
            (self.root/name).write_bytes(raw)
        physical = self.assert_rows(loops.density760_loops(self.root))
        self.assertEqual(physical, loops.DENSITY760_INPUTS)

    def test_each_partial_cohort_is_refused_in_both_directions(self):
        for baseline, alternate in ((self.current, self.historical),
                                    (self.historical, self.current)):
            for name, raw in baseline.items():
                (self.root/name).write_bytes(raw)
            for name, raw in alternate.items():
                with self.subTest(historical=baseline is self.historical, path=name):
                    (self.root/name).write_bytes(raw)
                    self.assertEqual(loops.density760_loops(self.root), {})
                    (self.root/name).write_bytes(baseline[name])
            self.assert_rows(loops.density760_loops(self.root))

    def test_changed_provider_and_unchanged_premises_fail_closed(self):
        names = (*self.current, loops.DENSITY_SOURCE,
                 'extensions/humanoid/skeleton/head/hair/groom.mojo',
                 'math/finite.mojo', 'tests/test_reconciled_hair_density.mojo',
                 'tests/test_hair_density_bounds_controls.mojo',
                 'tools/carla_lane_oracle/pr760_arithmetic_stage.py')
        for name in names:
            path = self.root/name
            raw = path.read_bytes()
            with self.subTest(path=name):
                path.write_bytes(raw + b'\n# unreviewed dependency\n')
                self.assertEqual(loops.density760_loops(self.root), {})
                path.write_bytes(raw)
        self.assert_rows(loops.density760_loops(self.root))

    def test_successor_authority_rejects_namespace_key_and_digest_changes(self):
        expected = dict(loops.DENSITY780_DEPENDENCY_SHA256)
        missing = dict(expected)
        missing.pop('math/vector4.mojo')
        extra = dict(expected, unknown='0' * 64)
        changed = dict(expected)
        changed['math/vector4.mojo'] = '0' * 64
        class Digest(str):
            pass
        subclass = dict(expected)
        subclass['math/vector4.mojo'] = Digest(expected['math/vector4.mojo'])
        for value in (None, [], missing, extra, changed, subclass):
            with self.subTest(value=value), patch.object(
                    loops, 'DENSITY780_DEPENDENCY_SHA256', value):
                with self.assertRaises(ValueError):
                    loops._density780_dependencies()
                self.assertEqual(loops.density760_loops(self.root), {})
        del loops.DENSITY780_DEPENDENCY_SHA256
        try:
            with self.assertRaises(ValueError):
                loops._density780_dependencies()
            self.assertEqual(loops.density760_loops(self.root), {})
        finally:
            loops.DENSITY780_DEPENDENCY_SHA256 = expected
        self.assert_rows(loops.density760_loops(self.root))

    def test_temporary_authority_expansion_cannot_change_snapshotted_pins(self):
        name = 'core/extent.mojo'
        target = self.root/name
        raw = target.read_bytes() + b'\n# unreviewed physical successor\n'
        target.write_bytes(raw)
        pins = dict(loops.DENSITY780_DEPENDENCY_SHA256)
        visits = []
        def mutate(frame, event, value):
            if (event == 'return' and not visits
                    and frame.f_code is loops._density780_dependencies.__code__):
                visits.append(True)
                loops.DENSITY780_DEPENDENCY_SHA256[name] = loops.sha256(raw)
            if (event == 'return' and frame.f_code is loops.density760_loops.__code__):
                loops.DENSITY780_DEPENDENCY_SHA256.clear()
                loops.DENSITY780_DEPENDENCY_SHA256.update(pins)
        self.assertIsNone(sys.getprofile())
        sys.setprofile(mutate)
        try:
            self.assertEqual(loops.density760_loops(self.root), {})
        finally:
            sys.setprofile(None)
            loops.DENSITY780_DEPENDENCY_SHA256.clear()
            loops.DENSITY780_DEPENDENCY_SHA256.update(pins)
        self.assertEqual(visits, [True])

    def test_resolver_shadows_still_withhold_successor_rows(self):
        for name in ('std.mojo', 'math/vector4.mojopkg',
                     'geometries/surface.mojo.cov-origin'):
            path = self.root/name
            with self.subTest(path=name):
                path.write_bytes(b'unreviewed resolver surface\n')
                try:
                    self.assertEqual(loops.density760_loops(self.root), {})
                finally:
                    path.unlink()
        self.assert_rows(loops.density760_loops(self.root))


class Density780ReceiptTests(unittest.TestCase):
    setUp = density760.Density760ReceiptTests.setUp
    regenerate = density760.Density760ReceiptTests.regenerate
    derive = density760.Density760ReceiptTests.derive
    traced = density760.Density760ReceiptTests.traced
    assert_closed = density760.Density760ReceiptTests.assert_closed

    def test_receipt_records_physical_successor_hashes_without_full_gate(self):
        with self.traced() as (counts, owners):
            receipt = self.derive()
        self.assert_closed(owners, False)
        self.assertEqual(counts['full'], 0)
        rows = [row for row in receipt['proofs'] if row['module'] == DENSITY]
        self.assertEqual({row['line'] for row in rows}, ROWS)
        physical = {name: loops.sha256((self.fixture.root/name).read_bytes())
                    for name in loops.DENSITY760_INPUTS}
        for row in rows:
            self.assertEqual(row['dependency_sha256'], physical)
            self.assertEqual(row['required'], 'T')
            self.assertEqual(row['impossible'], 'F')
        self.assertEqual({name: physical[name]
                          for name in loops.DENSITY780_DEPENDENCY_SHA256},
                         loops.DENSITY780_DEPENDENCY_SHA256)

    def test_live_authority_reader_substitution_cannot_enter_receipt(self):
        target = self.fixture.root/'core/extent.mojo'
        raw = target.read_bytes()
        original_checker = Path(loops.__file__).read_bytes()
        for changed_source in (False, True):
            pins = dict(loops.DENSITY780_DEPENDENCY_SHA256)
            if changed_source:
                target.write_bytes(raw + b'\n# coordinated unreviewed successor\n')
                pins['core/extent.mojo'] = loops.sha256(target.read_bytes())
                self.regenerate()
            with self.subTest(changed_source=changed_source), patch.object(
                    loops, 'DENSITY780_DEPENDENCY_SHA256', pins), patch.object(
                    loops, '_density780_dependencies', lambda: dict(pins)), self.traced() as (_, owners):
                with self.assertRaisesRegex(ValueError, 'reader code changed'):
                    self.derive()
                self.assert_closed(owners, True)
            target.write_bytes(raw)
            self.regenerate()
        self.assertEqual(Path(loops.__file__).read_bytes(), original_checker)
        with self.traced() as (_, owners):
            receipt = self.derive()
        self.assert_closed(owners, False)
        self.assertEqual({row['line'] for row in receipt['proofs']
                          if row['module'] == DENSITY}, ROWS)

    def test_projected_successor_provider_cannot_enter_receipt(self):
        target = self.fixture.root/'math/vector4.mojo'
        reviewed = target.read_bytes()
        target.write_bytes(reviewed + b'\n# physical provider mutation\n')
        self.regenerate()
        original = Path.read_bytes
        visits = []
        def projected(path):
            frame = sys._getframe(1)
            while frame:
                if frame.f_code is loops.density760_loops.__code__ and path == target:
                    visits.append(True)
                    return reviewed
                frame = frame.f_back
            return original(path)
        with patch.object(Path, 'read_bytes', projected), self.traced() as (_, owners):
            with self.assertRaises(ValueError):
                self.derive()
        self.assertTrue(visits)
        self.assert_closed(owners, True)

    def test_transient_successor_mutation_stays_failed_after_restoration(self):
        target = self.fixture.root/'core/extent.mojo'
        raw = target.read_bytes()
        visits = []
        def mutate(frame, event, value, owners):
            if (not visits and event == 'return'
                    and frame.f_code is loops._density760_stage_identity.__code__):
                visits.append(True)
                target.write_bytes(raw + b'\n# transient successor mutation\n')
                try:
                    loops._coverage_observe_bytes(self.fixture.root, 'core/extent.mojo',
                        target.read_bytes(), _operation=owners[0])
                except ValueError:
                    pass
                target.write_bytes(raw)
        with self.traced(mutate) as (_, owners):
            with self.assertRaises(ValueError):
                self.derive()
        self.assertEqual(target.read_bytes(), raw)
        self.assertEqual(visits, [True])
        self.assert_closed(owners, True)


if __name__ == '__main__':
    unittest.main()
