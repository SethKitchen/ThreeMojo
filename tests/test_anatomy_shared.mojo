# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Shared integration retains each leg bone's previous grid arithmetic."""

from core.assets import Assets
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import MIN_STATURE, MAX_STATURE
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.occupancy import (
    BoneMass,
    BoneOccupancy,
    Tally,
    add_fill,
    finish_mass,
    grid_cells,
    sample_bone_mass,
)
from extensions.humanoid.skeleton.look import resolved_paint
from extensions.humanoid.skeleton.soft_tissue import (
    vessel_tissue,
    arterial_tissue,
    venous_tissue,
)
from extensions.humanoid.skeleton.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from materials.material import MaterialId, phong_material
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises
from units.si import Length, MILLIMETER
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurField,
    femur_dimensions,
)
from extensions.humanoid.skeleton.leg.femur.mass import (
    femur_mass_from_dimensions,
    femur_field_occupancy,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaField,
    tibia_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.mass import (
    tibia_mass_from_dimensions,
    tibia_field_occupancy,
)
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    FibulaField,
    fibula_dimensions,
)
from extensions.humanoid.skeleton.leg.fibula.mass import (
    fibula_mass_from_dimensions,
    fibula_field_occupancy,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaField,
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.mass import (
    patella_mass_from_dimensions,
    patella_field_occupancy,
)


def _reference[
    F: DistanceField, //, classify: def(F, Vector3) thin -> BoneOccupancy
](field: F, low: Vector3, high: Vector3, step: Length) raises -> BoneMass:
    # Independent copy of the pre-extraction grid traversal. Keep its
    # Float32 operation and accumulation order to detect numeric drift.
    var cortical = cortical_tissue()
    var trabecular = trabecular_tissue()
    var dx = step.value
    var dy = step.value
    var dz = step.value
    var nx = grid_cells(high.x - low.x, dx)
    var ny = grid_cells(high.y - low.y, dy)
    var nz = grid_cells(high.z - low.z, dz)
    var cell = dx * dy * dz
    var tally = Tally(0, 0, 0, 0, 0)
    for iz in range(nz):
        var z = low.z + (Float32(iz) + Float32(0.5)) * dz
        for iy in range(ny):
            var y = low.y + (Float32(iy) + Float32(0.5)) * dy
            for ix in range(nx):
                var x = low.x + (Float32(ix) + Float32(0.5)) * dx
                add_fill(
                    tally,
                    classify(field, Vector3(x, y, z)),
                    cell,
                    cortical,
                    trabecular,
                )
    return finish_mass(tally)


def _same(actual: BoneMass, expected: BoneMass) raises:
    assert_equal(actual.envelope.value, expected.envelope.value)
    assert_equal(actual.cortical_region.value, expected.cortical_region.value)
    assert_equal(
        actual.trabecular_region.value, expected.trabecular_region.value
    )
    assert_equal(actual.solid_tissue.value, expected.solid_tissue.value)
    assert_equal(actual.mass.value, expected.mass.value)


def test_femur_integration_keeps_exact_grid_results() raises:
    for stature in [MIN_STATURE, MAX_STATURE]:
        for side in [LEFT, RIGHT]:
            var sex = FEMALE if stature == MIN_STATURE else MALE
            var dims = femur_dimensions(stature, sex, side)
            var field = FemurField(dims)
            for millimeters in [5, 20]:
                var step = Length(Float32(millimeters), MILLIMETER)
                _same(
                    femur_mass_from_dimensions(
                        dims, cortical_tissue(), trabecular_tissue(), step
                    ),
                    _reference[femur_field_occupancy](
                        field, field.low, field.high, step
                    ),
                )


def test_tibia_integration_keeps_exact_grid_results() raises:
    for stature in [MIN_STATURE, MAX_STATURE]:
        for side in [LEFT, RIGHT]:
            var sex = FEMALE if stature == MIN_STATURE else MALE
            var dims = tibia_dimensions(stature, sex, side)
            var field = TibiaField(dims)
            for millimeters in [5, 20]:
                var step = Length(Float32(millimeters), MILLIMETER)
                _same(
                    tibia_mass_from_dimensions(
                        dims, cortical_tissue(), trabecular_tissue(), step
                    ),
                    _reference[tibia_field_occupancy](
                        field, field.low, field.high, step
                    ),
                )


def test_fibula_integration_keeps_exact_grid_results() raises:
    for stature in [MIN_STATURE, MAX_STATURE]:
        for side in [LEFT, RIGHT]:
            var sex = FEMALE if stature == MIN_STATURE else MALE
            var dims = fibula_dimensions(stature, sex, side)
            var field = FibulaField(dims)
            for millimeters in [5, 20]:
                var step = Length(Float32(millimeters), MILLIMETER)
                _same(
                    fibula_mass_from_dimensions(
                        dims, cortical_tissue(), trabecular_tissue(), step
                    ),
                    _reference[fibula_field_occupancy](
                        field, field.low, field.high, step
                    ),
                )


def test_patella_integration_keeps_exact_grid_results() raises:
    for stature in [MIN_STATURE, MAX_STATURE]:
        for side in [LEFT, RIGHT]:
            var sex = FEMALE if stature == MIN_STATURE else MALE
            var dims = patella_dimensions(stature, sex, side)
            var field = PatellaField(dims)
            for millimeters in [5, 20]:
                var step = Length(Float32(millimeters), MILLIMETER)
                _same(
                    patella_mass_from_dimensions(
                        dims, cortical_tissue(), trabecular_tissue(), step
                    ),
                    _reference[patella_field_occupancy](
                        field, field.low, field.high, step
                    ),
                )


def test_shared_sampler_refuses_invalid_bounds_and_steps() raises:
    var dims = femur_dimensions(MIN_STATURE, FEMALE)
    var field = FemurField(dims)
    for invalid in [inf[DType.float32](), nan[DType.float32]()]:
        with assert_raises(contains="finite and ordered"):
            _ = sample_bone_mass[femur_field_occupancy](
                field,
                Vector3(invalid, 0, 0),
                Vector3(1, 1, 1),
                cortical_tissue(),
                trabecular_tissue(),
                Length(20, MILLIMETER),
                "test",
            )
        with assert_raises(contains="finite and ordered"):
            _ = sample_bone_mass[femur_field_occupancy](
                field,
                Vector3(0, 0, 0),
                Vector3(1, invalid, 1),
                cortical_tissue(),
                trabecular_tissue(),
                Length(20, MILLIMETER),
                "test",
            )
    with assert_raises(contains="finite and ordered"):
        _ = sample_bone_mass[femur_field_occupancy](
            field,
            Vector3(0, 0, 1),
            Vector3(1, 1, 0),
            cortical_tissue(),
            trabecular_tissue(),
            Length(20, MILLIMETER),
            "test",
        )
    for low_x in [Float32(0), Float32(-3e38)]:
        with assert_raises(contains="span is too large"):
            _ = sample_bone_mass[femur_field_occupancy](
                field,
                Vector3(low_x, 0, 0),
                Vector3(Float32(3e38), 1, 1),
                cortical_tissue(),
                trabecular_tissue(),
                Length(20, MILLIMETER),
                "test",
            )
    for value in [
        Float32(0),
        Float32(21),
        inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises():
            _ = sample_bone_mass[femur_field_occupancy](
                field,
                field.low,
                field.high,
                cortical_tissue(),
                trabecular_tissue(),
                Length(value, MILLIMETER),
                "test",
            )


def test_shared_paint_reuses_explicit_ids_and_creates_defaults() raises:
    var assets = Assets()
    var first = resolved_paint(
        assets, MaterialId(-1), phong_material(Color(20, 40, 60))
    )
    assert_equal(assets.materials.count(), 1)
    var again = resolved_paint(assets, first, phong_material(Color(90, 80, 70)))
    assert_equal(first, again)
    assert_equal(assets.materials.count(), 1)
    _ = resolved_paint(
        assets, MaterialId(-1), phong_material(Color(90, 80, 70))
    )
    assert_equal(assets.materials.count(), 2)


def test_shared_vessel_tissue_keeps_every_template_field() raises:
    for arterial in [False, True]:
        var actual = vessel_tissue(arterial)
        var expected = arterial_tissue() if arterial else venous_tissue()
        assert_equal(actual.kind, expected.kind)
        assert_equal(actual.wet_density.value, expected.wet_density.value)
        assert_equal(actual.water_fraction, expected.water_fraction)
        assert_equal(
            actual.elastic_modulus.value, expected.elastic_modulus.value
        )
        assert_equal(actual.poisson_ratio, expected.poisson_ratio)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
