# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a structure as an mmCIF file.

`encode_mmcif` writes a structure for other molecular viewers and tools.
mmCIF has no fixed columns, so it takes what the PDB format cannot: more
than 99999 atoms, long chain ids and long residue names. It writes one
data block with these categories:

- `_entry.id`, the structure's name. The block is `data_` and the name,
  or `data_unnamed` for a structure without one.
- `_struct_conf` with a `HELX_P` row for each run of helix residues of
  the first model, and `_struct_sheet_range` with a row for each run of
  strand residues. A range names its ends by the label ids, with their
  insertion codes, and again by the author ids, as wwPDB files do. Each
  strand is a sheet of its own, because the structure does not record
  which strands pair.
- `_atom_site`, one row per atom, with the columns that `parse_mmcif`
  reads.

Coordinates have three decimals in angstroms, and the occupancy and the
B-factor two, as wwPDB writes them. A residue whose `seq_id` is zero,
such as a water, gets the null `label_seq_id` `.`. A value that holds a
blank or starts like a CIF name or a comment is quoted.
"""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import COIL, HELIX, HETATM_RECORD
from extensions.molecule.structure import SQUARE_ANGSTROM, Structure
from loaders.js_number import js_to_fixed
from units.si import Length64


def _starts_reserved(text: String) -> Bool:
    """Return whether a value starts like a CIF reserved word."""
    var lower = text.lower()
    if lower.startswith("data_") or lower.startswith("save_"):
        return True
    return lower == "loop_" or lower == "global_" or lower == "stop_"


def _closes(bytes: Span[UInt8, _], quote: UInt8) -> Bool:
    """Return whether a quote followed by a blank appears in a value."""
    for k in range(len(bytes) - 1):
        var next = bytes[k + 1]
        if bytes[k] == quote and (next == 32 or next == 9):
            return True
    return False


def cif_value(text: String) raises -> String:
    """Return a value as a CIF token, quoted when it needs quotes.

    A value needs quotes when it is empty, holds a space or a tab, starts
    with one of `_ # $ ' " [ ] ;`, or starts like a reserved word such as
    `data_` or `loop_`. The value goes in single quotes, or in double
    quotes when it holds a single quote followed by a blank.

    Args:
        text: The value.

    Returns:
        The token.

    Raises:
        Error: If the value holds a line end, or both kinds of quote
            followed by a blank.
    """
    var bytes = text.as_bytes()
    var quote = len(bytes) == 0 or _starts_reserved(text)
    for k in range(len(bytes)):
        var byte = bytes[k]
        if byte == 10 or byte == 13:
            raise Error("A CIF value must fit on one line")
        if byte == 32 or byte == 9:
            quote = True
    if len(bytes) > 0:
        var first = bytes[0]
        for special in "_#$'\"[];".as_bytes():  # pragma: no branch
            if first == special:
                quote = True
    if not quote:
        return text
    if not _closes(bytes, 39):
        return "'" + text + "'"
    if not _closes(bytes, 34):
        return '"' + text + '"'
    raise Error("A CIF value cannot hold both kinds of closing quote")


def _seq(seq_id: Int) -> String:
    """Return a label_seq_id, the null `.` for zero."""
    if seq_id == 0:
        return String(".")
    return String(seq_id)


def _ranges(
    structure: Structure, mut helices: List[String], mut strands: List[String]
) raises:
    """Append a row for each helix and strand run of the first model."""
    ref m = structure.models[0]
    for c in range(
        m.first_chain, m.first_chain + m.chain_count
    ):  # pragma: no branch
        ref chain = structure.chains[c]
        var asym = cif_value(chain.label)
        var author = cif_value(chain.author)
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
            var span = (
                cif_value(first_residue.name)
                + " "
                + asym
                + " "
                + _seq(first_residue.seq_id)
                + " "
                + cif_value(first_residue.insertion)
                + " "
                + cif_value(last_residue.name)
                + " "
                + asym
                + " "
                + _seq(last_residue.seq_id)
                + " "
                + cif_value(last_residue.insertion)
                + " "
                + author
                + " "
                + String(first_residue.auth_seq_id)
                + " "
                + author
                + " "
                + String(last_residue.auth_seq_id)
            )
            if kind == HELIX:
                var id = String(len(helices) + 1)
                helices.append("HELX_P HELX_P" + id + " " + span)
            else:
                var id = String(len(strands) + 1)
                strands.append("S" + id + " 1 " + span)
            r = last + 1


def _loop(names: List[String], rows: List[String]) -> String:
    """Return a loop of a category, or nothing when it has no rows."""
    if len(rows) == 0:
        return String("")
    var out = String("loop_\n")
    for name in names:  # pragma: no branch
        out += name + "\n"
    for row in rows:  # pragma: no branch
        out += row + "\n"
    return out + "#\n"


def _range_names(category: String, first: String) -> List[String]:
    """Return the column names of a helix or a strand loop."""
    var out = List[String]()
    out.append(category + first)
    out.append(category + ".id")
    for end in ["beg", "end"]:  # pragma: no branch
        out.append(category + "." + end + "_label_comp_id")
        out.append(category + "." + end + "_label_asym_id")
        out.append(category + "." + end + "_label_seq_id")
        out.append(category + ".pdbx_" + end + "_PDB_ins_code")
    for end in ["beg", "end"]:  # pragma: no branch
        out.append(category + "." + end + "_auth_asym_id")
        out.append(category + "." + end + "_auth_seq_id")
    return out^


def _atom_names() -> List[String]:
    """Return the columns of the atom loop, in order."""
    var columns: List[String] = [
        "group_PDB",
        "id",
        "type_symbol",
        "label_atom_id",
        "label_alt_id",
        "label_comp_id",
        "label_asym_id",
        "label_seq_id",
        "pdbx_PDB_ins_code",
        "Cartn_x",
        "Cartn_y",
        "Cartn_z",
        "occupancy",
        "B_iso_or_equiv",
        "auth_seq_id",
        "auth_asym_id",
        "pdbx_PDB_model_num",
    ]
    var out = List[String]()
    for column in columns:  # pragma: no branch
        out.append("_atom_site." + column)
    return out^


def encode_mmcif(structure: Structure) raises -> String:
    """Return the text of an mmCIF file of a structure.

    Args:
        structure: The structure, with at least one model.

    Returns:
        The text, one data block.

    Raises:
        Error: If the structure has no model or no atom, its name holds
            a blank, or a value holds a line end or both kinds of closing
            quote.
    """
    if len(structure.models) == 0:
        raise Error("An mmCIF file needs a structure with a model")
    var name = structure.name
    if name == "":
        name = "unnamed"
    for byte in name.as_bytes():  # pragma: no branch
        if byte <= 32:
            raise Error("A data block name must not hold a blank")
    var out = String("data_") + name + "\n#\n"
    out += "_entry.id " + cif_value(name) + "\n#\n"
    var helices = List[String]()
    var strands = List[String]()
    _ranges(structure, helices, strands)
    out += _loop(_range_names("_struct_conf", ".conf_type_id"), helices)
    out += _loop(_range_names("_struct_sheet_range", ".sheet_id"), strands)
    var rows = List[String]()
    var scale = 1.0 / Length64(1.0, ANGSTROM).value
    for model in range(len(structure.models)):  # pragma: no branch
        ref m = structure.models[model]
        var number = String(m.number)
        for c in range(
            m.first_chain, m.first_chain + m.chain_count
        ):  # pragma: no branch
            ref chain = structure.chains[c]
            var asym = cif_value(chain.label)
            var author = cif_value(chain.author)
            for r in range(  # pragma: no branch
                chain.first_residue, chain.first_residue + chain.residue_count
            ):
                ref residue = structure.residues[r]
                var comp = cif_value(residue.name)
                var seq = _seq(residue.seq_id)
                var insertion = cif_value(residue.insertion)
                var auth_seq = String(residue.auth_seq_id)
                for a in range(
                    residue.first_atom, residue.first_atom + residue.atom_count
                ):
                    ref atom = structure.atoms[a]
                    var group = String("ATOM")
                    if atom.group == HETATM_RECORD:
                        group = "HETATM"
                    var p = atom.position * scale
                    rows.append(
                        group
                        + " "
                        + String(atom.serial)
                        + " "
                        + cif_value(atom.element)
                        + " "
                        + cif_value(atom.name)
                        + " "
                        + cif_value(atom.alt)
                        + " "
                        + comp
                        + " "
                        + asym
                        + " "
                        + seq
                        + " "
                        + insertion
                        + " "
                        + js_to_fixed(p.x, 3)
                        + " "
                        + js_to_fixed(p.y, 3)
                        + " "
                        + js_to_fixed(p.z, 3)
                        + " "
                        + js_to_fixed(atom.occupancy, 2)
                        + " "
                        + js_to_fixed(atom.b_factor.to(SQUARE_ANGSTROM), 2)
                        + " "
                        + auth_seq
                        + " "
                        + author
                        + " "
                        + number
                    )
    if len(rows) == 0:
        raise Error("An mmCIF file needs at least one atom")
    out += _loop(_atom_names(), rows)
    return out^
