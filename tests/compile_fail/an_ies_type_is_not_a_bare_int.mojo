# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the type an IES texture holds."""

from loaders.ies import IesLamp, ies_texture


def main() raises:
    var texture = ies_texture(IesLamp(), 2)
    print(texture.width)
