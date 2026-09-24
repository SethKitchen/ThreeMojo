# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco attribute coding."""

from loaders.draco import DRACO_RAW


def main() raises:
    var coding = DRACO_RAW
    coding = 2
    print(coding.is_valid())
