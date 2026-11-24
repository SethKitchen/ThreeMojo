# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Small EPANET input files against OWA EPANET 2.3.6.

`assets/epanet/cases.txt` holds small input files: each option, each
form of each section, and each input error. `cases.expected` holds what
the real EPANET library gives for each, from
`assets/epanet/make_epanet_cases.py`. A file with errors must give the
same error codes for the same lines. A file that opens must give the
same results at each step, or fail at the same call with the same code.
A case named `together_...` runs the hydraulics and the water quality
together.
"""

from std.testing import TestSuite, assert_equal, assert_true

from extensions.epanet.project import EpanetProject
from tests._epanet_expected import (
    Expected,
    check_simulation,
    check_together,
    error_code,
)


def _cases() raises -> List[List[String]]:
    """Return the name and the text of each case."""
    var out = List[List[String]]()
    var text = open("assets/epanet/cases.txt", "r").read()
    for line in text.split("\n"):
        if line.startswith("#### "):
            var name = String(line[byte=5:])
            var item: List[String] = [name, String()]
            out.append(item^)
        elif len(out) > 0:
            out[len(out) - 1][1] += String(line) + "\n"
    return out^


def _words(text: String) -> String:
    """Return the words of a line, each one space apart."""
    var out = String()
    for w in text.split():
        if out.byte_length() > 0:
            out += " "
        out += String(w)
    return out^


def _input_errors(message: String) -> List[String]:
    """Return `CODE LINE` for each input error in a message of the port."""
    var out = List[String]()
    for line in message.split("\n"):
        if not line.startswith("Error "):
            continue
        var at = line.find(" at line ")
        if at < 0:
            continue
        var rest = String(line[byte = at + 9 :])
        var colon = rest.find(": ")
        var code = String(line[byte = 6 : line.find(":")])
        out.append(code + " " + _words(String(rest[byte = colon + 2 :])))
    return out^


def _check_case(name: String, text: String, mut ex: Expected) raises:
    assert_equal(ex.take("case")[1], name)
    var code = atol(ex.take("open")[1])
    var expected = List[String]()
    while ex.peek() == "error":
        var row = ex.take("error")
        var s = row[1]
        for i in range(2, len(row)):
            s += " " + row[i]
        expected.append(s)
    try:
        var p = EpanetProject(text)
        assert_true(code <= 100, String(name, ": opened, EPANET gave ", code))
        if name.startswith("together_"):
            check_together(p, ex)
        else:
            check_simulation(p, ex)
    except e:
        var message = String(e)
        if code <= 100:
            raise Error(String(name, ": ", message))
        assert_equal(error_code(message), code, String(name, ": ", message))
        var got = _input_errors(message)
        assert_equal(len(got), len(expected), String(name, ": ", message))
        for i in range(len(got)):
            assert_equal(got[i], expected[i], name)


def _run(first: String, last: String) raises:
    """Check each case from the one named `first` to the one before `last`."""
    var cases = _cases()
    var ex = Expected(open("assets/epanet/cases.expected", "r").read())
    var on = False
    var seen = False
    for c in cases:
        if c[0] == first:
            on = True
        if c[0] == last:
            break
        if on:
            seen = True
            _check_case(c[0], c[1], ex)
        else:
            # Skip the lines of a case before the range.
            _ = ex.take("case")
            while ex.peek() != "case" and ex.peek() != String():
                ex.at += 1
    assert_true(seen, first)
    if last == String():
        assert_equal(ex.peek(), String())


def test_file_and_node_sections() raises:
    """The shape of a file, junctions, reservoirs and tanks."""
    _run("base", "pipe_defaults")


def test_link_sections() raises:
    """Pipes, pumps, curves and valves."""
    _run("pipe_defaults", "pattern_id_only")


def test_data_sections() raises:
    """The data sections, from [PATTERNS] to [REPORT]."""
    _run("pattern_id_only", "times")


def test_times_and_options() raises:
    """The [TIMES] and [OPTIONS] sections."""
    _run("times", "rules")


def test_rules_and_solver_failures() raises:
    """Rule-based controls and networks that the solver refuses."""
    _run("rules", String())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
