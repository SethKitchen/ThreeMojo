# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A float target's light above a normal attachment, as a sphere turns.

    mojo run -I . examples/targets.mojo [path.png]

The page is Render target and framebuffer. One draw fills a float target
and a normal attachment. The top band is that light through ACES, so a
bright lamp keeps its color. The bottom band is the view-space normal.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, point_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.float_image import FloatImage
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    RenderTarget,
    TargetOutput,
)
from render.tonemap import ACES_FILMIC_TONE_MAPPING, tone_map
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/targets.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime HALF = 90
comptime FRAMES = 36
comptime DELAY_MS = 55


def channel_byte(value: Float32) -> UInt8:
    """Return a normal channel, from minus one to one, as a display byte.

    Args:
        value: One axis of a unit normal.

    Returns:
        The byte three.js's `packNormalToRGB` would store.
    """
    var packed = (value + 1) * 0.5
    if packed <= 0:
        return 0
    if packed >= 1:
        return 255
    return UInt8(packed * 255 + 0.5)


def show(light: FloatImage, normals: FloatImage) raises -> Framebuffer:
    """Stack tone-mapped light over packed normals.

    Args:
        light: The float color attachment, straight linear light.
        normals: The normal attachment, each axis from minus one to one.

    Returns:
        One image, light in the top band and normals in the bottom.

    Raises:
        Error: If a pixel is outside an image.
    """
    var frame = Framebuffer(WIDTH, HEIGHT, Color(0, 0, 0))
    for y in range(HALF):
        for x in range(WIDTH):
            var sample = light.get_pixel(x, y)
            var color = FloatColor(sample[0], sample[1], sample[2], sample[3])
            var shown = tone_map(color, ACES_FILMIC_TONE_MAPPING, 1.0)
            frame.set_pixel(x, y, shown.encode())
            var normal = normals.get_pixel(x, y)
            frame.set_pixel(
                x,
                y + HALF,
                Color(
                    channel_byte(normal[0]),
                    channel_byte(normal[1]),
                    channel_byte(normal[2]),
                ),
            )
    return frame^


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HALF, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))
    var assets = Assets()
    var ball = assets.geometries.add(sphere(Length(0.85, METER), 36, 24))
    var paint = assets.materials.add(Material(Color(180, 186, 196)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, paint, node))
    var bulb = Object3D()
    bulb.set_position(0.7, 0.9, 1.1)
    var bulb_node = scene.add(bulb^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.15))
    scene.add_light(point_light(Color(255, 220, 170), bulb_node, 8.0))

    var outputs = List[TargetOutput]()
    outputs.append(OUTPUT_COLOR)
    outputs.append(OUTPUT_NORMAL)
    var held = RenderTarget(WIDTH, HALF, Color(0, 0, 0), FLOAT_TARGET, outputs^)

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HALF),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.15, 0.2, 2.6), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        scene.node(node).rotate_y(step)
        scene.update()
        renderer.render_into(held, scene, assets, camera)
        var light = held.attachment(0)
        var normals = held.attachment(1)
        frames.append(show(light^, normals^))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
