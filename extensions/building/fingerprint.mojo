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
    h.add_text("ThreeMojo Building fingerprint v2")
    h.add_text(building.name)
    h.add_float(building.site.latitude.value)
    h.add_float(building.site.longitude.value)
    h.add_float(building.site.elevation.value)
    h.add_float(building.site.north.value)
    h.add_int(len(building.storeys))
    for i in range(len(building.storeys)):
        h.add_text(building.storeys[i].name)
        h.add_float(building.storeys[i].elevation.value)
        h.add_float(building.storeys[i].height.value)
    h.add_int(len(building.spaces))
    for i in range(len(building.spaces)):
        ref space = building.spaces[i]
        h.add_text(space.name)
        h.add_int(space.cell.value)
        h.add_int(space.use.value)
        h.add_int(space.storey.value)
        h.add_int(len(space.outline))
        for k in range(len(space.outline)):
            h.add_float(space.outline[k].x)
            h.add_float(space.outline[k].y)
    h.add_int(len(building.elements))
    for i in range(len(building.elements)):
        ref element = building.elements[i]
        h.add_text(element.name)
        h.add_int(element.storey.value)
        h.add_int(element.kind.value)
        h.add_int(len(element.faces))
        for k in range(len(element.faces)):
            h.add_int(element.faces[k].value)
        h.add_int(1 if element.construction else 0)
        h.add_int(
            element.construction.value().value if element.construction else -1
        )
        h.add_int(1 if element.material else 0)
        h.add_int(element.material.value().value if element.material else -1)
        h.add_int(1 if element.section else 0)
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
        h.add_text(opening.name)
        h.add_int(opening.kind.value)
        h.add_int(opening.host.value)
        h.add_float(opening.offset.value)
        h.add_float(opening.sill.value)
        h.add_float(opening.width.value)
        h.add_float(opening.height.value)
        h.add_int(1 if opening.glazing else 0)
        if opening.glazing:
            var glazing = opening.glazing.value()
            h.add_float(glazing.u_value.value)
            h.add_float(glazing.solar_heat_gain)
            h.add_float(glazing.visible_transmittance)
    h.add_int(len(building.furnishings))
    for i in range(len(building.furnishings)):
        ref item = building.furnishings[i]
        h.add_text(item.name)
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
        h.add_float(m.poisson_ratio)
        h.add_float(m.strength.value)
        h.add_float(m.thermal_expansion.value)
        h.add_float(Float64(m.look.red))
        h.add_float(Float64(m.look.green))
        h.add_float(Float64(m.look.blue))
        h.add_float(Float64(m.look.roughness))
        h.add_float(Float64(m.look.metalness))
        h.add_float(Float64(m.look.transmission))
    h.add_int(len(building.constructions))
    for i in range(len(building.constructions)):
        ref c = building.constructions[i]
        h.add_text(c.name)
        h.add_int(len(c.layers))
        for k in range(len(c.layers)):
            h.add_int(c.layers[k].material.value)
            h.add_float(c.layers[k].thickness.value)
    # These public arrays are also read by views. Hash the geometry and
    # the maps, not its private caches or assembly weld tolerance. The
    # tolerance controls future input merging, not this model's content.
    ref topology = building.topology
    ref complex = topology.complex
    h.add_int(len(complex.welder.points))
    for i in range(len(complex.welder.points)):
        var point = complex.welder.points[i]
        h.add_float(point.x)
        h.add_float(point.y)
        h.add_float(point.z)
    h.add_int(len(complex.faces))
    for i in range(len(complex.faces)):
        ref face = complex.faces[i]
        h.add_int(face.kind.value)
        h.add_int(1 if face.positive else 0)
        h.add_int(face.positive.value().value if face.positive else -1)
        h.add_int(1 if face.negative else 0)
        h.add_int(face.negative.value().value if face.negative else -1)
        h.add_int(len(face.loop))
        for k in range(len(face.loop)):
            h.add_int(face.loop[k].value)
    h.add_int(len(complex.edges))
    for i in range(len(complex.edges)):
        h.add_int(complex.edges[i].a.value)
        h.add_int(complex.edges[i].b.value)
    h.add_int(len(complex.cell_faces))
    for i in range(len(complex.cell_faces)):
        h.add_int(len(complex.cell_faces[i]))
        for k in range(len(complex.cell_faces[i])):
            h.add_int(complex.cell_faces[i][k].value)
    h.add_int(len(complex.edge_faces))
    for i in range(len(complex.edge_faces)):
        h.add_int(len(complex.edge_faces[i]))
        for k in range(len(complex.edge_faces[i])):
            h.add_int(complex.edge_faces[i][k].value)
    h.add_int(len(topology.cell_storey))
    for i in range(len(topology.cell_storey)):
        h.add_int(topology.cell_storey[i])
    h.add_int(len(topology.cell_region))
    for i in range(len(topology.cell_region)):
        h.add_int(topology.cell_region[i].value)
    h.add_int(len(topology.face_level))
    for i in range(len(topology.face_level)):
        h.add_int(topology.face_level[i])
    h.add_int(len(building.face_element))
    for i in range(len(building.face_element)):
        h.add_int(building.face_element[i])
    return h.value
