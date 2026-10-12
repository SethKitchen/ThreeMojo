# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Require an explicit source-unit adapter for an arbitrary integer epoch."""

from extensions.carla.recorder import Recorder


def main() raises:
    var recorder = Recorder()
    _ = recorder.begin("", "epoch", False, 1234)
