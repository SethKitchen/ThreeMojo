# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How developed the skeletal muscle of a humanoid is.

The two values scale muscle belly radius. They do not change bone length.
`UNTONED` is the smaller adult template. `TONED` is the hypertrophied
template. The scales are authored. They are not a cited CSA regression.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
"""


@fieldwise_init
struct Athleticism(Equatable, ImplicitlyCopyable, Writable):
    """Whether a humanoid uses the untoned or the toned muscle template.

    The type stops a bare integer at compile time. A value that is not
    `UNTONED` or `TONED` is still constructible, and the boundary that
    reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `UNTONED` or `TONED`."""
        return self == UNTONED or self == TONED


# Smaller adult muscle bellies. Authored radius scale 0.80.
comptime UNTONED = Athleticism(0)
# Hypertrophied adult muscle bellies. Authored radius scale 1.25.
comptime TONED = Athleticism(1)

comptime UNTONED_RADIUS = Float32(0.80)
comptime TONED_RADIUS = Float32(1.25)


def radius_scale(athleticism: Athleticism) raises -> Float32:
    """Return the authored belly-radius scale for `athleticism`.

    Args:
        athleticism: `UNTONED` or `TONED`.

    Returns:
        `0.80` for untoned muscle, `1.25` for toned muscle.

    Raises:
        Error: If `athleticism` is not named.
    """
    if not athleticism.is_valid():
        raise Error("Athleticism must be toned or untoned")
    if athleticism == TONED:
        return TONED_RADIUS
    return UNTONED_RADIUS
