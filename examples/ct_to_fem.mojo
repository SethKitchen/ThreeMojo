# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bone segment from CT slices to a stress picture.

    mojo run -I . examples/ct_to_fem.mojo [out/ct-to-fem.png]

The pages are Medical imaging and Tetrahedral FEM. A synthetic CT holds
a straight bone 20 mm long: a cortical shell 2.5 mm thick around a
trabecular core, in soft tissue. The program writes each slice as an RLE
Lossless DICOM file in memory, reads the files back and stacks them. Two
thresholds label the cortical and the trabecular bone. The program keeps
the half of the labels below the axis, so that the cut face shows.

The left panel is the smoothed surface of each label. The right panel is
the voxel mesh of the two labels, compressed by a frictionless platen to
a strain of 0.001, colored by von Mises stress from 0 (blue) to 20 MPa
(red).

The two materials have one Poisson ratio, so the exact solution is a
uniform strain, and linear tetrahedra hold it exactly. The platen force
must then equal the rule of mixtures, `strain * sum(E * A)`, and the
program prints both.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z
from extensions.fem.mesh import voxel_mesh_labels
from extensions.fem.post import stress_geometry
from extensions.fem.static import StaticProblem, solve_static
from extensions.imaging.dicom import DicomSlice, parse_dicom
from extensions.imaging.dicom_write import encode_dicom
from extensions.imaging.ids import LabelId, RLE_LOSSLESS
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap, label_surface, threshold
from extensions.imaging.measure import label_statistics
from extensions.imaging.series import stack_slices, volume_slices
from extensions.imaging.smooth import enclosed_volume, smooth_surface
from materials.material import Material, PHONG
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.png import encode
from std.pathlib import Path
from tools._example_output import (
    blit,
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
)
from units.si import (
    Angle,
    CUBIC_METER,
    DEGREE,
    GIGAPASCAL,
    Length,
    Length64,
    MEGAPASCAL,
    METER,
    PASCAL,
    Pressure64,
)

comptime DEFAULT_OUTPUT = "out/ct-to-fem.png"
comptime PANEL = 480
comptime COLUMNS = 24
comptime SLICES = 20
# The axis of the bone is on voxel corners, at 11.5 mm on x and y.
comptime AXIS = 11.5
# The first column whose voxels lie past the axis.
comptime PAST_AXIS = 12
comptime OUTER = 10.0
comptime INNER = 7.5
comptime TISSUE = 11.5
comptime STRAIN = 0.001
comptime CORTICAL_E = 17.0
comptime TRABECULAR_E = 1.0
comptime POISSON = 0.3


def _ct() raises -> ImageVolume:
    """Air, soft tissue, the cortical shell and the core, in HU."""
    var mm = Length64(1.0, MILLIMETER64)
    var volume = ImageVolume(COLUMNS, COLUMNS, SLICES, mm, mm, mm)
    for k in range(SLICES):
        for j in range(COLUMNS):
            for i in range(COLUMNS):
                var dx = Float64(i) - AXIS
                var dy = Float64(j) - AXIS
                var r = (dx * dx + dy * dy) ** 0.5
                var value: Float32 = -1000
                if r <= INNER:
                    value = 250
                elif r <= OUTER:
                    value = 1400
                elif r <= TISSUE:
                    value = 40
                volume.set(i, j, k, value)
    volume.window_center = 400
    volume.window_width = 1800
    return volume^


def _through_dicom(volume: ImageVolume) raises -> ImageVolume:
    """Write each slice as an RLE file in memory, and stack the files."""
    var files = List[DicomSlice]()
    var plain = 0
    var packed = 0
    for slice in volume_slices(volume, 1.0, -1024.0):
        plain += len(encode_dicom(slice))
        var copy = slice.copy()
        copy.syntax = RLE_LOSSLESS
        var bytes = encode_dicom(copy)
        packed += len(bytes)
        files.append(parse_dicom(bytes))
    print(
        len(files),
        "slices:",
        packed,
        "bytes as RLE Lossless,",
        plain,
        "bytes uncompressed",
    )
    return stack_slices(files)


def _labels(volume: ImageVolume) raises -> LabelMap:
    """Cortical bone as label 1 and trabecular bone as label 2, cut in half."""
    var map = threshold(volume, 700, 3000, LabelId(1))
    var core = threshold(volume, 100, 700, LabelId(2))
    for index in range(map.count()):
        if core.labels[index] != 0:
            map.labels[index] = core.labels[index]
    # Keep the half below the axis, so that the cut face shows.
    for k in range(map.nz):
        for j in range(map.ny):
            for i in range(PAST_AXIS, map.nx):
                map.labels[map.index(i, j, k)] = 0
    return map^


def _draw(
    mut geometries: List[BufferGeometry], colors: List[Color], vertex: Bool
) raises -> Framebuffer:
    """Draw some meshes in the bone's frame, from the side of the cut."""
    var renderer = gallery_renderer(PANEL, PANEL, Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()
    # Turn the bone's z axis up, and center it.
    var holder = Object3D()
    holder.set_rotation_from_axis_angle(Vector3(1, 0, 0), Angle(-90.0, DEGREE))
    holder.set_position(-0.0055, -0.0095, 0.0115)
    var node = scene.add(holder^)
    for index in range(len(geometries)):
        var shape = assets.geometries.add(geometries[index].clone())
        var material = assets.materials.add(
            Material(
                colors[index],
                kind=PHONG,
                vertex_colors=vertex,
                specular=Color(40, 40, 40),
                shininess=20,
            )
        )
        scene.add_mesh(Mesh(shape, material, node))
    fill_and_key(
        scene,
        1.0,
        2.0,
        2.5,
        Color(255, 255, 255),
        0.55,
        Color(255, 250, 240),
        2.2,
    )
    scene.update()
    var camera = gallery_camera(
        PANEL,
        PANEL,
        Vector3(0.034, 0.05, 0.022),
        Vector3(0, -0.001, 0),
        field_of_view=Angle(34.0, DEGREE),
        near=Length(0.005, METER),
        far=Length(1.0, METER),
    )
    return renderer.render(scene, assets, camera)


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var volume = _through_dicom(_ct())
    var map = _labels(volume)
    var shell = smooth_surface(label_surface(map, LabelId(1)), 20)
    var core = smooth_surface(label_surface(map, LabelId(2)), 20)
    var cortical_stats = label_statistics(map, volume, LabelId(1))
    print(
        "Cortical bone:",
        cortical_stats.voxels,
        "voxels,",
        cortical_stats.volume.to(CUBIC_METER) * 1e9,
        "mm^3; smoothed surface",
        enclosed_volume(shell).to(CUBIC_METER) * 1e9,
        "mm^3",
    )
    var mesh = voxel_mesh_labels(map, [LabelId(1), LabelId(2)])
    var cortical = IsotropicMaterial(
        Pressure64(CORTICAL_E, GIGAPASCAL), POISSON
    )
    var trabecular = IsotropicMaterial(
        Pressure64(TRABECULAR_E, GIGAPASCAL), POISSON
    )
    var problem = StaticProblem(mesh^, [cortical, trabecular])
    var tolerance = Length64(1e-9, METER)
    var bottom = problem.mesh.nodes_on_plane(
        DOF_Z, Length64(-0.5, MILLIMETER64), tolerance
    )
    var top = problem.mesh.nodes_on_plane(
        DOF_Z, Length64(Float64(SLICES) - 0.5, MILLIMETER64), tolerance
    )
    var height = Float64(SLICES) * 0.001
    var press = Length64(-STRAIN * height, METER)
    for node in bottom:
        problem.fix(node, DOF_Z, Length64(0, METER))
        # The node on the axis holds still. A node on the line y = axis
        # cannot move along y. That stops the mesh sliding and turning.
        var p = problem.mesh.nodes[node.value]
        var on_line = abs(p.y - AXIS * 0.001) < 1e-9
        if on_line and abs(p.x - AXIS * 0.001) < 1e-9:
            problem.fix(node, DOF_X, Length64(0, METER))
        if on_line:
            problem.fix(node, DOF_Y, Length64(0, METER))
    for node in top:
        problem.fix(node, DOF_Z, press)
    var result = solve_static(problem, 1e-12, 20000)
    var force = 0.0
    for node in bottom:
        force += result.reactions[3 * node.value + 2]
    # Each slice holds the same voxels, so the areas come from one slice.
    var cortical_area = 0.0
    var trabecular_area = 0.0
    for j in range(map.ny):
        for i in range(map.nx):
            var label = map.labels[map.index(i, j, 0)]
            if label == 1:
                cortical_area += 1e-6
            elif label == 2:
                trabecular_area += 1e-6
    var mixture = (
        STRAIN
        * 1e9
        * (CORTICAL_E * cortical_area + TRABECULAR_E * trabecular_area)
    )
    var share = (
        CORTICAL_E
        * cortical_area
        / (CORTICAL_E * cortical_area + TRABECULAR_E * trabecular_area)
    )
    var pictures = List[BufferGeometry]()
    pictures.append(shell^)
    pictures.append(core^)
    var bones = _draw(
        pictures, [Color(236, 226, 204), Color(196, 92, 72)], False
    )
    var stresses = List[BufferGeometry]()
    stresses.append(
        stress_geometry(
            problem.mesh,
            result,
            1.0,
            Pressure64(0, PASCAL),
            Pressure64(20, MEGAPASCAL),
        )
    )
    var colored = _draw(stresses, [Color(255, 255, 255)], True)
    var sheet = Framebuffer(2 * PANEL, PANEL, Color(0, 0, 0))
    blit(sheet, bones, 0, 0)
    blit(sheet, colored, PANEL, 0)
    Path(destination).write_bytes(encode(sheet))
    print(
        problem.mesh.node_count(),
        "nodes,",
        problem.mesh.element_count(),
        "tetrahedra,",
        result.iterations,
        "iterations",
    )
    print("Platen force:   ", force, "N")
    print("Rule of mixtures:", mixture, "N")
    print("Cortical share:  ", share * 100, "percent of the load")
    print("Wrote", destination)
