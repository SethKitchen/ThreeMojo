# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A MODFLOW `InnerConvergence` is a type, not a bare integer."""

from extensions.groundwater.kinds import InnerConvergence


def main():
    var kind: InnerConvergence = 0
    _ = kind.is_valid()
