# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A junction id must be a `JuncId`, not a bare integer."""

from extensions.carla.map import Junction


def main() raises:
    var junction = Junction(1, "center")
    print(junction.name)
