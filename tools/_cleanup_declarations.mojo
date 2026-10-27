# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the reviewed cleanup declarations and the junction path.

The live texts still come from the three successor sources. This list only
says which declaration each premise checks.
"""


def cleanup_declarations() -> String:
    """Return the cleanup declarations, the junction path, and the label.

    Returns:
        JSON with `junction`, `unreviewed`, and `declarations` in that order.
    """
    return (
        '{"junction":"extensions/carla/junction_bounds.mojo",'
        + '"unreviewed":"unreviewed complete successor: ",'
        + '"declarations":['
        + '{"source":0,"name":"_rounded_line_axis_context","owner":[],"key":"line"},'
        + '{"source":1,"name":"_rounded_arc_context","owner":[],"key":"arc"},'
        + '{"source":1,"name":"bounds","owner":["_RoundedBox"],"key":"bounds"},'
        + '{"source":1,"name":"center","owner":["_RoundedArc"],"key":"center"},'
        + '{"source":2,"name":"_outward_float","owner":[],"key":"outward"}]}'
    )
