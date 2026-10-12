# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The strand-hair reference scenes, side by side (#298).

    mojo run -I . examples/hair_reference.mojo [path.png]

The page is Strand hair rendering. The image has six panels, each 256
pixels square, left to right and top to bottom:

1. Fine silhouettes: half-pixel fibers at opacity 0.65, with stochastic
   strand coverage.
2. The same fibers as the ground truth: solid coverage at four times the
   size, box-filtered and blended at opacity 0.65.
3. Crossing strands: two layers of fibers at distinct depths.
4. Self-shadow: a curtain of long strands in four rows under a front
   light, seen from the side. Each row farther from the light is darker.
5. Backlight: the same curtain lit from directly behind, with a TT
   weight of 0.1.
6. Moving long hair: the curtain after twelve steps in the wind, over a
   receiver that shows the strands' cast shadow.

The CPU rasterizer draws every panel. The scenes are the ones that
`tests/test_hair_reference_scenes.mojo` and `tests/test_gpu.mojo` check.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.humanoid.skeleton.head.hair.reference import (
    FIBER_COLOR,
    HairReferenceRig,
    REFERENCE_BACKGROUND,
    add_crossing_strands,
    add_fine_silhouettes,
    reference_camera,
    supersampled_coverage,
)
from extensions.humanoid.skeleton.head.hair.shading import HairLook
from math.vector3 import Vector3
from objects.line_segments2 import SOLID_LINE_COVERAGE, STRAND_LINE_COVERAGE
from render.framebuffer import Color, Framebuffer
from render.png import encode
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Length, METER

comptime DEFAULT_OUTPUT = "out/hair_reference.png"
comptime PANEL = 256
comptime COLUMNS = 3
comptime SUPERSAMPLE = 4
comptime OPACITY = Float32(0.65)


def _flat(scene: Scene, assets: Assets, size: Int) raises -> Framebuffer:
    """Render a flat reference scene through the two-meter camera."""
    var renderer = Renderer(size, size, available_workers())
    renderer.set_background(REFERENCE_BACKGROUND)
    return renderer.render(scene, assets, reference_camera(Length(2, METER)))


def _fine(size: Int, solid: Bool) raises -> Framebuffer:
    """Render twelve half-pixel fibers at `size` pixels."""
    var scene = Scene()
    var assets = Assets()
    add_fine_silhouettes(
        scene,
        assets,
        12,
        Length(Float32(0.5) * 2 / Float32(PANEL), METER),
        OPACITY,
        SOLID_LINE_COVERAGE if solid else STRAND_LINE_COVERAGE,
    )
    scene.update()
    return _flat(scene, assets, size)


def _truth() raises -> Framebuffer:
    """Return the supersampled ground truth, blended over the background."""
    var coverage = supersampled_coverage(
        _fine(PANEL * SUPERSAMPLE, True), SUPERSAMPLE, REFERENCE_BACKGROUND, 1
    )
    var image = Framebuffer(PANEL, PANEL, REFERENCE_BACKGROUND)
    for y in range(PANEL):
        for x in range(PANEL):
            var a = coverage[y * PANEL + x] * OPACITY
            image.set_pixel(
                x,
                y,
                Color(
                    UInt8(Float32(FIBER_COLOR.r) * a + 0.5),
                    UInt8(Float32(FIBER_COLOR.g) * a + 0.5),
                    UInt8(Float32(FIBER_COLOR.b) * a + 0.5),
                ),
            )
    return image^


def _crossing() raises -> Framebuffer:
    """Render eight fibers in each of two crossing layers."""
    var scene = Scene()
    var assets = Assets()
    add_crossing_strands(
        scene,
        assets,
        8,
        Length(0.03, METER),
        OPACITY,
        OPACITY,
        STRAND_LINE_COVERAGE,
    )
    scene.update()
    return _flat(scene, assets, PANEL)


def _curtain(rig: HairReferenceRig) raises -> Framebuffer:
    """Render a curtain rig through its own camera."""
    var renderer = Renderer(PANEL, PANEL, available_workers())
    renderer.set_background(Color(24, 26, 30))
    return renderer.render(rig.scene, rig.assets, rig.camera)


def _paste(mut page: Framebuffer, panel: Framebuffer, index: Int) raises:
    """Copy one panel into its place on the page."""
    var left = (index % COLUMNS) * PANEL
    var top = (index // COLUMNS) * PANEL
    for y in range(PANEL):
        for x in range(PANEL):
            page.set_pixel(left + x, top + y, panel.get_pixel(x, y))


def main() raises:
    var destination = String(DEFAULT_OUTPUT)
    var args = argv()
    if len(args) > 1:
        destination = String(args[1])
    var look = HairLook(Vector3(0.3, 0.18, 0.1))
    var page = Framebuffer(PANEL * COLUMNS, PANEL * 2, REFERENCE_BACKGROUND)
    _paste(page, _fine(PANEL, False), 0)
    _paste(page, _truth(), 1)
    _paste(page, _crossing(), 2)
    var front = HairReferenceRig(
        look, Vector3(0, 0.3, 1), guides=24, clump=Length(0.002, METER)
    )
    # Look from the side, so the four rows stand side by side.
    front.eye = Vector3(4, 0, -0.06)
    front.camera.place(front.eye, Vector3(0, 0, -0.06))
    front.advance(0)
    _paste(page, _curtain(front), 3)
    var transmitting = look
    transmitting.weight_tt = 0.1
    var back = HairReferenceRig(
        transmitting,
        Vector3(0, -0.035, -1),
        guides=24,
        clump=Length(0.002, METER),
    )
    _paste(page, _curtain(back), 4)
    var moving = HairReferenceRig(
        look,
        Vector3(0, 0.3, 1),
        guides=24,
        clump=Length(0.002, METER),
        receiver=True,
    )
    moving.advance(12)
    _paste(page, _curtain(moving), 5)
    Path(destination).write_bytes(encode(page))
    print("Wrote", destination)
