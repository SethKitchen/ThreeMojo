# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco attribute element."""

from loaders.draco import DRACO_VERTEX


def main() raises:
    var element = DRACO_VERTEX
    element = 1
    print(element.is_valid())
