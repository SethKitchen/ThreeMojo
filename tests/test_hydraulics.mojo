# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the pipe networks of `extensions.hydraulics`.

The references are the closed forms of each head loss formula, from
Rossman, "EPANET 2 Users Manual", EPA/600/R-00/057, 2000, table 3.1, and
the node and loop equations of a network, which have one solution. The
friction factor of rough turbulent flow is checked against the
Colebrook-White equation, which the test solves by iteration.
"""

from std.math import inf, log10, nan, pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.hydraulics.headloss import (
    GRAVITY,
    Roughness,
    chezy_manning,
    darcy_weisbach,
    friction_factor,
    hazen_williams,
    pipe_head_loss,
)
from extensions.hydraulics.kinds import (
    CHEZY_MANNING,
    DARCY_WEISBACH,
    HAZEN_WILLIAMS,
    HeadLossFormula,
    JUNCTION,
    KinematicViscosity64,
    LinkId,
    LinkKind,
    NodeId,
    NodeKind,
    PIPE,
    PUMP,
    RESERVOIR,
    SQUARE_METER_PER_SECOND,
)
from extensions.hydraulics.network import PipeNetwork, WATER_VISCOSITY
from extensions.hydraulics.solve import (
    SolveOptions,
    default_options,
    link_head_loss,
    solve_network,
)
from units.si import (
    CUBIC_METER_PER_SECOND,
    Length64,
    METER,
    METER_PER_SECOND,
    MILLIMETER,
    VolumeFlowRate64,
)


def _m(v: Float64) -> Length64:
    return Length64(v, METER)


def _q(v: Float64) -> VolumeFlowRate64:
    return VolumeFlowRate64(v, CUBIC_METER_PER_SECOND)


def test_kinds() raises:
    assert_true(NodeId(0).is_valid())
    assert_false(NodeId(-1).is_valid())
    assert_true(LinkId(3).is_valid())
    assert_false(LinkId(-1).is_valid())
    assert_true(JUNCTION.is_valid())
    assert_true(RESERVOIR.is_valid())
    assert_false(NodeKind(2).is_valid())
    assert_true(PIPE.is_valid())
    assert_true(PUMP.is_valid())
    assert_false(LinkKind(-1).is_valid())
    assert_true(HAZEN_WILLIAMS.is_valid())
    assert_true(CHEZY_MANNING.is_valid())
    assert_false(HeadLossFormula(3).is_valid())
    assert_true(hazen_williams(130).is_valid())
    assert_false(hazen_williams(0).is_valid())
    assert_true(darcy_weisbach(_m(0)).is_valid())
    assert_false(darcy_weisbach(_m(-1e-3)).is_valid())
    assert_true(chezy_manning(0.012).is_valid())
    assert_false(chezy_manning(nan[DType.float64]()).is_valid())
    assert_false(Roughness(HeadLossFormula(7), 1).is_valid())


def _colebrook(reynolds: Float64, rough: Float64) -> Float64:
    """Solve 1 / sqrt(f) = -2 log10(ε / 3.7 d + 2.51 / (Re sqrt(f)))."""
    var f = 0.02
    for _ in range(60):
        var root = -2 * log10(rough / 3.7 + 2.51 / (reynolds * sqrt(f)))
        f = 1 / (root * root)
    return f


def test_friction_factor() raises:
    """The friction factor in its three ranges.

    Reference: 64 / Re in laminar flow. The Colebrook-White equation in
    turbulent flow, which the formula of Swamee and Jain meets within 3%
    for a relative roughness from 1e-6 to 1e-2 and a Reynolds number from
    5000 to 1e8. The cubic between them meets both at its ends.
    """
    assert_almost_equal(friction_factor(1000, 0.01), 0.064, atol=1e-15)
    var roughs = [1e-6, 1e-4, 1e-2]
    var reynolds = [5e3, 1e5, 1e8]
    for i in range(3):
        for j in range(3):
            var got = friction_factor(reynolds[j], roughs[i])
            var exact = _colebrook(reynolds[j], roughs[i])
            assert_true(abs(got / exact - 1) < 0.03, String(got, " ", exact))
    for i in range(3):
        var below = friction_factor(2000 - 1e-9, roughs[i])
        var at_low = friction_factor(2000, roughs[i])
        var at_high = friction_factor(4000 - 1e-9, roughs[i])
        var above = friction_factor(4000, roughs[i])
        assert_almost_equal(at_low, below, atol=1e-9)
        assert_almost_equal(at_high, above, atol=1e-9)
        # The factor rises through the critical zone.
        assert_true(friction_factor(3000, roughs[i]) > at_low)


def _one_pipe(
    roughness: Roughness, minor: Float64, demand: Float64
) raises -> Float64:
    """Return the head at the end of a 1000 m pipe of 300 mm from 50 m."""
    var network = PipeNetwork()
    var source = network.add_reservoir(_m(50))
    var end = network.add_junction(_m(10), _q(demand))
    var pipe = network.add_pipe(
        source, end, _m(1000), _m(0.3), roughness, minor
    )
    var result = solve_network(network, default_options())
    assert_almost_equal(
        result.flow(pipe).to(CUBIC_METER_PER_SECOND), demand, atol=1e-12
    )
    var area = pi * 0.09 / 4
    assert_almost_equal(
        result.velocity(pipe).to(METER_PER_SECOND), demand / area, atol=1e-10
    )
    var head = result.head(end).to(METER)
    assert_almost_equal(
        result.pressure_head(end).to(METER), head - 10, atol=1e-12
    )
    assert_almost_equal(result.pressure_head(source).to(METER), 50.0, atol=0)
    assert_almost_equal(
        link_head_loss(network, pipe, _q(demand)).to(METER),
        50 - head,
        atol=1e-9,
    )
    return head


def test_one_pipe_with_each_formula() raises:
    """A reservoir, one pipe and one junction with a demand of 0.1 m³/s.

    Reference: the head falls by the head loss of the demand.
    Hazen-Williams: 10.67 L q^1.852 / (C^1.852 d^4.8704). Chezy-Manning:
    n² L v² / (d / 4)^(4/3). Darcy-Weisbach: f (L / d) v² / (2 g), with f
    from Swamee and Jain. A minor loss adds K v² / (2 g).
    """
    var q = 0.1
    var v = q / (pi * 0.09 / 4)
    var hw = 10.67 * 1000 * q**1.852 / (120.0**1.852 * 0.3**4.8704)
    assert_almost_equal(
        _one_pipe(hazen_williams(120), 0, q), 50 - hw, atol=1e-9
    )
    var cm = 0.013 * 0.013 * 1000 * v * v / 0.075 ** (4.0 / 3.0)
    assert_almost_equal(
        _one_pipe(chezy_manning(0.013), 0, q), 50 - cm, atol=1e-9
    )
    var reynolds = v * 0.3 / WATER_VISCOSITY
    var root = log10(0.00026 / 0.3 / 3.7 + 5.74 / reynolds**0.9)
    var f = 0.25 / (root * root)
    var dw = f * (1000 / 0.3) * v * v / (2 * GRAVITY)
    var rough = darcy_weisbach(Length64(0.26, MILLIMETER))
    assert_almost_equal(_one_pipe(rough, 0, q), 50 - dw, atol=1e-5 * dw)
    var fitting = 2.5 * v * v / (2 * GRAVITY)
    assert_almost_equal(
        _one_pipe(hazen_williams(120), 2.5, q), 50 - hw - fitting, atol=1e-9
    )
    # A flow toward the reservoir raises the head by the same loss.
    assert_almost_equal(
        _one_pipe(hazen_williams(120), 0, -q), 50 + hw, atol=1e-9
    )


def test_laminar_pipe() raises:
    """A slow flow of a thick oil.

    Reference: Hagen and Poiseuille, h = 128 ν L q / (π g d⁴). The loss
    is linear, so the solution is exact after the first iteration.
    """
    var network = PipeNetwork()
    network.set_viscosity(KinematicViscosity64(1e-4, SQUARE_METER_PER_SECOND))
    var source = network.add_reservoir(_m(20))
    var end = network.add_junction(_m(0), _q(0.001))
    _ = network.add_pipe(
        source, end, _m(500), _m(0.2), darcy_weisbach(_m(0)), 0
    )
    var result = solve_network(network, default_options())
    var loss = 128 * 1e-4 * 500 * 0.001 / (pi * GRAVITY * 0.2**4)
    assert_almost_equal(result.head(end).to(METER), 20 - loss, atol=1e-12)
    assert_true(result.iterations <= 3)
    # A fitting adds its loss to the laminar friction.
    var value = pipe_head_loss(0.001, 500, 0.2, darcy_weisbach(_m(0)), 4, 1e-4)
    var v = 0.001 / (pi * 0.04 / 4)
    assert_almost_equal(
        value.loss, loss + 4 * v * v / (2 * GRAVITY), atol=1e-12
    )


def test_parallel_pipes_share_the_flow() raises:
    """Two pipes of the same size and length, with C of 100 and 140.

    Reference: both lose the same head, so their flows are in the ratio
    of the coefficients, 100 to 140, and add to the demand.
    """
    var network = PipeNetwork()
    var source = network.add_reservoir(_m(40))
    var end = network.add_junction(_m(0), _q(0.24))
    var old = network.add_pipe(
        source, end, _m(800), _m(0.25), hazen_williams(100), 0
    )
    var new = network.add_pipe(
        source, end, _m(800), _m(0.25), hazen_williams(140), 0
    )
    var result = solve_network(network, default_options())
    assert_almost_equal(
        result.flow(old).to(CUBIC_METER_PER_SECOND), 0.1, atol=1e-10
    )
    assert_almost_equal(
        result.flow(new).to(CUBIC_METER_PER_SECOND), 0.14, atol=1e-10
    )


def _looped() raises -> PipeNetwork:
    """Two reservoirs and four junctions in two loops, with seven pipes."""
    var network = PipeNetwork()
    var high = network.add_reservoir(_m(60))
    var low = network.add_reservoir(_m(52))
    var a = network.add_junction(_m(20), _q(0.03))
    var b = network.add_junction(_m(22), _q(0.05))
    var c = network.add_junction(_m(18), _q(0.04))
    var d = network.add_junction(_m(25), _q(0.02))
    _ = network.add_pipe(high, a, _m(600), _m(0.35), hazen_williams(120), 0)
    _ = network.add_pipe(a, b, _m(400), _m(0.25), hazen_williams(110), 1)
    _ = network.add_pipe(a, c, _m(500), _m(0.25), chezy_manning(0.012), 0)
    _ = network.add_pipe(
        b, d, _m(450), _m(0.2), darcy_weisbach(Length64(0.1, MILLIMETER)), 0
    )
    _ = network.add_pipe(c, d, _m(350), _m(0.2), hazen_williams(100), 0.5)
    _ = network.add_pipe(b, c, _m(300), _m(0.15), hazen_williams(130), 0)
    _ = network.add_pipe(low, d, _m(700), _m(0.3), hazen_williams(120), 0)
    return network^


def test_looped_network_meets_its_equations() raises:
    """A network of two loops and two reservoirs, with all three formulas.

    Reference: the node and link equations, which have one solution. The
    flows into each junction, less the flows out, equal its demand within
    1e-12 m³/s. The head difference of each pipe is the head loss of its
    flow within 1e-8 m. The reservoirs supply the sum of the demands.
    """
    var network = _looped()
    var result = solve_network(network, default_options())
    var net = List[Float64](length=6, fill=0)
    for l in range(7):
        ref link = network.links[l]
        var q = result.flows[l]
        net[link.start.value] -= q
        net[link.end.value] += q
        var drop = result.heads[link.start.value] - result.heads[link.end.value]
        var loss = link_head_loss(network, LinkId(l), _q(q)).to(METER)
        assert_almost_equal(drop, loss, atol=1e-8)
    for n in range(2, 6):
        assert_almost_equal(net[n], network.demands[n], atol=1e-12)
    assert_almost_equal(net[0] + net[1], -0.14, atol=1e-12)
    # The higher reservoir gives more, and every junction has pressure.
    assert_true(result.flows[0] > result.flows[6])
    for n in range(2, 6):
        assert_true(result.pressure_head(NodeId(n)).to(METER) > 20)
    # EPANET's accuracy of 0.001 stops sooner and is close.
    var quick = solve_network(network, SolveOptions(1e-3, 40))
    assert_true(quick.iterations < result.iterations)
    assert_almost_equal(quick.heads[3], result.heads[3], atol=1e-3)


def test_pump_operating_point() raises:
    """A pump lifts water 30 m through a pipe to a second reservoir.

    Reference: the flow at which the pump head (4/3) h₀ - (1/3) h₀
    (q / q₀)² equals the lift plus the pipe loss, found by bisection.
    """
    var network = PipeNetwork()
    var low = network.add_reservoir(_m(5))
    var middle = network.add_junction(_m(5), _q(0))
    var high = network.add_reservoir(_m(35))
    var pump = network.add_pump(low, middle, _q(0.05), _m(40))
    var pipe = network.add_pipe(
        middle, high, _m(900), _m(0.2), hazen_williams(120), 0
    )
    var result = solve_network(network, default_options())
    var r = 10.67 * 900 / (120.0**1.852 * 0.2**4.8704)
    var lo = 0.0
    var hi = 0.1
    for _ in range(200):
        var mid = 0.5 * (lo + hi)
        var surplus = (
            160.0 / 3 - 40.0 / 3 * (mid / 0.05) ** 2 - 30 - r * mid**1.852
        )
        if surplus > 0:
            lo = mid
        else:
            hi = mid
    var got = result.flow(pump).to(CUBIC_METER_PER_SECOND)
    assert_almost_equal(got, lo, atol=1e-10)
    assert_almost_equal(
        result.flow(pipe).to(CUBIC_METER_PER_SECOND), lo, atol=1e-10
    )
    assert_almost_equal(
        result.head(middle).to(METER), 35 + r * lo**1.852, atol=1e-8
    )
    # The pump adds head, so its head loss is negative.
    assert_true(link_head_loss(network, pump, _q(got)).to(METER) < -30)
    with assert_raises(contains="no velocity"):
        _ = result.velocity(pump)


def test_network_at_rest() raises:
    """A network with no demand has no flow and the head of its reservoir."""
    var network = PipeNetwork()
    var source = network.add_reservoir(_m(12))
    var a = network.add_junction(_m(0), _q(0))
    var b = network.add_junction(_m(3), _q(0))
    _ = network.add_pipe(source, a, _m(100), _m(0.1), hazen_williams(100), 0)
    _ = network.add_pipe(a, b, _m(100), _m(0.1), chezy_manning(0.012), 0)
    var result = solve_network(network, SolveOptions(1e-12, 500))
    assert_almost_equal(result.head(b).to(METER), 12.0, atol=1e-9)
    assert_almost_equal(result.flows[1], 0.0, atol=1e-12)


def test_pipe_between_two_reservoirs() raises:
    """A pipe from a reservoir at 30 m to one at 22 m, and a lone reservoir.

    Reference: the flow whose Hazen-Williams loss is the 8 m between the
    two heads, q = (8 / r)^(1 / 1.852).
    """
    var network = PipeNetwork()
    var high = network.add_reservoir(_m(30))
    var low = network.add_reservoir(_m(22))
    var pipe = network.add_pipe(
        high, low, _m(500), _m(0.2), hazen_williams(110), 0
    )
    var result = solve_network(network, default_options())
    var r = 10.67 * 500 / (110.0**1.852 * 0.2**4.8704)
    assert_almost_equal(
        result.flow(pipe).to(CUBIC_METER_PER_SECOND),
        (8 / r) ** (1 / 1.852),
        atol=1e-10,
    )
    var alone = PipeNetwork()
    var lake = alone.add_reservoir(_m(7))
    var still = solve_network(alone, default_options())
    assert_almost_equal(still.head(lake).to(METER), 7.0, atol=0)
    assert_equal(len(still.flows), 0)


def test_network_refusals() raises:
    var bad = nan[DType.float64]()
    var network = PipeNetwork()
    with assert_raises(contains="elevation"):
        _ = network.add_junction(_m(bad), _q(0))
    with assert_raises(contains="demand"):
        _ = network.add_junction(_m(0), _q(inf[DType.float64]()))
    with assert_raises(contains="reservoir head"):
        _ = network.add_reservoir(_m(bad))
    with assert_raises(contains="viscosity"):
        network.set_viscosity(KinematicViscosity64(0, SQUARE_METER_PER_SECOND))
    var a = network.add_junction(_m(0), _q(0.01))
    var b = network.add_junction(_m(0), _q(0.01))
    var c = hazen_williams(100)
    with assert_raises(contains="node id"):
        _ = network.add_pipe(NodeId(-1), b, _m(1), _m(1), c, 0)
    with assert_raises(contains="node id"):
        _ = network.add_pipe(a, NodeId(2), _m(1), _m(1), c, 0)
    with assert_raises(contains="two different"):
        _ = network.add_pipe(a, a, _m(1), _m(1), c, 0)
    with assert_raises(contains="pipe length"):
        _ = network.add_pipe(a, b, _m(0), _m(1), c, 0)
    with assert_raises(contains="pipe diameter"):
        _ = network.add_pipe(a, b, _m(1), _m(-1), c, 0)
    with assert_raises(contains="roughness"):
        _ = network.add_pipe(a, b, _m(1), _m(1), hazen_williams(-5), 0)
    with assert_raises(contains="minor loss"):
        _ = network.add_pipe(a, b, _m(1), _m(1), c, -1)
    with assert_raises(contains="minor loss"):
        _ = network.add_pipe(a, b, _m(1), _m(1), c, inf[DType.float64]())
    with assert_raises(contains="design flow"):
        _ = network.add_pump(a, b, _q(0), _m(10))
    with assert_raises(contains="design head"):
        _ = network.add_pump(a, b, _q(1), _m(0))
    with assert_raises(contains="two different"):
        _ = network.add_pump(b, b, _q(1), _m(1))
    var pipe = network.add_pipe(a, b, _m(100), _m(0.2), c, 0)
    with assert_raises(contains="needs a reservoir"):
        _ = solve_network(network, default_options())
    with assert_raises(contains="needs a reservoir"):
        _ = solve_network(PipeNetwork(), default_options())
    var source = network.add_reservoir(_m(30))
    with assert_raises(contains="no path"):
        _ = solve_network(network, default_options())
    _ = network.add_pipe(source, a, _m(100), _m(0.2), c, 0)
    with assert_raises(contains="did not converge"):
        _ = solve_network(network, SolveOptions(1e-14, 1))
    var result = solve_network(network, default_options())
    with assert_raises(contains="node id"):
        _ = result.head(NodeId(3))
    with assert_raises(contains="node id"):
        _ = result.pressure_head(NodeId(-1))
    with assert_raises(contains="link id"):
        _ = result.flow(LinkId(2))
    with assert_raises(contains="link id"):
        _ = result.velocity(LinkId(-1))
    with assert_raises(contains="link id"):
        _ = link_head_loss(network, LinkId(5), _q(0))
    with assert_raises(contains="link id"):
        network.check_link(LinkId(-1))
    network.check_link(pipe)
    with assert_raises(contains="tolerance"):
        _ = SolveOptions(0, 5)
    with assert_raises(contains="iteration budget"):
        _ = SolveOptions(1e-6, 0)


def test_pump_that_cannot_lift_is_refused() raises:
    """A pump with a shutoff head of 8 m against a lift of 30 m."""
    var network = PipeNetwork()
    var low = network.add_reservoir(_m(0))
    var middle = network.add_junction(_m(0), _q(0))
    var high = network.add_reservoir(_m(30))
    _ = network.add_pump(low, middle, _q(0.05), _m(6))
    _ = network.add_pipe(middle, high, _m(100), _m(0.3), hazen_williams(120), 0)
    with assert_raises(contains="runs backward"):
        _ = solve_network(network, default_options())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
