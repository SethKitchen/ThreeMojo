# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Colored splats turn in a loose cloud.

    mojo run -I . examples/cloud.mojo [path.png]

The page is Gaussian splats. The splats are built in code, not read
from a file. The scene is drawn first, then `draw_gaussian_splat` blends
the cloud, and `resolve` makes the picture. The cloud turns one whole
turn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.gaussian_splat_utils import (
    create_gaussian_splat_geometry,
    write_color_bytes,
    write_covariance,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.splat_raster import draw_gaussian_splat
from render.target import RenderTarget
from renderers.renderer import Renderer, available_workers
from std.math import cos, pi, sin, sqrt
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import DEGREE, METER, Angle, Length, MILLISECOND

comptime DEFAULT_OUTPUT = "out/gaussian.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime SPLATS = 48


def _byte(index: Int, channel: Int) -> UInt8:
    """Return one channel of a repeating palette.

    Args:
        index: Which splat.
        channel: Zero for red, one for green, two for blue.

    Returns:
        The byte.
    """
    var band = index % 6
    if channel == 0:
        if band == 0 or band == 1 or band == 5:
            return 255
        if band == 4:
            return 210
        return 70
    if channel == 1:
        if band == 1:
            return 186
        if band == 2:
            return 170
        if band == 3:
            return 90
        return 84
    if band == 2:
        return 160
    if band == 3:
        return 210
    if band == 4:
        return 230
    return 64


def _splats(node: NodeId) raises -> GaussianSplat:
    """Return a ball of soft colored splats on `node`.

    Args:
        node: The scene node that places the cloud.

    Returns:
        The splats.

    Raises:
        Error: If the arrays disagree, or the node id is negative.
    """
    var centers = List[Float32]()
    var covariances = List[Float32]()
    var colors = List[UInt8]()
    for _ in range(SPLATS * 6):
        covariances.append(0)
    for _ in range(SPLATS * 4):
        colors.append(0)
    var golden = Float32(pi) * (3 - sqrt(Float32(5)))
    for index in range(SPLATS):
        var t = Float32(index) / Float32(SPLATS - 1)
        var y = (1 - 2 * t) * 0.55
        var ring = sqrt(1 - (1 - 2 * t) * (1 - 2 * t))
        var theta = Float32(index) * golden
        var reach = 0.35 + 0.4 * sin(Float32(index) * 0.7)
        centers.append(cos(theta) * ring * reach)
        centers.append(y)
        centers.append(sin(theta) * ring * reach)
        var scale = 0.09 + 0.05 * Float64(index % 4) / 3
        write_covariance(
            covariances, index * 6, scale, scale * 0.75, scale, 0, 0, 0, 1
        )
        write_color_bytes(
            colors,
            index * 4,
            Float64(Int(_byte(index, 0))),
            Float64(Int(_byte(index, 1))),
            Float64(Int(_byte(index, 2))),
            230.0,
        )
    return GaussianSplat(
        create_gaussian_splat_geometry(centers^, covariances^, colors^),
        node,
    )


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    mut cloud: GaussianSplat,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the cloud by `step`, draw the scene, then the splats.

    Args:
        renderer: The renderer to draw with.
        camera: The camera, placed in front of the cloud.
        assets: The scene's assets. The cloud holds its own geometry.
        scene: The persistent scene, edited in place.
        cloud: The splats. Sorting updates them.
        node: The node the cloud rides.
        step: How much further the cloud turns.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene, the splat draw or the resolve is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    var target = RenderTarget(WIDTH, HEIGHT, Color(12, 14, 20))
    renderer.render_into(target, scene, assets, camera)
    draw_gaussian_splat(target, scene, cloud, camera)
    return target.resolve()


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(12, 14, 20))
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var cloud = _splats(node)

    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.35, 0.28, 2.55), Vector3(0, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(
            frame_at(renderer, camera, assets, scene, cloud, node, step)
        )

    print(
        '{"frames_ms": ',
        frame_clock.elapsed().to(MILLISECOND),
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
