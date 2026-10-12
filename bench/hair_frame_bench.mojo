# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure a 1920 x 1080 strand-hair frame by stage (#729).

    mojo run -I . bench/hair_frame_bench.mojo [frames [gpu width height]]

It grows the default groom of a six-foot male, 1500 guides with six
followers each, under a head sphere. It frames the head at 1920 x 1080 and
steps the guides only. After two warm-up frames it times each frame by
stage:

- `step+write`: one guides-only `HairSimulation.step` and its `write`.
- `shade`: `HairStrands.shade`: the density volume, self-shadow depths,
  shading and the vertex upload into the geometry store.
- `cpu prepare`: `Renderer.prepare_frame` alone, the host step that
  builds the screen-space triangles. It is measured separately and is
  not part of the frame total.
- `cpu render`: `Renderer.render` on every logical core: its own
  preparation, lighting, rasterization and resolve.
- `gpu prepare`: `Renderer.prepare_frame`, the host step that turns the
  scene into screen-space triangles and segments for the device.
- `gpu draw`: `GpuRenderer.draw`: the upload, the launch and the
  rasterization.
- `gpu read back`: `GpuRenderer.read_back`, which waits for the draw.

The GPU stages run only where a GPU is present, and only when the command
line gives their image size. The device rasterizer gives each pixel one
thread that walks every primitive, so its cost grows with pixels times
strand segments. Measure it at a small size first.

It reports the median, the 95th percentile and the slowest frame of each
stage. The numbers describe the machine that runs it, so it prints the
CPU model that Linux reports and the logical core count first.

After the timed frames it counts the visible strands of the last CPU
frame. A strand is visible when one of its points projects into the image
and no stored depth is nearer than that point. Then it prints PASS or FAIL
against the 16.667 millisecond budget of 60 frames per second, from the
median whole frame. A GPU run prints its own verdict from the median frame
with the GPU raster.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import UNTONED
from extensions.humanoid.genome import Genome
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.head.hair.collider import HairCollider
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairSimulation,
    HairWind,
)
from extensions.humanoid.skeleton.head.hair.strands import add_groom
from extensions.humanoid.spec import HumanoidSpec
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from lights.lighting import Lighting
from render.framebuffer import Color, Framebuffer
from render.gpu import GpuRenderer
from render.rasterizer import SHADE_TEXTURE
from renderers.renderer import Renderer, camera_position, toward_camera
from std.sys import argv, has_accelerator, num_logical_cores
from std.time import perf_counter_ns
from units.si import DEGREE, FOOT, METER, Angle, Length

comptime WIDTH = 1920
comptime HEIGHT = 1080
comptime WARMUP = 2
comptime BUDGET_MS = 1000.0 / 60.0


@fieldwise_init
struct _Head(DistanceField, ImplicitlyCopyable):
    """A sphere standing in for the scalp."""

    var center: Vector3
    var radius: Float32

    def distance(self, point: Vector3) -> Float32:
        return (point - self.center).length() - self.radius


def _sorted(var times: List[Int]) -> List[Int]:
    for i in range(1, len(times)):
        var j = i
        while j > 0 and times[j - 1] > times[j]:
            times.swap_elements(j - 1, j)
            j -= 1
    return times^


def _percentile(times: List[Int], fraction: Float64) -> Float64:
    # Nearest rank on a sorted list.
    var rank = Int(fraction * Float64(len(times)) + 0.999999) - 1
    rank = max(0, min(rank, len(times) - 1))
    return Float64(times[rank]) / 1e6


def _report(label: String, var times: List[Int]) -> String:
    var sorted = _sorted(times^)
    return (
        label
        + " p50 "
        + String(_percentile(sorted, 0.5))
        + " p95 "
        + String(_percentile(sorted, 0.95))
        + " max "
        + String(_percentile(sorted, 1.0))
        + " ms"
    )


def _cpu_model() -> String:
    # Linux only. Other systems print that the model is unknown.
    try:
        with open("/proc/cpuinfo", "r") as info:
            for line in info.read().split("\n"):
                if line.startswith("model name"):
                    return String(line.split(":", 1)[1].strip())
    except:
        pass
    return "unknown"


def _verdict(label: String, var times: List[Int]) -> String:
    var median = _percentile(_sorted(times^), 0.5)
    var result = String("FAIL")
    if median <= BUDGET_MS:
        result = "PASS"
    return (
        "60 fps at 1920x1080, "
        + label
        + ": "
        + result
        + " (median "
        + String(median)
        + " ms, budget "
        + String(BUDGET_MS)
        + " ms)"
    )


def main() raises:
    print("CPU", _cpu_model(), "; logical cores", num_logical_cores())
    var frames = 10
    var gpu_width = 0
    var gpu_height = 0
    var args = argv()
    if len(args) > 1:
        frames = Int(String(args[1]))
    if len(args) > 4 and String(args[2]) == "gpu":
        gpu_width = Int(String(args[3]))
        gpu_height = Int(String(args[4]))
    var person = HumanoidSpec(Length(6.0, FOOT), MALE, UNTONED, Genome())
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var hair = add_groom(scene, assets, root, person)
    var low = Vector3(1e9, 1e9, 1e9)
    var high = Vector3(-1e9, -1e9, -1e9)
    for p in hair.groom.points:
        low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
        high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
    var middle = (low + high) * 0.5
    # A head sphere under the hair, so strands behind it are hidden.
    var head = scene.add(Object3D())
    scene.node(head).set_position(middle.x, middle.y, middle.z)
    var skin = assets.materials.add(Material(Color(200, 160, 140)))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.09, METER), 48, 32)),
            skin,
            head,
        )
    )
    var key = scene.add(Object3D())
    scene.node(key).set_position(middle.x + 1, middle.y + 2, middle.z + 2)
    scene.add_light(directional_light(Color(255, 250, 240), key, 1.0))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.update()
    var camera = PerspectiveCamera(
        Angle(30.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(20.0, METER),
    )
    var eye = middle + Vector3(0.25, 0.05, 0.65)
    camera.place(eye, middle)
    var collider = HairCollider(
        _Head(middle, 0.09),
        low - Vector3(0.1, 0.1, 0.1),
        high + Vector3(0.1, 0.1, 0.1),
    )
    var motion = HairSimulation(hair.groom, guides_only=True)
    var wind = HairWind(Vector3(1, 0, 0.3), 0.5)
    var lights: List[HairLight] = [
        HairLight(Vector3(0.41, 0.82, 0.41), Vector3(3, 3, 3))
    ]
    var ambient = Vector3(0.1, 0.1, 0.1)
    var renderer = Renderer(WIDTH, HEIGHT, num_logical_cores())
    var gpu = has_accelerator() and gpu_width > 0 and gpu_height > 0

    var strands = len(hair.groom.starts) - 1
    var points = len(hair.groom.points)
    var screen = camera.screen_matrix(WIDTH, HEIGHT)
    var visible = 0
    for s in range(strands):
        for i in range(hair.groom.starts[s], hair.groom.starts[s + 1]):
            var q = screen.transform_point(hair.groom.points[i])
            if q.x >= 0 and q.y >= 0 and q.x < WIDTH and q.y < HEIGHT:
                visible += 1
                break
    var paint = assets.materials.get(hair.material.value())
    var triangles = (
        len(renderer.prepare_frame(scene, assets, camera).whole_corners()) // 3
    )
    print(
        "1920x1080; strands",
        strands,
        "points",
        points,
        "points per strand",
        Float64(points) / Float64(strands),
        "strands with a point projected into the image at rest",
        visible,
        "; line width",
        paint.line_width.size,
        "px, opacity",
        paint.opacity,
        "with hashed strand coverage; triangles emitted",
        triangles,
        "; density resolution",
        hair.density.resolution,
        "; raster workers",
        renderer.workers,
        "; budget",
        BUDGET_MS,
        "ms",
    )

    # Which part of the render is the hair: the rest pose with each part
    # hidden, one render each. The animated frames below differ.
    var hair_node = hair.node.value()
    for part in range(3):
        scene.node(hair_node).visible = part != 1
        scene.node(head).visible = part != 2
        if part == 0:
            scene.node(hair_node).visible = False
            scene.node(head).visible = False
        scene.update()
        _ = renderer.render(scene, assets, camera)
        var t = perf_counter_ns()
        _ = renderer.render(scene, assets, camera)
        var label = String("empty frame")
        if part == 1:
            label = "head only"
        elif part == 2:
            label = "hair only"
        print(label, Float64(perf_counter_ns() - t) / 1e6, "ms")
    scene.node(hair_node).visible = True
    scene.node(head).visible = True
    scene.update()

    var steps = List[Int]()
    var shades = List[Int]()
    var cpu = List[Int]()
    var cpu_prepares = List[Int]()
    var prepares = List[Int]()
    var draws = List[Int]()
    var reads = List[Int]()
    var cpu_total = List[Int]()
    var gpu_total = List[Int]()
    var last = Framebuffer(1, 1, Color(0, 0, 0))
    var device = Optional[GpuRenderer]()
    if gpu:
        device = GpuRenderer(gpu_width, gpu_height)
        print("GPU stages at", gpu_width, "x", gpu_height)
    for frame in range(WARMUP + frames):
        var stepped = perf_counter_ns()
        motion.step(collider, wind)
        motion.write(hair.groom)
        var shaded = perf_counter_ns()
        hair.shade(assets, lights, eye, ambient)
        var rendered = perf_counter_ns()
        last = renderer.render(scene, assets, camera)
        var prepared_cpu = perf_counter_ns()
        _ = renderer.prepare_frame(scene, assets, camera)
        var done_cpu = perf_counter_ns()
        var gpu_start = done_cpu
        var gpu_drawn = done_cpu
        var gpu_drawing = done_cpu
        var gpu_read = done_cpu
        if gpu:
            var small = Renderer(gpu_width, gpu_height, num_logical_cores())
            var prepared = small.prepare_frame(scene, assets, camera)
            var lighting = Lighting(
                scene,
                camera.visible_layers(),
                camera_position(scene, camera),
                toward_camera(scene, camera),
            )
            gpu_drawing = perf_counter_ns()
            device.value().draw(
                prepared.whole_corners(),
                small.background,
                SHADE_TEXTURE,
                lighting,
                lines=prepared.segments,
                draws=prepared.draws,
            )
            gpu_drawn = perf_counter_ns()
            _ = device.value().read_back()
            gpu_read = perf_counter_ns()
            # Progress, after the frame's last measured stage.
            print(
                "frame",
                frame,
                "gpu prepare",
                Float64(gpu_drawing - gpu_start) / 1e6,
                "draw",
                Float64(gpu_drawn - gpu_drawing) / 1e6,
                "read back",
                Float64(gpu_read - gpu_drawn) / 1e6,
                "ms",
                flush=True,
            )
        if frame < WARMUP:
            continue
        steps.append(Int(shaded - stepped))
        shades.append(Int(rendered - shaded))
        cpu.append(Int(prepared_cpu - rendered))
        cpu_prepares.append(Int(done_cpu - prepared_cpu))
        cpu_total.append(Int(prepared_cpu - stepped))
        if gpu:
            prepares.append(Int(gpu_drawing - gpu_start))
            draws.append(Int(gpu_drawn - gpu_drawing))
            reads.append(Int(gpu_read - gpu_drawn))
            gpu_total.append(Int((rendered - stepped) + (gpu_read - gpu_start)))
    # Visible strands of the last CPU frame: a point inside the image that
    # no stored depth hides. The tolerance is far below the depth step
    # between two hair layers.
    var shown = 0
    for s in range(strands):
        for i in range(hair.groom.starts[s], hair.groom.starts[s + 1]):
            var q = screen.transform_point(hair.groom.points[i])
            if q.x >= 0 and q.y >= 0 and q.x < WIDTH and q.y < HEIGHT:
                if q.z <= last.depth_at(Int(q.x), Int(q.y)) + 1e-5:
                    shown += 1
                    break
    print("visible strands in the last CPU frame", shown, "of", strands)
    var verdict = _verdict("frame with cpu render", cpu_total.copy())
    print(_report("step+write", steps^))
    print(_report("shade", shades^))
    print(_report("cpu prepare (diagnostic, not in the frame)", cpu_prepares^))
    print(_report("cpu render", cpu^))
    print(_report("frame with cpu render", cpu_total^))
    print(verdict)
    if gpu:
        print(_report("gpu prepare", prepares^))
        print(_report("gpu draw", draws^))
        print(_report("gpu read back", reads^))
        print(_verdict("frame with gpu raster", gpu_total.copy()))
        print(_report("frame with gpu raster", gpu_total^))
    else:
        print("The GPU stages did not run: no GPU, or no size given.")
