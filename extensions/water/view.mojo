# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which picture Clearwater draws.

The page selects these with `?view=`. `FRAME` is the photograph. `CAUSTICS`
is the raw caustic texture. `LINEAR` skips glare and bloom. `GLARE` shows
the diffraction spikes on their own.
"""


@fieldwise_init
struct WaterView(Equatable, ImplicitlyCopyable, Writable):
    """Which Clearwater picture a frame is.

    The type stops a bare integer at compile time. A value outside the
    four names is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four pictures."""
        return self.value >= 0 and self.value <= GLARE.value


def require_view(view: WaterView) raises:
    """Refuse a picture that is not one of the four names.

    Args:
        view: The picture to check.

    Raises:
        Error: If `view` is not valid.
    """
    if not view.is_valid():
        raise Error("Water view must be frame, caustics, linear or glare")


# The graded photograph: water, glare, bloom and the tone curve.
comptime FRAME = WaterView(0)
# The caustic texture, scaled the way `?view=caus` scales it.
comptime CAUSTICS = WaterView(1)
# The water with the tone curve and without glare or bloom.
comptime LINEAR = WaterView(2)
# The diffraction spikes alone, as `?view=glare` draws them.
comptime GLARE = WaterView(3)
