# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.cube_depth_texture`."""

from cameras.cube_camera import CubeCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_depth_texture import cube_depth_texture, cube_depth_texture_of
from render.cube_texture import FACE_COUNT
from render.framebuffer import Color, Framebuffer
from render.raster_state import DepthMode, REVERSED_DEPTH
from render.texture import NEAREST
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def directions() -> List[Vector3]:
    """Return the six axes, in `POSITIVE_X` through `NEGATIVE_Z` order."""
    return [
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, -1, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, -1),
    ]


def test_six_buffers_become_six_faces_in_order() raises:
    # Face k holds the NDC depth that is the window depth k / 5.
    var depths = List[Float32]()
    for face in range(FACE_COUNT):
        for _ in range(4):
            depths.append(Float32(face) / 5 * 2 - 1)
    var cube_map = cube_depth_texture(2, depths)
    assert_equal(cube_map.size, 2)
    assert_true(cube_map.faces[0].mag_filter == NEAREST)
    var axes = directions()
    for face in range(FACE_COUNT):
        var seen = cube_map.sample(axes[face])
        assert_almost_equal(seen.r, Float32(face) / 5, atol=1e-6)


def test_a_reversed_depth_is_read_as_stored() raises:
    var depths = List[Float32](length=FACE_COUNT, fill=0.2)
    var cube_map = cube_depth_texture(1, depths, REVERSED_DEPTH)
    assert_almost_equal(cube_map.sample(Vector3(0, 0, 1)).r, 0.2, atol=3e-3)


def five_and(var last: Framebuffer) raises -> List[Framebuffer]:
    """Return five black two-by-two images and then `last`."""
    var images = List[Framebuffer]()
    for _ in range(FACE_COUNT - 1):
        images.append(Framebuffer(2, 2, Color(0, 0, 0)))
    images.append(last^)
    return images^


def test_a_cube_depth_texture_refuses_what_is_not_six_square_faces() raises:
    with assert_raises(contains="one texel"):
        _ = cube_depth_texture(0, List[Float32]())
    with assert_raises(contains="six square"):
        _ = cube_depth_texture(2, List[Float32](length=5, fill=0))
    with assert_raises():
        _ = cube_depth_texture(
            1, List[Float32](length=FACE_COUNT, fill=0), DepthMode(9)
        )
    with assert_raises(contains="exactly six"):
        _ = cube_depth_texture_of(List[Framebuffer]())
    with assert_raises(contains="one size"):
        _ = cube_depth_texture_of(five_and(Framebuffer(3, 2, Color(0, 0, 0))))
    with assert_raises(contains="one size"):
        _ = cube_depth_texture_of(five_and(Framebuffer(2, 3, Color(0, 0, 0))))

def test_a_cube_camera_render_keeps_the_depth_of_each_face() raises:
    # A box two meters along +x: its near side, a meter and a half away,
    # is in the +x face, and nothing is in the -x face.
    var assets = Assets()
    var scene = Scene()
    var spot = Object3D()
    spot.set_position(2, 0, 0)
    var node = scene.add(spot^)
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    scene.add_mesh(Mesh(box, paint, node))
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    scene.update()
    var eye = CubeCamera(Length(0.1, METER), Length(10.0, METER), 8)
    var renderer = Renderer(8, 8)
    var faces = List[Framebuffer]()
    for face in range(FACE_COUNT):
        faces.append(renderer.render(scene, assets, eye.face_camera(face, scene)))
    var cube_map = cube_depth_texture_of(faces)
    # z = -1.5 with planes at 0.1 and 10: a window depth of about 0.943.
    var near = cube_map.sample(Vector3(1, 0, 0)).r
    assert_almost_equal(near, 0.943, atol=5e-3)
    assert_almost_equal(cube_map.sample(Vector3(-1, 0, 0)).r, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
