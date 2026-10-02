# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An unknown typed side must not select a depth predicate."""

from renderers.clip import _DepthClipSide, _inside


def main():
    print(_inside[_DepthClipSide(2)](-1, -1))
