# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Medical image volumes for research visualization.

DICOM files become slices, and slices stack into a volume with physical
spacing. A ray caster draws a volume through a transfer function. Label
maps segment a volume, and overlays and measurements draw on its slices.
The package is not a medical device. See the wiki page Medical imaging.
"""
