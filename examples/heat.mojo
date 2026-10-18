# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An office floor's rooms through a summer day, colored by temperature.

    mojo run -I . examples/heat.mojo [path.png]

The page is Building energy. The thermal view turns a generated floor
into zones. `simulate` runs the heat balance through a clear July day
with no cooling. Each frame is one hour: each room's floor is colored
from 20 degrees Celsius, blue, to 34, red.
"""

from examples.output import example_destination, gallery_camera, write_frames
from examples.preview import Triangles, add_sky_and_sun, heat_color

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from units.si import DEGREE, DEGREE64, METER, Angle, Length
from extensions.building.construction import Construction, Layer, double_glazing
from extensions.building.generate.openings import (
    WindowOptions,
    add_doors,
    add_windows,
)
from extensions.building.generate.plan import (
    OFFICE_FLOOR,
    default_plan_options,
    plan_floor,
)
from extensions.building.ids import ConstructionId, MaterialId
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
)
from extensions.building.model import (
    ConstructionSet,
    Site,
    StoreyPlan,
    assemble,
)
from extensions.building.views.render import FULL, RenderOptions, add_building
from extensions.building.views.thermal import (
    default_thermal_options,
    thermal_view,
)
from extensions.energy.ids import ZoneId
from extensions.energy.simulation import default_options, simulate
from extensions.energy.weather import WeatherLocation, design_day
from extensions.topology.arrangement import Point2
from units.si import (
    Angle64,
    Duration64,
    HOUR,
    Length64,
    METER_PER_SECOND,
    Velocity64,
)
from units.temperature import CELSIUS, Temperature64

comptime DEFAULT_OUTPUT = "out/building-energy.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 24
comptime DELAY_MS = 160


def _camera() raises -> PerspectiveCamera:
    """Return the camera, placed to frame the scene.

    Returns:
        The camera.

    Raises:
        Error: If the camera's settings are not valid.
    """
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        Vector3(22, 34, 30),
        Vector3(0, 0, 0),
        field_of_view=Angle(40.0, DEGREE),
        near=Length(0.5, METER),
        far=Length(300, METER),
    )
    return camera^


def main() raises:
    var m = Length64(1, METER)
    var materials = List[BuildingMaterial]()
    materials.append(brick())
    materials.append(mineral_wool())
    materials.append(gypsum_board())
    materials.append(concrete())
    var constructions = List[Construction]()
    constructions.append(
        Construction(
            "wall",
            [
                Layer(MaterialId(0), m.scaled(0.2)),
                Layer(MaterialId(1), m.scaled(0.1)),
                Layer(MaterialId(2), m.scaled(0.0125)),
            ],
        )
    )
    constructions.append(
        Construction("partition", [Layer(MaterialId(2), m.scaled(0.1))])
    )
    constructions.append(
        Construction("slab", [Layer(MaterialId(3), m.scaled(0.25))])
    )
    var footprint: List[Point2] = [
        Point2(-18, -10),
        Point2(18, -10),
        Point2(18, 10),
        Point2(-18, 10),
    ]
    var plans = List[StoreyPlan]()
    plans.append(
        StoreyPlan(
            "office",
            m.scaled(3.5),
            plan_floor(footprint, OFFICE_FLOOR, 3, default_plan_options()),
        )
    )
    var c = ConstructionId(0)
    var building = assemble(
        "office floor",
        Site(
            Angle64(40.7, DEGREE64),
            Angle64(-74.0, DEGREE64),
            m.scaled(10),
            Angle64(0),
        ),
        m.scaled(0),
        plans,
        materials^,
        constructions^,
        ConstructionSet(
            c,
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(2),
            ConstructionId(2),
        ),
        m.scaled(1e-6),
    )
    _ = add_doors(building, m.scaled(0.9), m.scaled(2.1))
    _ = add_windows(
        building,
        WindowOptions(
            m.scaled(2.6),
            m.scaled(0.5),
            m.scaled(0.9),
            m.scaled(1.6),
            double_glazing(),
        ),
    )
    var options = default_thermal_options()
    options.cooling_setpoint = Temperature64(60, CELSIUS)
    var view = thermal_view(building, options, List[ZoneId]())
    var weather = design_day(
        WeatherLocation(
            "New York",
            Angle64(40.7, DEGREE64),
            Angle64(-74.0, DEGREE64),
            Duration64(-5, HOUR),
            m.scaled(10),
        ),
        7,
        21,
        Temperature64(22, CELSIUS),
        Temperature64(33, CELSIUS),
        Temperature64(18, CELSIUS),
        Velocity64(3, METER_PER_SECOND),
        1.0,
        1,
    )
    var result = simulate(view.model, weather, default_options())
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(26, 30, 40))
    var camera = _camera()
    var frames = List[Framebuffer]()
    for hour in range(FRAMES):
        var assets = Assets()
        var scene = Scene()
        var drawn = add_building(
            scene, assets, building, RenderOptions(FULL, 0)
        )
        var mesh = Triangles()
        for s in range(len(building.spaces)):
            ref outline = building.spaces[s].outline
            var zone = view.space_zone[s]
            var t = result.air_temperature(hour, zone).to(CELSIUS)
            var color = heat_color((t - 20) / 14)
            var a = Vec3d(outline[0].x, outline[0].y, 0.03)
            for k in range(1, len(outline) - 1):
                var b = Vec3d(outline[k].x, outline[k].y, 0.03)
                var d = Vec3d(outline[k + 1].x, outline[k + 1].y, 0.03)
                if (b - a).cross(d - a).z < 0:
                    mesh.triangle(a, d, b, color)
                else:
                    mesh.triangle(a, b, d, color)
        mesh.add_to(scene, assets, drawn.root)
        add_sky_and_sun(scene, 0.55, 1.5)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
    write_frames(
        frames,
        example_destination(String(DEFAULT_OUTPUT)),
        DELAY_MS,
        len(frames),
    )
