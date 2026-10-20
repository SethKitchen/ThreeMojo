# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Construction kits: the materials, the layered constructions and the
construction set of one way of building, ready for `assemble`.

A kit is the part of a building that other buildings can reuse. A scan,
a procedural tower and an imported plan that use the masonry kit have the
same brick walls and concrete floors, so their engineering views read the
same materials. Each kit gives the five constructions that a
`ConstructionSet` names, in its order: the outside wall, the partition,
the ground slab, the floor and the roof.

- **Masonry**: solid brick walls and concrete floors, as in a European
  apartment block or row house.
- **Stone**: thick stone masonry walls, stone vaults and a timber roof, as
  in a church, a castle or a Roman temple.
- **Concrete**: an insulated concrete wall, stud partitions and concrete
  slabs, as in a recent block.
- **Timber**: an insulated timber frame on a concrete ground slab, as in
  a North American house.

The values are typical, not design values, as in
`extensions.building.material`. Stone masonry is the one material the
material library does not have. Its strength is that of historic rubble
and ashlar masonry in lime mortar, which is far below that of the stone
itself.
"""

from core.ordinal import ordinal_label, ordinal_valid
from extensions.building.construction import Construction, Layer
from extensions.building.ids import ConstructionId, MaterialId
from extensions.building.material import (
    BuildingMaterial,
    Look,
    brick,
    concrete,
    gypsum_board,
    mineral_wool,
    timber,
)
from extensions.building.model import ConstructionSet
from units.si import (
    Density64,
    GIGAPASCAL,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    MEGAPASCAL,
    METER,
    PER_KELVIN,
    Pressure64,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    ThermalExpansion64,
    WATT_PER_METER_KELVIN,
)


@fieldwise_init
struct KitKind(Equatable, ImplicitlyCopyable, Writable):
    """Which construction kit."""

    var value: Int
    """The stored ordinal."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the 4 kits.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 4 - 1)

    def name(self) -> String:
        """Return the kit's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = ["masonry", "stone", "concrete", "timber"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


comptime MASONRY_KIT = KitKind(0)
"""Solid brick walls and concrete floors."""
comptime STONE_KIT = KitKind(1)
"""Thick stone masonry walls, stone vaults and a timber roof."""
comptime CONCRETE_KIT = KitKind(2)
"""An insulated concrete wall, stud partitions and concrete slabs."""
comptime TIMBER_KIT = KitKind(3)
"""An insulated timber frame on a concrete ground slab."""


def kit_kind(name: String) raises -> KitKind:
    """Return the kit that a name gives.

    Args:
        name: `masonry`, `stone`, `concrete` or `timber`.

    Returns:
        The kit.

    Raises:
        Error: If the name is not one of the four.
    """
    for value in range(4):
        if KitKind(value).name() == name:
            return KitKind(value)
    raise Error("Kit: '" + name + "' is not a construction kit")


def stone_masonry() -> BuildingMaterial:
    """Return historic stone masonry in lime mortar.

    Returns:
        2200 kg/m³, 3 GPa, a compressive strength of 3 MPa and a
        conductivity of 1.7 W/(m K).
    """
    return BuildingMaterial(
        "stone masonry",
        Density64(2200, KILOGRAM_PER_CUBIC_METER),
        Pressure64(3, GIGAPASCAL),
        0.2,
        Pressure64(3, MEGAPASCAL),
        ThermalConductivity64(1.7, WATT_PER_METER_KELVIN),
        SpecificHeatCapacity64(1000, JOULE_PER_KILOGRAM_KELVIN),
        ThermalExpansion64(6e-6, PER_KELVIN),
        Look(0.62, 0.58, 0.52, 0.9, 0, 0),
    )


struct ConstructionKit(Copyable, Movable):
    """A kit's materials, constructions and construction set."""

    var kind: KitKind
    """Which kit."""
    var materials: List[BuildingMaterial]
    """The materials that the constructions name."""
    var constructions: List[Construction]
    """The outside wall, partition, ground slab, floor and roof, in order."""
    var defaults: ConstructionSet
    """The constructions that `assemble` gives each kind of face."""

    def __init__(
        out self,
        kind: KitKind,
        var materials: List[BuildingMaterial],
        var constructions: List[Construction],
    ):
        """Hold a kit whose constructions are in the set's order.

        Args:
            kind: Which kit.
            materials: The materials.
            constructions: The five constructions.
        """
        self.kind = kind
        self.materials = materials^
        self.constructions = constructions^
        self.defaults = ConstructionSet(
            ConstructionId(0),
            ConstructionId(1),
            ConstructionId(2),
            ConstructionId(3),
            ConstructionId(4),
        )

    def check(self) raises:
        """Refuse a kit that `assemble` would refuse.

        Raises:
            Error: If the kind is not valid, a material or a construction
                is not valid, or the kit does not have five constructions.
        """
        if not self.kind.is_valid():
            raise Error("Kit: a kit kind is 0 to 3")
        if len(self.constructions) != 5:
            raise Error("Kit: a kit has five constructions")
        for material in self.materials:
            material.check()
        for construction in self.constructions:  # pragma: no branch
            construction.check(self.materials)


def _layer(material: Int, meters: Float64) -> Layer:
    """Return a layer of a kit material, `meters` thick."""
    return Layer(MaterialId(material), Length64(meters, METER))


def construction_kit(kind: KitKind) raises -> ConstructionKit:
    """Return a kit; see the module docstring.

    Args:
        kind: Which kit.

    Returns:
        The kit, checked.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("Kit: a kit kind is 0 to 3")
    var materials = List[BuildingMaterial]()
    var constructions = List[Construction]()
    if kind == MASONRY_KIT:
        materials.append(brick())
        materials.append(gypsum_board())
        materials.append(concrete())
        materials.append(mineral_wool())
        materials.append(timber())
        constructions.append(
            Construction("brick wall", [_layer(0, 0.365), _layer(1, 0.015)])
        )
        constructions.append(
            Construction("brick partition", [_layer(0, 0.115)])
        )
        constructions.append(Construction("ground slab", [_layer(2, 0.2)]))
        constructions.append(Construction("floor slab", [_layer(2, 0.18)]))
        constructions.append(
            Construction("timber roof", [_layer(3, 0.2), _layer(4, 0.1)])
        )
    elif kind == STONE_KIT:
        materials.append(stone_masonry())
        materials.append(timber())
        constructions.append(Construction("stone wall", [_layer(0, 1.2)]))
        constructions.append(Construction("stone partition", [_layer(0, 0.6)]))
        constructions.append(Construction("flagstone floor", [_layer(0, 0.3)]))
        constructions.append(Construction("stone vault", [_layer(0, 0.4)]))
        constructions.append(Construction("timber roof", [_layer(1, 0.15)]))
    elif kind == CONCRETE_KIT:
        materials.append(concrete())
        materials.append(mineral_wool())
        materials.append(gypsum_board())
        constructions.append(
            Construction(
                "insulated concrete wall",
                [_layer(1, 0.12), _layer(0, 0.2), _layer(2, 0.0125)],
            )
        )
        constructions.append(
            Construction(
                "stud partition",
                [_layer(2, 0.0125), _layer(1, 0.075), _layer(2, 0.0125)],
            )
        )
        constructions.append(Construction("ground slab", [_layer(0, 0.25)]))
        constructions.append(Construction("floor slab", [_layer(0, 0.22)]))
        constructions.append(
            Construction("concrete roof", [_layer(1, 0.2), _layer(0, 0.22)])
        )
    else:
        materials.append(timber())
        materials.append(mineral_wool())
        materials.append(gypsum_board())
        materials.append(concrete())
        constructions.append(
            Construction(
                "timber frame wall",
                [_layer(0, 0.022), _layer(1, 0.14), _layer(2, 0.0125)],
            )
        )
        constructions.append(
            Construction(
                "stud partition",
                [_layer(2, 0.0125), _layer(1, 0.075), _layer(2, 0.0125)],
            )
        )
        constructions.append(Construction("ground slab", [_layer(3, 0.15)]))
        constructions.append(Construction("timber floor", [_layer(0, 0.22)]))
        constructions.append(
            Construction("timber roof", [_layer(0, 0.05), _layer(1, 0.2)])
        )
    var kit = ConstructionKit(kind, materials^, constructions^)
    kit.check()
    return kit^
