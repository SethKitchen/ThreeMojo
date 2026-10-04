# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.energy.zone`: gains, films, zones, surfaces and
windows.

The film references are the surface resistances of ISO 6946 and its
Annex C correlation, h = 4 + 4 v + 4 epsilon sigma T³.
"""

from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
)
from extensions.building.construction import (
    Construction,
    Glazing,
    HORIZONTAL_FLOW,
    Layer,
    double_glazing,
)
from extensions.building.ids import ConstructionId, MaterialId
from extensions.building.kinds import (
    BEDROOM,
    KITCHEN,
    MECHANICAL,
    OFFICE,
    RETAIL,
    SpaceUse,
)
from extensions.building.material import (
    BuildingMaterial,
    brick,
    gypsum_board,
    mineral_wool,
)
from extensions.building.model import Site
from extensions.energy.ids import (
    BoundaryKind,
    EXTERIOR,
    GROUND,
    INTERZONE,
    SurfaceId,
    WindowId,
    ZoneId,
)
from extensions.energy.zone import (
    AIR_CHANGE_PER_HOUR,
    InternalGains,
    Surface,
    Window,
    Zone,
    ZoneModel,
    exterior_film,
    gain_fraction,
    interior_film,
    outside_film_coefficient,
    typical_gains,
)
from generators.utils import Vec3d
from units.si import (
    Angle64,
    Area64,
    DEGREE,
    Frequency64,
    HeatCapacity64,
    HeatFlux64,
    JOULE_PER_KELVIN,
    Length64,
    METER,
    METER_PER_SECOND,
    SQUARE_METER,
    ThermalTransmittance64,
    Velocity64,
    Volume64,
    WATT_PER_KELVIN,
    WATT_PER_SQUARE_METER,
    WATT_PER_SQUARE_METER_KELVIN,
)
from units.temperature import CELSIUS, KELVIN, Temperature64


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _site() -> Site:
    return Site(
        Angle64(40, DEGREE), Angle64(-105, DEGREE), _m(1600), Angle64(0)
    )


def _materials() -> List[BuildingMaterial]:
    var out = List[BuildingMaterial]()
    out.append(brick())
    out.append(mineral_wool())
    out.append(gypsum_board())
    return out^


def _constructions() -> List[Construction]:
    var out = List[Construction]()
    out.append(
        Construction(
            "wall",
            [
                Layer(MaterialId(0), _m(0.2)),
                Layer(MaterialId(1), _m(0.1)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    return out^


def _gains(p: Float64) -> InternalGains:
    var g = HeatFlux64(p, WATT_PER_SQUARE_METER)
    return InternalGains(g, g, g)


def _zone() -> Zone:
    return Zone(
        "room",
        OFFICE,
        Volume64(60),
        Area64(20, SQUARE_METER),
        Frequency64(0.5, AIR_CHANGE_PER_HOUR),
        _gains(1),
        Temperature64(20, CELSIUS),
        Temperature64(26, CELSIUS),
        HeatCapacity64(1000, JOULE_PER_KELVIN),
    )


def _film(h: Float64) -> ThermalTransmittance64:
    return ThermalTransmittance64(h, WATT_PER_SQUARE_METER_KELVIN)


def _surface(
    construction: Int, boundary: BoundaryKind, outside: Optional[ZoneId]
) -> Surface:
    return Surface(
        "s",
        ConstructionId(construction),
        boundary,
        ZoneId(0),
        outside,
        Area64(10, SQUARE_METER),
        Vec3d(0, -1, 0),
        _film(7.69),
        _film(25),
    )


def _model() raises -> ZoneModel:
    var model = ZoneModel(_site(), _materials(), _constructions())
    _ = model.add_zone(_zone())
    return model^


# --- gains ------------------------------------------------------------------


def test_typical_gains() raises:
    var office = typical_gains(OFFICE)
    assert_almost_equal(office.total().value, 25, atol=1e-12)
    assert_almost_equal(typical_gains(KITCHEN).equipment.value, 25, atol=1e-12)
    for i in range(12):
        typical_gains(SpaceUse(i)).check()
    with assert_raises(contains="space use"):
        _ = typical_gains(SpaceUse(12))
    with assert_raises(contains="internal gain"):
        _gains(-1).check()
    with assert_raises(contains="internal gain"):
        _gains(inf[DType.float64]()).check()


def test_gain_profiles() raises:
    var work: List[Float64] = [0.1, 1.0, 1.0, 0.1]
    var work_hours = [7, 8, 17, 18]
    for i in range(4):
        assert_equal(gain_fraction(OFFICE, work_hours[i]), work[i])
    var shop_hours = [8, 9, 20, 21]
    for i in range(4):
        assert_equal(gain_fraction(RETAIL, shop_hours[i]), work[i])
    var home: List[Float64] = [0.5, 0.3, 0.3, 1.0, 1.0, 0.5]
    var home_hours = [6, 7, 17, 18, 22, 23]
    for i in range(6):
        assert_equal(gain_fraction(BEDROOM, home_hours[i]), home[i])
    assert_equal(gain_fraction(MECHANICAL, 3), 1.0)
    with assert_raises(contains="space use"):
        _ = gain_fraction(SpaceUse(-1), 3)
    with assert_raises(contains="hour"):
        _ = gain_fraction(OFFICE, -1)
    with assert_raises(contains="hour"):
        _ = gain_fraction(OFFICE, 24)


# --- films ------------------------------------------------------------------


def test_iso_6946_films() raises:
    assert_almost_equal(
        interior_film(Vec3d(1, 0, 0)).value, 1 / 0.13, atol=1e-12
    )
    assert_almost_equal(
        interior_film(Vec3d(0, 0, -2)).value, 1 / 0.17, atol=1e-12
    )
    assert_almost_equal(
        interior_film(Vec3d(0, 0, 1)).value, 1 / 0.10, atol=1e-12
    )
    assert_almost_equal(outside_film_coefficient().value, 25, atol=1e-12)
    with assert_raises(contains="normal"):
        _ = interior_film(Vec3d(0, 0, 0))
    # ISO 6946 Annex C at 4 m/s, 10 degrees Celsius and emissivity 0.9.
    var h = exterior_film(
        Velocity64(4, METER_PER_SECOND), Temperature64(10, CELSIUS), 0.9
    )
    var t = 283.15
    assert_almost_equal(
        h.value, 4 + 16 + 4 * 0.9 * 5.670374419e-8 * t * t * t, atol=1e-12
    )
    assert_almost_equal(h.value, 25, atol=0.5)
    var calm = Velocity64(0)
    with assert_raises(contains="wind"):
        _ = exterior_film(Velocity64(-1), Temperature64(10, CELSIUS), 0.9)
    with assert_raises(contains="air temperature"):
        _ = exterior_film(calm, Temperature64(-5, KELVIN), 0.9)
    with assert_raises(contains="emissivity"):
        _ = exterior_film(calm, Temperature64(10, CELSIUS), -0.1)
    with assert_raises(contains="emissivity"):
        _ = exterior_film(calm, Temperature64(10, CELSIUS), 1.1)


# --- zones ------------------------------------------------------------------


def test_zone_air() raises:
    var z = _zone()
    z.check()
    assert_almost_equal(
        z.air_capacity().value, 1.204 * 1006 * 60 + 1000, atol=1e-9
    )
    assert_almost_equal(
        z.infiltration_conductance().to(WATT_PER_KELVIN),
        1.204 * 1006 * 60 * 0.5 / 3600,
        atol=1e-12,
    )


def test_zone_check_refuses() raises:
    var z = _zone()
    z.use = SpaceUse(40)
    with assert_raises(contains="space use"):
        z.check()
    z = _zone()
    z.volume = Volume64(0)
    with assert_raises(contains="volume"):
        z.check()
    z = _zone()
    z.volume = Volume64(inf[DType.float64]())
    with assert_raises(contains="volume"):
        z.check()
    z = _zone()
    z.floor_area = Area64(-1, SQUARE_METER)
    with assert_raises(contains="floor area"):
        z.check()
    z = _zone()
    z.infiltration = Frequency64(nan[DType.float64]())
    with assert_raises(contains="infiltration"):
        z.check()
    z = _zone()
    z.gains = _gains(-2)
    with assert_raises(contains="internal gain"):
        z.check()
    z = _zone()
    z.furniture = HeatCapacity64(-1)
    with assert_raises(contains="furniture"):
        z.check()
    z = _zone()
    z.heating_setpoint = Temperature64(-1, KELVIN)
    with assert_raises(contains="setpoint must be"):
        z.check()
    z = _zone()
    z.cooling_setpoint = Temperature64(-1, KELVIN)
    with assert_raises(contains="setpoint must be"):
        z.check()
    z = _zone()
    z.cooling_setpoint = Temperature64(18, CELSIUS)
    with assert_raises(contains="above cooling"):
        z.check()


# --- the model --------------------------------------------------------------


def test_model_adds_and_finds() raises:
    var model = _model()
    assert_equal(len(model.surfaces_of(ZoneId(0))), 0)
    var second = model.add_zone(_zone())
    assert_equal(second, ZoneId(1))
    var wall = model.add_surface(_surface(0, EXTERIOR, None))
    var party = model.add_surface(_surface(0, INTERZONE, ZoneId(1)))
    var floor = model.add_surface(_surface(0, GROUND, None))
    var w = model.add_window(
        Window(
            "w",
            ZoneId(0),
            Area64(2, SQUARE_METER),
            double_glazing(),
            Vec3d(0, -1, 0),
        )
    )
    assert_equal(w, WindowId(0))
    model.check()
    var u = _constructions()[0].u_value(_materials(), HORIZONTAL_FLOW).value
    assert_almost_equal(
        model.surface_u_value(wall).value,
        1 / (1 / 7.69 - 0.13 + 1 / u),
        atol=1e-12,
    )
    var of_one = model.surfaces_of(ZoneId(1))
    assert_equal(len(of_one), 1)
    assert_equal(of_one[0], party)
    assert_equal(len(model.surfaces_of(ZoneId(0))), 3)
    assert_equal(floor, SurfaceId(2))
    model.check_surface(floor)
    model.check_window(w)
    with assert_raises(contains="surface id"):
        model.check_surface(SurfaceId(3))
    with assert_raises(contains="surface id"):
        _ = model.surface_u_value(SurfaceId(-1))
    with assert_raises(contains="window id"):
        model.check_window(WindowId(1))
    with assert_raises(contains="window id"):
        model.check_window(WindowId(-1))
    with assert_raises(contains="zone id"):
        _ = model.surfaces_of(ZoneId(2))


def test_model_refuses() raises:
    var bad_site = _site()
    bad_site.latitude = Angle64(100, DEGREE)
    with assert_raises(contains="latitude"):
        _ = ZoneModel(bad_site, _materials(), _constructions())
    var bad_materials = _materials()
    bad_materials[0].density = bad_materials[0].density.scaled(-1)
    with assert_raises(contains="positive"):
        _ = ZoneModel(_site(), bad_materials^, _constructions())
    var bad_constructions = _constructions()
    bad_constructions.append(Construction("empty", List[Layer]()))
    with assert_raises(contains="needs a layer"):
        _ = ZoneModel(_site(), _materials(), bad_constructions^)
    var empty = ZoneModel(
        _site(), List[BuildingMaterial](), List[Construction]()
    )
    with assert_raises(contains="needs a zone"):
        empty.check()
    var model = _model()
    var bad_zone = _zone()
    bad_zone.volume = Volume64(-1)
    with assert_raises(contains="volume"):
        _ = model.add_zone(bad_zone^)
    with assert_raises(contains="construction id"):
        _ = model.add_surface(_surface(1, EXTERIOR, None))
    with assert_raises(contains="construction id"):
        _ = model.add_surface(_surface(-1, EXTERIOR, None))
    with assert_raises(contains="boundary kind"):
        _ = model.add_surface(_surface(0, BoundaryKind(5), None))
    var lost = _surface(0, EXTERIOR, None)
    lost.inside = ZoneId(4)
    with assert_raises(contains="zone id"):
        _ = model.add_surface(lost^)
    with assert_raises(contains="needs an outside zone"):
        _ = model.add_surface(_surface(0, INTERZONE, None))
    with assert_raises(contains="zone id"):
        _ = model.add_surface(_surface(0, INTERZONE, ZoneId(-2)))
    with assert_raises(contains="Only an interzone"):
        _ = model.add_surface(_surface(0, GROUND, ZoneId(0)))
    var flat = _surface(0, EXTERIOR, None)
    flat.area = Area64(0, SQUARE_METER)
    with assert_raises(contains="area"):
        _ = model.add_surface(flat^)
    var pointless = _surface(0, EXTERIOR, None)
    pointless.normal = Vec3d(0, 0, 0)
    with assert_raises(contains="normal"):
        _ = model.add_surface(pointless^)
    var filmless = _surface(0, EXTERIOR, None)
    filmless.inside_film = _film(0)
    with assert_raises(contains="film"):
        _ = model.add_surface(filmless^)
    var bare = _surface(0, EXTERIOR, None)
    bare.outside_film = _film(-1)
    with assert_raises(contains="film"):
        _ = model.add_surface(bare^)
    var g = double_glazing()
    var good = Area64(2, SQUARE_METER)
    with assert_raises(contains="zone id"):
        _ = model.add_window(Window("w", ZoneId(3), good, g, Vec3d(1, 0, 0)))
    with assert_raises(contains="window area"):
        _ = model.add_window(
            Window("w", ZoneId(0), Area64(0, SQUARE_METER), g, Vec3d(1, 0, 0))
        )
    with assert_raises(contains="solar"):
        _ = model.add_window(
            Window(
                "w", ZoneId(0), good, Glazing(g.u_value, 2, 0.5), Vec3d(1, 0, 0)
            )
        )
    with assert_raises(contains="normal"):
        _ = model.add_window(Window("w", ZoneId(0), good, g, Vec3d(0, 0, 0)))


def test_check_sees_edits() raises:
    var model = _model()
    model.check()
    _ = model.add_surface(_surface(0, EXTERIOR, None))
    _ = model.add_window(
        Window(
            "w",
            ZoneId(0),
            Area64(2, SQUARE_METER),
            double_glazing(),
            Vec3d(0, -1, 0),
        )
    )
    model.check()
    model.windows[0].area = Area64(-1, SQUARE_METER)
    with assert_raises(contains="window area"):
        model.check()
    model.windows[0].area = Area64(1, SQUARE_METER)
    model.surfaces[0].area = Area64(-1, SQUARE_METER)
    with assert_raises(contains="surface area"):
        model.check()
    model.surfaces[0].area = Area64(1, SQUARE_METER)
    model.zones[0].heating_setpoint = Temperature64(30, CELSIUS)
    with assert_raises(contains="above cooling"):
        model.check()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
