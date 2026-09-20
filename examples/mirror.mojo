# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A chrome ball under a sky, reflecting two boxes that circle it.

    mojo run -I . examples/mirror.mojo [path.png]

The page is Textures. The sky is a cube texture built from six images
that are computed rather than loaded, and it is the scene's background
and its environment. A cube camera at the ball's center renders the sky
and the boxes into a second cube texture every frame, and the ball
reflects that one, so the boxes go round in its surface as they go round
the scene. The floor reflects the sky a little, mixed into its own gray.
"""

from cameras.cube_camera import CubeCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import cube_background
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import (
    BASIC,
    MIX_OPERATION,
    Material,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.cube_texture import (
    FACE_COUNT,
    CubeTexture,
    face_forward,
    face_up,
)
from render.cube_texture_store import SCENE_ENVIRONMENT
from render.framebuffer import Color, FloatColor, Framebuffer
from render.srgb import SRGB
from render.texture import BILINEAR, CLAMP, Texture
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/mirror.png"
comptime WIDTH = 240
comptime HEIGHT = 180
# The size of each face of the sky, and of the cube camera's faces.
comptime SKY_SIZE = 64
comptime MIRROR_SIZE = 48
comptime FRAMES = 30
comptime DELAY_MS = 66


def sky_face(face: Int) raises -> Texture:
    """Return one face of a sky: blue overhead, pale at the horizon and
    a dull green below, by the direction each texel looks along.

    Args:
        face: `POSITIVE_X` through `NEGATIVE_Z`.

    Returns:
        The face, clamped and filtered.

    Raises:
        Error: If the texture cannot be built.
    """
    var forward = face_forward(face)
    var up = face_up(face)
    var right = forward
    right.cross(up)
    var zenith = FloatColor(srgb=Color(70, 120, 220))
    var horizon = FloatColor(srgb=Color(210, 225, 240))
    var ground = FloatColor(srgb=Color(70, 90, 60))
    var pixels = List[UInt8]()
    for row in range(SKY_SIZE):
        for column in range(SKY_SIZE):
            # The direction this texel looks along, as `face_uv` reads
            # it back: across by the camera's right, up by its up, with
            # the top row up.
            var across = (Float32(column) + 0.5) / Float32(SKY_SIZE) * 2 - 1
            var upward = 1 - (Float32(row) + 0.5) / Float32(SKY_SIZE) * 2
            var direction = forward + right * across + up * upward
            direction.normalize()
            var tint = ground
            if direction.y >= 0:
                var lean = direction.y
                tint = FloatColor(
                    horizon.r + (zenith.r - horizon.r) * lean,
                    horizon.g + (zenith.g - horizon.g) * lean,
                    horizon.b + (zenith.b - horizon.b) * lean,
                )
            var shown = tint.encode()
            pixels.append(shown.r)
            pixels.append(shown.g)
            pixels.append(shown.b)
            pixels.append(255)
    return Texture(SKY_SIZE, SKY_SIZE, pixels^, CLAMP, BILINEAR, SRGB, False)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    var assets = Assets()
    var faces = List[Texture]()
    for face in range(FACE_COUNT):
        faces.append(sky_face(face))
    var sky = assets.cube_textures.add(CubeTexture(faces^))

    var ball = assets.geometries.add(sphere(Length(0.8, METER), 48, 32))
    var box = assets.geometries.add(cube(Length(0.5, METER)))
    var ground = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER))
    )
    var floor = assets.materials.add(
        Material(
            Color(150, 150, 150),
            env_map=SCENE_ENVIRONMENT,
            reflectivity=0.35,
            combine=MIX_OPERATION,
        )
    )
    var orange = assets.materials.add(Material(Color(240, 120, 40)))
    var teal = assets.materials.add(Material(Color(40, 170, 160)))

    var scene = Scene()
    scene.background = cube_background(sky)
    scene.environment = sky
    var slab = Object3D()
    slab.set_position(0, -0.8, 0)
    slab.set_euler(Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    var slab_node = scene.add(slab^)
    scene.add_mesh(Mesh(ground, floor, slab_node))
    # The ball, on a layer of its own so the cube camera at its center
    # does not see the inside of it.
    var center = Object3D()
    center.layers.set(1)
    var center_node = scene.add(center^)
    # The boxes ride a pivot that turns each frame.
    var pivot_node = scene.add(Object3D())
    var first = Object3D()
    first.set_position(1.7, 0, 0)
    var first_node = scene.attach(first^, pivot_node)
    scene.add_mesh(Mesh(box, orange, first_node))
    var second = Object3D()
    second.set_position(-1.7, 0.3, 0)
    second.set_euler(
        Angle(30.0, DEGREE), Angle(40.0, DEGREE), Angle(0.0, DEGREE)
    )
    var second_node = scene.attach(second^, pivot_node)
    scene.add_mesh(Mesh(box, teal, second_node))
    var lamp = Object3D()
    lamp.set_position(2, 3, 2)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.7))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.2))
    scene.update()

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 1.0, 4.2), Vector3(0, 0, 0))
    camera.layers.enable(1)
    var eye = CubeCamera(Length(0.1, METER), Length(50.0, METER), MIRROR_SIZE)
    eye.attach(center_node)

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        scene.node(pivot_node).rotate_y(step)
        scene.update()
        # What the ball sees this frame, then the ball wearing it. The
        # store grows by one cube a frame; a long animation would reuse
        # one material and replace the cube in place instead.
        var seen = assets.cube_textures.add(
            renderer.render_cube(scene, assets, eye)
        )
        var chrome = assets.materials.add(
            Material(Color(255, 255, 255), kind=BASIC, env_map=seen)
        )
        scene.meshes = List[Mesh]()
        scene.add_mesh(Mesh(ground, floor, slab_node))
        scene.add_mesh(Mesh(box, orange, first_node))
        scene.add_mesh(Mesh(box, teal, second_node))
        scene.add_mesh(Mesh(ball, chrome, center_node))
        frames.append(renderer.render(scene, assets, camera))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
