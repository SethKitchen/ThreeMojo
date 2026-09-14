# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three translucent panes turning through each other, over a solid cube.

Blending is not commutative, so this is really a picture of draw order. The
renderer puts the opaque cube down first — it writes depth, which is what
stops a pane behind it from showing through — and then sorts the panes back to
front and mixes each into what the ones beyond it left. Submitting them in any
order gives the same image, which is the point of the sort and is asserted in
the tests.

Where the panes cross, three colours are mixed one over another. That is the
place a renderer's colour space shows most plainly: half of white over black is
*half the light*, which displays as 188, and blending the encoded bytes instead
gives 128 — a fifth of the light, wearing the label of a half. Every mix here
happens in linear light and is encoded once at the pixel; see `render.srgb`.

Each pane is `DOUBLE_SIDE`, because a single flat quad has no inside and no
outside and you should be able to see it from either. Its lighting follows
whichever side you are looking at.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import DOUBLE_SIDE, NO_TEXTURE, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METRE

comptime DEFAULT_OUTPUT = "out/glass.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 60


def pane(size: Float32) raises -> BufferGeometry:
    """Return a flat square in the xy plane, two triangles, no normals.

    With no `normal` attribute the renderer uses the triangle's own geometric
    normal, which is what a flat quad wants: it has exactly one.

    Args:
        size: The square's width and height.

    Returns:
        The geometry.

    Raises:
        Error: If the attributes are malformed, which they are not.
    """
    var half = size / 2
    var positions = List[Float32]()
    var xs = [-half, half, half, -half]
    var ys = [-half, -half, half, half]
    for corner in range(4):
        positions.append(xs[corner])
        positions.append(ys[corner])
        positions.append(0)

    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    var index = List[Int]()
    for entry in [0, 1, 2, 0, 2, 3]:
        index.append(entry)
    geometry.set_index(index^)
    return geometry^


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    meshes: List[Mesh],
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the panes turned to `turn` degrees.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        meshes: The cube and the three panes, bound to nodes 0 to 3.
        turn: How far the panes have turned, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var scene = Scene()
    _ = scene.add(Object3D())

    # Three panes on a shared turntable, a third of a turn apart, each also
    # leaning so they cross rather than merely overlapping.
    for pane_index in range(3):
        var node = Object3D()
        var angle = turn + Float32(120) * Float32(pane_index)
        node.set_euler(
            Angle(24.0, DEGREE), Angle(angle, DEGREE), Angle(0.0, DEGREE)
        )
        node.set_position(0, 0, 0)
        _ = scene.add(node^)
    scene.update()

    return renderer.render(scene, assets, meshes, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(16, 18, 26))

    var assets = Assets()
    var solid = assets.geometries.add(cube(Length(0.9, METRE)))
    var sheet = assets.geometries.add(pane(2.0))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            solid,
            assets.materials.add(Material(Color(235, 235, 240))),
            NodeId(0),
        )
    )
    var tints = [Color(255, 60, 60), Color(60, 255, 90), Color(70, 120, 255)]
    for pane_index in range(3):
        meshes.append(
            Mesh(
                sheet,
                assets.materials.add(
                    Material(tints[pane_index], NO_TEXTURE, DOUBLE_SIDE, 0.45)
                ),
                NodeId(pane_index + 1),
            )
        )

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 0.5, 3.4), Vector3(0, 0, 0))

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
