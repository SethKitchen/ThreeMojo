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
# The Mojo 1.2 port edits three imported helpers that the PR760 image does not
# pin. Each row maps a helper to its port digest and its exact inverse edits,
# as (start, stop, before, after) in the coordinates of the port source.
PORT_INVERSE = {
    'extensions/humanoid/skeleton/head/assembly.mojo': (
        '813a09e4b30a5a9682e606cdabb2e22188866f4153318a18f9df62f091c0435e',
        ((362, 363, ('    scene.add_mesh(mesh^)\n',), ('    scene.add_mesh(mesh)\n',)),)),
    'extensions/humanoid/skeleton/look.mojo': (
        '662665a1ea3c291b45030fcf90d732b2a7900f0c1a591e4d94d854201e8caa48',
        ((725, 726, ('    var skin = assets.materials.add(look^)\n',),
          ('    var skin = assets.materials.add(look)\n',)),
         (757, 758, ('    return assets.materials.add(material^)\n',),
          ('    return assets.materials.add(material)\n',)))),
    'extensions/humanoid/skeleton/surface_nets.mojo': (
        '98b354cea54d1d1dc33ee23f02b0e89f80466ddb2fc06a6415ea224a3a93aeee',
        ((319, 320, ('async def _sample_task[\n',), ('__async def _sample_task[\n',)),
         (344, 345, ('async def _vertex_task[\n',), ('__async def _vertex_task[\n',)))),
}

# PR843 adds the #792 work limits to four cohort helpers that the PR780
# successor does not pin. Each row inverts those edits to the bytes before
# them: the PR760 image, or the Mojo 1.2 port for the surface net.
PR843_INVERSE = {
    'extensions/humanoid/skeleton/loft.mojo': (
        'fe36bfbe8b8022fcf37a145368865b5841a194cbb2549a3335bc1f07aaab4e91',
        (
         (569, 575, ('    var steps = Int(run / (Float32(0.5) * finest)) + 2\n', '    if steps > 16:\n', '        steps = 16\n'),
          ('    # Sixteen slices is the cap. A ratio of fifteen or more, or one that\n', '    # is not a number, is not a count `Int` can hold.\n', '    var ratio = run / (Float32(0.5) * finest)\n', '    var steps = 16\n', '    if ratio < Float32(15):\n', '        steps = Int(ratio) + 2\n')),)),
    'extensions/humanoid/skeleton/surface_nets.mojo': (
        '05a7d079446a90673256f9f38529922c861c3c137151edd332195cd00d011e81',
        (
         (40, 41, ('from std.math import atan2, ceil, max, min, pi, sqrt\n',),
          ('from std.math import atan2, ceil, isfinite, max, min, pi, sqrt\n',)),
         (44, 46, (),
          ('# Each pass walks every vertex. The maximum integer never finishes.\n', 'comptime MAX_SMOOTH_PASSES = 16777216\n')),
         (81, 100, ('def _blocks(span: Float32, cell: Float32) -> Int:\n', '    """Return how many whole blocks hold `span` at `cell`, at least one."""\n', '    return max(1, Int(ceil(span / (cell * Float32(BLOCK)))))\n'),
          ('def _blocks(span: Float32, cell: Float32) raises -> Int:\n', '    """Return how many whole blocks hold `span` at `cell`, at least one.\n', '\n', '    Args:\n', "        span: The length to cover, in the field's units.\n", '        cell: The fine cell size. It must be positive.\n', '\n', '    Returns:\n', '        The block count.\n', '\n', '    Raises:\n', '        Error: If the count is not a positive finite integer this port\n', '            stores, including after the block is widened to fine cells.\n', '    """\n', '    var count = ceil(Float64(span) / (Float64(cell) * Float64(BLOCK)))\n', '    # `Int.MAX // BLOCK` keeps `blocks * BLOCK` inside an integer.\n', '    if not isfinite(count) or count <= 0 or count > Float64(Int.MAX // BLOCK):\n', '        raise Error("A surface net is larger than this port builds")\n', '    return Int(count)\n')),
         (461, 464, ('        Error: If `detail` is out of range, or the field makes no\n', '            surface in the box.\n'),
          ('        Error: If `detail` is out of range, `smoothing` is above\n', "            16777216, the box's block count does not fit in an integer,\n", '            or the field makes no surface in the box.\n')),
         (466, 471, (),
          ('    if smoothing > MAX_SMOOTH_PASSES:\n', '        raise Error(\n', '            "A surface net\'s smoothing count is larger than this port"\n', '            + " smooths"\n', '        )\n')),
         (482, 487, (),
          ('    var nx = bx * BLOCK + 1\n', '    var ny = by * BLOCK + 1\n', '    var nz = bz * BLOCK + 1\n', '    if nx > Int.MAX // ny or nx * ny > Int.MAX // nz:\n', '        raise Error("A surface net is larger than this port builds")\n')),
         (488, 489, ('    var total = (grid.nx + 1) * (grid.ny + 1) * (grid.nz + 1)\n',),
          ('    var total = nx * ny * nz\n',)),)),
    'extensions/humanoid/skeleton/torso/bones/dimensions.mojo': (
        '7da0adc38b32b78766ec9685c53015e215a814c7eb92b44d0663ee27b188d332',
        (
         (692, 693, ('def rib_path(dimensions: TorsoDimensions, rib: Int) -> List[Vector3]:\n',),
          ('def rib_path(dimensions: TorsoDimensions, rib: Int) raises -> List[Vector3]:\n',)),
         (702, 705, (),
          ('\n', '    Raises:\n', '        Error: If the spline sample count is refused.\n')),
         (790, 791, ('def _rib(dimensions: TorsoDimensions, rib: Int) -> Sweep:\n',),
          ('def _rib(dimensions: TorsoDimensions, rib: Int) raises -> Sweep:\n',)),
         (899, 900, ('def clavicle_path(dimensions: TorsoDimensions) -> List[Vector3]:\n',),
          ('def clavicle_path(dimensions: TorsoDimensions) raises -> List[Vector3]:\n',)),
         (911, 914, (),
          ('\n', '    Raises:\n', '        Error: If the spline sample count is refused.\n')),
         (927, 928, ('def _clavicle(dimensions: TorsoDimensions) -> Sweep:\n',),
          ('def _clavicle(dimensions: TorsoDimensions) raises -> Sweep:\n',)),
         (1171, 1172, ('):\n',),
          (') raises:\n',)),
         (1180, 1183, (),
          ('\n', '    Raises:\n', '        Error: If the spline sample count is refused.\n')),)),
    'extensions/humanoid/skeleton/torso/sweep.mojo': (
        '1eb865b559862c5d27371f4ae9e5a576b827eb49f7b2e0906c7e00bee8aa34a1',
        (
         (425, 432, ('def spline_points(points: List[Vector3], steps: Int) -> List[Vector3]:\n',),
          ('# Samples between two control points. `steps + 1` wraps at `Int.MAX`,\n', '# so the span walk is empty, and `range` of one below that never ends.\n', '# `Float32` also stops telling those steps apart past 2^24.\n', 'comptime MAX_SPLINE_STEPS = 16777216\n', '\n', '\n', 'def spline_points(points: List[Vector3], steps: Int) raises -> List[Vector3]:\n')),
         (436, 437, ('        steps: Samples between two control points.\n',),
          ('        steps: Samples between two control points. One through 16777216.\n',)),
         (441, 444, (),
          ('\n', '    Raises:\n', '        Error: If `steps` is below one or above 16777216.\n')),
         (445, 449, (),
          ('    if steps < 1:\n', '        raise Error("A spline needs one sample between control points or more")\n', '    if steps > MAX_SPLINE_STEPS:\n', '        raise Error("A spline sample count is larger than this port builds")\n')),)),
}

# The CSS color successor writes through this module, so the successor
# cohort's closure holds it as well.
CLOSURE_ADDITIONS = ('loaders/js_number.mojo',)


def _inverted(name, raw, table):
    """Undo one table row's edits when `raw` is its exact endpoint."""
    digest, edits = table[name]
    if loops.sha256(raw) != digest:
        return raw
    lines = raw.decode().splitlines(keepends=True)
    for start, stop, before, after in reversed(edits):
        assert tuple(lines[start:stop]) == after, (name, start)
        lines[start:stop] = before
    return ''.join(lines).encode()


def historical_bytes(name, raw):
    """Return the PR760 bytes of a cohort helper from its current bytes."""
    if name in PR843_INVERSE:
        raw = _inverted(name, raw, PR843_INVERSE)
    if name not in PORT_INVERSE:
        return successor.predecessor_bytes(name, raw)
    return _inverted(name, raw, PORT_INVERSE)


class Density780DependencyTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='density780-local-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        for name in (*loops.DENSITY760_INPUTS, *CLOSURE_ADDITIONS):
            target = self.root/name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT/name).read_bytes())
        self.current = {name: (self.root/name).read_bytes()
                        for name in loops.DENSITY780_DEPENDENCY_SHA256}
        self.historical = {name: historical_bytes(name, raw)
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
            'objects/gaussian_splat.mojo', 'geometries/attribute_utils.mojo', 'lights/shadow.mojo', 'render/tasks.mojo',
            *PORT_INVERSE,
            # PR843
            'core/fog.mojo', 'core/gaussian_splat_utils.mojo', 'core/geometry_store.mojo',
            'core/morph.mojo', 'extensions/humanoid/skeleton/head/hair/groom.mojo',
            'materials/material.mojo', 'math/curve.mojo', 'math/curve_checks.mojo',
            'math/path.mojo', 'math/utils.mojo', 'objects/line_segments2.mojo',
            'render/css_color.mojo', 'render/cube_texture.mojo', 'render/cube_uv.mojo',
            'render/framebuffer.mojo', 'render/linerule.mojo', 'render/texture.mojo',
            'render/volume_texture.mojo', *PR843_INVERSE,
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
