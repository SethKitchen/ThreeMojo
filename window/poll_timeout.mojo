# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Checked duration conversion for the native poll boundary."""

from std.ffi import c_int
from std.math import isfinite
from units.si import Duration, SECOND


def poll_milliseconds(timeout: Duration) raises -> c_int:
    """Return a nonnegative native poll timeout, rounded down.

    Args:
        timeout: How long to wait. Zero does not wait.

    Returns:
        Whole milliseconds that fit the native signed integer.

    Raises:
        Error: If the timeout is negative, nonfinite, or too large.
    """
    # Widen before conversion so an exact second stays 1000 ms.
    var milliseconds = Float64(timeout.to(SECOND)) * 1000
    if milliseconds < 0:
        raise Error("A timeout must not be negative")
    if not isfinite(milliseconds) or milliseconds > Float64(Int32.MAX):
        raise Error("A timeout must be finite and fit native poll milliseconds")
    return c_int(milliseconds)
