# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a precision mismatch at the lens_polynomial configuration boundary."""

from extensions.carla.cameras import kannala_brandt_polynomial
from units.si import Angle64


def main() raises:
    _ = kannala_brandt_polynomial(Angle64(0), List[Float32]())
