# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The reviewed Sum2 helper bindings stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._sum2_helper_bindings import (
    sum2_half_import_checks,
    sum2_helper_bindings,
    sum2_helper_import_checks,
)


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


def _import_lane() -> String:
    """Return one reviewed lane import.

    Returns:
        The import text.
    """
    return (
        "from extensions.carla.curve_sum2 import _sum2_update,"
        " _require_sum2_environment\nfrom math import sin\n"
    )


def _import_bounds() -> String:
    """Return one reviewed bounds import.

    Returns:
        The import text.
    """
    return (
        "from math import sin\n"
        "from extensions.carla.curve_sum2 import _sum2_error_checked,"
        " _sum2_supported_environment\n"
        "from extensions.carla.curve_interval import _other, _stored_half\n"
    )


def _import_roundoff() -> String:
    """Return one reviewed roundoff import.

    Returns:
        The import text.
    """
    return "from extensions.carla.curve_sum2 import _sum2_error\n"


def _import_interval() -> String:
    """Return one stored-half definition.

    Returns:
        The definition text.
    """
    return "def _stored_half(value: Float64) -> Float64:\n    return value\n"


def test_the_sum2_import_inventory_holds() raises:
    """The live modules and a direct import list pass."""
    var lane = _text("extensions/carla/lane_geometry.mojo")
    var bounds = _text("extensions/carla/curve_bounds.mojo")
    var roundoff = _text("extensions/carla/spiral_roundoff_proof.mojo")
    var interval = _text("extensions/carla/curve_interval.mojo")
    sum2_helper_import_checks(lane, bounds, roundoff)
    sum2_half_import_checks(bounds, interval)
    sum2_helper_import_checks(
        _import_lane(), _import_bounds(), _import_roundoff()
    )
    sum2_half_import_checks(_import_bounds(), _import_interval())
    sum2_helper_import_checks(
        _import_lane()
        + "def later():\n    from extensions.carla.curve_sum2 import"
        " _sum2_update\n",
        _import_bounds(),
        _import_roundoff(),
    )


def test_a_changed_sum2_import_inventory_is_refused() raises:
    """A changed import list or a shadow is refused in source order."""
    var lane = _import_lane()
    var bounds = _import_bounds()
    var roundoff = _import_roundoff()
    var interval = _import_interval()
    with assert_raises(
        contains="Sum2 direct helper import changed: lane_geometry"
    ):
        sum2_helper_import_checks("from math import sin\n", bounds, roundoff)
    with assert_raises(
        contains="Sum2 direct helper import changed: lane_geometry"
    ):
        sum2_helper_import_checks(lane + lane, bounds, roundoff)
    with assert_raises(
        contains="Sum2 direct helper import changed: lane_geometry"
    ):
        sum2_helper_import_checks(
            (
                "from extensions.carla.curve_sum2 import"
                " _require_sum2_environment, _sum2_update\n"
            ),
            bounds,
            roundoff,
        )
    with assert_raises(
        contains="Sum2 direct helper import changed: lane_geometry"
    ):
        sum2_helper_import_checks(
            (
                "from extensions.carla.curve_sum2 import _sum2_update as other,"
                " _require_sum2_environment\n"
            ),
            bounds,
            roundoff,
        )
    with assert_raises(
        contains="Sum2 direct helper import changed: lane_geometry"
    ):
        sum2_helper_import_checks(
            "from extensions.carla.curve_sum2 import _sum2_update\n",
            bounds,
            roundoff,
        )
    with assert_raises(contains="invalid source tokens: unclosed string"):
        sum2_helper_import_checks('"', bounds, roundoff)
    with assert_raises(
        contains="wildcard import can shadow reviewed helper: _sum2_update"
    ):
        sum2_helper_import_checks(
            lane + "from math import *\n", bounds, roundoff
        )
    with assert_raises(
        contains="reviewed helper assignment shadows: _require_sum2_environment"
    ):
        sum2_helper_import_checks(
            lane + "var _require_sum2_environment = 1\n", bounds, roundoff
        )
    with assert_raises(
        contains="Sum2 direct helper import changed: curve_bounds"
    ):
        sum2_helper_import_checks(
            lane,
            "from extensions.carla.curve_sum2 import _sum2_error_checked\n",
            roundoff,
        )
    with assert_raises(
        contains="reviewed helper import alias shadows: _sum2_error_checked"
    ):
        sum2_helper_import_checks(
            lane,
            bounds + "from math import _sum2_error_checked\n",
            roundoff,
        )
    with assert_raises(
        contains=(
            "reviewed helper assignment shadows: _sum2_supported_environment"
        )
    ):
        sum2_helper_import_checks(
            lane,
            bounds + "var _sum2_supported_environment = 1\n",
            roundoff,
        )
    with assert_raises(
        contains="Sum2 direct helper import changed: spiral_roundoff_proof"
    ):
        sum2_helper_import_checks(lane, bounds, "from math import sin\n")
    with assert_raises(
        contains="reviewed helper declaration shadows: _sum2_error"
    ):
        sum2_helper_import_checks(
            lane, bounds, roundoff + "def _sum2_error():\n    return\n"
        )
    with assert_raises(contains="stored-half direct import changed"):
        sum2_half_import_checks("from math import sin\n", interval)
    with assert_raises(contains="stored-half direct import changed"):
        sum2_half_import_checks(
            (
                "from extensions.carla.curve_interval import _stored_half\n"
                "from extensions.carla.curve_interval import _stored_half\n"
            ),
            interval,
        )
    with assert_raises(contains="stored-half direct import changed"):
        sum2_half_import_checks("from math import _stored_half\n", interval)
    with assert_raises(contains="stored-half direct import changed"):
        sum2_half_import_checks(
            (
                "from extensions.carla.curve_interval import _stored_half as"
                " stored_half\n"
            ),
            interval,
        )
    with assert_raises(contains="stored-half direct import changed"):
        sum2_half_import_checks(
            (
                "from extensions.carla.curve_interval import other as"
                " _stored_half\n"
            ),
            interval,
        )
    with assert_raises(contains="stored-half direct import changed"):
        sum2_half_import_checks(
            (
                "from extensions.carla.curve_interval import _stored_half,"
                " _stored_half\n"
            ),
            interval,
        )
    with assert_raises(
        contains="reviewed helper assignment shadows: _stored_half"
    ):
        sum2_half_import_checks(
            _import_bounds() + "var _stored_half = 1\n", interval
        )
    with assert_raises(
        contains="reviewed helper declaration shadows: _stored_half"
    ):
        sum2_half_import_checks(
            _import_bounds(),
            interval
            + "def _stored_half(value: Float64) -> Float64:\n    return"
            " value\n",
        )


def main() raises:
    """Run the Sum2 helper binding tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
