# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the kind of a tagged buffer."""

from extensions.streamline.tags import TaggedBuffer


def main():
    var buffer = TaggedBuffer(2, 64, 64, 2, False)
    print(buffer.width)
