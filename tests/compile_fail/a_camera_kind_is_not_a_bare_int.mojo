# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ground-truth image must be named by a `CameraKind`, not a bare
integer."""

from extensions.carla.cameras import CameraKind


def main():
    var kind: CameraKind = 3
    print(kind.is_valid())
