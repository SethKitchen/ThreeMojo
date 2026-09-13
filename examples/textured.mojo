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
from materials.material import Material
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.texture import BILINEAR, REPEAT, checkerboard
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
    assets: Assets,
    meshes: List[Mesh],
    turn: Float32,
) raises -> Framebuffer:
    """Render one frame with the cube turned to `turn` degrees.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        meshes: The two cubes, already bound to nodes 0 and 1.
        turn: How far the cubes have turned, in degrees.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var scene = Scene()
    # Tilted as well as spun, so a top face comes into view and its own copy
    # of the pattern can be seen meeting a side's at the edge. The two turn
    # opposite ways, which keeps them from looking like one object.
    var left = Object3D()
    left.set_position(-0.95, 0, 0)
    left.set_euler(Angle(26.0, DEGREE), Angle(turn, DEGREE), Angle(0.0, DEGREE))
    _ = scene.add(left^)
    var right = Object3D()
    right.set_position(0.95, 0, 0)
    right.set_euler(
        Angle(26.0, DEGREE), Angle(-turn, DEGREE), Angle(0.0, DEGREE)
    )
    _ = scene.add(right^)
    scene.update()
    return renderer.render(scene, assets, meshes, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT)
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
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 255, 255), sharp)), 0
        )
    )
    meshes.append(
        Mesh(
            box,
            assets.materials.add(Material(Color(255, 255, 255), smooth)),
            1,
        )
    )

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
                meshes,
                Float32(360) * Float32(index) / Float32(FRAMES),
            )
        )

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
