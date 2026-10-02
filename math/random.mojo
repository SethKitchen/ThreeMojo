# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Bit-exact random arithmetic shared by three.js and extensions."""


def mulberry32_step(mut state: UInt32) -> Float64:
    """Advance one Mulberry32 state and return its next uniform sample.

    Args:
        state: The current 32-bit state, advanced modulo 2^32.

    Returns:
        The next sample in `[0, 1)`, with JavaScript's `Math.imul` and
        unsigned-shift arithmetic.
    """
    state = state + 0x6D2B79F5
    var t = state
    t = (t ^ (t >> 15)) * (t | 1)
    t ^= t + (t ^ (t >> 7)) * (t | 61)
    return Float64(t ^ (t >> 14)) / 4294967296.0
