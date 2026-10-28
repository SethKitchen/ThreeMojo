# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The sampled input modules stay in reviewed order."""

from std.testing import TestSuite, assert_equal

from tools._python_json import PyJson
from tools._sampled_input_modules import (
    sampled_input_modules,
    sampled_input_plan,
)


def test_four_sampled_inputs_stay_in_order() raises:
    """Bounds, trig, and the interval come before the lane value module."""
    var doc = PyJson.parse(sampled_input_modules())
    assert_equal(doc.length(doc.root), 4)
    assert_equal(doc.text(doc.item(doc.root, 0)), "curve_bounds.mojo")
    assert_equal(doc.text(doc.item(doc.root, 1)), "curve_trig.mojo")
    assert_equal(doc.text(doc.item(doc.root, 2)), "curve_interval.mojo")
    assert_equal(doc.text(doc.item(doc.root, 3)), "lane_value_bounds.mojo")


def test_the_modules_come_before_the_package() raises:
    """The four module names are read before the package path."""
    var doc = PyJson.parse(sampled_input_plan())
    assert_equal(doc.key(doc.root, 0), "modules")
    assert_equal(doc.key(doc.root, 1), "package")
    var modules = doc.at(doc.root, "modules")
    assert_equal(doc.text(doc.item(modules, 0)), "curve_bounds.mojo")
    assert_equal(doc.text(doc.item(modules, 1)), "curve_trig.mojo")
    assert_equal(doc.text(doc.item(modules, 2)), "curve_interval.mojo")
    assert_equal(doc.text(doc.item(modules, 3)), "lane_value_bounds.mojo")
    assert_equal(doc.text(doc.at(doc.root, "package")), "extensions/carla")


def main() raises:
    """Run the sampled input module tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
