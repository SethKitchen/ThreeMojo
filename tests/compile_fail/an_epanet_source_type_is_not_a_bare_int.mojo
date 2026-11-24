# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An EPANET source type must be a `SourceType`, not a bare integer."""

from extensions.epanet.kinds import SourceType


def main():
    var kind: SourceType = 0
    _ = kind.is_valid()
