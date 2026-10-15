# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Capture unchanged geometry seeds, not lane-query answers, for Fraction controls."""

from std.math import cos, sin
from std.memory import bitcast
from tests.carla_fixed_s_fixture import _fixed_geometry
from units.si import Length64


def capture() raises -> String:
    """Return the geometry seeds of all five kinds, one case per line.

    Each line holds the kind, the origin and heading bits, and the bits of
    x, y and the sine and cosine of the tangent at s = 3.25, in decimal.

    Returns:
        The capture text, with a final newline.

    Raises:
        Error: If a geometry cannot be built, which it must not.
    """
    var out = String()
    for kind in range(5):
        for origin in [Float64(0), Float64(1000000001), Float64(-1000000001)]:
            for heading in [Float64(0.37), Float64(-1.2), Float64(2.3)]:
                var geometry = _fixed_geometry(kind, origin, heading)
                var point = geometry.pos_at(Length64(3.25))
                var words: List[UInt64] = [
                    bitcast[DType.uint64](origin),
                    bitcast[DType.uint64](heading),
                    bitcast[DType.uint64](point.x),
                    bitcast[DType.uint64](point.y),
                    bitcast[DType.uint64](sin(point.tangent)),
                    bitcast[DType.uint64](cos(point.tangent)),
                ]
                out += String(kind)
                for word in words:
                    out += " " + String(word)
                out += "\n"
    return out^


def main() raises:
    """Print the capture.

    Raises:
        Error: If a geometry cannot be built, which it must not.
    """
    print(capture(), end="")
