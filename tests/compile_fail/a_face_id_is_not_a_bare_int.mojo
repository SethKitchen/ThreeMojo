# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A face id must be a `FaceId`, not a bare integer."""

from extensions.topology.ids import FaceId


def main():
    var id: FaceId = 0
    _ = id.is_valid()
