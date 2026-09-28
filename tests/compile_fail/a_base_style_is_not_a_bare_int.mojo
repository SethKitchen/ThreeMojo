# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a skyscraper's ground floor: say
`ARCADE` or `STOREFRONT`."""

from generators.skyscraper import SkyscraperParameters


def main() raises:
    var p = SkyscraperParameters()
    p.base_style = 0
    print(p.seed)
