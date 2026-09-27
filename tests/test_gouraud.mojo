# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `MeshGouraudMaterial`: a `LAMBERT` surface lit at its
corners. Where the light is the same at every point of a flat face, as a
directional light's is, a Gouraud surface draws as a Lambert one does, shadows
and all; a point light near a face shows the difference."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import (
    ambient_light,
    directional_light,
    point_light,
    spot_light,
)
from lights.lighting import Lighting
from materials.material import (
    BACK_SIDE,
    DOUBLE_SIDE,
    FRONT_SIDE,
    GOURAUD,
    LAMBERT,
    Material,
    MaterialKind,
    Side,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.srgb import LINEAR
from render.texture import IGNORED, NEAREST, REPEAT, Texture
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 24


def camera_at(z: Float32) raises -> PerspectiveCamera:
    """Return a camera on the z axis looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, 0))
    return camera^


def floor_scene(
    mut assets: Assets, kind: MaterialKind, receive: Bool
) raises -> Scene:
    """Return a floor facing the camera, a block between it and a sun
    that casts, and a dim ambient light."""
    var scene = Scene()
    var floor_node = scene.add(Object3D())
    var lift = Object3D()
    lift.set_position(0.5, 0.5, 1.0)
    var lift_node = scene.add(lift^)
    var paint = assets.materials.add(Material(Color(200, 200, 200), kind=kind))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(4.0, METER), Length(4.0, METER), 3, 3)
            ),
            paint,
            floor_node,
            receive_shadow=receive,
        )
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(0.5, METER))),
            assets.materials.add(Material(Color(200, 60, 60))),
            lift_node,
            cast_shadow=True,
        )
    )
    var lamp = Object3D()
    lamp.set_position(1, 1, 4)
    var sun = directional_light(Color(255, 255, 255), scene.add(lamp^), 2.0)
    sun.cast_shadow = True
    sun.shadow.map_size = 64
    scene.add_light(sun)
    scene.add_light(ambient_light(Color(40, 40, 40)))
    scene.update()
    return scene^


def mismatches(a: Framebuffer, b: Framebuffer) raises -> Int:
    """Return how many pixels differ by more than one level."""
    var count = 0
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if (
                abs(Int(p.r) - Int(q.r)) > 1
                or abs(Int(p.g) - Int(q.g)) > 1
                or abs(Int(p.b) - Int(q.b)) > 1
            ):
                count += 1
    return count


def test_a_sun_lights_a_gouraud_floor_as_it_lights_a_lambert_one() raises:
    # The same light at every point of a flat face: lit at the corners or
    # at each fragment, the floor is the same, and the block's shadow
    # darkens it the same way.
    for receive in [True, False]:
        var assets = Assets()
        var renderer = Renderer(SIZE, SIZE)
        var lambert = renderer.render(
            floor_scene(assets, LAMBERT, receive), assets, camera_at(6)
        )
        var gouraud = renderer.render(
            floor_scene(assets, GOURAUD, receive), assets, camera_at(6)
        )
        assert_equal(mismatches(lambert, gouraud), 0)
    # And a shadow does fall: the floor under the block is darker than
    # the floor beside it.
    var assets = Assets()
    var image = Renderer(SIZE, SIZE).render(
        floor_scene(assets, GOURAUD, True), assets, camera_at(6)
    )
    var beside = image.get_pixel(3, SIZE - 4)
    var under = image.get_pixel(SIZE // 2 + 1, SIZE // 2 - 1)
    assert_true(Int(under.r) + 20 < Int(beside.r))


def bulb_scene(
    mut assets: Assets, kind: MaterialKind, side: Side, z: Float32
) raises -> Scene:
    """Return one square of two triangles facing +z, and a bulb in front of
    its middle, at `z`."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(2.0, METER), Length(2.0, METER))
            ),
            assets.materials.add(
                Material(Color(255, 255, 255), kind=kind, side=side)
            ),
            node,
        )
    )
    var lamp = Object3D()
    lamp.set_position(0, 0, z)
    scene.add_light(point_light(Color(255, 255, 255), scene.add(lamp^), 2.0))
    scene.update()
    return scene^


def test_a_bulb_near_a_square_lights_its_corners_alike() raises:
    # The bulb is as far from each corner and as far round, so a Gouraud
    # square is one color all over; a Lambert one is brightest in the
    # middle, straight under the bulb.
    var assets = Assets()
    var renderer = Renderer(SIZE, SIZE)
    var gouraud = renderer.render(
        bulb_scene(assets, GOURAUD, FRONT_SIDE, 0.5), assets, camera_at(3)
    )
    var lambert = renderer.render(
        bulb_scene(assets, LAMBERT, FRONT_SIDE, 0.5), assets, camera_at(3)
    )
    var middle = gouraud.get_pixel(SIZE // 2, SIZE // 2)
    var off = gouraud.get_pixel(SIZE // 2 + 3, SIZE // 2 + 2)
    assert_true(Int(middle.r) > 0)
    assert_true(abs(Int(middle.r) - Int(off.r)) <= 1)
    assert_true(
        Int(lambert.get_pixel(SIZE // 2, SIZE // 2).r) > Int(middle.r) + 20
    )


def test_the_far_side_of_a_gouraud_square_is_lit_from_its_side() raises:
    # The camera and the bulb are both behind the square. A two-sided
    # square shows its far side lit by the bulb, as a Lambert one does,
    # and a back-sided one is lit on its back whichever way it is seen.
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    for side in [DOUBLE_SIDE, BACK_SIDE]:
        var assets = Assets()
        var gouraud = renderer.render(
            bulb_scene(assets, GOURAUD, side, -0.5), assets, camera_at(-3)
        )
        var seen = gouraud.get_pixel(SIZE // 2, SIZE // 2)
        assert_true(Int(seen.r) > 0)
    # A one-sided one is not drawn from behind at all.
    var assets = Assets()
    var culled = renderer.render(
        bulb_scene(assets, GOURAUD, FRONT_SIDE, -0.5), assets, camera_at(-3)
    )
    assert_equal(Int(culled.get_pixel(SIZE // 2, SIZE // 2).r), 0)


def test_a_gouraud_material_has_no_normal_map() raises:
    # Lit at the corners, before a map could turn its normal: three.js's
    # `MeshGouraudMaterial` has neither a normal map nor a bump map, nor a
    # displacement map. It does reflect, and takes a specular map.
    assert_true(GOURAUD.is_valid())
    assert_true(GOURAUD.is_lit())
    assert_true(GOURAUD.has_normal())
    assert_false(GOURAUD.has_normal_map())
    assert_false(GOURAUD.displaces())
    assert_true(GOURAUD.reflects())
    assert_true(GOURAUD.has_specular_map())
    assert_true(GOURAUD.has_indirect())


def test_an_ao_map_takes_a_gouraud_surface_s_ambient_light() raises:
    # Lit at the corners, the ambient light is still dimmed at each
    # fragment by the ao map, three.js's `aomap_fragment`. Two squares of
    # the one material share one lighting of their corners.
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var seen = List[Int]()
    for mapped in [False, True]:
        var assets = Assets()
        var scene = Scene()
        var paint = Material(Color(255, 255, 255), kind=GOURAUD)
        if mapped:
            paint.ao_map = assets.textures.add(
                Texture(
                    1,
                    1,
                    [UInt8(0), 0, 0, 255],
                    REPEAT,
                    NEAREST,
                    LINEAR,
                    False,
                    IGNORED,
                )
            )
        var painted = assets.materials.add(paint)
        var square = assets.geometries.add(
            plane(Length(2.0, METER), Length(2.0, METER))
        )
        for across in [Float32(-1.1), Float32(1.1)]:
            var node = Object3D()
            node.set_position(across, 0, 0)
            scene.add_mesh(Mesh(square, painted, scene.add(node^)))
        scene.add_light(ambient_light(Color(255, 255, 255)))
        scene.update()
        var image = renderer.render(scene, assets, camera_at(6))
        seen.append(Int(image.get_pixel(SIZE // 4, SIZE // 2).r))
        seen.append(Int(image.get_pixel(3 * SIZE // 4, SIZE // 2).r))
    assert_true(seen[0] > 100)
    assert_equal(seen[0], seen[1])
    assert_equal(seen[2], 0)
    assert_equal(seen[3], 0)


def test_the_corners_skip_a_light_that_cannot_reach_them() raises:
    # A bulb on the corner, and a narrow spot whose cone misses it or which
    # is behind it: none lights the corner. A sun does.
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 2)
    var at = scene.add(lamp^)
    scene.add_light(point_light(Color(255, 255, 255), at, 1.0))
    scene.add_light(
        spot_light(Color(255, 255, 255), at, 1.0, angle=Angle(10.0, DEGREE))
    )
    scene.update()
    var lighting = Lighting(scene)
    var up = Vector3(0, 0, 1)
    # On the bulb, and in the spot's cone but with the spot behind.
    assert_equal(lighting.direct_at(up, Vector3(0, 0, 2)).r, 0)
    assert_equal(lighting.direct_at(Vector3(0, 0, -1), Vector3(0, 0, 0)).r, 0)
    # Out of the spot's cone, the bulb alone lights the corner.
    var aside = lighting.direct_at(up, Vector3(3, 0, 0))
    var bulb_only = Scene()
    var bare = Object3D()
    bare.set_position(0, 0, 2)
    bulb_only.add_light(
        point_light(Color(255, 255, 255), bulb_only.add(bare^), 1.0)
    )
    bulb_only.update()
    assert_equal(aside.r, Lighting(bulb_only).direct_at(up, Vector3(3, 0, 0)).r)
    # Straight under both, each adds its light.
    assert_true(lighting.direct_at(up, Vector3(0, 0, 0)).r > aside.r)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
