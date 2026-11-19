# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Distance maps and contact maps of the residues of a model.

A distance map gives the distance between one atom of each residue and
the same atom of every other residue, such as the CA atoms. It shows the
fold of a chain at a glance: a helix is a band along the diagonal, two
strands that pair are a line across it, and two domains are blocks.

A contact is a pair of residues closer than a cutoff, such as 8
angstroms between CA atoms, that are far enough apart in the chain. A
residue of another chain is always far enough. Structure prediction
compares contact maps, because they do not change when a model turns.

`map_image` draws a map, one pixel per pair: dark blue at zero distance,
through light blue, to white at `far` and beyond.
"""

from extensions.molecule.ids import ModelId
from extensions.molecule.structure import Structure
from extensions.sdf.vector import distance
from render.framebuffer import Color, Framebuffer
from std.math import isfinite, min
from units.si import Length64, METER


struct DistanceMap(Copyable, Movable):
    """The distances between one atom of each residue of a model."""

    var residues: List[Int]
    """The residue of each row, an index into `structure.residues`."""
    var chains: List[Int]
    """The chain of each row."""
    var distances: List[Float64]
    """The distance of each pair, row by row, in meters."""

    def __init__(out self):
        """Create an empty map."""
        self.residues = List[Int]()
        self.chains = List[Int]()
        self.distances = List[Float64]()

    def count(self) -> Int:
        """Return the number of rows.

        Returns:
            The residues that have the atom.
        """
        return len(self.residues)

    def distance(self, row: Int, column: Int) raises -> Length64:
        """Return the distance of one pair.

        Args:
            row: The first row.
            column: The second row.

        Returns:
            The distance between the two atoms.

        Raises:
            Error: If a row is outside the map.
        """
        var n = self.count()
        if row < 0 or row >= n or column < 0 or column >= n:
            raise Error("A distance map row is outside the map")
        return Length64(self.distances[row * n + column], METER)

    def contacts(
        self, cutoff: Length64, separation: Int
    ) raises -> List[Tuple[Int, Int]]:
        """Return the pairs of rows in contact.

        Args:
            cutoff: The largest distance of a contact. Positive and finite.
            separation: The least number of residues between the two
                rows of one chain, such as 6. One or more.

        Returns:
            Each pair once, the lower row first, in row order.

        Raises:
            Error: If the cutoff is not positive and finite, or the
                separation is less than one.
        """
        var limit = cutoff.to(METER)
        if not (limit > 0) or not isfinite(limit):
            raise Error("A contact cutoff must be positive and finite")
        if separation < 1:
            raise Error("A contact separation must be one or more")
        var n = self.count()
        var out = List[Tuple[Int, Int]]()
        for i in range(n):
            for j in range(i + 1, n):
                var apart = (
                    self.chains[i] != self.chains[j] or j - i >= separation
                )
                if apart and self.distances[i * n + j] <= limit:
                    out.append((i, j))
        return out^


def distance_map(
    structure: Structure, model: ModelId, name: String
) raises -> DistanceMap:
    """Return the distance map of one atom of each residue of a model.

    A residue without an atom of that name has no row. Of two atoms of
    one name in a residue, such as alternate locations, the first counts.

    Args:
        structure: The structure.
        model: The model.
        name: The atom name, such as `CA` or `CB`.

    Returns:
        The map.

    Raises:
        Error: If the model id names no model, or no residue has the atom.
    """
    structure.require_model(model)
    ref m = structure.models[model.value]
    var out = DistanceMap()
    var places = List[Int]()
    for c in range(
        m.first_chain, m.first_chain + m.chain_count
    ):  # pragma: no branch
        ref chain = structure.chains[c]
        for r in range(  # pragma: no branch
            chain.first_residue, chain.first_residue + chain.residue_count
        ):
            ref residue = structure.residues[r]
            for a in range(  # pragma: no branch
                residue.first_atom, residue.first_atom + residue.atom_count
            ):
                if structure.atoms[a].name == name:
                    out.residues.append(r)
                    out.chains.append(c)
                    places.append(a)
                    break
    var n = len(places)
    if n == 0:
        raise Error("No residue of the model has an atom named " + name)
    out.distances = List[Float64](length=n * n, fill=0)
    for i in range(n):  # pragma: no branch
        for j in range(i + 1, n):
            var d = distance(
                structure.atoms[places[i]].position,
                structure.atoms[places[j]].position,
            )
            out.distances[i * n + j] = d
            out.distances[j * n + i] = d
    return out^


def map_image(map: DistanceMap, far: Length64) raises -> Framebuffer:
    """Draw a distance map, one pixel per pair, the first row at the top.

    Args:
        map: The map.
        far: The distance drawn white. Positive and finite.

    Returns:
        An image of `count` by `count` pixels: dark blue at zero, light
        blue halfway, and white at `far` and beyond.

    Raises:
        Error: If `far` is not positive and finite, or the map is empty.
    """
    var limit = far.to(METER)
    if not (limit > 0) or not isfinite(limit):
        raise Error("A map's far distance must be positive and finite")
    var n = map.count()
    if n == 0:
        raise Error("An empty distance map has no image")
    var image = Framebuffer(n, n, Color(255, 255, 255))
    for i in range(n):  # pragma: no branch
        for j in range(n):  # pragma: no branch
            var t = min(map.distances[i * n + j] / limit, 1.0)
            var r = UInt8(Int(20 + 235 * t * t))
            var g = UInt8(Int(40 + 215 * t))
            var b = UInt8(Int(110 + 145 * t))
            image.set_pixel(j, i, Color(r, g, b))
    return image^
