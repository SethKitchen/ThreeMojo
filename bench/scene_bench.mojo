# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A whole scene through the CPU renderer, timed stage by stage.

    mojo run -I . bench/scene_bench.mojo

`raster_bench` fills one flat triangle, which measures coverage and nothing
else. A frame of an actual scene is transforms, clipping, per-fragment
lighting, trilinear texture sampling and blending, and which of those costs
what is the question this answers. The scene is a mipmapped, bilinear
checkerboard sphere of a few thousand triangles at a modest resolution: enough
work that the per-frame fixed costs vanish, small enough to run in a second.

Each stage is timed on its own, by running the same calls `Renderer.render`
makes with a clock between them, rather than by subtracting one whole
measurement from another. The difference of two measurements used to stand
in for the rasterizer, and it moved when something that was neither the
rasterizer nor the stage subtracted got faster. `prepare` is everything
before pixels -- single-threaded and per vertex -- `rasterize` is the
triangle pass, `resolve` is the encode to bytes, and `frame` is the whole
call, which is the number a caller sees. The last rows repeat the frame with
one worker per core, which is where the rasterizer's and the resolve's share
should shrink and `prepare`'s should not.

Standard library only: this does not touch the GPU backend and runs without
MAX.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.fog import FogView
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from lights.lighting import Lighting
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.rasterizer import rasterize_all
from render.target import RenderTarget
from render.texture import BILINEAR, REPEAT, checkerboard
from render.tonemap import NO_TONE_MAPPING
from renderers.renderer import (
    Renderer,
    available_workers,
    camera_position,
    camera_up,
    toward_camera,
)
from std.time import perf_counter_ns
from units.si import Angle, DEGREE, Length, METER

comptime REPEATS = 5
# The stages, in the order a frame runs them.
comptime PREPARE = 0
comptime RASTERIZE = 1
comptime RESOLVE = 2
comptime FRAME = 3
comptime STAGES = 4


def build(mut scene: Scene, mut assets: Assets) raises:
    """Put a textured sphere and two lights into the scene.

    Args:
        scene: The scene to fill.
        assets: The stores to put the geometry, material and texture in.

    Raises:
        Error: If any part cannot be built.
    """
    var ball = assets.geometries.add(sphere(Length(1.0, METER), 96, 64))
    var board = assets.textures.add(
        checkerboard(
            128,
            16,
            Color(245, 245, 250),
            Color(35, 70, 150),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var paint = assets.materials.add(Material(Color(255, 255, 255), board))
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(ball, paint, node))
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))
    scene.update()


def time_stages(
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: PerspectiveCamera,
) raises -> List[Int]:
    """Return the fastest of several runs of each stage, in microseconds.

    The calls are the ones `Renderer.render` makes, in its order, so the
    stages add up to a frame; the whole call is timed as well, separately,
    so the sum can be checked against what a caller pays.
    """
    var best = List[Int](length=STAGES, fill=-1)
    for _ in range(REPEATS):
        var lighting = Lighting(
            scene,
            visible=camera.visible_layers(),
            eye=camera_position(scene, camera),
            toward_eye=toward_camera(scene, camera),
            up=camera_up(scene, camera),
        )
        var fog = FogView(scene.fog)
        var started = perf_counter_ns()
        var corners = renderer.prepare(scene, assets, camera)
        var prepared = perf_counter_ns()
        var target = RenderTarget(
            renderer.width, renderer.height, renderer.background
        )
        rasterize_all(
            corners,
            target,
            renderer.shading,
            assets.textures,
            lighting,
            renderer.workers,
            fog,
        )
        var rasterized = perf_counter_ns()
        var image = target.resolve(renderer.workers, NO_TONE_MAPPING, 1.0)
        var resolved = perf_counter_ns()
        var whole = renderer.render(scene, assets, camera)
        var finished = perf_counter_ns()
        # Keep both images alive past the timers so they cannot be
        # optimized away.
        if image.width == 0 or whole.width == 0 or len(corners) == 0:
            raise Error("unreachable")
        var stages: List[Int] = [
            Int(prepared - started),
            Int(rasterized - prepared),
            Int(resolved - rasterized),
            Int(finished - resolved),
        ]
        for stage in range(STAGES):
            var elapsed = stages[stage] // 1000
            if best[stage] < 0 or elapsed < best[stage]:
                best[stage] = elapsed
    return best^


def report(
    width: Int,
    height: Int,
    workers: Int,
    scene: Scene,
    assets: Assets,
    camera: PerspectiveCamera,
) raises:
    """Time one configuration and print the row."""
    var renderer = Renderer(width, height, workers=workers)
    var best = time_stages(renderer, scene, assets, camera)
    print(
        String(width) + "x" + String(height),
        " workers",
        workers,
        "  prepare",
        best[PREPARE],
        "us   rasterize",
        best[RASTERIZE],
        "us   resolve",
        best[RESOLVE],
        "us   frame",
        best[FRAME],
        "us",
    )


def main() raises:
    var scene = Scene()
    var assets = Assets()
    build(scene, assets)
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 4.0 / 3.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0.3, 3.0), Vector3(0, 0, 0))

    var triangles = assets.geometries.get(
        scene.meshes[0].geometry
    ).triangle_count()
    print("A mipmapped checkerboard sphere of", triangles, "triangles.")
    print("Best of", REPEATS, "runs, microseconds, lower is better.")
    print("rasterize includes clearing the target; frame is the whole call.")
    print()
    report(320, 240, 1, scene, assets, camera)
    report(640, 480, 1, scene, assets, camera)
    report(1280, 720, 1, scene, assets, camera)
    var cores = available_workers()
    print()
    print("With", cores, "workers:")
    report(320, 240, cores, scene, assets, camera)
    report(640, 480, cores, scene, assets, camera)
    report(1280, 720, cores, scene, assets, camera)
