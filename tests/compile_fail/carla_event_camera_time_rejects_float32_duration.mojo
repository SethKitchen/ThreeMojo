# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An event camera's frame time must keep Float64, not a Float32 Duration."""

from extensions.carla.cameras import DVSCamera
from render.framebuffer import Framebuffer
from units.si import Duration, SECOND


def frame(mut camera: DVSCamera, image: Framebuffer) raises:
    _ = camera.simulate(image, Duration(1.0, SECOND))


def main() raises:
    pass
