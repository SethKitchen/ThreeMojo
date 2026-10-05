# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.energy.conduction`.

The references are closed forms of Carslaw and Jaeger, "Conduction of Heat
in Solids", 2nd edition, 1959, and of Incropera, DeWitt, Bergman and
Lavine, "Fundamentals of Heat and Mass Transfer", 6th edition, 2007:
the error-function solution for a semi-infinite solid (Incropera eq.
5.57), the Fourier series for a plane slab (Carslaw and Jaeger section
3.3) and the steady series resistance of ISO 6946.
"""

from std.math import erf, exp, inf, nan, pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from extensions.building.construction import (
    Construction,
    HORIZONTAL_FLOW,
    Layer,
)
from extensions.building.ids import MaterialId
from extensions.building.material import (
    BuildingMaterial,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
)
from extensions.energy.conduction import (
    FaceCondition,
    LayeredWall,
    MAX_ELEMENTS_PER_LAYER,
)
from units.si import (
    Duration64,
    HeatFlux64,
    Length64,
    METER,
    SECOND,
    SQUARE_METER_KELVIN_PER_WATT,
    ThermalTransmittance64,
    WATT_PER_SQUARE_METER,
    WATT_PER_SQUARE_METER_KELVIN,
)
from units.temperature import CELSIUS, KELVIN, Temperature64

comptime _ALPHA = 2.3 / (2400.0 * 1000.0)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _materials() -> List[BuildingMaterial]:
    var out = List[BuildingMaterial]()
    out.append(brick())
    out.append(mineral_wool())
    out.append(gypsum_board())
    out.append(concrete())
    return out^


def _wall() -> Construction:
    return Construction(
        "wall",
        [
            Layer(MaterialId(0), _m(0.2)),
            Layer(MaterialId(1), _m(0.1)),
            Layer(MaterialId(2), _m(0.0125)),
        ],
    )


def _concrete(layers: Int, thickness: Float64) -> Construction:
    var list = List[Layer]()
    for _ in range(layers):
        list.append(Layer(MaterialId(3), _m(thickness)))
    return Construction("concrete", list^)


def _film(h: Float64) -> ThermalTransmittance64:
    return ThermalTransmittance64(h, WATT_PER_SQUARE_METER_KELVIN)


def _face(h: Float64, celsius: Float64) -> FaceCondition:
    return FaceCondition(
        _film(h), Temperature64(celsius, CELSIUS), HeatFlux64(0)
    )


def test_mesh_follows_the_fourier_criterion() raises:
    var materials = _materials()
    var dt = 3600.0
    var wall = LayeredWall(
        _concrete(1, 0.2),
        materials,
        Duration64(dt, SECOND),
        2.0,
        Temperature64(20, CELSIUS),
    )
    var largest = sqrt(_ALPHA * dt / 2.0)
    var count = Int(0.2 / largest) + 1
    assert_equal(wall.node_count(), count + 1)
    var dx = 0.2 / Float64(count)
    assert_true(_ALPHA * dt / (dx * dx) >= 2.0)
    assert_almost_equal(wall.node_depth(count).to(METER), 0.2, atol=1e-12)
    var total = 0.0
    for i in range(wall.node_count()):
        total += wall.capacity[i]
    assert_almost_equal(total, 2400 * 1000 * 0.2, atol=1e-6)
    # A very fine criterion stops at the cap.
    var fine = LayeredWall(
        _wall(),
        materials,
        Duration64(dt, SECOND),
        1e12,
        Temperature64(0, CELSIUS),
    )
    assert_equal(fine.node_count(), 3 * MAX_ELEMENTS_PER_LAYER + 1)
    # Every mesh has the layers' resistance.
    assert_almost_equal(
        fine.resistance().to(SQUARE_METER_KELVIN_PER_WATT),
        _wall().resistance(materials).to(SQUARE_METER_KELVIN_PER_WATT),
        atol=1e-12,
    )
    assert_almost_equal(fine.node_temperature(5).to(CELSIUS), 0, atol=1e-12)


def test_steady_state_matches_u_value() raises:
    """ISO 6946: the steady flux through a wall with films of 1/0.13 and
    25 W/(m² K) is U (T_in - T_out), with U from `Construction.u_value`."""
    var materials = _materials()
    var u = _wall().u_value(materials, HORIZONTAL_FLOW).value
    for fourier in [1e-9, 1e9]:
        var wall = LayeredWall(
            _wall(),
            materials,
            Duration64(1e8, SECOND),
            fourier,
            Temperature64(0, CELSIUS),
        )
        for _ in range(40):
            wall.advance(_face(25, -10), _face(1 / 0.13, 20))
        var inside = wall.inside_surface().to(CELSIUS)
        var outside = wall.outside_surface().to(CELSIUS)
        var flux = (20 - inside) / 0.13
        assert_almost_equal(flux, u * 30, atol=1e-9)
        assert_almost_equal((outside + 10) * 25, u * 30, atol=1e-9)
        # The brick-insulation interface lies on the line of resistances.
        var r_brick = 0.2 / 0.77
        var expected = -10 + u * 30 * (0.04 + r_brick)
        var k = 1
        while wall.depth[k] < 0.2 - 1e-12:
            k += 1
        assert_almost_equal(wall.temperature[k] - 273.15, expected, atol=1e-9)


def test_semi_infinite_step_against_error_function() raises:
    """Incropera eq. 5.57: a semi-infinite solid at T_i whose surface steps
    to T_s has T = T_s + (T_i - T_s) erf(x / (2 sqrt(alpha t))). A 1 m
    concrete block is semi-infinite for 6 hours: the far face sees less
    than 1e-5 of the step."""
    var materials = _materials()
    var dt = 60.0
    var wall = LayeredWall(
        _concrete(10, 0.1),
        materials,
        Duration64(dt, SECOND),
        2.0,
        Temperature64(0, CELSIUS),
    )
    var steps = 360
    for _ in range(steps):
        wall.advance(_face(1e9, 100), _face(0, 0))
    var t = dt * Float64(steps)
    var worst = 0.0
    for i in range(wall.node_count()):
        var x = wall.depth[i]
        if x > 0.4:
            break
        var exact = 100 * (1 - erf(x / (2 * sqrt(_ALPHA * t))))
        worst = max(worst, abs(wall.temperature[i] - 273.15 - exact))
    # Within 0.5% of the step everywhere in the heated depth.
    assert_true(worst < 0.5)
    assert_almost_equal(wall.inside_surface().to(CELSIUS), 0, atol=1e-3)


def _slab_exact(x: Float64, t: Float64, length: Float64) -> Float64:
    # A slab at 0 whose face x = 0 steps to 100 and whose face x = L stays
    # at 0: T = 100 (1 - x/L) - 100 sum 2/(n pi) sin(n pi x/L) exp(-n² pi²
    # alpha t / L²).
    var total = 100 * (1 - x / length)
    for n in range(1, 400):
        var k = Float64(n) * pi / length
        total -= (
            100 * 2 / (Float64(n) * pi) * sin(k * x) * exp(-k * k * _ALPHA * t)
        )
    return total


def test_slab_converges_with_refinement() raises:
    """Carslaw and Jaeger section 3.3: the plane slab with one face stepped.
    Halving the step at a fixed Fourier number roughly halves the error at
    the middle of the slab after 2 hours, the first order of backward
    Euler."""
    var materials = _materials()
    var errors = List[Float64]()
    var dt = 900.0
    for _ in range(4):
        var wall = LayeredWall(
            _concrete(1, 0.2),
            materials,
            Duration64(dt, SECOND),
            2.0,
            Temperature64(0, CELSIUS),
        )
        var steps = Int(7200.0 / dt + 0.5)
        for _ in range(steps):
            wall.advance(_face(1e10, 100), _face(1e10, 0))
        var middle = (wall.node_count() - 1) // 2
        var x = wall.depth[middle]
        var exact = _slab_exact(x, 7200.0, 0.2)
        errors.append(abs(wall.temperature[middle] - 273.15 - exact))
        dt /= 2
    for i in range(1, 4):
        var ratio = errors[i - 1] / errors[i]
        assert_true(ratio > 1.6 and ratio < 2.6)
    # About 2.0, 1.05, 0.53 and 0.27 K of a 100 K step.
    assert_true(errors[3] < 0.3)


def test_absorbed_flux_and_superposition() raises:
    var materials = _materials()
    var wall = LayeredWall(
        _wall(),
        materials,
        Duration64(600, SECOND),
        2.0,
        Temperature64(5, CELSIUS),
    )
    var sun = FaceCondition(
        _film(25),
        Temperature64(0, CELSIUS),
        HeatFlux64(300, WATT_PER_SQUARE_METER),
    )
    var inside = _face(7.7, 20)
    var whole = wall.solve(sun, inside, True)
    # The same step as the sum of the history part and a unit response.
    var known = wall.solve(sun, _face(7.7, -273.15), True)
    var unit = wall.solve(
        _face(25, -273.15),
        FaceCondition(_film(7.7), Temperature64(1, KELVIN), HeatFlux64(0)),
        False,
    )
    var n = wall.node_count()
    for i in range(n):
        assert_almost_equal(whole[i], known[i] + unit[i] * 293.15, atol=1e-9)
    wall.advance(sun, inside)
    assert_true(wall.outside_surface().to(CELSIUS) > 5)
    var heated = wall.temperature.copy()
    wall.set_temperatures(heated^)
    with assert_raises(contains="one temperature per node"):
        wall.set_temperatures([1.0, 2.0])


def test_wall_refuses() raises:
    var materials = _materials()
    var t = Temperature64(20, CELSIUS)
    var hour = Duration64(3600, SECOND)
    with assert_raises(contains="needs a layer"):
        _ = LayeredWall(
            Construction("none", List[Layer]()), materials, hour, 2, t
        )
    with assert_raises(contains="step"):
        _ = LayeredWall(_wall(), materials, Duration64(0), 2, t)
    with assert_raises(contains="step"):
        _ = LayeredWall(
            _wall(), materials, Duration64(inf[DType.float64]()), 2, t
        )
    with assert_raises(contains="Fourier"):
        _ = LayeredWall(_wall(), materials, hour, 0, t)
    with assert_raises(contains="Fourier"):
        _ = LayeredWall(_wall(), materials, hour, inf[DType.float64](), t)
    with assert_raises(contains="initial"):
        _ = LayeredWall(_wall(), materials, hour, 2, Temperature64(-1, KELVIN))
    var wall = LayeredWall(_wall(), materials, hour, 2, t)
    with assert_raises(contains="node"):
        _ = wall.node_depth(-1)
    with assert_raises(contains="node"):
        _ = wall.node_temperature(wall.node_count())
    var ok = _face(10, 0)
    var big = inf[DType.float64]()
    with assert_raises(contains="film"):
        _ = wall.solve(_face(-1, 0), ok, True)
    with assert_raises(contains="film"):
        _ = wall.solve(ok, _face(-1, 0), True)
    with assert_raises(contains="film"):
        _ = wall.solve(_face(big, 0), ok, True)
    with assert_raises(contains="film"):
        _ = wall.solve(ok, _face(big, 0), True)
    with assert_raises(contains="finite"):
        _ = wall.solve(ok, _face(10, nan[DType.float64]()), True)
    with assert_raises(contains="finite"):
        wall.advance(
            FaceCondition(
                _film(10), Temperature64(0, CELSIUS), HeatFlux64(big)
            ),
            ok,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
