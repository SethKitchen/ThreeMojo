# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A region id must be a `RegionId`, not a bare integer."""

from extensions.topology.ids import RegionId


def main():
    var id: RegionId = 0
    _ = id.is_valid()
