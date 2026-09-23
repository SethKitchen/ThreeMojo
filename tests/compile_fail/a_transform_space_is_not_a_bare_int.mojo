# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a transform space."""

from controls.transform_controls import TransformControls


def main() raises:
    var controls = TransformControls()
    controls.space = 1
    print(controls.enabled)
