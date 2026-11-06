# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skirt's hem that swings: its four targets, their weights, and the
spring that the body's motion drives."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from materials.material import MaterialId
from math.matrix4 import Matrix4
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from extensions.village.sway import (
    Sway,
    add_sway_targets,
    sway_skirts,
    sway_name,
    sway_weights,
)
from math.vector3 import Vector3
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _piece(heights: List[Float32]) raises -> BufferGeometry:
    """Return a piece of one vertex at each height, on the +x side."""
    var flat = List[Float32]()
    for y in heights:
        flat.extend([Float32(0.2), y, 0])
    var piece = BufferGeometry()
    piece.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    return piece^


def test_the_hem_moves_most_and_the_waist_not_at_all() raises:
    var piece = _piece([1.0, 0.5, 0.0])
    assert_true(add_sway_targets(piece, 0.8, 0.1))
    assert_equal(piece.morph_count(), 5)
    assert_true(piece.morph_relative)
    assert_equal(piece.morph_target_name(0), "sway+x")
    assert_equal(piece.morph_target_name(3), "sway-z")
    ref forth = piece.morph_positions[0]
    # Over the skirt's top, no move; at the hem, the whole reach; between,
    # by the square of the fall.
    assert_equal(forth.component(0, 0), 0)
    var fall = Float32(0.3) / 0.8
    assert_almost_equal(forth.component(1, 0), 0.1 * fall * fall, atol=1e-6)
    assert_almost_equal(forth.component(2, 0), 0.1, atol=1e-6)
    assert_equal(forth.component(2, 1), 0)
    assert_almost_equal(piece.morph_positions[3].component(2, 2), -0.1)
    # The flare moves the hem out from the axis, along +x here, and up.
    ref flare = piece.morph_positions[4]
    assert_equal(piece.morph_target_name(4), "sway-flare")
    assert_almost_equal(flare.component(2, 0), 0.1, atol=1e-6)
    assert_almost_equal(flare.component(2, 1), 0.04, atol=1e-6)
    assert_equal(flare.component(0, 0), 0)
    # A piece that swings already, or that hangs wholly over the top, is
    # left alone.
    assert_false(add_sway_targets(piece, 0.8, 0.1))
    var high = _piece([1.0, 0.9])
    assert_false(add_sway_targets(high, 0.8, 0.1))
    assert_equal(high.morph_count(), 0)
    with assert_raises(contains="reach"):
        _ = add_sway_targets(high, 0.8, 2)
    with assert_raises(contains="reach"):
        _ = add_sway_targets(high, 0.8, -0.1)


def test_each_part_of_a_skirt_takes_the_targets() raises:
    var scene = Scene()
    var assets = Assets()
    var body = scene.add(Object3D())
    var hip = scene.attach(Object3D(), body)
    var meshes = List[Int]()
    var low = assets.geometries.add(_piece([1.0, 0.0]))
    var high = assets.geometries.add(_piece([1.0, 0.9]))
    for geometry in [low, high]:
        meshes.append(len(scene.skinned_meshes))
        scene.add_skinned_mesh(
            SkinnedMesh(
                geometry,
                MaterialId(0),
                body,
                Skeleton([Bone(hip, Matrix4())]),
            )
        )
    # The part that hangs below the top swings; the one over it does not.
    var swung = sway_skirts(scene, assets, meshes, 0.8, 0.1)
    assert_equal(len(swung), 1)
    assert_equal(swung[0], meshes[0])
    assert_equal(assets.geometries.get(low).morph_count(), 5)
    assert_equal(
        scene.skinned_meshes[meshes[0]].morph_target_dictionary["sway-z"], 3
    )
    assert_equal(assets.geometries.get(high).morph_count(), 0)
    # A garment that draws nothing has no part to swing.
    assert_equal(len(sway_skirts(scene, assets, List[Int](), 0.8, 0.1)), 0)


def test_an_offset_splits_into_four_weights() raises:
    var w = sway_weights(Vector3(0.05, 9, -0.2), 0.1)
    assert_almost_equal(w[0], 0.5, atol=1e-6)
    assert_equal(w[1], 0)
    assert_equal(w[2], 0)
    assert_equal(w[3], 1)
    var back = sway_weights(Vector3(-0.02, 0, 0.03), 0.1)
    assert_almost_equal(back[1], 0.2, atol=1e-6)
    assert_almost_equal(back[2], 0.3, atol=1e-6)
    var none = sway_weights(Vector3(1, 0, 1), 0)
    for k in range(4):
        assert_equal(none[k], 0)
    assert_equal(sway_name(1), "sway-x")
    assert_equal(sway_name(2), "sway+z")
    assert_equal(sway_name(4), "sway-flare")
    assert_equal(sway_name(7), "sway")


def test_a_hem_trails_a_run_and_swings_on_as_it_stops() raises:
    var sway = Sway()
    var dt = Float32(1) / 30
    # The first step only learns where the body stands.
    var at = Vector3(0, 0, 0)
    assert_equal(sway.step(at, 0, dt, 0.1).z, 0)
    # Speeding up along the body's own +z: the hem trails back.
    var speed = Float32(0)
    var least = Float32(0)
    for _ in range(30):
        speed = min(Float32(5), speed + 0.5)
        at = at + Vector3(0, 0, speed * dt)
        least = min(least, sway.step(at, 0, dt, 0.1).z)
    assert_true(least < -0.02)
    # A sudden stop throws it forward, past its rest.
    var most = Float32(-1)
    for _ in range(30):
        most = max(most, sway.step(at, 0, dt, 0.1).z)
    assert_true(most > 0)
    # At rest a while, it settles.
    for _ in range(300):
        _ = sway.step(at, 0, dt, 0.1)
    assert_almost_equal(sway.offset.z, 0, atol=1e-3)
    # A frame of no time leaves it as it is.
    var still = sway.step(at + Vector3(5, 0, 0), 0, 0, 0.1)
    assert_equal(still.x, sway.offset.x)


def test_a_hem_flares_as_the_body_spins_and_falls() raises:
    var dt = Float32(1) / 30
    # Standing still, it does not flare.
    var still = Sway()
    for _ in range(10):
        _ = still.step(Vector3(0, 0, 0), 0, dt, 0.1)
    assert_equal(still.flare, 0)
    # A whirlwind's spin, two turns a second, past a half turn each way.
    var spin = Sway()
    var turn = Float32(0)
    for _ in range(20):
        turn += 4 * Float32(pi) * dt
        if turn > Float32(pi):
            turn -= 2 * Float32(pi)
        _ = spin.step(Vector3(0, 0, 0), turn, dt, 0.1)
    assert_true(spin.flare > 0.9)
    # Then it settles.
    for _ in range(60):
        _ = spin.step(Vector3(0, 0, 0), turn, dt, 0.1)
    assert_true(spin.flare < 0.01)
    # Falling from a jump flares it too; rising does not.
    var jump = Sway()
    var y = Float32(1)
    _ = jump.step(Vector3(0, y, 0), 0, dt, 0.1)
    for _ in range(10):
        y += 3 * dt
        _ = jump.step(Vector3(0, y, 0), 0, dt, 0.1)
    assert_equal(jump.flare, 0)
    for _ in range(10):
        y -= 4 * dt
        _ = jump.step(Vector3(0, y, 0), 0, dt, 0.1)
    assert_true(jump.flare > 0.4)


def test_a_hem_swings_in_the_bodys_frame_and_within_reach() raises:
    # Turned a quarter about +y, the body's +z faces the world's +x: a run
    # along +x trails the hem along the body's -z.
    var sway = Sway()
    var dt = Float32(1) / 30
    var at = Vector3(0, 0, 0)
    _ = sway.step(at, Float32(pi) / 2, dt, 0.1)
    var speed = Float32(0)
    var offset = Vector3(0, 0, 0)
    for _ in range(10):
        speed += 0.5
        at = at + Vector3(speed * dt, 0, 0)
        offset = sway.step(at, Float32(pi) / 2, dt, 0.1)
    assert_true(offset.z < 0)
    assert_true(abs(offset.x) < abs(offset.z))
    # A great jolt is held within the reach, and a long frame is taken in
    # short steps.
    var jolt = sway.step(at + Vector3(0, 0, 30), 0, 2, 0.05)
    var length = (jolt.x * jolt.x + jolt.z * jolt.z) ** 0.5
    assert_true(length <= 0.05 + 1e-5)
    # A reach under none holds the hem at rest.
    var held = sway.step(at + Vector3(0, 0, 60), 0, 0.1, -1)
    assert_equal(held.x, 0)
    assert_equal(held.z, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
