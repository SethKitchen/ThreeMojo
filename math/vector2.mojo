# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A 2D vector, ported from three.js `src/math/Vector2.js`."""


@fieldwise_init
struct Vector2(ImplicitlyCopyable):
    """A point or direction in 2D space."""

    var x: Float32
    var y: Float32
