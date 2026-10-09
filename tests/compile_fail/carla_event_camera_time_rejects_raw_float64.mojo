# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An event camera's frame time must be a Duration64, not a raw Float64."""

from extensions.carla.cameras import DVSCamera
from render.framebuffer import Framebuffer


def frame(mut camera: DVSCamera, image: Framebuffer) raises:
    _ = camera.simulate(image, Float64(1.0))


def main() raises:
    pass
