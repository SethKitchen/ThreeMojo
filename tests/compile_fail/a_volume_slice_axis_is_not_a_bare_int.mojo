# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A volume slice axis must be a `SliceAxis`, not a bare integer."""

from extensions.imaging.ids import require_axis


def main() raises:
    require_axis(0)
