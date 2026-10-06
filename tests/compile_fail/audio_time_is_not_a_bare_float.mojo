# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The authoritative audio clock carries a time unit."""
from extensions.humanoid.skeleton.head.aligned_speech import AlignedSpeech
from units.si import Duration


def main() raises:
    var speech = AlignedSpeech("test", Duration(1), [])
    _ = speech.sample(0.5)
