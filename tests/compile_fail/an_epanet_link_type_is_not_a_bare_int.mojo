# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An EPANET link type must be a `LinkType`, not a bare integer."""

from extensions.epanet.kinds import LinkType


def main():
    var kind: LinkType = 0
    _ = kind.is_valid()
