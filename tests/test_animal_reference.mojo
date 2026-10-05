# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Analytic landmark controls and scale covariance across all 24 species."""

from extensions.animals.anatomy.body import species_body
from extensions.animals.anatomy.reference import _extent, reference_length
from extensions.animals.build import Animal, create_animal
from extensions.animals.options import (
    ADULT,
    CROWD,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import SPECIES_COUNT, SpeciesId
from extensions.animals.warp import Warps, scale_warp
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import BoneId
from extensions.sdf.vector import V3
from std.math import sqrt
from std.testing import TestSuite, assert_almost_equal


def test_analytic_envelopes_have_independent_closed_form_controls() raises:
    var model = SdfModel()
    var y = V3(0, 1, 0)
    var z = V3(0, 0, 1)
    var id = model.ell("ellipsoid", BoneId(0), V3(1, 2, 3), V3(2, 3, 4), k=0.0)
    var bounds = _extent(model.prims[id], model.outline, y)
    assert_almost_equal(bounds[0], -1.0)
    assert_almost_equal(bounds[1], 5.0)
    bounds = _extent(
        model.prims[id], model.outline, (y + z) * (1.0 / sqrt(2.0))
    )
    assert_almost_equal(
        bounds[1] - bounds[0], 2.0 * sqrt((9.0 + 16.0) / 2.0), rtol=1e-12
    )
    id = model.cone(
        "cone", BoneId(0), V3(0, 0, 0), V3(0, 0, 2), 0.2, 0.4, k=0.0
    )
    bounds = _extent(model.prims[id], model.outline, z)
    assert_almost_equal(bounds[0], -0.2)
    assert_almost_equal(bounds[1], 2.4)


def test_all_species_landmarks_scale_without_occupancy_sampling() raises:
    for i in range(SPECIES_COUNT):
        var id = SpeciesId(i)
        var body = species_body(id)
        var base = create_animal(
            id,
            animal_options(
                1,
                quality=CROWD,
                sex=MALE,
                age=ADULT,
                variant=Variant(max(0, body.variant)),
            ),
        )
        var before = Float64(reference_length(base).value)
        for factor in [0.6, 1.7]:
            var warp = Warps()
            warp.add(scale_warp(factor))
            var grown = Animal(
                base.species,
                base.options,
                base.traits.copy(),
                warp.warp_rig(base.rig),
                warp.warp_model(base.model),
                base.palette.copy(),
                base.eye,
                base.look,
                base.cell * factor,
                base.eye_cell * factor,
            )
            assert_almost_equal(
                Float64(reference_length(grown).value),
                before * factor,
                rtol=2e-6,
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
