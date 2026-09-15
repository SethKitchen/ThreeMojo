# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two checkerboard cubes, turning, with different textures.

Everything this project has built, in one image: a scene graph places the
cubes, the camera projects them, each material's `side` drops the half facing
away, the depth buffer sorts what is left, `uv` reaches each fragment with the
perspective divide applied, and a texture is read there.

Two cubes rather than one because a texture belongs to a material now, not to
the renderer. When it belonged to the renderer this example could only have
drawn one image per frame, and the left cube's sharp squares beside the right
cube's blended ones would have been two renders and a composite.

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
from render.texture import BILINEAR, REPEAT, checkerboard
from renderers.renderer import Renderer, available_workers
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
    assets: Assets,
    mut scene: Scene,
    left: NodeId,
    right: NodeId,
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the cubes turned to `turn` degrees.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        left: The sharp cube's node.
        right: The blended cube's node.
        turn: How far the cubes have turned, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    # Tilted as well as spun, so a top face comes into view and its own copy
    # of the pattern can be seen meeting a side's at the edge. The two turn
    # opposite ways, which keeps them from looking like one object.
    scene.node(left).set_euler(
        Angle(26.0, DEGREE), Angle(turn, DEGREE), Angle(0.0, DEGREE)
    )
    scene.node(right).set_euler(
        Angle(26.0, DEGREE), Angle(-turn, DEGREE), Angle(0.0, DEGREE)
    )
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(14, 16, 22))

    var assets = Assets()
    # One geometry, drawn twice.
    var box = assets.geometries.add(cube(Length(1.1, METRE)))
    # Two images, one sharp and one blended, so the difference between the
    # filters is visible side by side on the same shape.
    var sharp = assets.textures.add(
        checkerboard(64, 8, Color(245, 245, 250), Color(40, 90, 170))
    )
    var smooth = assets.textures.add(
        checkerboard(
            64,
            8,
            Color(250, 240, 215),
            Color(190, 80, 40),
            REPEAT,
            BILINEAR,
        )
    )
    # White base colours, so each texture arrives unmodulated by anything but
    # the lighting.
    var sharp_paint = assets.materials.add(
        Material(Color(255, 255, 255), sharp)
    )
    var smooth_paint = assets.materials.add(
        Material(Color(255, 255, 255), smooth)
    )

    var scene = Scene()
    var left_node = Object3D()
    left_node.set_position(-0.95, 0, 0)
    var left = scene.add(left_node^)
    var right_node = Object3D()
    right_node.set_position(0.95, 0, 0)
    var right = scene.add(right_node^)
    scene.add_mesh(Mesh(box, sharp_paint, left))
    scene.add_mesh(Mesh(box, smooth_paint, right))

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
                assets,
                scene,
                left,
                right,
                Float32(360) * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
