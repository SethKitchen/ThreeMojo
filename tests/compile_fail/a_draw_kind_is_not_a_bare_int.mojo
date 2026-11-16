# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A draw kind must be a `DrawKind`, not a bare integer."""

from render.rasterizer import DrawKind


def main():
    var value: DrawKind = 0
    _ = value.is_valid()
