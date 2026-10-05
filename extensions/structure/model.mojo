# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A linear-elastic structural model of frame members and flat shells.

A `StructuralModel` holds nodes, supports, members, shells, load cases,
loads and added masses. Each node has six degrees of freedom, named by
`Dof`. A support fixes some of them at zero. Loads belong to a load case,
so one model can carry several cases and one factored stiffness can solve
them all.

Coordinates are meters, z up. Gravity acts along -z.
"""

from std.math import isfinite
from extensions.building.material import BuildingMaterial
from extensions.building.model import Section
from extensions.structure.frame import member_axes
from extensions.structure.ids import LoadCaseId, MemberId, NodeId, ShellId
from extensions.structure.kinds import Dof
from extensions.structure.shell import ShellElement
from generators.utils import Vec3d
from units.si import (
    Acceleration64,
    Force64,
    KILOGRAM,
    Length64,
    LineLoad64,
    Mass64,
    METER_PER_SECOND_SQUARED,
    Moment64,
    NEWTON,
    NEWTON_METER,
    NEWTON_PER_METER,
    PASCAL,
    Pressure64,
)


struct Member(Copyable, Movable):
    """A frame member between two nodes."""

    var start: NodeId
    var end: NodeId
    var section: Section
    var material: BuildingMaterial
    # A vector in the plane of the local x and z axes, in global axes.
    var reference: Vec3d

    def __init__(
        out self,
        start: NodeId,
        end: NodeId,
        section: Section,
        var material: BuildingMaterial,
        reference: Vec3d,
    ):
        """Create a member. `StructuralModel.add_member` makes these.

        Args:
            start: The start node.
            end: The end node.
            section: The cross-section.
            material: The material.
            reference: A vector in the plane of the local x and z axes.
        """
        self.start = start
        self.end = end
        self.section = section
        self.material = material^
        self.reference = reference


struct Shell(Copyable, Movable):
    """A flat three-node shell."""

    var a: NodeId
    var b: NodeId
    var c: NodeId
    var thickness: Length64
    var material: BuildingMaterial

    def __init__(
        out self,
        a: NodeId,
        b: NodeId,
        c: NodeId,
        thickness: Length64,
        var material: BuildingMaterial,
    ):
        """Create a shell. `StructuralModel.add_shell` makes these.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner.
            thickness: The thickness.
            material: The material.
        """
        self.a = a
        self.b = b
        self.c = c
        self.thickness = thickness
        self.material = material^


@fieldwise_init
struct NodalLoad(ImplicitlyCopyable):
    """A force or a moment at a node, in global axes."""

    var load_case: LoadCaseId
    var node: NodeId
    var dof: Dof
    # Newtons for a translation, newton meters for a rotation.
    var value: Float64


@fieldwise_init
struct LineLoad(ImplicitlyCopyable):
    """A uniform load per length on a member, along a global axis."""

    var load_case: LoadCaseId
    var member: MemberId
    var dof: Dof
    # Newtons per meter.
    var value: Float64


@fieldwise_init
struct PressureLoad(ImplicitlyCopyable):
    """A uniform pressure on a shell."""

    var load_case: LoadCaseId
    var shell: ShellId
    # Pascals. A positive pressure pushes against the shell normal.
    var value: Float64


@fieldwise_init
struct GravityLoad(ImplicitlyCopyable):
    """The self-weight of every member and shell in a load case."""

    var load_case: LoadCaseId
    # Meters per second squared, along -z.
    var acceleration: Float64


struct StructuralModel(Copyable, Movable):
    """Nodes, supports, members, shells, loads and added masses."""

    var nodes: List[Vec3d]
    # Six entries per node: True where the degree of freedom is fixed.
    var fixed: List[Bool]
    # One entry per node, in kilograms, on each translation.
    var added_mass: List[Float64]
    var members: List[Member]
    var shells: List[Shell]
    var cases: List[String]
    var nodal_loads: List[NodalLoad]
    var line_loads: List[LineLoad]
    var pressures: List[PressureLoad]
    var gravity: List[GravityLoad]

    def __init__(out self):
        """Create an empty model."""
        self.nodes = List[Vec3d]()
        self.fixed = List[Bool]()
        self.added_mass = List[Float64]()
        self.members = List[Member]()
        self.shells = List[Shell]()
        self.cases = List[String]()
        self.nodal_loads = List[NodalLoad]()
        self.line_loads = List[LineLoad]()
        self.pressures = List[PressureLoad]()
        self.gravity = List[GravityLoad]()

    # --- checks -----------------------------------------------------------

    def check_node(self, id: NodeId) raises:
        """Refuse a node id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last node.
        """
        if not id.is_valid() or id.value >= len(self.nodes):
            raise Error("A node id is out of range")

    def check_member(self, id: MemberId) raises:
        """Refuse a member id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last member.
        """
        if not id.is_valid() or id.value >= len(self.members):
            raise Error("A member id is out of range")

    def check_shell(self, id: ShellId) raises:
        """Refuse a shell id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last shell.
        """
        if not id.is_valid() or id.value >= len(self.shells):
            raise Error("A shell id is out of range")

    def check_case(self, id: LoadCaseId) raises:
        """Refuse a load case id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last load case.
        """
        if not id.is_valid() or id.value >= len(self.cases):
            raise Error("A load case id is out of range")

    # --- parts ------------------------------------------------------------

    def dof_count(self) -> Int:
        """Return the number of degrees of freedom.

        Returns:
            Six per node.
        """
        return 6 * len(self.nodes)

    def add_node(mut self, at: Vec3d) raises -> NodeId:
        """Add a free node.

        Args:
            at: Its position, in meters.

        Returns:
            The new node.

        Raises:
            Error: If the position is not finite.
        """
        if not (isfinite(at.x) and isfinite(at.y) and isfinite(at.z)):
            raise Error("A node position must be finite")
        self.nodes.append(at)
        for _ in range(6):  # pragma: no branch
            self.fixed.append(False)
        self.added_mass.append(0)
        return NodeId(len(self.nodes) - 1)

    def add_support(mut self, node: NodeId, dofs: List[Dof]) raises:
        """Fix some degrees of freedom of a node at zero.

        Args:
            node: The node.
            dofs: The degrees of freedom to fix. Fixing one twice is
                allowed.

        Raises:
            Error: If the node id is out of range or a degree of freedom
                is not valid.
        """
        self.check_node(node)
        for i in range(len(dofs)):
            if not dofs[i].is_valid():
                raise Error("A degree of freedom must be from 0 to 5")
        for i in range(len(dofs)):
            self.fixed[6 * node.value + dofs[i].value] = True

    def fix(mut self, node: NodeId) raises:
        """Fix all six degrees of freedom of a node.

        Args:
            node: The node.

        Raises:
            Error: If the node id is out of range.
        """
        self.check_node(node)
        for d in range(6):  # pragma: no branch
            self.fixed[6 * node.value + d] = True

    def is_fixed(self, node: NodeId, dof: Dof) raises -> Bool:
        """Return True if a degree of freedom is fixed.

        Args:
            node: The node.
            dof: The degree of freedom.

        Returns:
            Whether a support fixes it.

        Raises:
            Error: If the node id is out of range or the degree of freedom
                is not valid.
        """
        self.check_node(node)
        if not dof.is_valid():
            raise Error("A degree of freedom must be from 0 to 5")
        return self.fixed[6 * node.value + dof.value]

    def add_member(
        mut self,
        start: NodeId,
        end: NodeId,
        section: Section,
        material: BuildingMaterial,
        reference: Vec3d,
    ) raises -> MemberId:
        """Add a frame member.

        Args:
            start: The start node.
            end: The end node.
            section: The cross-section. Its depth lies along the local z
                axis.
            material: The material.
            reference: A vector in the plane of the local x and z axes. If
                it is parallel to the member, `member_axes` uses a global
                axis instead.

        Returns:
            The new member.

        Raises:
            Error: If a node id is out of range, the nodes are at one
                point, the reference is zero or not finite, or the section
                or the material is not valid.
        """
        self.check_node(start)
        self.check_node(end)
        section.check()
        material.check()
        _ = member_axes(
            self.nodes[start.value], self.nodes[end.value], reference
        )
        self.members.append(
            Member(start, end, section, material.copy(), reference)
        )
        return MemberId(len(self.members) - 1)

    def add_shell(
        mut self,
        a: NodeId,
        b: NodeId,
        c: NodeId,
        thickness: Length64,
        material: BuildingMaterial,
    ) raises -> ShellId:
        """Add a flat three-node shell.

        Args:
            a: The first corner.
            b: The second corner.
            c: The third corner. The normal follows the right hand rule
                over a, b and c.
            thickness: The thickness.
            material: The material.

        Returns:
            The new shell.

        Raises:
            Error: If a node id is out of range, the corners lie on one
                line, the thickness is not positive and finite, or the
                material is not valid.
        """
        self.check_node(a)
        self.check_node(b)
        self.check_node(c)
        _ = ShellElement(
            self.nodes[a.value],
            self.nodes[b.value],
            self.nodes[c.value],
            thickness,
            material,
        )
        self.shells.append(Shell(a, b, c, thickness, material.copy()))
        return ShellId(len(self.shells) - 1)

    def shell_element(self, shell: ShellId) raises -> ShellElement:
        """Return the element of a shell.

        Args:
            shell: The shell.

        Returns:
            Its element, with its local axes and matrices.

        Raises:
            Error: If the id is out of range.
        """
        self.check_shell(shell)
        ref s = self.shells[shell.value]
        return ShellElement(
            self.nodes[s.a.value],
            self.nodes[s.b.value],
            self.nodes[s.c.value],
            s.thickness,
            s.material,
        )

    def add_mass(mut self, node: NodeId, mass: Mass64) raises:
        """Add a point mass at a node, for modal analysis.

        The mass acts on the three translations. It does not load a static
        case; add its weight as a force.

        Args:
            node: The node.
            mass: The mass. Zero or more.

        Raises:
            Error: If the node id is out of range or the mass is negative
                or not finite.
        """
        self.check_node(node)
        var m = mass.to(KILOGRAM)
        if not (m >= 0 and isfinite(m)):
            raise Error("An added mass must be zero or more and finite")
        self.added_mass[node.value] += m

    # --- loads ------------------------------------------------------------

    def add_load_case(mut self, var name: String) -> LoadCaseId:
        """Add an empty load case.

        Args:
            name: A name for people.

        Returns:
            The new load case.
        """
        self.cases.append(name^)
        return LoadCaseId(len(self.cases) - 1)

    def add_force(
        mut self, load_case: LoadCaseId, node: NodeId, dof: Dof, force: Force64
    ) raises:
        """Add a force at a node along a global axis.

        Args:
            load_case: The load case.
            node: The node.
            dof: `UX`, `UY` or `UZ`.
            force: The force.

        Raises:
            Error: If an id is out of range, the degree of freedom is not
                a translation, or the force is not finite.
        """
        self.check_case(load_case)
        self.check_node(node)
        if not dof.is_translation():
            raise Error("A force must act along a translation")
        var f = force.to(NEWTON)
        if not isfinite(f):
            raise Error("A load must be finite")
        self.nodal_loads.append(NodalLoad(load_case, node, dof, f))

    def add_moment(
        mut self,
        load_case: LoadCaseId,
        node: NodeId,
        dof: Dof,
        moment: Moment64,
    ) raises:
        """Add a moment at a node about a global axis.

        Args:
            load_case: The load case.
            node: The node.
            dof: `RX`, `RY` or `RZ`.
            moment: The moment, right-handed.

        Raises:
            Error: If an id is out of range, the degree of freedom is not
                a rotation, or the moment is not finite.
        """
        self.check_case(load_case)
        self.check_node(node)
        if not dof.is_rotation():
            raise Error("A moment must act about a rotation")
        var m = moment.to(NEWTON_METER)
        if not isfinite(m):
            raise Error("A load must be finite")
        self.nodal_loads.append(NodalLoad(load_case, node, dof, m))

    def add_line_load(
        mut self,
        load_case: LoadCaseId,
        member: MemberId,
        dof: Dof,
        load: LineLoad64,
    ) raises:
        """Add a uniform load per length along a global axis to a member.

        The solver turns it into consistent nodal loads and subtracts the
        fixed-end forces from the member end forces.

        Args:
            load_case: The load case.
            member: The member.
            dof: `UX`, `UY` or `UZ`.
            load: The load per length of the member.

        Raises:
            Error: If an id is out of range, the degree of freedom is not
                a translation, or the load is not finite.
        """
        self.check_case(load_case)
        self.check_member(member)
        if not dof.is_translation():
            raise Error("A line load must act along a translation")
        var w = load.to(NEWTON_PER_METER)
        if not isfinite(w):
            raise Error("A load must be finite")
        self.line_loads.append(LineLoad(load_case, member, dof, w))

    def add_pressure(
        mut self, load_case: LoadCaseId, shell: ShellId, pressure: Pressure64
    ) raises:
        """Add a uniform pressure to a shell.

        A positive pressure pushes against the shell normal. Each corner
        takes a third of the resultant.

        Args:
            load_case: The load case.
            shell: The shell.
            pressure: The pressure.

        Raises:
            Error: If an id is out of range or the pressure is not finite.
        """
        self.check_case(load_case)
        self.check_shell(shell)
        var p = pressure.to(PASCAL)
        if not isfinite(p):
            raise Error("A load must be finite")
        self.pressures.append(PressureLoad(load_case, shell, p))

    def add_self_weight(
        mut self, load_case: LoadCaseId, acceleration: Acceleration64
    ) raises:
        """Add the weight of every member and shell, along -z.

        A member's weight is a uniform line load ρ A g. A shell's weight
        is ρ t A g, a third at each corner.

        Args:
            load_case: The load case.
            acceleration: The acceleration of gravity. Zero or more.

        Raises:
            Error: If the id is out of range or the acceleration is
                negative or not finite.
        """
        self.check_case(load_case)
        var g = acceleration.to(METER_PER_SECOND_SQUARED)
        if not (g >= 0 and isfinite(g)):
            raise Error("A gravity must be zero or more and finite")
        self.gravity.append(GravityLoad(load_case, g))
