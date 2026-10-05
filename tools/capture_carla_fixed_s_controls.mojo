# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Capture unchanged geometry seeds, not lane-query answers, for Fraction controls."""

from std.math import cos, sin
from std.memory import bitcast
from tests.carla_fixed_s_fixture import _fixed_geometry


def main() raises:
    for kind in range(5):
        for origin in [Float64(0), Float64(1000000001), Float64(-1000000001)]:
            for heading in [Float64(0.37), Float64(-1.2), Float64(2.3)]:
                var geometry = _fixed_geometry(kind, origin, heading)
                var point = geometry.pos_at(3.25)
                print(
                    kind,
                    bitcast[DType.uint64](origin),
                    bitcast[DType.uint64](heading),
                    bitcast[DType.uint64](point.x),
                    bitcast[DType.uint64](point.y),
                    bitcast[DType.uint64](sin(point.tangent)),
                    bitcast[DType.uint64](cos(point.tangent)),
                )
