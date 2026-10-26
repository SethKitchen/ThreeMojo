# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live trig and interval modules keep the reviewed syntax graphs."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.sampled_module_graphs import (
    primitive_graph,
    require_primitive,
    sampled_module_graphs,
)


def _copy(root: String) raises:
    """Copy the module-graph inputs.

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
    files.append("extensions/carla/curve_trig.mojo")
    files.append("extensions/carla/curve_interval.mojo")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_live_module_graphs_hold() raises:
    """The trig graph, the interval graph, and the jet primitive hold."""
    sampled_module_graphs(".")
    sampled_module_graphs("./")
    sampled_module_graphs("extensions/..")


def test_a_comment_keeps_the_graph() raises:
    """A comment keeps the reviewed graph."""
    var root = "/tmp/sampled-module-graphs-comment"
    _copy(root)
    var path = root + "/extensions/carla/curve_trig.mojo"
    Path(path).write_text("# reviewed\n" + Path(path).read_text())
    sampled_module_graphs(root)


def test_wider_spacing_keeps_the_graph() raises:
    """A wider spelling of the same number keeps the graph."""
    var root = "/tmp/sampled-module-graphs-space"
    _copy(root)
    var path = root + "/extensions/carla/curve_trig.mojo"
    Path(path).write_text(Path(path).read_text().replace("1.0,", "1.00,"))
    sampled_module_graphs(root)


def test_a_changed_trig_graph_is_refused() raises:
    """A changed trig declaration is refused."""
    var root = "/tmp/sampled-module-graphs-trig"
    _copy(root)
    var path = root + "/extensions/carla/curve_trig.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "def _sincos_jet(value: _Jet)",
            "def _sincos_jet(value: _ValueJet)",
        )
    )
    with assert_raises(
        contains=(
            "reference module changed; renewed review required: "
            + "curve_trig.mojo"
        )
    ):
        sampled_module_graphs(root)


def test_a_changed_interval_graph_is_refused() raises:
    """A changed interval declaration is refused."""
    var root = "/tmp/sampled-module-graphs-interval"
    _copy(root)
    var path = root + "/extensions/carla/curve_interval.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("def _next_up(value: Float64)", "def _next_up(value: Int)")
    )
    with assert_raises(
        contains=(
            "reference module changed; renewed review required: "
            + "curve_interval.mojo"
        )
    ):
        sampled_module_graphs(root)


def test_a_changed_primitive_is_refused() raises:
    """A changed jet class is refused."""
    var text = Path("extensions/carla/curve_interval.mojo").read_text()
    text = text.replace(
        "struct _JetExpression[derivatives: Bool]",
        "struct _JetExpression[derivatives: Int]",
    )
    with assert_raises(
        contains=(
            "Jet primitive graph changed; renewed "
            + "derivative-independence review required"
        )
    ):
        require_primitive(text)


def test_a_changed_derivative_alias_is_refused() raises:
    """A changed derivative alias is refused."""
    var text = Path("extensions/carla/curve_interval.mojo").read_text()
    text = text.replace(
        "comptime _Jet = _JetExpression[True]",
        "comptime _Jet = _JetExpression[False]",
    )
    with assert_raises(contains="actual derivative alias changed: _Jet"):
        _ = primitive_graph(text)


def test_a_missing_primitive_is_refused() raises:
    """A renamed jet class is refused."""
    var text = Path("extensions/carla/curve_interval.mojo").read_text()
    text = text.replace(
        "struct _JetExpression[derivatives: Bool]",
        "struct _JetValue[derivatives: Bool]",
    )
    with assert_raises(contains="unsupported primitive declaration"):
        _ = primitive_graph(text)


def test_an_empty_module_is_refused() raises:
    """An empty trig module is refused."""
    var root = "/tmp/sampled-module-graphs-empty"
    _copy(root)
    Path(root + "/extensions/carla/curve_trig.mojo").write_text("")
    with assert_raises(
        contains=(
            "reference module changed; renewed review required: "
            + "curve_trig.mojo"
        )
    ):
        sampled_module_graphs(root)


def main() raises:
    """Run the module-graph tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
