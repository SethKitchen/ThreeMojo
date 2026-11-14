# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The first three natural modes of a steel tuning fork.

    mojo run -I . examples/fem_modes.mojo [out/fem-modes.png]

The page is Tetrahedral FEM. The fork is a label map of 5 mm voxels: a
stem 25 mm long, a yoke 25 mm wide and two tines 80 mm long and 5 mm
square, 15 mm apart. The
voxels are meshed with ten-node tetrahedra, and the bottom of the stem
is clamped. The mesh stays below 4096 free degrees of freedom, the most
that the Sturm check of the eigen solver takes. Each panel is one mode, drawn with its largest motion at
7 mm and colored by motion, from blue at rest to red. The program
prints the frequencies.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z
from extensions.fem.mesh import quadratic_mesh, voxel_mesh
from extensions.fem.modal import natural_modes
from extensions.fem.post import mode_geometry
from extensions.fem.static import StaticProblem
from extensions.imaging.ids import LabelId
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.labels import LabelMap
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
    DEGREE,
    Density64,
    GIGAPASCAL,
    KILOGRAM_PER_CUBIC_METER,
    Length,
    Length64,
    METER,
    PER_SECOND,
    Pressure64,
)

comptime DEFAULT_OUTPUT = "out/fem-modes.png"
comptime PANEL_WIDTH = 320
comptime PANEL_HEIGHT = 420
comptime MODES = 3
comptime VOXEL = 5.0


def _fork() raises -> LabelMap:
    """A stem, a yoke and two tines, in voxels of 5 mm."""
    var size = Length64(VOXEL, MILLIMETER64)
    var map = LabelMap(ImageVolume(5, 1, 22, size, size, size))
    var fork = LabelId(1)
    for k in range(22):
        for i in range(5):
            var stem = k < 5 and i == 2
            var yoke = k == 5
            var tine = k > 5 and (i == 0 or i == 4)
            if stem or yoke or tine:
                map.set(i, 0, k, fork)
    return map^


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var mesh = quadratic_mesh(voxel_mesh(_fork(), LabelId(1)))
    var steel = IsotropicMaterial(Pressure64(200, GIGAPASCAL), 0.3)
    var problem = StaticProblem(mesh^, [steel])
    var bottom = Length64(-VOXEL / 2, MILLIMETER64)
    for node in problem.mesh.nodes_on_plane(
        DOF_Z, bottom, Length64(1e-9, METER)
    ):
        problem.fix(node, DOF_X, Length64(0, METER))
        problem.fix(node, DOF_Y, Length64(0, METER))
        problem.fix(node, DOF_Z, Length64(0, METER))
    var densities: List[Density64] = [Density64(7850, KILOGRAM_PER_CUBIC_METER)]
    var modes = natural_modes(problem, densities, MODES, 1e-10, 300)
    var sheet = Framebuffer(MODES * PANEL_WIDTH, PANEL_HEIGHT, Color(0, 0, 0))
    for m in range(MODES):
        var renderer = gallery_renderer(
            PANEL_WIDTH, PANEL_HEIGHT, Color(16, 18, 26)
        )
        var assets = Assets()
        var scene = Scene()
        var shape = assets.geometries.add(
            mode_geometry(
                problem.mesh,
                modes.shapes[m],
                Length64(7, MILLIMETER64),
            )
        )
        var material = assets.materials.add(
            Material(
                Color(255, 255, 255),
                kind=PHONG,
                vertex_colors=True,
                specular=Color(60, 60, 60),
                shininess=30,
            )
        )
        # Turn the fork's z axis up, and center it.
        var holder = Object3D()
        holder.set_rotation_from_axis_angle(
            Vector3(1, 0, 0), Angle(-90.0, DEGREE)
        )
        holder.set_position(-0.01, -0.0525, 0)
        scene.add_mesh(Mesh(shape, material, scene.add(holder^)))
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
            PANEL_WIDTH,
            PANEL_HEIGHT,
            Vector3(0.17, 0.035, 0.17),
            Vector3(0, -0.002, 0),
            field_of_view=Angle(34.0, DEGREE),
            near=Length(0.01, METER),
            far=Length(2.0, METER),
        )
        blit(sheet, renderer.render(scene, assets, camera), m * PANEL_WIDTH, 0)
        print(
            "Mode",
            m + 1,
            ":",
            modes.frequencies[m].to(PER_SECOND),
            "Hz",
        )
    Path(destination).write_bytes(encode(sheet))
    print(
        problem.mesh.node_count(),
        "nodes,",
        problem.mesh.element_count(),
        "tetrahedra,",
        modes.iterations,
        "iterations",
    )
    print("Wrote", destination)
