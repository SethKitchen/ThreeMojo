# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an ASTC color endpoint mode."""

from render.uastc_hdr import decode_endpoints


def main() raises:
    var ends = decode_endpoints(0, [10, 200])
    print(len(ends))
