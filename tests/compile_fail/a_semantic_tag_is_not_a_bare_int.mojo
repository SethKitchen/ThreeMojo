# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A semantic tag must be a `SemanticTag`, not a bare integer."""

from extensions.carla.sensor import cityscapes_color


def main() raises:
    var color = cityscapes_color(1)
    print(color.r)
