# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An animal's segments as rigid bodies in the z-up physics world."""

from extensions.animals.anatomy.mass import sample_mass
from extensions.animals.anatomy.physics import (
    segment_bodies,
    segment_chain,
    to_physics,
)
from extensions.animals.build import create_animal
from extensions.animals.options import ADULT, CROWD, MALE, animal_options
from extensions.animals.registry import FISH, RAT
from extensions.animals.rig import NO_BONE
from extensions.physics.body import STATIC
from extensions.physics.world import PhysicsWorld
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import METER, SECOND, Duration, Length


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


def test_segments_form_a_chain_of_ball_joints() raises:
    var rat = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var mass = sample_mass(rat, rat.bind_pose(), Length(0.006, METER))
    var world = PhysicsWorld()
    var chain = segment_chain(rat, mass, world)
    assert_equal(len(chain.bodies), len(segment_bodies(rat, mass)))
    assert_equal(world.body_count(), len(chain.bodies))
    # Every bone with flesh hangs from another one, but the root.
    assert_equal(len(chain.joints), len(chain.bodies) - 1)
    assert_equal(world.joint_count(), len(chain.joints))
    # Each joint is at the head of its lower bone, where that body's
    # frame starts, and has no error in the bind pose.
    for joint in world.joints:
        var at = joint.anchor(world.bodies)
        var head = world.bodies[joint.b.value].position
        assert_almost_equal(at.x, head.x, atol=1e-6)
        assert_almost_equal(at.y, head.y, atol=1e-6)
        assert_almost_equal(at.z, head.z, atol=1e-6)
        assert_true(joint.separation(world.bodies).length() < 1e-6)
        assert_true(joint.a.value < joint.b.value)
    # Hung by its first segment, the rat stays in one piece. The segments
    # make no contacts here: in the bind pose, capsules that are not
    # joined overlap.
    world.bodies[chain.bodies[0].value].set_kind(STATIC)
    for id in chain.bodies:
        world.bodies[id.value].collides = False
    var last = chain.bodies[len(chain.bodies) - 1].value
    var start = world.bodies[last].position
    var apart = Float32(0)
    for _ in range(120):
        world.step(Duration(1.0 / 240.0, SECOND))
        for joint in world.joints:
            apart = max(apart, joint.separation(world.bodies).length())
    # The rat is 0.2 m long. Its smallest segments weigh a tenth of a
    # gram and whip, so the joints hold within a centimeter at this step.
    assert_true(apart < 0.01)
    assert_true((world.bodies[last].position - start).length() > 0.01)


def test_a_bone_with_no_flesh_is_skipped_in_the_chain() raises:
    var rat = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var mass = sample_mass(rat, rat.bind_pose(), Length(0.006, METER))
    # Find a bone with flesh whose parent and grandparent have flesh, and
    # take the flesh off the parent.
    var child = -1
    for i in range(len(rat.rig.bones)):
        var parent = rat.rig.bones[i].parent
        if parent == NO_BONE or mass.bones[i].mass == 0.0:
            continue
        var grandparent = rat.rig.bones[parent.value].parent
        if (
            grandparent != NO_BONE
            and mass.bones[parent.value].mass > 0.0
            and mass.bones[grandparent.value].mass > 0.0
        ):
            child = i
    assert_true(child >= 0)
    var parent = rat.rig.bones[child].parent.value
    var grandparent = rat.rig.bones[parent].parent.value
    var whole = PhysicsWorld()
    var before = segment_chain(rat, mass, whole)
    mass.bones[parent].mass = 0.0
    var world = PhysicsWorld()
    var chain = segment_chain(rat, mass, world)
    assert_equal(len(chain.bodies), len(before.bodies) - 1)
    # The child now hangs from its grandparent, at its own head.
    var slot = List[Int]()
    var next = 0
    for i in range(len(rat.rig.bones)):
        if mass.bones[i].mass == 0.0:
            slot.append(-1)
        else:
            slot.append(next)
            next += 1
    var found = False
    for joint in world.joints:
        if joint.b.value == slot[child]:
            found = True
            assert_equal(joint.a.value, slot[grandparent])
    assert_true(found)
    # A root with no flesh leaves its children with no joint to it.
    var bare = sample_mass(rat, rat.bind_pose(), Length(0.006, METER))
    for i in range(len(rat.rig.bones)):
        if rat.rig.bones[i].parent == NO_BONE:
            bare.bones[i].mass = 0.0
    var loose = PhysicsWorld()
    var parts = segment_chain(rat, bare, loose)
    assert_true(len(parts.joints) < len(parts.bodies) - 1)
    var fish = create_animal(FISH, animal_options(2))
    with assert_raises(contains="another rig"):
        _ = segment_chain(fish, mass, world)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
