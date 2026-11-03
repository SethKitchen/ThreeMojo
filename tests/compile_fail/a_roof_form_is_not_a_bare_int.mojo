# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A roof form must be a `RoofForm`, not a bare integer."""

from extensions.castle.kinds import RoofForm


def main():
    var id: RoofForm = 0
    _ = id.is_valid()
