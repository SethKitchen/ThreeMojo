# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a sculptor's event kind."""

from geometries.sculptor import SCULPT_END, SculptorEventKind


def main() raises:
    var kind: SculptorEventKind = 2
    print(kind == SCULPT_END)
