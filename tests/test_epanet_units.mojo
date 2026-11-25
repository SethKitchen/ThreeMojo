# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Single functions of the hydraulic solver against EPANET 2.3.6.

Some states of the solver are hard to reach from an input file: a valve
at a singular node, a leak that has not converged, a pressure driven
demand that does not match its pressure. `assets/epanet/units.expected`
sets such states on networks of `cases.txt`, calls one function of the C
solver, and gives what it returns, from `assets/epanet/make_epanet_units.py`.
The port must give the same values, bit for bit. Where C gives NaN, the
port must give NaN.
"""

from std.math import isnan
from std.testing import TestSuite, assert_equal

from extensions.epanet.cmath import cstrtod
from extensions.epanet.coeffs import (
    _demandcoeffs,
    _emittercoeffs,
    _pbvcoeff,
    _pumpcoeff,
)
from extensions.epanet.hydraul import tanktimestep
from extensions.epanet.hydsolver import (
    Hydbalance,
    _badvalve,
    _hasconverged,
    _newdemandflows,
    _pdaconverged,
    _pswitch,
)
from extensions.epanet.hydstatus import (
    _cvstatus,
    _fcvstatus,
    _prvstatus,
    _psvstatus,
    _pumpstatus,
)
from extensions.epanet.kinds import StatusType
from extensions.epanet.leakage import leakagehasconverged
from extensions.epanet.project import EpanetProject


def _number(text: String) raises -> Float64:
    """Read a number as the C library reads it."""
    var used = 0
    var x = cstrtod(text, used)
    if used != text.byte_length():
        raise Error(String("not a number: ", text))
    return x


def _case(name: String) raises -> String:
    """Return the text of a case of `cases.txt`."""
    var text = open("assets/epanet/cases.txt", "r").read()
    var out = String()
    var found = False
    for line in text.split("\n"):
        if line.startswith("#### "):
            if found:
                break
            found = String(line[byte=5:]) == name
        elif found:
            out += String(line) + "\n"
    if not found:
        raise Error(String("no case ", name))
    return out^


def _links(p: EpanetProject, mut got: List[Float64]):
    """Add the status, then the setting, of each link."""
    for k in range(1, p.pr.net.nlinks + 1):
        got.append(Float64(p.pr.hyd.link_status[k].value))
    for k in range(1, p.pr.net.nlinks + 1):
        got.append(p.pr.hyd.link_setting[k])


def _zero_rows(mut p: EpanetProject):
    """Clear the diagonal and the right side of the matrix."""
    for i in range(p.pr.net.nnodes + 1):
        p.pr.hyd.sm.aii[i] = 0.0
        p.pr.hyd.sm.f[i] = 0.0


def _rows(p: EpanetProject, mut got: List[Float64]):
    """Add the diagonal and the right side of the row of each junction."""
    for i in range(1, p.pr.net.njuncs + 1):
        var r = p.pr.hyd.sm.row[i]
        got.append(p.pr.hyd.sm.aii[r])
        got.append(p.pr.hyd.sm.f[r])


def _call(mut p: EpanetProject, words: List[String]) raises -> List[Float64]:
    """Call one function of the port and return what it gives."""
    var name = words[1]
    var a = List[Float64]()
    for i in range(2, len(words)):
        a.append(_number(words[i]))
    var got = List[Float64]()
    if name == "cvstatus":
        got.append(
            Float64(_cvstatus(p.pr, StatusType(Int(a[0])), a[1], a[2]).value)
        )
    elif name == "pumpstatus":
        got.append(Float64(_pumpstatus(p.pr, Int(a[0]), a[1]).value))
    elif name == "prvstatus":
        var s = _prvstatus(
            p.pr, Int(a[0]), StatusType(Int(a[1])), a[2], a[3], a[4]
        )
        got.append(Float64(s.value))
    elif name == "psvstatus":
        var s = _psvstatus(
            p.pr, Int(a[0]), StatusType(Int(a[1])), a[2], a[3], a[4]
        )
        got.append(Float64(s.value))
    elif name == "fcvstatus":
        var s = _fcvstatus(p.pr, Int(a[0]), StatusType(Int(a[1])), a[2], a[3])
        got.append(Float64(s.value))
    elif name == "badvalve":
        got.append(1.0 if _badvalve(p.pr, Int(a[0])) else 0.0)
        _links(p, got)
    elif name == "pswitch":
        got.append(1.0 if _pswitch(p.pr) else 0.0)
        _links(p, got)
    elif name == "newdemandflows":
        var hbal = Hydbalance(0.0, 0.0, 0.0, 0, 0, 0)
        var qsum = 0.0
        var dqsum = 0.0
        p.pr.hyd.relax_factor = 1.0
        _newdemandflows(p.pr, hbal, qsum, dqsum)
        got.append(qsum)
        got.append(dqsum)
        got.append(hbal.maxflowchange)
        got.append(Float64(hbal.maxflownode))
        for i in range(1, p.pr.net.njuncs + 1):
            got.append(p.pr.hyd.demand_flow[i])
    elif name == "hasconverged":
        var hbal = Hydbalance(0.0, 0.0, a[1], 0, 0, 0)
        got.append(1.0 if _hasconverged(p.pr, a[0], hbal) else 0.0)
    elif name == "pdaconverged":
        got.append(1.0 if _pdaconverged(p.pr) else 0.0)
        got.append(Float64(p.pr.hyd.deficient_nodes))
        got.append(p.pr.hyd.demand_reduction)
    elif name == "leakagehasconverged":
        got.append(1.0 if leakagehasconverged(p.pr) else 0.0)
    elif name == "demandcoeffs":
        _zero_rows(p)
        _demandcoeffs(p.pr)
        _rows(p, got)
    elif name == "emittercoeffs":
        _zero_rows(p)
        _emittercoeffs(p.pr)
        _rows(p, got)
    elif name == "pumpcoeff":
        var k = Int(a[0])
        _pumpcoeff(p.pr, k)
        got.append(p.pr.hyd.p[k])
        got.append(p.pr.hyd.y[k])
    elif name == "pbvcoeff":
        var k = Int(a[0])
        _pbvcoeff(p.pr, k)
        got.append(p.pr.hyd.p[k])
        got.append(p.pr.hyd.y[k])
    elif name == "tanktimestep":
        var tstep = Int(a[0])
        var i = tanktimestep(p.pr, tstep)
        got.append(Float64(i))
        got.append(Float64(tstep))
    else:
        raise Error(String("unknown function ", name))
    return got^


def _set(mut p: EpanetProject, words: List[String]) raises:
    """Set one value of the solver."""
    var what = words[1]
    var i = Int(_number(words[2]))
    var v = _number(words[3])
    if what == "flow":
        p.pr.hyd.link_flow[i] = v
    elif what == "head":
        p.pr.hyd.node_head[i] = v
    elif what == "status":
        p.pr.hyd.link_status[i] = StatusType(Int(v))
    elif what == "setting":
        p.pr.hyd.link_setting[i] = v
    elif what == "demandflow":
        p.pr.hyd.demand_flow[i] = v
    elif what == "fulldemand":
        p.pr.hyd.full_demand[i] = v
    elif what == "nodedemand":
        p.pr.hyd.node_demand[i] = v
    elif what == "emitterflow":
        p.pr.hyd.emitter_flow[i] = v
    elif what == "leakageflow":
        p.pr.hyd.leakage_flow[i] = v
    elif what == "km":
        p.pr.net.link[i].km = v
    elif what == "tankv":
        p.pr.net.tank[i].v = v
    else:
        raise Error(String("unknown array ", what))


def _words(text: String) -> List[String]:
    """Return the words of a text."""
    var out = List[String]()
    for w in text.split():
        out.append(String(w))
    return out^


def _check(names: List[String]) raises:
    """Run every command and compare the calls of the named functions."""
    var text = open("assets/epanet/units.expected", "r").read()
    var p = EpanetProject(_case("base"))
    var count = 0
    for raw in text.split("\n"):
        var line = String(raw)
        if line.byte_length() == 0:
            continue
        var eq = line.find(" = ")
        var words = _words(line if eq < 0 else String(line[byte=0:eq]))
        if words[0] == "net":
            p = EpanetProject(_case(words[1]))
            p.open_hydraulics()
            p.init_hydraulics(save=False)
            _ = p.run_hydraulics()
        elif words[0] == "set":
            _set(p, words)
        elif words[0] == "call":
            var got = _call(p, words)
            if words[1] not in names:
                continue
            var want = List[Float64]()
            for w in _words(String(line[byte = eq + 3 :])):
                if w != "|":
                    want.append(_number(w))
            assert_equal(len(got), len(want), line)
            for i in range(len(want)):
                # An emitter with no flow gives NaN, in C as here.
                var same = got[i] == want[i] or (
                    isnan(got[i]) and isnan(want[i])
                )
                if not same:
                    raise Error(String(line, ": value ", i, " is ", got[i]))
            count += 1
        else:
            raise Error(String("bad line: ", line))
    if count == 0:
        raise Error("no calls were checked")


def test_valve_and_pump_status() raises:
    """The status of check valves, pumps, PRVs, PSVs and FCVs."""
    _check(["cvstatus", "pumpstatus", "prvstatus", "psvstatus", "fcvstatus"])


def test_valves_at_singular_nodes_and_pressure_controls() raises:
    """`badvalve` at each node, and the junction pressure controls."""
    _check(["badvalve", "pswitch"])


def test_pressure_driven_demands_and_leaks() raises:
    """The demand flows, their convergence, and the leak convergence."""
    _check(
        [
            "newdemandflows",
            "pdaconverged",
            "demandcoeffs",
            "hasconverged",
            "leakagehasconverged",
        ]
    )


def test_coefficients_and_tank_steps() raises:
    """Emitter, pump and PBV coefficients, and the tank time step."""
    _check(["emittercoeffs", "pumpcoeff", "pbvcoeff", "tanktimestep"])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
