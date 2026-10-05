# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An animal's segments as rigid bodies in the z-up physics world."""

from extensions.animals.anatomy.mass import sample_mass
from extensions.animals.anatomy.physics import segment_bodies, to_physics
from extensions.animals.build import create_animal
from extensions.animals.options import ADULT, CROWD, MALE, animal_options
from extensions.animals.registry import FISH, RAT
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import METER, Length


def test_frames_turn_y_up_to_z_up() raises:
    var p = to_physics(Vector3(1, 2, 3))
    assert_equal(p.x, 3)
    assert_equal(p.y, 1)
    assert_equal(p.z, 2)


def test_segments_carry_their_sampled_mass() raises:
    var rat = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var mass = sample_mass(rat, rat.bind_pose(), Length(0.006, METER))
    var bodies = segment_bodies(rat, mass)
    var weighted = 0
    for b in mass.bones:
        weighted += 1 if b.mass > 0.0 else 0
    assert_equal(len(bodies), weighted)
    var total = 0.0
    var at = 0
    for i in range(len(mass.bones)):
        if mass.bones[i].mass <= 0.0:
            continue
        ref body = bodies[at]
        at += 1
        total += Float64(body.mass())
        var s = mass.bone(i, 0.0)
        var expect = to_physics(s.center)
        var got = body.world_center_of_mass()
        assert_almost_equal(got.x, expect.x, atol=1e-5)
        assert_almost_equal(got.y, expect.y, atol=1e-5)
        assert_almost_equal(got.z, expect.z, atol=1e-5)
        var inverse = body.inverse_inertia()
        for d in [0, 4, 8]:
            assert_true(inverse.elements[d] > 0.0)
    assert_almost_equal(total, Float64(mass.total().mass.value), rtol=1e-5)
    # A bone of no length keeps its body, turned no way.
    var flat = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var tip = flat.rig.find_joint("tail1")
    flat.rig.joints[tip] = flat.rig.joints[flat.rig.find_joint("tail0")]
    var flat_mass = sample_mass(flat, flat.bind_pose(), Length(0.006, METER))
    assert_true(len(segment_bodies(flat, flat_mass)) > 0)
    # A bone with no flesh has no body.
    mass.bones[0].mass = 0.0
    assert_equal(len(segment_bodies(rat, mass)), len(bodies) - 1)
    var fish = create_animal(FISH, animal_options(2))
    with assert_raises(contains="another rig"):
        _ = segment_bodies(fish, mass)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
