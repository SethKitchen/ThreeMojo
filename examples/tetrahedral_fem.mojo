# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A steel cantilever of ten-node tetrahedra, bent by a load at its tip.

    mojo run -I . examples/tetrahedral_fem.mojo [out/tetrahedral-fem.png]

The page is Tetrahedral FEM. The beam is 600 mm long and 60 mm square,
clamped at x = 0, and meshed with quadratic tetrahedra. A force of 20 kN
pulls its tip face down. The picture
shows the bent beam, drawn 40 times its true deflection, colored by von
Mises stress from 0 (blue) to 300 MPa (red). The program prints the tip
deflection and the deflection that Euler-Bernoulli beam theory gives.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, NodeId
from extensions.fem.mesh import box_mesh, quadratic_mesh
from extensions.fem.post import stress_geometry
from extensions.fem.static import StaticProblem, solve_static
from materials.material import Material, PHONG
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.png import encode
from std.pathlib import Path
from tools._example_output import (
    example_destination,
    fill_and_key,
    gallery_camera,
    gallery_renderer,
)
from units.si import (
    Angle,
    DEGREE,
    Force64,
    GIGAPASCAL,
    Length64,
    MEGAPASCAL,
    METER,
    NEWTON,
    PASCAL,
    Pressure64,
)

comptime DEFAULT_OUTPUT = "out/tetrahedral-fem.png"
comptime WIDTH = 720
comptime HEIGHT = 360
comptime LENGTH = 0.6
comptime SIDE = 0.06
comptime FORCE = 20000.0
comptime YOUNG = 200.0e9
comptime SCALE = 40.0


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var mesh = quadratic_mesh(
        box_mesh(
            Length64(LENGTH, METER),
            Length64(SIDE, METER),
            Length64(SIDE, METER),
            30,
            3,
            3,
        )
    )
    var steel = IsotropicMaterial(Pressure64(YOUNG / 1e9, GIGAPASCAL), 0.3)
    var problem = StaticProblem(mesh^, [steel])
    var tolerance = Length64(1e-9, METER)
    for node in problem.mesh.nodes_on_plane(
        DOF_X, Length64(0, METER), tolerance
    ):
        problem.fix(node, DOF_X, Length64(0, METER))
        problem.fix(node, DOF_Y, Length64(0, METER))
        problem.fix(node, DOF_Z, Length64(0, METER))
    var tip = problem.mesh.nodes_on_plane(
        DOF_X, Length64(LENGTH, METER), tolerance
    )
    var share = FORCE / Float64(len(tip))
    for node in tip:
        problem.load(node, DOF_Z, Force64(-share, NEWTON))
    var result = solve_static(problem, 1e-10, 5000)
    var deflection = 0.0
    for node in tip:
        deflection += result.displacement(node).z
    deflection /= Float64(len(tip))
    var inertia = SIDE**4 / 12.0
    var beam = FORCE * LENGTH**3 / (3.0 * YOUNG * inertia)
    var peak = 0.0
    for stress in result.von_mises:
        peak = max(peak, stress.to(PASCAL))
    var geometry = stress_geometry(
        problem.mesh,
        result,
        SCALE,
        Pressure64(0, PASCAL),
        Pressure64(300, MEGAPASCAL),
    )
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()
    var shape = assets.geometries.add(geometry^)
    var material = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=PHONG,
            vertex_colors=True,
            specular=Color(40, 40, 40),
            shininess=20,
        )
    )
    # The beam runs along x with z up; the scene has y up.
    var node = Object3D()
    node.set_rotation_from_axis_angle(Vector3(1, 0, 0), Angle(-90.0, DEGREE))
    node.set_position(-Float32(LENGTH / 2), 0.1, 0)
    scene.add_mesh(Mesh(shape, material, scene.add(node^)))
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
        WIDTH,
        HEIGHT,
        Vector3(0.12, 0.16, 0.62),
        Vector3(0, -0.02, 0),
        field_of_view=Angle(40.0, DEGREE),
    )
    var frame = renderer.render(scene, assets, camera)
    Path(destination).write_bytes(encode(frame))
    print(
        problem.mesh.node_count(),
        "nodes,",
        problem.mesh.element_count(),
        "tetrahedra,",
        result.iterations,
        "iterations",
    )
    print("Tip deflection:", -deflection * 1000, "mm")
    print("Beam theory:   ", beam * 1000, "mm")
    print("Peak von Mises:", peak / 1e6, "MPa")
    print("Wrote", destination)
