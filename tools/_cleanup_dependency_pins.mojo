# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the two reviewed stored-word dependencies.

Only trig and geometry may keep their stored words after a token change.
"""


def cleanup_dependency_pins() -> String:
    """Return the trig and geometry paths and token digests.

    Returns:
        JSON with `trig_path`, `trig_token`, `geometry_path`, and
        `geometry_token` in that order.
    """
    return (
        '{"trig_path":"extensions/carla/curve_trig.mojo",'
        + '"trig_token":"523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f",'
        + '"geometry_path":"extensions/carla/geometry.mojo",'
        + '"geometry_token":"a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb"}'
    )
