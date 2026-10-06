# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A flow direction must be a `FlowDirection`, not a bare integer."""

from extensions.building.construction import FlowDirection


def main():
    var id: FlowDirection = 0
    _ = id.is_valid()
