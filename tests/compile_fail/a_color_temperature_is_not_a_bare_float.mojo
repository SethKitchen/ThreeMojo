# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare float must not stand in for a color temperature: say its scale
with `Temperature(6500, KELVIN)`."""

from render.color_utils import kelvin_color


def main() raises:
    print(kelvin_color(6500.0).r)
