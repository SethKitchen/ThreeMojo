# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a dimension mismatch at the lens_derivative configuration boundary."""

from extensions.carla.cameras import kannala_brandt_derivative
from units.si import Length


def main() raises:
    _ = kannala_brandt_derivative(Length(0), List[Float32]())
