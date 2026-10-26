# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live trig and interval modules keep the reviewed reference graphs."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sampled_reference_graphs import sampled_reference_graphs


def _copy(root: String) raises:
    """Copy the reference-graph inputs.

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


def test_the_live_reference_graphs_hold() raises:
    """The trig and interval modules keep their reviewed token digests."""
    sampled_reference_graphs(".")
    sampled_reference_graphs("./")
    sampled_reference_graphs("extensions/..")


def test_a_changed_trig_token_is_refused() raises:
    """A changed trig token is refused."""
    var root = "/tmp/sampled-reference-graphs-trig"
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
        sampled_reference_graphs(root)


def test_a_changed_interval_token_is_refused() raises:
    """A changed interval token is refused."""
    var root = "/tmp/sampled-reference-graphs-interval"
    _copy(root)
    var path = root + "/extensions/carla/curve_interval.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace(
            "struct _JetExpression[derivatives: Bool]",
            "struct _JetExpression[derivatives: Int]",
        )
    )
    with assert_raises(
        contains=(
            "reference module changed; renewed review required: "
            + "curve_interval.mojo"
        )
    ):
        sampled_reference_graphs(root)


def test_an_empty_trig_module_is_refused() raises:
    """An empty trig module is refused."""
    var root = "/tmp/sampled-reference-graphs-empty"
    _copy(root)
    Path(root + "/extensions/carla/curve_trig.mojo").write_text("")
    with assert_raises(
        contains=(
            "reference module changed; renewed review required: "
            + "curve_trig.mojo"
        )
    ):
        sampled_reference_graphs(root)


def main() raises:
    """Run the reference-graph tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
