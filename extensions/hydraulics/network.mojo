# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A network of junctions, reservoirs, pipes and pumps.

A junction has an elevation and a demand, which is the flow that leaves
the network there. A reservoir has a fixed head. A pipe joins two nodes
and loses head to friction. A pump joins two nodes and adds head from its
start to its end.

A pump has the one-point curve of EPANET. From a design flow q₀ and a
design head h₀, the head that it adds at a flow q is
(4/3) h₀ - (1/3) h₀ (q / q₀)². So the shutoff head is 4/3 of the design
head, and the head is zero at twice the design flow.
"""

from std.math import isfinite
from core.ordinal import require_valid
from math.finite import require_finite, require_positive_finite
from extensions.hydraulics.headloss import Roughness
from extensions.hydraulics.kinds import (
    HAZEN_WILLIAMS,
    JUNCTION,
    KinematicViscosity64,
    LinkId,
    LinkKind,
    NodeId,
    NodeKind,
    PIPE,
    PUMP,
    RESERVOIR,
    SQUARE_METER_PER_SECOND,
)
from units.si import (
    CUBIC_METER_PER_SECOND,
    Length64,
    METER,
    VolumeFlowRate64,
)

# The kinematic viscosity of water at 20 °C, in square meters per second.
comptime WATER_VISCOSITY = 1.004e-6


struct Link(ImplicitlyCopyable):
    """A pipe or a pump between two nodes."""

    var kind: LinkKind
    var start: NodeId
    var end: NodeId
    # A pipe's length and inside diameter, in meters.
    var length: Float64
    var diameter: Float64
    var roughness: Roughness
    # A pipe's minor loss coefficient K.
    var minor: Float64
    # A pump's shutoff head, in meters, and the coefficient r of its
    # curve h = shutoff - r q².
    var shutoff: Float64
    var curve: Float64

    def __init__(
        out self,
        kind: LinkKind,
        start: NodeId,
        end: NodeId,
        length: Float64,
        diameter: Float64,
        roughness: Roughness,
        minor: Float64,
        shutoff: Float64,
        curve: Float64,
    ):
        """Hold a link. `PipeNetwork.add_pipe` and `add_pump` make these.

        Args:
            kind: `PIPE` or `PUMP`.
            start: The start node.
            end: The end node.
            length: A pipe's length, in meters.
            diameter: A pipe's inside diameter, in meters.
            roughness: A pipe's roughness.
            minor: A pipe's minor loss coefficient.
            shutoff: A pump's shutoff head, in meters.
            curve: A pump's curve coefficient.
        """
        self.kind = kind
        self.start = start
        self.end = end
        self.length = length
        self.diameter = diameter
        self.roughness = roughness
        self.minor = minor
        self.shutoff = shutoff
        self.curve = curve


struct PipeNetwork(Copyable, Movable):
    """Junctions, reservoirs, pipes and pumps."""

    # One entry per node.
    var kinds: List[NodeKind]
    # The elevation of a junction, in meters. Zero for a reservoir.
    var elevations: List[Float64]
    # The demand of a junction, in cubic meters per second.
    var demands: List[Float64]
    # The head of a reservoir, in meters. Zero for a junction.
    var heads: List[Float64]
    var links: List[Link]
    # The kinematic viscosity of the fluid, in square meters per second.
    var viscosity: Float64

    def __init__(out self):
        """Create an empty network of water at 20 °C."""
        self.kinds = List[NodeKind]()
        self.elevations = List[Float64]()
        self.demands = List[Float64]()
        self.heads = List[Float64]()
        self.links = List[Link]()
        self.viscosity = WATER_VISCOSITY

    def check_node(self, id: NodeId) raises:
        """Refuse a node id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last node.
        """
        if not id.is_valid() or id.value >= len(self.kinds):
            raise Error("A node id is out of range")

    def check_link(self, id: LinkId) raises:
        """Refuse a link id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last link.
        """
        if not id.is_valid() or id.value >= len(self.links):
            raise Error("A link id is out of range")

    def set_viscosity(mut self, viscosity: KinematicViscosity64) raises:
        """Set the kinematic viscosity of the fluid.

        Only pipes with a Darcy-Weisbach roughness use it.

        Args:
            viscosity: The viscosity. Positive.

        Raises:
            Error: If the viscosity is not positive and finite.
        """
        var nu = viscosity.to(SQUARE_METER_PER_SECOND)
        require_positive_finite(nu, "A viscosity must be positive and finite")
        self.viscosity = nu

    def add_junction(
        mut self, elevation: Length64, demand: VolumeFlowRate64
    ) raises -> NodeId:
        """Add a junction.

        Args:
            elevation: The elevation of the junction.
            demand: The flow that leaves the network at the junction. A
                negative demand is an inflow.

        Returns:
            The new node.

        Raises:
            Error: If the elevation or the demand is not finite.
        """
        var z = elevation.to(METER)
        var q = demand.to(CUBIC_METER_PER_SECOND)
        require_finite(z, "An elevation must be finite")
        require_finite(q, "A demand must be finite")
        self.kinds.append(JUNCTION)
        self.elevations.append(z)
        self.demands.append(q)
        self.heads.append(0)
        return NodeId(len(self.kinds) - 1)

    def add_reservoir(mut self, head: Length64) raises -> NodeId:
        """Add a reservoir.

        Args:
            head: The head of the water surface.

        Returns:
            The new node.

        Raises:
            Error: If the head is not finite.
        """
        var h = head.to(METER)
        require_finite(h, "A reservoir head must be finite")
        self.kinds.append(RESERVOIR)
        self.elevations.append(0)
        self.demands.append(0)
        self.heads.append(h)
        return NodeId(len(self.kinds) - 1)

    def _check_ends(self, start: NodeId, end: NodeId) raises:
        """Refuse a link whose ends are not two nodes of the network."""
        self.check_node(start)
        self.check_node(end)
        if start == end:
            raise Error("A link must join two different nodes")

    def add_pipe(
        mut self,
        start: NodeId,
        end: NodeId,
        length: Length64,
        diameter: Length64,
        roughness: Roughness,
        minor_loss: Float64,
    ) raises -> LinkId:
        """Add a pipe.

        Args:
            start: The start node. A positive flow runs from it.
            end: The end node.
            length: The length. Positive.
            diameter: The inside diameter. Positive.
            roughness: The formula and its coefficient, from
                `hazen_williams`, `darcy_weisbach` or `chezy_manning`.
            minor_loss: The sum of the loss coefficients K of the
                fittings. Zero or more.

        Returns:
            The new link.

        Raises:
            Error: If a node id is out of range, the ends are one node,
                the length or the diameter is not positive and finite,
                the roughness is not valid or the minor loss is negative
                or not finite.
        """
        self._check_ends(start, end)
        var l = length.to(METER)
        var d = diameter.to(METER)
        require_positive_finite(l, "A pipe length must be positive and finite")
        require_positive_finite(
            d, "A pipe diameter must be positive and finite"
        )
        require_valid(
            roughness.is_valid(),
            "A roughness needs a valid formula and a positive coefficient",
        )
        if not (minor_loss >= 0 and isfinite(minor_loss)):
            raise Error("A minor loss must be zero or more and finite")
        self.links.append(
            Link(PIPE, start, end, l, d, roughness, minor_loss, 0, 0)
        )
        return LinkId(len(self.links) - 1)

    def add_pump(
        mut self,
        start: NodeId,
        end: NodeId,
        design_flow: VolumeFlowRate64,
        design_head: Length64,
    ) raises -> LinkId:
        """Add a pump with a one-point curve.

        Args:
            start: The suction node.
            end: The discharge node.
            design_flow: The flow at the design point. Positive.
            design_head: The head that the pump adds at the design flow.
                Positive.

        Returns:
            The new link.

        Raises:
            Error: If a node id is out of range, the ends are one node,
                or the design flow or head is not positive and finite.
        """
        self._check_ends(start, end)
        var q = design_flow.to(CUBIC_METER_PER_SECOND)
        var h = design_head.to(METER)
        require_positive_finite(
            q, "A pump design flow must be positive and finite"
        )
        require_positive_finite(
            h, "A pump design head must be positive and finite"
        )
        var none = Roughness(HAZEN_WILLIAMS, 1)
        self.links.append(
            Link(PUMP, start, end, 0, 0, none, 0, 4 * h / 3, h / (3 * q * q))
        )
        return LinkId(len(self.links) - 1)
