# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a KTX 2.0 supercompression
scheme."""

from render.ktx2 import KTX2Container


def main():
    var container = KTX2Container()
    container.supercompression = 3
    print(container.supercompression)
