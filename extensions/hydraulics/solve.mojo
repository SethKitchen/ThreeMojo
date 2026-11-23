# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The steady flows and heads of a pipe network.

The unknowns are the head at each junction and the flow in each link.
Each link gives one equation, H_start - H_end = h(q), with h the head
loss of a pipe or minus the head of a pump. Each junction gives one
equation: the flows in, less the flows out, equal the demand.

`solve_network` uses the global gradient algorithm of Todini and Pilati,
"A gradient algorithm for the analysis of pipe networks", 1988, as EPANET
does. It is Newton's method on both sets of equations at once. With
p = 1 / h'(q) and y = p h(q) for each link, each iteration solves the
symmetric positive definite system

    Σ p (H_i - H_j) = Σ (y - q) out of i - Σ (y - q) into i - D_i

for the junction heads and then sets q to q - y + p (H_start - H_end).
The flows of each iterate balance at each junction. See Rossman,
"EPANET 2 Users Manual", EPA/600/R-00/057, 2000, appendix D.

EPANET is in the public domain. The code here is original.
"""

from std.math import pi
from core.ordinal import require_positive
from math.finite import require_positive_tolerance
from extensions.hydraulics.headloss import LOW_GRADIENT, pipe_head_loss
from extensions.hydraulics.kinds import LinkId, NodeId, PIPE, PUMP, RESERVOIR
from extensions.hydraulics.network import PipeNetwork
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import SparseBuilder
from extensions.numerics.vector import zeros
from units.si import Length64, Velocity64, VolumeFlowRate64

# The speed of the first guess of the flow in each pipe, in meters per
# second. EPANET starts from one foot per second.
comptime _FIRST_SPEED = 0.3048


struct SolveOptions(ImplicitlyCopyable):
    """When the iteration stops."""

    # The sum of the flow changes over the sum of the flows at which to
    # stop.
    var accuracy: Float64
    var iterations: Int

    def __init__(out self, accuracy: Float64, iterations: Int) raises:
        """Create the options.

        Args:
            accuracy: The sum of the absolute flow changes of one
                iteration, over the sum of the absolute flows, at which
                to stop. Positive. EPANET uses 0.001.
            iterations: The largest number of iterations. One or more.

        Raises:
            Error: If the accuracy is not positive and finite or the
                iteration count is not positive.
        """
        require_positive_tolerance(accuracy)
        require_positive(iterations, "An iteration budget must be one or more")
        self.accuracy = accuracy
        self.iterations = iterations


def default_options() raises -> SolveOptions:
    """Return an accuracy of 1e-10 and a budget of 200 iterations.

    Returns:
        The options.

    Raises:
        Error: Never.
    """
    return SolveOptions(1e-10, 200)


struct NetworkResult(Movable):
    """The heads and the flows of a solved network."""

    # The head of each node, in meters.
    var heads: List[Float64]
    # The flow of each link from its start to its end, in cubic meters
    # per second.
    var flows: List[Float64]
    # The elevation of each node and the diameter of each link, in
    # meters, from the network.
    var elevations: List[Float64]
    var diameters: List[Float64]
    var iterations: Int

    def __init__(
        out self,
        var heads: List[Float64],
        var flows: List[Float64],
        var elevations: List[Float64],
        var diameters: List[Float64],
        iterations: Int,
    ):
        """Hold a result. `solve_network` makes these.

        Args:
            heads: One per node.
            flows: One per link.
            elevations: One per node.
            diameters: One per link. Zero for a pump.
            iterations: How many iterations ran.
        """
        self.heads = heads^
        self.flows = flows^
        self.elevations = elevations^
        self.diameters = diameters^
        self.iterations = iterations

    def _node(self, node: NodeId) raises -> Int:
        """Return the index of a node, checked."""
        if not node.is_valid() or node.value >= len(self.heads):
            raise Error("A node id is out of range")
        return node.value

    def _link(self, link: LinkId) raises -> Int:
        """Return the index of a link, checked."""
        if not link.is_valid() or link.value >= len(self.flows):
            raise Error("A link id is out of range")
        return link.value

    def head(self, node: NodeId) raises -> Length64:
        """Return the head at a node.

        Args:
            node: The node.

        Returns:
            The elevation plus the pressure head.

        Raises:
            Error: If the node id is out of range.
        """
        return Length64(self.heads[self._node(node)])

    def pressure_head(self, node: NodeId) raises -> Length64:
        """Return the pressure head at a node.

        Args:
            node: The node.

        Returns:
            The head less the elevation. A negative value means that the
            network cannot supply the junction. Zero for a reservoir.

        Raises:
            Error: If the node id is out of range.
        """
        var n = self._node(node)
        return Length64(self.heads[n] - self.elevations[n])

    def flow(self, link: LinkId) raises -> VolumeFlowRate64:
        """Return the flow in a link.

        Args:
            link: The link.

        Returns:
            The flow from the start node to the end node. A negative
            flow runs the other way.

        Raises:
            Error: If the link id is out of range.
        """
        return VolumeFlowRate64(self.flows[self._link(link)])

    def velocity(self, link: LinkId) raises -> Velocity64:
        """Return the mean velocity in a pipe.

        Args:
            link: The pipe.

        Returns:
            The flow over the area, with the sign of the flow.

        Raises:
            Error: If the link id is out of range or the link is a pump.
        """
        var l = self._link(link)
        var d = self.diameters[l]
        if not (d > 0):
            raise Error("A pump has no velocity")
        return Velocity64(4 * self.flows[l] / (pi * d * d))


def link_head_loss(
    network: PipeNetwork, link: LinkId, flow: VolumeFlowRate64
) raises -> Length64:
    """Return the head that a link loses at a flow.

    Args:
        network: The network.
        link: The link.
        flow: The flow from the start node to the end node.

    Returns:
        The head at the start less the head at the end. A pipe gives the
        loss with the sign of the flow. A pump gives minus the head that
        it adds.

    Raises:
        Error: If the link id is out of range.
    """
    network.check_link(link)
    return Length64(_loss(network, link.value, flow.value).loss)


@fieldwise_init
struct _Signed(ImplicitlyCopyable):
    """The signed head loss of a link and its gradient."""

    var loss: Float64
    var gradient: Float64


def _loss(network: PipeNetwork, l: Int, q: Float64) -> _Signed:
    """Return the signed head loss of a link at a flow, and its gradient."""
    ref link = network.links[l]
    if link.kind == PUMP:
        # Minus the head that the pump adds: -(shutoff - r q |q|).
        var gradient = max(2 * link.curve * abs(q), LOW_GRADIENT)
        return _Signed(link.curve * q * abs(q) - link.shutoff, gradient)
    var value = pipe_head_loss(
        abs(q),
        link.length,
        link.diameter,
        link.roughness,
        link.minor,
        network.viscosity,
    )
    if q < 0:
        return _Signed(-value.loss, value.gradient)
    return _Signed(value.loss, value.gradient)


def solve_network(
    network: PipeNetwork, options: SolveOptions
) raises -> NetworkResult:
    """Return the heads and the flows of a network in steady flow.

    Args:
        network: The network. Each junction needs a path of links to a
            reservoir.
        options: The accuracy and the iteration budget.

    Returns:
        The head of each node and the flow of each link.

    Raises:
        Error: If the network has no reservoir, a junction has no path
            to a reservoir, a pump runs backward, or the iteration does
            not converge within the budget.
    """
    var nodes = len(network.kinds)
    var equation = List[Int](capacity=nodes)
    var count = 0
    for n in range(nodes):
        if network.kinds[n] == RESERVOIR:
            equation.append(-1)
        else:
            equation.append(count)
            count += 1
    if count == nodes:
        raise Error("A network needs a reservoir")
    var heads = network.heads.copy()
    var flows = zeros(len(network.links))
    var diameters = zeros(len(network.links))
    for l in range(len(network.links)):
        ref link = network.links[l]
        if link.kind == PIPE:
            diameters[l] = link.diameter
            flows[l] = _FIRST_SPEED * pi * link.diameter * link.diameter / 4
        else:
            # The design flow: the shutoff head is four times r q².
            flows[l] = (link.shutoff / (4 * link.curve)) ** 0.5
    for iteration in range(1, options.iterations + 1):  # pragma: no branch
        var builder = SparseBuilder(count)
        var rhs = zeros(count)
        var p = zeros(len(network.links))
        var y = zeros(len(network.links))
        for n in range(nodes):  # pragma: no branch
            if equation[n] >= 0:
                rhs[equation[n]] = -network.demands[n]
        for l in range(len(network.links)):
            ref link = network.links[l]
            var value = _loss(network, l, flows[l])
            p[l] = 1 / value.gradient
            y[l] = p[l] * value.loss
            var a = equation[link.start.value]
            var b = equation[link.end.value]
            if a >= 0:
                builder.add(a, a, p[l])
                rhs[a] += y[l] - flows[l]
            if b >= 0:
                builder.add(b, b, p[l])
                rhs[b] -= y[l] - flows[l]
            if a >= 0 and b >= 0:
                builder.add(a, b, -p[l])
                builder.add(b, a, -p[l])
            elif a >= 0:
                rhs[a] += p[l] * heads[link.end.value]
            elif b >= 0:
                rhs[b] += p[l] * heads[link.start.value]
        var solved: List[Float64]
        try:
            var matrix = builder.build()
            var factor = SkylineFactor(matrix, reverse_cuthill_mckee(matrix))
            solved = factor.solve(rhs)
        except:
            raise Error("A junction has no path of links to a reservoir")
        for n in range(nodes):  # pragma: no branch
            if equation[n] >= 0:
                heads[n] = solved[equation[n]]
        var change = Float64(0)
        var total = Float64(0)
        for l in range(len(network.links)):
            ref link = network.links[l]
            var drop = heads[link.start.value] - heads[link.end.value]
            var next = flows[l] - y[l] + p[l] * drop
            change += abs(next - flows[l])
            total += abs(next)
            flows[l] = next
        if change <= options.accuracy * total:
            for l in range(len(network.links)):
                if network.links[l].kind == PUMP and flows[l] < 0:
                    raise Error(
                        "A pump runs backward: its shutoff head is below"
                        " the head that it must add"
                    )
            return NetworkResult(
                heads^,
                flows^,
                network.elevations.copy(),
                diameters^,
                iteration,
            )
    raise Error("The network solution did not converge within its budget")
