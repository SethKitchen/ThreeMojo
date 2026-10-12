# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Checked scalar extraction at CARLA's dimensional API boundaries.

These private helpers do not convert units or change precision. Storage and
serialized compatibility records retain their existing scalar layouts.
"""

from std.math import isfinite


@fieldwise_init
struct _RawSI(ImplicitlyCopyable):
    var marker: Bool


comptime _RAW_SI = _RawSI(True)


def _finite_si(value: Float64) raises -> Float64:
    if not isfinite(value):
        raise Error("A dimensional value must be finite")
    return value


def _nonnegative_si(value: Float64) raises -> Float64:
    if not isfinite(value) or value < 0.0:
        raise Error("A dimensional value must be finite and nonnegative")
    return value


def _positive_si(value: Float64) raises -> Float64:
    if not isfinite(value) or value <= 0.0:
        raise Error("A dimensional value must be finite and positive")
    return value
