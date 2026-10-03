# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One individual's drawn traits: procedural-animals' `params`.

Each species draws its own named numbers, such as `muzzle` or `ear`,
from the seed. A missing name reads as its default, as `params.muzzle
|| 1` does in the original.
"""

from extensions.animals.options import (
    ADULT,
    FEMALE,
    JUVENILE,
    MALE,
    Age,
    AnimalRandom,
    Sex,
)
from extensions.animals.warp import Warps


struct Traits(Movable):
    """One individual's drawn traits."""

    var names: List[String]
    var values: List[Float64]
    var sex: Sex
    var age: Age
    var variant: Int
    var warps: Warps

    def __init__(out self, sex: Sex, age: Age, variant: Int):
        """Make traits with no named numbers.

        Args:
            sex: `MALE` or `FEMALE`.
            age: `ADULT` or `JUVENILE`.
            variant: The color morph's index.
        """
        self.names = List[String]()
        self.values = List[Float64]()
        self.sex = sex
        self.age = age
        self.variant = variant
        self.warps = Warps()

    def set(mut self, name: String, value: Float64):
        """Store a named number, replacing any earlier one.

        Args:
            name: The trait.
            value: Its value.
        """
        for i in range(len(self.names)):
            if self.names[i] == name:
                self.values[i] = value
                return
        self.names.append(name)
        self.values.append(value)

    def get(self, name: String, default: Float64 = 1.0) -> Float64:
        """Return a named number.

        Args:
            name: The trait.
            default: The value of a trait that was not drawn.

        Returns:
            The value.
        """
        for i in range(len(self.names)):
            if self.names[i] == name:
                return self.values[i]
        return default

    def male(self) -> Bool:
        """Return True for a male.

        Returns:
            Whether the sex is `MALE`.
        """
        return self.sex == MALE

    def juvenile(self) -> Float64:
        """Return one for a young animal and zero for an adult.

        Returns:
            The `juv` flag of procedural-animals, as a number.
        """
        return 1.0 if self.age == JUVENILE else 0.0


def pick_sex(requested: Sex, mut r: AnimalRandom) -> Sex:
    """Return the requested sex, or one drawn by a coin.

    The coin is drawn only when no sex is requested, as the original
    draws it, so the rest of the stream matches.

    Args:
        requested: `MALE`, `FEMALE` or `ANY_SEX`.
        r: The individual's stream.

    Returns:
        The sex.
    """
    if requested == MALE or requested == FEMALE:
        return requested
    return MALE if r.next() < 0.5 else FEMALE


def pick_age(requested: Age) -> Age:
    """Return the requested age, an adult by default.

    Args:
        requested: `ADULT`, `JUVENILE` or `ANY_AGE`.

    Returns:
        The age.
    """
    return JUVENILE if requested == JUVENILE else ADULT


def pick_variant(
    requested: Int, weights: List[Float64], draw: Float64
) raises -> Int:
    """Return the requested morph, or one drawn by weight.

    Args:
        requested: A morph index, or -1 to draw.
        weights: Each morph's share. They should sum to one.
        draw: A number in `[0, 1)`.

    Returns:
        The morph's index. A draw past the last share is the first morph.

    Raises:
        Error: If `requested` is not -1 and names no morph.
    """
    if requested >= len(weights):
        raise Error("The species has no such color variant")
    if requested >= 0:
        return requested
    var x = draw
    for i in range(len(weights)):
        if x < weights[i]:
            return i
        x -= weights[i]
    return 0
