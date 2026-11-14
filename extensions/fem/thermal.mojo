# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steady heat conduction in a tetrahedral mesh, with Pennes' bioheat term.

The temperature `T` in a solid at rest solves

    div(k grad T) + q + c (T_a - T) = 0

where `k` is the conductivity, `q` a heat source per volume, such as the
metabolism of tissue or the power of an ablation probe, and `c` the
perfusion coefficient of Pennes (1948): the blood perfusion rate times
the density and the specific heat of blood. Blood at the arterial
temperature `T_a` carries heat away where the tissue is warmer.

A node can have a fixed temperature. The outer faces on a plane can lose
heat to a fluid by convection: a flux `h (T - T_ambient)` out of the
face. Every integral is exact: the four-point rule for the conduction of
a ten-node element, and the closed forms of the shape functions for the
rest. The conjugate gradient method solves the system.

`solve_transient` follows the temperature in time from a start. Each
material stores heat: its density times its specific heat. A step of
the backward Euler method solves

    (C / dt + K) T_next = C / dt T + F

where `C` is the capacity matrix. The method is stable for every step,
and its error falls with the step. The consistent capacity is the more
accurate. Near a sudden change, a step that is short against
`h^2 / alpha` can then undershoot. The lumped capacity puts the heat of
each element on its nodes in proportion to the consistent diagonal, the
method of Hinton, Rock and Zienkiewicz. On four-node elements without
obtuse angles, a lumped step keeps each temperature between its bounds.
"""

from extensions.fem.elasticity import (
    gauss_points,
    quadratic_gradients,
    shape_gradients,
)
from extensions.fem.ids import (
    CONSISTENT_CAPACITY,
    CapacityKind,
    DofAxis,
    LINEAR,
    LUMPED_CAPACITY,
    NodeId,
    require_capacity,
    require_dof_axis,
    require_id,
)
from extensions.fem.mesh import TetMesh, boundary_faces, signed_volume
from extensions.fem.modal import mass_coefficients
from extensions.fem.static import edge_node_map
from extensions.numerics.iterative import (
    CONVERGED,
    SolveStatus,
    conjugate_gradient,
)
from extensions.numerics.sparse import CsrMatrix, SparseBuilder
from extensions.sdf.vector import V3, cross, dot, length
from std.math import isfinite, max, min, sqrt
from units.quantity import Quantity, Unit
from units.si import (
    Density64,
    Duration64,
    HeatFlux64,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    Power64,
    SECOND,
    WATT,
    WATT_PER_SQUARE_METER,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    WATT_PER_METER_KELVIN,
    WATT_PER_SQUARE_METER_KELVIN,
)
from units.temperature import CELSIUS, KELVIN, Temperature64

# A heat source per volume, in watts per cubic meter.
comptime PowerDensity64 = Quantity[-1, 1, -3, 0, 0, DType.float64]
comptime WATT_PER_CUBIC_METER = Unit[-1, 1, -3, 0, 0, DType.float64](
    1.0, "W/m^3"
)
# A perfusion coefficient, in watts per cubic meter per kelvin.
comptime PerfusionCoefficient64 = Quantity[-1, 1, -3, 0, -1, DType.float64]
comptime WATT_PER_CUBIC_METER_KELVIN = Unit[-1, 1, -3, 0, -1, DType.float64](
    1.0, "W/(m^3 K)"
)
# A film coefficient of convection, in watts per square meter per kelvin.
comptime FilmCoefficient64 = Quantity[0, 1, -3, 0, -1, DType.float64]


struct ThermalMaterial(ImplicitlyCopyable):
    """How a material conducts, makes and loses heat."""

    var conductivity: ThermalConductivity64
    """The thermal conductivity."""
    var source: PowerDensity64
    """The heat made per volume."""
    var perfusion: PerfusionCoefficient64
    """Pennes' coefficient: perfusion rate times blood density and heat."""

    def __init__(
        out self,
        conductivity: ThermalConductivity64,
        source: PowerDensity64 = PowerDensity64(0, WATT_PER_CUBIC_METER),
        perfusion: PerfusionCoefficient64 = PerfusionCoefficient64(
            0, WATT_PER_CUBIC_METER_KELVIN
        ),
    ) raises:
        """Create a material.

        Args:
            conductivity: The conductivity. Positive and finite.
            source: The heat made per volume. Finite. Zero by default.
            perfusion: Pennes' coefficient. Zero or more, finite. Zero by
                default.

        Raises:
            Error: If a value is out of its range.
        """
        var k = conductivity.to(WATT_PER_METER_KELVIN)
        if not (k > 0) or not isfinite(k):
            raise Error("A conductivity must be positive and finite")
        if not isfinite(source.to(WATT_PER_CUBIC_METER)):
            raise Error("A heat source must be finite")
        var c = perfusion.to(WATT_PER_CUBIC_METER_KELVIN)
        if not (c >= 0) or not isfinite(c):
            raise Error(
                "A perfusion coefficient must be zero or more, and finite"
            )
        self.conductivity = conductivity
        self.source = source
        self.perfusion = perfusion


struct ThermalProblem(Movable):
    """A mesh, its materials, its fixed temperatures and its convection."""

    var mesh: TetMesh
    """The mesh, in meters."""
    var materials: List[ThermalMaterial]
    """The material of each material id."""
    var arterial: Temperature64
    """The temperature of the blood that perfuses the tissue."""
    var fixed: List[Bool]
    """Whether each node's temperature is fixed."""
    var values: List[Float64]
    """The fixed temperature of each node, in kelvin."""
    var film: List[Float64]
    """The convection on the outer faces: four numbers per face, its three
    corners as node indexes and its film coefficient, then the ambient
    temperature in kelvin, five in all."""

    def __init__(
        out self,
        var mesh: TetMesh,
        var materials: List[ThermalMaterial],
        arterial: Temperature64 = Temperature64(37, CELSIUS),
    ) raises:
        """Create a problem with no fixed temperatures and no convection.

        Args:
            mesh: The mesh. It holds at least one element.
            materials: The materials. Each element's material id must
                name one.
            arterial: The arterial blood temperature, 37 C by default.

        Raises:
            Error: If the mesh has no elements, an element names a
                material that the list does not hold, or the arterial
                temperature is not above absolute zero.
        """
        if mesh.element_count() == 0:
            raise Error("A thermal problem needs a mesh with an element")
        for e in range(mesh.element_count()):  # pragma: no branch
            var id = mesh.materials[e]
            require_id(id >= 0, id, len(materials), "material")
        if not (arterial.to(KELVIN) > 0) or not isfinite(arterial.to(KELVIN)):
            raise Error("A temperature must be above absolute zero, and finite")
        var count = mesh.node_count()
        self.mesh = mesh^
        self.materials = materials^
        self.arterial = arterial
        self.fixed = List[Bool](length=count, fill=False)
        self.values = List[Float64](length=count, fill=0)
        self.film = List[Float64]()

    def fix(mut self, node: NodeId, temperature: Temperature64) raises:
        """Hold one node at a temperature.

        Args:
            node: The node.
            temperature: The temperature. Above absolute zero.

        Raises:
            Error: If the node is not valid, or the temperature is not
                above absolute zero and finite.
        """
        self.mesh.require_node(node)
        var kelvin = temperature.to(KELVIN)
        if not (kelvin > 0) or not isfinite(kelvin):
            raise Error("A temperature must be above absolute zero, and finite")
        self.fixed[node.value] = True
        self.values[node.value] = kelvin

    def convect_plane(
        mut self,
        axis: DofAxis,
        at: Length64,
        tolerance: Length64,
        coefficient: FilmCoefficient64,
        ambient: Temperature64,
    ) raises -> Int:
        """Let the outer faces on a plane lose heat to a fluid.

        A face loses `h (T - T_ambient)` per area. The plane holds the
        points whose coordinate on `axis` is `at`, within `tolerance`.

        Args:
            axis: The axis normal to the plane.
            at: The coordinate of the plane.
            tolerance: How far a node can be from the plane.
            coefficient: The film coefficient `h`. Zero or more, finite.
            ambient: The fluid temperature. Above absolute zero.

        Returns:
            How many faces the plane holds.

        Raises:
            Error: If the axis is not valid, or a value is out of range.
        """
        require_dof_axis(axis)
        var h = coefficient.to(WATT_PER_SQUARE_METER_KELVIN)
        if not (h >= 0) or not isfinite(h):
            raise Error("A film coefficient must be zero or more, and finite")
        var kelvin = ambient.to(KELVIN)
        if not (kelvin > 0) or not isfinite(kelvin):
            raise Error("A temperature must be above absolute zero, and finite")
        var on_plane = List[Bool](length=self.mesh.node_count(), fill=False)
        for node in self.mesh.nodes_on_plane(axis, at, tolerance):
            on_plane[node.value] = True
        var faces = boundary_faces(self.mesh)
        var count = 0
        # A problem's mesh has an element, so it has outer faces.
        for face in range(len(faces) // 4):  # pragma: no branch
            var a = faces[4 * face]
            var b = faces[4 * face + 1]
            var c = faces[4 * face + 2]
            var corners = Int(on_plane[a]) + Int(on_plane[b]) + Int(on_plane[c])
            if corners < 3:
                continue
            self.film.extend([Float64(a), Float64(b), Float64(c), h, kelvin])
            count += 1
        return count


struct ThermalResult(Movable):
    """The temperatures of a solved problem."""

    var temperatures: List[Float64]
    """One per node, in kelvin."""
    var iterations: Int
    """How many conjugate gradient iterations ran."""
    var relative_residual: Float64
    """The final residual norm over the norm of the right-hand side."""
    var status: SolveStatus
    """`CONVERGED`, or `BUDGET_EXHAUSTED` when the budget ran out."""

    def __init__(out self, var temperatures: List[Float64]):
        """Hold temperatures.

        Args:
            temperatures: One per node, in kelvin.
        """
        self.temperatures = temperatures^
        self.iterations = 0
        self.relative_residual = 0
        self.status = SolveStatus(0)

    def temperature(self, node: NodeId) raises -> Temperature64:
        """Return the temperature of one node.

        Args:
            node: The node.

        Returns:
            The temperature.

        Raises:
            Error: If the node id names no node.
        """
        require_id(node.is_valid(), node.value, len(self.temperatures), "node")
        return Temperature64(self.temperatures[node.value], KELVIN)


def _element_matrix(
    mesh: TetMesh, e: Int, material: ThermalMaterial, arterial: Float64
) raises -> Tuple[List[Float64], List[Float64]]:
    """Return the conduction plus perfusion matrix of one element, and its
    load vector of source and perfused blood."""
    var count = mesh.nodes_per_element()
    var at = count * e
    var corners = List[V3]()
    for k in range(4):  # pragma: no branch
        corners.append(mesh.nodes[mesh.corners[at + k]])
    var volume = signed_volume(corners[0], corners[1], corners[2], corners[3])
    var linear = shape_gradients(corners[0], corners[1], corners[2], corners[3])
    var k = material.conductivity.to(WATT_PER_METER_KELVIN)
    var matrix = List[Float64](length=count * count, fill=0)
    if count == 4:
        for a in range(4):  # pragma: no branch
            for b in range(4):  # pragma: no branch
                matrix[4 * a + b] = k * volume * dot(linear[a], linear[b])
    else:
        var points = gauss_points()
        for g in range(4):  # pragma: no branch
            var weights: List[Float64] = [
                points[4 * g],
                points[4 * g + 1],
                points[4 * g + 2],
                points[4 * g + 3],
            ]
            var grads = quadratic_gradients(linear, weights)
            for a in range(10):  # pragma: no branch
                for b in range(10):  # pragma: no branch
                    matrix[10 * a + b] += (
                        k * volume / 4.0 * dot(grads[a], grads[b])
                    )
    var c = material.perfusion.to(WATT_PER_CUBIC_METER_KELVIN)
    var mass = mass_coefficients(count)
    for index in range(count * count):  # pragma: no branch
        matrix[index] += c * volume * mass[index]
    # The integral of each shape function over the element, over V.
    var shares = List[Float64](length=count, fill=0.25)
    if count == 10:
        for a in range(10):  # pragma: no branch
            shares[a] = -0.05 if a < 4 else 0.2
    # The source, and the heat that the perfused blood brings.
    var q = material.source.to(WATT_PER_CUBIC_METER) + c * arterial
    var load = List[Float64]()
    for a in range(count):  # pragma: no branch
        load.append(shares[a] * volume * q)
    return (matrix^, load^)


def solve_thermal(
    problem: ThermalProblem, tolerance: Float64, max_iterations: Int
) raises -> ThermalResult:
    """Solve a steady thermal problem.

    Args:
        problem: The problem.
        tolerance: The relative residual at which the solve stops.
        max_iterations: The iteration budget.

    Returns:
        The temperature of each node. Check `status`: a solve that ran out
        of iterations returns its last iterate.

    Raises:
        Error: If the tolerance is not positive and finite, the budget is
            negative, or no temperature is fixed and nothing else sets the
            level of the temperatures.
    """
    ref mesh = problem.mesh
    var level = len(problem.film) > 0
    for node in range(mesh.node_count()):  # pragma: no branch
        level = level or problem.fixed[node]
    # A problem's elements name its materials, so it has one.
    for material in problem.materials:  # pragma: no branch
        var c = material.perfusion.to(WATT_PER_CUBIC_METER_KELVIN)
        level = level or c > 0
    if not level:
        raise Error(
            "A thermal problem needs a fixed temperature, convection or"
            " perfusion"
        )
    var n = mesh.node_count()
    var builder = SparseBuilder(n)
    var rhs = List[Float64](length=n, fill=0)
    _assemble(problem, builder, rhs)
    return _solve_held(builder.build(), rhs, problem, tolerance, max_iterations)


def _assemble(
    problem: ThermalProblem, mut builder: SparseBuilder, mut rhs: List[Float64]
) raises:
    """Add conduction, perfusion and convection to a matrix and a load."""
    ref mesh = problem.mesh
    var n = mesh.node_count()
    var count = mesh.nodes_per_element()
    var arterial = problem.arterial.to(KELVIN)
    for e in range(mesh.element_count()):  # pragma: no branch
        var material = problem.materials[mesh.materials[e]]
        var parts = _element_matrix(mesh, e, material, arterial)
        ref matrix = parts[0]
        ref load = parts[1]
        for a in range(count):  # pragma: no branch
            var row = mesh.corners[count * e + a]
            rhs[row] += load[a]
            for b in range(count):  # pragma: no branch
                var col = mesh.corners[count * e + b]
                builder.add(row, col, matrix[count * a + b])
    var middles = edge_node_map(mesh)
    var face_mass: List[Float64] = [
        6,
        -1,
        -1,
        0,
        -4,
        0,
        -1,
        6,
        -1,
        0,
        0,
        -4,
        -1,
        -1,
        6,
        -4,
        0,
        0,
        0,
        0,
        -4,
        32,
        16,
        16,
        -4,
        0,
        0,
        16,
        32,
        16,
        0,
        -4,
        0,
        16,
        16,
        32,
    ]
    for f in range(len(problem.film) // 5):
        var a = Int(problem.film[5 * f])
        var b = Int(problem.film[5 * f + 1])
        var c = Int(problem.film[5 * f + 2])
        var h = problem.film[5 * f + 3]
        var ambient = problem.film[5 * f + 4]
        ref nodes = mesh.nodes
        var area = length(cross(nodes[b] - nodes[a], nodes[c] - nodes[a])) / 2
        var face: List[Int] = [a, b, c]
        if mesh.order == LINEAR:
            for i in range(3):  # pragma: no branch
                rhs[face[i]] += h * ambient * area / 3.0
                for j in range(3):  # pragma: no branch
                    var weight = 2.0 if i == j else 1.0
                    builder.add(face[i], face[j], h * area * weight / 12.0)
        else:
            face.append(middles[min(a, b) * n + max(a, b)])
            face.append(middles[min(b, c) * n + max(b, c)])
            face.append(middles[min(a, c) * n + max(a, c)])
            for i in range(6):  # pragma: no branch
                if i >= 3:
                    rhs[face[i]] += h * ambient * area / 3.0
                for j in range(6):  # pragma: no branch
                    var weight = face_mass[6 * i + j]
                    builder.add(face[i], face[j], h * area * weight / 180.0)


def _solve_held(
    k: CsrMatrix,
    rhs: List[Float64],
    problem: ThermalProblem,
    tolerance: Float64,
    max_iterations: Int,
) raises -> ThermalResult:
    """Solve `k T = rhs` with the fixed nodes of a problem held."""
    var n = len(rhs)
    var free_index = List[Int](length=n, fill=-1)
    var free = 0
    for node in range(n):  # pragma: no branch
        if not problem.fixed[node]:
            free_index[node] = free
            free += 1
    var t = List[Float64](length=n, fill=0)
    for node in range(n):  # pragma: no branch
        if problem.fixed[node]:
            t[node] = problem.values[node]
    var result = ThermalResult(t.copy())
    if free > 0:
        var reduced = SparseBuilder(free)
        var right = List[Float64](length=free, fill=0)
        for row in range(n):  # pragma: no branch
            var r = free_index[row]
            if r < 0:
                continue
            right[r] += rhs[row]
            for at in range(
                k.row_start[row], k.row_start[row + 1]
            ):  # pragma: no branch
                var col = k.columns[at]
                var c = free_index[col]
                if c < 0:
                    right[r] -= k.values[at] * t[col]
                else:
                    reduced.add(r, c, k.values[at])
        var solved = conjugate_gradient(
            reduced.build(), right, tolerance, max_iterations
        )
        for node in range(n):  # pragma: no branch
            if free_index[node] >= 0:
                t[node] = solved.x[free_index[node]]
        result.iterations = solved.iterations
        result.relative_residual = solved.relative_residual
        result.status = solved.status
    result.temperatures = t^
    return result^


struct ThermalCapacity(ImplicitlyCopyable):
    """How much heat a material stores: its density and specific heat."""

    var density: Density64
    """The density."""
    var specific_heat: SpecificHeatCapacity64
    """The specific heat capacity."""

    def __init__(
        out self, density: Density64, specific_heat: SpecificHeatCapacity64
    ) raises:
        """Create a capacity.

        Args:
            density: The density. Positive and finite.
            specific_heat: The specific heat. Positive and finite.

        Raises:
            Error: If a value is not positive and finite.
        """
        var rho = density.to(KILOGRAM_PER_CUBIC_METER)
        var heat = specific_heat.to(JOULE_PER_KILOGRAM_KELVIN)
        if not (rho > 0) or not isfinite(rho):
            raise Error("A density must be positive and finite")
        if not (heat > 0) or not isfinite(heat):
            raise Error("A specific heat must be positive and finite")
        self.density = density
        self.specific_heat = specific_heat


struct TransientResult(Movable):
    """The temperatures of a problem at a series of times."""

    var times: List[Float64]
    """The time of each record after the start, in seconds."""
    var temperatures: List[List[Float64]]
    """One list per record: the temperature of each node, in kelvin."""
    var iterations: Int
    """How many conjugate gradient iterations ran over every step."""

    def __init__(out self):
        """Create a result without records."""
        self.times = List[Float64]()
        self.temperatures = List[List[Float64]]()
        self.iterations = 0


def solve_transient(
    problem: ThermalProblem,
    capacities: List[ThermalCapacity],
    initial: List[Temperature64],
    step: Duration64,
    steps: Int,
    every: Int,
    tolerance: Float64,
    max_iterations: Int,
    capacity: CapacityKind = CONSISTENT_CAPACITY,
) raises -> TransientResult:
    """Follow the temperatures of a problem in time, by backward Euler.

    The fixed nodes hold their temperatures from the first step on. The
    start is the first record, at time zero.

    Args:
        problem: The problem.
        capacities: The capacity of each material, by material id.
        initial: The temperature of each node at the start.
        step: The time step. Positive and finite.
        steps: How many steps, from 1 to 1000000.
        every: Record the temperatures every this many steps. One or more.
        tolerance: The relative residual at which each solve stops.
        max_iterations: The iteration budget of each solve.
        capacity: `CONSISTENT_CAPACITY`, the default, or
            `LUMPED_CAPACITY`.

    Returns:
        The records.

    Raises:
        Error: If the capacities do not fit the materials, the start does
            not fit the nodes or is not above absolute zero, an argument
            is out of range, the capacity kind is not valid, or a step
            does not converge.
    """
    ref mesh = problem.mesh
    var n = mesh.node_count()
    if len(capacities) != len(problem.materials):
        raise Error("A transient problem needs one capacity per material")
    if len(initial) != n:
        raise Error("A transient problem needs one start temperature per node")
    var dt = step.to(SECOND)
    if not (dt > 0) or not isfinite(dt):
        raise Error("A time step must be positive and finite")
    require_capacity(capacity)
    if steps < 1 or steps > 1000000:
        raise Error("A transient problem takes from 1 to 1000000 steps")
    if every < 1:
        raise Error("A record interval must be one step or more")
    var t = List[Float64]()
    for value in initial:  # pragma: no branch
        var kelvin = value.to(KELVIN)
        if not (kelvin > 0) or not isfinite(kelvin):
            raise Error("A temperature must be above absolute zero, and finite")
        t.append(kelvin)
    var builder = SparseBuilder(n)
    var rhs = List[Float64](length=n, fill=0)
    _assemble(problem, builder, rhs)
    var stores = _capacity_matrix(mesh, capacities, capacity)
    var inverse = 1.0 / dt
    for row in range(n):  # pragma: no branch
        for at in range(
            stores.row_start[row], stores.row_start[row + 1]
        ):  # pragma: no branch
            builder.add(row, stores.columns[at], stores.values[at] * inverse)
    var matrix = builder.build()
    var out = TransientResult()
    out.times.append(0)
    out.temperatures.append(t.copy())
    for index in range(1, steps + 1):  # pragma: no branch
        var stored = stores.multiply(t)
        for node in range(n):  # pragma: no branch
            stored[node] = stored[node] * inverse + rhs[node]
        var solved = _solve_held(
            matrix, stored, problem, tolerance, max_iterations
        )
        if solved.status != CONVERGED:
            raise Error("A time step did not converge within its budget")
        out.iterations += solved.iterations
        t = solved.temperatures.copy()
        if index % every == 0:
            out.times.append(Float64(index) * dt)
            out.temperatures.append(t.copy())
    return out^


def _capacity_matrix(
    mesh: TetMesh, capacities: List[ThermalCapacity], kind: CapacityKind
) raises -> CsrMatrix:
    """Return the capacity matrix of a kind, in joules per kelvin."""
    var count = mesh.nodes_per_element()
    var unit = mass_coefficients(count)
    var lumped = kind == LUMPED_CAPACITY
    var diagonal = 0.0
    for a in range(count):  # pragma: no branch
        diagonal += unit[count * a + a]
    var builder = SparseBuilder(mesh.node_count())
    for e in range(mesh.element_count()):  # pragma: no branch
        var at = count * e
        var volume = signed_volume(
            mesh.nodes[mesh.corners[at]],
            mesh.nodes[mesh.corners[at + 1]],
            mesh.nodes[mesh.corners[at + 2]],
            mesh.nodes[mesh.corners[at + 3]],
        )
        ref material = capacities[mesh.materials[e]]
        var stored = (
            material.density.to(KILOGRAM_PER_CUBIC_METER)
            * material.specific_heat.to(JOULE_PER_KILOGRAM_KELVIN)
            * volume
        )
        for a in range(count):  # pragma: no branch
            var node = mesh.corners[at + a]
            if lumped:
                builder.add(node, node, stored * unit[count * a + a] / diagonal)
                continue
            for b in range(count):  # pragma: no branch
                builder.add(
                    node, mesh.corners[at + b], stored * unit[count * a + b]
                )
    return builder.build()


struct HeatRates(Movable):
    """The heat that enters a body at each held node of a steady result."""

    var values: List[Float64]
    """The heat rate at each node, in watts. Positive heat enters the
    body. A free node has zero."""

    def __init__(out self, var values: List[Float64]):
        """Hold heat rates.

        Args:
            values: One per node, in watts.
        """
        self.values = values^

    def at(self, node: NodeId) raises -> Power64:
        """Return the heat rate at one node.

        Args:
            node: The node.

        Returns:
            The heat that enters the body there.

        Raises:
            Error: If the node id names no node.
        """
        require_id(node.is_valid(), node.value, len(self.values), "node")
        return Power64(self.values[node.value], WATT)

    def total(self) -> Power64:
        """Return the heat that enters the body at every held node.

        Returns:
            The sum. In a steady state it balances the sources, the
            perfusion and the convection.
        """
        var sum = 0.0
        for value in self.values:
            sum += value
        return Power64(sum, WATT)


def held_heat(
    problem: ThermalProblem, result: ThermalResult
) raises -> HeatRates:
    """Return the heat that enters the body at each held node.

    The rate at a held node is the row of `K T - F` there: the heat that
    the held temperature must supply to keep its value. A needle held at
    70 C supplies the heat that the tissue conducts and the blood takes
    away.

    Args:
        problem: The problem that was solved.
        result: Its steady temperatures.

    Returns:
        The rate at each node, in watts. A free node has zero.

    Raises:
        Error: If the result is not for this problem.
    """
    var n = problem.mesh.node_count()
    if len(result.temperatures) != n:
        raise Error("The result is not for this problem")
    var builder = SparseBuilder(n)
    var rhs = List[Float64](length=n, fill=0)
    _assemble(problem, builder, rhs)
    var k = builder.build()
    var applied = k.multiply(result.temperatures)
    var out = List[Float64](length=n, fill=0)
    for node in range(n):  # pragma: no branch
        if problem.fixed[node]:
            out[node] = applied[node] - rhs[node]
    return HeatRates(out^)


struct HeatFluxes(Movable):
    """The conducted heat flux of each element, at its centroid."""

    var values: List[Float64]
    """Three components per element, in watts per square meter."""

    def __init__(out self, var values: List[Float64]):
        """Hold heat fluxes.

        Args:
            values: Three per element, in watts per square meter.
        """
        self.values = values^

    def component(self, element: Int, axis: DofAxis) raises -> HeatFlux64:
        """Return one component of the flux of an element.

        Args:
            element: The element, from zero.
            axis: `DOF_X`, `DOF_Y` or `DOF_Z`.

        Returns:
            The component, positive along the axis.

        Raises:
            Error: If the element is outside the result, or the axis is
                not valid.
        """
        require_dof_axis(axis)
        var count = len(self.values) // 3
        if element < 0 or element >= count:
            raise Error("An element is outside the heat fluxes")
        return HeatFlux64(
            self.values[3 * element + axis.value], WATT_PER_SQUARE_METER
        )

    def magnitude(self, element: Int) raises -> HeatFlux64:
        """Return the size of the flux of an element.

        Args:
            element: The element, from zero.

        Returns:
            The length of the flux vector.

        Raises:
            Error: If the element is outside the result.
        """
        var count = len(self.values) // 3
        if element < 0 or element >= count:
            raise Error("An element is outside the heat fluxes")
        var x = self.values[3 * element]
        var y = self.values[3 * element + 1]
        var z = self.values[3 * element + 2]
        return HeatFlux64(sqrt(x * x + y * y + z * z), WATT_PER_SQUARE_METER)


def heat_flux(
    problem: ThermalProblem, result: ThermalResult
) raises -> HeatFluxes:
    """Return the conducted heat flux `-k grad T` of each element.

    A four-node element has one gradient. A ten-node element takes its
    gradient at the centroid. The flux runs from hot to cold.

    Args:
        problem: The problem that was solved.
        result: Its temperatures.

    Returns:
        Three components per element, in watts per square meter.

    Raises:
        Error: If the result is not for this problem.
    """
    ref mesh = problem.mesh
    if len(result.temperatures) != mesh.node_count():
        raise Error("The result is not for this problem")
    var count = mesh.nodes_per_element()
    var centroid: List[Float64] = [0.25, 0.25, 0.25, 0.25]
    var out = List[Float64]()
    for e in range(mesh.element_count()):  # pragma: no branch
        var at = count * e
        var linear = shape_gradients(
            mesh.nodes[mesh.corners[at]],
            mesh.nodes[mesh.corners[at + 1]],
            mesh.nodes[mesh.corners[at + 2]],
            mesh.nodes[mesh.corners[at + 3]],
        )
        var grads = linear.copy()
        if count == 10:
            grads = quadratic_gradients(linear, centroid)
        var k = problem.materials[mesh.materials[e]].conductivity.to(
            WATT_PER_METER_KELVIN
        )
        var gx = 0.0
        var gy = 0.0
        var gz = 0.0
        for a in range(count):  # pragma: no branch
            var t = result.temperatures[mesh.corners[at + a]]
            gx += t * grads[a].x
            gy += t * grads[a].y
            gz += t * grads[a].z
        out.append(-k * gx)
        out.append(-k * gy)
        out.append(-k * gz)
    return HeatFluxes(out^)
