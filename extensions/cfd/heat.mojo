# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Flow that carries heat and rises where it is warm.

The fluid has one density in every term but the weight. There the density
falls with the temperature: a cell at a temperature T has an upward
acceleration of g β (T - T₀), with β the expansion coefficient and T₀ a
reference temperature. This is the approximation of Boussinesq. It holds
for a small temperature range.

The temperature follows ∂T/∂t + ∇·(u T) = α ∇²T, with α the thermal
diffusivity. `BuoyantSolver` advances both equations. Each time step has
these parts:

1. The buoyancy of each cell, from the temperature at the start.
2. One PISO step of the flow, by `FlowSolver`.
3. The temperature, implicit in time, with the new face fluxes. The
   fluxes balance in each cell, so the scheme keeps a uniform
   temperature uniform.

The model follows the OpenFOAM solver buoyantBoussinesqPimpleFoam. The
gravity acts along -y. The code is original and shares no source with
OpenFOAM.
"""

from std.math import isfinite
from core.ordinal import require_positive, require_valid
from math.finite import require_finite, require_positive_finite
from extensions.cfd.flow import FlowCase, FlowOptions, FlowSolver
from extensions.cfd.kinds import (
    FIXED_TEMPERATURE,
    INSULATED,
    Side,
    ThermalKind,
    UPWIND,
)
from extensions.cfd.quantities import (
    SQUARE_METER_PER_SECOND,
    ThermalDiffusivity64,
)
from units.si import (
    Acceleration64,
    Duration64,
    METER_PER_SECOND_SQUARED,
    PER_KELVIN,
    SECOND,
    ThermalExpansion64,
)
from units.temperature import (
    KELVIN,
    KELVIN_DIFFERENCE,
    Temperature64,
    TemperatureDifference64,
)

# The size of a Gauss-Seidel update, over the temperature range, at which
# the sweeps of the temperature stop.
comptime _SWEEP_TOLERANCE = 1e-9


struct ThermalBoundary(ImplicitlyCopyable):
    """What one side of the grid does to the heat."""

    var kind: ThermalKind
    # The fixed temperature, in kelvins. Not used by an insulated side.
    var value: Float64

    def __init__(out self, kind: ThermalKind, value: Float64):
        """Hold a boundary. `fixed_temperature` and `insulated` make these.

        Args:
            kind: The kind.
            value: The temperature, in kelvins.
        """
        self.kind = kind
        self.value = value

    def is_valid(self) -> Bool:
        """Return True if the kind is valid and the value is finite.

        Returns:
            Whether a case can use the boundary.
        """
        return self.kind.is_valid() and isfinite(self.value)


def fixed_temperature(temperature: Temperature64) -> ThermalBoundary:
    """Return a side with a fixed temperature.

    Args:
        temperature: The temperature of the side.

    Returns:
        The boundary.
    """
    return ThermalBoundary(FIXED_TEMPERATURE, temperature.to(KELVIN))


def insulated() -> ThermalBoundary:
    """Return a side that no heat crosses by conduction.

    Fluid that enters through the side has the temperature of the cell
    beside it.

    Returns:
        The boundary.
    """
    return ThermalBoundary(INSULATED, 0)


struct BuoyantCase(Copyable, Movable):
    """A flow case with the thermal properties of its fluid."""

    var flow: FlowCase
    # The thermal diffusivity, in square meters per second.
    var diffusivity: Float64
    # The expansion coefficient, per kelvin.
    var expansion: Float64
    # The acceleration of gravity along -y, in meters per second squared.
    var gravity: Float64
    # The temperature of no buoyancy, and of the fluid at the start, in
    # kelvins.
    var reference: Float64
    # One per side, in the order of `Side`.
    var thermal: List[ThermalBoundary]

    def __init__(
        out self,
        var flow: FlowCase,
        diffusivity: ThermalDiffusivity64,
        expansion: ThermalExpansion64,
        gravity: Acceleration64,
        reference: Temperature64,
    ) raises:
        """Create a case with every side insulated.

        Args:
            flow: The flow case. Its sides fix the velocity or the
                pressure.
            diffusivity: The thermal diffusivity. Positive.
            expansion: The volume expansion coefficient β. Finite. Zero
                gives a flow that the heat does not move.
            gravity: The acceleration of gravity, along -y. Finite.
            reference: The temperature at which the buoyancy is zero. The
                fluid starts at it.

        Raises:
            Error: If the diffusivity is not positive and finite, or the
                expansion, the gravity or the reference is not finite.
        """
        var alpha = diffusivity.to(SQUARE_METER_PER_SECOND)
        var beta = expansion.to(PER_KELVIN)
        var g = gravity.to(METER_PER_SECOND_SQUARED)
        var start = reference.to(KELVIN)
        require_positive_finite(
            alpha, "A thermal diffusivity must be positive and finite"
        )
        require_finite(beta, "An expansion coefficient must be finite")
        require_finite(g, "A gravity must be finite")
        require_finite(start, "A reference temperature must be finite")
        self.flow = flow^
        self.diffusivity = alpha
        self.expansion = beta
        self.gravity = g
        self.reference = start
        self.thermal = [insulated(), insulated(), insulated(), insulated()]

    def set_thermal_boundary(
        mut self, side: Side, boundary: ThermalBoundary
    ) raises:
        """Set what a side does to the heat.

        Args:
            side: The side.
            boundary: The boundary.

        Raises:
            Error: If the side or the boundary is not valid.
        """
        require_valid(side.is_valid(), "A side must be from 0 to 3")
        require_valid(
            boundary.is_valid(),
            "A thermal boundary needs a valid kind and a finite temperature",
        )
        self.thermal[side.value] = boundary


struct BuoyantSolver(Movable):
    """A buoyant case, its flow solver and its temperatures at one time."""

    var flow: FlowSolver
    var diffusivity: Float64
    var expansion: Float64
    var gravity: Float64
    var reference: Float64
    var thermal: List[ThermalBoundary]
    # The temperature of each cell, in kelvins, at index i + nx j.
    var temperatures: List[Float64]
    # The largest change of a temperature in the last step, in kelvins.
    var last_change: Float64

    def __init__(
        out self, var buoyant: BuoyantCase, options: FlowOptions
    ) raises:
        """Create a solver with the fluid at rest at the reference
        temperature.

        Args:
            buoyant: The case. The solver keeps it.
            options: The inner iterations of a step. The temperature uses
                the sweep budget of the momentum predictor.

        Raises:
            Error: If a boundary of the case is not valid. A case changed
                through its fields can hold one.
        """
        for s in range(4):
            require_valid(
                buoyant.thermal[s].is_valid(),
                (
                    "A thermal boundary needs a valid kind and a finite"
                    " temperature"
                ),
            )
        var cells = buoyant.flow.grid.count()
        self.diffusivity = buoyant.diffusivity
        self.expansion = buoyant.expansion
        self.gravity = buoyant.gravity
        self.reference = buoyant.reference
        self.thermal = buoyant.thermal.copy()
        self.temperatures = List[Float64](length=cells, fill=buoyant.reference)
        self.last_change = 0
        self.flow = FlowSolver(buoyant.flow.copy(), options)

    def temperature(self, i: Int, j: Int) raises -> Temperature64:
        """Return the temperature at the center of a cell.

        Args:
            i: The column, from the west.
            j: The row, from the south.

        Returns:
            The temperature.

        Raises:
            Error: If the cell is out of range.
        """
        return Temperature64(
            self.temperatures[self.flow.flow.grid.cell(i, j)], KELVIN
        )

    def change(self) -> TemperatureDifference64:
        """Return the largest change of a temperature in the last step.

        Returns:
            The change. Zero before the first step.
        """
        return TemperatureDifference64(self.last_change, KELVIN_DIFFERENCE)

    def wall_gradient(self, side: Side) raises -> Float64:
        """Return the mean temperature gradient at a side into the fluid.

        The Nusselt number of a wall is this gradient times a length over
        a temperature difference.

        Args:
            side: A side of fixed temperature.

        Returns:
            The mean over the side of the wall temperature less the cell
            temperature, over the half cell between them, in kelvins per
            meter. It is positive where the wall heats the fluid.

        Raises:
            Error: If the side is not valid or is insulated.
        """
        require_valid(side.is_valid(), "A side must be from 0 to 3")
        ref boundary = self.thermal[side.value]
        if boundary.kind != FIXED_TEMPERATURE:
            raise Error("A wall gradient needs a side of fixed temperature")
        var grid = self.flow.flow.grid
        var total = Float64(0)
        var count = grid.ny
        var half = 0.5 * grid.dx
        if side.value >= 2:
            count = grid.nx
            half = 0.5 * grid.dy
        for k in range(count):  # pragma: no branch
            var c = k * grid.nx
            if side.value == 1:
                c = grid.nx - 1 + k * grid.nx
            elif side.value == 2:
                c = k
            elif side.value == 3:
                c = k + grid.nx * (grid.ny - 1)
            total += (boundary.value - self.temperatures[c]) / half
        return total / Float64(count)

    def step(mut self, step: Duration64) raises:
        """Advance the flow and the temperature by one time step.

        Args:
            step: The time step. Positive.

        Raises:
            Error: If the step is not positive and finite, the flow step
                fails, or a temperature is not finite.
        """
        var dt = step.to(SECOND)
        require_positive_finite(dt, "A time step must be positive and finite")
        var grid = self.flow.flow.grid
        var n = grid.count()
        var lift = self.gravity * self.expansion
        for c in range(n):  # pragma: no branch
            self.flow.force_y[c] = lift * (
                self.temperatures[c] - self.reference
            )
        self.flow.step(step)
        var upwind = self.flow.flow.scheme == UPWIND
        var volume = grid.dx * grid.dy
        var a_center = List[Float64](length=n, fill=volume / dt)
        var a_side = List[Float64](length=4 * n, fill=0)
        var source = List[Float64](length=n, fill=0)
        for j in range(grid.ny):  # pragma: no branch
            for i in range(grid.nx):  # pragma: no branch
                var c = i + grid.nx * j
                source[c] = volume / dt * self.temperatures[c]
                for side in range(4):
                    var area = grid.dy
                    var distance = grid.dx
                    if side >= 2:
                        area = grid.dx
                        distance = grid.dy
                    var out = self.flow.outward_flux(i, j, side)
                    if grid.neighbor(i, j, side) >= 0:
                        var diffusion = self.diffusivity * area / distance
                        if upwind:
                            a_side[4 * c + side] = diffusion + max(-out, 0)
                            a_center[c] += diffusion + max(out, 0)
                        else:
                            a_side[4 * c + side] = diffusion - out / 2
                            a_center[c] += diffusion + out / 2
                        continue
                    ref boundary = self.thermal[side]
                    if boundary.kind == INSULATED:
                        a_center[c] += out
                        continue
                    var diffusion = 2 * self.diffusivity * area / distance
                    a_center[c] += diffusion
                    source[c] += (diffusion - out) * boundary.value
        var old = self.temperatures.copy()
        for _ in range(self.flow.options.sweeps):  # pragma: no branch
            var update = Float64(0)
            var size = Float64(0)
            for j in range(grid.ny):  # pragma: no branch
                for i in range(grid.nx):  # pragma: no branch
                    var c = i + grid.nx * j
                    var total = source[c]
                    for side in range(4):
                        var other = grid.neighbor(i, j, side)
                        if other >= 0:
                            total += (
                                a_side[4 * c + side] * self.temperatures[other]
                            )
                    var value = total / a_center[c]
                    update = max(update, abs(value - self.temperatures[c]))
                    size = max(size, abs(value - self.reference))
                    self.temperatures[c] = value
            if update <= _SWEEP_TOLERANCE * size:
                break
        var change = Float64(0)
        for c in range(n):  # pragma: no branch
            require_finite(self.temperatures[c], "A temperature is not finite")
            change = max(change, abs(self.temperatures[c] - old[c]))
        self.last_change = change

    def run_to_steady(
        mut self,
        step: Duration64,
        tolerance: TemperatureDifference64,
        budget: Int,
    ) raises -> Int:
        """Advance until the temperatures stop changing.

        Args:
            step: The time step. Positive.
            tolerance: The largest change of a temperature in one step at
                which the case is steady. Positive.
            budget: The largest number of steps. One or more.

        Returns:
            The number of steps taken.

        Raises:
            Error: If the tolerance or the budget is not positive, a step
                fails, or the case is not steady within the budget.
        """
        var limit = tolerance.to(KELVIN_DIFFERENCE)
        require_positive_finite(
            limit, "A steady tolerance must be positive and finite"
        )
        require_positive(budget, "A step budget must be one or more")
        for taken in range(1, budget + 1):  # pragma: no branch
            self.step(step)
            if self.last_change <= limit:
                return taken
        raise Error("The case is not steady within the step budget")
