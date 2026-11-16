# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An asset role must be an `AssetRole`, not a bare integer."""

from extensions.carla.assets import AssetRole


def main():
    var value: AssetRole = 0
    _ = value.is_valid()
