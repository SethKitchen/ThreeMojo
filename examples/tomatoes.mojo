# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Three tomatoes, scanned as 445,409 Gaussian splats, with the camera circling.

    mojo run -I . examples/tomatoes.mojo [path.png]

This is the three.js example `webgpu_gaussian_splat`, with its tomato scan.
`read_spz` decodes `assets/tomatoes/tomatoes.v4.spz`. The camera stands where the example puts it: on
the side of the scan's bounding sphere that `(0, 0.35, 1)` names. It stands closer than
the example's 15 % beyond the distance that fits the sphere in a 50 degree
view, so that the tomatoes fill a picture this small. It then goes once round
the scan's vertical axis. The splats are sorted and blended for every frame,
with the spherical harmonics of the scan shading them.

The example sets `workingColorSpace` to sRGB, so the splats' colors blend as
they are stored and reach the screen unchanged. `render.working_space` does
the same, and the background is the example's `0x07080f`.

The scan is by Grail, CC BY 4.0: see `assets/tomatoes/ATTRIBUTION.md`.
"""

from cameras.fit_sphere import fit_sphere
from cameras.perspective_camera import PerspectiveCamera
from core.clock import Clock
from core.object3d import NodeId, Object3D
from core.scene import Scene
from loaders.spz import read_spz
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.splat_raster import draw_gaussian_splat
from render.working_space import resolve_srgb_working, srgb_working_target
from std.math import cos, pi, sin
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import DEGREE, METER, MILLISECOND, RADIAN, Angle, Length

comptime DEFAULT_SCAN = "assets/tomatoes/tomatoes.v4.spz"
comptime DEFAULT_OUTPUT = "out/tomatoes.png"
comptime WIDTH = 260
comptime HEIGHT = 200
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime BACKGROUND = Color(7, 8, 15)
"""The example's `scene.background`, `0x07080f`."""
comptime MARGIN = Float32(0.8)
"""How many times the tight-fit distance the camera stands away. The example
uses 1.15, which `cameras.fit_sphere.FIT_MARGIN` holds."""
comptime VIEW_FROM = Vector3(0, 0.35, 1)
"""The example's `cameraPosition` for this scan: which side the camera takes."""


def frame_at(
    mut scan: GaussianSplat,
    scene: Scene,
    mut camera: PerspectiveCamera,
    center: Vector3,
    radius: Length,
    turn: Angle,
) raises -> Framebuffer:
    """Stand the camera `turn` round the scan and draw one frame.

    Args:
        scan: The splats. Sorting updates them.
        scene: The updated scene that holds the scan's node.
        camera: The camera, placed by this call.
        center: The center of the scan's bounding sphere.
        radius: The radius of the scan's bounding sphere.
        turn: How far round the vertical axis the camera has gone.

    Returns:
        The frame, as the screen shows it.

    Raises:
        Error: If the camera, the splat draw or the resolve is refused.
    """
    var angle = turn.value
    var side = Vector3(
        VIEW_FROM.x * cos(angle) + VIEW_FROM.z * sin(angle),
        VIEW_FROM.y,
        VIEW_FROM.z * cos(angle) - VIEW_FROM.x * sin(angle),
    )
    _ = fit_sphere(camera, center, radius, side, MARGIN)
    var target = srgb_working_target(WIDTH, HEIGHT, BACKGROUND)
    draw_gaussian_splat(target, scene, scan, camera)
    return resolve_srgb_working(target)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var load_clock = Clock()
    load_clock.start()
    var scene = Scene()
    var node: NodeId = scene.add(Object3D())
    scene.update()
    var scan = GaussianSplat(read_spz(DEFAULT_SCAN), node)
    scan.compute_bounding_sphere()
    var sphere = scan.bounding_sphere.value()
    print(
        '{"load_ms": ',
        load_clock.elapsed().to(MILLISECOND),
        ', "splats": ',
        scan.count(),
        "}",
        sep="",
        file=stderr,
    )

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    var radius = Length(sphere.radius, METER)
    var frame_clock = Clock()
    frame_clock.start()
    var frames = List[Framebuffer]()
    for frame in range(FRAMES):
        var turn = Angle(
            Float32(2 * pi) * Float32(frame) / Float32(FRAMES), RADIAN
        )
        frames.append(
            frame_at(scan, scene, camera, sphere.center, radius, turn)
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
