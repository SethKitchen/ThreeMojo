# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a humanoid is, as far as the bones need to know.

A later pass will take this spec and scale every bone. Today the femur
reads stature and sex from it. Age, build and population are not fields
yet. The named default is the inverted Trotter and Gleser 1952 American
White adult line. That is a template choice, not a unique measurement
for a person of that stature.

    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = femur(person)
"""

from extensions.humanoid.sex import Sex
from units.si import Length


@fieldwise_init
struct HumanoidSpec(ImplicitlyCopyable):
    """Standing height and osteological sex of an adult humanoid.

    The constructor does not refuse a bad sex or a stature outside the
    software range. The bone that reads the spec does that, the same way a
    `Material` can hold a kind that `is_valid` then rejects.
    """

    var stature: Length
    var sex: Sex
