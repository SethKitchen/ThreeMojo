# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the moment dependency record and the check messages.

The live path list still follows the canonical accumulation group. This plan
only names the fixed record and the messages each check reports.
"""


def moment_check_plan() -> String:
    """Return the moment dependency record and the check messages.

    Returns:
        JSON with the record fields, the array names, and the messages.
    """
    return (
        '{"group":"stored_arithmetic",'
        + '"pin_file":"tools/carla_lane_oracle/runtime-source-pins.json",'
        + '"interval":"extensions/carla/curve_interval.mojo",'
        + '"additional_groups":["canonical_accumulation"],'
        + '"arrays":["_GL_NODES","_GL_WEIGHTS","_COS_COEFFICIENTS","_SIN_COEFFICIENTS"],'
        + '"nodes":"_GL_NODES","weights":"_GL_WEIGHTS","ideal_caller":"ideal_caller",'
        + '"messages":{"stored_words":"stored constant words changed: ",'
        + '"invalid_word":"invalid UInt64 word",'
        + '"array_set":"wrong constant-array set",'
        + '"overflow":"binary64 overflow",'
        + '"scalar_word":"stored scalar word changed: ",'
        + '"routing_pin":"inconsistent routing pin: ",'
        + '"routing":"source routing changed: ",'
        + '"closure":"stored-half dependency closure: ",'
        + '"projection":"ideal half projection: ",'
        + '"node_sums":"rounded 1 + node words changed",'
        + '"utf8":"table is not UTF-8"}}'
    )
