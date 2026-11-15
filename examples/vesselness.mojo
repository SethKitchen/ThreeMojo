# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A synthetic angiogram: a branching vessel tree among a blob and a plate,
and its Frangi vesselness.

    mojo run -I . examples/vesselness.mojo [out/vesselness.png]

The page is Medical imaging. The volume has 80 by 80 by 40 voxels of 1
mm. A trunk of 3 mm radius runs across it, and three branches of 2, 1.5
and 1.2 mm leave it. A bright blob of 5 mm and a bright plate of 1.5 mm,
which are not vessels, lie beside them. Each voxel has noise of 8 on a
vessel height of 100.

`vesselness` filters the volume at the scales 1.5, 2.5 and 3.5 mm. The
left panel is the maximum intensity projection of the volume along z. The
right panel is that of the vesselness, from 0 to 0.5 on the hot scale.
The tree stays, and the blob, the inside of the plate and the noise fade.
The edges of the plate are thin ridges, so they look like tubes too. The
program prints the mean vesselness on the axis of the trunk, at the
center of the blob and in the plate.
"""

from extensions.imaging.fusion import hot_color
from extensions.imaging.ids import K_AXIS
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.overlay import render_slice, zoom_image
from extensions.imaging.vesselness import vesselness
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.collections import Optional
from std.math import cos, expm1, log, pi, sqrt
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import Length64

comptime DEFAULT_OUTPUT = "out/vesselness.png"
comptime NX = 80
comptime NY = 80
comptime NZ = 40
comptime ZOOM = 5
comptime PANEL = NX * ZOOM
comptime NOISE = 8.0


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


def _exp(x: Float64) -> Float64:
    """Return `e^x` for an x of 0 or less."""
    return 1.0 / (1.0 + expm1(-x))


def _segment(
    p: List[Float64], a: List[Float64], b: List[Float64], radius: Float64
) -> Float64:
    """Return the height of a tube of a radius along a segment, at a point."""
    var ab2 = 0.0
    var dot = 0.0
    for c in range(3):
        ab2 += (b[c] - a[c]) * (b[c] - a[c])
        dot += (p[c] - a[c]) * (b[c] - a[c])
    var t = min(max(dot / ab2, 0.0), 1.0)
    var d2 = 0.0
    for c in range(3):
        var q = a[c] + t * (b[c] - a[c]) - p[c]
        d2 += q * q
    return 100.0 * _exp(-d2 / (2.0 * radius * radius))


def _projection(volume: ImageVolume) raises -> ImageVolume:
    """Return the largest value along z of each column."""
    var mm = Length64(1.0, MILLIMETER64)
    var out = ImageVolume(volume.nx, volume.ny, 1, mm, mm, mm)
    for j in range(volume.ny):
        for i in range(volume.nx):
            var top = volume.get(i, j, 0)
            for k in range(1, volume.nz):
                top = max(top, volume.get(i, j, k))
            out.set(i, j, 0, top)
    return out^


def _hot(volume: ImageVolume, top: Float64) raises -> Framebuffer:
    """Return a slice on the hot scale from 0 to a top value."""
    var image = Framebuffer(volume.nx, volume.ny, Color(0, 0, 0))
    for j in range(volume.ny):
        for i in range(volume.nx):
            var c = hot_color(Float64(volume.get(i, j, 0)) / top)
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
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(NX, NY, NZ, mm, mm, mm)
    var trunk: List[List[Float64]] = [[8.0, 40.0, 20.0], [72.0, 40.0, 20.0]]
    var branches: List[List[Float64]] = [
        [30.0, 40.0, 20.0, 62.0, 12.0, 26.0, 2.0],
        [48.0, 40.0, 20.0, 70.0, 68.0, 14.0, 1.5],
        [58.0, 22.0, 24.0, 76.0, 26.0, 30.0, 1.2],
    ]
    var noise = _Noise(20261115)
    for k in range(NZ):
        for j in range(NY):
            for i in range(NX):
                var p: List[Float64] = [Float64(i), Float64(j), Float64(k)]
                var v = _segment(p, trunk[0], trunk[1], 3.0)
                for b in branches:
                    v = max(
                        v,
                        _segment(
                            p,
                            [b[0], b[1], b[2]],
                            [b[3], b[4], b[5]],
                            b[6],
                        ),
                    )
                # A blob of 5 mm and a plate of 1.5 mm, which are not
                # vessels.
                var bx = Float64(i) - 20.0
                var by = Float64(j) - 64.0
                var bz = Float64(k) - 20.0
                v = max(v, 90.0 * _exp(-(bx * bx + by * by + bz * bz) / 50.0))
                if i >= 8 and i < 28 and j >= 6 and j < 26:
                    var pz = Float64(k) - 28.0
                    v = max(v, 80.0 * _exp(-pz * pz / 4.5))
                volume.set(i, j, k, Float32(v + NOISE * noise.normal()))
    var sigmas: List[Length64] = [
        Length64(1.5, MILLIMETER64),
        Length64(2.5, MILLIMETER64),
        Length64(3.5, MILLIMETER64),
    ]
    var found = vesselness(volume, sigmas, 0.5, 0.5, None)
    var input = _projection(volume)
    input.window_center = 50
    input.window_width = 120
    var sheet = Framebuffer(2 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, zoom_image(render_slice(input, K_AXIS, 0), ZOOM), 0, 0)
    blit(sheet, zoom_image(_hot(_projection(found), 0.5), ZOOM), PANEL, 0)
    Path(destination).write_bytes(encode(sheet))
    var axis = 0.0
    for i in range(12, 28):
        axis += Float64(found.get(i, 40, 20)) / 16.0
    var plate = 0.0
    for i in range(12, 24):
        plate += Float64(found.get(i, 16, 28)) / 12.0
    print("Mean vesselness on the trunk's axis:", axis)
    print("At the center of the blob:", found.get(20, 64, 20))
    print("Mean in the plate:", plate)
    print("Wrote", destination)
