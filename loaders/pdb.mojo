# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Protein Data Bank files, from three.js `examples/jsm/loaders/PDBLoader.js`.

A PDB file is text in fixed columns. An `ATOM` or `HETATM` line gives an
atom: its serial number in columns 7 to 11, its position in columns 31 to
53, and its element in columns 77 and 78, or in 13 and 14 when those are
blank. A `CONECT` line bonds the atom it names to up to four others.
`parse_pdb` returns what three.js's `parse` returns: the atoms as points,
the bonds as line segments, and each atom's position, color and element.

**Colors.** Each element has three.js's CPK color, in sRGB. The atom
geometry's `color` is that color decoded to linear light, as three.js's
`Color.setRGB( r, g, b, SRGBColorSpace )` decodes it.

**What is read.** The numbers are read as JavaScript's `parseFloat` and
`parseInt` read them, from the same columns. A bond is kept once, however
many lines name it. A bond to atom zero, or to a column that holds no
number, is stepped over, as three.js steps over it.

**What is refused.** An element three.js has no color for, and a bond to
an atom that no line gives. three.js throws on both when it builds the
geometry. A line that is not an atom or a bond is stepped over.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from loaders.js_number import js_parse_float, js_parse_int
from render.srgb import srgb_to_linear
from std.math import isnan
from std.pathlib import Path


def _cpk_names() -> List[String]:
    """Return three.js's CPK element names, in its order."""
    return [
        "h",
        "he",
        "li",
        "be",
        "b",
        "c",
        "n",
        "o",
        "f",
        "ne",
        "na",
        "mg",
        "al",
        "si",
        "p",
        "s",
        "cl",
        "ar",
        "k",
        "ca",
        "sc",
        "ti",
        "v",
        "cr",
        "mn",
        "fe",
        "co",
        "ni",
        "cu",
        "zn",
        "ga",
        "ge",
        "as",
        "se",
        "br",
        "kr",
        "rb",
        "sr",
        "y",
        "zr",
        "nb",
        "mo",
        "tc",
        "ru",
        "rh",
        "pd",
        "ag",
        "cd",
        "in",
        "sn",
        "sb",
        "te",
        "i",
        "xe",
        "cs",
        "ba",
        "la",
        "ce",
        "pr",
        "nd",
        "pm",
        "sm",
        "eu",
        "gd",
        "tb",
        "dy",
        "ho",
        "er",
        "tm",
        "yb",
        "lu",
        "hf",
        "ta",
        "w",
        "re",
        "os",
        "ir",
        "pt",
        "au",
        "hg",
        "tl",
        "pb",
        "bi",
        "po",
        "at",
        "rn",
        "fr",
        "ra",
        "ac",
        "th",
        "pa",
        "u",
        "np",
        "pu",
        "am",
        "cm",
        "bk",
        "cf",
        "es",
        "fm",
        "md",
        "no",
        "lr",
        "rf",
        "db",
        "sg",
        "bh",
        "hs",
        "mt",
        "ds",
        "rg",
        "cn",
        "uut",
        "uuq",
        "uup",
        "uuh",
        "uus",
        "uuo",
    ]


def _cpk_colors() -> List[Int]:
    """Return three.js's CPK colors, red, green and blue for each name."""
    return [
        255,
        255,
        255,
        217,
        255,
        255,
        204,
        128,
        255,
        194,
        255,
        0,
        255,
        181,
        181,
        144,
        144,
        144,
        48,
        80,
        248,
        255,
        13,
        13,
        144,
        224,
        80,
        179,
        227,
        245,
        171,
        92,
        242,
        138,
        255,
        0,
        191,
        166,
        166,
        240,
        200,
        160,
        255,
        128,
        0,
        255,
        255,
        48,
        31,
        240,
        31,
        128,
        209,
        227,
        143,
        64,
        212,
        61,
        255,
        0,
        230,
        230,
        230,
        191,
        194,
        199,
        166,
        166,
        171,
        138,
        153,
        199,
        156,
        122,
        199,
        224,
        102,
        51,
        240,
        144,
        160,
        80,
        208,
        80,
        200,
        128,
        51,
        125,
        128,
        176,
        194,
        143,
        143,
        102,
        143,
        143,
        189,
        128,
        227,
        255,
        161,
        0,
        166,
        41,
        41,
        92,
        184,
        209,
        112,
        46,
        176,
        0,
        255,
        0,
        148,
        255,
        255,
        148,
        224,
        224,
        115,
        194,
        201,
        84,
        181,
        181,
        59,
        158,
        158,
        36,
        143,
        143,
        10,
        125,
        140,
        0,
        105,
        133,
        192,
        192,
        192,
        255,
        217,
        143,
        166,
        117,
        115,
        102,
        128,
        128,
        158,
        99,
        181,
        212,
        122,
        0,
        148,
        0,
        148,
        66,
        158,
        176,
        87,
        23,
        143,
        0,
        201,
        0,
        112,
        212,
        255,
        255,
        255,
        199,
        217,
        255,
        199,
        199,
        255,
        199,
        163,
        255,
        199,
        143,
        255,
        199,
        97,
        255,
        199,
        69,
        255,
        199,
        48,
        255,
        199,
        31,
        255,
        199,
        0,
        255,
        156,
        0,
        230,
        117,
        0,
        212,
        82,
        0,
        191,
        56,
        0,
        171,
        36,
        77,
        194,
        255,
        77,
        166,
        255,
        33,
        148,
        214,
        38,
        125,
        171,
        38,
        102,
        150,
        23,
        84,
        135,
        208,
        208,
        224,
        255,
        209,
        35,
        184,
        184,
        208,
        166,
        84,
        77,
        87,
        89,
        97,
        158,
        79,
        181,
        171,
        92,
        0,
        117,
        79,
        69,
        66,
        130,
        150,
        66,
        0,
        102,
        0,
        125,
        0,
        112,
        171,
        250,
        0,
        186,
        255,
        0,
        161,
        255,
        0,
        143,
        255,
        0,
        128,
        255,
        0,
        107,
        255,
        84,
        92,
        242,
        120,
        92,
        227,
        138,
        79,
        227,
        161,
        54,
        212,
        179,
        31,
        212,
        179,
        31,
        186,
        179,
        13,
        166,
        189,
        13,
        135,
        199,
        0,
        102,
        204,
        0,
        89,
        209,
        0,
        79,
        217,
        0,
        69,
        224,
        0,
        56,
        230,
        0,
        46,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
        235,
        0,
        38,
    ]


def cpk_color(element: String) -> Tuple[Int, Int, Int]:
    """Return an element's CPK color, in sRGB bytes, or -1 in each channel
    for an element three.js has no color for.

    Args:
        element: The element, lower case, as three.js looks it up.

    Returns:
        Red, green and blue.
    """
    var names = _cpk_names()
    for at in range(len(names)):  # pragma: no branch
        if names[at] == element:
            var colors = _cpk_colors()
            return (colors[at * 3], colors[at * 3 + 1], colors[at * 3 + 2])
    return (-1, -1, -1)


@fieldwise_init
struct PdbAtom(Copyable, Movable):
    """One atom, as three.js's `json.atoms` holds it: its position, its
    color in sRGB bytes, and its element, capitalized."""

    var x: Float64
    var y: Float64
    var z: Float64
    var red: Int
    var green: Int
    var blue: Int
    var element: String


struct PdbModel(Movable):
    """What `parse_pdb` returns: three.js's `geometryAtoms`,
    `geometryBonds` and `json.atoms`."""

    # The atoms as points: `position` and `color`.
    var atoms_geometry: BufferGeometry
    # The bonds as line segments: `position`, two points a bond.
    var bonds_geometry: BufferGeometry
    var atoms: List[PdbAtom]

    def __init__(
        out self,
        var atoms_geometry: BufferGeometry,
        var bonds_geometry: BufferGeometry,
        var atoms: List[PdbAtom],
    ):
        """Hold the two geometries and the atoms.

        Args:
            atoms_geometry: The atoms as points.
            bonds_geometry: The bonds as line segments.
            atoms: Each atom's position, color and element.
        """
        self.atoms_geometry = atoms_geometry^
        self.bonds_geometry = bonds_geometry^
        self.atoms = atoms^


def _slice(line: String, start: Int, end: Int) -> String:
    """Return JavaScript's `line.slice( start, end )`, short where the line
    is."""
    var n = line.byte_length()
    var a = min(start, n)
    var b = min(end, n)
    return String(line[byte=a:b])


def _capitalize(text: String) -> String:
    """Return three.js's `capitalize`: the first letter upper case and the
    rest lower. The element is not empty: an empty one has no CPK color and
    is refused first."""
    return String(text[byte=0:1]).upper() + String(text[byte=1:]).lower()


def parse_pdb(text: String) raises -> PdbModel:
    """Read a PDB file's text, three.js's `PDBLoader.parse`.

    Args:
        text: The file.

    Returns:
        The atoms as points, the bonds as segments, and the atoms.

    Raises:
        Error: If an atom's element has no CPK color, or a bond names an
            atom that no line gives.
    """
    var atoms = List[PdbAtom]()
    # three.js's `_atomMap`: each atom's serial number less one.
    var serials = List[Int]()
    # Each bond once, its two serial numbers less one, in the order found.
    var bonds = List[Int]()
    var number = 0
    for raw in text.split("\n"):  # pragma: no branch
        number += 1
        var line = String(raw)
        if line.startswith("ATOM") or line.startswith("HETATM"):
            var element = String(_slice(line, 76, 78).strip()).lower()
            if element == "":
                element = String(_slice(line, 12, 14).strip()).lower()
            var color = cpk_color(element)
            if color[0] < 0:
                raise Error(
                    "PDB line "
                    + String(number)
                    + ": no color for the element `"
                    + element
                    + "`"
                )
            atoms.append(
                PdbAtom(
                    js_parse_float(_slice(line, 30, 37)),
                    js_parse_float(_slice(line, 38, 45)),
                    js_parse_float(_slice(line, 46, 53)),
                    color[0],
                    color[1],
                    color[2],
                    _capitalize(element),
                )
            )
            var serial = js_parse_int(_slice(line, 6, 11))
            serials.append(-1 if isnan(serial) else Int(serial) - 1)
        elif line.startswith("CONECT"):
            var start = js_parse_int(_slice(line, 6, 11))
            for column in [11, 16, 21, 26]:  # pragma: no branch
                var end = js_parse_int(_slice(line, column, column + 5))
                # three.js's `if ( eatom )`: NaN and zero are stepped over.
                if isnan(end) or end == 0:
                    continue
                if isnan(start):
                    raise Error(
                        "PDB line " + String(number) + ": a bond from no atom"
                    )
                var low = Int(min(start, end)) - 1
                var high = Int(max(start, end)) - 1
                var seen = False
                for at in range(0, len(bonds), 2):
                    var a = min(bonds[at], bonds[at + 1])
                    var b = max(bonds[at], bonds[at + 1])
                    if a == low and b == high:
                        seen = True
                if not seen:
                    bonds.append(Int(start) - 1)
                    bonds.append(Int(end) - 1)

    var positions = List[Float32]()
    var colors = List[Float32]()
    for atom in atoms:
        positions.append(Float32(atom.x))
        positions.append(Float32(atom.y))
        positions.append(Float32(atom.z))
        colors.append(srgb_to_linear(Float32(atom.red) / 255))
        colors.append(srgb_to_linear(Float32(atom.green) / 255))
        colors.append(srgb_to_linear(Float32(atom.blue) / 255))
    var ends = List[Float32]()
    for at in range(len(bonds)):
        # three.js's `_atomMap`: the last atom with that serial number.
        var found = -1
        for slot in range(len(serials)):  # pragma: no branch
            if serials[slot] == bonds[at]:
                found = slot
        if found < 0:
            raise Error(
                "PDB: a bond names atom "
                + String(bonds[at] + 1)
                + ", which no line gives"
            )
        ends.append(Float32(atoms[found].x))
        ends.append(Float32(atoms[found].y))
        ends.append(Float32(atoms[found].z))
    var atom_geometry = BufferGeometry()
    atom_geometry.set_attribute(
        String(POSITION), BufferAttribute(positions^, 3)
    )
    atom_geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var bond_geometry = BufferGeometry()
    bond_geometry.set_attribute(String(POSITION), BufferAttribute(ends^, 3))
    return PdbModel(atom_geometry^, bond_geometry^, atoms^)


def read_pdb(path: String) raises -> PdbModel:
    """Read a PDB file.

    Args:
        path: The file.

    Returns:
        What `parse_pdb` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_pdb`
            refuses.
    """
    return parse_pdb(Path(path).read_text())
