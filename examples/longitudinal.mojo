# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lesion followed across two scans: aligned, measured and graded.

    mojo run -I . examples/longitudinal.mojo [out/longitudinal.png]

The page is Medical imaging. Two synthetic CT scans of the head phantom
are 90 days apart. A lesion of 9 mm radius at the first scan grows to
12 mm at the second. At the second scan, the head is turned 4 degrees and
moved 6 mm, and the scanner's grid has other voxels.

`register_rigid` aligns the second scan to the first by mean squares, on
three levels. `resample_transformed` brings the second scan onto the
first grid. A region grown from the lesion's center labels it in each
scan. The example gives the volumes, the doubling time, the longest
axial diameters and the RECIST 1.1 response.

Each panel shows 64 voxels around the lesion, on a window from 0 to 0.8.
The left panel is the first scan through the lesion, with its outline in
green and its longest diameter in yellow. The middle panel is the same
slice of the second scan as acquired, before registration. The right
panel is the second scan after registration, with its outline in red,
the first outline in green and its longest diameter in yellow.

This is a picture of synthetic scans, for teaching. It is not a
diagnosis.
"""

from extensions.imaging.contour import draw_outlines, slice_outlines
from extensions.imaging.dvh import CUBIC_CENTIMETER64
from extensions.imaging.filter import gaussian_filter
from extensions.imaging.growth import (
    DAY64,
    LongestDiameter,
    doubling_time,
    longest_diameter,
    recist_response,
    response_name,
)
from extensions.imaging.ids import K_AXIS, LabelId, MEAN_SQUARES
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap, region_grow
from extensions.imaging.overlay import (
    draw_measurement,
    render_slice,
    zoom_image,
)
from extensions.imaging.phantom import shepp_logan
from extensions.imaging.register import (
    RigidTransform,
    largest_difference,
    register_rigid,
    resample_transformed,
)
from extensions.imaging.shape import label_shape
from extensions.imaging.transfer import Rgba
from extensions.sdf.vector import V3, distance, v3
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.math import cos, max, min, sin
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import Angle64, DEGREE64, Duration64, Length64, METER

comptime DEFAULT_OUTPUT = "out/longitudinal.png"
comptime SIZE = 128
comptime ZOOM = 6
# Each panel shows this many voxels around the lesion.
comptime REGION = 64
comptime PANEL = REGION * ZOOM
comptime LESION_VALUE = 0.6


def _lesion() -> V3:
    """The lesion's center, in meters from the patient origin."""
    return v3(0.032, -0.024, 0.006)


def _scan(radius: Float64) raises -> ImageVolume:
    """Return the phantom with a lesion of a radius, blurred as a scanner
    blurs it."""
    var volume = shepp_logan(SIZE, Length64(200.0, MILLIMETER64), 2)
    var step = volume.spacing_x.to(METER)
    var center = _lesion()
    for k in range(SIZE):
        for j in range(SIZE):
            for i in range(SIZE):
                var p = volume.patient_point(Float64(i), Float64(j), Float64(k))
                # The share of the voxel inside the ball, over one voxel.
                var share = max(
                    0.0, min(1.0, 0.5 - (distance(p, center) - radius) / step)
                )
                if share > 0:
                    var at = volume.index(i, j, k)
                    var v = Float64(volume.values[at])
                    volume.values[at] = Float32(v + (LESION_VALUE - v) * share)
    return gaussian_filter(volume, Length64(1.5, MILLIMETER64))


def _grid() raises -> ImageVolume:
    """The second scanner's grid: 120 voxels of 1.65 mm, turned 3 degrees
    about z and moved."""
    var step = Length64(1.65, MILLIMETER64)
    var grid = ImageVolume(120, 120, 120, step, step, step)
    var turn = 0.0523598776
    grid.axis_x = v3(cos(turn), sin(turn), 0)
    grid.axis_y = v3(-sin(turn), cos(turn), 0)
    var half = 0.5 * 119.0 * 0.00165
    grid.origin = (
        v3(0.003, -0.002, 0.004)
        - grid.axis_x * half
        - grid.axis_y * half
        - grid.axis_z * half
    )
    return grid^


def _caliper(
    mut image: Framebuffer, diameter: LongestDiameter, color: Rgba
) raises:
    """Draw a diameter on a zoomed slice, from pixel center to center."""
    var half = Float64(ZOOM - 1) / 2.0
    var a = diameter.first
    var b = diameter.second
    draw_measurement(
        image,
        K_AXIS,
        v3(Float64(a[0] * ZOOM) + half, Float64(a[1] * ZOOM) + half, 0),
        v3(Float64(b[0] * ZOOM) + half, Float64(b[1] * ZOOM) + half, 0),
        color,
    )


def _crop(image: Framebuffer, x0: Int, y0: Int) raises -> Framebuffer:
    """Return a square of the panel's size from a zoomed slice."""
    var out = Framebuffer(PANEL, PANEL, Color(0, 0, 0))
    var channels = len(image.pixels) // (image.width * image.height)
    for y in range(PANEL):
        for x in range(PANEL):
            var src = ((y0 + y) * image.width + x0 + x) * channels
            var dst = (y * PANEL + x) * channels
            for c in range(channels):
                out.pixels[dst + c] = image.pixels[src + c]
    return out^


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var first = _scan(0.009)
    # The head moves between the scans: 4 degrees and 6 mm.
    var moved = RigidTransform(
        v3(0.2, -0.3, 1.0),
        Angle64(4.0, DEGREE64),
        v3(0, 0, 0),
        v3(0.004, -0.0035, 0.0025),
    )
    var second = resample_transformed(_scan(0.012), _grid(), moved.inverse(), 0)
    # A window from the ventricles to past the lesion.
    first.window_center = 0.4
    first.window_width = 0.8
    second.window_center = 0.4
    second.window_width = 0.8
    var middle = first.patient_point(63.5, 63.5, 63.5)
    var found = register_rigid(
        first, second, MEAN_SQUARES, RigidTransform(middle), 3, 2
    )
    var aligned = resample_transformed(second, first, found.transform, 0)
    # Each lesion grows from the first scan's voxel at its center.
    var seed = first.voxel_point(_lesion())
    var i = Int(seed.x + 0.5)
    var j = Int(seed.y + 0.5)
    var k = Int(seed.z + 0.5)
    var level = 0.5 * (0.2 + LESION_VALUE)
    var before = region_grow(first, i, j, k, level, 2.0, LabelId(1))
    var after = region_grow(aligned, i, j, k, level, 2.0, LabelId(1))
    var v1 = label_shape(before, first, LabelId(1)).volume
    var v2 = label_shape(after, aligned, LabelId(1)).volume
    var d1 = longest_diameter(before, LabelId(1))
    var d2 = longest_diameter(after, LabelId(1))
    var response = recist_response(d1.length, d1.length, d2.length)
    # The pictures, on the slice of the lesion's center.
    var green = Rgba(0.3, 1, 0.4, 1)
    var red = Rgba(1, 0.3, 0.3, 1)
    var yellow = Rgba(1, 0.9, 0.2, 1)
    var left = zoom_image(render_slice(first, K_AXIS, k), ZOOM)
    draw_outlines(
        left, K_AXIS, slice_outlines(before, LabelId(1), K_AXIS, k), ZOOM, green
    )
    _caliper(left, d1, yellow)
    var raw = zoom_image(render_slice(second, K_AXIS, k), ZOOM)
    var right = zoom_image(render_slice(aligned, K_AXIS, k), ZOOM)
    draw_outlines(
        right,
        K_AXIS,
        slice_outlines(before, LabelId(1), K_AXIS, k),
        ZOOM,
        green,
    )
    draw_outlines(
        right, K_AXIS, slice_outlines(after, LabelId(1), K_AXIS, k), ZOOM, red
    )
    _caliper(right, d2, yellow)
    # The region around the lesion, the same in each panel.
    var x0 = max(0, min(SIZE - REGION, i - REGION // 2)) * ZOOM
    var y0 = max(0, min(SIZE - REGION, j - REGION // 2)) * ZOOM
    var sheet = Framebuffer(3 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, _crop(left, x0, y0), 0, 0)
    blit(sheet, _crop(raw, x0, y0), PANEL, 0)
    blit(sheet, _crop(right, x0, y0), 2 * PANEL, 0)
    Path(destination).write_bytes(encode(sheet))
    print(
        "Registration: off by",
        largest_difference(found.transform, moved, first).to(METER) * 1000,
        "mm at the corners; turn",
        found.transform.angle.to(DEGREE64),
        "degrees",
    )
    print(
        "Lesion:",
        v1.to(CUBIC_CENTIMETER64),
        "cm^3, then",
        v2.to(CUBIC_CENTIMETER64),
        "cm^3; doubling time",
        doubling_time(v1, v2, Duration64(90, DAY64)).to(DAY64),
        "days",
    )
    print(
        "Longest diameter:",
        d1.length.to(METER) * 1000,
        "mm, then",
        d2.length.to(METER) * 1000,
        "mm; RECIST",
        response_name(response),
    )
    print("Wrote", destination)
