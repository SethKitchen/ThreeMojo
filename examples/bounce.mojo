# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Red and green walls bounce light onto a white floor.

    mojo run -I . examples/bounce.mojo [path.png]

The page is Voxel global illumination. The frame is drawn with its
normals, `VXGINode` gathers the bounced light, and `vxgi_light` lays
that light on the picture. The camera sways and returns.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.screen_space import DepthView
from postprocessing.vxgi_node import VXGINode, vxgi_light
from render.apng import encode
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    RenderTarget,
    TargetOutput,
)
from renderers.renderer import Renderer, available_workers
from std.math import pi, sin
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/vxgi.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def _place(
    mut scene: Scene,
    geometry: GeometryId,
    material: MaterialId,
    var node: Object3D,
) raises:
    """Add one mesh at `node`.

    Args:
        scene: The scene.
        geometry: The stored geometry.
        material: The stored material.
        node: Where the mesh sits. Moved in.

    Raises:
        Error: If the scene refuses the node.
    """
    scene.add_mesh(Mesh(geometry, material, scene.add(node^)))


def frame_at(
    renderer: Renderer,
    mut camera: PerspectiveCamera,
    assets: Assets,
    scene: Scene,
    mut node: VXGINode,
    diffuse: List[FloatColor],
    sway: Float32,
    frame_id: Int,
) raises -> Framebuffer:
    """Draw the corner, gather the bounced light, and composite it.

    Args:
        renderer: The renderer to draw with.
        camera: The camera. This frame places it.
        assets: The geometries and materials.
        scene: The corner, already updated.
        node: The illumination pass. The first frame fills its volume.
        diffuse: One white color a pixel, for the indirect term.
        sway: How far the camera slides, in meters.
        frame_id: The frame's number, for the pass's noise.

    Returns:
        The rendered frame.

    Raises:
        Error: If the draw, the gather or the composite is invalid.
    """
    camera.place(
        Vector3(0.15 + sway, 0.9, 1.55),
        Vector3(-0.45, 0.5, -0.35),
    )
    var outputs = List[TargetOutput]()
    outputs.append(OUTPUT_COLOR)
    outputs.append(OUTPUT_NORMAL)
    var target = RenderTarget(
        WIDTH, HEIGHT, Color(8, 8, 10), FLOAT_TARGET, outputs
    )
    renderer.render_into(target, scene, assets, camera)
    var view = DepthView(
        target.depth,
        WIDTH,
        HEIGHT,
        camera.projection_matrix(),
        Length(0.05, METER),
        Length(20.0, METER),
        target.depth_mode,
        target.normals,
    )
    var world = camera.view_matrix()
    world.invert()
    var gathered = node.render(view, world, scene, assets, frame_id)
    vxgi_light(target, gathered, diffuse)
    # The pass also paints pixels the meshes never drew. Put the
    # background back there, so only the corner carries the bounced light.
    var clear = FloatColor(srgb=Color(8, 8, 10)).premultiplied()
    var count = WIDTH * HEIGHT
    for slot in range(count):
        if target.depth[slot] >= 0.999:
            target.colors[slot] = clear
            target.data[slot] = False
    return target.resolve()


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(8, 8, 10))

    var assets = Assets()
    var wall = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var block = assets.geometries.add(cube(Length(0.5, METER)))
    var white = assets.materials.add(Material(Color(236, 236, 232)))
    var red = assets.materials.add(Material(Color(190, 42, 36)))
    var green = assets.materials.add(Material(Color(46, 150, 64)))

    var scene = Scene()
    var floor = Object3D()
    floor.rotate_x(Angle(-90.0, DEGREE))
    _place(scene, wall, white, floor^)
    var left = Object3D()
    left.rotate_y(Angle(90.0, DEGREE))
    left.set_position(-1, 1, 0)
    _place(scene, wall, red, left^)
    var back = Object3D()
    back.set_position(0, 1, -1)
    _place(scene, wall, green, back^)
    var box = Object3D()
    box.set_position(-0.28, 0.25, -0.22)
    _place(scene, block, white, box^)

    var lamp = Object3D()
    lamp.set_position(0.15, 4.2, 0.35)
    scene.add_light(
        directional_light(Color(255, 250, 240), scene.add(lamp^), 1.7)
    )
    scene.add_light(ambient_light(Color(210, 214, 220), 0.32))
    scene.update()

    var node = VXGINode(24)
    node.volume.bounces = 1
    node.gi_intensity = 2.8
    node.cone_count = 2
    var diffuse = List[FloatColor](
        length=WIDTH * HEIGHT, fill=FloatColor(0.85, 0.85, 0.85)
    )

    var camera = PerspectiveCamera(
        Angle(42.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(20.0, METER),
    )

    var frames = List[Framebuffer]()
    for index in range(FRAMES):
        var turn = Float32(2) * Float32(pi) * Float32(index) / Float32(FRAMES)
        frames.append(
            frame_at(
                renderer,
                camera,
                assets,
                scene,
                node,
                diffuse,
                sin(turn) * 0.28,
                index,
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
