# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An edge id must be a `EdgeId`, not a bare integer."""

from extensions.topology.ids import EdgeId


def main():
    var id: EdgeId = 0
    _ = id.is_valid()
