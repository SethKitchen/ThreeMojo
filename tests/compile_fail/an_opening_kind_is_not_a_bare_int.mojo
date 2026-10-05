# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An opening kind must be a `OpeningKind`, not a bare integer."""

from extensions.building.kinds import OpeningKind


def main():
    var id: OpeningKind = 0
    _ = id.is_valid()
