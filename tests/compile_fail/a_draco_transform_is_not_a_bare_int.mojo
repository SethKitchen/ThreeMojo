# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco prediction transform."""

from loaders.draco_attributes import PredictionTransform


def main() raises:
    var transform = PredictionTransform(1, 3)
    print(transform.positive())
