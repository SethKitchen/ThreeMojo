# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A heated needle in perfused tissue, by Pennes' bioheat equation.

    mojo run -I . examples/bioheat.mojo [out/bioheat.png]

The page is Tetrahedral FEM. A block of tissue 40 mm on a side is cut in
half through a needle, which enters from the top and stops at the
center. The needle holds 70 C. The tissue conducts heat at 0.5 W/(m K),
makes 400 W/m^3 of metabolic heat, and blood perfuses it at 37 C. The
picture shows the half block from its cut face, colored from 37 C (blue)
to 70 C (red). The program prints the temperature at 2, 5 and 10 mm
below the needle's tip, where a thermocouple would read it, and the
power that the needle supplies.

This is a picture of a simple model, for teaching. It is not a plan for
a treatment.
"""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.fem.ids import DOF_X, NodeId
from extensions.fem.mesh import box_mesh
from extensions.fem.post import temperature_geometry
from extensions.fem.probe import sample_temperature
from extensions.fem.thermal import (
    PerfusionCoefficient64,
    PowerDensity64,
    ThermalMaterial,
    ThermalProblem,
    WATT_PER_CUBIC_METER,
    WATT_PER_CUBIC_METER_KELVIN,
    held_heat,
    solve_thermal,
)
from extensions.sdf.vector import v3
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
    Length,
    Length64,
    METER,
    ThermalConductivity64,
    WATT,
    WATT_PER_METER_KELVIN,
)
from units.temperature import CELSIUS, KELVIN, Temperature64

comptime DEFAULT_OUTPUT = "out/bioheat.png"
comptime WIDTH = 640
comptime HEIGHT = 480
comptime SIDE = 0.04
comptime CELLS = 16
comptime NEEDLE = 70.0


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    # Half of the block: x from 0 to 20 mm, with the cut face at x = 20 mm.
    var mesh = box_mesh(
        Length64(SIDE / 2, METER),
        Length64(SIDE, METER),
        Length64(SIDE, METER),
        CELLS // 2,
        CELLS,
        CELLS,
    )
    var tissue = ThermalMaterial(
        ThermalConductivity64(0.5, WATT_PER_METER_KELVIN),
        PowerDensity64(400, WATT_PER_CUBIC_METER),
        PerfusionCoefficient64(1890, WATT_PER_CUBIC_METER_KELVIN),
    )
    var problem = ThermalProblem(mesh^, [tissue])
    # The needle: the nodes on the cut face along y = 20 mm, from the top
    # down to the center.
    var tip = -1
    for n in range(problem.mesh.node_count()):
        var p = problem.mesh.nodes[n]
        var on_cut = abs(p.x - SIDE / 2) < 1e-9
        var on_line = abs(p.y - SIDE / 2) < 1e-9
        if on_cut and on_line and p.z >= SIDE / 2 - 1e-9:
            problem.fix(NodeId(n), Temperature64(NEEDLE, CELSIUS))
            if abs(p.z - SIDE / 2) < 1e-9:
                tip = n
    var result = solve_thermal(problem, 1e-10, 5000)
    # Thermocouples on the axis below the tip, read between the nodes.
    for depth in [2.0, 5.0, 10.0]:
        var probe = v3(SIDE / 2, SIDE / 2, SIDE / 2 - depth / 1000)
        print(
            "Temperature",
            depth,
            "mm below the tip:",
            sample_temperature(problem.mesh, result, probe).to(CELSIUS),
            "C",
        )
    # The half block takes half of the needle's heat.
    var half = held_heat(problem, result).total().to(WATT)
    print("The needle supplies", 2 * half, "W")
    var geometry = temperature_geometry(
        problem.mesh,
        result,
        Temperature64(37, CELSIUS),
        Temperature64(NEEDLE, CELSIUS),
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
            specular=Color(30, 30, 30),
            shininess=12,
        )
    )
    # Turn the block's z axis up, and center it.
    var holder = Object3D()
    holder.set_rotation_from_axis_angle(Vector3(1, 0, 0), Angle(-90.0, DEGREE))
    holder.set_position(
        -Float32(SIDE / 4), -Float32(SIDE / 2), Float32(SIDE / 2)
    )
    scene.add_mesh(Mesh(shape, material, scene.add(holder^)))
    fill_and_key(
        scene,
        1.0,
        2.0,
        2.5,
        Color(255, 255, 255),
        0.6,
        Color(255, 250, 240),
        2.0,
    )
    scene.update()
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(0.075, 0.045, 0.05),
        Vector3(0.002, -0.002, 0),
        field_of_view=Angle(36.0, DEGREE),
        near=Length(0.01, METER),
        far=Length(2.0, METER),
    )
    Path(destination).write_bytes(
        encode(renderer.render(scene, assets, camera))
    )
    print(
        problem.mesh.node_count(),
        "nodes,",
        problem.mesh.element_count(),
        "tetrahedra,",
        result.iterations,
        "iterations; needle tip node",
        tip,
    )
    print("Wrote", destination)
