# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A face kind must be a `FaceKind`, not a bare integer."""

from extensions.topology.complex import FaceKind


def main():
    var id: FaceKind = 0
    _ = id.is_valid()
