# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a humanoid is, as far as the body's layers need to know.

Each bone reads stature and sex from this spec and sizes itself. Each
muscle also reads athleticism and scales its belly radius. The other
layers reuse those landmarks. The genome sets the heritable traits:
skin tone, the frame's proportions and the shape of the face. Age is
not a field yet. Long-bone templates invert the Trotter and Gleser 1952 American
White adult lines. That is a named choice, not
a unique measurement for a person of that stature.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var athlete = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    var cousin = HumanoidSpec(
        Length(6.0, FOOT), MALE, TONED, random_genome(7)
    )
    var bone = femur(person)

The accepted stature interval is 1.2 m through 2.5 m. That is the
software range. It is not the calibration range of the 1952 sample.
"""

from extensions.humanoid.athleticism import UNTONED, Athleticism
from extensions.humanoid.genome import Genome
from extensions.humanoid.sex import Sex
from units.si import Length, METER

# Software range for a stature argument. This is not the calibration
# range of the 1952 sample.
comptime MIN_STATURE = Length(1.2, METER)
comptime MAX_STATURE = Length(2.5, METER)


struct HumanoidSpec(ImplicitlyCopyable):
    """Standing height, osteological sex, muscle athleticism and genome.

    The constructor stores `UNTONED` and the template genome unless it
    is given others. The constructor does not refuse a bad sex, a bad
    athleticism, a bad genome, or a stature outside the software range.
    The bone or muscle that reads the spec does that, the same way a
    `Material` can hold a kind that `is_valid` then rejects.
    """

    var stature: Length
    var sex: Sex
    var athleticism: Athleticism
    var genome: Genome

    def __init__(
        out self,
        stature: Length,
        sex: Sex,
        athleticism: Athleticism = UNTONED,
        genome: Genome = Genome(),
    ):
        """Store stature, sex, athleticism and genome.

        Args:
            stature: Standing height.
            sex: Osteological template.
            athleticism: Muscle template, `UNTONED` by default.
            genome: Heritable traits, the template genome by default.
        """
        self.stature = stature
        self.sex = sex
        self.athleticism = athleticism
        self.genome = genome
