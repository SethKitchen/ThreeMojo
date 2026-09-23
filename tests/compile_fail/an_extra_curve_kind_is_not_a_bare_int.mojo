# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for which named curve to make."""

from math.curve_extras import ExtraCurve


def main() raises:
    var bad = ExtraCurve(6, 10)
    print(bad.scale)
