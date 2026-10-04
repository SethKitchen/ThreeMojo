# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A section shape must be a `SectionShape`, not a bare integer."""

from extensions.building.kinds import SectionShape


def main():
    var id: SectionShape = 0
    _ = id.is_valid()
