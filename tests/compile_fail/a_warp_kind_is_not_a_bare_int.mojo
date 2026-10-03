# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A proportion warp kind must be a `WarpKind`, not a bare integer."""

from extensions.sdf.vector import V3
from extensions.animals.warp import Warp, check_warp


def main() raises:
    var zero = V3(0.0, 0.0, 0.0)
    check_warp(Warp(0, 1.0, 0.0, 0.0, zero, zero, zero))
