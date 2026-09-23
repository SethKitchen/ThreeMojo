# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a transform event kind."""

from controls.transform_controls import (
    HANDLE_X,
    TRANSLATE_MODE,
    TransformEvent,
)


def main():
    var event = TransformEvent(3, TRANSLATE_MODE, HANDLE_X, False)
    print(event.dragging)
