# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `SubsurfaceScatteringShader`: a `PHONG` surface that lets a
light behind it show through toward the camera."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light, point_light, spot_light
from lights.lighting import scattering_through
from materials.material import (
    LAMBERT,
    NO_SCATTERING,
    PHONG,
    Material,
    phong_material,
    subsurface_scattering,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.rasterizer import SHADE_LIT
from render.srgb import LINEAR
from render.texture import IGNORED, NEAREST, REPEAT, Texture
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16


def white_data() raises -> Texture:
    """Return a one-texel white texture that holds data."""
    return Texture(
        1,
        1,
        [UInt8(255), 255, 255, 255],
        REPEAT,
        NEAREST,
        LINEAR,
        False,
        IGNORED,
    )


def lit_from_behind(
    mut assets: Assets, light: String, thick: Bool, tint: Color
) raises -> Scene:
    """Return a phong square facing the camera, with only a light behind
    it, straight on its axis."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var material = phong_material(Color(200, 200, 200))
    if thick:
        material.set_scattering(
            subsurface_scattering(assets.textures.add(white_data()), tint)
        )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(2.0, METER), Length(2.0, METER))
            ),
            assets.materials.add(material),
            node,
        )
    )
    var lamp = Object3D()
    lamp.set_position(0, 0, -2)
    var at = scene.add(lamp^)
    if light == "sun":
        scene.add_light(directional_light(Color(255, 255, 255), at, 1.0))
    elif light == "bulb":
        scene.add_light(point_light(Color(255, 255, 255), at, 1.0))
    else:
        scene.add_light(
            spot_light(Color(255, 255, 255), at, 1.0, angle=Angle(60.0, DEGREE))
        )
    scene.update()
    return scene^


def middle_of(mut assets: Assets, scene: Scene) raises -> Color:
    """Return the middle pixel of the square, seen from four meters."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    return renderer.render(scene, assets, camera).get_pixel(
        SIZE // 2, SIZE // 2
    )


def test_a_sun_behind_a_thin_surface_shows_through() raises:
    # Without a thickness the sun behind the square leaves it dark. With
    # one, the way to the sun, bent a tenth along the normal, is straight
    # away from the camera: the light through is 10 at three.js's scale,
    # times the attenuation, a tenth, times the sun: one. A gray color,
    # 0x80, shows it as sRGB 128.
    var assets = Assets()
    assert_equal(
        middle_of(
            assets, lit_from_behind(assets, "sun", False, Color(128, 128, 128))
        ).r,
        0,
    )
    var through = middle_of(
        assets, lit_from_behind(assets, "sun", True, Color(128, 128, 128))
    )
    assert_equal(Int(through.r), 128)
    assert_equal(Int(through.b), 128)


def test_a_bulb_and_a_spot_behind_show_through_too() raises:
    for light in ["bulb", "spot"]:
        var assets = Assets()
        var through = middle_of(
            assets, lit_from_behind(assets, light, True, Color(255, 255, 255))
        )
        assert_true(Int(through.r) > 40)


def test_the_light_through_follows_three_js() raises:
    # Straight through: the power of one is one, times the scale, plus the
    # ambient.
    var back = Vector3(0, 0, -1)
    var normal = Vector3(0, 0, 1)
    var eye = Vector3(0, 0, 1)
    assert_almost_equal(
        scattering_through(back, normal, eye, 0.1, 2, 10, 0.5), 10.5
    )
    # Facing the light, none gets through but the ambient.
    assert_almost_equal(
        scattering_through(normal, normal, eye, 0.1, 2, 10, 0.25), 0.25
    )


def test_only_a_phong_material_scatters_light_through_it() raises:
    var lambert = Material(Color(200, 200, 200), kind=LAMBERT)
    with assert_raises(contains="Only a PHONG material scatters light"):
        lambert.set_scattering(subsurface_scattering(TextureId(0)))
    # Turning it off is allowed anywhere.
    lambert.set_scattering(NO_SCATTERING)
    assert_false(lambert.scattering.is_on())
    with assert_raises(contains="numbers must be finite"):
        _ = subsurface_scattering(TextureId(0), power=Float32.MAX * 2)
    with assert_raises(contains="cannot be negative"):
        _ = subsurface_scattering(TextureId(0), scale=-1)
    with assert_raises(contains="a texture id or NO_TEXTURE"):
        _ = subsurface_scattering(TextureId(-5))
    var off = subsurface_scattering(NO_TEXTURE)
    assert_false(off.is_on())


def test_a_thickness_map_must_be_there_and_hold_data() raises:
    var assets = Assets()
    var material = phong_material(Color(200, 200, 200))
    material.set_scattering(subsurface_scattering(TextureId(3)))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(2.0, METER), Length(2.0, METER))
            ),
            assets.materials.add(material),
            node,
        )
    )
    scene.update()
    with assert_raises(contains="A thickness map is named that is not there"):
        _ = middle_of(assets, scene)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
