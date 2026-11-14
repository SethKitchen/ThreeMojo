# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A macromolecular structure read from an mmCIF file.

A `Structure` holds models, chains, residues and atoms in four lists. A
model holds a run of chains, a chain a run of residues and a residue a run
of atoms. Each run is a first index and a count.

`parse_mmcif` reads the `_atom_site` table. A new model starts where
`pdbx_PDB_model_num` changes. A new chain starts where `label_asym_id`
changes. A new residue starts where `label_seq_id`, `auth_seq_id`,
`pdbx_PDB_ins_code` or `label_comp_id` changes. Positions are read in
angstroms and kept in meters. B-factors are read in square angstroms and
kept as areas.

The secondary structure comes from `_struct_conf`, where each helix has a
`conf_type_id` that starts with `HELX`, and from `_struct_sheet_range`. A
range names a chain by `label_asym_id` and its residues by
`label_seq_id`.
"""

from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.cif import CifBlock, is_null, parse_cif
from extensions.molecule.ids import (
    ATOM_RECORD,
    AltLocPolicy,
    AtomGroup,
    AtomId,
    COIL,
    ChainId,
    FIRST_LOCATION,
    HELIX,
    HETATM_RECORD,
    ModelId,
    ResidueId,
    STRAND,
    SecondaryKind,
    require_index,
    require_policy,
)
from extensions.sdf.vector import V3, v3
from std.math import isfinite, max, min
from std.pathlib import Path
from units.quantity import Unit
from units.si import Area64, Length64

# A square angstrom with a Float64 scale, the unit of a B-factor.
comptime SQUARE_ANGSTROM = Unit[2, 0, 0, 0, 0, DType.float64](
    1.0e-20, "angstrom^2"
)


@fieldwise_init
struct Atom(Copyable, Movable):
    """One atom of a structure."""

    var name: String
    """The atom's name in its residue, such as `CA`."""
    var element: String
    """The element symbol, such as `C` or `FE`."""
    var serial: Int
    """The atom's id in the file."""
    var group: AtomGroup
    """`ATOM_RECORD` or `HETATM_RECORD`."""
    var alt: String
    """The alternate location, or `.` when it has none."""
    var position: V3
    """The position, in meters."""
    var occupancy: Float64
    """The occupancy, from zero to one."""
    var b_factor: Area64
    """The isotropic displacement parameter."""
    var residue: ResidueId
    """The residue that holds the atom."""


@fieldwise_init
struct Residue(Copyable, Movable):
    """One residue, or one ligand or water."""

    var name: String
    """The component name, such as `ALA` or `HOH`."""
    var seq_id: Int
    """The `label_seq_id`. Zero when the file gives none."""
    var auth_seq_id: Int
    """The author's residue number."""
    var insertion: String
    """The insertion code, or `?` when it has none."""
    var chain: ChainId
    """The chain that holds the residue."""
    var first_atom: Int
    """The index of its first atom."""
    var atom_count: Int
    """How many atoms it holds."""
    var secondary: SecondaryKind
    """Its secondary structure."""


@fieldwise_init
struct Chain(Copyable, Movable):
    """One chain of one model."""

    var label: String
    """The `label_asym_id`, unique in the file."""
    var author: String
    """The `auth_asym_id`, the name an author gave the chain."""
    var model: ModelId
    """The model that holds the chain."""
    var first_residue: Int
    """The index of its first residue."""
    var residue_count: Int
    """How many residues it holds."""


@fieldwise_init
struct Model(Copyable, Movable):
    """One model, such as one conformer of an NMR ensemble."""

    var number: Int
    """The `pdbx_PDB_model_num`."""
    var first_chain: Int
    """The index of its first chain."""
    var chain_count: Int
    """How many chains it holds."""


struct Structure(Copyable, Movable):
    """The models, chains, residues and atoms of one entry."""

    var name: String
    """The data block's name, such as the PDB id."""
    var models: List[Model]
    """The models, in file order."""
    var chains: List[Chain]
    """The chains of every model."""
    var residues: List[Residue]
    """The residues of every chain."""
    var atoms: List[Atom]
    """The atoms of every residue."""

    def __init__(out self, name: String):
        """Create an empty structure.

        Args:
            name: The entry's name.
        """
        self.name = name
        self.models = List[Model]()
        self.chains = List[Chain]()
        self.residues = List[Residue]()
        self.atoms = List[Atom]()

    def require_atom(self, id: AtomId) raises:
        """Refuse an atom id that names no atom.

        Args:
            id: The atom.

        Raises:
            Error: If the id is negative or past the last atom.
        """
        require_index(id.is_valid(), id.value, len(self.atoms), "atom")

    def require_residue(self, id: ResidueId) raises:
        """Refuse a residue id that names no residue.

        Args:
            id: The residue.

        Raises:
            Error: If the id is negative or past the last residue.
        """
        require_index(id.is_valid(), id.value, len(self.residues), "residue")

    def require_chain(self, id: ChainId) raises:
        """Refuse a chain id that names no chain.

        Args:
            id: The chain.

        Raises:
            Error: If the id is negative or past the last chain.
        """
        require_index(id.is_valid(), id.value, len(self.chains), "chain")

    def require_model(self, id: ModelId) raises:
        """Refuse a model id that names no model.

        Args:
            id: The model.

        Raises:
            Error: If the id is negative or past the last model.
        """
        require_index(id.is_valid(), id.value, len(self.models), "model")

    def find_atom(self, residue: ResidueId, name: String) raises -> AtomId:
        """Return the first atom of a residue with a name.

        Args:
            residue: The residue.
            name: The atom name, such as `CA`.

        Returns:
            The atom, or `AtomId(-1)` when the residue has none of that
            name.

        Raises:
            Error: If the residue id names no residue.
        """
        self.require_residue(residue)
        ref r = self.residues[residue.value]
        for index in range(r.first_atom, r.first_atom + r.atom_count):
            if self.atoms[index].name == name:
                return AtomId(index)
        return AtomId(-1)

    def model_atoms(self, model: ModelId) raises -> Tuple[Int, Int]:
        """Return the first atom and the atom count of a model.

        Args:
            model: The model.

        Returns:
            The index of the model's first atom, and how many it holds.

        Raises:
            Error: If the model id names no model.
        """
        self.require_model(model)
        ref m = self.models[model.value]
        ref first_chain = self.chains[m.first_chain]
        ref last_chain = self.chains[m.first_chain + m.chain_count - 1]
        ref first = self.residues[first_chain.first_residue]
        ref last = self.residues[
            last_chain.first_residue + last_chain.residue_count - 1
        ]
        return (
            first.first_atom,
            last.first_atom + last.atom_count - first.first_atom,
        )

    def bounds(self, model: ModelId) raises -> Tuple[V3, V3]:
        """Return the low and the high corner of a model's atom centers.

        Args:
            model: The model.

        Returns:
            The two corners, in meters.

        Raises:
            Error: If the model id names no model.
        """
        var span = self.model_atoms(model)
        var low = self.atoms[span[0]].position
        var high = low
        for index in range(span[0], span[0] + span[1]):  # pragma: no branch
            var p = self.atoms[index].position
            low = v3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
            high = v3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        return (low, high)


def _number(text: String, name: String, line: Int) raises -> Float64:
    """Read a finite number of the atom site table."""
    var value: Float64
    try:
        value = atof(text)
    except:
        raise Error(
            String("Atom row ", line, ": the ", name, " is not a number")
        )
    if not isfinite(value):
        raise Error(String("Atom row ", line, ": the ", name, " is not finite"))
    return value


def _integer(
    text: String, fallback: Int, name: String, line: Int
) raises -> Int:
    """Read an integer of the atom site table, or a fallback for a null."""
    if is_null(text):
        return fallback
    try:
        return atol(text)
    except:
        raise Error(
            String("Atom row ", line, ": the ", name, " is not an integer")
        )


def _group(text: String, line: Int) raises -> AtomGroup:
    """Read the record group of an atom."""
    if text == "ATOM":
        return ATOM_RECORD
    if text == "HETATM":
        return HETATM_RECORD
    raise Error(String("Atom row ", line, ": the group is not ATOM or HETATM"))


def parse_mmcif(text: String, policy: AltLocPolicy) raises -> Structure:
    """Read the atoms of an mmCIF file into a structure.

    The `_atom_site` table needs `group_PDB`, `type_symbol`,
    `label_atom_id`, `label_comp_id`, `label_asym_id`, `label_seq_id` and
    `Cartn_x`, `Cartn_y` and `Cartn_z`. The other columns are optional:
    `id`, `label_alt_id`, `auth_asym_id`, `auth_seq_id`,
    `pdbx_PDB_ins_code`, `occupancy`, `B_iso_or_equiv` and
    `pdbx_PDB_model_num`.

    Args:
        text: The text of the file.
        policy: Which alternate locations to keep.

    Returns:
        The structure.

    Raises:
        Error: If the policy is not valid, the text is not CIF, a column
            that the reader needs is missing, a value is not a number, or
            the file has no atoms.
    """
    require_policy(policy)
    var block = parse_cif(text)
    var group = block.column("_atom_site.group_PDB")
    var rows = len(group)
    if rows == 0:
        raise Error("The mmCIF file has no atoms")
    var element = block.column("_atom_site.type_symbol")
    var atom_name = block.column("_atom_site.label_atom_id")
    var comp = block.column("_atom_site.label_comp_id")
    var asym = block.column("_atom_site.label_asym_id")
    var seq = block.column("_atom_site.label_seq_id")
    var xs = block.column("_atom_site.Cartn_x")
    var ys = block.column("_atom_site.Cartn_y")
    var zs = block.column("_atom_site.Cartn_z")
    var serial = block.column_or("_atom_site.id", "?", rows)
    var alt = block.column_or("_atom_site.label_alt_id", ".", rows)
    var author = block.column_or("_atom_site.auth_asym_id", "?", rows)
    var auth_seq = block.column_or("_atom_site.auth_seq_id", "?", rows)
    var insertion = block.column_or("_atom_site.pdbx_PDB_ins_code", "?", rows)
    var occupancy = block.column_or("_atom_site.occupancy", "1", rows)
    var b_iso = block.column_or("_atom_site.B_iso_or_equiv", "0", rows)
    var model = block.column_or("_atom_site.pdbx_PDB_model_num", "1", rows)
    var out = Structure(block.name)
    var chosen = String("")
    for row in range(rows):  # pragma: no branch
        var line = row + 1
        var model_number = _integer(model[row], 1, "model number", line)
        var label_seq = _integer(seq[row], 0, "label_seq_id", line)
        var author_seq = _integer(auth_seq[row], label_seq, "auth_seq_id", line)
        var new_model = (
            len(out.models) == 0
            or out.models[len(out.models) - 1].number != model_number
        )
        if new_model:
            out.models.append(Model(model_number, len(out.chains), 0))
        var new_chain = (
            new_model or out.chains[len(out.chains) - 1].label != asym[row]
        )
        if new_chain:
            var chain_author = author[row]
            if is_null(chain_author):
                chain_author = asym[row]
            out.chains.append(
                Chain(
                    asym[row],
                    chain_author,
                    ModelId(len(out.models) - 1),
                    len(out.residues),
                    0,
                )
            )
            out.models[len(out.models) - 1].chain_count += 1
        var new_residue = new_chain or _residue_changed(
            out.residues[len(out.residues) - 1],
            comp[row],
            label_seq,
            author_seq,
            insertion[row],
        )
        if new_residue:
            out.residues.append(
                Residue(
                    comp[row],
                    label_seq,
                    author_seq,
                    insertion[row],
                    ChainId(len(out.chains) - 1),
                    len(out.atoms),
                    0,
                    COIL,
                )
            )
            out.chains[len(out.chains) - 1].residue_count += 1
            chosen = String("")
        var location = alt[row]
        if policy == FIRST_LOCATION and not is_null(location):
            if chosen == "":
                chosen = location
            if location != chosen:
                continue
        var position = v3(
            Length64(_number(xs[row], "x", line), ANGSTROM).value,
            Length64(_number(ys[row], "y", line), ANGSTROM).value,
            Length64(_number(zs[row], "z", line), ANGSTROM).value,
        )
        out.atoms.append(
            Atom(
                atom_name[row],
                element[row],
                _integer(serial[row], line, "id", line),
                _group(group[row], line),
                location,
                position,
                _number(occupancy[row], "occupancy", line),
                Area64(_number(b_iso[row], "B-factor", line), SQUARE_ANGSTROM),
                ResidueId(len(out.residues) - 1),
            )
        )
        out.residues[len(out.residues) - 1].atom_count += 1
    _assign_secondary(block, out)
    return out^


def _residue_changed(
    last: Residue,
    name: String,
    label_seq: Int,
    author_seq: Int,
    insertion: String,
) -> Bool:
    """Return whether a row starts a new residue."""
    if last.seq_id != label_seq or last.auth_seq_id != author_seq:
        return True
    return last.insertion != insertion or last.name != name


def _mark(
    mut out: Structure,
    chain: String,
    first: Int,
    last: Int,
    kind: SecondaryKind,
):
    """Give a run of residues of every model a secondary structure."""
    for c in range(len(out.chains)):  # pragma: no branch
        if out.chains[c].label != chain:
            continue
        var start = out.chains[c].first_residue
        # A parsed chain starts with the row of its first residue.
        for r in range(
            start, start + out.chains[c].residue_count
        ):  # pragma: no branch
            var seq_id = out.residues[r].seq_id
            if seq_id >= first and seq_id <= last:
                out.residues[r].secondary = kind


def _assign_secondary(block: CifBlock, mut out: Structure) raises:
    """Mark the helices and the strands that the file lists."""
    if block.has("_struct_conf.conf_type_id"):
        var kinds = block.column("_struct_conf.conf_type_id")
        var rows = len(kinds)
        var chains = block.column_or(
            "_struct_conf.beg_label_asym_id", "?", rows
        )
        var begins = block.column_or("_struct_conf.beg_label_seq_id", "?", rows)
        var ends = block.column_or("_struct_conf.end_label_seq_id", "?", rows)
        for row in range(rows):
            if not kinds[row].upper().startswith("HELX"):
                continue
            var first = _integer(begins[row], -1, "helix start", row + 1)
            var last = _integer(ends[row], -1, "helix end", row + 1)
            _mark(out, chains[row], first, last, HELIX)
    if block.has("_struct_sheet_range.beg_label_seq_id"):
        var begins = block.column("_struct_sheet_range.beg_label_seq_id")
        var rows = len(begins)
        var chains = block.column_or(
            "_struct_sheet_range.beg_label_asym_id", "?", rows
        )
        var ends = block.column_or(
            "_struct_sheet_range.end_label_seq_id", "?", rows
        )
        for row in range(rows):
            var first = _integer(begins[row], -1, "strand start", row + 1)
            var last = _integer(ends[row], -1, "strand end", row + 1)
            _mark(out, chains[row], first, last, STRAND)


def read_mmcif(path: String, policy: AltLocPolicy) raises -> Structure:
    """Read the atoms of an mmCIF file.

    Args:
        path: The file.
        policy: Which alternate locations to keep.

    Returns:
        The structure.

    Raises:
        Error: If the file cannot be read, or `parse_mmcif` refuses it.
    """
    return parse_mmcif(Path(path).read_text(), policy)
