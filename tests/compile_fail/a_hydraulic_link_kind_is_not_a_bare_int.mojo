# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pipe network kind must be a `LinkKind`, not a bare integer."""

from extensions.hydraulics.kinds import LinkKind


def main():
    var kind: LinkKind = 0
    _ = kind.is_valid()
