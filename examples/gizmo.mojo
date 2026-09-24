# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A transform gizmo on a cube, redrawn as the camera orbits.

    mojo run -I . examples/gizmo.mojo [path.png]

The page is Windowing and controls. `TransformControls.gizmo` returns
the translate handles as colored line segments in world space. A handle
that points at the eye is left out, so the axes change as the camera
goes round. The terminal window itself is `examples/viewer.mojo`.
"""

from cameras.perspective_camera import PerspectiveCamera
from controls.transform_controls import TransformControls
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from helpers.grid import grid_helper
from helpers.material import helper_material
from lights.light import ambient_light, directional_light
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.line import SEGMENTS, Line
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/controls.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    mut assets: Assets,
    mut scene: Scene,
    controls: TransformControls,
    pivot: NodeId,
    paint: MaterialId,
    origin: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the camera, redraw the gizmo, and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera riding a child of `pivot`.
        assets: The geometries and materials. The new gizmo is stored here.
        scene: The persistent scene, edited in place.
        controls: The gizmo, already attached to the cube.
        pivot: The node the camera swings about.
        paint: The helper material the gizmo is drawn with.
        origin: A node at the origin. The gizmo is already in world space.
        step: How much further round the camera goes this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(pivot).rotate_y(step)
    scene.update()
    if len(scene.lines) > 1:
        _ = scene.lines.pop()
    var geometry = assets.geometries.add(controls.gizmo(camera, scene))
    scene.add_line(Line(geometry, paint, origin, mode=SEGMENTS))
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()
    var origin = scene.add(Object3D())

    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var ball = assets.geometries.add(sphere(Length(0.28, METER), 20, 14))
    var blue = assets.materials.add(Material(Color(70, 110, 200)))
    var orange = assets.materials.add(Material(Color(230, 140, 60)))
    var stand = Object3D()
    stand.set_position(-0.15, 0.35, 0)
    var block_node = scene.add(stand^)
    scene.add_mesh(Mesh(block, blue, block_node))
    var perch = Object3D()
    perch.set_position(0.85, 0.28, 0.35)
    scene.add_mesh(Mesh(ball, orange, scene.add(perch^)))

    var paint = assets.materials.add(helper_material())
    var grid = assets.geometries.add(grid_helper(Length(3.0, METER), 6))
    scene.add_line(Line(grid, paint, origin, mode=SEGMENTS))

    var lamp = Object3D()
    lamp.set_position(1.2, 1.6, 1.4)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.55))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.2))

    var controls = TransformControls()
    controls.attach(block_node)
    # The handles are a fraction of `size` in world space, and the depth
    # test hides any that stay inside the cube. This size clears the cube.
    controls.size = 3.2

    var pivot = scene.add(Object3D())
    var eye = Object3D()
    eye.set_position(0.2, 1.15, 3.3)
    var eye_node = scene.attach(eye^, pivot)
    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(40.0, METER),
    )
    camera.attach(eye_node)

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                controls,
                pivot,
                paint,
                origin,
                step,
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
