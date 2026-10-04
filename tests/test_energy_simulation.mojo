# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.energy.simulation`.

The references are closed forms:

- Steady state: the heating load of a zone is sum(U A dT) + rho c_p V n dT,
  with U from `Construction.u_value` (ISO 6946) and the infiltration term
  of the ASHRAE Handbook of Fundamentals chapter 16.
- A lumped capacitance cools as T - T_out = (T_0 - T_out) exp(-t / tau)
  with tau = C / (U A) (Incropera section 5.2); backward Euler gives
  (1 + dt / tau)^-n exactly.
- Two zones in series reach the steady temperature of a conductance
  divider.
"""

from std.math import exp, inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.building.construction import (
    Construction,
    DOWNWARD_FLOW,
    Glazing,
    HORIZONTAL_FLOW,
    Layer,
    UPWARD_FLOW,
    double_glazing,
)
from extensions.building.ids import ConstructionId, MaterialId
from extensions.building.kinds import OFFICE
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
)
from extensions.building.model import Site
from extensions.energy.ids import EXTERIOR, GROUND, INTERZONE, ZoneId
from extensions.energy.simulation import (
    SimulationOptions,
    default_options,
    ideal_loads,
    simulate,
)
from extensions.energy.weather import (
    Weather,
    WeatherLocation,
    WeatherRecord,
    design_day,
)
from extensions.energy.zone import (
    AIR_CHANGE_PER_HOUR,
    InternalGains,
    Surface,
    Window,
    Zone,
    ZoneModel,
    interior_film,
    outside_film_coefficient,
    typical_gains,
)
from extensions.numerics.dense import DenseMatrix
from generators.utils import Vec3d
from units.si import (
    Angle64,
    Area64,
    DEGREE,
    DEGREE64,
    Duration64,
    Frequency64,
    HOUR,
    HeatCapacity64,
    HeatFlux64,
    JOULE_PER_KELVIN,
    KILOWATT_HOUR,
    Length64,
    METER,
    METER_PER_SECOND,
    PASCAL,
    Pressure64,
    SQUARE_METER,
    Velocity64,
    Volume64,
)
from units.temperature import CELSIUS, KELVIN, Temperature64

comptime _RHO_CP = 1.204 * 1006.0


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _area(v: Float64) -> Area64:
    return Area64(v, SQUARE_METER)


def _site() -> Site:
    return Site(
        Angle64(40, DEGREE64), Angle64(-105, DEGREE64), _m(1600), Angle64(0)
    )


def _location() -> WeatherLocation:
    return WeatherLocation(
        "Golden",
        Angle64(39.74, DEGREE64),
        Angle64(-105.18, DEGREE64),
        Duration64(-7, HOUR),
        _m(1829),
    )


def _materials() -> List[BuildingMaterial]:
    var out = List[BuildingMaterial]()
    out.append(brick())
    out.append(mineral_wool())
    out.append(gypsum_board())
    out.append(concrete())
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
    out.append(
        Construction(
            "roof",
            [Layer(MaterialId(1), _m(0.15)), Layer(MaterialId(3), _m(0.2))],
        )
    )
    out.append(
        Construction(
            "ground",
            [Layer(MaterialId(1), _m(0.1)), Layer(MaterialId(3), _m(0.15))],
        )
    )
    out.append(
        Construction(
            "partition",
            [
                Layer(MaterialId(2), _m(0.0125)),
                Layer(MaterialId(1), _m(0.05)),
                Layer(MaterialId(2), _m(0.0125)),
            ],
        )
    )
    return out^


def _no_gains() -> InternalGains:
    return InternalGains(HeatFlux64(0), HeatFlux64(0), HeatFlux64(0))


def _zone(var name: String, heat: Temperature64, cool: Temperature64) -> Zone:
    return Zone(
        name^,
        OFFICE,
        Volume64(60),
        _area(20),
        Frequency64(0.5, AIR_CHANGE_PER_HOUR),
        _no_gains(),
        heat,
        cool,
        HeatCapacity64(0),
    )


def _surface(
    construction: Int,
    boundary: Int,
    inside: Int,
    outside: Optional[ZoneId],
    area: Float64,
    normal: Vec3d,
) raises -> Surface:
    var kinds = [EXTERIOR, INTERZONE, GROUND]
    var outside_film = outside_film_coefficient()
    if outside:
        outside_film = interior_film(normal * -1.0)
    return Surface(
        String("surface ", construction),
        ConstructionId(construction),
        kinds[boundary],
        ZoneId(inside),
        outside,
        _area(area),
        normal,
        interior_film(normal),
        outside_film,
    )


def _record(hour: Float64, celsius: Float64, wind: Float64) -> WeatherRecord:
    var zero = HeatFlux64(0)
    return WeatherRecord(
        1,
        15,
        Duration64(hour, HOUR),
        Temperature64(celsius, CELSIUS),
        Temperature64(celsius - 5, CELSIUS),
        70,
        Pressure64(101325, PASCAL),
        zero,
        zero,
        zero,
        Angle64(0),
        Velocity64(wind, METER_PER_SECOND),
    )


def _constant_weather(celsius: Float64, wind: Float64) -> Weather:
    var records = List[WeatherRecord]()
    for h in range(24):
        records.append(_record(Float64(h + 1), celsius, wind))
    return Weather(_location(), Duration64(1, HOUR), records^)


def _box(heat: Temperature64) raises -> ZoneModel:
    # A 5 m by 4 m by 3 m room with a 3 m² south window.
    var model = ZoneModel(_site(), _materials(), _constructions())
    _ = model.add_zone(_zone("box", heat, Temperature64(400, KELVIN)))
    _ = model.add_surface(_surface(0, 0, 0, None, 12, Vec3d(0, -1, 0)))
    _ = model.add_surface(_surface(0, 0, 0, None, 15, Vec3d(0, 1, 0)))
    _ = model.add_surface(_surface(0, 0, 0, None, 12, Vec3d(1, 0, 0)))
    _ = model.add_surface(_surface(0, 0, 0, None, 12, Vec3d(-1, 0, 0)))
    _ = model.add_surface(_surface(1, 0, 0, None, 20, Vec3d(0, 0, 1)))
    _ = model.add_surface(_surface(2, 2, 0, None, 20, Vec3d(0, 0, -1)))
    _ = model.add_window(
        Window("south", ZoneId(0), _area(3), double_glazing(), Vec3d(0, -1, 0))
    )
    return model^


def _steady_load(
    model: ZoneModel, inside: Float64, outdoor: Float64, ground: Float64
) raises -> Float64:
    var materials = _materials()
    var c = _constructions()
    var wall = c[0].u_value(materials, HORIZONTAL_FLOW).value
    var roof = c[1].u_value(materials, UPWARD_FLOW).value
    var slab = c[2].u_value(materials, DOWNWARD_FLOW).value
    var dt = inside - outdoor
    return (
        wall * (12 + 15 + 12 + 12) * dt
        + roof * 20 * dt
        + slab * 20 * (inside - ground)
        + 1.6 * 3 * dt
        + _RHO_CP * 60 * 0.5 / 3600 * dt
    )


def test_steady_state_load_is_ua_dt() raises:
    """The heating load at steady state is sum(U A dT) + rho c_p V n dT, and
    each surface's U equals `Construction.u_value` for its flow direction."""
    var model = _box(Temperature64(20, CELSIUS))
    var materials = _materials()
    var c = _constructions()
    var directions = [
        HORIZONTAL_FLOW,
        HORIZONTAL_FLOW,
        HORIZONTAL_FLOW,
        HORIZONTAL_FLOW,
        UPWARD_FLOW,
        DOWNWARD_FLOW,
    ]
    for i in range(6):
        ref s = model.surfaces[i]
        assert_almost_equal(
            model.surface_u_value(model.surfaces_of(ZoneId(0))[i]).value,
            c[s.construction.value].u_value(materials, directions[i]).value,
            atol=1e-12,
        )
    var options = default_options()
    options.warmup_days = 10
    var result = simulate(model, _constant_weather(-10, 3), options)
    var expected = _steady_load(model, 20, -10, 10)
    var last = result.step_count() - 1
    assert_equal(result.step_count(), 24)
    assert_almost_equal(
        result.heating(last, ZoneId(0)).value, expected, atol=1e-6 * expected
    )
    assert_almost_equal(
        result.air_temperature(last, ZoneId(0)).to(CELSIUS), 20, atol=1e-9
    )
    assert_equal(result.cooling(last, ZoneId(0)).value, 0)
    # A day of the steady load.
    assert_almost_equal(
        result.heating_energy(ZoneId(0)).value,
        expected * 86400,
        atol=1e-5 * expected * 86400,
    )
    assert_almost_equal(
        result.total_heating_energy().to(KILOWATT_HOUR),
        result.heating_energy(ZoneId(0)).to(KILOWATT_HOUR),
        atol=1e-9,
    )
    assert_equal(result.total_cooling_energy().value, 0)
    assert_equal(result.cooling_energy(ZoneId(0)).value, 0)
    # Substeps change the step, not the steady answer.
    options.substeps = 4
    var fine = simulate(model, _constant_weather(-10, 3), options)
    assert_equal(fine.step_count(), 96)
    assert_almost_equal(
        fine.heating(95, ZoneId(0)).value, expected, atol=1e-6 * expected
    )


def test_steady_gains_lower_the_load() raises:
    """With the air held at its setpoint, a gain lowers the load by itself:
    25 W/m² of office gains on 20 m² during working hours."""
    var model = _box(Temperature64(20, CELSIUS))
    model.zones[0].gains = typical_gains(OFFICE)
    var options = default_options()
    options.warmup_days = 10
    var result = simulate(model, _constant_weather(-10, 3), options)
    var expected = _steady_load(model, 20, -10, 10)
    # The record ending 13:00 is at work; the one ending 03:00 is not.
    assert_almost_equal(
        result.heating(12, ZoneId(0)).value,
        expected - 500,
        atol=1e-5 * expected,
    )
    assert_almost_equal(
        result.heating(2, ZoneId(0)).value, expected - 50, atol=1e-5 * expected
    )


def test_lumped_capacitance_cools_exponentially() raises:
    """A zone with no wall mass, C = 5e5 J/K plus its air and U A = 16 W/K
    through a window, starts at 20 degrees Celsius with heating off in
    0 degree weather. Backward Euler gives (1 + dt/tau)^-n exactly, and
    it is within 0.3% of exp(-t/tau) at dt = 60 s."""
    var model = ZoneModel(_site(), _materials(), _constructions())
    var zone = _zone(
        "lump", Temperature64(0, KELVIN), Temperature64(1000, KELVIN)
    )
    zone.infiltration = Frequency64(0)
    zone.volume = Volume64(100)
    zone.furniture = HeatCapacity64(5e5, JOULE_PER_KELVIN)
    _ = model.add_zone(zone^)
    _ = model.add_window(
        Window(
            "w",
            ZoneId(0),
            _area(10),
            Glazing(double_glazing().u_value, 0, 0.7),
            Vec3d(0, -1, 0),
        )
    )
    var options = default_options()
    options.warmup_days = 0
    options.substeps = 60
    var result = simulate(model, _constant_weather(0, 3), options)
    var c = 5e5 + _RHO_CP * 100
    var tau = c / 16
    var dt = 60.0
    for n in [60, 600, 1440]:
        var t = result.air_temperature(n - 1, ZoneId(0)).to(CELSIUS)
        var discrete = 20 / (1 + dt / tau) ** Float64(n)
        assert_almost_equal(t, discrete, atol=1e-9)
        var exact = 20 * exp(-dt * Float64(n) / tau)
        assert_true(abs(t - exact) < 0.003 * exact)
    assert_equal(result.total_heating_energy().value, 0)


def test_two_zones_in_series() raises:
    """Zone A, heated to 20 degrees Celsius, and unheated zone B share a
    partition, and each has an exterior wall. At steady state B sits at
    (K_p T_A + K_e T_out) / (K_p + K_e), with K the U A of each path and
    B's leakage, and A's load is its losses plus the partition flow."""
    var model = ZoneModel(_site(), _materials(), _constructions())
    var off = Temperature64(0, KELVIN)
    var never = Temperature64(1000, KELVIN)
    var a = _zone("A", Temperature64(20, CELSIUS), never)
    a.infiltration = Frequency64(0)
    var b = _zone("B", off, never)
    _ = model.add_zone(a^)
    _ = model.add_zone(b^)
    _ = model.add_surface(_surface(0, 0, 0, None, 10, Vec3d(0, -1, 0)))
    _ = model.add_surface(_surface(0, 0, 1, None, 10, Vec3d(0, 1, 0)))
    var partition = model.add_surface(
        _surface(3, 1, 0, ZoneId(1), 12, Vec3d(1, 0, 0))
    )
    # A partition inside zone A on both faces stores heat and passes none.
    _ = model.add_surface(_surface(3, 1, 0, ZoneId(0), 8, Vec3d(0, 1, 0)))
    var options = default_options()
    options.warmup_days = 15
    var result = simulate(model, _constant_weather(0, 3), options)
    var u_wall = model.surface_u_value(model.surfaces_of(ZoneId(0))[0]).value
    var u_part = model.surface_u_value(partition).value
    var k_p = u_part * 12
    var k_e = u_wall * 10 + _RHO_CP * 60 * 0.5 / 3600
    var t_b = k_p * 20 / (k_p + k_e)
    var last = result.step_count() - 1
    assert_almost_equal(
        result.air_temperature(last, ZoneId(1)).to(CELSIUS), t_b, atol=1e-6
    )
    var load = u_wall * 10 * 20 + k_p * (20 - t_b)
    assert_almost_equal(
        result.heating(last, ZoneId(0)).value, load, atol=1e-6 * load
    )
    assert_equal(result.heating(last, ZoneId(1)).value, 0)


def test_ideal_loads_release_a_held_zone() raises:
    """Zone A (gain 90 W, 1 W/K outside) and zone B (10 W/K outside) couple
    by 10 W/K, with 0 outside. Free, both fall below a 20 setpoint. Held
    together, A needs -70 W, so the loop frees A, which settles at
    (90 + 200) / 11 = 26.36. The mirror case with a sink and cooling
    frees A the same way."""
    var m = DenseMatrix(2, 2)
    m.set(0, 0, 11)
    m.set(0, 1, -10)
    m.set(1, 0, -10)
    m.set(1, 1, 20)
    var heat: List[Float64] = [20, 20]
    var cool: List[Float64] = [30, 30]
    var solved = ideal_loads(m, [90.0, 0.0], heat, cool)
    assert_almost_equal(solved[0][0], 290.0 / 11, atol=1e-12)
    assert_almost_equal(solved[0][1], 20, atol=1e-12)
    assert_equal(solved[1][0], 0)
    assert_almost_equal(solved[1][1], 20 * 20 - 10 * 290.0 / 11, atol=1e-9)
    var low: List[Float64] = [-100, -100]
    var high: List[Float64] = [-20, -20]
    var mirror = ideal_loads(m, [-90.0, 0.0], low, high)
    assert_almost_equal(mirror[0][0], -290.0 / 11, atol=1e-12)
    assert_almost_equal(mirror[0][1], -20, atol=1e-12)
    assert_equal(mirror[1][0], 0)
    assert_true(mirror[1][1] < 0)
    var free = ideal_loads(m, [0.0, 0.0], low, cool)
    assert_equal(free[0][0], 0)
    var none = ideal_loads(
        DenseMatrix(0, 0), List[Float64](), List[Float64](), List[Float64]()
    )
    assert_equal(len(none[0]), 0)
    with assert_raises(contains="one row"):
        _ = ideal_loads(DenseMatrix(2, 3), [0.0, 0.0], heat, cool)
    with assert_raises(contains="one row"):
        _ = ideal_loads(m, [0.0], heat, cool)
    with assert_raises(contains="one row"):
        _ = ideal_loads(m, [0.0, 0.0], [1.0], cool)
    with assert_raises(contains="one row"):
        _ = ideal_loads(m, [0.0, 0.0], heat, [1.0])


def test_sun_wind_and_cooling() raises:
    """A July design day: the sun through a south window raises the cooling
    energy, and the wind-dependent film changes the result a little."""
    var weather = design_day(
        _location(),
        7,
        21,
        Temperature64(18, CELSIUS),
        Temperature64(33, CELSIUS),
        Temperature64(10, CELSIUS),
        Velocity64(4, METER_PER_SECOND),
        1.0,
        1,
    )
    var model = _box(Temperature64(20, CELSIUS))
    model.zones[0].cooling_setpoint = Temperature64(24, CELSIUS)
    var options = default_options()
    options.warmup_days = 3
    options.ground_temperature = Temperature64(15, CELSIUS)
    var sunny = simulate(model, weather, options)
    model.windows[0].glazing = Glazing(double_glazing().u_value, 0.0, 0.7)
    var shaded = simulate(model, weather, options)
    var cooling = sunny.total_cooling_energy().to(KILOWATT_HOUR)
    assert_true(cooling > shaded.total_cooling_energy().to(KILOWATT_HOUR) + 0.5)
    model.windows[0].glazing = double_glazing()
    options.wind_film = True
    var windy = simulate(model, weather, options)
    var a = windy.total_cooling_energy().value
    var b = sunny.total_cooling_energy().value
    assert_true(a != b and abs(a - b) < 0.2 * b)


def test_result_and_options_refuse() raises:
    var model = _box(Temperature64(20, CELSIUS))
    var weather = _constant_weather(0, 3)
    var options = default_options()
    options.warmup_days = 0
    var result = simulate(model, weather, options)
    with assert_raises(contains="step"):
        _ = result.air_temperature(24, ZoneId(0))
    with assert_raises(contains="step"):
        _ = result.heating(-1, ZoneId(0))
    with assert_raises(contains="zone id"):
        _ = result.cooling(0, ZoneId(1))
    with assert_raises(contains="zone id"):
        _ = result.heating_energy(ZoneId(-1))
    with assert_raises(contains="zone id"):
        _ = result.cooling_energy(ZoneId(1))
    var bad = List[SimulationOptions]()
    for _ in range(12):
        bad.append(default_options())
    bad[0].substeps = 0
    bad[1].substeps = 61
    bad[2].fourier = 0
    bad[3].fourier = inf[DType.float64]()
    bad[4].ground_temperature = Temperature64(-1, KELVIN)
    bad[5].initial_temperature = Temperature64(-1, KELVIN)
    bad[6].ground_reflectance = -0.1
    bad[7].solar_absorptance = 1.1
    bad[8].emissivity = 2
    bad[9].warmup_days = -1
    bad[10].warmup_days = 366
    bad[11].substeps = 1
    var messages: List[String] = [
        "Substeps",
        "Substeps",
        "Fourier",
        "Fourier",
        "temperature",
        "temperature",
        "reflectance",
        "reflectance",
        "reflectance",
        "Warm-up",
        "Warm-up",
    ]
    for i in range(11):
        with assert_raises(contains=messages[i]):
            _ = simulate(model, weather, bad[i])
    var empty = Weather(_location(), Duration64(1, HOUR), List[WeatherRecord]())
    with assert_raises(contains="weather record"):
        _ = simulate(model, empty, options)
    var slow = Weather(_location(), Duration64(2, HOUR), [_record(2, 0, 1)])
    with assert_raises(contains="weather step"):
        _ = simulate(model, slow, options)
    var still = Weather(_location(), Duration64(0), [_record(2, 0, 1)])
    with assert_raises(contains="weather step"):
        _ = simulate(model, still, options)
    var lost = _constant_weather(0, 3)
    lost.location.latitude = Angle64(-91, DEGREE64)
    with assert_raises(contains="latitude"):
        _ = simulate(model, lost, options)
    var odd = Weather(_location(), Duration64(1, HOUR), [_record(1, 0, 1)])
    odd.records[0].day = 40
    with assert_raises(contains="not in its month"):
        _ = simulate(model, odd, options)
    var nothing = ZoneModel(_site(), _materials(), _constructions())
    with assert_raises(contains="needs a zone"):
        _ = simulate(nothing, weather, options)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
