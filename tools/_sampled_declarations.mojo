# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Return the three inline sampled declarations.

These texts are the reviewed uncertain helper and the two lane value bounds.
"""

from tools._python_json import PyJson


def sampled_declarations() raises -> String:
    """Return the three sampled declarations.

    Returns:
        JSON with `_uncertain_value`, `_sampled_lane_value_bound`, and
        `_lane_value_bound`.

    Raises:
        Error: A declaration cannot be written.
    """
    var doc = PyJson()
    var result = doc.new_dict()
    doc.set(
        result,
        "_uncertain_value",
        doc.new_str(
            "def _uncertain_value(value: _Interval) -> _ValueJet:\n       "
            " return _uncertain_expression[False](value)\n    "
        ),
    )
    doc.set(
        result,
        "_sampled_lane_value_bound",
        doc.new_str(
            "def _sampled_lane_value_bound(\n            road: Road, section:"
            " Int, lane: Int, low: Float64, high: Float64\n        ) raises ->"
            " Tuple[_ValueJet, _ValueJet, _ValueJet]:\n            return"
            " _lane_value_bound_impl[False](road, section, lane, low,"
            " high)\n    "
        ),
    )
    doc.set(
        result,
        "_lane_value_bound",
        doc.new_str(
            "def _lane_value_bound(\n            road: Road, section: Int,"
            " lane: Int, low: Float64, high: Float64\n        ) raises ->"
            " Tuple[_ValueJet, _ValueJet, _ValueJet]:\n            var at ="
            " info_index(road.info.geometries, low)\n            if at >= 0 and"
            " road.info.geometries[at].geometry.kind == SPIRAL:\n              "
            "  var full = _lane_jet(road, section, lane, low, high)\n          "
            "      return (_without_derivatives(full[0]),"
            " _without_derivatives(full[1]),\n                       "
            " _without_derivatives(full[2]))\n            return"
            " _lane_value_bound_impl[True](road, section, lane, low,"
            " high)\n    "
        ),
    )
    doc.root = result
    return doc.dumps()
