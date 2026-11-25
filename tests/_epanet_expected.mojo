# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare an EPANET project with the results of the real EPANET.

`assets/epanet/make_epanet.py` and `make_epanet_cases.py` write the
results. `check_simulation` runs the project one step at a time, as the
scripts do, and compares each line. A line such as `runH 110` says that
the real EPANET failed at that call with that code: the port must raise
the same code there.
"""

from std.testing import assert_equal, assert_true

from extensions.epanet.kinds import (
    EN_DEMAND,
    EN_ENERGY,
    EN_FLOW,
    EN_HEAD,
    EN_LINKQUAL,
    EN_PRESSURE,
    EN_QUALITY,
    EN_SETTING,
    EN_STATUS,
    LinkIndex,
    LinkProperty,
    NodeIndex,
    NodeProperty,
)
from extensions.epanet.project import EpanetProject

# Ten significant digits round a value by at most 5e-10 of itself.
comptime TOLERANCE = 1.0e-9


struct Expected(Movable):
    """The words of each line of an expected file, and a cursor."""

    var lines: List[List[String]]
    var at: Int

    def __init__(out self, text: String):
        """Split the text into lines of words.

        Args:
            text: The text of the file.
        """
        self.lines = List[List[String]]()
        for line in text.split("\n"):
            var words = List[String]()
            for w in line.split(" "):
                if w.byte_length() > 0:
                    words.append(String(w))
            if len(words) > 0:
                self.lines.append(words^)
        self.at = 0

    def peek(self) -> String:
        """Return the first word of the next line.

        Returns:
            The word, or an empty string at the end.
        """
        if self.at >= len(self.lines):
            return String()
        return self.lines[self.at][0]

    def take(mut self, word: String) raises -> List[String]:
        """Return the next line, which must start with a word.

        Args:
            word: The first word that the line must have.

        Returns:
            The words of the line.

        Raises:
            Error: The next line does not start with the word.
        """
        assert_true(self.at < len(self.lines), String("no line ", word))
        assert_equal(self.lines[self.at][0], word)
        self.at += 1
        return self.lines[self.at - 1].copy()


def error_code(message: String) raises -> Int:
    """Return the code of an `EPANET error N: ...` message.

    Args:
        message: The message of an error that the port raised.

    Returns:
        The code, or -1 if the message has none.

    Raises:
        Error: The code is not a number.
    """
    var head = "EPANET error "
    if not message.startswith(head):
        return -1
    var rest = String(message[byte = head.byte_length() :])
    var colon = rest.find(":")
    if colon < 0:
        return -1
    return atol(String(rest[byte=0:colon]))


def _close(got: Float64, expected: Float64, what: String) raises:
    var limit = TOLERANCE * max(1.0, abs(expected))
    assert_true(
        abs(got - expected) <= limit,
        String(what, ": got ", got, ", expected ", expected),
    )


def _nodes(
    p: EpanetProject, mut ex: Expected, word: String, prop: NodeProperty
) raises:
    var row = ex.take(word)
    assert_equal(len(row), p.node_count() + 1)
    for i in range(1, p.node_count() + 1):
        _close(
            p.node_value(NodeIndex(i), prop),
            atof(row[i]),
            String(word, " ", i),
        )


def _links(
    p: EpanetProject, mut ex: Expected, word: String, prop: LinkProperty
) raises:
    var row = ex.take(word)
    assert_equal(len(row), p.link_count() + 1)
    for i in range(1, p.link_count() + 1):
        _close(
            p.link_value(LinkIndex(i), prop),
            atof(row[i]),
            String(word, " ", i),
        )


def _fails(mut ex: Expected, call: String, message: String) raises:
    """Check that the expected file says that a call fails as it did."""
    var row = ex.take(call)
    assert_equal(error_code(message), atol(row[1]), message)


def _hydraulic_step(p: EpanetProject, mut ex: Expected, t: Int) raises:
    """Compare the hydraulic results of one step."""
    var row = ex.take("hydraulic")
    assert_equal(t, atol(row[1]))
    _nodes(p, ex, "head", EN_HEAD)
    _nodes(p, ex, "demand", EN_DEMAND)
    _nodes(p, ex, "pressure", EN_PRESSURE)
    _links(p, ex, "flow", EN_FLOW)
    _links(p, ex, "status", EN_STATUS)
    _links(p, ex, "setting", EN_SETTING)
    _links(p, ex, "energy", EN_ENERGY)


def _quality_step(p: EpanetProject, mut ex: Expected, t: Int) raises:
    """Compare the water quality of one step."""
    var row = ex.take("quality")
    assert_equal(t, atol(row[1]))
    _nodes(p, ex, "node", EN_QUALITY)
    _links(p, ex, "link", EN_LINKQUAL)


def _hydraulics(mut p: EpanetProject, mut ex: Expected) raises -> Bool:
    """Compare the hydraulic steps; return False after a failed call."""
    try:
        p.open_hydraulics()
    except e:
        _fails(ex, "openH", String(e))
        return False
    p.init_hydraulics(save=True)
    while True:
        var t: Int
        try:
            t = Int(p.run_hydraulics().value)
        except e:
            _fails(ex, "runH", String(e))
            return False
        _hydraulic_step(p, ex, t)
        if p.next_hydraulics().value <= 0.0:
            p.close_hydraulics()
            return True


def _quality(mut p: EpanetProject, mut ex: Expected) raises:
    """Compare the water quality at each report time."""
    p.open_quality()
    p.init_quality()
    var report = Int(p.report_step().value)
    while True:
        var t = Int(p.run_quality().value)
        if t % report == 0:
            _quality_step(p, ex, t)
        if p.next_quality().value <= 0.0:
            p.close_quality()
            return


def check_simulation(mut p: EpanetProject, mut ex: Expected) raises:
    """Run a project and compare it with the lines of an expected file.

    Args:
        p: A project that is open.
        ex: The expected lines, at the `size` line.

    Raises:
        Error: A value, a time or an error code differs.
    """
    var size = ex.take("size")
    assert_equal(atol(size[1]), p.node_count())
    assert_equal(atol(size[2]), p.link_count())
    if _hydraulics(p, ex):
        _quality(p, ex)


def check_together(mut p: EpanetProject, mut ex: Expected) raises:
    """Run the hydraulics and the water quality together, and compare.

    This is `simulate_together` of `make_epanet.py`. The hydraulics start
    from new flows and save nothing.

    Args:
        p: A project that is open.
        ex: The expected lines, at the `size` line.

    Raises:
        Error: A value, a time or an error code differs.
    """
    var size = ex.take("size")
    assert_equal(atol(size[1]), p.node_count())
    assert_equal(atol(size[2]), p.link_count())
    try:
        p.open_hydraulics()
    except e:
        _fails(ex, "openH", String(e))
        return
    p.init_hydraulics(save=False, init_flows=True)
    p.open_quality()
    p.init_quality()
    while True:
        var t: Int
        try:
            t = Int(p.run_hydraulics().value)
        except e:
            _fails(ex, "runH", String(e))
            return
        _hydraulic_step(p, ex, t)
        _quality_step(p, ex, Int(p.run_quality().value))
        var step = p.next_hydraulics()
        _ = p.next_quality()
        if step.value <= 0.0:
            break
    p.close_quality()
    p.close_hydraulics()
