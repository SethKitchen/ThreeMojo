# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the game humanoid's rig, its skin weights and its clips."""

from animation.animation_mixer import AnimationAction, AnimationMixer
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.rig.clips import (
    Pose,
    clip_from_poses,
    idle_clip,
    joint_rotation,
    jump_clip,
    run_clip,
    walk_clip,
    wave_clip,
)
from extensions.humanoid.fidelity import (
    CANONICAL_RECIPE,
    ENGINEERING_USE,
    FIDELITY_KEY,
    GAME_RECIPE,
    humanoid_provenance,
    require_bake_provenance,
)
from extensions.humanoid.rig.game import (
    add_game_humanoid,
    game_build_settings,
    carry_attributes,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    JOINT_COUNT,
    LEFT_FOREARM,
    LEFT_HAND,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_HAND,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
    Joint,
    humanoid_rig,
    joint_label,
    joint_parent,
    named_joints,
)
from extensions.humanoid.rig.weights import (
    _quantized_coordinate,
    _weld_key,
    _welded_edges,
    bone_weights,
    part_legs,
    rigid_weights,
    skin_weights,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.torso.body import body_skin_mesh
from extensions.humanoid.spec import HumanoidSpec
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from renderers.renderer import available_workers
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration, FOOT, Length


def _spec() -> HumanoidSpec:
    """Return the six-foot male template."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def _rig() raises -> HumanoidRig:
    """Return the template's rig, placed on a coarse skin."""
    return humanoid_rig(
        _spec(), body_skin_mesh(_spec(), 12, available_workers(), 0.014)
    )


def _mesh(points: List[Vector3], triangles: List[Int]) raises -> BufferGeometry:
    """Return an indexed mesh of `points`."""
    var flat = List[Float32]()
    for p in points:  # pragma: no branch
        flat.append(p.x)
        flat.append(p.y)
        flat.append(p.z)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    if len(triangles) > 0:
        mesh.set_index(triangles.copy())
    return mesh^


def _bones(mut scene: Scene, rig: HumanoidRig) raises -> List[NodeId]:
    """Return one scene node per joint, hung as the rig hangs them."""
    var bones = List[NodeId]()
    var root = scene.add(Object3D())
    for joint in named_joints():  # pragma: no branch
        var node = Object3D()
        var at = rig.local(joint)
        node.set_position(at.x, at.y, at.z)
        var hang = root
        if joint != HIPS:
            hang = bones[joint_parent(joint).value]
        bones.append(scene.attach(node^, hang))
    return bones^


def test_joints_are_named_and_hung() raises:
    assert_equal(len(named_joints()), JOINT_COUNT)
    assert_equal(joint_label(RIGHT_SHIN), "rightShin")
    assert_equal(joint_label(Joint(-1)), "joint")
    assert_false(Joint(JOINT_COUNT).is_valid())
    assert_equal(joint_parent(HIPS), HIPS)
    assert_equal(joint_parent(HEAD), NECK)
    assert_equal(joint_parent(LEFT_HAND), LEFT_FOREARM)
    assert_equal(joint_parent(RIGHT_TOES), RIGHT_FOOT)
    with assert_raises(contains="named joint"):
        _ = joint_parent(Joint(40))
    assert_equal(RIGHT_UPPER_ARM.side(), 1)
    assert_equal(LEFT_UPPER_ARM.side(), -1)
    assert_equal(RIGHT_THIGH.side(), 1)
    assert_equal(LEFT_SHIN.side(), -1)
    assert_equal(CHEST.side(), 0)
    assert_equal(Joint(40).side(), 0)


def test_the_rig_stands_on_the_anatomy() raises:
    var rig = _rig()
    # Up the spine, the joints rise.
    assert_true(rig.at(SPINE).y > rig.at(HIPS).y)
    assert_true(rig.at(CHEST).y > rig.at(SPINE).y)
    assert_true(rig.at(NECK).y > rig.at(CHEST).y)
    assert_true(rig.at(HEAD).y > rig.at(NECK).y)
    # Down each leg, they fall; the toes lie ahead of the ankle.
    assert_true(rig.at(RIGHT_SHIN).y < rig.at(RIGHT_THIGH).y)
    assert_true(rig.at(RIGHT_FOOT).y < rig.at(RIGHT_SHIN).y)
    assert_true(rig.at(RIGHT_TOES).z > rig.at(RIGHT_FOOT).z)
    # The sides mirror.
    assert_true(abs(rig.at(RIGHT_THIGH).x + rig.at(LEFT_THIGH).x) < 1e-5)
    assert_true(rig.at(RIGHT_UPPER_ARM).x > 0)
    # The fingertips hang below the wrist; the crown tops the head.
    assert_true(rig.ends[RIGHT_HAND.value].y < rig.at(RIGHT_HAND).y)
    assert_true(rig.ends[HEAD.value].y > rig.at(HEAD).y)
    # A bone stands where its parent puts it.
    var shin = rig.local(RIGHT_SHIN)
    var gap = rig.at(RIGHT_SHIN) - rig.at(RIGHT_THIGH)
    assert_true((shin - gap).length() < 1e-6)
    assert_true((rig.local(HIPS) - rig.at(HIPS)).length() < 1e-6)
    with assert_raises(contains="named joint"):
        _ = rig.at(Joint(-3))
    with assert_raises(contains="one place per joint"):
        _ = HumanoidRig(List[Vector3](), List[Vector3](), 1.8)
    with assert_raises(contains="one place per joint"):
        _ = HumanoidRig(rig.joints.copy(), List[Vector3](), 1.8)


def test_the_skin_is_weighted_to_its_bones() raises:
    var rig = _rig()
    var skin = body_skin_mesh(_spec(), 12, available_workers(), 0.014)
    skin_weights(skin, rig)
    ref placed = skin.attribute_view(String(POSITION))
    ref bones = skin.attribute_view(String(SKIN_INDEX))
    ref weights = skin.attribute_view(String(SKIN_WEIGHT))
    var knee = rig.at(RIGHT_SHIN)
    for v in range(placed.count()):  # pragma: no branch
        var total = Float32(0)
        for k in range(4):  # pragma: no branch
            total += weights.component(v, k)
            # A limb never turns the far side of the body.
            var joint = Joint(Int(bones.component(v, k)))
            if weights.component(v, k) > 0.01:
                assert_true(
                    Float32(joint.side()) * placed.vector3(v).x > -0.011
                )
        assert_true(abs(total - 1) < 1e-4)
        # By the knee, the thigh and the shin turn the skin.
        var p = placed.vector3(v)
        if (p - knee).length() < 0.06:
            var top = Int(bones.component(v, 0))
            assert_true(top == RIGHT_THIGH.value or top == RIGHT_SHIN.value)
    # Through the air, every bone counts, and the weights add to one.
    var air = bone_weights(rig, rig.at(CHEST))
    var sum = Float32(0)
    for w in air:  # pragma: no branch
        sum += w
    assert_true(abs(sum - 1) < 1e-4)
    assert_true(air[CHEST.value] > air[RIGHT_SHIN.value])
    # A rig whose bones have no length still weighs a point, and a skin
    # with a triangle folded onto one corner still binds.
    var point = List[Vector3](length=JOINT_COUNT, fill=Vector3(0, 0, 0))
    var flat = HumanoidRig(point.copy(), point.copy(), 1.8288)
    var lone = bone_weights(flat, Vector3(0.1, 0.2, 0))
    assert_true(lone[HIPS.value] > 0)
    var folded = _mesh(
        [Vector3(0, 0.05, 0), Vector3(0, 0.05, 0), Vector3(0, 0.06, 0)],
        [0, 1, 2],
    )
    skin_weights(folded, flat)
    assert_true(folded.has_attribute(String(SKIN_INDEX)))


def test_a_part_of_the_skin_is_turned_by_the_joints_it_may_be() raises:
    var rig = _rig()
    var wrist = rig.at(RIGHT_HAND)
    # A strip down the hand, not indexed, turned only by the hand and
    # its forearm.
    var strip: List[Vector3] = [
        wrist,
        wrist + Vector3(0.01, -0.03, 0),
        wrist + Vector3(-0.01, -0.03, 0),
        wrist + Vector3(0.0, -0.08, 0.005),
        wrist + Vector3(0.01, -0.12, 0),
        wrist + Vector3(-0.01, -0.12, 0),
    ]
    var hand = _mesh(strip, List[Int]())
    var allowed: List[Joint] = [RIGHT_FOREARM, RIGHT_HAND]
    skin_weights(hand, rig, allowed)
    ref bones = hand.attribute_view(String(SKIN_INDEX))
    ref weights = hand.attribute_view(String(SKIN_WEIGHT))
    for v in range(len(strip)):  # pragma: no branch
        for k in range(4):  # pragma: no branch
            if weights.component(v, k) > 0:
                var b = Int(bones.component(v, k))
                assert_true(b == RIGHT_FOREARM.value or b == RIGHT_HAND.value)
    # A speck far from every bone falls back on the nearest through the
    # air.
    var speck: List[Vector3] = [
        Vector3(3, 3, 3),
        Vector3(3.01, 3, 3),
        Vector3(3, 3.01, 3),
    ]
    var far = _mesh(speck, [0, 1, 2])
    skin_weights(far, rig)
    assert_true(far.has_attribute(String(SKIN_WEIGHT)))
    with assert_raises(contains="named joint"):
        skin_weights(far, rig, [Joint(77)])
    # A rigid part is wholly one joint's.
    rigid_weights(far, HEAD)
    assert_equal(
        far.attribute_view(String(SKIN_INDEX)).component(1, 0),
        Float32(HEAD.value),
    )
    assert_equal(far.attribute_view(String(SKIN_WEIGHT)).component(2, 0), 1)
    with assert_raises(contains="named joint"):
        rigid_weights(far, Joint(-1))


def test_the_legs_part_below_the_crotch() raises:
    var rig = _rig()
    # One triangle across the midline low between the legs, one high on
    # the belly, and one wholly on the right.
    var points: List[Vector3] = [
        Vector3(0.02, -0.3, 0.0),
        Vector3(-0.01, -0.3, 0.0),
        Vector3(0.02, -0.32, 0.0),
        Vector3(0.02, 0.1, 0.1),
        Vector3(-0.02, 0.1, 0.1),
        Vector3(0.0, 0.12, 0.1),
        Vector3(0.1, -0.3, 0.0),
        Vector3(0.12, -0.3, 0.0),
        Vector3(0.1, -0.32, 0.0),
        Vector3(-0.03, -0.3, 0.0),
        Vector3(0.01, -0.3, 0.0),
        Vector3(-0.03, -0.32, 0.0),
    ]
    var mesh = _mesh(points, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
    var colors = List[Float32](length=3 * len(points), fill=1)
    mesh.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    skin_weights(mesh, rig)
    part_legs(mesh, rig.at(HIPS).y - 0.06)
    # The low triangles each took a copy of their far corner, turned by
    # the side's own joints; the belly's was left alone.
    assert_equal(mesh.attribute_view(String(POSITION)).count(), 14)
    ref bones = mesh.attribute_view(String(SKIN_INDEX))
    for k in range(4):  # pragma: no branch
        var right = Joint(Int(bones.component(12, k)))
        assert_true(right.side() >= 0)
        var left = Joint(Int(bones.component(13, k)))
        assert_true(left.side() <= 0)
    assert_equal(mesh.index[4], 4)
    assert_true(mesh.has_attribute(String(COLOR)))


def test_clips_play_on_the_bones() raises:
    var rig = _rig()
    var scene = Scene()
    var bones = _bones(scene, rig)
    var walk = walk_clip(bones, rig)
    assert_equal(walk.name, "walk")
    assert_equal(len(walk.tracks), JOINT_COUNT + 1)
    assert_true(abs(walk.duration().value - 1.1) < 1e-4)
    assert_equal(run_clip(bones, rig).name, "run")
    assert_equal(idle_clip(bones, rig).name, "idle")
    assert_equal(jump_clip(bones, rig).name, "jump")
    assert_equal(wave_clip(bones, rig).name, "wave")
    var mixer = AnimationMixer()
    var playing = mixer.add(AnimationAction(walk^))
    mixer.action(playing).play()
    var before = scene.node(bones[RIGHT_THIGH.value]).quaternion
    mixer.update(scene, Duration(0.3, SECOND))
    var after = scene.node(bones[RIGHT_THIGH.value]).quaternion
    assert_true(abs(after.w - before.w) + abs(after.x - before.x) > 0.01)
    # A turn of nothing is no turn; a pose half way is half the turn.
    var still = joint_rotation(Vector3(0, 0, 0))
    assert_equal(still.w, 1)
    var bent = Pose()
    bent.turn(RIGHT_SHIN, 60)
    var half = Pose().blend(bent, 0.5)
    assert_equal(half.angles[RIGHT_SHIN.value].x, 30)
    var poses = List[Pose]()
    poses.append(Pose())
    with assert_raises(contains="two poses"):
        _ = clip_from_poses("one", bones, rig, poses, 1)
    poses.append(Pose())
    with assert_raises(contains="above zero"):
        _ = clip_from_poses("instant", bones, rig, poses, 0)
    with assert_raises(contains="one bone per joint"):
        _ = clip_from_poses("none", List[NodeId](), rig, poses, 1)


def test_a_game_humanoid_is_built_bound_and_light() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = add_game_humanoid(
        scene,
        assets,
        root,
        _spec(),
        3000,
        12,
        8,
        8,
        guides=12,
        followers=1,
        workers=available_workers(),
    )
    var expected = humanoid_provenance(
        _spec(),
        game_build_settings(3000, 12, 8, 8, guides=12, followers=1),
        String(CANONICAL_RECIPE),
        String(GAME_RECIPE),
        "unverified-converted-ICTF-THRS",
    )
    require_bake_provenance(scene.get(person.root).user_data, expected)
    assert_equal(len(person.bones), JOINT_COUNT)
    assert_equal(len(person.skins), 3)
    assert_equal(len(person.strands), 1)
    assert_equal(scene.node(person.bones[HEAD.value]).name, "head")
    var triangles = 0
    for k in person.skins:  # pragma: no branch
        ref skin = assets.geometries.get(scene.skinned_meshes[k].geometry)
        assert_true(skin.has_attribute(String(SKIN_WEIGHT)))
        assert_true(skin.has_attribute(String(COLOR)))
        triangles += skin.triangle_count()
    # Within its budget, give or take the copies that part the legs.
    assert_true(triangles <= 3000)
    # The hair's shell and the two eyes hang from the head.
    assert_equal(len(scene.meshes), 3)
    # With no budget, or one it already keeps within, the skin is drawn
    # whole; looks given are used.
    var whole = add_game_humanoid(
        scene, assets, root, _spec(), 0, 12, 8, 8, workers=available_workers()
    )
    var paint = scene.skinned_meshes[person.skins[0]].material
    var roomy = add_game_humanoid(
        scene,
        assets,
        root,
        _spec(),
        1000000,
        12,
        8,
        8,
        skin_paint=paint,
        eye_paint=paint,
        workers=available_workers(),
    )
    assert_equal(scene.skinned_meshes[roomy.skins[0]].material, paint)
    var full = 0
    for k in whole.skins:  # pragma: no branch
        full += assets.geometries.get(
            scene.skinned_meshes[k].geometry
        ).triangle_count()
    assert_true(full > triangles)


def test_colors_are_carried_to_a_decimated_skin() raises:
    var source = _mesh(
        [Vector3(0, 0, 0), Vector3(0.5, 0, 0), Vector3(0, 0.5, 0)], [0, 1, 2]
    )
    var colors: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    source.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var target = _mesh([Vector3(0.49, 0.001, 0), Vector3(0.001, 0.001, 0)], [])
    carry_attributes(source, target)
    ref carried = target.attribute_view(String(COLOR))
    assert_equal(carried.component(0, 1), 1)
    assert_equal(carried.component(1, 0), 1)


def test_weld_hash_collisions_do_not_join_distinct_positions() raises:
    var p = Vector3(0.00001001, 0.00001001, 0.00108001)
    var graph = _welded_edges([Vector3(0, 0, 0), p, p], List[Int]())
    var y_collision = _welded_edges(
        [Vector3(0, 0, 0), Vector3(0, 0.00001001, 9.999831)], List[Int]()
    )
    assert_equal(y_collision[0][1], 1)
    var first = graph[0][0]
    var second = graph[0][1]
    var third = graph[0][2]
    assert_equal(first, 0)
    assert_equal(second, 1)
    assert_equal(third, 1)


def test_weld_quantization_rejects_each_invalid_axis_before_skin_writes() raises:
    var rig = _rig()
    var invalid: List[Float32] = [
        bitcast[DType.float32](UInt32(0x7FC00000)),
        bitcast[DType.float32](UInt32(0x7F800000)),
        bitcast[DType.float32](UInt32(0xFF800000)),
        1e14,
        -1e14,
        2e14,
        -2e14,
        1e34,
        -1e34,
        # First rejected positive coordinate and first rejected negative
        # neighbor, from exact binary32 product rounding at +/-2**63.
        bitcast[DType.float32](UInt32(0x56A7C5AC)),
        bitcast[DType.float32](UInt32(0xD6A7C5AD)),
    ]
    for axis in range(3):
        for value in invalid:
            var p = Vector3(
                value if axis == 0 else Float32(0),
                value if axis == 1 else Float32(0),
                value if axis == 2 else Float32(0),
            )
            # An invalid later point cannot reach a candidate conversion.
            var points: List[Vector3] = [Vector3(0, 0, 0), p]
            with assert_raises(contains="Skin positions"):
                _ = _welded_edges(points, [])
            for existing in [False, True]:
                var skin = _mesh(points, [])
                var before = skin.clone_attribute(String(POSITION)).data.copy()
                if existing:
                    skin.set_attribute(
                        String(SKIN_INDEX), BufferAttribute([7.0, 6, 5, 4], 4)
                    )
                    skin.set_attribute(
                        String(SKIN_WEIGHT),
                        BufferAttribute([0.4, 0.3, 0.2, 0.1], 4),
                    )
                with assert_raises(contains="Skin positions"):
                    skin_weights(skin, rig)
                assert_equal(skin.has_attribute(String(SKIN_INDEX)), existing)
                assert_equal(skin.has_attribute(String(SKIN_WEIGHT)), existing)
                if existing:
                    assert_equal(
                        skin.clone_attribute(String(SKIN_INDEX)).data,
                        [Float32(7), 6, 5, 4],
                    )
                    assert_equal(
                        skin.clone_attribute(String(SKIN_WEIGHT)).data,
                        [Float32(0.4), 0.3, 0.2, 0.1],
                    )
                # Compare raw bits so an unchanged NaN compares equal.
                ref after = skin.attribute_view(String(POSITION))
                for k in range(len(before)):
                    assert_equal(
                        bitcast[DType.uint32](after.data[k]),
                        bitcast[DType.uint32](before[k]),
                    )
                assert_equal(len(skin.index), 0)


def test_weld_quantization_accepts_exact_integer_domain_neighbors() raises:
    # Independent binary32 oracle: rounded products are 2**63 - 2**40
    # and -2**63. Their adjacent outer coordinates are rejected above.
    var positive = bitcast[DType.float32](UInt32(0x56A7C5AB))
    var negative = bitcast[DType.float32](UInt32(0xD6A7C5AC))
    assert_equal(_quantized_coordinate(positive), 9223370937343148032)
    assert_equal(_quantized_coordinate(negative), Int.MIN)
    assert_equal(_quantized_coordinate(-positive), -9223370937343148032)
    assert_equal(_quantized_coordinate(0), 0)
    assert_equal(_quantized_coordinate(-0.0), 0)
    for axis in range(3):
        for value in [positive, negative, -positive]:
            var p = Vector3(
                value if axis == 0 else Float32(0),
                value if axis == 1 else Float32(0),
                value if axis == 2 else Float32(0),
            )
            var graph = _welded_edges([Vector3(0, 0, 0), p, p], [])
            assert_equal(graph[0], [0, 1, 1])


def test_weld_hash_has_explicit_modular_arithmetic() raises:
    # Exact integer products, masked to 64 bits, give these constants.
    # Products overflow signed Int even for otherwise supported positions.
    assert_equal(_weld_key(Int.MAX, Int.MIN, -1), UInt64(0xF4242))
    assert_equal(_weld_key(Int.MIN, 0, 0), UInt64(0x8000000000000000))
    assert_equal(_weld_key(1 << 62, 1 << 61, 17), UInt64(0x2000000000000011))
    assert_equal(_weld_key(-1, -1, -1), UInt64(0xFFFFFFFFFFFFFF93))


def test_weld_ordinary_grid_and_adjacency_are_unchanged() raises:
    var graph = _welded_edges(
        [
            Vector3(0.125, -0.25, 0.5),
            Vector3(0.125001, -0.250001, 0.500001),
            Vector3(-0.125, 0.25, -0.5),
            Vector3(-0.0, 0, 0),
            Vector3(0.000001, -0.000001, 0),
            Vector3(0.00001, 0, 0),
        ],
        [0, 2, 3, 1, 2, 4, 0, 0, 5],
    )
    assert_equal(graph[0], [0, 0, 2, 3, 3, 5])
    assert_equal(graph[1][0], [2, 3, 5])
    assert_equal(graph[1][1], List[Int]())
    assert_equal(graph[1][2], [0, 3])
    assert_equal(graph[1][3], [2, 0])
    assert_equal(graph[1][4], List[Int]())
    assert_equal(graph[1][5], [0])


def test_attribute_transfer_searches_past_the_first_populated_ring() raises:
    var source = _mesh(
        [Vector3(-0.0099, -0.0099, -0.0099), Vector3(0.0201, 0.0099, 0.0099)],
        [],
    )
    source.set_attribute(
        String(COLOR), BufferAttribute([1.0, 0.0, 0.0, 0.0, 1.0, 0.0], 3)
    )
    var target = _mesh([Vector3(0.0099, 0.0099, 0.0099)], [])
    carry_attributes(source, target)
    assert_equal(target.attribute_view(String(COLOR)).component(0, 1), 1)
    var empty = _mesh([], [])
    with assert_raises(contains="source vertices"):
        carry_attributes(empty, target)


def test_attribute_transfer_accepts_two_empty_meshes() raises:
    var source = _mesh([], [])
    source.set_attribute(String(COLOR), BufferAttribute(List[Float32](), 3))
    var target = _mesh([], [])
    carry_attributes(source, target)
    assert_equal(target.attribute_view(String(POSITION)).count(), 0)
    ref colors = target.attribute_view(String(COLOR))
    assert_equal(colors.count(), 0)
    assert_equal(colors.item_size, 3)


def test_game_builder_refuses_engineering_before_scene_edits() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var before = scene.count()
    with assert_raises(contains="Engineering use is unsupported"):
        _ = add_game_humanoid(scene, assets, root, _spec(), use=ENGINEERING_USE)
    assert_equal(scene.count(), before)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
