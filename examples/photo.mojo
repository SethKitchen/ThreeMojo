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

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.png import decode
from render.texture import BILINEAR, REPEAT, texture_from
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

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
    mut scene: Scene,
    pivot: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Swing the camera on by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through, riding a child of `pivot`.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        pivot: The node the camera swings about.
        step: How much further round the camera goes this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(pivot).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


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

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(14, 16, 22))

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

    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.79))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.36))

    # The camera rig: a pivot at the origin and an eye three meters out along
    # its +z, looking back down -z at the cube. Turning the pivot carries the
    # eye round, exactly as the moon in `cubes.mojo` is carried.
    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0, 0, 3.0)
    var eye_node = scene.attach(eye^, pivot)

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.attach(eye_node)

    # One full circuit over the loop, so the animation repeats seamlessly.
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
