# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An area must not silently pass where a length is wanted."""

from units.si import Area, Length, METRE


def describe(value: Length):
    print(value.value)


def main() raises:
    describe(Length(2.0, METRE) * Length(3.0, METRE))
