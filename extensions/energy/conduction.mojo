# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One-dimensional transient conduction through a layered construction.

A `LayeredWall` cuts each layer of a `Construction` into equal elements
and puts a node at each element boundary, so a node lies on each face and
on each interface between layers. Each node holds half the heat capacity
of the elements on its two sides. Each element conducts k / dx between
its two nodes. Incropera, DeWitt, Bergman and Lavine, "Fundamentals of
Heat and Mass Transfer", 6th edition, 2007, section 5.10, derive this
energy balance.

A step is the implicit (backward Euler) form, which is stable for any
step:

    C_i (T_i' - T_i) / dt = K_(i-1) (T_(i-1)' - T_i') + K_i (T_(i+1)' - T_i')

A face node also gains h (T_env - T') + q from its film and from the
radiation it absorbs. The system is tridiagonal and `solve_tridiagonal`
solves it.

The number of elements in a layer follows a Fourier-number criterion.
Each element is cut so that its Fourier number alpha dt / dx² is at least
the given `fourier`. A larger `fourier` gives a finer mesh.

The wall is per square meter of area. The first node is on the outside
face, the side of the first layer.
"""

from std.math import ceil, isfinite, sqrt
from extensions.building.construction import Construction
from extensions.building.material import BuildingMaterial
from extensions.numerics.dense import solve_tridiagonal
from units.si import (
    Duration64,
    HeatFlux64,
    Length64,
    METER,
    SECOND,
    SQUARE_METER_KELVIN_PER_WATT,
    ThermalResistance64,
    ThermalTransmittance64,
    WATT_PER_SQUARE_METER,
    WATT_PER_SQUARE_METER_KELVIN,
)
from units.temperature import KELVIN, Temperature64

# The most elements one layer gets, however fine the criterion asks.
comptime MAX_ELEMENTS_PER_LAYER = 64


@fieldwise_init
struct FaceCondition(ImplicitlyCopyable):
    """What one face of a wall sees during a step."""

    # The film coefficient between the face and its environment.
    var film: ThermalTransmittance64
    # The temperature of the environment: the air, or the ground.
    var environment: Temperature64
    # The radiation the face absorbs, per area.
    var absorbed: HeatFlux64


struct LayeredWall(Copyable, Movable):
    """The nodes of a layered construction, per square meter."""

    var step: Float64
    # The heat capacity of each node, in J/(m² K).
    var capacity: List[Float64]
    # The conductance from node i to node i + 1, in W/(m² K).
    var conductance: List[Float64]
    # The depth of each node from the outside face, in meters.
    var depth: List[Float64]
    # The temperature of each node, in kelvin.
    var temperature: List[Float64]

    def __init__(
        out self,
        construction: Construction,
        materials: List[BuildingMaterial],
        step: Duration64,
        fourier: Float64,
        initial: Temperature64,
    ) raises:
        """Cut a construction into nodes, all at one temperature.

        Args:
            construction: The layers, outside first.
            materials: The materials its layers name.
            step: The time step the wall will advance by.
            fourier: The smallest Fourier number an element may have.
            initial: The temperature of every node.

        Raises:
            Error: If the construction is not valid, the step or the
                Fourier number is not positive and finite, or the
                temperature is not valid.
        """
        construction.check(materials)
        var dt = step.to(SECOND)
        if not (dt > 0 and isfinite(dt)):
            raise Error("A conduction step must be positive and finite")
        if not (fourier > 0 and isfinite(fourier)):
            raise Error("A Fourier number must be positive and finite")
        if not initial.is_valid():
            raise Error("A wall's initial temperature must be valid")
        self.step = dt
        self.capacity = [0.0]
        self.conductance = List[Float64]()
        self.depth = [0.0]
        var x = 0.0
        for i in range(len(construction.layers)):  # pragma: no branch
            ref layer = construction.layers[i]
            ref material = materials[layer.material.value]
            var k = material.conductivity.value
            var rho_c = material.density.value * material.specific_heat.value
            var thickness = layer.thickness.to(METER)
            var largest = sqrt(k / rho_c * dt / fourier)
            var count = min(
                max(1, Int(ceil(thickness / largest))), MAX_ELEMENTS_PER_LAYER
            )
            var dx = thickness / Float64(count)
            for _ in range(count):  # pragma: no branch
                var half = rho_c * dx / 2
                self.capacity[len(self.capacity) - 1] += half
                self.capacity.append(half)
                self.conductance.append(k / dx)
                x += dx
                self.depth.append(x)
        self.temperature = List[Float64](
            length=len(self.capacity), fill=initial.kelvin
        )

    def node_count(self) -> Int:
        """Return the number of nodes.

        Returns:
            One more than the number of elements.
        """
        return len(self.capacity)

    def _check_node(self, node: Int) raises:
        if node < 0 or node >= len(self.capacity):
            raise Error("A wall node is out of range")

    def node_depth(self, node: Int) raises -> Length64:
        """Return the depth of a node from the outside face.

        Args:
            node: The node, 0 on the outside face.

        Returns:
            Its depth.

        Raises:
            Error: If the node is out of range.
        """
        self._check_node(node)
        return Length64(self.depth[node], METER)

    def node_temperature(self, node: Int) raises -> Temperature64:
        """Return the temperature of a node.

        Args:
            node: The node, 0 on the outside face.

        Returns:
            Its temperature.

        Raises:
            Error: If the node is out of range.
        """
        self._check_node(node)
        return Temperature64(self.temperature[node], KELVIN)

    def outside_surface(self) -> Temperature64:
        """Return the temperature of the outside face.

        Returns:
            The temperature of the first node.
        """
        return Temperature64(self.temperature[0], KELVIN)

    def inside_surface(self) -> Temperature64:
        """Return the temperature of the inside face.

        Returns:
            The temperature of the last node.
        """
        return Temperature64(
            self.temperature[len(self.temperature) - 1], KELVIN
        )

    def resistance(self) -> ThermalResistance64:
        """Return the face-to-face resistance of the mesh.

        It equals the sum of the layer resistances for any mesh.

        Returns:
            The sum of the inverse element conductances.
        """
        var total = 0.0
        for i in range(len(self.conductance)):  # pragma: no branch
            total += 1 / self.conductance[i]
        return ThermalResistance64(total, SQUARE_METER_KELVIN_PER_WATT)

    def solve(
        self, outside: FaceCondition, inside: FaceCondition, history: Bool
    ) raises -> List[Float64]:
        """Return the node temperatures after one step, without keeping them.

        Because the step is linear, a caller can superpose solutions. One
        with `history` and the known conditions, plus one per unknown
        environment temperature with a unit temperature and no history,
        gives the response to that unknown.

        Args:
            outside: What the outside face sees.
            inside: What the inside face sees.
            history: Whether the present temperatures enter the step.

        Returns:
            The node temperatures in kelvin.

        Raises:
            Error: If a film is negative or not finite, or a temperature or
                an absorbed flux is not finite.
        """
        var h0 = outside.film.to(WATT_PER_SQUARE_METER_KELVIN)
        var h1 = inside.film.to(WATT_PER_SQUARE_METER_KELVIN)
        if not (h0 >= 0 and h1 >= 0 and isfinite(h0) and isfinite(h1)):
            raise Error("A film coefficient must be zero or more and finite")
        var forcing = [
            outside.environment.kelvin,
            inside.environment.kelvin,
            outside.absorbed.to(WATT_PER_SQUARE_METER),
            inside.absorbed.to(WATT_PER_SQUARE_METER),
        ]
        for i in range(len(forcing)):  # pragma: no branch
            if not isfinite(forcing[i]):
                raise Error("A face temperature and flux must be finite")
        var n = len(self.capacity)
        var lower = List[Float64](length=n, fill=0.0)
        var diagonal = List[Float64](length=n, fill=0.0)
        var upper = List[Float64](length=n, fill=0.0)
        var rhs = List[Float64](length=n, fill=0.0)
        for i in range(n):  # pragma: no branch
            var c = self.capacity[i] / self.step
            diagonal[i] = c
            if history:
                rhs[i] = c * self.temperature[i]
        for e in range(n - 1):  # pragma: no branch
            var k = self.conductance[e]
            diagonal[e] += k
            diagonal[e + 1] += k
            upper[e] = -k
            lower[e + 1] = -k
        diagonal[0] += h0
        rhs[0] += h0 * forcing[0] + forcing[2]
        diagonal[n - 1] += h1
        rhs[n - 1] += h1 * forcing[1] + forcing[3]
        return solve_tridiagonal(lower, diagonal, upper, rhs)

    def set_temperatures(mut self, var temperatures: List[Float64]) raises:
        """Replace the node temperatures.

        Args:
            temperatures: One temperature per node, in kelvin.

        Raises:
            Error: If the count differs from the node count.
        """
        if len(temperatures) != len(self.capacity):
            raise Error("A wall needs one temperature per node")
        self.temperature = temperatures^

    def advance(mut self, outside: FaceCondition, inside: FaceCondition) raises:
        """Advance the wall by one step.

        Args:
            outside: What the outside face sees.
            inside: What the inside face sees.

        Raises:
            Error: If `solve` refuses a condition.
        """
        self.set_temperatures(self.solve(outside, inside, True))
