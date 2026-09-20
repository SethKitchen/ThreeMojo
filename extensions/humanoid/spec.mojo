# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a humanoid is, as far as the bones and muscles need to know.

Each bone reads stature and sex from this spec and sizes itself. Each
muscle also reads athleticism and scales its belly radius. Age and
population are not fields yet. Long-bone templates invert the Trotter
and Gleser 1952 American White adult lines. That is a named choice, not
a unique measurement for a person of that stature.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var athlete = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var bone = femur(person)

The accepted stature interval is 1.2 m through 2.5 m. That is the
software range. It is not the calibration range of the 1952 sample.
"""

from extensions.humanoid.athleticism import UNTONED, Athleticism
from extensions.humanoid.sex import Sex
from units.si import Length, METER

# Software range for a stature argument. This is not the calibration
# range of the 1952 sample.
comptime MIN_STATURE = Length(1.2, METER)
comptime MAX_STATURE = Length(2.5, METER)


@fieldwise_init
struct HumanoidSpec(ImplicitlyCopyable):
    """Standing height, osteological sex and muscle athleticism.

    The two-argument constructor stores `UNTONED`. The constructor does
    not refuse a bad sex, a bad athleticism, or a stature outside the
    software range. The bone or muscle that reads the spec does that,
    the same way a `Material` can hold a kind that `is_valid` then
    rejects.
    """

    var stature: Length
    var sex: Sex
    var athleticism: Athleticism

    def __init__(out self, stature: Length, sex: Sex):
        """Store stature and sex with untoned muscle.

        Args:
            stature: Standing height.
            sex: Osteological template.
        """
        self.stature = stature
        self.sex = sex
        self.athleticism = UNTONED
