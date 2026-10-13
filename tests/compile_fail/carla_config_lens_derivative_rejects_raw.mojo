# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a raw mismatch at the lens_derivative configuration boundary."""

from extensions.carla.cameras import kannala_brandt_derivative


def main() raises:
    _ = kannala_brandt_derivative(Float32(0), List[Float32]())
