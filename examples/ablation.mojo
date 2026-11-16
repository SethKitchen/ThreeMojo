# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A needle heats perfused tissue for six minutes, and the dose kills a zone.

    mojo run -I . examples/ablation.mojo [out/ablation.png]

The page is Tetrahedral FEM. As in the bioheat example, a block of tissue
40 mm on a side is cut in half through a needle that enters from the top
and stops at the center. The tissue starts at 37 C. The needle holds
90 C for six minutes, and `solve_transient` follows the temperatures in
steps of two seconds. The tissue conducts 0.5 W/(m K), has a density of
1050 kg/m^3 and a specific heat of 3600 J/(kg K), and blood perfuses it
at 37 C.

`thermal_dose` turns the history into the cumulative equivalent minutes
at 43 C of each node. The left panel is the temperature at the end, from
37 C (blue) to 90 C (red). The right panel is the dose on a logarithmic
scale, from 1 minute (blue) to 240 minutes (red): the red zone is the
dose that kills most tissues. The program prints the ablated volume and
the temperature and dose at 5 mm from the tip.

This is a picture of a simple model, for teaching. It is not a plan for
a treatment.
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.fem.dose import dose_volume, thermal_dose
from extensions.fem.ids import NodeId
from extensions.fem.mesh import box_mesh
from extensions.fem.post import dose_geometry, temperature_geometry
from extensions.fem.probe import locate_point, sample_field
from extensions.fem.thermal import (
    PerfusionCoefficient64,
    PowerDensity64,
    ThermalCapacity,
    ThermalMaterial,
    ThermalProblem,
    ThermalResult,
    WATT_PER_CUBIC_METER,
    WATT_PER_CUBIC_METER_KELVIN,
    solve_transient,
)
from extensions.sdf.vector import v3
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
    Density64,
    Duration64,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    Length,
    Length64,
    METER,
    MINUTE,
    SECOND,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    WATT_PER_METER_KELVIN,
)
from units.temperature import CELSIUS, KELVIN, Temperature64

comptime DEFAULT_OUTPUT = "out/ablation.png"
comptime WIDTH = 640
comptime HEIGHT = 480
comptime SIDE = 0.04
comptime CELLS = 16
comptime NEEDLE = 90.0
comptime STEP = 2.0
comptime STEPS = 180


def _panel(var geometry: BufferGeometry) raises -> Framebuffer:
    """Return the half block drawn from its cut face."""
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
    return renderer.render(scene, assets, camera)


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
    var start = List[Temperature64]()
    for n in range(problem.mesh.node_count()):
        var p = problem.mesh.nodes[n]
        var on_cut = abs(p.x - SIDE / 2) < 1e-9
        var on_line = abs(p.y - SIDE / 2) < 1e-9
        if on_cut and on_line and p.z >= SIDE / 2 - 1e-9:
            problem.fix(NodeId(n), Temperature64(NEEDLE, CELSIUS))
            start.append(Temperature64(NEEDLE, CELSIUS))
        else:
            start.append(Temperature64(37, CELSIUS))
    var capacity: List[ThermalCapacity] = [
        ThermalCapacity(
            Density64(1050, KILOGRAM_PER_CUBIC_METER),
            SpecificHeatCapacity64(3600, JOULE_PER_KILOGRAM_KELVIN),
        )
    ]
    var history = solve_transient(
        problem,
        capacity,
        start,
        Duration64(STEP, SECOND),
        STEPS,
        3,
        1e-10,
        2000,
    )
    var doses = thermal_dose(history)
    # The half block holds half of the ablated zone.
    var ablated = 2.0 * dose_volume(
        problem.mesh, doses, Duration64(240, MINUTE)
    ).to(CUBIC_METER)
    var last = ThermalResult(
        history.temperatures[len(history.temperatures) - 1].copy()
    )
    var probe = locate_point(
        problem.mesh, v3(SIDE / 2, SIDE / 2, SIDE / 2 - 0.005)
    )
    var hot = sample_field(problem.mesh, probe, last.temperatures, 1)[0]
    var minutes = List[Float64]()
    for dose in doses:
        minutes.append(dose.to(MINUTE))
    var dosed = sample_field(problem.mesh, probe, minutes, 1)[0]
    var left = _panel(
        temperature_geometry(
            problem.mesh,
            last,
            Temperature64(37, CELSIUS),
            Temperature64(NEEDLE, CELSIUS),
        )
    )
    var right = _panel(
        dose_geometry(
            problem.mesh,
            doses,
            Duration64(1, MINUTE),
            Duration64(240, MINUTE),
        )
    )
    var sheet = Framebuffer(2 * WIDTH, HEIGHT, Color(0, 0, 0))
    blit(sheet, left, 0, 0)
    blit(sheet, right, WIDTH, 0)
    Path(destination).write_bytes(encode(sheet))
    print(
        "After",
        Float64(STEPS) * STEP / 60.0,
        "minutes:",
        ablated * 1e6,
        "mL reach 240 minutes at 43 C",
    )
    print(
        "At 5 mm below the tip:",
        hot - 273.15,
        "C and",
        dosed,
        "minutes;",
        history.iterations,
        "iterations",
    )
    print("Wrote", destination)
