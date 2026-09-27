# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare int must not stand in for a wood's genus: say which with its
named constant."""

from materials.wood import GLOSS, TEAK, wood_preset


def main() raises:
    var params = wood_preset(3, GLOSS)
    print(params.clearcoat)
