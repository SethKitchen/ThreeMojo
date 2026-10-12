# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A radio distance must keep Float64, not a Float32 Length."""

from extensions.carla.v2x import PathLossModel
from units.si import Length, Length64, METER


def loss(model: PathLossModel) -> Float64:
    return model.two_ray(Length(1.0, METER), Length64(1.5), Length64(1.5))


def main():
    pass
