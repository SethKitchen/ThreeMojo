# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A depth clipping side must be a named type, not an integer."""

from renderers.clip import _clip_plane, ClipVertex


def main():
    var polygon = _clip_plane[0](List[ClipVertex](), -1)
    print(len(polygon))
