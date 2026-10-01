# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A V2X loss model must be a `PathLossKind`, not a bare integer."""

from extensions.carla.v2x import PropagationParams


def main():
    var params = PropagationParams()
    params.model = 0
    print(params.model.is_valid())
