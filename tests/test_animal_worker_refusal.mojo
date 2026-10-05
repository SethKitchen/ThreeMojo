# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded pre-cull refusal for a normal-sized distant subtractive lens."""

from extensions.animals.anatomy.mass import (
    BLOCK,
    INVALID_FIELD,
    STATS,
    _check_sampling_model,
    sample_mass,
)
from extensions.animals.build import Animal, create_animal, part_box
from extensions.animals.options import ADULT, CROWD, MALE, animal_options
from extensions.animals.parts import BODY
from extensions.animals.registry import RAT
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import V3
from std.math import ceil, isfinite
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER


def _two_lenses(carve_x: Float64) raises -> Animal:
    var animal = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var original_bones = len(animal.rig.bones)
    var bone = animal.rig.bone("pelvis")
    var model = SdfModel()
    _ = model.lens(
        "body",
        bone,
        V3(0, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        V3(0, 0, 1),
        0.2,
        0.05,
        -0.1,
        0.1,
        k=0,
        part=BODY,
    )
    _ = model.lens(
        "cut",
        bone,
        V3(carve_x, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        V3(0, 0, 1),
        0.2,
        0.05,
        -0.1,
        0.1,
        k=0,
        carve=True,
        part=BODY,
    )
    animal.model = model^
    assert_equal(len(animal.rig.bones), original_bones)
    return animal^


def _assert_work_bound(animal: Animal) raises:
    assert_equal(len(animal.model.prims), 2)
    assert_true(len(animal.rig.bones) > 0 and len(animal.rig.bones) <= 64)
    var pose = animal.bind_pose()
    var posed = animal.model.moved(pose.world(animal.rig))
    _check_sampling_model(posed)
    var ids: List[Int] = [0, 1]
    var bounds = part_box(posed, ids)
    var h = Float64(Length(0.25, METER).value)
    var nx = ceil((bounds[1].x - bounds[0].x) / h)
    var ny = ceil((bounds[1].y - bounds[0].y) / h)
    var nz = ceil((bounds[1].z - bounds[0].z) / h)
    assert_true(isfinite(nx) and nx >= 1 and nx <= 5)
    assert_true(isfinite(ny) and ny >= 1 and ny <= 5)
    assert_true(isfinite(nz) and nz >= 1 and nz <= 5)
    assert_true(nx * ny * nz <= 125)
    # Each dimension is below BLOCK=8, and workers=1 below, so the
    # production task count is one. Its existing allocation has eight slots.
    assert_equal(BLOCK, 8)
    assert_equal(STATS, 8)
    assert_equal(INVALID_FIELD, 7)


def test_far_subtractive_lens_refuses_before_candidate_access() raises:
    var animal = _two_lenses(1e200)
    _assert_work_bound(animal)
    var bones = len(animal.rig.bones)
    var tags = len(animal.model.tags)
    with assert_raises(
        contains="A sampled field must have finite valid distances"
    ):
        _ = sample_mass(animal, animal.bind_pose(), Length(0.25, METER), 1)
    assert_equal(len(animal.model.prims), 2)
    assert_equal(len(animal.model.tags), tags)
    assert_equal(len(animal.rig.bones), bones)
    assert_equal(animal.model.prims[0].c.x, Float64(0))
    assert_equal(animal.model.prims[1].c.x, Float64(1e200))
    assert_equal(animal.model.prims[0].r.x, Float64(0.2))
    assert_equal(animal.model.prims[1].r.x, Float64(0.2))
    assert_true(animal.model.prims[1].carve)


def test_nearby_subtractive_lens_keeps_finite_mass() raises:
    var animal = _two_lenses(2)
    _assert_work_bound(animal)
    var result = sample_mass(animal, animal.bind_pose(), Length(0.25, METER), 1)
    assert_equal(len(result.bones), len(animal.rig.bones))
    assert_true(isfinite(result.total().mass.value))
    assert_true(result.total().mass.value > 0)
    assert_true(result.volume.value > 0)
    assert_equal(len(animal.model.prims), 2)
    assert_equal(animal.model.prims[1].c.x, Float64(2))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
