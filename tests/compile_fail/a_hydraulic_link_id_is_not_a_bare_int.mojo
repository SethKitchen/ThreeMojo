# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pipe network link must be a `LinkId`, not a bare integer."""

from extensions.hydraulics.kinds import LinkId


def main():
    var link: LinkId = 0
    _ = link.is_valid()
