# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a structure as a PDB file.

`encode_pdb` writes a structure that this extension built or moved, such
as a superposed model, for other molecular viewers. It writes these
records, in the fixed columns of the wwPDB format version 3.3:

- `HEADER` with the structure's name, when it is a PDB id of up to four
  characters, or `TITLE` with a longer name. The reader reads the PDB
  id of a `HEADER` only.
- `HELIX` and `SHEET` for each run of helix or strand residues of the
  first model.
- `MODEL` and `ENDMDL` around each model, when there are two or more.
- `ATOM` and `HETATM` for each atom, `TER` after each chain, and `END`.

Coordinates have three decimals in angstroms, and the occupancy and the
B-factor two. A value that does not fit its columns is refused, as is a
chain id of more than one character.
"""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import COIL, HELIX, HETATM_RECORD
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from loaders.js_number import js_to_fixed
from units.si import Length64


def _put(mut line: List[UInt8], column: Int, text: String) raises:
    """Write text from a column, counted from one."""
    var bytes = text.as_bytes()
    for k in range(len(bytes)):
        line[column - 1 + k] = bytes[k]


def _right(text: String, width: Int, name: String) raises -> String:
    """Return text padded on the left to a width, or refuse it."""
    var size = len(text.as_bytes())
    if size > width:
        raise Error(
            "The " + name + " " + text + " does not fit its PDB columns"
        )
    var out = String("")
    for _ in range(width - size):
        out += " "
    return out + text


def _blank() -> List[UInt8]:
    """Return 80 spaces."""
    return List[UInt8](length=80, fill=32)


def _text(line: List[UInt8]) -> String:
    """Return a line without its trailing spaces."""
    var end = len(line)
    # Every record starts with its name in column 1.
    while line[end - 1] == 32:
        end -= 1
    return String(from_utf8_lossy=Span(line)[:end])


def _insertion(code: String) -> String:
    """Return the insertion code of a column, blank for none."""
    if code == "?" or code == ".":
        return String(" ")
    return code


def _chain_id(structure: Structure, chain: Int) raises -> String:
    """Return a chain's author id, or refuse one longer than a column."""
    var id = structure.chains[chain].author
    if len(id.as_bytes()) != 1:
        raise Error("A PDB chain id must be one character, not '" + id + "'")
    return id


def _runs(structure: Structure, mut lines: List[String]) raises:
    """Append the HELIX and SHEET records of the first model."""
    ref m = structure.models[0]
    var helices = 0
    var strands = 0
    for c in range(
        m.first_chain, m.first_chain + m.chain_count
    ):  # pragma: no branch
        ref chain = structure.chains[c]
        var r = chain.first_residue
        var end = chain.first_residue + chain.residue_count
        while r < end:
            var kind = structure.residues[r].secondary
            if kind == COIL:
                r += 1
                continue
            var last = r
            while (
                last + 1 < end
                and structure.residues[last + 1].secondary == kind
            ):
                last += 1
            ref first_residue = structure.residues[r]
            ref last_residue = structure.residues[last]
            var id = _chain_id(structure, c)
            var line = _blank()
            if kind == HELIX:
                helices += 1
                _put(line, 1, "HELIX")
                _put(line, 8, _right(String(helices), 3, "helix number"))
                _put(line, 12, _right(String(helices), 3, "helix id"))
                _put(line, 16, _right(first_residue.name, 3, "residue name"))
                _put(line, 20, id)
                _put(
                    line,
                    22,
                    _right(String(first_residue.seq_id), 4, "residue number"),
                )
                _put(line, 26, _insertion(first_residue.insertion))
                _put(line, 28, _right(last_residue.name, 3, "residue name"))
                _put(line, 32, id)
                _put(
                    line,
                    34,
                    _right(String(last_residue.seq_id), 4, "residue number"),
                )
                _put(line, 38, _insertion(last_residue.insertion))
                _put(line, 39, " 1")
            else:
                strands += 1
                _put(line, 1, "SHEET")
                _put(line, 8, _right(String(strands), 3, "strand number"))
                _put(line, 12, _right(String(strands), 3, "sheet id"))
                _put(line, 15, " 1")
                _put(line, 18, _right(first_residue.name, 3, "residue name"))
                _put(line, 22, id)
                _put(
                    line,
                    23,
                    _right(String(first_residue.seq_id), 4, "residue number"),
                )
                _put(line, 27, _insertion(first_residue.insertion))
                _put(line, 29, _right(last_residue.name, 3, "residue name"))
                _put(line, 33, id)
                _put(
                    line,
                    34,
                    _right(String(last_residue.seq_id), 4, "residue number"),
                )
                _put(line, 38, _insertion(last_residue.insertion))
                _put(line, 39, " 0")
            lines.append(_text(line))
            r = last + 1


def _atom_line(structure: Structure, atom: Int, chain: Int) raises -> String:
    """Return the ATOM or HETATM record of one atom."""
    ref a = structure.atoms[atom]
    ref residue = structure.residues[a.residue.value]
    var line = _blank()
    var record = String("ATOM")
    if a.group == HETATM_RECORD:
        record = "HETATM"
    _put(line, 1, record)
    _put(line, 7, _right(String(a.serial % 100000), 5, "serial"))
    var name = a.name
    if len(name.as_bytes()) > 4:
        raise Error("The atom name " + name + " does not fit its PDB columns")
    # A short name of a one-letter element starts in column 14.
    var column = 13
    if len(name.as_bytes()) < 4 and len(a.element.as_bytes()) == 1:
        column = 14
    _put(line, column, name)
    if a.alt != ".":
        _put(line, 17, a.alt)
    _put(line, 18, _right(residue.name, 3, "residue name"))
    _put(line, 22, _chain_id(structure, chain))
    if residue.seq_id < -999:
        raise Error(
            "The residue number "
            + String(residue.seq_id)
            + " does not fit its PDB columns"
        )
    _put(line, 23, _right(String(residue.seq_id), 4, "residue number"))
    _put(line, 27, _insertion(residue.insertion))
    var scale = 1.0 / Length64(1.0, ANGSTROM).value
    var p = a.position * scale
    _put(line, 31, _right(js_to_fixed(p.x, 3), 8, "coordinate"))
    _put(line, 39, _right(js_to_fixed(p.y, 3), 8, "coordinate"))
    _put(line, 47, _right(js_to_fixed(p.z, 3), 8, "coordinate"))
    _put(line, 55, _right(js_to_fixed(a.occupancy, 2), 6, "occupancy"))
    _put(
        line,
        61,
        _right(js_to_fixed(a.b_factor.to(SQUARE_ANGSTROM), 2), 6, "B-factor"),
    )
    _put(line, 77, _right(a.element, 2, "element"))
    return _text(line)


def encode_pdb(structure: Structure) raises -> String:
    """Return the text of a PDB file of a structure.

    Args:
        structure: The structure, with at least one model.

    Returns:
        The text, one record per line.

    Raises:
        Error: If the structure has no model, a chain id is not one
            character, or a name or a number does not fit its columns.
    """
    if len(structure.models) == 0:
        raise Error("A PDB file needs a structure with a model")
    var lines = List[String]()
    var size = len(structure.name.as_bytes())
    if size > 0 and size <= 4:
        var header = _blank()
        _put(header, 1, "HEADER")
        _put(header, 63, structure.name)
        lines.append(_text(header))
    elif size > 4:
        if size > 70:
            raise Error(
                "The title " + structure.name + " does not fit its PDB columns"
            )
        lines.append("TITLE     " + structure.name)
    _runs(structure, lines)
    var several = len(structure.models) > 1
    for model in range(len(structure.models)):  # pragma: no branch
        ref m = structure.models[model]
        if several:
            lines.append(
                "MODEL     " + _right(String(m.number), 4, "model number")
            )
        for c in range(
            m.first_chain, m.first_chain + m.chain_count
        ):  # pragma: no branch
            ref chain = structure.chains[c]
            var first = structure.residues[chain.first_residue].first_atom
            ref last_residue = structure.residues[
                chain.first_residue + chain.residue_count - 1
            ]
            var end = last_residue.first_atom + last_residue.atom_count
            for atom in range(first, end):  # pragma: no branch
                lines.append(_atom_line(structure, atom, c))
            lines.append("TER")
        if several:
            lines.append("ENDMDL")
    lines.append("END")
    var out = String("")
    for line in lines:  # pragma: no branch
        out += line + "\n"
    return out^
