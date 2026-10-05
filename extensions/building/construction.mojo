# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Layered constructions and glazing.

A `Construction` is an ordered list of layers, each a material and a
thickness, from the outside face to the inside face. A wall, a floor and a
roof each have one. Its thermal transmittance is the inverse of the sum of
the layer resistances and the two surface film resistances, the method of
ISO 6946. The film resistances depend on the direction of heat flow:
`HORIZONTAL_FLOW` for a wall, `UPWARD_FLOW` for a roof or a ceiling and
`DOWNWARD_FLOW` for a floor over a colder space.

A `Glazing` is a window's whole-unit thermal transmittance, its solar heat
gain coefficient and its visible transmittance. These are the three
numbers of the simple glazing model that thermal programs use for a
window without a layer-by-layer description.
"""

from std.math import isfinite
from extensions.building.ids import MaterialId
from extensions.building.material import BuildingMaterial
from units.si import (
    Area64,
    HeatCapacity64,
    Length64,
    METER,
    SQUARE_METER,
    SQUARE_METER_KELVIN_PER_WATT,
    ThermalResistance64,
    ThermalTransmittance64,
    WATT_PER_SQUARE_METER_KELVIN,
)


@fieldwise_init
struct FlowDirection(Equatable, ImplicitlyCopyable, Writable):
    """Which way heat crosses a construction, for its film resistances."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three directions.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime HORIZONTAL_FLOW = FlowDirection(0)
comptime UPWARD_FLOW = FlowDirection(1)
comptime DOWNWARD_FLOW = FlowDirection(2)


def inside_film(direction: FlowDirection) raises -> ThermalResistance64:
    """Return the inside surface resistance of ISO 6946.

    Args:
        direction: Which way heat flows.

    Returns:
        0.13 m² K/W for horizontal flow, 0.10 upward and 0.17 downward.

    Raises:
        Error: If the direction is not valid.
    """
    if not direction.is_valid():
        raise Error("A flow direction must be horizontal, upward or downward")
    var values: List[Float64] = [0.13, 0.10, 0.17]
    return ThermalResistance64(
        values[direction.value], SQUARE_METER_KELVIN_PER_WATT
    )


def outside_film() -> ThermalResistance64:
    """Return the outside surface resistance of ISO 6946.

    Returns:
        0.04 m² K/W, for every direction.
    """
    return ThermalResistance64(0.04, SQUARE_METER_KELVIN_PER_WATT)


@fieldwise_init
struct Layer(ImplicitlyCopyable):
    """One layer of a construction: a material and a thickness."""

    var material: MaterialId
    var thickness: Length64


struct Construction(Copyable, Movable):
    """Layers from the outside face to the inside face."""

    var name: String
    var layers: List[Layer]

    def __init__(out self, var name: String, var layers: List[Layer]):
        """Create a construction. Call `check` before use.

        Args:
            name: A name for people and for exchange files.
            layers: The layers, outside first.
        """
        self.name = name^
        self.layers = layers^

    def check(self, materials: List[BuildingMaterial]) raises:
        """Refuse a construction that cannot be built.

        Args:
            materials: The materials its layers name.

        Raises:
            Error: If it has no layers, a layer names a material that is
                not in the list, or a thickness is not positive and finite.
        """
        if len(self.layers) == 0:
            raise Error("A construction needs a layer")
        for i in range(len(self.layers)):  # pragma: no branch
            ref layer = self.layers[i]
            if not layer.material.is_valid() or layer.material.value >= len(
                materials
            ):
                raise Error("A layer's material id is out of range")
            var t = layer.thickness.to(METER)
            if not (t > 0 and isfinite(t)):
                raise Error("A layer must be positive and finite")

    def thickness(self) -> Length64:
        """Return the sum of the layer thicknesses.

        Returns:
            The total thickness.
        """
        var total = Length64(0)
        for i in range(len(self.layers)):
            total = total + self.layers[i].thickness
        return total

    def resistance(
        self, materials: List[BuildingMaterial]
    ) raises -> ThermalResistance64:
        """Return the sum of the layer resistances, without the films.

        Args:
            materials: The materials its layers name.

        Returns:
            The sum of thickness over conductivity.

        Raises:
            Error: If `check` refuses the construction.
        """
        self.check(materials)
        var total = ThermalResistance64(0)
        for i in range(len(self.layers)):  # pragma: no branch
            ref layer = self.layers[i]
            total = total + (
                layer.thickness / materials[layer.material.value].conductivity
            )
        return total

    def u_value(
        self, materials: List[BuildingMaterial], direction: FlowDirection
    ) raises -> ThermalTransmittance64:
        """Return the thermal transmittance with both surface films.

        Args:
            materials: The materials its layers name.
            direction: Which way heat flows.

        Returns:
            1 / (Rsi + sum of layer resistances + Rse).

        Raises:
            Error: If `check` refuses the construction or the direction is
                not valid.
        """
        var total = (
            inside_film(direction) + self.resistance(materials) + outside_film()
        )
        var one = Area64(1, SQUARE_METER) / Area64(1, SQUARE_METER)
        return one / total

    def heat_capacity_per_area(
        self, materials: List[BuildingMaterial]
    ) raises -> HeatCapacity64:
        """Return the heat stored per kelvin by one square meter.

        Args:
            materials: The materials its layers name.

        Returns:
            The sum of density times specific heat times thickness, times
            one square meter.

        Raises:
            Error: If `check` refuses the construction.
        """
        self.check(materials)
        var total = HeatCapacity64(0)
        var area = Area64(1, SQUARE_METER)
        for i in range(len(self.layers)):  # pragma: no branch
            ref layer = self.layers[i]
            ref material = materials[layer.material.value]
            total = total + (
                material.density
                * material.specific_heat
                * layer.thickness
                * area
            )
        return total


@fieldwise_init
struct Glazing(ImplicitlyCopyable):
    """A window unit by the simple glazing model."""

    var u_value: ThermalTransmittance64
    # The share of incident solar radiation that enters as heat, normal
    # incidence. From zero to one.
    var solar_heat_gain: Float64
    # The share of visible light that passes. From zero to one.
    var visible_transmittance: Float64

    def check(self) raises:
        """Refuse a glazing no window can have.

        Raises:
            Error: If the U-value is not positive and finite, or a share is
                outside zero to one.
        """
        var u = self.u_value.to(WATT_PER_SQUARE_METER_KELVIN)
        if not (u > 0 and isfinite(u)):
            raise Error("A glazing U-value must be positive and finite")
        if not (self.solar_heat_gain >= 0 and self.solar_heat_gain <= 1):
            raise Error("A solar heat gain coefficient must be zero to one")
        if not (
            self.visible_transmittance >= 0 and self.visible_transmittance <= 1
        ):
            raise Error("A visible transmittance must be zero to one")


def double_glazing() -> Glazing:
    """Return a typical low-emissivity double-glazed unit.

    Returns:
        1.6 W/(m² K), a solar heat gain coefficient of 0.4 and a visible
        transmittance of 0.7.
    """
    return Glazing(
        ThermalTransmittance64(1.6, WATT_PER_SQUARE_METER_KELVIN), 0.4, 0.7
    )
