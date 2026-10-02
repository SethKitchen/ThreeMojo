# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An unknown typed side must be refused even for an empty polygon."""

from renderers.clip import _DepthClipSide, _clip_plane, ClipVertex


def main():
    var polygon = _clip_plane[_DepthClipSide(-1)](List[ClipVertex](), -1)
    print(len(polygon))
