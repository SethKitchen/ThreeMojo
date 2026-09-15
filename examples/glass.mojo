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

Where the panes cross, three colors are mixed one over another. That is the
place a renderer's color space shows most plainly: half of white over black is
*half the light*, which displays as 188, and blending the encoded bytes instead
gives 128 — a fifth of the light, wearing the label of a half. Every mix here
happens in linear light and is encoded once at the pixel; see `render.srgb`.

Each pane is a `plane`, `DOUBLE_SIDE`, because a single flat quad has no inside
and no outside and you should be able to see it from either. Its lighting
follows whichever side you are looking at.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from geometries.box import cube
from geometries.plane import plane
from materials.material import DOUBLE_SIDE, NO_TEXTURE, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/glass.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 60


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    panes: List[NodeId],
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the panes turned to `turn` degrees.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        panes: The three pane nodes, a third of a turn apart.
        turn: How far the panes have turned, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    # Three panes on a shared turntable, a third of a turn apart, each also
    # leaning so they cross rather than merely overlapping.
    for pane_index in range(len(panes)):
        var angle = turn + Float32(120) * Float32(pane_index)
        scene.node(panes[pane_index]).set_euler(
            Angle(24.0, DEGREE), Angle(angle, DEGREE), Angle(0.0, DEGREE)
        )
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var assets = Assets()
    var solid = assets.geometries.add(cube(Length(0.9, METER)))
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var white = assets.materials.add(Material(Color(235, 235, 240)))

    var scene = Scene()
    var block = scene.add(Object3D())
    scene.add_mesh(Mesh(solid, white, block))

    var tints = [Color(255, 60, 60), Color(60, 255, 90), Color(70, 120, 255)]
    var panes = List[NodeId]()
    for pane_index in range(3):
        var node = scene.add(Object3D())
        panes.append(node)
        scene.add_mesh(
            Mesh(
                sheet,
                assets.materials.add(
                    Material(tints[pane_index], NO_TEXTURE, DOUBLE_SIDE, 0.45)
                ),
                node,
            )
        )

    # The lamp is a node like any other, so it could be parented to something
    # that moves.
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.5, 3.4), Vector3(0, 0, 0))

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                panes,
                Float32(360) * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
