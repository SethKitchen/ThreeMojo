# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""NVIDIA Streamline's DLSS Super Resolution and Ray Reconstruction.

This package is the part of the integration that needs no graphics device:
the typed modes and presets, the options, the render size and jitter, the
per-frame constants, the check of a frame's tagged buffers, and an upscaler
trait with a CPU fallback. It does not load Streamline. See
`docs/wiki/Streamline.md` for what a native binding still needs.
"""
