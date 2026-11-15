# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A synthetic CT perfusion scan of a stroke in the head phantom, with
maps of CBF and Tmax and the ischemic core and tissue at risk.

    mojo run -I . examples/perfusion.mojo [out/perfusion.png]

The page is Medical imaging. One axial slice of the head phantom is on 96
voxels of 2.08 mm, 5 mm thick, over 40 frames 1.5 s apart. The arterial
curve is a gamma variate that peaks at 300 HU of enhancement. Each tissue
curve is the arterial curve convolved with `F exp(-(t - delay) / MTT)`:

- the brain: CBF 55 mL/100 g/min and an MTT of 4 s;
- the small features: CBF 25 and an MTT of 5 s;
- the scalp: CBF 10 and an MTT of 6 s;
- the tissue at risk, a ring of 25 mm radius: CBF 30, an MTT of 8 s and
  a delay of 4 s;
- the ischemic core, of 12 mm radius: CBF 4, an MTT of 12 s and a delay
  of 6 s.

The fluid of the ventricles has no flow. Each voxel is the mean of nine
points in it, over 40 HU, with noise of 1 HU. `Deconvolution.circular`
deconvolves each voxel of the brain, which leaves out the fluid and the
scalp, with a threshold of 0.15. The reference CBF is the mean of the
other hemisphere. `perfusion_mismatch` finds the core, below 30 percent
of it, and the tissue at risk, with a Tmax above 6 s.

The left panel is the CBF map from 0 to 80 mL/100 g/min, on the hot
scale. The middle panel is the Tmax map from 0 to 12 s. The right panel
is the scan at the peak of the arterial curve, with the core in red and
the rest of the tissue at risk in green.

The truncation of small singular values lowers the CBF of fast flows
most. The reference is 31 mL/100 g/min, not 55, but the core still falls
below 30 percent of it. The program prints the reference, a core of 1.6
mL, 4.9 mL with a Tmax above 6 s, and a mismatch ratio of 3.1.

This is a picture of a synthetic volume, for teaching. It is not a
diagnosis, and it does not give a treatment decision.
"""

from extensions.imaging.fusion import hot_color
from extensions.imaging.ids import K_AXIS, LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
from extensions.imaging.overlay import overlay_labels, render_slice, zoom_image
from extensions.imaging.perfusion import (
    BRAIN_DENSITY,
    BloodFlow64,
    Deconvolution,
    HEMATOCRIT_FACTOR,
    MILLILITER_PER_100_GRAM_PER_MINUTE,
    ct_concentration,
    ct_concentration_series,
    perfusion_maps,
    perfusion_mismatch,
)
from extensions.imaging.phantom import phantom_value, shepp_logan_table
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.math import cos, expm1, log, pi, sqrt
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import (
    Density64,
    Duration64,
    GRAM_PER_CUBIC_CENTIMETER,
    Length64,
    SECOND,
)
from units.quantity import Unit

comptime DEFAULT_OUTPUT = "out/perfusion.png"
comptime SIZE = 96
comptime ZOOM = 4
comptime PANEL = SIZE * ZOOM
comptime SAMPLES = 3
comptime FRAMES = 40
comptime STEP = 1.5
comptime FINE = 50
comptime SIGMA = 1.0
comptime PEAK_FRAME = 7
# The stroke's center and radii, in fractions of half the field.
comptime STROKE_X = -0.36
comptime STROKE_Y = -0.5
comptime CORE_R = 0.12
comptime RISK_R = 0.25
# The tissues.
comptime OUTSIDE = 0
comptime SCALP = 1
comptime FLUID = 2
comptime FEATURE = 3
comptime BRAIN = 4
comptime RISK = 5
comptime CORE = 6
comptime TISSUES = 7
comptime MILLILITER = Unit[3, 0, 0, 0, 0, DType.float64](1.0e-6, "mL")


struct _Noise(Movable):
    """A seeded source of normal numbers, by xorshift and Box-Muller."""

    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def uniform(mut self) -> Float64:
        self.state ^= self.state << 13
        self.state ^= self.state >> 7
        self.state ^= self.state << 17
        return (Float64(self.state >> 11) + 0.5) / 9007199254740992.0

    def normal(mut self) -> Float64:
        var u = self.uniform()
        var v = self.uniform()
        return sqrt(-2.0 * log(u)) * cos(2.0 * pi * v)


def _tissue(x: Float64, y: Float64) -> Int:
    """Return the tissue at a point of the axial slice through the center."""
    if not shepp_logan_table()[0].contains(x, y, 0):
        return OUTSIDE
    var v = phantom_value(x, y, 0)
    if v > 0.6:
        return SCALP
    if v < 0.1:
        return FLUID
    var dx = x - STROKE_X
    var dy = y - STROKE_Y
    var r2 = dx * dx + dy * dy
    if r2 <= CORE_R * CORE_R:
        return CORE
    if r2 <= RISK_R * RISK_R:
        return RISK
    if v > 0.25:
        return FEATURE
    return BRAIN


def _exp(x: Float64) -> Float64:
    """Return `e^x` from `expm1`, for x of 0 or less."""
    return 1.0 + expm1(x)


def _arterial_fine() -> List[Float64]:
    """Return the arterial enhancement on the fine grid, peaking at 300."""
    var out = List[Float64]()
    var top = 0.0
    for at in range(FRAMES * FINE):
        var s = max(Float64(at) * STEP / Float64(FINE) - 6.0, 0.0)
        var v = s * s * s * _exp(-s / 1.5)
        out.append(v)
        top = max(top, v)
    for at in range(len(out)):
        out[at] *= 300.0 / top
    return out^


def _curves(arterial: List[Float64]) -> List[List[Float64]]:
    """Return the enhancement of each tissue at each frame."""
    # CBF in mL/100 g/min, MTT and delay in s.
    var cbf: List[Float64] = [0.0, 10.0, 0.0, 25.0, 55.0, 30.0, 4.0]
    var mtt: List[Float64] = [1.0, 6.0, 1.0, 5.0, 4.0, 8.0, 12.0]
    var delay: List[Float64] = [0.0, 0.0, 0.0, 0.0, 0.0, 4.0, 6.0]
    var dt = STEP / Float64(FINE)
    var out = List[List[Float64]]()
    for tissue in range(TISSUES):
        # F a second from CBF, the inverse of `factor F / density`.
        var flow = cbf[tissue] * BRAIN_DENSITY / HEMATOCRIT_FACTOR / 6000.0
        var residue = List[Float64]()
        for at in range(FRAMES * FINE):
            var t = Float64(at) * dt - delay[tissue]
            residue.append(flow * _exp(-t / mtt[tissue]) if t >= 0 else 0.0)
        var frames = List[Float64]()
        for frame in range(FRAMES):
            var j = frame * FINE
            var total = 0.0
            for i in range(j + 1):
                total += arterial[j - i] * residue[i]
            frames.append(total * dt)
        out.append(frames^)
    return out^


def _hot(volume: ImageVolume, top: Float64) raises -> Framebuffer:
    """Return a slice on the hot scale from 0 to a top value, black where
    the value is 0."""
    var image = Framebuffer(SIZE, SIZE, Color(0, 0, 0))
    for j in range(SIZE):
        for i in range(SIZE):
            var v = Float64(volume.get(i, j, 0))
            if v == 0:
                continue
            var c = hot_color(v / top)
            image.set_pixel(
                i,
                j,
                Color(
                    UInt8(Int(c.r * 255 + 0.5)),
                    UInt8(Int(c.g * 255 + 0.5)),
                    UInt8(Int(c.b * 255 + 0.5)),
                ),
            )
    return image^


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var arterial_fine = _arterial_fine()
    var curves = _curves(arterial_fine)
    var step = Length64(200.0 / Float64(SIZE), MILLIMETER64)
    var grid = ImageVolume(
        SIZE, SIZE, 1, step, step, Length64(5.0, MILLIMETER64)
    )
    var series = List[ImageVolume]()
    for _ in range(FRAMES):
        series.append(grid.copy())
    var brain = LabelMap(grid)
    var noise = _Noise(20261115)
    for j in range(SIZE):
        for i in range(SIZE):
            var counts = List[Int](length=TISSUES, fill=0)
            for sj in range(SAMPLES):
                for si in range(SAMPLES):
                    var x = -1.0 + 2.0 * (
                        Float64(i) + (Float64(si) + 0.5) / Float64(SAMPLES)
                    ) / Float64(SIZE)
                    var y = -1.0 + 2.0 * (
                        Float64(j) + (Float64(sj) + 0.5) / Float64(SAMPLES)
                    ) / Float64(SIZE)
                    counts[_tissue(x, y)] += 1
            var parenchyma = (
                counts[FEATURE] + counts[BRAIN] + counts[RISK] + counts[CORE]
            )
            if parenchyma == SAMPLES * SAMPLES:
                brain.labels[grid.index(i, j, 0)] = 1
            for frame in range(FRAMES):
                var total = 0.0
                for tissue in range(TISSUES):
                    total += Float64(counts[tissue]) * curves[tissue][frame]
                var hu = 40.0 + total / Float64(SAMPLES * SAMPLES)
                if counts[OUTSIDE] == SAMPLES * SAMPLES:
                    hu = -1000.0
                series[frame].set(i, j, 0, Float32(hu + SIGMA * noise.normal()))
    var arterial = List[Float64]()
    for frame in range(FRAMES):
        arterial.append(100.0 + arterial_fine[frame * FINE])
    var deconvolution = Deconvolution.circular(
        ct_concentration(arterial, 4), Duration64(STEP, SECOND), 0.15
    )
    var density = Density64(BRAIN_DENSITY, GRAM_PER_CUBIC_CENTIMETER)
    var maps = perfusion_maps(
        ct_concentration_series(series, 4),
        deconvolution,
        brain,
        LabelId(1),
        density,
        HEMATOCRIT_FACTOR,
    )
    # The reference: the mean CBF of the brain in the other hemisphere.
    var total = 0.0
    var count = 0
    for j in range(SIZE):
        for i in range(SIZE // 2, SIZE):
            var at = grid.index(i, j, 0)
            if brain.labels[at] == 1:
                total += Float64(maps.cbf.values[at])
                count += 1
    var reference = BloodFlow64(
        total / Float64(count), MILLILITER_PER_100_GRAM_PER_MINUTE
    )
    var found = perfusion_mismatch(
        maps, brain, LabelId(1), reference, 0.3, Duration64(6, SECOND)
    )
    # The overlay: the core in red, the rest at risk in green.
    var regions = LabelMap(grid)
    for at in range(grid.count()):
        if brain.labels[at] != 1:
            continue
        if Float64(maps.cbf.values[at]) < 0.3 * reference.to(
            MILLILITER_PER_100_GRAM_PER_MINUTE
        ):
            regions.labels[at] = 1
        elif Float64(maps.tmax.values[at]) > 6.0:
            regions.labels[at] = 2
    var scan = series[PEAK_FRAME].copy()
    scan.window_center = 60
    scan.window_width = 120
    var picture = render_slice(scan, K_AXIS, 0)
    overlay_labels(picture, regions, K_AXIS, 0, 0.6)
    var sheet = Framebuffer(3 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, zoom_image(_hot(maps.cbf, 80.0), ZOOM), 0, 0)
    blit(sheet, zoom_image(_hot(maps.tmax, 12.0), ZOOM), PANEL, 0)
    blit(sheet, zoom_image(picture, ZOOM), 2 * PANEL, 0)
    Path(destination).write_bytes(encode(sheet))
    print(
        "Reference CBF of the other hemisphere:",
        reference.to(MILLILITER_PER_100_GRAM_PER_MINUTE),
        "mL/100 g/min",
    )
    print(
        "Core (CBF below 30 percent):",
        found.core.to(MILLILITER),
        "mL; Tmax above 6 s:",
        found.hypoperfused.to(MILLILITER),
        "mL",
    )
    print(
        "Mismatch ratio",
        found.ratio(),
        "; mismatch volume",
        found.difference().to(MILLILITER),
        "mL",
    )
    print("Wrote", destination)
