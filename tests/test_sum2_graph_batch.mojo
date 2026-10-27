# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The five Sum2 caller graphs match in one comparison."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tests._python_expr import sum2_graph_batch
from tools._python_json import PyJson
from tools._sum2_checkpoints import sum2_checkpoints


def _payload() raises -> String:
    """Return the live modules and the reviewed checkpoints.

    Returns:
        JSON for `sum2_graph_batch`.

    Raises:
        Error: A source cannot be read.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var texts = doc.new_dict()
    doc.set(
        texts,
        "curve_sum2",
        doc.new_str(Path("extensions/carla/curve_sum2.mojo").read_text()),
    )
    doc.set(
        texts,
        "lane_geometry",
        doc.new_str(Path("extensions/carla/lane_geometry.mojo").read_text()),
    )
    doc.set(
        texts,
        "spiral_roundoff_proof",
        doc.new_str(
            Path("extensions/carla/spiral_roundoff_proof.mojo").read_text()
        ),
    )
    doc.set(root, "texts", texts)
    var saved = PyJson.parse(sum2_checkpoints())
    var checkpoints = doc.new_dict()
    var names = List[String]()
    names.append("helper")
    names.append("scalar")
    names.append("envelope")
    names.append("eligibility")
    for name in names:
        doc.set(
            checkpoints,
            name,
            doc.new_str(saved.text(saved.at(saved.root, name))),
        )
    doc.set(root, "checkpoints", checkpoints)
    doc.root = root
    return doc.dumps()


def test_sum2_slices_reach_the_lane_environment_check() raises:
    """The stored-term slices match, then the lane caller must keep its guard.
    """
    var saved = PyJson.parse(sum2_checkpoints())
    var doc = PyJson.parse(_payload())
    var texts = doc.at(doc.root, "texts")
    doc.set(
        texts,
        "lane_geometry",
        doc.new_str(saved.text(saved.at(saved.root, "scalar"))),
    )
    with assert_raises(contains="scalar environment check moved"):
        sum2_graph_batch(doc.dumps())


def test_a_missing_sum2_module_is_refused() raises:
    """The batch reads the first module before it compares a graph."""
    with assert_raises():
        sum2_graph_batch('{"texts":{},"checkpoints":{}}')


def main() raises:
    """Run the Sum2 graph batch tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
