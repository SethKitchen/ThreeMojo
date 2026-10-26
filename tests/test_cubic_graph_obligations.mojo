# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The reviewed cubic operation spans still appear once."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.cubic_graph_obligations import cubic_graph_obligations


def _copy(root: String) raises:
    """Copy the four cubic graph modules.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(["mkdir", "-p", root + "/extensions/carla"], 10.0)
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/carla/polynomial.mojo")
    files.append("extensions/carla/lane_value_bounds.mojo")
    files.append("extensions/carla/junction_bounds.mojo")
    files.append("extensions/carla/curve_rounded_arc.mojo")
    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_cubic_graphs_hold() raises:
    """Each reviewed span appears once."""
    cubic_graph_obligations(".")
    cubic_graph_obligations("./")
    cubic_graph_obligations("extensions/..")


def test_a_changed_polynomial_span_is_refused() raises:
    """A changed polynomial span is refused."""
    var root = "/tmp/cubic-graph-polynomial"
    _copy(root)
    var path = root + "/extensions/carla/polynomial.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("        self.d = d\n", "        self.d = d + 0.0\n")
    )
    with assert_raises(
        contains=(
            "missing or ambiguous current operation: "
            + "extensions/carla/polynomial.mojo:0"
        )
    ):
        cubic_graph_obligations(root)


def test_a_repeated_arc_span_is_refused() raises:
    """A repeated rounded-arc span is refused."""
    var root = "/tmp/cubic-graph-arc"
    _copy(root)
    var path = root + "/extensions/carla/curve_rounded_arc.mojo"
    var text = Path(path).read_text()
    Path(path).write_text(
        text
        + "\ndef _rounded_constant(polynomial: CubicPolynomial) ->"
        " _RoundedBox:\n    if (\n        not"
        " _rounded_operand(polynomial.s)\n        or polynomial.b != 0.0\n   "
        "     or polynomial.c != 0.0\n        or polynomial.d != 0.0\n   "
        " ):\n        return _RoundedBox.unknown()\n"
    )
    with assert_raises(
        contains=(
            "missing or ambiguous current operation: "
            + "extensions/carla/curve_rounded_arc.mojo:0"
        )
    ):
        cubic_graph_obligations(root)


def main() raises:
    """Run the cubic graph tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
