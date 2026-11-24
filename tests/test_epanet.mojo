# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The EPANET project interface: its checks, its units and its kinds.

`test_epanet_reference.mojo` and `test_epanet_cases.mojo` compare the
results with the real EPANET. This suite checks what they cannot: the
order of the toolkit calls, the ranges of the indexes, the SI results,
and two input lines that make EPANET 2.3.6 read past the end of a line.
"""

from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from extensions.epanet.input import error_text
from extensions.epanet.kinds import (
    AGE,
    CHEM,
    ControlType,
    CurveType,
    DemandModel,
    EN_DEMAND,
    EN_FLOW,
    EN_HEAD,
    EN_LINKQUAL,
    EN_PRESSURE,
    EN_QUALITY,
    FlowDirection,
    FlowUnits,
    HeadLossType,
    LinkIndex,
    LinkProperty,
    LinkType,
    MixType,
    NodeIndex,
    NodeProperty,
    NodeType,
    PressureUnits,
    PumpType,
    QualityType,
    SourceType,
    StatusType,
    UnitSystem,
)
from extensions.epanet.project import EpanetProject
from tests._epanet_expected import error_code
from units.si import CUBIC_METER_PER_SECOND, FOOT64, METER, SECOND

comptime NET = """[JUNCTIONS]
 J1 10 5
 J2 12 3
[RESERVOIRS]
 R1 100
[TANKS]
 T1 50 10 2 20 30
[PIPES]
 P1 R1 J1 1000 12 100
 P2 J1 J2 800 10 100 0 CLOSED
 P3 J2 T1 900 10 100
[TIMES]
 Duration 2:00
 Report Timestep 0:30
[OPTIONS]
 Quality Age
[END]
"""


def _code(text: String) raises -> Int:
    """Return the code of the error that opening a text raises."""
    try:
        _ = EpanetProject(text)
    except e:
        return error_code(String(e))
    return 0


def test_open_reports_input_errors() raises:
    """A bad line raises error 200 with a line for each error."""
    var bad = String(NET).replace(" J2 12 3\n", " J2 x 3\n")
    try:
        _ = EpanetProject(bad)
        raise Error("no error")
    except e:
        var message = String(e)
        assert_equal(error_code(message), 200)
        assert_true("Error 202: illegal numeric value at line 3" in message)


def test_source_lines_that_crash_epanet() raises:
    """EPANET 2.3.6 reads past these lines; the port gives the C codes.

    For an unknown source type, `sourcedata` returns 213. For a source
    with no strength it reads the token after the last one; the port
    gives 202, the code of a strength that is not a number.
    """
    var base = String(NET).replace(
        "[TIMES]", "[SOURCES]\n J1 BRIGHT 1\n[TIMES]"
    )
    assert_equal(_code(base), 200)
    try:
        _ = EpanetProject(base)
    except e:
        assert_true("Error 213" in String(e))
    var empty = String(NET).replace("[TIMES]", "[SOURCES]\n J1 CONCEN\n[TIMES]")
    try:
        _ = EpanetProject(empty)
        raise Error("no error")
    except e:
        assert_true("Error 202" in String(e))


def test_calls_out_of_order() raises:
    """The solvers must be opened, and in order, as in the toolkit."""
    var p = EpanetProject(NET)
    with assert_raises(contains="EPANET error 103"):
        p.init_hydraulics(save=True)
    with assert_raises(contains="EPANET error 103"):
        _ = p.run_hydraulics()
    with assert_raises(contains="EPANET error 103"):
        _ = p.next_hydraulics()
    with assert_raises(contains="EPANET error 104"):
        p.open_quality()
    with assert_raises(contains="EPANET error 105"):
        p.init_quality()
    with assert_raises(contains="EPANET error 105"):
        _ = p.run_quality()
    with assert_raises(contains="EPANET error 105"):
        _ = p.next_quality()


def test_quality_past_the_saved_hydraulics() raises:
    """A quality step after the last saved hydraulics gives error 307."""
    var p = EpanetProject(NET)
    p.open_hydraulics()
    p.init_hydraulics(save=True)
    while True:
        _ = p.run_hydraulics()
        if p.next_hydraulics().value <= 0.0:
            break
    p.close_hydraulics()
    p.open_quality()
    p.init_quality()
    while True:
        _ = p.run_quality()
        if p.next_quality().value <= 0.0:
            break
    with assert_raises(contains="EPANET error 307"):
        _ = p.run_quality()


def test_unsaved_hydraulics() raises:
    """After the hydraulics close, quality needs hydraulics that were saved."""
    var p = EpanetProject(NET)
    p.open_hydraulics()
    p.init_hydraulics(save=False)
    _ = p.run_hydraulics()
    p.close_hydraulics()
    with assert_raises(contains="EPANET error 103"):
        _ = p.run_hydraulics()
    with assert_raises(contains="EPANET error 104"):
        p.open_quality()


def test_hydraulic_steps_without_quality_steps() raises:
    """With the quality open, a hydraulic step needs no quality step.

    `run_quality` moves the report time. When it is not called, the report
    time stays at the clock, and the next hydraulic step must not be zero.
    """
    var p = EpanetProject(NET)
    p.open_hydraulics()
    p.init_hydraulics(save=False)
    p.open_quality()
    p.init_quality()
    _ = p.run_hydraulics()
    assert_equal(Int(p.next_hydraulics().to(SECOND)), 1800)
    _ = p.run_hydraulics()
    assert_equal(Int(p.next_hydraulics().to(SECOND)), 1800)


def test_quality_calls_in_other_orders() raises:
    """Read the quality before it opens, and load a step twice.

    The values are those of EPANET 2.3.6 for the same calls. Before the
    quality opens, a link has the mean quality of its end nodes. A second
    `run_quality` at the same time loads nothing.
    """
    var p = EpanetProject(NET)
    p.open_hydraulics()
    p.init_hydraulics(save=True, init_flows=True)
    _ = p.run_hydraulics()
    assert_equal(p.link_value(LinkIndex(1), EN_LINKQUAL), 0.0)
    assert_equal(p.node_value(NodeIndex(1), EN_QUALITY), 0.0)
    while p.next_hydraulics().value > 0.0:
        _ = p.run_hydraulics()
    p.close_hydraulics()
    p.open_quality()
    p.init_quality()
    assert_equal(Int(p.run_quality().to(SECOND)), 0)
    assert_equal(Int(p.run_quality().to(SECOND)), 0)
    assert_equal(Int(p.next_quality().to(SECOND)), 1800)
    assert_equal(Int(p.run_quality().to(SECOND)), 1800)
    assert_equal(p.node_value(NodeIndex(1), EN_QUALITY), 0.4999999999999999)


def test_names_and_indexes() raises:
    """IDs map to indexes and back; a bad index or ID raises."""
    var p = EpanetProject(NET)
    assert_equal(p.node_count(), 4)
    assert_equal(p.link_count(), 3)
    assert_equal(p.node_index("T1").value, 4)
    assert_equal(p.link_index("P2").value, 2)
    assert_equal(p.node_id(NodeIndex(3)), "R1")
    assert_equal(p.link_id(LinkIndex(1)), "P1")
    assert_equal(p.quality_type(), AGE)
    assert_equal(Int(p.duration().to(SECOND)), 7200)
    assert_equal(Int(p.report_step().to(SECOND)), 1800)
    with assert_raises(contains="EPANET error 203"):
        _ = p.node_index("J9")
    with assert_raises(contains="EPANET error 204"):
        _ = p.link_index("P9")
    with assert_raises(contains="EPANET error 203"):
        _ = p.node_id(NodeIndex(0))
    with assert_raises(contains="EPANET error 203"):
        _ = p.head(NodeIndex(5))
    with assert_raises(contains="EPANET error 204"):
        _ = p.link_id(LinkIndex(0))
    with assert_raises(contains="EPANET error 204"):
        _ = p.flow(LinkIndex(4))
    with assert_raises(contains="EPANET error 251"):
        _ = p.node_value(NodeIndex(1), NodeProperty(0))
    with assert_raises(contains="EPANET error 251"):
        _ = p.link_value(LinkIndex(1), LinkProperty(0))


def test_si_results() raises:
    """The typed results are the toolkit values in SI units."""
    var p = EpanetProject(NET)
    p.open_hydraulics()
    p.init_hydraulics(save=False)
    _ = p.run_hydraulics()
    var j1 = NodeIndex(1)
    var feet = p.node_value(j1, EN_HEAD)
    assert_almost_equal(p.head(j1).to(FOOT64), feet, atol=1.0e-9)
    assert_almost_equal(
        p.pressure_head(j1).to(METER),
        (feet - 10.0) * 0.3048,
        atol=1.0e-9,
    )
    var gpm = p.node_value(j1, EN_DEMAND)
    var cms = p.demand(j1).to(CUBIC_METER_PER_SECOND)
    assert_almost_equal(cms * 15850.32314, gpm, atol=1.0e-3)
    var q = p.link_value(LinkIndex(1), EN_FLOW)
    var m3s = p.flow(LinkIndex(1)).to(CUBIC_METER_PER_SECOND)
    assert_almost_equal(m3s * 15850.32314, q, atol=1.0e-3)
    assert_equal(p.flow(LinkIndex(2)).value, 0.0)
    assert_true(p.node_value(j1, EN_PRESSURE) > 0.0)


def _first_head(text: String) raises -> Float64:
    """Open a text, solve the first hydraulic step, and return head J1."""
    var p = EpanetProject(text)
    p.open_hydraulics()
    p.init_hydraulics(save=False)
    _ = p.run_hydraulics()
    return p.node_value(NodeIndex(1), EN_HEAD)


def test_carriage_returns() raises:
    """A file with CR LF line ends gives the results of one with LF.

    A carriage return is a blank between tokens. It also ends a quoted
    token that has no closing quote.
    """
    var lf = String(NET)
    var crlf = String('\n[TITLE]\n "no closing quote\n') + lf
    crlf = crlf.replace("\n", "\r\n")
    assert_equal(_first_head(crlf), _first_head(lf))


def test_tank_lines_before_the_junctions() raises:
    """A [REACTIONS] or [MIXING] line for a tank, read before the junctions.

    EPANET 2.3.6 then finds the tank from a junction count that is not yet
    complete, and can write past the end of its tank array. The port skips
    the line; the tank keeps the global rate and complete mixing.
    """
    var text = String(
        "[TANKS]\n T1 50 10 2 20 30\n[REACTIONS]\n Tank T1 -0.5\n",
        "[MIXING]\n T1 FIFO\n",
    ) + String(NET).replace(" T1 50 10 2 20 30\n", "")
    var head = _first_head(text)
    assert_almost_equal(head, _first_head(NET), atol=1.0e-9)


def test_error_text() raises:
    """Each code that the port raises has the text of errors.dat."""
    assert_equal(error_text(103), "hydraulic solver not opened")
    assert_equal(error_text(307), "cannot read hydraulics file")
    assert_equal(error_text(999), "unknown error")


def test_kinds_are_checked() raises:
    """Each kind accepts its C codes and nothing else."""
    assert_true(NodeType(2).is_valid())
    assert_false(NodeType(3).is_valid())
    assert_true(LinkType(9).is_valid())
    assert_false(LinkType(-1).is_valid())
    assert_true(StatusType(10).is_valid())
    assert_false(StatusType(11).is_valid())
    assert_true(CurveType(5).is_valid())
    assert_false(CurveType(6).is_valid())
    assert_true(PumpType(3).is_valid())
    assert_false(PumpType(4).is_valid())
    assert_true(SourceType(3).is_valid())
    assert_false(SourceType(4).is_valid())
    assert_true(ControlType(3).is_valid())
    assert_false(ControlType(4).is_valid())
    assert_true(MixType(3).is_valid())
    assert_false(MixType(4).is_valid())
    assert_true(HeadLossType(2).is_valid())
    assert_false(HeadLossType(3).is_valid())
    assert_true(UnitSystem(1).is_valid())
    assert_false(UnitSystem(2).is_valid())
    assert_true(FlowUnits(10).is_valid())
    assert_false(FlowUnits(11).is_valid())
    assert_true(PressureUnits(5).is_valid())
    assert_false(PressureUnits(6).is_valid())
    assert_true(QualityType(3).is_valid())
    assert_false(QualityType(4).is_valid())
    assert_true(DemandModel(1).is_valid())
    assert_false(DemandModel(2).is_valid())
    assert_true(FlowDirection(-1).is_valid())
    assert_false(FlowDirection(2).is_valid())
    assert_true(NodeProperty(12).is_valid())
    assert_false(NodeProperty(13).is_valid())
    assert_true(LinkProperty(14).is_valid())
    assert_false(LinkProperty(9).is_valid())
    assert_true(NodeIndex(1).is_valid())
    assert_false(NodeIndex(0).is_valid())
    assert_true(LinkIndex(1).is_valid())
    assert_false(LinkIndex(0).is_valid())
    assert_equal(CHEM, QualityType(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
