# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skirt that the legs push out of the way: its target, the push, and
where the cloth ends up."""

from core.assets import Assets
from core.scene import Scene
from extensions.attire.outfit import Outfit
from extensions.attire.skirt import skirt_top
from extensions.humanoid.rig.joints import RIGHT_THIGH
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.village.clothes import MADDER, WALNUT, WELD, village_outfit
from extensions.village.battle import HEM_NEAR
from extensions.village.hem_push import (
    HEM_GAP,
    HEM_TARGET_NAME,
    add_hem_push,
)
from extensions.village.residents import Body
from math.vector3 import Vector3
from objects.skinned_mesh import SkinnedMesh
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)
from tests._village_arena import Arena, arena_parameters
from units.si import DEGREE, INCH, Angle, Length


def _body(mut scene: Scene, mut assets: Assets) raises -> Body:
    """Return a man in a tunic whose skirt reaches the thighs."""
    return Body(
        scene,
        assets,
        HumanoidSpec(Length(68.0, INCH), MALE),
        village_outfit(MADDER, WELD, WALNUT, False),
        500,
        8,
    )


def test_each_skirt_takes_a_push_at_full_weight() raises:
    var assets = Assets()
    var scene = Scene()
    var body = _body(scene, assets)
    assert_true(len(body.skirts) > 0)
    # A body that keeps no hems pushes nothing.
    scene.update()
    assert_equal(body.push_hems(scene, assets), 0)
    body.keep_hems(scene, assets)
    assert_equal(len(body.hems), len(body.skirts))
    for k in range(len(body.hems)):
        ref push = body.hems[k]
        ref mesh = scene.skinned_meshes[push.mesh]
        ref piece = assets.geometries.get(mesh.geometry)
        assert_equal(push.target, piece.morph_count() - 1)
        assert_equal(piece.morph_target_name(push.target), HEM_TARGET_NAME)
        assert_equal(mesh.morph_influence(push.target), 1)
        assert_equal(len(push.legs), 4)
        assert_true(len(push.skirt) > 0)


def test_a_raised_knee_pushes_the_cloth_out_of_the_leg() raises:
    var assets = Assets()
    var scene = Scene()
    var body = _body(scene, assets)
    body.keep_hems(scene, assets)
    scene.update()
    var standing = body.push_hems(scene, assets)
    for k in range(len(body.hems)):
        assert_true(body.hems[k].clearance(scene, assets) >= HEM_GAP - 1.0e-3)
    # The right knee up, forward or back: one of the two goes through the
    # skirt as it stood. The push takes the cloth out again.
    var thigh = body.person.bones[RIGHT_THIGH.value]
    var through = False
    var raised = 0
    for degrees in [Float32(-80), Float32(80)]:
        scene.node(thigh).set_rotation_from_axis_angle(
            Vector3(1, 0, 0), Angle(degrees, DEGREE)
        )
        scene.update()
        for k in range(len(body.hems)):
            var before = body.hems[k].clearance(scene, assets)
            through = through or before < HEM_GAP - 1.0e-2
        raised = max(raised, body.push_hems(scene, assets))
        for k in range(len(body.hems)):
            var after = body.hems[k].clearance(scene, assets)
            assert_true(after >= HEM_GAP - 5.0e-3)
    assert_true(through)
    assert_true(raised > standing)


def test_a_body_with_no_skirt_keeps_no_hems() raises:
    var assets = Assets()
    var scene = Scene()
    var body = Body(
        scene,
        assets,
        HumanoidSpec(Length(68.0, INCH), MALE),
        Outfit(),
        500,
        8,
    )
    body.keep_hems(scene, assets)
    assert_equal(len(body.hems), 0)


def test_a_piece_with_no_skirt_or_no_relative_targets_takes_no_push() raises:
    var assets = Assets()
    var scene = Scene()
    var body = _body(scene, assets)
    var mesh = body.skirts[0]
    # A top under every vertex leaves no skirt.
    assert_false(add_hem_push(scene, assets, mesh, body.person, -100))
    ref skinned = scene.skinned_meshes[mesh]
    var bare = assets.geometries.get(skinned.geometry).clone()
    var absolute = bare.clone()
    absolute.morph_relative = False
    bare.morph_positions.clear()
    bare.morph_names.clear()
    var top = skirt_top(body.person.rig)
    var material = skinned.material
    var node = skinned.node
    var skeleton = skinned.skeleton.copy()
    var bind = skinned.bind_matrix
    var ids = [assets.geometries.add(bare^), assets.geometries.add(absolute^)]
    for id in ids:
        var at = len(scene.skinned_meshes)
        scene.add_skinned_mesh(
            SkinnedMesh(
                id,
                material,
                node,
                skeleton.copy(),
                bind,
            )
        )
        assert_false(add_hem_push(scene, assets, at, body.person, top))


def test_a_fighter_near_the_camera_keeps_their_skirt_out_of_their_legs() raises:
    var arena = Arena(arena_parameters(1, 0, 5, ally=True))
    arena.battle.keep_hems(arena.scene, arena.assets)
    # The doors open for the companion.
    assert_equal(len(arena.battle.friends()), 1)
    # The companion wears a skirt; the bandit does not.
    var skirted = -1
    for k in range(len(arena.battle.people)):
        if len(arena.battle.people[k].body.hems) > 0:
            skirted = k
    assert_true(skirted >= 0)
    ref body = arena.battle.people[skirted].body
    ref hem = body.hems[0]
    arena.scene.update()
    var at = arena.scene.world_matrix(body.carrier).transform_point(
        Vector3(0, 0, 0)
    )
    var shown = arena.battle.push_hems(
        arena.scene, arena.assets, at + Vector3(0, 1, HEM_NEAR / 2)
    )
    assert_true(shown >= 0)
    assert_equal(
        arena.scene.skinned_meshes[hem.mesh].morph_influence(hem.target), 1
    )
    # Far from the camera, or hidden, the skirt is as it is skinned.
    arena.scene.update()
    _ = arena.battle.push_hems(
        arena.scene, arena.assets, at + Vector3(0, 0, 3 * HEM_NEAR)
    )
    assert_equal(
        arena.scene.skinned_meshes[hem.mesh].morph_influence(hem.target), 0
    )
    arena.scene.node(body.carrier).visible = False
    arena.scene.update()
    _ = arena.battle.push_hems(arena.scene, arena.assets, at)
    assert_equal(
        arena.scene.skinned_meshes[hem.mesh].morph_influence(hem.target), 0
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
