# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One generated tower through every view of the canonical model.

The tower is written once. The render view draws it, the structural view
solves its frame, the thermal view simulates a winter day, and IFC
exchange writes and reads it back. The references are equilibrium of the
dead load, a positive heating need on a cold day, and an unchanged
fingerprint after the IFC round trip.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from core.assets import Assets
from core.scene import Scene
from extensions.building.fingerprint import fingerprint
from extensions.building.model import Building
from extensions.building.generate.tower import TowerOptions, generate_tower
from extensions.building.ifc.ifc4 import read_ifc, write_ifc
from extensions.building.views.render import RenderOptions, add_building
from extensions.building.views.structural import (
    default_options,
    structural_view,
)
from extensions.building.views.thermal import (
    default_thermal_options,
    thermal_view,
)
from extensions.energy.ids import ZoneId
from extensions.energy.simulation import default_options as simulation_options
from extensions.energy.simulation import simulate
from extensions.energy.weather import WeatherLocation, design_day
from extensions.structure.modal import solve_modes
from extensions.structure.static import solve_static
from generators.skyscraper import SkyscraperParameters
from units.si import (
    Angle64,
    DEGREE,
    Duration64,
    HOUR,
    Length,
    Length64,
    METER,
    METER_PER_SECOND,
    Velocity64,
)
from units.temperature import CELSIUS, Temperature64


def _tower() raises -> Building:
    var parameters = SkyscraperParameters()
    parameters.seed = 11
    parameters.total_height = Length(12, METER)
    return generate_tower(TowerOptions(parameters^))


def test_one_tower_serves_every_view() raises:
    var tower = _tower()
    # Render.
    var scene = Scene()
    var assets = Assets()
    var drawn = add_building(scene, assets, tower, RenderOptions.default())
    assert_true(drawn.triangles > 10000)
    # Structure: the supports carry the whole dead load.
    var frame = structural_view(tower, default_options())
    var dead = solve_static(frame.model, frame.dead)
    var reactions = Float64(0)
    var applied = Float64(0)
    for i in range(len(dead.reactions) // 6):
        reactions += dead.reactions[6 * i + 2]
        applied += dead.loads[6 * i + 2]
    assert_true(applied < 0)
    assert_almost_equal(reactions, -applied, atol=1e-6 * abs(applied))
    var modes = solve_modes(frame.model, 2)
    assert_true(modes.frequencies[0].value > 0)
    # Energy: a cold day needs heat.
    var zones = thermal_view(tower, default_thermal_options(), List[ZoneId]())
    var weather = design_day(
        WeatherLocation(
            "New York",
            Angle64(40.7, DEGREE),
            Angle64(-74.0, DEGREE),
            Duration64(-5, HOUR),
            Length64(10, METER),
        ),
        1,
        21,
        Temperature64(-8, CELSIUS),
        Temperature64(-1, CELSIUS),
        Temperature64(-12, CELSIUS),
        Velocity64(5, METER_PER_SECOND),
        1.0,
        1,
    )
    var result = simulate(zones.model, weather, simulation_options())
    var heat = Float64(0)
    for z in range(result.zone_count):
        heat += result.heating_total[z]
    assert_true(heat > 0)
    # Exchange: the model comes back exactly.
    var back = read_ifc(write_ifc(tower, "t"), Length64(1e-6, METER))
    assert_equal(fingerprint(back), fingerprint(tower))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
