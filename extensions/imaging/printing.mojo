# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a label surface as an STL file for a 3D printer.

An STL file has no unit, and slicers for 3D printers read it in
millimeters. The library keeps lengths in meters, so a surface written
as it is prints a thousand times too small. `printable_stl` writes a
mesh in meters as a binary STL file in millimeters. `label_stl` takes a
label straight to that file: its surface, smoothed by Taubin's filter.

A printed model is for teaching and for planning research. It is not a
medical device.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from exporters.stl import STL_BINARY, export_stl
from extensions.imaging.ids import LabelId
from extensions.imaging.labels import LabelMap, label_surface
from extensions.imaging.smooth import smooth_surface
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color

# Millimeters per meter.
comptime MILLIMETERS = 1000.0


def printable_stl(geometry: BufferGeometry) raises -> List[UInt8]:
    """Return a mesh in meters as the bytes of a binary STL file in
    millimeters.

    Args:
        geometry: A triangle mesh with positions in meters.

    Returns:
        The file: an 80-byte header, the facet count, and fifty bytes a
        facet.

    Raises:
        Error: If the geometry has no positions.
    """
    var assets = Assets()
    var scene = Scene()
    var shape = assets.geometries.add(geometry.clone())
    var material = assets.materials.add(Material(Color(255, 255, 255)))
    var node = Object3D()
    node.set_scale(
        Float32(MILLIMETERS), Float32(MILLIMETERS), Float32(MILLIMETERS)
    )
    scene.add_mesh(Mesh(shape, material, scene.add(node^)))
    scene.update()
    return export_stl(scene, assets, STL_BINARY)


def label_stl(map: LabelMap, label: LabelId, passes: Int) raises -> List[UInt8]:
    """Return a label's smoothed surface as a binary STL file in
    millimeters.

    Args:
        map: The label map.
        label: The label. Not the background.
        passes: Taubin passes, as `smooth_surface` takes. Zero only welds.

    Returns:
        The file.

    Raises:
        Error: If the label is not valid, is the background or has no
            voxels, or `passes` is negative.
    """
    return printable_stl(smooth_surface(label_surface(map, label), passes))
