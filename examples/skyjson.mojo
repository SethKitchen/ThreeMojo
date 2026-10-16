# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A metal ball under a sky that was written as JSON and read back.

    mojo run -I . examples/skyjson.mojo [path.png]

The page is Scene JSON. Six solid faces become a cube texture. The
writer stores that cube as the scene's environment, and the reader
builds its PMREM again. The picture is the ball that came back.
"""

from examples.output import example_destination, gallery_camera, write_example

from core.assets import Assets
from core.background import cube_background
from core.clock import Clock
from core.object3d import Object3D
from core.scene import Scene
from exporters.object_json import write_object_json
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from loaders.object_loader import load_object_json
from materials.material import physical_material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.cube_texture import CubeTexture
from render.framebuffer import Color, FloatColor, Framebuffer
from render.pmrem import pmrem_from_cube
from render.srgb import SRGB
from render.texture import BILINEAR, CLAMP, Texture
from renderers.renderer import Renderer, available_workers
from std.os import remove
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/environment.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime FACE = 16


def solid_face(color: Color) raises -> Texture:
    """Return one face of the sky, a solid color with a mip chain.

    Args:
        color: The face color, as authored in sRGB.

    Returns:
        A square texture.

    Raises:
        Error: If the texture is refused.
    """
    var shown = FloatColor(srgb=color).encode()
    var pixels = List[UInt8]()
    for _ in range(FACE * FACE):
        pixels.append(shown.r)
        pixels.append(shown.g)
        pixels.append(shown.b)
        pixels.append(255)
    return Texture(FACE, FACE, pixels^, CLAMP, BILINEAR, SRGB, True)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var document = String(destination.removesuffix(".png")) + ".json"

    var assets = Assets()
    var colors = List[Color]()
    colors.append(Color(220, 50, 40))
    colors.append(Color(40, 70, 200))
    colors.append(Color(235, 235, 240))
    colors.append(Color(40, 42, 48))
    colors.append(Color(40, 170, 70))
    colors.append(Color(230, 180, 40))
    var faces = List[Texture]()
    for index in range(6):
        faces.append(solid_face(colors[index]))
    var sky = assets.cube_textures.add(pmrem_from_cube(CubeTexture(faces^)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 40, 28))
    var metal = assets.materials.add(
        physical_material(
            Color(220, 220, 224),
            roughness=0.12,
            metalness=1.0,
            env_map=sky,
        )
    )

    var scene = Scene()
    scene.background = cube_background(sky)
    scene.environment = sky
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, metal, node))
    var lamp = Object3D()
    lamp.set_position(1.0, 1.4, 1.6)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.15))
    scene.add_light(directional_light(Color(255, 250, 240), lamp_node, 1.4))
    scene.update()
    write_object_json(document, scene, assets)

    var loaded = Scene()
    var loaded_assets = Assets()
    _ = load_object_json(document, loaded, loaded_assets)
    remove(document)
    var subject = loaded.meshes[0].node

    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.3, 0.35, 2.8),
        Vector3(0, 0, 0),
        field_of_view=Angle(38.0, DEGREE),
        near=Length(0.1, METER),
        far=Length(40.0, METER),
    )
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        loaded.node(subject).rotate_y(step)
        loaded.update()
        frames.append(renderer.render(loaded, loaded_assets, camera))

    write_example(frames, destination, DELAY_MS, FRAMES, frame_clock)
