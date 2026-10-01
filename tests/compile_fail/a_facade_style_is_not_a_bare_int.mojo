# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A wall's look must be a `FacadeStyle`, not a bare integer."""

from extensions.carla.render_textures import facade_maps


def main() raises:
    print(facade_maps(1, 4).color.width)
