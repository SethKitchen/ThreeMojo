# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a humanoid is, as far as the bones need to know.

Each bone reads stature and sex from this spec and sizes itself. Age,
build and population are not fields yet. Long-bone templates invert the
Trotter and Gleser 1952 American White adult lines. That is a named
choice, not a unique measurement for a person of that stature.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = femur(person)

The accepted stature interval is 1.2 m through 2.5 m. That is the
software range. It is not the calibration range of the 1952 sample.
"""

from extensions.humanoid.sex import Sex
from units.si import Length, METER

# Software range for a stature argument. This is not the calibration
# range of the 1952 sample.
comptime MIN_STATURE = Length(1.2, METER)
comptime MAX_STATURE = Length(2.5, METER)


@fieldwise_init
struct HumanoidSpec(ImplicitlyCopyable):
    """Standing height and osteological sex of an adult humanoid.

    The constructor does not refuse a bad sex or a stature outside the
    software range. The bone that reads the spec does that, the same way a
    `Material` can hold a kind that `is_valid` then rejects.
    """

    var stature: Length
    var sex: Sex
