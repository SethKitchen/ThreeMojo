# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube wearing an image loaded from a PNG file, circled by the camera.

Every other example generates its texture in code, because until now that was
the only kind this renderer had. `assets/brick.png` was written by a
conforming encoder rather than by this project: it is DEFLATE-compressed with
dynamic Huffman codes, and every row uses the Sub filter, which
`render.png`'s *encoder* never emits. So opening it exercises the parts of
`render.inflate` that a round trip through our own encoder cannot reach.

The image is decoded once, turned into a texture with a mip chain, and mapped
onto a cube. Nothing about that is new -- which is the point: a decoded image
is an ordinary texture, because the decoder widens every color type to the
RGBA that `Texture` already holds.

What moves is the camera, not the cube. three.js's camera is an `Object3D`:
it can be parented, and `camera.position.set` is the same call a mesh gets.
Here `attach` puts the `PerspectiveCamera` on a scene node the way a `Mesh`
names one, and that node is a child of a pivot at the origin. Turning the
pivot each frame swings the camera around the cube while the cube and the lamp
stay put -- so the lit face stays lit as the camera passes it, which a
spinning cube under a fixed lamp cannot do.
"""

from examples.output import (
    fill_and_key,
    framed_camera,
    gallery_renderer,
    spin_clip,
)

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color
from render.png import decode
from render.texture import BILINEAR, REPEAT, texture_from
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_IMAGE = "assets/brick.png"
comptime DEFAULT_OUTPUT = "out/photo.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 60


def main() raises:
    var args = argv()
    var source = String(DEFAULT_IMAGE)
    if len(args) > 1:
        source = String(args[1])
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 2:
        destination = String(args[2])

    # The one new line: a file becomes an image becomes a texture.
    var image = decode(Path(source).read_bytes())
    print("Read", source, "-", image.width, "x", image.height)

    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(14, 16, 22))

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(1.2, METER)))
    var skin = assets.textures.add(
        texture_from(image, REPEAT, BILINEAR, mipmapped=True)
    )
    var brick = assets.materials.add(Material(Color(255, 255, 255), skin))

    var scene = Scene()
    # Tilted once, so the top face shows, and never touched again.
    var tilted = Object3D()
    tilted.set_euler(
        Angle(22.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var box = scene.add(tilted^)
    scene.add_mesh(Mesh(block, brick, box))

    fill_and_key(
        scene,
        0.4,
        0.8,
        0.5,
        Color(255, 255, 255),
        0.79,
        Color(255, 255, 255),
        2.36,
    )

    # The camera rig: a pivot at the origin and an eye three meters out along
    # its +z, looking back down -z at the cube. Turning the pivot carries the
    # eye round, exactly as the moon in `cubes.mojo` is carried.
    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0, 3.0)
    var eye_node = scene.attach(eye^, pivot)

    var camera = framed_camera(
        WIDTH,
        HEIGHT,
        field_of_view=Angle(45.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(100.0, METER),
    )
    camera.attach(eye_node)

    # One full circuit over the loop, so the animation repeats seamlessly.
    spin_clip(
        renderer, camera, assets, scene, pivot, FRAMES, DELAY_MS, destination
    )
