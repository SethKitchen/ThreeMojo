# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Dimensional contracts for template vertebral bodies and discs."""

from extensions.humanoid.sex import MALE, FEMALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.skeleton.torso.sweep import Sweep
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    torso_dimensions,
    torso_bone_field,
    TorsoBone,
)
from extensions.humanoid.skeleton.torso.ligaments.dimensions import (
    torso_ligament_field,
    INTERVERTEBRAL_DISCS,
)
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.bones.dimensions import (
    head_bone_field,
    HeadBone,
)
from extensions.humanoid.skeleton.head.ligaments.dimensions import (
    head_ligament_field,
    CERVICAL_DISCS,
)
from math.vector3 import Vector3
from std.math import pi
from std.testing import TestSuite, assert_almost_equal, assert_true
from units.si import Length, METER


def test_flat_sections_preserve_endplanes_and_integrated_volume() raises:
    var flat = Sweep(Vector3(1, 0, 0), flat_y=True)
    flat.add(Vector3(0, 0, 0), 0.02, 0.01)
    flat.add(Vector3(0.01, 0.03, 0.02), 0.03, 0.02)
    # Shear changes the center, not the horizontal cross-sectional area.
    assert_almost_equal(
        flat.volume(),
        pi
        * 0.03
        * (2 * 0.02 * 0.01 + 0.02 * 0.02 + 0.03 * 0.01 + 2 * 0.03 * 0.02)
        / 6,
        atol=1e-9,
    )
    for t in [Float32(0), Float32(1)]:
        var center = Vector3(0.01 * t, 0.03 * t, 0.02 * t)
        assert_almost_equal(flat.distance(center, 0.005), 0, atol=1e-7)
        var outward = Float32(-1) if t == 0 else Float32(1)
        assert_true(
            flat.distance(center + Vector3(0, outward * 0.001, 0), 0.005) > 0
        )
    assert_true(flat.distance(Vector3(0.005, 0.015, 0.01), 0.005) < 0)
    # Reversing station order preserves the same solid and volume.
    var reverse = Sweep(Vector3(0, 0, 1), flat_y=True)
    reverse.add(Vector3(0.01, 0.03, 0.02), 0.03, 0.02)
    reverse.add(Vector3(0, 0, 0), 0.02, 0.01)
    assert_almost_equal(reverse.volume(), flat.volume(), atol=1e-9)
    assert_almost_equal(
        reverse.distance(Vector3(0.005, 0.015, 0.01), 0),
        flat.distance(Vector3(0.005, 0.015, 0.01), 0),
        atol=1e-7,
    )


def test_flat_empty_and_zero_height_segments_have_no_interior() raises:
    var flat = Sweep(Vector3(1, 0, 0), flat_y=True)
    assert_true(flat.distance(Vector3(0, 0, 0), 0) > 0)
    assert_almost_equal(flat.volume(), 0)
    flat.round(Vector3(0, 0, 0), 0.01)
    assert_true(flat.distance(Vector3(0, 0, 0), 0) > 0)
    flat.round(Vector3(0.01, 0, 0), 0.01)
    assert_true(flat.distance(Vector3(0, 0, 0), 0) > 0)
    assert_almost_equal(flat.volume(), 0)


def test_default_capsules_keep_their_caps() raises:
    var capsule = Sweep(Vector3(1, 0, 0))
    capsule.round(Vector3(0, 0, 0), 0.01)
    capsule.round(Vector3(0, 0.03, 0), 0.01)
    assert_true(capsule.distance(Vector3(0, -0.005, 0), 0.001) < 0)
    assert_almost_equal(
        capsule.volume(),
        pi * 0.0001 * 0.03 + Float32(4.0 / 3.0) * pi * 0.000001,
        atol=1e-9,
    )


def _body_contract(
    body: Sweep,
    center: Vector3,
    height: Float32,
    width: Float32,
    depth: Float32,
) raises:
    assert_true(body.flat_y)
    assert_almost_equal(body.volume(), pi * width * depth * height, atol=1e-8)
    for side in [Float32(-1), Float32(1)]:
        var end = center + Vector3(0, side * height * 0.5, 0)
        assert_almost_equal(body.distance(end, 0), 0, atol=1e-7)
        assert_true(body.distance(end + Vector3(0, side * 0.0001, 0), 0) > 0)
    assert_true(body.distance(center, 0) < 0)


def test_all_template_bodies_and_disc_spaces() raises:
    for sex in [MALE, FEMALE]:
        for height in [Float32(1.2), Float32(1.8288), Float32(2.5)]:
            var h = head_dimensions(Length(height, METER), sex)
            var t = h.torso.copy()
            var discs = torso_ligament_field(t, INTERVERTEBRAL_DISCS, RIGHT)
            for index in range(17):
                var field = torso_bone_field(t, TorsoBone(index), RIGHT)
                _body_contract(
                    field.sweeps[0],
                    t.centers[index],
                    t.heights[index],
                    t.widths[index],
                    t.depths[index],
                )
                var disc = discs.sweeps[index].copy()
                assert_true(disc.flat_y)
                var top = disc.stations[0].p
                var below = disc.stations[1].p
                assert_true(top.y > below.y)
                var midpoint = (top + below) * 0.5
                assert_true(disc.distance(midpoint, 0) < 0)
                assert_true(field.sweeps[0].distance(midpoint, 0) > 0)
                assert_true(discs.distance(t.centers[index]) > 0)
                if index < 16:
                    var next = torso_bone_field(t, TorsoBone(index + 1), RIGHT)
                    assert_true(next.sweeps[0].distance(midpoint, 0) > 0)
            var cervical = head_ligament_field(h, CERVICAL_DISCS, RIGHT)
            for index in range(1, 7):
                var field = head_bone_field(h, HeadBone(index))
                _body_contract(
                    field.sweeps[0],
                    h.centers[index],
                    h.heights[index],
                    h.widths[index],
                    h.depths[index],
                )
                var disc = cervical.sweeps[index - 1].copy()
                var top = disc.stations[0].p
                var below = disc.stations[1].p
                assert_true(top.y > below.y)
                var midpoint = (top + below) * 0.5
                assert_true(disc.distance(midpoint, 0) < 0)
                assert_true(field.sweeps[0].distance(midpoint, 0) > 0)
                assert_true(cervical.distance(h.centers[index]) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
