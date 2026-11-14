# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids and kinds of a molecular structure.

Each is a type, so a bare integer cannot stand in for one. An id is an
index into one list of a `Structure`. `is_valid` checks the sign only. A
structure checks the upper bound where it reads the id.
"""

from core.ordinal import ordinal_valid, require_valid


@fieldwise_init
struct AtomId(Equatable, ImplicitlyCopyable, Writable):
    """An atom: its index in `Structure.atoms`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index an atom.
        """
        return self.value >= 0


@fieldwise_init
struct ResidueId(Equatable, ImplicitlyCopyable, Writable):
    """A residue: its index in `Structure.residues`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a residue.
        """
        return self.value >= 0


@fieldwise_init
struct ChainId(Equatable, ImplicitlyCopyable, Writable):
    """A chain: its index in `Structure.chains`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a chain.
        """
        return self.value >= 0


@fieldwise_init
struct ModelId(Equatable, ImplicitlyCopyable, Writable):
    """A model: its index in `Structure.models`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a model.
        """
        return self.value >= 0


def require_index(valid: Bool, index: Int, count: Int, name: String) raises:
    """Refuse an id that does not name an entry.

    Args:
        valid: Whether the id's `is_valid` holds.
        index: The id's index.
        count: How many entries the list holds.
        name: The kind of entry, for the error text.

    Raises:
        Error: If the id is negative or past the last entry.
    """
    if not valid or index >= count:
        raise Error(
            "The " + name + " id names no " + name + " of this structure"
        )


@fieldwise_init
struct AtomGroup(Equatable, ImplicitlyCopyable, Writable):
    """The record group of an atom: `ATOM` or `HETATM`.

    `ATOM` is an atom of a standard residue of a polymer. `HETATM` is any
    other atom, such as a ligand, an ion or a water.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two groups.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime ATOM_RECORD = AtomGroup(0)
comptime HETATM_RECORD = AtomGroup(1)


def require_group(group: AtomGroup) raises:
    """Refuse an atom group that is not one of the two.

    Args:
        group: The group to check.

    Raises:
        Error: If `group` is not valid.
    """
    require_valid(group.is_valid(), "An atom group must be 0 or 1")


@fieldwise_init
struct SecondaryKind(Equatable, ImplicitlyCopyable, Writable):
    """The secondary structure of a residue.

    `COIL` is neither of the others. `HELIX` is a helix of any kind.
    `STRAND` is a strand of a beta sheet.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three kinds.

        Returns:
            Whether the value is from zero to two.
        """
        return ordinal_valid(self.value, 2)


comptime COIL = SecondaryKind(0)
comptime HELIX = SecondaryKind(1)
comptime STRAND = SecondaryKind(2)


def require_secondary(kind: SecondaryKind) raises:
    """Refuse a secondary structure kind that is not one of the three.

    Args:
        kind: The kind to check.

    Raises:
        Error: If `kind` is not valid.
    """
    require_valid(kind.is_valid(), "A secondary structure must be from 0 to 2")


@fieldwise_init
struct AltLocPolicy(Equatable, ImplicitlyCopyable, Writable):
    """Which alternate locations a reader keeps.

    `ALL_LOCATIONS` keeps every atom. `FIRST_LOCATION` keeps the atoms
    with no alternate location, and in each residue the atoms of the first
    alternate location that the file gives.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two policies.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime ALL_LOCATIONS = AltLocPolicy(0)
comptime FIRST_LOCATION = AltLocPolicy(1)


def require_policy(policy: AltLocPolicy) raises:
    """Refuse an alternate location policy that is not one of the two.

    Args:
        policy: The policy to check.

    Raises:
        Error: If `policy` is not valid.
    """
    require_valid(
        policy.is_valid(), "An alternate location policy must be 0 or 1"
    )


@fieldwise_init
struct RibbonColoring(Equatable, ImplicitlyCopyable, Writable):
    """How a ribbon is colored.

    `BY_STRUCTURE` colors helices, strands and coils apart. `BY_CHAIN`
    gives each chain its own color.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two colorings.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)


comptime BY_STRUCTURE = RibbonColoring(0)
comptime BY_CHAIN = RibbonColoring(1)


def require_coloring(coloring: RibbonColoring) raises:
    """Refuse a ribbon coloring that is not one of the two.

    Args:
        coloring: The coloring to check.

    Raises:
        Error: If `coloring` is not valid.
    """
    require_valid(coloring.is_valid(), "A ribbon coloring must be 0 or 1")


@fieldwise_init
struct SurfaceColoring(Equatable, ImplicitlyCopyable, Writable):
    """How a molecular surface is colored.

    `COLOR_BY_ELEMENT` gives each vertex the CPK color of its atom.
    `COLOR_BY_B_FACTOR` runs from blue at the least B-factor of the model
    to red at the largest. `COLOR_BY_CHAIN` gives each chain its own
    color. `COLOR_BY_HYDROPATHY` runs from blue for the most hydrophilic
    residue to orange for the most hydrophobic, on the scale of Kyte and
    Doolittle.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four colorings.

        Returns:
            Whether the value is from zero to three.
        """
        return ordinal_valid(self.value, 3)


comptime COLOR_BY_ELEMENT = SurfaceColoring(0)
comptime COLOR_BY_B_FACTOR = SurfaceColoring(1)
comptime COLOR_BY_CHAIN = SurfaceColoring(2)
comptime COLOR_BY_HYDROPATHY = SurfaceColoring(3)


def require_surface_coloring(coloring: SurfaceColoring) raises:
    """Refuse a surface coloring that is not one of the four.

    Args:
        coloring: The coloring to check.

    Raises:
        Error: If `coloring` is not valid.
    """
    require_valid(coloring.is_valid(), "A surface coloring must be from 0 to 3")
