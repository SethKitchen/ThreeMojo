# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ten spheres from chalk to mirror, and from dielectric to metal.

    mojo run -I . examples/physical.mojo [path.png]

The page is Materials. The top row is a dielectric and the bottom row a
metal, and the roughness runs from one on the left to zero on the right.
Every sphere is a `standard_material` under one lamp and a sky it
reflects; the sky's faces carry a mip chain, which is what a rough
sphere reads. The last sphere of each row has a clear coat over it.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import cube_background
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import physical_material, standard_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_texture import (
    FACE_COUNT,
    CubeTexture,
    face_forward,
    face_up,
)
from render.framebuffer import Color, FloatColor
from render.png import encode
from render.srgb import SRGB
from render.texture import BILINEAR, CLAMP, Texture
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/physical.png"
comptime WIDTH = 480
comptime HEIGHT = 220
# The size of each face of the sky.
comptime SKY_SIZE = 64
# How many spheres a row holds, and how far apart they stand.
comptime ACROSS = 5
comptime SPACING = Float32(1.15)


def sky_face(face: Int) raises -> Texture:
    """Return one face of a sky: blue overhead, pale at the horizon and
    a warm brown below, with a mip chain for the rough spheres to read.

    Args:
        face: `POSITIVE_X` through `NEGATIVE_Z`.

    Returns:
        The face, clamped, filtered and mipmapped.

    Raises:
        Error: If the texture cannot be built.
    """
    var forward = face_forward(face)
    var up = face_up(face)
    var right = forward
    right.cross(up)
    var zenith = FloatColor(srgb=Color(60, 110, 230))
    var horizon = FloatColor(srgb=Color(235, 235, 245))
    var ground = FloatColor(srgb=Color(110, 80, 50))
    var pixels = List[UInt8]()
    for row in range(SKY_SIZE):
        for column in range(SKY_SIZE):
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
    return Texture(SKY_SIZE, SKY_SIZE, pixels^, CLAMP, BILINEAR, SRGB, True)


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
    var ball = assets.geometries.add(sphere(Length(0.5, METER), 40, 28))

    var scene = Scene()
    scene.background = cube_background(sky)
    scene.environment = sky
    for row in range(2):
        var metalness = Float32(row)
        for column in range(ACROSS):
            var roughness = 1 - Float32(column) / Float32(ACROSS - 1)
            var paint = standard_material(
                Color(200, 60, 50),
                roughness=roughness,
                metalness=metalness,
                env_map=sky,
            )
            if column == ACROSS - 1:
                paint = physical_material(
                    Color(200, 60, 50),
                    roughness=0.6,
                    metalness=metalness,
                    clearcoat=1.0,
                    clearcoat_roughness=0.1,
                    env_map=sky,
                )
            var stand = Object3D()
            stand.set_position(
                (Float32(column) - Float32(ACROSS - 1) / 2) * SPACING,
                (0.5 - Float32(row)) * SPACING,
                0,
            )
            var node = scene.add(stand^)
            scene.add_mesh(Mesh(ball, assets.materials.add(paint), node))

    var lamp = Object3D()
    lamp.set_position(-1.0, 2.0, 2.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 250, 240), lamp_node, 2.5))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.3))
    scene.update()

    var camera = PerspectiveCamera(
        Angle(32.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.3, 6.2), Vector3(0, 0, 0))

    var image = renderer.render(scene, assets, camera)
    Path(destination).write_bytes(encode(image))
    print("Wrote", destination)
