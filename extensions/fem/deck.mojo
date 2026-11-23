# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Input decks of CalculiX and Abaqus, read and written.

An input deck is a text file of keyword lines, which start with `*`, and
data lines. `parse_deck` reads the static subset that this port can
solve: nodes, four-node and ten-node tetrahedra, node and element sets,
elastic materials, solid sections, boundary conditions, point loads and
gravity. `Deck.problem` gives a `StaticProblem`. `deck_text` writes a
`StaticProblem` as a deck, so CalculiX can run the same model.

A keyword outside the subset raises an error. The reader does not skip
what it cannot honor, because a skipped keyword changes the answer.

A deck has no units. `DeckUnits` gives the length and the force of one
deck unit. The other units follow from them.

The format is that of Dhondt, "CalculiX CrunchiX User's Manual", and of
the Abaqus keyword manual. The code is original and shares no source
with CalculiX.
"""

from std.collections import Dict
from std.math import isfinite
from std.pathlib import Path
from math.finite import require_finite, require_positive_finite
from loaders.text_number import file_line
from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import (
    DofAxis,
    ElementId,
    LINEAR,
    MaterialId,
    NodeId,
    QUADRATIC,
)
from extensions.fem.mesh import TetMesh, signed_volume
from extensions.fem.static import StaticProblem
from extensions.sdf.vector import V3, dot, v3
from units.si import (
    Acceleration64,
    Density64,
    Force64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND_SQUARED,
    NEWTON,
    PASCAL,
    Pressure64,
)

# The largest number of entries that one GENERATE line can make.
comptime MAX_GENERATED = 16777216


struct DeckUnits(ImplicitlyCopyable):
    """The length and the force of one deck unit."""

    # Meters in one deck length.
    var length: Float64
    # Newtons in one deck force.
    var force: Float64

    def __init__(out self, length: Length64, force: Force64) raises:
        """Create the units of a deck.

        Args:
            length: The length of one deck unit. Positive.
            force: The force of one deck unit. Positive.

        Raises:
            Error: If a unit is not positive and finite.
        """
        var l = length.to(METER)
        var f = force.to(NEWTON)
        require_positive_finite(l, "A deck length must be positive and finite")
        require_positive_finite(f, "A deck force must be positive and finite")
        self.length = l
        self.force = f

    def stress(self) -> Float64:
        """Return the pascals in one deck stress.

        Returns:
            The force over the length squared.
        """
        return self.force / (self.length * self.length)

    def density(self) -> Float64:
        """Return the kilograms per cubic meter in one deck density.

        A deck mass is a force times a second squared over a length.

        Returns:
            The force over the fourth power of the length.
        """
        var area = self.length * self.length
        return self.force / (area * area)


def si_units() raises -> DeckUnits:
    """Return meters and newtons, with pascals and kg/m³.

    Returns:
        The units.

    Raises:
        Error: Never.
    """
    return DeckUnits(Length64(1), Force64(1))


def millimeter_units() raises -> DeckUnits:
    """Return millimeters and newtons, with megapascals and tonnes/mm³.

    Returns:
        The units that most CalculiX decks use.

    Raises:
        Error: Never.
    """
    return DeckUnits(Length64(0.001), Force64(1))


@fieldwise_init
struct DeckValue(ImplicitlyCopyable):
    """A value on one degree of freedom of one node."""

    # The index of the node in the mesh.
    var node: Int
    # The axis, 0 to 2.
    var axis: Int
    # Meters for a support and newtons for a load.
    var value: Float64


struct Deck(Movable):
    """What a deck holds, in meters, newtons and kilograms."""

    var mesh: TetMesh
    var materials: List[IsotropicMaterial]
    var material_names: List[String]
    # The density of each material, in kilograms per cubic meter. Zero if
    # the deck gives none.
    var densities: List[Float64]
    # The deck number of each node and of each element.
    var node_numbers: List[Int]
    var element_numbers: List[Int]
    # The node and element indices of each set, by its name in capitals.
    var node_sets: Dict[String, List[Int]]
    var element_sets: Dict[String, List[Int]]
    var supports: List[DeckValue]
    var loads: List[DeckValue]
    # The acceleration of gravity, in meters per second squared. Zero if
    # the deck has no gravity load.
    var gravity: Float64
    var gravity_direction: V3
    var _node_index: Dict[Int, Int]
    var _element_index: Dict[Int, Int]

    def __init__(out self):
        """Create an empty deck. `parse_deck` fills it."""
        self.mesh = TetMesh()
        self.materials = List[IsotropicMaterial]()
        self.material_names = List[String]()
        self.densities = List[Float64]()
        self.node_numbers = List[Int]()
        self.element_numbers = List[Int]()
        self.node_sets = Dict[String, List[Int]]()
        self.element_sets = Dict[String, List[Int]]()
        self.supports = List[DeckValue]()
        self.loads = List[DeckValue]()
        self.gravity = 0
        self.gravity_direction = v3(0, 0, -1)
        self._node_index = Dict[Int, Int]()
        self._element_index = Dict[Int, Int]()

    def node(self, number: Int) raises -> NodeId:
        """Return the mesh node of a deck node number.

        Args:
            number: The number in the deck.

        Returns:
            The node.

        Raises:
            Error: If the deck has no node of that number.
        """
        var index = self._node_index.get(number, -1)
        if index < 0:
            raise Error("The deck has no node ", number)
        return NodeId(index)

    def element(self, number: Int) raises -> ElementId:
        """Return the mesh element of a deck element number.

        Args:
            number: The number in the deck.

        Returns:
            The element.

        Raises:
            Error: If the deck has no element of that number.
        """
        var index = self._element_index.get(number, -1)
        if index < 0:
            raise Error("The deck has no element ", number)
        return ElementId(index)

    def problem(self) raises -> StaticProblem:
        """Return the static problem of the deck.

        Returns:
            The mesh and the materials, with the supports, the point loads
            and the gravity load of the deck.

        Raises:
            Error: If the deck has no element, or a gravity load meets a
                direction of zero.
        """
        var problem = StaticProblem(self.mesh.copy(), self.materials.copy())
        for i in range(len(self.supports)):
            var s = self.supports[i]
            problem.fix(NodeId(s.node), DofAxis(s.axis), Length64(s.value))
        for i in range(len(self.loads)):
            var l = self.loads[i]
            problem.load(NodeId(l.node), DofAxis(l.axis), Force64(l.value))
        if self.gravity != 0:
            var densities = List[Density64]()
            for i in range(len(self.densities)):  # pragma: no branch
                densities.append(
                    Density64(self.densities[i], KILOGRAM_PER_CUBIC_METER)
                )
            problem.apply_gravity(
                densities,
                Acceleration64(self.gravity, METER_PER_SECOND_SQUARED),
                self.gravity_direction,
            )
        return problem^


def _fields(text: String, separator: String) -> List[String]:
    """Return the fields of a line, each with no space around it."""
    var parts = text.split(separator)
    var out = List[String](capacity=len(parts))
    for i in range(len(parts)):  # pragma: no branch
        out.append(String(parts[i].strip()))
    return out^


def _upper(text: String) -> String:
    """Return a field in capitals, with one space between its words."""
    var words = text.upper().split()
    var out = String("")
    for i in range(len(words)):
        if i > 0:
            out += " "
        out += String(words[i])
    return out


def _real(field: String, what: String, line: Int) raises -> Float64:
    """Return a field as a finite number."""
    var value: Float64
    try:
        value = atof(field)
    except:
        raise Error(file_line("deck", line), what, " is not a number")
    require_finite(value, file_line("deck", line) + what + " must be finite")
    return value


def _whole(field: String, what: String, line: Int) raises -> Int:
    """Return a field as an integer."""
    try:
        return atol(field)
    except:
        raise Error(file_line("deck", line), what, " is not an integer")


struct _Reader(Movable):
    """A deck under construction and the state of its reader."""

    var deck: Deck
    var units: DeckUnits
    # The keyword that the data lines belong to.
    var keyword: String
    # The parameters of that keyword, in capitals.
    var parameters: Dict[String, String]
    # The numbers of an element whose data continues on the next line.
    var pending: List[Int]
    var continues: Bool
    # The material that *ELASTIC and *DENSITY belong to, or -1.
    var material: Int
    var has_elastic: List[Bool]
    # The element set and the material of each solid section.
    var section_sets: List[String]
    var section_materials: List[String]
    var steps: Int
    var in_step: Bool
    var has_gravity: Bool
    # The members of each set, as its name, `#` and an index.
    var members: Dict[String, Bool]

    def __init__(out self, units: DeckUnits):
        """Create a reader with an empty deck."""
        self.deck = Deck()
        self.units = units
        self.keyword = String("")
        self.parameters = Dict[String, String]()
        self.pending = List[Int]()
        self.continues = False
        self.material = -1
        self.has_elastic = List[Bool]()
        self.section_sets = List[String]()
        self.section_materials = List[String]()
        self.steps = 0
        self.in_step = False
        self.has_gravity = False
        self.members = Dict[String, Bool]()

    def _need(self, name: String, line: Int) raises -> String:
        """Return a parameter that the keyword must have."""
        if name not in self.parameters:
            raise Error(
                file_line("deck", line), self.keyword, " needs ", name, "="
            )
        return self.parameters[name]

    def _in_step(self, line: Int) raises:
        """Refuse a keyword that is outside a step."""
        if not self.in_step:
            raise Error(
                file_line("deck", line), self.keyword, " must be in a *STEP"
            )

    def _in_material(self, line: Int) raises:
        """Refuse a keyword that is outside a material."""
        if self.material < 0:
            raise Error(
                file_line("deck", line),
                self.keyword,
                " must follow a *MATERIAL",
            )

    def start(mut self, text: String, line: Int) raises:
        """Read a keyword line."""
        if self.continues:
            raise Error(file_line("deck", line), "an element ends with a comma")
        var fields = _fields(text, ",")
        self.keyword = _upper(fields[0])
        self.parameters = Dict[String, String]()
        for i in range(1, len(fields)):
            var pair = _fields(fields[i], "=")
            var name = _upper(pair[0])
            if name.byte_length() == 0:
                continue
            var value = String("")
            if len(pair) > 1:
                value = _upper(pair[1])
            self.parameters[name] = value
        var k = self.keyword
        if k == "*NODE" or k == "*BOUNDARY" or k == "*HEADING":
            return
        if k == "*ELEMENT":
            var kind = self._need("TYPE", line)
            if kind != "C3D4" and kind != "C3D10":
                raise Error(
                    file_line("deck", line),
                    "element type ",
                    kind,
                    " is not supported. Use C3D4 or C3D10.",
                )
            return
        if k == "*NSET":
            _ = self._need("NSET", line)
            return
        if k == "*ELSET":
            _ = self._need("ELSET", line)
            return
        if k == "*MATERIAL":
            var name = self._need("NAME", line)
            for i in range(len(self.deck.material_names)):
                if self.deck.material_names[i] == name:
                    raise Error(
                        file_line("deck", line), "material ", name, " repeats"
                    )
            self.deck.material_names.append(name)
            self.deck.densities.append(0)
            # A place holder until *ELASTIC gives the constants.
            self.deck.materials.append(IsotropicMaterial(Pressure64(1), 0))
            self.has_elastic.append(False)
            self.material = len(self.deck.material_names) - 1
            return
        if k == "*ELASTIC":
            self._in_material(line)
            if self.parameters.get("TYPE", "ISO") != "ISO":
                raise Error(
                    file_line("deck", line), "*ELASTIC must have TYPE=ISO"
                )
            return
        if k == "*DENSITY":
            self._in_material(line)
            return
        if k == "*SOLID SECTION":
            self.section_sets.append(self._need("ELSET", line))
            self.section_materials.append(self._need("MATERIAL", line))
            return
        if k == "*STEP":
            if "NLGEOM" in self.parameters:
                raise Error(
                    file_line("deck", line),
                    "NLGEOM is not supported. The analysis is linear.",
                )
            if self.steps > 0:
                raise Error(
                    file_line("deck", line), "a deck can have one *STEP only"
                )
            self.steps = 1
            self.in_step = True
            return
        if k == "*STATIC" or k == "*CLOAD" or k == "*DLOAD":
            self._in_step(line)
            return
        if k == "*END STEP":
            self._in_step(line)
            self.in_step = False
            return
        if (
            k == "*NODE FILE"
            or k == "*EL FILE"
            or k == "*NODE PRINT"
            or k == "*EL PRINT"
        ):
            return
        raise Error(file_line("deck", line), "keyword ", k, " is not supported")

    def _join(mut self, name: String, index: Int, is_node: Bool) raises:
        """Add an index to a set once."""
        var key = name + "#" + String(index)
        if is_node:
            key = "N" + key
        if key in self.members:
            return
        self.members[key] = True
        if is_node:
            if name not in self.deck.node_sets:
                self.deck.node_sets[name] = List[Int]()
            self.deck.node_sets[name].append(index)
        else:
            if name not in self.deck.element_sets:
                self.deck.element_sets[name] = List[Int]()
            self.deck.element_sets[name].append(index)

    def _node(mut self, fields: List[String], line: Int) raises:
        """Read a data line of *NODE."""
        if len(fields) < 4:
            raise Error(
                file_line("deck", line), "a node needs a number and x, y, z"
            )
        var number = _whole(fields[0], "A node number", line)
        if number < 1 or number in self.deck._node_index:
            raise Error(
                file_line("deck", line),
                "a node number must be positive and new",
            )
        var scale = self.units.length
        var id = self.deck.mesh.add_node(
            v3(
                _real(fields[1], "A coordinate", line) * scale,
                _real(fields[2], "A coordinate", line) * scale,
                _real(fields[3], "A coordinate", line) * scale,
            )
        )
        self.deck._node_index[number] = id.value
        self.deck.node_numbers.append(number)
        if "NSET" in self.parameters:
            var name = String(self.parameters["NSET"])
            self._join(name, id.value, True)

    def _element(mut self, fields: List[String], line: Int) raises:
        """Read a data line of *ELEMENT, which can continue."""
        for i in range(len(fields)):  # pragma: no branch
            if fields[i].byte_length() == 0:
                continue
            self.pending.append(_whole(fields[i], "An element entry", line))
        self.continues = fields[len(fields) - 1].byte_length() == 0
        if self.continues:
            return
        var quadratic = self.parameters["TYPE"] == "C3D10"
        var count = 4
        if quadratic:
            count = 10
        if len(self.pending) != count + 1:
            raise Error(
                file_line("deck", line),
                "an element of this type needs a number and ",
                count,
                " nodes",
            )
        var number = self.pending[0]
        if number < 1 or number in self.deck._element_index:
            raise Error(
                file_line("deck", line),
                "an element number must be positive and new",
            )
        var nodes = List[Int]()
        for i in range(1, count + 1):  # pragma: no branch
            var index = self.deck._node_index.get(self.pending[i], -1)
            if index < 0:
                raise Error(
                    file_line("deck", line),
                    "an element names node ",
                    self.pending[i],
                    ", which the deck does not have yet",
                )
            nodes.append(index)
        self.pending.clear()
        var existing = self.deck.mesh.element_count()
        if existing > 0 and (self.deck.mesh.order == QUADRATIC) != quadratic:
            raise Error(
                file_line("deck", line),
                "a deck cannot mix C3D4 and C3D10 elements",
            )
        if quadratic:
            self._ten_nodes(nodes, line)
        else:
            _ = self.deck.mesh.add_element(
                NodeId(nodes[0]),
                NodeId(nodes[1]),
                NodeId(nodes[2]),
                NodeId(nodes[3]),
                MaterialId(0),
            )
        # No section has given the element a material yet.
        self.deck.mesh.materials[existing] = -1
        self.deck._element_index[number] = existing
        self.deck.element_numbers.append(number)
        if "ELSET" in self.parameters:
            var name = String(self.parameters["ELSET"])
            self._join(name, existing, False)

    def _ten_nodes(mut self, nodes: List[Int], line: Int) raises:
        """Add a ten-node element, turned so that its volume is positive."""
        ref points = self.deck.mesh.nodes
        var a = points[nodes[0]]
        var b = points[nodes[1]]
        var c = points[nodes[2]]
        var d = points[nodes[3]]
        var volume = signed_volume(a, b, c, d)
        var edges = dot(b - a, b - a) + dot(c - a, c - a) + dot(d - a, d - a)
        if not (abs(volume) > 1.0e-6 * edges * (edges**0.5)):
            raise Error(
                file_line("deck", line),
                "a tetrahedron needs four corners that are not flat",
            )
        # The edge nodes follow the edges 1-2, 2-3, 1-3, 1-4, 2-4 and 3-4.
        # A swap of corners 3 and 4 swaps the nodes of 2-3 with 2-4 and of
        # 1-3 with 1-4.
        var order = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        if volume < 0:
            order = [0, 1, 3, 2, 4, 8, 7, 6, 5, 9]
        self.deck.mesh.order = QUADRATIC
        for i in range(10):
            self.deck.mesh.corners.append(nodes[order[i]])
        self.deck.mesh.materials.append(0)

    def _set(mut self, fields: List[String], line: Int, is_node: Bool) raises:
        """Read a data line of *NSET or *ELSET."""
        var name: String
        if is_node:
            name = self.parameters["NSET"]
        else:
            name = self.parameters["ELSET"]
        var numbers = List[Int]()
        if "GENERATE" in self.parameters:
            if len(fields) < 2:
                raise Error(
                    file_line("deck", line),
                    "GENERATE needs a first and a last number",
                )
            var first = _whole(fields[0], "A first number", line)
            var last = _whole(fields[1], "A last number", line)
            var step = 1
            if len(fields) > 2 and fields[2].byte_length() > 0:
                step = _whole(fields[2], "A step", line)
            if step < 1 or last < first:
                raise Error(
                    file_line("deck", line),
                    (
                        "GENERATE needs a positive step and a last number that"
                        " is not below the first"
                    ),
                )
            if (last - first) // step >= MAX_GENERATED:
                raise Error(
                    file_line("deck", line), "GENERATE makes too many entries"
                )
            var number = first
            while number <= last:
                numbers.append(number)
                number += step
        else:
            for i in range(len(fields)):  # pragma: no branch
                if fields[i].byte_length() > 0:
                    numbers.append(_whole(fields[i], "A set entry", line))
        for i in range(len(numbers)):
            var index: Int
            if is_node:
                index = self.deck._node_index.get(numbers[i], -1)
            else:
                index = self.deck._element_index.get(numbers[i], -1)
            if index < 0:
                raise Error(
                    file_line("deck", line),
                    "a set names number ",
                    numbers[i],
                    ", which the deck does not have yet",
                )
            self._join(name, index, is_node)

    def _targets(self, field: String, line: Int) raises -> List[Int]:
        """Return the nodes that a node number or a node set names."""
        var number: Int
        try:
            number = atol(field)
        except:
            var name = _upper(field)
            if name not in self.deck.node_sets:
                raise Error(
                    file_line("deck", line), "the deck has no node set ", name
                )
            return self.deck.node_sets[name].copy()
        var index = self.deck._node_index.get(number, -1)
        if index < 0:
            raise Error(
                file_line("deck", line), "the deck has no node ", number
            )
        return [index]

    def _axis(self, field: String, line: Int) raises -> Int:
        """Return the axis of a degree of freedom from 1 to 3."""
        var dof = _whole(field, "A degree of freedom", line)
        if dof < 1 or dof > 3:
            raise Error(
                file_line("deck", line),
                (
                    "a degree of freedom must be 1, 2 or 3. A solid has no"
                    " rotations."
                ),
            )
        return dof - 1

    def _boundary(mut self, fields: List[String], line: Int) raises:
        """Read a data line of *BOUNDARY."""
        if len(fields) < 2:
            raise Error(
                file_line("deck", line),
                "a boundary needs a node and a degree of freedom",
            )
        var nodes = self._targets(fields[0], line)
        var first = self._axis(fields[1], line)
        var last = first
        if len(fields) > 2 and fields[2].byte_length() > 0:
            last = self._axis(fields[2], line)
        if last < first:
            raise Error(
                file_line("deck", line),
                "the last degree of freedom is below the first",
            )
        var value = Float64(0)
        if len(fields) > 3 and fields[3].byte_length() > 0:
            value = _real(fields[3], "A displacement", line) * self.units.length
        for i in range(len(nodes)):  # pragma: no branch
            for axis in range(first, last + 1):  # pragma: no branch
                self.deck.supports.append(DeckValue(nodes[i], axis, value))

    def _cload(mut self, fields: List[String], line: Int) raises:
        """Read a data line of *CLOAD."""
        if len(fields) < 3:
            raise Error(
                file_line("deck", line),
                "a load needs a node, a degree of freedom and a value",
            )
        var nodes = self._targets(fields[0], line)
        var axis = self._axis(fields[1], line)
        var value = _real(fields[2], "A load", line) * self.units.force
        for i in range(len(nodes)):  # pragma: no branch
            self.deck.loads.append(DeckValue(nodes[i], axis, value))

    def _dload(mut self, fields: List[String], line: Int) raises:
        """Read a data line of *DLOAD. Only GRAV on every element."""
        if len(fields) < 6 or _upper(fields[1]) != "GRAV":
            raise Error(
                file_line("deck", line),
                (
                    "the only distributed load is GRAV, with a size and a"
                    " direction"
                ),
            )
        if self.has_gravity:
            raise Error(
                file_line("deck", line), "a deck can have one GRAV load only"
            )
        var name = _upper(fields[0])
        if name.byte_length() > 0:
            if name not in self.deck.element_sets:
                raise Error(
                    file_line("deck", line),
                    "the deck has no element set ",
                    name,
                )
            var count = len(self.deck.element_sets[name])
            if count != self.deck.mesh.element_count():
                raise Error(
                    file_line("deck", line),
                    "GRAV must act on every element of the deck",
                )
        self.has_gravity = True
        self.deck.gravity = (
            _real(fields[2], "A gravity", line) * self.units.length
        )
        self.deck.gravity_direction = v3(
            _real(fields[3], "A direction", line),
            _real(fields[4], "A direction", line),
            _real(fields[5], "A direction", line),
        )

    def _material_value(mut self, fields: List[String], line: Int) raises:
        """Read a data line of *ELASTIC or *DENSITY."""
        if self.keyword == "*DENSITY":
            var density = _real(fields[0], "A density", line)
            if density < 0:
                raise Error(
                    file_line("deck", line), "a density must be zero or more"
                )
            self.deck.densities[self.material] = density * self.units.density()
            return
        if len(fields) < 2:
            raise Error(
                file_line("deck", line),
                "*ELASTIC needs Young's modulus and Poisson's ratio",
            )
        if self.has_elastic[self.material]:
            raise Error(
                file_line("deck", line),
                "a material can have one line of elastic constants only",
            )
        var young = _real(fields[0], "Young's modulus", line)
        var poisson = _real(fields[1], "Poisson's ratio", line)
        self.deck.materials[self.material] = IsotropicMaterial(
            Pressure64(young * self.units.stress(), PASCAL), poisson
        )
        self.has_elastic[self.material] = True

    def data(mut self, text: String, line: Int) raises:
        """Read a data line of the current keyword."""
        var fields = _fields(text, ",")
        var k = self.keyword
        if k == "*NODE":
            self._node(fields, line)
        elif k == "*ELEMENT":
            self._element(fields, line)
        elif k == "*NSET":
            self._set(fields, line, True)
        elif k == "*ELSET":
            self._set(fields, line, False)
        elif k == "*ELASTIC" or k == "*DENSITY":
            self._material_value(fields, line)
        elif k == "*BOUNDARY":
            self._boundary(fields, line)
        elif k == "*CLOAD":
            self._cload(fields, line)
        elif k == "*DLOAD":
            self._dload(fields, line)
        elif k == "*MATERIAL" or k == "*STEP" or k == "*END STEP" or k == "":
            raise Error(
                file_line("deck", line), "a data line has no keyword to own it"
            )
        # The other keywords have data that changes no result: a heading,
        # the time of a static step, a section thickness and the output
        # requests.

    def finish(deinit self) raises -> Deck:
        """Give each element its material, check the deck and return it."""
        if self.continues:
            raise Error("The deck ends in an element that ends with a comma")
        if self.in_step:
            raise Error("The deck ends in a *STEP with no *END STEP")
        ref mesh = self.deck.mesh
        if mesh.element_count() == 0:
            raise Error("The deck has no element")
        for m in range(len(self.has_elastic)):
            if not self.has_elastic[m]:
                raise Error(
                    "Material ",
                    self.deck.material_names[m],
                    " has no *ELASTIC",
                )
        for s in range(len(self.section_sets)):
            var material = -1
            for m in range(len(self.deck.material_names)):
                if self.deck.material_names[m] == self.section_materials[s]:
                    material = m
            if material < 0:
                raise Error(
                    "A section names material ",
                    self.section_materials[s],
                    ", which the deck does not have",
                )
            if self.section_sets[s] not in self.deck.element_sets:
                raise Error(
                    "A section names element set ",
                    self.section_sets[s],
                    ", which the deck does not have",
                )
            ref members = self.deck.element_sets[self.section_sets[s]]
            for i in range(len(members)):  # pragma: no branch
                mesh.materials[members[i]] = material
        var used = List[Bool](length=mesh.node_count(), fill=False)
        var per = mesh.nodes_per_element()
        for e in range(mesh.element_count()):  # pragma: no branch
            if mesh.materials[e] < 0:
                raise Error(
                    "Element ",
                    self.deck.element_numbers[e],
                    " has no *SOLID SECTION",
                )
            for i in range(per):  # pragma: no branch
                used[mesh.corners[per * e + i]] = True
        for n in range(len(used)):  # pragma: no branch
            if not used[n]:
                raise Error(
                    "Node ",
                    self.deck.node_numbers[n],
                    " belongs to no element",
                )
        return self.deck^


def parse_deck(text: String, units: DeckUnits) raises -> Deck:
    """Return what the text of an input deck holds.

    Args:
        text: The whole deck.
        units: The length and the force of one deck unit.

    Returns:
        The mesh, the materials, the sets, the supports and the loads.

    Raises:
        Error: If a keyword is outside the subset, a line is malformed, a
            number or a set is not defined before its use, an element has
            no section, a node belongs to no element, or the deck has no
            element. The message names the line where it can.
    """
    var reader = _Reader(units)
    var lines = text.split("\n")
    for i in range(len(lines)):  # pragma: no branch
        var line = String(lines[i].strip())
        if line.byte_length() == 0 or line.startswith("**"):
            continue
        if line.startswith("*"):
            reader.start(line, i + 1)
        else:
            reader.data(line, i + 1)
    return reader^.finish()


def read_deck(path: String, units: DeckUnits) raises -> Deck:
    """Return what an input deck file holds.

    Args:
        path: The file.
        units: The length and the force of one deck unit.

    Returns:
        The mesh, the materials, the sets, the supports and the loads.

    Raises:
        Error: If the file cannot be read, or `parse_deck` refuses it.
    """
    return parse_deck(Path(path).read_text(), units)


def deck_text(problem: StaticProblem, title: String) raises -> String:
    """Return a static problem as an input deck in SI units.

    The deck has one element set, one material and one section for each
    material that an element uses. Every force of the problem becomes a
    point load, so a pressure and a weight keep their consistent nodal
    forces. A number has the 16 digits that `String` gives it.

    Args:
        problem: The problem.
        title: One line for the heading. It must not start with `*`.

    Returns:
        The text of the deck. `parse_deck` with `si_units()` reads it
        back.

    Raises:
        Error: If the title has a line break or starts with `*`, or the
            problem has a thermal strain, which a point load cannot
            carry.
    """
    if "\n" in title or title.strip().startswith("*"):
        raise Error("A deck title must be one line that does not start with *")
    for e in range(len(problem.thermal)):  # pragma: no branch
        if problem.thermal[e] != 0:
            raise Error("A deck cannot carry the thermal strain of a problem")
    ref mesh = problem.mesh
    var out = String("*HEADING\n")
    out += title + "\n*NODE, NSET=NALL\n"
    for n in range(mesh.node_count()):  # pragma: no branch
        var p = mesh.nodes[n]
        out += String(n + 1, ", ", p.x, ", ", p.y, ", ", p.z, "\n")
    var per = mesh.nodes_per_element()
    var kind = String("C3D4")
    if mesh.order != LINEAR:
        kind = String("C3D10")
    for m in range(len(problem.materials)):  # pragma: no branch
        var any = False
        for e in range(mesh.element_count()):  # pragma: no branch
            if mesh.materials[e] != m:
                continue
            if not any:
                out += String("*ELEMENT, TYPE=", kind, ", ELSET=E", m + 1, "\n")
                any = True
            out += String(e + 1)
            for i in range(per):  # pragma: no branch
                out += String(", ", mesh.corners[per * e + i] + 1)
            out += "\n"
        out += String("*MATERIAL, NAME=M", m + 1, "\n*ELASTIC\n")
        out += String(
            problem.materials[m].young.to(PASCAL),
            ", ",
            problem.materials[m].poisson,
            "\n",
        )
        if any:
            out += String(
                "*SOLID SECTION, ELSET=E", m + 1, ", MATERIAL=M", m + 1, "\n"
            )
    out += "*BOUNDARY\n"
    for dof in range(len(problem.prescribed)):  # pragma: no branch
        if problem.prescribed[dof]:
            var axis = dof % 3 + 1
            out += String(
                dof // 3 + 1, ", ", axis, ", ", axis, ", ", problem.values[dof]
            )
            out += "\n"
    out += "*STEP\n*STATIC\n*CLOAD\n"
    for dof in range(len(problem.forces)):  # pragma: no branch
        if problem.forces[dof] != 0:
            out += String(
                dof // 3 + 1, ", ", dof % 3 + 1, ", ", problem.forces[dof], "\n"
            )
    out += "*NODE FILE\nU\n*EL FILE\nS\n*END STEP\n"
    return out
