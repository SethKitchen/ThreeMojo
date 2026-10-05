# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Aligned phonemes require a typed Phoneme label."""
from extensions.humanoid.skeleton.head.aligned_speech import phoneme_viseme


def main() raises:
    _ = phoneme_viseme("AA")
