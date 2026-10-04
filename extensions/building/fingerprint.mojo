# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fingerprint of a building model, for provenance.

A view of the model, such as a baked game mesh or an exchange file, stores
the fingerprint of the model it came from. A reader compares it with the
fingerprint of the model it has, to tell whether the view is current.

The fingerprint is the 64-bit FNV-1a hash of the model's content: storey
levels, space outlines and uses, element kinds, faces, constructions,
sections and axes, openings, furnishings, materials and constructions. Two models with
the same content have the same fingerprint. A change to any of those
values changes it, except with the small chance of a hash collision. It
is not a cryptographic hash.

See Fowler, Noll and Vo, "The FNV non-cryptographic hash algorithm"
(IETF draft, 2019).
"""

from std.memory import bitcast
from extensions.building.model import Building

comptime _OFFSET = UInt64(0xCBF29CE484222325)
comptime _PRIME = UInt64(0x100000001B3)


struct Fingerprint(Movable):
    """A running FNV-1a hash."""

    var value: UInt64

    def __init__(out self):
        """Start a hash."""
        self.value = _OFFSET

    def add_byte(mut self, byte: UInt8):
        """Mix one byte into the hash.

        Args:
            byte: The byte.
        """
        self.value = (self.value ^ UInt64(byte)) * _PRIME

    def add_int(mut self, value: Int):
        """Mix the eight bytes of an integer into the hash.

        Args:
            value: The integer.
        """
        var bits = UInt64(value)
        for i in range(8):  # pragma: no branch
            self.add_byte(UInt8((bits >> UInt64(8 * i)) & 0xFF))

    def add_float(mut self, value: Float64):
        """Mix the bits of a float into the hash.

        Args:
            value: The float.
        """
        self.add_int(Int(bitcast[DType.uint64](value)))

    def add_text(mut self, text: String):
        """Mix the bytes of a text into the hash, then its length.

        Args:
            text: The text.
        """
        var bytes = text.as_bytes()
        for i in range(len(bytes)):
            self.add_byte(bytes[i])
        self.add_int(len(bytes))


def fingerprint(building: Building) -> UInt64:
    """Return the fingerprint of a building model's content.

    Args:
        building: The model.

    Returns:
        The 64-bit FNV-1a hash of its content.
    """
    var h = Fingerprint()
    h.add_text(building.name)
    h.add_int(len(building.storeys))
    for i in range(len(building.storeys)):
        h.add_float(building.storeys[i].elevation.value)
        h.add_float(building.storeys[i].height.value)
    h.add_int(len(building.spaces))
    for i in range(len(building.spaces)):
        ref space = building.spaces[i]
        h.add_int(space.use.value)
        h.add_int(space.storey.value)
        h.add_int(len(space.outline))
        for k in range(len(space.outline)):
            h.add_float(space.outline[k].x)
            h.add_float(space.outline[k].y)
    h.add_int(len(building.elements))
    for i in range(len(building.elements)):
        ref element = building.elements[i]
        h.add_int(element.kind.value)
        h.add_int(len(element.faces))
        for k in range(len(element.faces)):
            h.add_int(element.faces[k].value)
        h.add_int(
            element.construction.value().value if element.construction else -1
        )
        h.add_int(element.material.value().value if element.material else -1)
        if element.section:
            var s = element.section.value()
            h.add_int(s.shape.value)
            h.add_float(s.width.value)
            h.add_float(s.depth.value)
            h.add_float(s.flange_thickness.value)
            h.add_float(s.web_thickness.value)
        h.add_float(element.start.x)
        h.add_float(element.start.y)
        h.add_float(element.start.z)
        h.add_float(element.end.x)
        h.add_float(element.end.y)
        h.add_float(element.end.z)
    h.add_int(len(building.openings))
    for i in range(len(building.openings)):
        ref opening = building.openings[i]
        h.add_int(opening.kind.value)
        h.add_int(opening.host.value)
        h.add_float(opening.offset.value)
        h.add_float(opening.sill.value)
        h.add_float(opening.width.value)
        h.add_float(opening.height.value)
    h.add_int(len(building.furnishings))
    for i in range(len(building.furnishings)):
        ref item = building.furnishings[i]
        h.add_int(item.kind.value)
        h.add_int(item.space.value)
        h.add_float(item.center.x)
        h.add_float(item.center.y)
        h.add_float(item.rotation.value)
        h.add_float(item.width.value)
        h.add_float(item.depth.value)
        h.add_float(item.height.value)
    h.add_int(len(building.materials))
    for i in range(len(building.materials)):
        ref m = building.materials[i]
        h.add_text(m.name)
        h.add_float(m.density.value)
        h.add_float(m.elastic_modulus.value)
        h.add_float(m.conductivity.value)
        h.add_float(m.specific_heat.value)
    h.add_int(len(building.constructions))
    for i in range(len(building.constructions)):
        ref c = building.constructions[i]
        h.add_text(c.name)
        for k in range(len(c.layers)):
            h.add_int(c.layers[k].material.value)
            h.add_float(c.layers[k].thickness.value)
    return h.value
