# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A navigation area must be a `NavArea`, not a bare integer."""

from extensions.carla.navigation_mesh import flags_of


def main() raises:
    print(flags_of(1).value)
