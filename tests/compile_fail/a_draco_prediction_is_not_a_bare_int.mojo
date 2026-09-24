# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco prediction."""

from loaders.draco_attributes import (
    DRACO_WRAP,
    PredictionScheme,
    PredictionTransform,
)


def main() raises:
    var scheme = PredictionScheme(1, PredictionTransform(DRACO_WRAP, 3))
    print(scheme.needs_positions())
