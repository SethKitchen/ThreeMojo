# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A curved vessel found, followed and straightened.

    mojo run -I . examples/vessel.mojo [out/vessel.png]

A synthetic vessel with contrast winds through a block of soft tissue in
all three axes, and narrows to half its radius partway along. A
threshold labels it, and `label_path` finds its centered path.
`smooth_path` and `resample_path` turn the chain of voxels into a smooth
path with even steps, and `curved_reformat` straightens the vessel along
it. The top left panel is the maximum
intensity projection along z, with the path in yellow. The top right
panel is one axial slice, with the outline of the label in yellow: no
single plane holds the vessel. The band
below is the straightened vessel, with the narrowing plain to see. The program
prints the path length and the narrowest radius along it.

This is a picture of a synthetic volume, for teaching. It is not a
diagnosis.
"""

from extensions.imaging.contour import draw_outlines, slice_outlines
from extensions.imaging.curved import curved_reformat
from extensions.imaging.ids import CORNERS, K_AXIS, LabelId, SLAB_MAXIMUM
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.labels import keep_largest, threshold
from extensions.imaging.overlay import render_slice, zoom_image
from extensions.imaging.path import label_path, resample_path, smooth_path
from extensions.imaging.reformat import slab_projection
from extensions.imaging.thickness import label_distance
from extensions.imaging.transfer import Rgba
from extensions.sdf.vector import V3, distance, v3
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.math import cos, exp, pi, sin
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import MILLIMETER64, Length64

comptime DEFAULT_OUTPUT = "out/vessel.png"
comptime NX = 80
comptime NY = 80
comptime NZ = 48
# Voxels of 0.5 mm.
comptime STEP = 0.5
comptime ZOOM = 3
comptime PANEL = NX * ZOOM


def _center(t: Float64) -> V3:
    """Return the vessel's center at a share t of its length, in mm."""
    return v3(
        5.0 + 30.0 * t,
        20.0 + 9.0 * sin(2.0 * pi * t),
        6.0 + 12.0 * t + 3.0 * sin(pi * t),
    )


def _radius(t: Float64) -> Float64:
    """Return the vessel's radius in mm: 2.4, and half that at t = 0.6."""
    return 2.4 * (1.0 - 0.5 * exp(-(((t - 0.6) / 0.05) ** 2)))


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var mm = Length64(STEP, MILLIMETER64)
    var volume = ImageVolume(NX, NY, NZ, mm, mm, mm)
    volume.window_center = 170
    volume.window_width = 400
    # Soft tissue of about 40 HU, and the vessel of 300 HU.
    var samples = 400
    var centers = List[V3]()
    var radii = List[Float64]()
    for s in range(samples + 1):
        var t = Float64(s) / Float64(samples)
        centers.append(_center(t))
        radii.append(_radius(t))
    for k in range(NZ):
        for j in range(NY):
            for i in range(NX):
                var p = v3(Float64(i), Float64(j), Float64(k)) * STEP
                var value = 40.0 + 8.0 * sin(0.3 * p.x) * cos(0.2 * p.y)
                for s in range(0, samples + 1, 2):
                    if distance(p, centers[s]) <= radii[s]:
                        value = 300.0
                        break
                volume.set(i, j, k, Float32(value))
    var map = keep_largest(
        threshold(volume, 150, 1000, LabelId(1)), LabelId(1), CORNERS
    )
    var first = _center(0) * (1.0 / STEP)
    var last = _center(1) * (1.0 / STEP)
    var path = label_path(
        map,
        volume,
        LabelId(1),
        (Int(first.x + 0.5), Int(first.y + 0.5), Int(first.z + 0.5)),
        (Int(last.x + 0.5), Int(last.y + 0.5), Int(last.z + 0.5)),
    )
    # The radius along the path: the distance from each point to the edge.
    var edge = label_distance(map, LabelId(1))
    var length = 0.0
    var narrowest = 1.0e9
    var narrowest_at = 0.0
    for k in range(len(path)):
        if k > 0:
            length += distance(path[k], path[k - 1]) * 1000.0
        var q = volume.voxel_point(path[k])
        var r = Float64(
            edge.get(Int(q.x + 0.5), Int(q.y + 0.5), Int(q.z + 0.5))
        )
        if k > 4 and k + 4 < len(path) and r < narrowest:
            narrowest = r
            narrowest_at = length
    print("Path:", len(path), "voxels,", length, "mm long")
    print("Narrowest radius:", narrowest, "mm, at", narrowest_at, "mm")
    # The projection along z, with the path in yellow.
    var middle = v3(
        Float64(NX - 1) / 2.0, Float64(NY - 1) / 2.0, Float64(NZ - 1) / 2.0
    ) * (STEP / 1000.0)
    var mip = slab_projection(
        volume,
        middle,
        v3(1, 0, 0),
        v3(0, 1, 0),
        NX,
        NY,
        mm,
        Length64(Float64(NZ) * STEP, MILLIMETER64),
        NZ,
        SLAB_MAXIMUM,
        0,
    )
    var projected = render_slice(mip, K_AXIS, 0)
    for p in path:
        var q = volume.voxel_point(p)
        projected.set_pixel(Int(q.x + 0.5), Int(q.y + 0.5), Color(255, 220, 40))
    var axial = render_slice(volume, K_AXIS, NZ // 2)
    var fine = Length64(0.25, MILLIMETER64)
    var smooth = resample_path(smooth_path(path, 4), fine)
    var straight = curved_reformat(volume, smooth, v3(0, 0, 1), 20, fine, 0)
    var wide = zoom_image(render_slice(straight, K_AXIS, 0), 2)
    var band = wide.height + 20
    var sheet = Framebuffer(2 * PANEL, PANEL + band, Color(0, 0, 0))
    blit(sheet, zoom_image(projected, ZOOM), 0, 0)
    # The label's outline on the axial slice, in yellow.
    var axial_zoomed = zoom_image(axial, ZOOM)
    draw_outlines(
        axial_zoomed,
        K_AXIS,
        slice_outlines(map, LabelId(1), K_AXIS, NZ // 2),
        ZOOM,
        Rgba(1, 0.86, 0.16, 1),
    )
    blit(sheet, axial_zoomed, PANEL, 0)
    blit(sheet, wide, (2 * PANEL - wide.width) // 2, PANEL + 10)
    Path(destination).write_bytes(encode(sheet))
    print("Wrote", destination)
