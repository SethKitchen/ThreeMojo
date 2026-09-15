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

Two numbers per row. `prepare` is everything before pixels -- the part that is
single-threaded and per vertex -- and `render` is the whole frame including
it, so the difference is rasterization. The last rows repeat the frame with
one worker per core, which is where the rasterizer's share should shrink and
`prepare`'s should not.

Standard library only: this does not touch the GPU backend and runs without
MAX.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.target import RenderTarget
from render.texture import BILINEAR, REPEAT, checkerboard
from renderers.renderer import Renderer, available_workers
from std.time import perf_counter_ns
from units.si import Angle, DEGREE, Length, METRE

comptime REPEATS = 5


def build(mut scene: Scene, mut assets: Assets) raises:
    """Put a textured sphere and two lights into the scene.

    Args:
        scene: The scene to fill.
        assets: The stores to put the geometry, material and texture in.

    Raises:
        Error: If any part cannot be built.
    """
    var ball = assets.geometries.add(sphere(Length(1.0, METRE), 96, 64))
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


def time_prepare(
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: PerspectiveCamera,
) raises -> Int:
    """Return the fastest of several `prepare` calls, in microseconds."""
    var best = -1
    for _ in range(REPEATS):
        var started = perf_counter_ns()
        var corners = renderer.prepare(scene, assets, camera)
        var elapsed = Int(perf_counter_ns() - started) // 1000
        if len(corners) == 0:
            raise Error("the scene prepared no triangles")
        if best < 0 or elapsed < best:
            best = elapsed
    return best


def time_render(
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: PerspectiveCamera,
) raises -> Int:
    """Return the fastest of several whole frames, in microseconds."""
    var best = -1
    for _ in range(REPEATS):
        var started = perf_counter_ns()
        var image = renderer.render(scene, assets, camera)
        var elapsed = Int(perf_counter_ns() - started) // 1000
        # Keep the image alive past the timer so it cannot be optimized away.
        if image.width == 0:
            raise Error("unreachable")
        if best < 0 or elapsed < best:
            best = elapsed
    return best


def time_resolve(width: Int, height: Int, workers: Int) raises -> Int:
    """Return the fastest of several clear-and-resolve passes, in microseconds.

    The fixed cost of a frame that draws nothing: allocating the linear
    target and encoding every pixel to sRGB. Everything the rasterizer does
    sits on top of this.
    """
    var best = -1
    for _ in range(REPEATS):
        var started = perf_counter_ns()
        var target = RenderTarget(width, height, Color(16, 18, 26))
        var image = target.resolve(workers)
        var elapsed = Int(perf_counter_ns() - started) // 1000
        if image.width == 0:
            raise Error("unreachable")
        if best < 0 or elapsed < best:
            best = elapsed
    return best


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
    var prepared = time_prepare(renderer, scene, assets, camera)
    var resolved = time_resolve(width, height, workers)
    var rendered = time_render(renderer, scene, assets, camera)
    print(
        String(width) + "x" + String(height),
        " workers",
        workers,
        "  prepare",
        prepared,
        "us   clear+resolve",
        resolved,
        "us   render",
        rendered,
        "us   of which rasterize",
        rendered - prepared - resolved,
        "us",
    )


def main() raises:
    var scene = Scene()
    var assets = Assets()
    build(scene, assets)
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 4.0 / 3.0, Length(0.1, METRE), Length(100.0, METRE)
    )
    camera.place(Vector3(0, 0.3, 3.0), Vector3(0, 0, 0))

    var triangles = assets.geometries.get(
        scene.meshes[0].geometry
    ).triangle_count()
    print("A mipmapped checkerboard sphere of", triangles, "triangles.")
    print("Best of", REPEATS, "runs, microseconds, lower is better.")
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
