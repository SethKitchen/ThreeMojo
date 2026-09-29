# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A V2X path state must be a `PathState`, not a bare integer."""

from extensions.carla.v2x import PathLossModel, PropagationParams


def main() raises:
    var model = PathLossModel(PropagationParams())
    print(model.winner(0, 100.0))
