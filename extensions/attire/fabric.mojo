# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What each fabric weighs, how thick it is, how it hangs and looks.

| Kind | Areal density | Thickness | Drape passes | Source |
|---|---|---|---|---|
| `LINEN` | 200 g/m² | 0.5 mm | 1 | Textile practice, 150 to 250 gsm |
| `WOOL` | 300 g/m² | 1.2 mm | 2 | Textile practice |
| `SILK` | 80 g/m² | 0.2 mm | 1 | Textile practice |
| `VELVET` | 350 g/m² | 1.5 mm | 2 | Textile practice |
| `LEATHER` | 1.7 kg/m² | 2 mm | 3 | 2 mm at about 860 kg/m³ |
| `PADDING` | 2.4 kg/m² | 15 mm | 6 | Many layers of linen; Wikipedia, Gambeson |
| `MAIL` | 8.5 kg/m² | 3 mm | 3 | Set so the template's hauberk weighs 9.3 kg, as one at the Cleveland Museum of Art does |
| `PLATE` | 15.7 kg/m² | 2 mm | 24 | 2 mm of steel at 7,850 kg/m³; breastplates 1 to 2.5 mm |

The drape is how many smoothing passes the shell takes. One pass keeps
the skin's shape under a thin cloth. Many passes span the hollows, as a
stiff plate does. The clearance is the gap a garment keeps off the layer
under it.

These are template estimates. Each value carries an `Evidence` grade.
The areal densities of mail and plate are derived from the cited masses
and thicknesses, so they are graded `DESIGN`.

This is not a three.js port. See Extensions.

    var mail = fabric(MAIL)
    var look = fabric_material(MAIL, Color(255, 255, 255))
"""

from extensions.anatomy.evidence import DESIGN, FROM_TEXT, Cited
from extensions.attire.kinds import (
    LEATHER,
    LINEN,
    MAIL,
    PADDING,
    PLATE,
    SILK,
    VELVET,
    WOOL,
    FabricKind,
    require_fabric_kind,
)
from extensions.attire.quantities import (
    ArealDensity,
    GRAM_PER_SQUARE_METER,
    KILOGRAM_PER_SQUARE_METER,
)
from materials.material import SCENE_ENVIRONMENT, Material, physical_material
from render.framebuffer import Color
from units.si import MILLIMETER, Length


struct Fabric(Copyable, Movable):
    """The constants of one fabric."""

    var kind: FabricKind
    """What the fabric is."""
    var areal_density: ArealDensity
    """Its mass per area."""
    var thickness: Length
    """How far its outer face stands off its inner face."""
    var clearance: Length
    """The gap it keeps off the layer under it."""
    var drape: Int
    """Smoothing passes: one follows the body, many span its hollows."""
    var source: Cited
    """Where the areal density and the thickness come from."""

    def __init__(
        out self,
        kind: FabricKind,
        areal_density: ArealDensity,
        thickness: Length,
        clearance: Length,
        drape: Int,
        var source: Cited,
    ):
        """Hold the constants of one fabric.

        Args:
            kind: What the fabric is.
            areal_density: Its mass per area.
            thickness: How thick it is.
            clearance: The gap it keeps off the layer under it.
            drape: Smoothing passes of its shell.
            source: Where the numbers come from.
        """
        self.kind = kind
        self.areal_density = areal_density
        self.thickness = thickness
        self.clearance = clearance
        self.drape = drape
        self.source = source^


def _gsm(value: Float32) -> ArealDensity:
    """Return an areal density in grams per square meter."""
    return ArealDensity(value, GRAM_PER_SQUARE_METER)


def _mm(value: Float32) -> Length:
    """Return a length in millimeters."""
    return Length(value, MILLIMETER)


def fabric(kind: FabricKind) raises -> Fabric:
    """Return the constants of a fabric kind.

    Args:
        kind: A named fabric kind.

    Returns:
        Its areal density, thickness, clearance, drape and source.

    Raises:
        Error: If `kind` is not named.
    """
    require_fabric_kind(kind)
    var practice = Cited(DESIGN, "TextilePractice")
    if kind == LINEN:
        return Fabric(kind, _gsm(200), _mm(0.5), _mm(2), 1, practice^)
    if kind == WOOL:
        return Fabric(kind, _gsm(300), _mm(1.2), _mm(2), 2, practice^)
    if kind == SILK:
        return Fabric(kind, _gsm(80), _mm(0.2), _mm(1.5), 1, practice^)
    if kind == VELVET:
        return Fabric(kind, _gsm(350), _mm(1.5), _mm(2), 2, practice^)
    if kind == LEATHER:
        return Fabric(kind, _gsm(1700), _mm(2), _mm(2), 3, practice^)
    if kind == PADDING:
        return Fabric(
            kind, _gsm(2400), _mm(15), _mm(2), 6, Cited(FROM_TEXT, "Gambeson")
        )
    if kind == MAIL:
        return Fabric(
            kind,
            ArealDensity(8.5, KILOGRAM_PER_SQUARE_METER),
            _mm(3),
            _mm(1),
            3,
            Cited(DESIGN, "ClevelandHauberk"),
        )
    return Fabric(
        kind,
        ArealDensity(15.7, KILOGRAM_PER_SQUARE_METER),
        _mm(2),
        _mm(4),
        24,
        Cited(DESIGN, "LazarKraner2019"),
    )


def fold_depth(kind: FabricKind) raises -> Length:
    """Return how deep a skirt of a fabric folds at its hem.

    | Kind | Fold |
    |---|---|
    | `LINEN`, `SILK` | 18 mm |
    | `WOOL`, `VELVET` | 25 mm |
    | `LEATHER`, `MAIL` | 6 mm |
    | `PADDING` | 4 mm |
    | `PLATE` | none |

    Thin, soft cloth hangs in deep folds; stiff fabric hardly folds, and
    plate not at all. These are design values for the look, not measured.

    Args:
        kind: A named fabric kind.

    Returns:
        The depth of the folds at the hem.

    Raises:
        Error: If `kind` is not named.
    """
    require_fabric_kind(kind)
    if kind == LINEN or kind == SILK:
        return _mm(18)
    if kind == WOOL or kind == VELVET:
        return _mm(25)
    if kind == LEATHER or kind == MAIL:
        return _mm(6)
    if kind == PADDING:
        return _mm(4)
    return _mm(0)


def fabric_material(kind: FabricKind, tint: Color) raises -> Material:
    """Return a physically based look for a fabric.

    Cloth takes a sheen, the lobe of cloth and velvet. Leather takes a
    faint clear coat. Mail is a rough metal; its rings scatter the light.
    Plate is a polished metal under a thin clear coat. Every look reads
    the garment's vertex colors, which carry its dyes and its wear. Every
    look reflects the scene's environment; a metal shows little else, so
    give the scene one.

    Args:
        kind: A named fabric kind.
        tint: The base color, multiplied by the vertex colors. White
            leaves the dyes as they are.

    Returns:
        A `PHYSICAL` material with vertex colors on.

    Raises:
        Error: If `kind` is not named, or the material constructor
            refuses the values.
    """
    require_fabric_kind(kind)
    var look: Material
    if kind == MAIL:
        look = physical_material(
            tint,
            roughness=0.55,
            metalness=0.85,
            env_map=SCENE_ENVIRONMENT,
        )
    elif kind == PLATE:
        look = physical_material(
            tint,
            roughness=0.32,
            metalness=0.9,
            env_map=SCENE_ENVIRONMENT,
            clearcoat=0.2,
            clearcoat_roughness=0.2,
        )
    elif kind == LEATHER:
        look = physical_material(
            tint,
            roughness=0.6,
            clearcoat=0.25,
            clearcoat_roughness=0.4,
            env_map=SCENE_ENVIRONMENT,
        )
    elif kind == SILK:
        look = physical_material(
            tint,
            roughness=0.35,
            env_map=SCENE_ENVIRONMENT,
            sheen=1.0,
            sheen_color=Color(255, 255, 255),
            sheen_roughness=0.3,
        )
    elif kind == VELVET:
        look = physical_material(
            tint,
            roughness=0.9,
            env_map=SCENE_ENVIRONMENT,
            sheen=1.0,
            sheen_color=tint,
            sheen_roughness=0.25,
        )
    else:
        look = physical_material(
            tint,
            roughness=0.85,
            env_map=SCENE_ENVIRONMENT,
            sheen=0.6,
            sheen_color=Color(230, 230, 230),
            sheen_roughness=0.6,
        )
    look.vertex_colors = True
    return look^
