# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The reviewed Sum2 helper bindings stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._sum2_helper_bindings import sum2_helper_bindings


def _text(path: String) raises -> String:
    """Return one module.

    Args:
        path: The repository path.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path(path).read_text()


def test_the_sum2_helper_bindings_hold() raises:
    """The consumers import the reviewed helpers directly."""
    var lane = _text("extensions/carla/lane_geometry.mojo")
    var bounds = _text("extensions/carla/curve_bounds.mojo")
    var roundoff = _text("extensions/carla/spiral_roundoff_proof.mojo")
    var interval = _text("extensions/carla/curve_interval.mojo")
    sum2_helper_bindings(lane, bounds, roundoff, interval)
    sum2_helper_bindings(lane + "\n# reviewed\n", bounds, roundoff, interval)


def test_a_changed_sum2_helper_binding_is_refused() raises:
    """A changed import or a shadowing binding is refused."""
    var lane = _text("extensions/carla/lane_geometry.mojo")
    var bounds = _text("extensions/carla/curve_bounds.mojo")
    var roundoff = _text("extensions/carla/spiral_roundoff_proof.mojo")
    var interval = _text("extensions/carla/curve_interval.mojo")
    with assert_raises(
        contains="Sum2 direct helper import changed: lane_geometry"
    ):
        sum2_helper_bindings(
            lane.replace(
                (
                    "from extensions.carla.curve_sum2 import _sum2_update,"
                    " _require_sum2_environment"
                ),
                (
                    "from extensions.carla.curve_sum2 import"
                    " _require_sum2_environment, _sum2_update"
                ),
            ),
            bounds,
            roundoff,
            interval,
        )
    with assert_raises(
        contains="wildcard import can shadow reviewed helper: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\nfrom math import *\n", bounds, roundoff, interval
        )
    with assert_raises(
        contains="reviewed helper import alias shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\nfrom math import _sum2_update\n",
            bounds,
            roundoff,
            interval,
        )
    with assert_raises(
        contains="reviewed helper module alias shadows: _sum2_error"
    ):
        sum2_helper_bindings(
            lane,
            bounds,
            roundoff + "\nimport math as _sum2_error\n",
            interval,
        )
    with assert_raises(
        contains="reviewed helper declaration shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\ndef _sum2_update():\n    return\n",
            bounds,
            roundoff,
            interval,
        )
    with assert_raises(
        contains="reviewed helper assignment shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\nvar _sum2_update = 1\n", bounds, roundoff, interval
        )
    with assert_raises(
        contains="reviewed helper assignment shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\nfor _sum2_update in range(1):\n    return\n",
            bounds,
            roundoff,
            interval,
        )
    with assert_raises(
        contains="reviewed helper assignment shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\n_sum2_update += 1\n", bounds, roundoff, interval
        )
    with assert_raises(
        contains="reviewed helper assignment shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\n_sum2_update -= 1\n", bounds, roundoff, interval
        )
    with assert_raises(
        contains="reviewed helper parameter shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane + "\ndef _reviewed_shadow(_sum2_update: Int):\n    return\n",
            bounds,
            roundoff,
            interval,
        )
    with assert_raises(
        contains="reviewed helper exception binding shadows: _sum2_update"
    ):
        sum2_helper_bindings(
            lane
            + "\ntry:\n    pass\nexcept Error as _sum2_update:\n    return\n",
            bounds,
            roundoff,
            interval,
        )
    with assert_raises(contains="stored-half direct import changed"):
        sum2_helper_bindings(
            lane,
            bounds.replace(
                "_stored_half,",
                "_stored_half as stored_half,",
            ),
            roundoff,
            interval,
        )
    with assert_raises(
        contains="reviewed helper declaration shadows: _stored_half"
    ):
        sum2_helper_bindings(
            lane,
            bounds,
            roundoff,
            interval
            + "\ndef _stored_half(value: Float64):\n    return value\n",
        )


def main() raises:
    """Run the Sum2 helper binding tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
