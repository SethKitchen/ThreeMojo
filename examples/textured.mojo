# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A checkerboard cube, turning.

Everything this project has built, in one image: a scene graph places the cube,
the camera projects it, backface culling drops the half facing away, the depth
buffer sorts what is left, `uv` reaches each fragment with the perspective
divide applied, and a texture is read there.

A checkerboard is the traditional test image because its errors are legible. A
wrong `uv` moves a square somewhere obviously wrong; a wrong interpolation
bends the grid lines instead of merely shading oddly; a flipped `v` turns the
pattern upside down, which a smooth gradient would hide completely. Nearest
sampling keeps the edges hard, so none of that is softened.

Each face carries the whole image, which is what `BoxGeometry` does. The
squares therefore run straight across a face and meet at right angles at its
edges, rather than continuing around the cube.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.geometry_store import GeometryId, GeometryStore
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.rasterizer import SHADE_TEXTURE
from render.texture import checkerboard
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METRE

comptime DEFAULT_OUTPUT = "out/textured.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 60


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    geometries: GeometryStore,
    box: GeometryId,
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the cube turned to `turn` degrees.

    Args:
        renderer: The renderer to draw with, already holding the texture.
        camera: The camera to view through.
        geometries: The store owning the cube.
        box: Id of the cube.
        turn: How far the cube has turned, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var scene = Scene()
    var node = Object3D()
    # Tilted as well as spun, so the top face comes into view and its own
    # copy of the pattern can be seen meeting the side's at the edge.
    node.set_euler(Angle(26.0, DEGREE), Angle(turn, DEGREE), Angle(0.0, DEGREE))
    _ = scene.add(node^)
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(Mesh(box, Color(255, 255, 255), 0))
    return renderer.render(scene, geometries, meshes, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(14, 16, 22))
    renderer.set_shading(SHADE_TEXTURE)
    # White meshes, so the texture arrives unmodulated by any base colour and
    # only the lighting dims it.
    renderer.set_texture(
        checkerboard(64, 8, Color(245, 245, 250), Color(40, 90, 170))
    )

    var geometries = GeometryStore()
    var box = geometries.add(cube(Length(1.2, METRE)))

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 0, 3.2), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                geometries,
                box,
                Float32(360) * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
