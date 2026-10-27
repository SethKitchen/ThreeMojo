# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the modules the sampled-value check reads first.

Bounds, trig, and the interval come first. The lane value module is last.
"""


def sampled_input_modules() -> String:
    """Return the four sampled input modules in reviewed order.

    Returns:
        A JSON list of file names.
    """
    return (
        '["curve_bounds.mojo","curve_trig.mojo","curve_interval.mojo",'
        + '"lane_value_bounds.mojo"]'
    )
