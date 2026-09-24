# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the kind of a VRML token."""

from loaders.vrml_parse import VrmlToken


def main() raises:
    var token = VrmlToken(3, "USE", 0)
    print(token.offset)
