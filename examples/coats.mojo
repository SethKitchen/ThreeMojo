# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A clear coat and a tinted highlight, each varied by a map.

    mojo run -I . examples/coats.mojo [path.png]

The page is Materials. The left sphere is red paint. Its clear coat is
on only where the map's red channel is one, so glossy bands cross a
matte surface. The right sphere is gray. Its specular color map tints
the highlight gold or blue per texel.
"""

from examples.output import (
    example_destination,
    fill_and_key,
    gallery_renderer,
    spin_clip,
)

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from materials.material import physical_material
from objects.mesh import Mesh
from render.framebuffer import Color
from render.texture import IGNORED, data_texture
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/coats.png"
comptime WIDTH = 320
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime STRIPES = 4


def coat_stripes() -> List[Float32]:
    """Return a clearcoat map: one and zero in alternating columns.

    Returns:
        One red fraction per texel, four wide and two tall.
    """
    var data = List[Float32]()
    for _ in range(2):
        for column in range(STRIPES):
            var on = Float32(0)
            if column % 2 == 0:
                on = 1
            data.append(on)
    return data^


def highlight_tint() -> List[Float32]:
    """Return a specular color map: gold on the left, blue on the right.

    Returns:
        Three fractions a texel, four wide and one tall.
    """
    var data = List[Float32]()
    data.append(1.0)
    data.append(0.72)
    data.append(0.2)
    data.append(0.25)
    data.append(0.45)
    data.append(1.0)
    data.append(1.0)
    data.append(0.72)
    data.append(0.2)
    data.append(0.25)
    data.append(0.45)
    data.append(1.0)
    return data^


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(14, 16, 22))
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(0.62, METER), 48, 32))
    var coat = assets.textures.add(
        data_texture(STRIPES, 2, coat_stripes(), channels=1, alpha=IGNORED)
    )
    var tint = assets.textures.add(
        data_texture(4, 1, highlight_tint(), channels=3, alpha=IGNORED)
    )
    var lacquer = assets.materials.add(
        physical_material(
            Color(170, 28, 28),
            roughness=1.0,
            clearcoat=1.0,
            clearcoat_roughness=0.35,
            clearcoat_map=coat,
        )
    )
    var plastic = assets.materials.add(
        physical_material(
            Color(150, 152, 158),
            roughness=0.18,
            specular_intensity=1.0,
            specular_color_map=tint,
        )
    )

    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.85, 0, 0)
    scene.add_mesh(Mesh(ball, lacquer, scene.add(left^)))
    var right = Object3D()
    right.set_position(0.85, 0, 0)
    scene.add_mesh(Mesh(ball, plastic, scene.add(right^)))

    fill_and_key(
        scene,
        0.4,
        1.5,
        2.0,
        Color(255, 255, 255),
        0.22,
        Color(255, 250, 240),
        3.2,
    )

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0.25, 3.6)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(36.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )
    camera.attach(eye_node)

    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
