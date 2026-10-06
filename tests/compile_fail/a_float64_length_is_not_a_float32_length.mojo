# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A `Float64` length does not mix with a `Float32` one without a cast."""

from units.si import Length, Length64, METER


def main():
    var precise = Length64(1.0, METER)
    var coarse = Length(1.0, METER)
    _ = precise + coarse
