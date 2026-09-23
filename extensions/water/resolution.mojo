# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Power-of-two grid sizes for the ocean spectrum and the glare FFT."""


@fieldwise_init
struct SpectrumResolution(Equatable, ImplicitlyCopyable, Writable):
    """How many texels share one side of a spectrum or glare grid.

    Clearwater's ocean uses 256. A test can use a smaller power of two.
    The type stops a bare integer at compile time. A value that is not a
    power of two from 4 through 256 is still constructible, and the
    boundary that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a power of two from 4 through 256."""
        if self.value < 4 or self.value > 256:
            return False
        return (self.value & (self.value - 1)) == 0


def require_resolution(resolution: SpectrumResolution) raises:
    """Refuse a resolution that is not a named grid size.

    Args:
        resolution: The grid size to check.

    Raises:
        Error: If `resolution` is not valid.
    """
    if not resolution.is_valid():
        raise Error("Spectrum resolution must be a power of two from 4 to 256")


def log2_resolution(resolution: SpectrumResolution) raises -> Int:
    """Return how many radix-2 stages this grid needs.

    Args:
        resolution: A valid spectrum resolution.

    Returns:
        The base-2 logarithm of the side length.

    Raises:
        Error: If `resolution` is not valid.
    """
    require_resolution(resolution)
    var n = resolution.value
    var stages = 0
    while n > 1:
        n >>= 1
        stages += 1
    return stages
