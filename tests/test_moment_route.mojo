# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Moment routing uses the reviewed array and scalar names."""

from std.testing import TestSuite, assert_equal, assert_raises

from tests._python_tokens import module_routing_json
from tools._moment_route import (
    _routing_constants,
    moment_route_accept,
    moment_route_current,
)


def test_moment_routing_uses_the_sorted_constant_names() raises:
    """The live route masks the same names Python sorts."""
    var source = "def f():\n    return 1\n"
    var constants = _routing_constants()
    assert_equal(
        constants,
        (
            '["_COS_COEFFICIENTS","_GL_NODES","_GL_WEIGHTS","_HALF_PI_HIGH",'
            + '"_HALF_PI_LOW","_INV_HALF_PI","_PHASE_LIMIT","_SIN_COEFFICIENTS"]'
        ),
    )
    assert_equal(
        moment_route_current(source), module_routing_json(source, constants)
    )


def test_a_changed_moment_route_is_refused() raises:
    """The accept check refuses a different routing document."""
    var current = moment_route_current("def f():\n    return 1\n")
    moment_route_accept(current, current, "source routing changed: demo", False)
    with assert_raises(contains="source routing changed: demo"):
        moment_route_accept(
            current, current + " ", "source routing changed: demo", False
        )


def main() raises:
    """Run the moment routing tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
