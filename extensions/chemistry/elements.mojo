# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Chemical elements and formulas.

An `Element` is an atomic number. The table holds the 84 elements that
have an IUPAC standard atomic weight: hydrogen to bismuth without
technetium and promethium, and thorium, protactinium and uranium. An
element outside the table is not valid. The weights are the IUPAC
abridged values of 2021, to five significant figures. They are
conventional values for normal terrestrial material.

`element_from_symbol` finds an element by its symbol in either case, as
data files write "TI" or "Ti". A `Formula` counts the atoms of each
element in a species. `parse_formula` reads one from text:

    parse_formula("TiCl4")      # Ti 1, Cl 4
    parse_formula("Ca(OH)2")    # Ca 1, O 2, H 2
    parse_formula("Mg2SiO4")    # Mg 2, Si 1, O 4

A formula holds element symbols, counts and parentheses with counts. It
has no charges, dots of hydration or isotopes.
"""

from extensions.chemistry.quantities import GRAM_PER_MOLE, MolarMass64
from loaders.bytes import ascii_digit

# The largest count a formula can hold for one element.
comptime _MAX_COUNT = 1_000_000_000
# The most digits of one count in formula text.
comptime _MAX_DIGITS = 6


def _numbers() -> List[Int]:
    """Return the atomic numbers in the table."""
    return [
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
        19,
        20,
        21,
        22,
        23,
        24,
        25,
        26,
        27,
        28,
        29,
        30,
        31,
        32,
        33,
        34,
        35,
        36,
        37,
        38,
        39,
        40,
        41,
        42,
        44,
        45,
        46,
        47,
        48,
        49,
        50,
        51,
        52,
        53,
        54,
        55,
        56,
        57,
        58,
        59,
        60,
        62,
        63,
        64,
        65,
        66,
        67,
        68,
        69,
        70,
        71,
        72,
        73,
        74,
        75,
        76,
        77,
        78,
        79,
        80,
        81,
        82,
        83,
        90,
        91,
        92,
    ]


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
        "Ga",
        "Ge",
        "As",
        "Se",
        "Br",
        "Kr",
        "Rb",
        "Sr",
        "Y",
        "Zr",
        "Nb",
        "Mo",
        "Ru",
        "Rh",
        "Pd",
        "Ag",
        "Cd",
        "In",
        "Sn",
        "Sb",
        "Te",
        "I",
        "Xe",
        "Cs",
        "Ba",
        "La",
        "Ce",
        "Pr",
        "Nd",
        "Sm",
        "Eu",
        "Gd",
        "Tb",
        "Dy",
        "Ho",
        "Er",
        "Tm",
        "Yb",
        "Lu",
        "Hf",
        "Ta",
        "W",
        "Re",
        "Os",
        "Ir",
        "Pt",
        "Au",
        "Hg",
        "Tl",
        "Pb",
        "Bi",
        "Th",
        "Pa",
        "U",
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
        69.723,
        72.630,
        74.922,
        78.971,
        79.904,
        83.798,
        85.468,
        87.62,
        88.906,
        91.224,
        92.906,
        95.95,
        101.07,
        102.91,
        106.42,
        107.87,
        112.41,
        114.82,
        118.71,
        121.76,
        127.60,
        126.90,
        131.29,
        132.91,
        137.33,
        138.91,
        140.12,
        140.91,
        144.24,
        150.36,
        151.96,
        157.25,
        158.93,
        162.50,
        164.93,
        167.26,
        168.93,
        173.05,
        174.97,
        178.49,
        180.95,
        183.84,
        186.21,
        190.23,
        192.22,
        195.08,
        196.97,
        200.59,
        204.38,
        207.2,
        208.98,
        232.04,
        231.04,
        238.03,
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
            Whether the atomic number is one with a standard weight.
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


def element_from_symbol(symbol: String) raises -> Element:
    """Return the element with a symbol, in either case.

    Args:
        symbol: The symbol, such as "Ti", "TI" or "ti".

    Returns:
        The element.

    Raises:
        Error: If no element in the table has the symbol.
    """
    var wanted = symbol.upper()
    var symbols = _symbols()
    var numbers = _numbers()
    for i in range(len(symbols)):  # pragma: no branch
        if symbols[i].upper() == wanted:
            return Element(numbers[i])
    raise Error(String("No element in the table has the symbol '", symbol, "'"))


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
comptime GALLIUM = Element(31)
comptime GERMANIUM = Element(32)
comptime ARSENIC = Element(33)
comptime SELENIUM = Element(34)
comptime BROMINE = Element(35)
comptime KRYPTON = Element(36)
comptime RUBIDIUM = Element(37)
comptime STRONTIUM = Element(38)
comptime YTTRIUM = Element(39)
comptime ZIRCONIUM = Element(40)
comptime NIOBIUM = Element(41)
comptime MOLYBDENUM = Element(42)
comptime RUTHENIUM = Element(44)
comptime RHODIUM = Element(45)
comptime PALLADIUM = Element(46)
comptime SILVER = Element(47)
comptime CADMIUM = Element(48)
comptime INDIUM = Element(49)
comptime TIN = Element(50)
comptime ANTIMONY = Element(51)
comptime TELLURIUM = Element(52)
comptime IODINE = Element(53)
comptime XENON = Element(54)
comptime CESIUM = Element(55)
comptime BARIUM = Element(56)
comptime LANTHANUM = Element(57)
comptime CERIUM = Element(58)
comptime PRASEODYMIUM = Element(59)
comptime NEODYMIUM = Element(60)
comptime SAMARIUM = Element(62)
comptime EUROPIUM = Element(63)
comptime GADOLINIUM = Element(64)
comptime TERBIUM = Element(65)
comptime DYSPROSIUM = Element(66)
comptime HOLMIUM = Element(67)
comptime ERBIUM = Element(68)
comptime THULIUM = Element(69)
comptime YTTERBIUM = Element(70)
comptime LUTETIUM = Element(71)
comptime HAFNIUM = Element(72)
comptime TANTALUM = Element(73)
comptime TUNGSTEN = Element(74)
comptime RHENIUM = Element(75)
comptime OSMIUM = Element(76)
comptime IRIDIUM = Element(77)
comptime PLATINUM = Element(78)
comptime GOLD = Element(79)
comptime MERCURY = Element(80)
comptime THALLIUM = Element(81)
comptime LEAD = Element(82)
comptime BISMUTH = Element(83)
comptime THORIUM = Element(90)
comptime PROTACTINIUM = Element(91)
comptime URANIUM = Element(92)


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


def _add(mut counts: List[ElementCount], element: Element, count: Int) raises:
    """Add atoms of an element to a list of counts."""
    var at = formula_index(counts, element)
    var total = count
    if at >= 0:
        total += counts[at].count
    if total > _MAX_COUNT:
        raise Error("A count in a formula is too large")
    if at < 0:
        counts.append(ElementCount(element, total))
    else:
        counts[at].count = total


def _is_upper(byte: UInt8) -> Bool:
    """Return True for an ASCII capital letter."""
    return byte >= 65 and byte <= 90


def _is_lower(byte: UInt8) -> Bool:
    """Return True for an ASCII small letter."""
    return byte >= 97 and byte <= 122


def _count(text: String, mut at: Int) raises -> Int:
    """Read the count at `at`, or return one when there is none."""
    var bytes = text.as_bytes()
    var start = at
    var n = 0
    while at < len(bytes) and ascii_digit(bytes[at]):
        n = n * 10 + Int(bytes[at]) - 48
        at += 1
        if at - start > _MAX_DIGITS:
            raise Error("A count in a formula is too large")
    if at == start:
        return 1
    if n == 0:
        raise Error("A count in a formula must be positive")
    return n


def _group(text: String, mut at: Int, depth: Int) raises -> List[ElementCount]:
    """Read counts up to the end of the text or a closing parenthesis."""
    var bytes = text.as_bytes()
    var counts = List[ElementCount]()
    while at < len(bytes):
        var byte = bytes[at]
        if byte == 40:
            at += 1
            var inner = _group(text, at, depth + 1)
            if at >= len(bytes):
                raise Error("A formula has an unmatched '('")
            # The inner group stopped at its ')'.
            at += 1
            if len(inner) == 0:
                raise Error("A group in a formula must hold an element")
            var times = _count(text, at)
            for c in inner:  # pragma: no branch
                _add(counts, c.element, c.count * times)
        elif byte == 41:
            if depth == 0:
                raise Error("A formula has an unmatched ')'")
            return counts^
        elif _is_upper(byte):
            var start = at
            at += 1
            if at < len(bytes) and _is_lower(bytes[at]):
                at += 1
            var element = element_from_symbol(String(text[byte=start:at]))
            _add(counts, element, _count(text, at))
        else:
            raise Error(
                "A formula holds only element symbols, counts and parentheses"
            )
    return counts^


def parse_formula(text: String) raises -> Formula:
    """Read a formula from text, such as "Ca(OH)2".

    An element that appears more than once is counted once, in the order
    it first appears.

    Args:
        text: Element symbols with counts, and parenthesized groups with
            counts.

    Returns:
        The formula.

    Raises:
        Error: If the text is empty, holds another character, names an
            element outside the table, has a zero count, an empty group,
            an unmatched parenthesis, or a count over a billion.
    """
    var at = 0
    var counts = _group(text, at, 0)
    return Formula(counts^)
