# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A radio distance is a Length64, not a Duration64."""

from extensions.carla.v2x import PathLossModel
from units.si import Duration64, Length64


def loss(model: PathLossModel) -> Float32:
    return model.two_ray_simple(Duration64(1.0), Length64(1.5), Length64(1.5))


def main():
    pass
