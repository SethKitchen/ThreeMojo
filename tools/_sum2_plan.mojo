# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the Sum2 modules and the reviewed caller comparisons.

The live texts still come from the repository. This plan only says which
module and which checkpoint each comparison uses.
"""


def sum2_plan() -> String:
    """Return the Sum2 module names, caller comparisons, and helper map.

    Returns:
        JSON with `modules`, `graphs`, and `helpers` in that order. The
        helper digest follows those fields.
    """
    return (
        '{"modules":["curve_sum2","lane_geometry","curve_bounds","spiral_roundoff_proof"],'
        + '"graphs":['
        + '{"module":"curve_sum2","slice":"_sum2_update","left_name":"_sum2_update","checkpoint":"helper","right_name":"_sum2_update","message":"Sum2'
        ' recurrence changed"},'
        + '{"module":"curve_sum2","slice":"_sum2_error_checked","left_name":"_sum2_error_checked","checkpoint":"helper","right_name":"_sum2_error","message":"Sum2'
        ' checked arithmetic leaf changed","rename":"_sum2_error"},'
        + '{"module":"lane_geometry","left_name":"_lane_spiral","checkpoint":"scalar","right_name":"_lane_spiral","message":"Sum2'
        " complete caller graph changed:"
        ' _lane_spiral","drop_first":true,"expect_first":"_require_sum2_environment()"},'
        + '{"module":"spiral_roundoff_proof","left_name":"_sum2_envelope_error","checkpoint":"envelope","right_name":"_sum2_envelope_error","message":"Sum2'
        ' complete caller graph changed: _sum2_envelope_error"},'
        + '{"module":"spiral_roundoff_proof","left_name":"_try_spiral_roundoff_envelope","checkpoint":"eligibility","right_name":"_try_spiral_roundoff_envelope","message":"Sum2'
        ' complete caller graph changed: _try_spiral_roundoff_envelope"}'
        + '],"helpers":{"lane":"lane_geometry","bounds":"curve_bounds","roundoff":"spiral_roundoff_proof"},'
        + '"stored_half":"_stored_half","half_key":"bounds","interval_key":"interval",'
        + '"spiral_begin":"def _spiral_expression[","spiral_end":"def'
        ' _sample_index(",'
        + '"helper_sha":"41995592963bae61a2b690b465bdad6c759b02ddbe98141ba5da30d0df5d5c8e"}'
    )
