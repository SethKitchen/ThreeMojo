# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube wearing an image loaded from a PNG file.

Every other example generates its texture in code, because until now that was
the only kind this renderer had. `assets/brick.png` was written by a
conforming encoder rather than by this project: it is DEFLATE-compressed with
dynamic Huffman codes, and every row uses the Sub filter, which
`render.png`'s *encoder* never emits. So opening it exercises the parts of
`render.inflate` that a round trip through our own encoder cannot reach.

The image is decoded once, turned into a texture with a mip chain, and mapped
onto a turning cube. Nothing else here is new — which is the point: a decoded
image is an ordinary texture, because the decoder widens every colour type to
the RGBA that `Texture` already holds.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.png import decode
from render.texture import BILINEAR, REPEAT, texture_from
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METRE

comptime DEFAULT_IMAGE = "assets/brick.png"
comptime DEFAULT_OUTPUT = "out/photo.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 60


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    meshes: List[Mesh],
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the cube turned to `turn` degrees.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        meshes: The cube, bound to node 0.
        turn: How far it has turned, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var scene = Scene()
    var box = Object3D()
    box.set_euler(Angle(22.0, DEGREE), Angle(turn, DEGREE), Angle(0.0, DEGREE))
    _ = scene.add(box^)

    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))
    scene.update()
    return renderer.render(scene, assets, meshes, camera)


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

    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(14, 16, 22))

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.2, METRE)))
    var skin = assets.textures.add(
        texture_from(image, REPEAT, BILINEAR, mipmapped=True)
    )
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box,
            assets.materials.add(Material(Color(255, 255, 255), skin)),
            NodeId(0),
        )
    )

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 0, 3.0), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                meshes,
                Float32(360) * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
