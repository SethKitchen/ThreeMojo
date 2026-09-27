# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""three.js's `VolumeRenderShader1`, marched through a ball of intensity in
an eight-texel volume, as a MIP render and as an ISO render."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from materials.material import BACK_SIDE, shader_material
from materials.volume_shader import (
    VOLUME_ISO,
    VOLUME_ISO_STEPS,
    VOLUME_MIP,
    VOLUME_MIP_STEPS,
    VolumeStyle,
    volume_render_shader,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.srgb import LINEAR
from render.texture import BILINEAR, CLAMP, Texture
from render.volume_texture import Data3DTexture, VolumeImage
from renderers.renderer import Renderer
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SIDE = 8
comptime SIZE = 16


def a_ball() raises -> Data3DTexture:
    """Return an eight-texel volume whose intensity is one at its center
    and falls to zero three texels out."""
    var data = List[Float32]()
    for z in range(SIDE):
        for y in range(SIDE):
            for x in range(SIDE):
                var dx = Float32(x) - 3.5
                var dy = Float32(y) - 3.5
                var dz = Float32(z) - 3.5
                var reach = sqrt(dx * dx + dy * dy + dz * dz)
                var value = max(Float32(0), 1 - reach / 3)
                data.append(value)
                data.append(value)
                data.append(value)
                data.append(1)
    return Data3DTexture(
        VolumeImage.of_floats(SIDE, SIDE, SIDE, data), filter=BILINEAR
    )


def a_colormap() raises -> Texture:
    """Return a colormap from blue at zero to red at one."""
    var pixels: List[UInt8] = [0, 0, 255, 255, 255, 0, 0, 255]
    return Texture(2, 1, pixels^, CLAMP, BILINEAR, LINEAR, False)


def a_volume_scene(style: VolumeStyle) raises -> Tuple[Assets, Scene]:
    """Return the ball in a box that spans it, drawn from its back faces."""
    var assets = Assets()
    var program = volume_render_shader(style)
    program.set_volume("u_data", assets.data_3d_textures.add(a_ball()))
    program.set_texture("u_cmdata", assets.textures.add(a_colormap()))
    program.set_uniform("u_size", Vector3(SIDE, SIDE, SIDE))
    program.set_uniform("u_renderthreshold", Float32(0.4))
    # The box runs from -0.5 to 7.5 in its own space, and the node puts
    # that back on the origin, so `u_world_to_local` undoes the move.
    var shape = box(
        Length(Float32(SIDE), METER),
        Length(Float32(SIDE), METER),
        Length(Float32(SIDE), METER),
    )
    shape.translate(
        Length(3.5, METER), Length(3.5, METER), Length(3.5, METER)
    )
    var to_local = Matrix4()
    to_local.elements[12] = 3.5
    to_local.elements[13] = 3.5
    to_local.elements[14] = 3.5
    program.set_uniform("u_world_to_local", to_local)
    var id = assets.programs.add(program^)
    var scene = Scene()
    var node = Object3D()
    node.set_position(-3.5, -3.5, -3.5)
    var at = scene.add(node^)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(shape^),
            assets.materials.add(shader_material(id, side=BACK_SIDE)),
            at,
        )
    )
    scene.update()
    return (assets^, scene^)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking at the ball from the side and above."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(6, 5, 18), Vector3(0, 0, 0))
    return camera^


def render(style: VolumeStyle) raises -> Framebuffer:
    """Return the ball rendered in a style."""
    var made = a_volume_scene(style)
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    return renderer.render(made[1], made[0], a_camera())


def test_a_mip_render_is_red_at_the_center_and_empty_outside() raises:
    var image = render(VOLUME_MIP)
    var middle = image.get_pixel(SIZE // 2, SIZE // 2)
    # The brightest value on the middle ray is the center's, about 0.7:
    # mostly red.
    assert_true(middle.r > 200, "the center is red")
    assert_true(Int(middle.r) > 2 * Int(middle.b), "the center is not blue")
    # A corner of the image misses the box, and the background stays.
    var corner = image.get_pixel(0, 0)
    assert_equal(Int(corner.r), 0)
    assert_equal(Int(corner.b), 0)


def test_an_iso_render_lights_the_surface_it_finds() raises:
    var image = render(VOLUME_ISO)
    var middle = image.get_pixel(SIZE // 2, SIZE // 2)
    assert_true(
        Int(middle.r) + Int(middle.g) + Int(middle.b) > 60,
        "the surface is lit",
    )
    # Past the ball, where no texel reaches the threshold, nothing shows.
    var edge = image.get_pixel(SIZE // 2, 1)
    assert_equal(Int(edge.r) + Int(edge.g) + Int(edge.b), 0)


def test_the_march_is_long_enough_and_a_style_is_one_of_two() raises:
    # The longest ray through an eight-texel cube is under fourteen texels.
    assert_true(VOLUME_ISO_STEPS >= 14)
    assert_true(VOLUME_MIP_STEPS >= VOLUME_ISO_STEPS)
    assert_true(VOLUME_MIP.is_valid())
    assert_true(VOLUME_ISO.is_valid())
    assert_false(VolumeStyle(2).is_valid())
    with assert_raises(contains="VOLUME_MIP or VOLUME_ISO"):
        _ = volume_render_shader(VolumeStyle(-1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
