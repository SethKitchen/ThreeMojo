# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the kind of a VRML field value."""

from loaders.vrml_parse import VrmlValue


def main() raises:
    var value = VrmlValue(3)
    print(value.number)
