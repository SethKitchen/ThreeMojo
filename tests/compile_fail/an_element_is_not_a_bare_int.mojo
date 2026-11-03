# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An element must be an `Element`, not a bare atomic number."""

from extensions.chemistry.elements import Element


def main():
    var element: Element = 22
    _ = element.is_valid()
