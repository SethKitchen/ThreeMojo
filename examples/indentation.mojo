# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A soft block indented far: linear elasticity beside the Neo-Hookean solid.

    mojo run -I . examples/indentation.mojo [out/indentation.png]

The page is Tetrahedral FEM. A block of soft tissue, 40 by 40 by 20 mm,
of 5 kPa and a Poisson's ratio of 0.45, sits on a held base. A square
indenter 10 mm wide is bonded to the middle of its top and pressed 8 mm
down, two fifths of its thickness.

The left block is the linear solve, and the right block is the
Neo-Hookean solve in 16 load steps. Each is drawn at its true size,
colored by von Mises stress from 0 (blue) to 6 kPa (red). The program
prints the force on the indenter of each solve. At this depth the
Neo-Hookean block is the stiffer, as soft tissue is.
"""

from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.hyperelastic import solve_neo_hookean
from extensions.fem.ids import DOF_X, DOF_Y, DOF_Z, NodeId
from extensions.fem.mesh import box_mesh
from extensions.fem.post import deformed_geometry
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
    KILOPASCAL,
    Length64,
    METER,
    PASCAL,
    Pressure64,
)

comptime DEFAULT_OUTPUT = "out/indentation.png"
comptime WIDTH = 760
comptime HEIGHT = 340
comptime SIDE = 0.04
comptime THICK = 0.02
comptime HALF_PAD = 0.005
comptime DEPTH = 0.008


def _problem() raises -> StaticProblem:
    """The block, with its base held and its indenter pressed down."""
    var mesh = box_mesh(
        Length64(SIDE, METER),
        Length64(SIDE, METER),
        Length64(THICK, METER),
        8,
        8,
        4,
    )
    var tissue = IsotropicMaterial(Pressure64(5.0, KILOPASCAL), 0.45)
    var problem = StaticProblem(mesh^, [tissue])
    for n in range(problem.mesh.node_count()):
        var p = problem.mesh.nodes[n]
        var under = (
            abs(p.x - SIDE / 2) <= HALF_PAD + 1e-9
            and abs(p.y - SIDE / 2) <= HALF_PAD + 1e-9
        )
        if p.z < 1e-9:
            problem.fix(NodeId(n), DOF_X, Length64(0, METER))
            problem.fix(NodeId(n), DOF_Y, Length64(0, METER))
            problem.fix(NodeId(n), DOF_Z, Length64(0, METER))
        elif p.z > THICK - 1e-9 and under:
            problem.fix(NodeId(n), DOF_X, Length64(0, METER))
            problem.fix(NodeId(n), DOF_Y, Length64(0, METER))
            problem.fix(NodeId(n), DOF_Z, Length64(-DEPTH, METER))
    return problem^


def _push(problem: StaticProblem, reactions: List[Float64]) -> Float64:
    """Return the force that the indenter presses with, in newtons."""
    var force = 0.0
    for n in range(problem.mesh.node_count()):
        if (
            problem.mesh.nodes[n].z > THICK - 1e-9
            and problem.prescribed[3 * n + 2]
        ):
            force -= reactions[3 * n + 2]
    return force


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var linear = _problem()
    var nonlinear = _problem()
    var small = solve_static(linear, 1e-11, 20000)
    var large = solve_neo_hookean(nonlinear, 16, 1e-8, 30, 1e-11, 20000)
    var low = Pressure64(0, PASCAL)
    var high = Pressure64(6.0, KILOPASCAL)
    var renderer = gallery_renderer(WIDTH, HEIGHT, Color(16, 18, 26))
    var assets = Assets()
    var scene = Scene()
    var material = assets.materials.add(
        Material(
            Color(255, 255, 255),
            kind=PHONG,
            vertex_colors=True,
            specular=Color(40, 40, 40),
            shininess=20,
        )
    )
    var shapes = List[GeometryId]()
    shapes.append(
        assets.geometries.add(
            deformed_geometry(
                linear.mesh,
                small.displacements,
                small.von_mises,
                1.0,
                low,
                high,
            )
        )
    )
    shapes.append(
        assets.geometries.add(
            deformed_geometry(
                nonlinear.mesh,
                large.displacements,
                large.von_mises,
                1.0,
                low,
                high,
            )
        )
    )
    for b in range(2):
        # The block has z up; the scene has y up.
        var node = Object3D()
        node.set_rotation_from_axis_angle(
            Vector3(1, 0, 0), Angle(-90.0, DEGREE)
        )
        node.set_position(
            Float32(-0.05 + 0.055 * Float64(b)), -0.01, Float32(SIDE / 2)
        )
        scene.add_mesh(Mesh(shapes[b], material, scene.add(node^)))
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
        Vector3(0.0, 0.055, 0.082),
        Vector3(0.002, -0.004, 0),
        field_of_view=Angle(40.0, DEGREE),
    )
    var frame = renderer.render(scene, assets, camera)
    Path(destination).write_bytes(encode(frame))
    print(
        "Indenter force: linear",
        _push(linear, small.reactions) * 1000,
        "mN; Neo-Hookean",
        _push(nonlinear, large.reactions) * 1000,
        "mN in",
        large.newton_steps,
        "Newton steps; converged:",
        large.converged,
    )
    var least = 1.0
    for j in large.jacobians:
        least = min(least, j)
    print("Least J of an element:", least)
    print("Wrote", destination)
