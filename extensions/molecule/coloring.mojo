# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Color a molecular surface by a property of the atom under each vertex.

`color_surface` finds, for each vertex, the atom whose van der Waals
sphere is nearest: the least `|p - center| - radius`. The vertex then
takes a color from that atom, by one of four `SurfaceColoring` kinds:

- `COLOR_BY_ELEMENT`: the CPK color of the element.
- `COLOR_BY_B_FACTOR`: blue at the least B-factor of the model, white
  halfway and red at the largest.
- `COLOR_BY_CHAIN`: the color of the atom's chain, as the ribbons have.
- `COLOR_BY_HYDROPATHY`: blue at -4.5 on the scale of Kyte and Doolittle,
  white at 0 and orange at +4.5. A residue that is not one of the twenty
  amino acids is gray.

The colors are linear, as the renderer takes them.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from extensions.chemistry.quantities import ANGSTROM
from extensions.molecule.ids import (
    COLOR_BY_B_FACTOR,
    COLOR_BY_CHAIN,
    COLOR_BY_ELEMENT,
    ModelId,
    SurfaceColoring,
    require_surface_coloring,
)
from extensions.molecule.ribbon import chain_color
from extensions.molecule.structure import Structure
from extensions.molecule.surface import AtomCells, vdw_radius
from extensions.sdf.vector import V3, distance, v3
from loaders.pdb import cpk_color
from render.srgb import srgb_to_linear
from std.math import max, min
from units.si import Length64, METER, SQUARE_METER

# The gray of an element without a CPK color, or a residue without a
# hydropathy.
comptime NEUTRAL_GRAY = 0.78


def kyte_doolittle(residue: String) -> Tuple[Bool, Float64]:
    """Return the hydropathy of an amino acid, after Kyte and Doolittle.

    Args:
        residue: The three-letter residue name, such as `ILE`.

    Returns:
        Whether the name is one of the twenty amino acids, and its value
        from -4.5 (arginine) to +4.5 (isoleucine). Zero for another name.
    """
    var names: List[String] = [
        "ILE",
        "VAL",
        "LEU",
        "PHE",
        "CYS",
        "MET",
        "ALA",
        "GLY",
        "THR",
        "SER",
        "TRP",
        "TYR",
        "PRO",
        "HIS",
        "GLU",
        "GLN",
        "ASP",
        "ASN",
        "LYS",
        "ARG",
    ]
    var values: List[Float64] = [
        4.5,
        4.2,
        3.8,
        2.8,
        2.5,
        1.9,
        1.8,
        -0.4,
        -0.7,
        -0.8,
        -0.9,
        -1.3,
        -1.6,
        -3.2,
        -3.5,
        -3.5,
        -3.5,
        -3.5,
        -3.9,
        -4.5,
    ]
    for index in range(len(names)):  # pragma: no branch
        if names[index] == residue:
            return (True, values[index])
    return (False, 0.0)


def _blend(a: V3, b: V3, t: Float64) -> V3:
    """Return the sRGB blend of two colors."""
    return a + (b - a) * t


def _diverging(low: V3, high: V3, t: Float64) -> V3:
    """Return a color from `low` at -1 through white at 0 to `high` at 1."""
    var white = v3(0.96, 0.96, 0.96)
    var s = min(max(t, -1.0), 1.0)
    if s < 0:
        return _blend(white, low, -s)
    return _blend(white, high, s)


def _linear(srgb: V3) -> V3:
    """Return the linear color of an sRGB color."""
    return v3(
        Float64(srgb_to_linear(Float32(srgb.x))),
        Float64(srgb_to_linear(Float32(srgb.y))),
        Float64(srgb_to_linear(Float32(srgb.z))),
    )


def atom_color(
    structure: Structure, model: ModelId, atom: Int, coloring: SurfaceColoring
) raises -> V3:
    """Return the sRGB color of one atom of a model, by a coloring.

    Args:
        structure: The structure.
        model: The model that holds the atom.
        atom: The index of the atom in `structure.atoms`.
        coloring: How to color.

    Returns:
        A color from 0 to 1 in each channel.

    Raises:
        Error: If the model id names no model, the atom is not in it, or
            the coloring is not valid.
    """
    require_surface_coloring(coloring)
    var span = structure.model_atoms(model)
    if atom < span[0] or atom >= span[0] + span[1]:
        raise Error("The atom is not in the model")
    var b_range = _b_range(structure, model)
    return _color_of(structure, model, atom, coloring, b_range)


def _b_range(
    structure: Structure, model: ModelId
) raises -> Tuple[Float64, Float64]:
    """Return the least and the largest B-factor of a model, in m^2."""
    var span = structure.model_atoms(model)
    var low = structure.atoms[span[0]].b_factor.to(SQUARE_METER)
    var high = low
    # The callers check that the model holds an atom.
    for index in range(span[0], span[0] + span[1]):  # pragma: no branch
        var b = structure.atoms[index].b_factor.to(SQUARE_METER)
        low = min(low, b)
        high = max(high, b)
    return (low, high)


def _color_of(
    structure: Structure,
    model: ModelId,
    atom: Int,
    coloring: SurfaceColoring,
    b_range: Tuple[Float64, Float64],
) -> V3:
    """Return the sRGB color of one atom, with the model's B-factor range."""
    ref a = structure.atoms[atom]
    if coloring == COLOR_BY_ELEMENT:
        var rgb = cpk_color(a.element.lower())
        if rgb[0] < 0:
            return v3(NEUTRAL_GRAY, NEUTRAL_GRAY, NEUTRAL_GRAY)
        return v3(
            Float64(rgb[0]) / 255, Float64(rgb[1]) / 255, Float64(rgb[2]) / 255
        )
    ref residue = structure.residues[a.residue.value]
    if coloring == COLOR_BY_CHAIN:
        var first = structure.models[model.value].first_chain
        return chain_color(residue.chain.value - first)
    var blue = v3(0.2, 0.4, 0.85)
    if coloring == COLOR_BY_B_FACTOR:
        var low = b_range[0]
        var high = b_range[1]
        var t = 0.0
        if high > low:
            t = 2.0 * (a.b_factor.to(SQUARE_METER) - low) / (high - low) - 1.0
        return _diverging(blue, v3(0.85, 0.2, 0.2), t)
    var scale = kyte_doolittle(residue.name)
    if not scale[0]:
        return v3(NEUTRAL_GRAY, NEUTRAL_GRAY, NEUTRAL_GRAY)
    return _diverging(blue, v3(0.95, 0.55, 0.15), scale[1] / 4.5)


def color_surface(
    mut geometry: BufferGeometry,
    structure: Structure,
    model: ModelId,
    coloring: SurfaceColoring,
) raises:
    """Set the color of each vertex of a surface from its nearest atom.

    The nearest atom is the one whose van der Waals sphere is nearest the
    vertex. The `color` attribute is replaced with linear colors.

    Args:
        geometry: A mesh in meters, such as `excluded_surface` makes.
        structure: The structure.
        model: The model whose atoms color the surface.
        coloring: How to color.

    Raises:
        Error: If the model id names no model, the coloring is not valid,
            or the geometry has no positions.
    """
    require_surface_coloring(coloring)
    # A model holds a chain, a chain a residue, and a residue an atom.
    var span = structure.model_atoms(model)
    var centers = List[V3]()
    var radii = List[Float64]()
    var largest = 0.0
    var colors = List[V3]()
    var b_range = _b_range(structure, model)
    for index in range(span[0], span[0] + span[1]):  # pragma: no branch
        ref atom = structure.atoms[index]
        centers.append(atom.position)
        var r = vdw_radius(atom.element).to(METER)
        radii.append(r)
        largest = max(largest, r)
        var srgb = _color_of(structure, model, index, coloring, b_range)
        colors.append(_linear(srgb))
    # A cell holds a sphere and the gap of a probe of 1.4 angstroms.
    var size = largest + Length64(1.4, ANGSTROM).to(METER)
    var cells = AtomCells(centers, size)
    ref points = geometry.attribute_view(POSITION)
    var out = List[Float32]()
    for vertex in range(points.count()):
        var p = points.vector3(vertex)
        var at = v3(Float64(p.x), Float64(p.y), Float64(p.z))
        var near = cells.near(at)
        if len(near) == 0:
            # Far from every atom: look at them all.
            for index in range(len(centers)):  # pragma: no branch
                near.append(index)
        var best = near[0]
        var gap = distance(at, centers[best]) - radii[best]
        for index in near:  # pragma: no branch
            var d = distance(at, centers[index]) - radii[index]
            if d < gap:
                gap = d
                best = index
        out.append(Float32(colors[best].x))
        out.append(Float32(colors[best].y))
        out.append(Float32(colors[best].z))
    geometry.set_attribute(String(COLOR), BufferAttribute(out^, 3))
