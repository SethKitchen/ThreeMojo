# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A coat surface class must be a `SurfaceClass`, not a bare integer."""

from extensions.animals.coat import Paint
from extensions.sdf.vector import V3


def main() raises:
    _ = Paint(V3(0.0, 0.0, 0.0), 0)
