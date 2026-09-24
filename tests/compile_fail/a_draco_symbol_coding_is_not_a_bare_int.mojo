# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco symbol coding."""

from exporters.draco_writer import DRACO_TAGGED_SYMBOLS


def main() raises:
    var coding = DRACO_TAGGED_SYMBOLS
    coding = 1
    print(coding.is_valid())
