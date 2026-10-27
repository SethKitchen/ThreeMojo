# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The stored-moment pin specification keeps its reviewed tables."""

from std.testing import TestSuite, assert_equal, assert_raises

from tools._moment_pin_spec import moment_pin_spec
from tools._python_json import PyJson


def test_the_static_tables_keep_their_paths_and_sizes() raises:
    """Arrays, scalars, blocks, and routing stay on the reviewed paths."""
    var doc = PyJson.parse(
        moment_pin_spec(
            '{"dependencies":{"group":"stored_arithmetic","paths":["extensions/carla/curve_interval.mojo","extensions/carla/curve_sum2.mojo"]}}'
        )
    )
    assert_equal(doc.length(doc.root), 7)
    var arrays = doc.at(doc.root, "arrays")
    assert_equal(doc.length(arrays), 4)
    assert_equal(doc.text(doc.at(doc.at(arrays, "_GL_NODES"), "size")), "5")
    assert_equal(doc.text(doc.at(doc.at(arrays, "_GL_WEIGHTS"), "size")), "5")
    assert_equal(
        doc.text(doc.at(doc.at(arrays, "_COS_COEFFICIENTS"), "size")), "11"
    )
    assert_equal(
        doc.text(doc.at(doc.at(arrays, "_SIN_COEFFICIENTS"), "size")), "11"
    )
    assert_equal(
        doc.text(doc.at(doc.at(arrays, "_GL_NODES"), "path")),
        "extensions/carla/geometry.mojo",
    )
    assert_equal(doc.length(doc.at(doc.root, "scalars")), 4)
    assert_equal(
        doc.text(doc.at(doc.at(doc.root, "scalars"), "_PHASE_LIMIT")), "1"
    )
    assert_equal(
        doc.text(doc.at(doc.root, "scalar_path")),
        "extensions/carla/curve_trig.mojo",
    )
    var blocks = doc.at(doc.root, "block_paths")
    assert_equal(doc.length(blocks), 10)
    assert_equal(
        doc.text(doc.at(blocks, "ideal_spiral")),
        "extensions/carla/curve_bounds.mojo",
    )
    var boundaries = doc.at(doc.root, "boundaries")
    assert_equal(doc.length(boundaries), 10)
    var spiral = doc.at(boundaries, "ideal_spiral")
    assert_equal(doc.text(doc.at(spiral, "begin")), "def _spiral_expression[")
    assert_equal(doc.text(doc.at(spiral, "end")), "def _sample_index(")
    assert_equal(doc.length(doc.at(doc.root, "routing_paths")), 4)
    var dependencies = doc.at(doc.root, "dependencies")
    assert_equal(doc.text(doc.at(dependencies, "group")), "stored_arithmetic")
    assert_equal(
        doc.text(doc.item(doc.at(dependencies, "paths"), 0)),
        "extensions/carla/curve_interval.mojo",
    )
    assert_equal(
        doc.text(doc.item(doc.at(dependencies, "paths"), 1)),
        "extensions/carla/curve_sum2.mojo",
    )


def test_a_missing_or_non_object_dependency_record_is_refused() raises:
    """A missing dependency record and a list are both refused."""
    with assert_raises(contains="KeyError: 'dependencies'"):
        _ = moment_pin_spec("{}")
    with assert_raises(contains="moment pin dependencies changed"):
        _ = moment_pin_spec('{"dependencies":[]}')


def main() raises:
    """Run the moment pin specification tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
