# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for an archer's longbow and quiver."""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from core.scene import Scene
from extensions.attire.archery import (
    BRACE,
    QUIVER_ARROWS,
    equip_archer,
    hip_quiver,
    longbow,
    sweep,
)
from materials.material import physical_material
from math.vector3 import Vector3
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from tests._attire_people import coarse_person
from units.si import METER, Length

comptime YEW = Color(150, 104, 58)
comptime WRAP = Color(70, 46, 30)
comptime FLAX = Color(226, 220, 196)


def _bounds(mesh: BufferGeometry) raises -> Tuple[Vector3, Vector3]:
    """Return the lowest and highest corner of a mesh's box."""
    ref placed = mesh.attribute_view(String(POSITION))
    var low = Vector3(1e9, 1e9, 1e9)
    var high = Vector3(-1e9, -1e9, -1e9)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
    return (low, high)


def test_a_sweep_rings_its_path() raises:
    var path: List[Vector3] = [Vector3(0, 0, 0), Vector3(0, 1, 0)]
    var radii: List[Float32] = [0.1, 0.2]
    var tube = sweep(path, radii, 6)
    assert_equal(tube.vertex_count(), 12)
    assert_equal(tube.triangle_count(), 12)
    ref placed = tube.attribute_view(String(POSITION))
    ref normals = tube.attribute_view(String(NORMAL))
    # Each ring stands its radius from the path, its normals pointing out.
    for v in range(12):
        var p = placed.vector3(v)
        var r = Vector3(p.x, 0, p.z).length()
        assert_almost_equal(r, radii[v // 6], atol=1e-5)
        assert_almost_equal(normals.vector3(v).length(), 1, atol=1e-5)
    with assert_raises(contains="two points"):
        _ = sweep([Vector3(0, 0, 0)], [Float32(0.1)], 6)
    with assert_raises(contains="one radius"):
        _ = sweep(path, [Float32(0.1)], 6)
    with assert_raises(contains="three sides"):
        _ = sweep(path, radii, 2)


def test_a_longbow_is_braced_and_painted() raises:
    var bow = longbow(Length(1.8, METER), YEW, WRAP, FLAX)
    var box = _bounds(bow)
    # Tip to tip, as tall as asked; the grip stands the brace height
    # behind the string.
    assert_almost_equal(box[1].y - box[0].y, 1.8, atol=0.01)
    assert_almost_equal(-box[0].z, BRACE * 1.8, atol=0.02)
    assert_true(bow.has_attribute(String(COLOR)))
    ref colors = bow.attribute_view(String(COLOR))
    var shades = List[Float32]()
    for v in range(colors.count()):
        var red = colors.component(v, 0)
        if not (red in shades):
            shades.append(red)
    # The stave, the wrap and the string.
    assert_equal(len(shades), 3)
    with assert_raises(contains="positive height"):
        _ = longbow(Length(0, METER), YEW, WRAP, FLAX)


def test_a_quiver_holds_its_arrows_out_of_its_mouth() raises:
    var quiver = hip_quiver(Length(0.5, METER), WRAP, YEW, FLAX)
    var box = _bounds(quiver)
    assert_almost_equal(box[0].y, -0.5, atol=1e-4)
    # The arrows stand out of the mouth, at the origin.
    assert_true(box[1].y > 0.15)
    assert_true(quiver.triangle_count() > QUIVER_ARROWS * 12)
    with assert_raises(contains="positive length"):
        _ = hip_quiver(Length(-1, METER), WRAP, YEW, FLAX)


def test_an_archer_carries_a_bow_and_a_quiver() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var painted = physical_material(Color(255, 255, 255))
    painted.vertex_colors = True
    var look = assets.materials.add(painted)
    var meshes = len(scene.meshes)
    var nodes = equip_archer(scene, assets, person, look)
    assert_equal(len(nodes), 2)
    assert_equal(len(scene.meshes), meshes + 2)
    assert_true(scene.meshes[meshes].node == nodes[0])
    # In a cloak, the bow alone.
    var cloaked = coarse_person(scene, assets)
    var before = len(scene.meshes)
    assert_equal(
        len(equip_archer(scene, assets, cloaked, look, quivered=False)), 1
    )
    assert_equal(len(scene.meshes), before + 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
