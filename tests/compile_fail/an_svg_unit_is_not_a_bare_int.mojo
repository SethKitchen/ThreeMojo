# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an SVG unit."""

from loaders.svg import parse_svg


def main() raises:
    var data = parse_svg("<svg/>", 5)
    print(len(data.paths))
