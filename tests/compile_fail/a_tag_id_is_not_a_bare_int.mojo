# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A sculpt tag must be a `TagId`, not a bare integer."""

from extensions.sdf.field import SdfModel


def main() raises:
    var m = SdfModel()
    _ = m.tag_name(0)
