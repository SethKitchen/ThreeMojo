# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bounded constructor-valid taper refusals before candidate access."""

from extensions.animals.anatomy.density import (
    IS_COAT,
    solid_densities,
    solid_roles,
)
from extensions.animals.anatomy.mass import (
    BLOCK,
    INVALID_FIELD,
    STATS,
    _check_sampling_model,
    _sample_distance,
    sample_mass,
)
from extensions.animals.build import Animal, create_animal, part_box
from extensions.animals.options import ADULT, CROWD, MALE, animal_options
from extensions.animals.parts import BODY
from extensions.animals.registry import RAT
from extensions.sdf.field import SdfModel
from extensions.sdf.ids import FIN, LENS
from extensions.sdf.vector import V3
from std.math import ceil, isfinite, isnan, sqrt
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER


def _fin_animal(gradient: Float64, coat: Bool) raises -> Animal:
    var animal = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var bones = len(animal.rig.bones)
    var bone = animal.rig.bone("pelvis")
    var model = SdfModel()
    if coat:
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
    var outline: List[Float64] = [
        -0.25,
        -0.25,
        0.25,
        -0.25,
        0.25,
        0.25,
        -0.25,
        0.25,
    ]
    _ = model.fin(
        "tuft" if coat else "body",
        bone,
        V3(0, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        outline,
        0.25,
        grad_u=gradient,
        grad_v=0,
        k=0,
        part=BODY,
    )
    animal.model = model^
    assert_equal(len(animal.rig.bones), bones)
    return animal^


def _assert_geometry(animal: Animal, gradient: Float64, coat: Bool) raises:
    var index = Int(coat)
    assert_equal(len(animal.model.prims), index + 1)
    assert_equal(len(animal.model.outline), 8)
    assert_true(len(animal.rig.bones) > 0 and len(animal.rig.bones) <= 64)
    var outline: List[Float64] = [
        -0.25,
        -0.25,
        0.25,
        -0.25,
        0.25,
        0.25,
        -0.25,
        0.25,
    ]
    for i in range(8):
        assert_equal(animal.model.outline[i], outline[i])
    for primitive in animal.model.prims:
        for point in [primitive.c, primitive.b]:
            assert_equal(point.x, 0.0)
            assert_equal(point.y, 0.0)
            assert_equal(point.z, 0.0)
        for pair in [
            (primitive.ax, V3(1, 0, 0)),
            (primitive.ay, V3(0, 1, 0)),
            (primitive.az, V3(0, 0, 1)),
        ]:
            assert_equal(pair[0].x, pair[1].x)
            assert_equal(pair[0].y, pair[1].y)
            assert_equal(pair[0].z, pair[1].z)
    if coat:
        ref lens = animal.model.prims[0]
        assert_equal(lens.kind, LENS)
        assert_equal(lens.r.x, 0.2)
        assert_equal(lens.r.y, 0.05)
        assert_equal(lens.r.z, 0.0)
        assert_equal(lens.lo, -0.1)
        assert_equal(lens.hi, 0.1)
        assert_equal(lens.k, 0.0)
        assert_equal(lens.carve, False)
        assert_equal(lens.part, BODY)
        assert_equal(animal.model.tag_name(lens.tag), "body")
    ref fin = animal.model.prims[index]
    assert_equal(fin.kind, FIN)
    assert_equal(fin.part, BODY)
    assert_equal(fin.first, 0)
    assert_equal(fin.count, 4)
    assert_true(isfinite(gradient))
    assert_equal(fin.lo, gradient)
    assert_equal(fin.hi, 0.0)
    assert_equal(fin.r.x, 0.125)
    assert_equal(fin.r.y, 0.125)
    assert_equal(fin.k, 0.0)
    assert_equal(fin.carve, False)
    assert_equal(animal.model.tag_name(fin.tag), "tuft" if coat else "body")
    assert_equal(fin.bone.value, animal.rig.bone("pelvis").value)
    var density = solid_densities(animal)
    var roles = solid_roles(animal)
    assert_equal(len(density), index + 1)
    assert_equal(len(roles), index + 1)
    if coat:
        assert_equal(density[index], 0.0)
        assert_true(roles[index] & IS_COAT != 0)
        assert_true(density[0] > 0)
    else:
        assert_true(density[index] > 0)
        assert_equal(roles[index] & IS_COAT, 0)


def _checked_pose(animal: Animal, coat: Bool, h: Float64) raises -> SdfModel:
    var pose = animal.bind_pose()
    var posed = animal.model.moved(pose.world(animal.rig))
    _check_sampling_model(posed)
    var index = Int(coat)
    ref fin = posed.prims[index]
    assert_equal(fin.c.x, 0.0)
    assert_equal(fin.c.y, 0.0)
    assert_equal(fin.c.z, 0.0)
    for pair in [
        (fin.ax, V3(1, 0, 0)),
        (fin.ay, V3(0, 1, 0)),
        (fin.az, V3(0, 0, 1)),
    ]:
        assert_equal(pair[0].x, pair[1].x)
        assert_equal(pair[0].y, pair[1].y)
        assert_equal(pair[0].z, pair[1].z)
    var ids = List[Int]()
    for i in range(index + 1):
        ids.append(i)
    var bounds = part_box(posed, ids)
    for value in [bounds[0].x, bounds[0].y, bounds[0].z]:
        assert_equal(value, -0.625)
    for value in [bounds[1].x, bounds[1].y, bounds[1].z]:
        assert_equal(value, 0.625)
    var nx = ceil((bounds[1].x - bounds[0].x) / h)
    var ny = ceil((bounds[1].y - bounds[0].y) / h)
    var nz = ceil((bounds[1].z - bounds[0].z) / h)
    var expected = Float64(8) if h == 0.15625 else Float64(5)
    assert_equal(nx, expected)
    assert_equal(ny, expected)
    assert_equal(nz, expected)
    assert_true(nx * ny * nz <= 512)
    assert_equal(BLOCK, 8)
    assert_equal(STATS, 8)
    assert_equal(INVALID_FIELD, 7)
    return posed^


def _step(h: Float64) raises -> Length:
    var step = Length(Float32(h), METER)
    assert_equal(Float64(step.to(METER)), h)
    return step


def _refusal(gradient: Float64, coat: Bool, h: Float64, at_center: Bool) raises:
    var animal = _fin_animal(gradient, coat)
    _assert_geometry(animal, gradient, coat)
    var bones = len(animal.rig.bones)
    var tags = len(animal.model.tags)
    var posed = _checked_pose(animal, coat, h)
    var index = Int(coat)
    var ids: List[Int] = [index]
    var center = -0.625 + 0.5 * Float64(BLOCK) * h
    var first = -0.625 + 0.5 * h
    var c = V3(center, center, center)
    var q = V3(first, first, first)
    assert_equal(center, 0.375 if at_center else 0.0)
    assert_equal(first, -0.5 if at_center else -0.546875)
    if coat:
        var body: List[Int] = [0]
        assert_true(isfinite(_sample_distance(posed, body, c)))
        assert_true(isfinite(_sample_distance(posed, body, q)))
    if at_center:
        assert_true(isnan(posed.distance(index, c)))
        assert_true(isnan(_sample_distance(posed, ids, c)))
    else:
        assert_true(isfinite(posed.distance(index, c)))
        assert_equal(_sample_distance(posed, ids, c), 0.0)
        var rho = 0.5 * sqrt(3.0) * Float64(BLOCK) * h
        var kept = posed.cull(ids, c, rho, posed.max_blend())
        assert_equal(len(kept), 1)
        assert_equal(kept[0], index)
        assert_true(isfinite(_sample_distance(posed, kept, c)))
        assert_true(isnan(posed.distance(index, q)))
        assert_true(isnan(_sample_distance(posed, kept, q)))
    with assert_raises(
        contains="A sampled field must have finite valid distances"
    ):
        _ = sample_mass(animal, animal.bind_pose(), _step(h), 1)
    assert_equal(len(animal.rig.bones), bones)
    assert_equal(len(animal.model.tags), tags)
    _assert_geometry(animal, gradient, coat)


def test_coat_taper_refuses_at_original_block_center() raises:
    _refusal(1e200, True, 0.25, True)


def test_coat_taper_refuses_at_first_cell_before_solids() raises:
    _refusal(-1e200, True, 0.15625, False)


def test_solid_taper_refuses_at_first_cell_before_nearest() raises:
    _refusal(-1e200, False, 0.15625, False)


def test_zero_taper_controls_keep_positive_finite_mass() raises:
    for control in [
        (False, Float64(0.15625)),
        (True, Float64(0.15625)),
        (True, Float64(0.25)),
    ]:
        var coat = control[0]
        var h = control[1]
        var animal = _fin_animal(0, coat)
        _assert_geometry(animal, 0, coat)
        _ = _checked_pose(animal, coat, h)
        var bones = len(animal.rig.bones)
        var result = sample_mass(animal, animal.bind_pose(), _step(h), 1)
        assert_equal(len(result.bones), bones)
        assert_true(isfinite(result.total().mass.value))
        assert_true(result.total().mass.value > 0)
        assert_true(result.volume.value > 0)
        assert_equal(len(animal.rig.bones), bones)
        _assert_geometry(animal, 0, coat)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
