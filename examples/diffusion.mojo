# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A synthetic diffusion MRI of the head phantom, with an ADC map and a
computed image at a higher b-value.

    mojo run -I . examples/diffusion.mojo [out/diffusion.png]

The page is Medical imaging. One axial slice of the head phantom is on 128
voxels of 1.56 mm. Each tissue has a signal S0 and an ADC: the brain 0.75,
the small features 0.9 and the fluid of the ventricles 3.0, in 10^-3
mm^2/s. A lesion of 8 mm radius has dense cells and an ADC of only 0.45.
Each voxel is the mean signal of nine points in it, and each image has
Rician noise of sigma 8.

`adc_maps` fits the images at b = 0, 500 and 1000 s/mm^2. `computed_dwi`
makes the image at b = 2000 s/mm^2 from the maps. `label_statistics`
measures the mean ADC of the lesion and of the brain.

The left panel is the scan at b = 1000, where the lesion is bright. The
middle panel is the ADC map, from 0 to 3000 x 10^-6 mm^2/s, where the
lesion is dark and the fluid is bright. A lesion that is bright at a high
b-value and dark on the ADC map has restricted diffusion. The right panel
is the computed image at b = 2000, where only the lesion stays bright.

This is a picture of a synthetic volume, for teaching. It is not a
diagnosis.
"""

from extensions.imaging.diffusion import (
    BValue64,
    SECOND_PER_SQUARE_MILLIMETER,
    adc_maps,
    computed_dwi,
)
from extensions.imaging.ids import K_AXIS, LabelId
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import LabelMap
from extensions.imaging.measure import label_statistics
from extensions.imaging.overlay import render_slice, zoom_image
from extensions.imaging.phantom import phantom_value, shepp_logan_table
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.math import cos, expm1, log, pi, sqrt
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import MILLIMETER64, Length64

comptime DEFAULT_OUTPUT = "out/diffusion.png"
comptime SIZE = 128
comptime ZOOM = 3
comptime PANEL = SIZE * ZOOM
comptime SAMPLES = 3
comptime SIGMA = 8.0
# The lesion's center and radius, in fractions of half the field.
comptime LESION_X = 0.3
comptime LESION_Y = -0.45
comptime LESION_R = 0.08
# The tissues.
comptime OUTSIDE = 0
comptime SCALP = 1
comptime FLUID = 2
comptime FEATURE = 3
comptime BRAIN = 4
comptime LESION = 5


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
    var dx = x - LESION_X
    var dy = y - LESION_Y
    if dx * dx + dy * dy <= LESION_R * LESION_R:
        return LESION
    var v = phantom_value(x, y, 0)
    if v > 0.6:
        return SCALP
    if v < 0.1:
        return FLUID
    if v > 0.25:
        return FEATURE
    return BRAIN


def _signal(tissue: Int, b: Float64) -> Float64:
    """Return the signal of a tissue at a b-value in s/mm^2."""
    var s0 = 0.0
    var adc = 0.0
    if tissue == SCALP:
        s0 = 150.0
        adc = 0.6e-3
    elif tissue == FLUID:
        s0 = 1500.0
        adc = 3.0e-3
    elif tissue == FEATURE:
        s0 = 1100.0
        adc = 0.9e-3
    elif tissue == BRAIN:
        s0 = 1000.0
        adc = 0.75e-3
    elif tissue == LESION:
        s0 = 1150.0
        adc = 0.45e-3
    return s0 * (1.0 + expm1(-b * adc))


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var step = Length64(200.0 / Float64(SIZE), MILLIMETER64)
    var b_values: List[Float64] = [0.0, 500.0, 1000.0]
    var grid = ImageVolume(SIZE, SIZE, 1, step, step, step)
    var map = LabelMap(grid)
    var series = List[ImageVolume]()
    for _ in b_values:
        series.append(grid.copy())
    var noise = _Noise(20261115)
    for j in range(SIZE):
        for i in range(SIZE):
            var sums = List[Float64](length=len(b_values), fill=0.0)
            var first = -1
            var same = True
            for sj in range(SAMPLES):
                for si in range(SAMPLES):
                    var x = -1.0 + 2.0 * (
                        Float64(i) + (Float64(si) + 0.5) / Float64(SAMPLES)
                    ) / Float64(SIZE)
                    var y = -1.0 + 2.0 * (
                        Float64(j) + (Float64(sj) + 0.5) / Float64(SAMPLES)
                    ) / Float64(SIZE)
                    var tissue = _tissue(x, y)
                    if first < 0:
                        first = tissue
                    same = same and tissue == first
                    for at in range(len(b_values)):
                        sums[at] += _signal(tissue, b_values[at])
            if same and (first == LESION or first == BRAIN):
                map.labels[grid.index(i, j, 0)] = UInt8(
                    1 if first == LESION else 2
                )
            for at in range(len(b_values)):
                var s = sums[at] / Float64(SAMPLES * SAMPLES)
                var real = s + SIGMA * noise.normal()
                var imaginary = SIGMA * noise.normal()
                series[at].set(
                    i, j, 0, Float32(sqrt(real * real + imaginary * imaginary))
                )
    var b = List[BValue64]()
    for value in b_values:
        b.append(BValue64(value, SECOND_PER_SQUARE_MILLIMETER))
    var maps = adc_maps(series, b, 4.0 * SIGMA)
    var computed = computed_dwi(
        maps, BValue64(2000.0, SECOND_PER_SQUARE_MILLIMETER)
    )
    var scan = series[2].copy()
    scan.window_center = 400
    scan.window_width = 800
    maps.adc.window_center = 1500
    maps.adc.window_width = 3000
    computed.window_center = 250
    computed.window_width = 500
    var sheet = Framebuffer(3 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, zoom_image(render_slice(scan, K_AXIS, 0), ZOOM), 0, 0)
    blit(sheet, zoom_image(render_slice(maps.adc, K_AXIS, 0), ZOOM), PANEL, 0)
    blit(
        sheet, zoom_image(render_slice(computed, K_AXIS, 0), ZOOM), 2 * PANEL, 0
    )
    Path(destination).write_bytes(encode(sheet))
    var lesion = label_statistics(map, maps.adc, LabelId(1))
    var brain = label_statistics(map, maps.adc, LabelId(2))
    print(
        "Lesion:",
        lesion.voxels,
        "voxels; mean ADC",
        lesion.mean / 1000.0,
        "x 10^-3 mm^2/s",
    )
    print(
        "Brain:",
        brain.voxels,
        "voxels; mean ADC",
        brain.mean / 1000.0,
        "x 10^-3 mm^2/s",
    )
    print("Wrote", destination)
