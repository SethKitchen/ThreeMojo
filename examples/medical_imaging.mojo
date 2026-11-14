# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A head phantom through the imaging pipeline, drawn two ways.

The phantom is cut into DICOM slices, written as Part 10 files in memory,
read back and stacked into a volume. The left panel casts rays through
the volume with its front half cropped away. The middle panel shows the
same cut as an isosurface. The right panel is one axial slice with three
labels and one measurement over it.

    mojo run -I . examples/medical_imaging.mojo [out/medical-imaging.png]
"""

from extensions.imaging.dicom import DicomSlice, parse_dicom
from extensions.imaging.dicom_write import encode_dicom
from extensions.imaging.ids import COMPOSITE, ISOSURFACE, K_AXIS, LabelId
from extensions.imaging.image_volume import MILLIMETER64
from extensions.imaging.labels import (
    LabelMap,
    keep_largest,
    region_grow,
    threshold,
)
from extensions.imaging.measure import label_statistics, voxel_distance
from extensions.imaging.overlay import (
    draw_measurement,
    overlay_labels,
    render_slice,
)
from extensions.imaging.phantom import shepp_logan
from extensions.imaging.raycast import (
    VolumeCamera,
    orbit_camera,
    render_volume,
    volume_center,
)
from extensions.imaging.series import stack_slices, volume_slices
from extensions.imaging.transfer import Rgba, TransferFunction
from extensions.sdf.vector import v3
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.pathlib import Path
from tools._example_output import blit, example_destination
from units.si import Angle64, DEGREE64, Length64

comptime DEFAULT_OUTPUT = "out/medical-imaging.png"
comptime SIZE = 128
comptime PANEL = 480
comptime ZOOM = 3


def _transfer() raises -> TransferFunction:
    """Clear air, a faint brain, red features and an opaque skull."""
    var transfer = TransferFunction()
    var brain = Rgba(0.95, 0.78, 0.68, 0)
    var feature = Rgba(0.9, 0.15, 0.1, 0)
    var bone = Rgba(0.95, 0.93, 0.88, 0)
    transfer.add_point(0.0, Rgba(0, 0, 0, 0))
    transfer.add_point(0.15, brain)
    transfer.add_point(0.19, Rgba(brain.r, brain.g, brain.b, 0.06))
    transfer.add_point(0.23, Rgba(brain.r, brain.g, brain.b, 0.06))
    transfer.add_point(0.26, brain)
    transfer.add_point(0.27, feature)
    transfer.add_point(0.29, Rgba(feature.r, feature.g, feature.b, 0.7))
    transfer.add_point(0.42, Rgba(1.0, 0.45, 0.1, 0.7))
    transfer.add_point(0.46, Rgba(1.0, 0.45, 0.1, 0))
    transfer.add_point(0.6, bone)
    transfer.add_point(0.85, Rgba(bone.r, bone.g, bone.b, 0.9))
    transfer.add_point(1.0, Rgba(1, 1, 0.97, 0.9))
    return transfer^


def _zoomed(image: Framebuffer, factor: Int) raises -> Framebuffer:
    """Return an image scaled up by repeating each pixel."""
    var width = image.width * factor
    var height = image.height * factor
    var pixels = List[UInt8](length=width * height * 4, fill=0)
    for y in range(height):
        for x in range(width):
            var source = ((y // factor) * image.width + x // factor) * 4
            var target = (y * width + x) * 4
            for c in range(4):
                pixels[target + c] = image.pixels[source + c]
    return Framebuffer(width, height, pixels^)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var phantom = shepp_logan(SIZE, Length64(200.0, MILLIMETER64), 2)
    var files = List[DicomSlice]()
    for slice in volume_slices(phantom, 0.001, 0.0):
        files.append(parse_dicom(encode_dicom(slice)))
    var volume = stack_slices(files)
    # The orbit camera frames the whole cube. The head fills less of it,
    # so the camera moves in along the same line of sight.
    var orbit = orbit_camera(
        volume,
        Angle64(35, DEGREE64),
        Angle64(25, DEGREE64),
        Angle64(24, DEGREE64),
        PANEL,
        PANEL,
    )
    var target = volume_center(volume)
    var camera = VolumeCamera(
        target - orbit.forward * 0.46,
        target,
        v3(0, 0, -1),
        Angle64(24, DEGREE64),
        PANEL,
        PANEL,
    )
    var background = Rgba(0.05, 0.06, 0.08, 1)
    var rendered = render_volume(
        volume,
        camera,
        _transfer(),
        COMPOSITE,
        0.5,
        0.3,
        background,
        v3(0, 0.5, 0),
        v3(1, 1, 1),
    )
    # The same cut, as the surface where the value first reaches 0.27: the
    # cut edge of the skull, and the small features inside the brain.
    var surface_colors = TransferFunction()
    surface_colors.add_point(0.27, Rgba(0.92, 0.62, 0.45, 1))
    var surfaces = render_volume(
        volume,
        camera,
        surface_colors,
        ISOSURFACE,
        0.25,
        0.25,
        background,
        v3(0, 0.5, 0),
        v3(1, 1, 1),
        iso_value=0.27,
    )
    var middle = SIZE // 2
    var labels = threshold(volume, 0.6, 2.0, LabelId(1))
    var ventricle = region_grow(
        volume, 45, middle, middle, -0.05, 0.11, LabelId(2)
    )
    var features = keep_largest(
        threshold(volume, 0.27, 0.45, LabelId(3)), LabelId(3)
    )
    for index in range(labels.count()):
        if ventricle.labels[index] != 0:
            labels.labels[index] = ventricle.labels[index]
        if features.labels[index] != 0:
            labels.labels[index] = features.labels[index]
    var slice = render_slice(volume, K_AXIS, middle)
    overlay_labels(slice, labels, K_AXIS, middle, 0.45)
    var center = Float64(middle)
    var left = v3(21, center, center)
    var right = v3(107, center, center)
    draw_measurement(slice, K_AXIS, left, right, Rgba(1, 0.9, 0.1, 1))
    var sheet = Framebuffer(3 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, rendered, 0, 0)
    blit(sheet, surfaces, PANEL, 0)
    var zoomed = _zoomed(slice, ZOOM)
    var margin = (PANEL - SIZE * ZOOM) // 2
    blit(sheet, zoomed, 2 * PANEL + margin, margin)
    Path(destination).write_bytes(encode(sheet))
    var stats = label_statistics(ventricle, volume, LabelId(2))
    print(
        "Left ventricle:",
        stats.voxels,
        "voxels,",
        stats.volume.value * 1.0e6,
        "mL",
    )
    print(
        "Measured width:",
        voxel_distance(volume, left, right).to(MILLIMETER64),
        "mm",
    )
    print("Wrote", destination)
