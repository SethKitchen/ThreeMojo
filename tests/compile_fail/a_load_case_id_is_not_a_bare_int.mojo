# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A load case id must be a `LoadCaseId`, not a bare integer."""

from extensions.structure.ids import LoadCaseId


def main():
    var id: LoadCaseId = 0
    _ = id.is_valid()
