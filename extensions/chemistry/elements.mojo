# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Chemical elements and formulas.

An `Element` is an atomic number. The table holds hydrogen through zinc,
and the heavier metals that tools, coatings and jewelry use: zirconium,
molybdenum, silver, tin, tantalum, tungsten, platinum, gold, mercury, lead
and bismuth. An element outside the table is not valid.

The atomic weights are the IUPAC abridged standard atomic weights of 2021,
to five significant figures. They are conventional values for normal
terrestrial material.

A `Formula` counts the atoms of each element in a species. Its text is
the usual formula, such as `TiCl4`.
"""

from extensions.chemistry.quantities import GRAM_PER_MOLE, MolarMass64


def _numbers() -> List[Int]:
    """Return the atomic numbers in the table."""
    var out = List[Int]()
    for z in range(1, 31):
        out.append(z)
    for z in [40, 42, 47, 50, 73, 74, 78, 79, 80, 82, 83]:
        out.append(z)
    return out^


def _symbols() -> List[String]:
    """Return the symbols, in table order."""
    return [
        "H",
        "He",
        "Li",
        "Be",
        "B",
        "C",
        "N",
        "O",
        "F",
        "Ne",
        "Na",
        "Mg",
        "Al",
        "Si",
        "P",
        "S",
        "Cl",
        "Ar",
        "K",
        "Ca",
        "Sc",
        "Ti",
        "V",
        "Cr",
        "Mn",
        "Fe",
        "Co",
        "Ni",
        "Cu",
        "Zn",
        "Zr",
        "Mo",
        "Ag",
        "Sn",
        "Ta",
        "W",
        "Pt",
        "Au",
        "Hg",
        "Pb",
        "Bi",
    ]


def _weights() -> List[Float64]:
    """Return the atomic weights in g/mol, in table order."""
    return [
        1.008,
        4.0026,
        6.94,
        9.0122,
        10.81,
        12.011,
        14.007,
        15.999,
        18.998,
        20.180,
        22.990,
        24.305,
        26.982,
        28.085,
        30.974,
        32.06,
        35.45,
        39.95,
        39.098,
        40.078,
        44.956,
        47.867,
        50.942,
        51.996,
        54.938,
        55.845,
        58.933,
        58.693,
        63.546,
        65.38,
        91.224,
        95.95,
        107.87,
        118.71,
        180.95,
        183.84,
        195.08,
        196.97,
        200.59,
        207.2,
        208.98,
    ]


def _slot(number: Int) -> Int:
    """Return the table index of an atomic number, or -1."""
    var numbers = _numbers()
    for i in range(len(numbers)):  # pragma: no branch
        if numbers[i] == number:
            return i
    return -1


@fieldwise_init
struct Element(Equatable, ImplicitlyCopyable, Writable):
    """A chemical element, named by its atomic number."""

    var number: Int

    def is_valid(self) -> Bool:
        """Return True if the element is in the table.

        Returns:
            Whether the atomic number is one this module knows.
        """
        return _slot(self.number) >= 0

    def symbol(self) -> String:
        """Return the element's symbol.

        Returns:
            The symbol, such as "Ti", or "?" if not valid.
        """
        var slot = _slot(self.number)
        if slot < 0:
            return "?"
        return _symbols()[slot]

    def atomic_weight(self) raises -> MolarMass64:
        """Return the standard atomic weight as a molar mass.

        Returns:
            The molar mass of the element's atoms.

        Raises:
            Error: If the element is not in the table.
        """
        var slot = _slot(self.number)
        if slot < 0:
            raise Error("An element must be in the table")
        return MolarMass64(_weights()[slot], GRAM_PER_MOLE)


comptime HYDROGEN = Element(1)
comptime HELIUM = Element(2)
comptime LITHIUM = Element(3)
comptime BERYLLIUM = Element(4)
comptime BORON = Element(5)
comptime CARBON = Element(6)
comptime NITROGEN = Element(7)
comptime OXYGEN = Element(8)
comptime FLUORINE = Element(9)
comptime NEON = Element(10)
comptime SODIUM = Element(11)
comptime MAGNESIUM = Element(12)
comptime ALUMINUM = Element(13)
comptime SILICON = Element(14)
comptime PHOSPHORUS = Element(15)
comptime SULFUR = Element(16)
comptime CHLORINE = Element(17)
comptime ARGON = Element(18)
comptime POTASSIUM = Element(19)
comptime CALCIUM = Element(20)
comptime SCANDIUM = Element(21)
comptime TITANIUM = Element(22)
comptime VANADIUM = Element(23)
comptime CHROMIUM = Element(24)
comptime MANGANESE = Element(25)
comptime IRON = Element(26)
comptime COBALT = Element(27)
comptime NICKEL = Element(28)
comptime COPPER = Element(29)
comptime ZINC = Element(30)
comptime ZIRCONIUM = Element(40)
comptime MOLYBDENUM = Element(42)
comptime SILVER = Element(47)
comptime TIN = Element(50)
comptime TANTALUM = Element(73)
comptime TUNGSTEN = Element(74)
comptime PLATINUM = Element(78)
comptime GOLD = Element(79)
comptime MERCURY = Element(80)
comptime LEAD = Element(82)
comptime BISMUTH = Element(83)


@fieldwise_init
struct ElementCount(ImplicitlyCopyable):
    """How many atoms of one element a formula holds."""

    var element: Element
    var count: Int


struct Formula(Copyable, Movable, Writable):
    """The atoms of a species, one count per element."""

    var counts: List[ElementCount]

    def __init__(out self, var counts: List[ElementCount]) raises:
        """Make a formula from its element counts.

        Args:
            counts: Each element once, with a positive count, in the
                order the formula is written.

        Raises:
            Error: If there are no counts, an element is not in the
                table, a count is not positive, or an element repeats.
        """
        if len(counts) == 0:
            raise Error("A formula needs at least one element")
        for i in range(len(counts)):  # pragma: no branch
            if not counts[i].element.is_valid():
                raise Error("A formula element must be in the table")
            if counts[i].count <= 0:
                raise Error("A formula count must be positive")
            for j in range(i):
                if counts[j].element == counts[i].element:
                    raise Error("A formula names each element once")
        self.counts = counts^

    def count_of(self, element: Element) -> Int:
        """Return how many atoms of an element the formula holds.

        Args:
            element: The element.

        Returns:
            The count, or zero if the formula does not hold it.
        """
        for c in self.counts:  # pragma: no branch
            if c.element == element:
                return c.count
        return 0

    def same(self, other: Formula) -> Bool:
        """Return True if both formulas hold the same atoms.

        The order the elements are written in does not matter.

        Args:
            other: The formula to compare with.

        Returns:
            Whether every element has the same count in both.
        """
        if len(self.counts) != len(other.counts):
            return False
        for c in self.counts:  # pragma: no branch
            if other.count_of(c.element) != c.count:
                return False
        return True

    def molar_mass(self) raises -> MolarMass64:
        """Return the mass of one mole of the formula.

        Returns:
            The sum of count times atomic weight.

        Raises:
            Error: Never for a formula this type made. The table lookup
                can raise for an element outside the table.
        """
        var total = MolarMass64(0)
        for c in self.counts:  # pragma: no branch
            total = total + c.element.atomic_weight().scaled(Float64(c.count))
        return total

    def write_to(self, mut writer: Some[Writer]):
        """Write the formula, such as `TiCl4`.

        Args:
            writer: Where to write.
        """
        for c in self.counts:  # pragma: no branch
            writer.write(c.element.symbol())
            if c.count > 1:
                writer.write(c.count)


def formula_index(counts: List[ElementCount], element: Element) -> Int:
    """Return where an element sits in a list of counts.

    Args:
        counts: The counts to search.
        element: The element.

    Returns:
        The index, or -1 when the element is not in the list.
    """
    for i in range(len(counts)):
        if counts[i].element == element:
            return i
    return -1
