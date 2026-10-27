# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""The Sum2 helper imports and the stored-half function stay one check."""

from std.testing import TestSuite, assert_raises

from tools._python_json import PyJson
from tools._sum2_helper_bindings import sum2_import_batch


def _payload(
    lane: String, bounds: String, roundoff: String, interval: String
) raises -> String:
    """Return one import-batch payload.

    Args:
        lane: The lane module.
        bounds: The bounds module.
        roundoff: The roundoff module.
        interval: The interval module.

    Returns:
        JSON for `sum2_import_batch`.

    Raises:
        Error: The payload cannot be written.
    """
    var doc = PyJson()
    var root = doc.new_dict()
    var texts = doc.new_dict()
    doc.set(texts, "lane_geometry", doc.new_str(lane))
    doc.set(texts, "curve_bounds", doc.new_str(bounds))
    doc.set(texts, "spiral_roundoff_proof", doc.new_str(roundoff))
    doc.set(root, "texts", texts)
    doc.set(root, "interval", doc.new_str(interval))
    doc.root = root
    return doc.dumps()


def test_reviewed_sum2_imports_and_stored_half_pass() raises:
    """Direct helper imports and one stored-half function are accepted."""
    sum2_import_batch(
        _payload(
            (
                "from extensions.carla.curve_sum2 import _sum2_update,"
                " _require_sum2_environment\n"
            ),
            (
                "from extensions.carla.curve_sum2 import _sum2_error_checked,"
                " _sum2_supported_environment\nfrom"
                " extensions.carla.curve_interval import _stored_half\n"
            ),
            "from extensions.carla.curve_sum2 import _sum2_error\n",
            "def _stored_half():\n    return 1\n",
        )
    )


def test_a_missing_stored_half_is_refused() raises:
    """The interval must declare `_stored_half` once."""
    with assert_raises(contains="missing or ambiguous function: _stored_half"):
        _ = sum2_import_batch(
            _payload(
                (
                    "from extensions.carla.curve_sum2 import _sum2_update,"
                    " _require_sum2_environment\n"
                ),
                (
                    "from extensions.carla.curve_sum2 import"
                    " _sum2_error_checked, _sum2_supported_environment\nfrom"
                    " extensions.carla.curve_interval import _stored_half\n"
                ),
                "from extensions.carla.curve_sum2 import _sum2_error\n",
                "def other():\n    return 1\n",
            )
        )


def main() raises:
    """Run the Sum2 import batch tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
