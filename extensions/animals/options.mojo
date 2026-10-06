# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a caller asks of one animal: a seed, a quality, a sex, an age and
a color morph.

This is procedural-animals' `normaliseOptions`. A seed picks one
repeatable individual. The sex, the age and the morph, when they are not
given, are drawn from the seed as the original draws them.
"""

from math.utils import SeededRandom


@fieldwise_init
struct Sex(Equatable, ImplicitlyCopyable, Writable):
    """An animal's sex. `ANY_SEX` lets the seed choose."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `ANY_SEX`, `MALE` or `FEMALE`.

        Returns:
            Whether the value is from -1 to 1.
        """
        return self.value >= -1 and self.value <= 1


comptime ANY_SEX = Sex(-1)
comptime MALE = Sex(0)
comptime FEMALE = Sex(1)


@fieldwise_init
struct Age(Equatable, ImplicitlyCopyable, Writable):
    """An animal's age class. `ANY_AGE` means an adult unless a species
    draws a young one from the seed."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `ANY_AGE`, `ADULT` or `JUVENILE`.

        Returns:
            Whether the value is from -1 to 1.
        """
        return self.value >= -1 and self.value <= 1


comptime ANY_AGE = Age(-1)
comptime ADULT = Age(0)
comptime JUVENILE = Age(1)


@fieldwise_init
struct Quality(Equatable, ImplicitlyCopyable, Writable):
    """The procedural-animals quality tiers, finest first.

    A tier multiplies each species' base cell size: `HERO` by 1, `HIGH`
    by 1.3, `MEDIUM` by 2, `LOW` by 3 and `CROWD` by 4.2.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the five tiers.

        Returns:
            Whether the value is from zero to four.
        """
        return self.value >= 0 and self.value < 5

    def resolution(self) -> Float64:
        """Return the tier's cell-size multiplier.

        Returns:
            1, 1.3, 2, 3 or 4.2. A tier that is not valid gives 4.2.
        """
        var table: List[Float64] = [1.0, 1.3, 2.0, 3.0, 4.2]
        return table[self.value] if self.is_valid() else 4.2


comptime HERO = Quality(0)
comptime HIGH = Quality(1)
comptime MEDIUM = Quality(2)
comptime LOW = Quality(3)
comptime CROWD = Quality(4)


@fieldwise_init
struct Variant(Equatable, ImplicitlyCopyable, Writable):
    """A species' color morph: an index into its morph list.

    `ANY_VARIANT` lets the seed choose. A species checks the upper bound.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `ANY_VARIANT` or not negative.

        Returns:
            Whether the value is -1 or more.
        """
        return self.value >= -1


comptime ANY_VARIANT = Variant(-1)


@fieldwise_init
struct AnimalOptions(ImplicitlyCopyable):
    """What a caller asks of one animal."""

    var seed: Int
    var quality: Quality
    var sex: Sex
    var age: Age
    var variant: Variant


def animal_options(
    seed: Int = 1,
    quality: Quality = HIGH,
    sex: Sex = ANY_SEX,
    age: Age = ANY_AGE,
    variant: Variant = ANY_VARIANT,
) -> AnimalOptions:
    """Return options with procedural-animals' defaults.

    Args:
        seed: The individual. The low 32 bits are kept.
        quality: The quality tier.
        sex: The sex, or `ANY_SEX`.
        age: The age class, or `ANY_AGE`.
        variant: The color morph, or `ANY_VARIANT`.

    Returns:
        The options.
    """
    return AnimalOptions(seed & 0xFFFFFFFF, quality, sex, age, variant)


def check_options(options: AnimalOptions) raises:
    """Refuse options that hold a value no animal accepts.

    Args:
        options: The options.

    Raises:
        Error: If the quality, sex, age or variant is not valid.
    """
    if not options.quality.is_valid():
        raise Error("Animal quality must be from 0 to 4")
    if not options.sex.is_valid():
        raise Error("Animal sex must be ANY_SEX, MALE or FEMALE")
    if not options.age.is_valid():
        raise Error("Animal age must be ANY_AGE, ADULT or JUVENILE")
    if not options.variant.is_valid():
        raise Error("Animal variant must be ANY_VARIANT or an index")


struct AnimalRandom(Movable):
    """The procedural-animals `rng`: a Mulberry32 stream.

    The seed is mixed as the original mixes it, so a seed draws the same
    individual here as there.
    """

    var stream: SeededRandom

    def __init__(out self, seed: Int, multiplier: Int, offset: Int):
        """Start the stream at `seed * multiplier + offset`, as 32 bits.

        Args:
            seed: The individual's seed.
            multiplier: The stream's multiplier.
            offset: The stream's offset.
        """
        self.stream = SeededRandom((seed * multiplier + offset) & 0xFFFFFFFF)

    def next(mut self) -> Float64:
        """Draw one number in `[0, 1)`.

        Returns:
            The next number.
        """
        return self.stream.next()

    def g(mut self) -> Float64:
        """Draw one peaked number in about `[-1, 1]`: the mean of three.

        Returns:
            `(r + r + r - 1.5) / 1.5`.
        """
        var a = self.next()
        var b = self.next()
        var c = self.next()
        return (a + b + c - 1.5) / 1.5


def body_random(seed: Int) -> AnimalRandom:
    """Return the stream an individual's proportions are drawn from.

    Args:
        seed: The individual's seed.

    Returns:
        The procedural-animals `rng(seed * 2654435761 + 12345)`.
    """
    return AnimalRandom(seed, 2654435761, 12345)


def coat_random(seed: Int) -> AnimalRandom:
    """Return the stream an individual's coat is drawn from.

    Args:
        seed: The individual's seed.

    Returns:
        The procedural-animals `rng(seed * 7919 + 17)`.
    """
    return AnimalRandom(seed, 7919, 17)
