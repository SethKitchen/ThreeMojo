# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A width in the world is a `Length`, not a bare float in meters."""

from materials.material import LineWidth


def main() raises:
    var width = LineWidth(world=0.1)
    print(width.size)
