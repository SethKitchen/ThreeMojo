# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Laminar incompressible flow on a block of cells, by the PISO algorithm.

The equations are those of the OpenFOAM solver icoFoam: the momentum
equation ∂u/∂t + ∇·(u u) = -∇p + ν ∇²u and the continuity equation
∇·u = 0, with p the pressure over the density. The cells hold the
velocity and the pressure at their centers. The faces hold the volume
flux.

Each time step has these parts, from Issa, "Solution of the implicitly
discretised fluid flow equations by operator-splitting", 1986:

1. The momentum predictor. Implicit Euler in time, with the old face
   fluxes and the old pressure gradient, by Gauss-Seidel sweeps.
2. Two or more pressure correctors. Each one writes the velocity as
   H / A - (1 / A) ∇p, takes the face fluxes from H / A, solves the
   pressure equation ∇·((1 / A) ∇p) = ∇·(H / A) by conjugate gradients,
   and corrects the fluxes and the velocity.

The face flux comes from H / A and the pressure gradient between the two
cells of the face, not from an interpolated velocity. This is the method
of Rhie and Chow, 1983, and it keeps the pressure free of the
checkerboard mode. The discretization is that of Jasak, "Error analysis
and estimation for the finite volume method with applications to fluid
flows", 1996, section 3.8.

The grid is a single block of equal rectangles, one cell thick. The code
is original and shares no source with OpenFOAM.
"""

from std.math import isfinite
from core.ordinal import require_positive, require_valid
from math.finite import (
    require_finite,
    require_positive_finite,
    require_positive_tolerance,
)
from extensions.cfd.kinds import (
    BoundaryKind,
    CENTRAL,
    ConvectionScheme,
    FIXED_PRESSURE,
    FIXED_VELOCITY,
    Side,
    UPWIND,
)
from extensions.cfd.quantities import (
    DynamicViscosity64,
    KinematicViscosity64,
    PASCAL_SECOND,
)
from extensions.numerics.iterative import CONVERGED, conjugate_gradient
from extensions.numerics.sparse import CsrMatrix
from extensions.numerics.vector import norm, zeros
from units.si import (
    Density64,
    Duration64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND,
    PASCAL,
    Pressure64,
    SECOND,
    Velocity64,
)

# The largest number of cells of one grid.
comptime MAX_CELLS = 1048576


struct Grid(ImplicitlyCopyable):
    """A block of equal rectangular cells in the x-y plane.

    Cell (i, j) is column i from the west and row j from the south. Its
    index in a field is i + nx j. The block is one meter thick.
    """

    var nx: Int
    var ny: Int
    # The cell size along x and along y, in meters.
    var dx: Float64
    var dy: Float64

    def __init__(
        out self, nx: Int, ny: Int, width: Length64, height: Length64
    ) raises:
        """Create a grid.

        Args:
            nx: The number of cells along x. One or more.
            ny: The number of cells along y. One or more.
            width: The size of the block along x. Positive.
            height: The size of the block along y. Positive.

        Raises:
            Error: If a count is not positive, the grid has more than
                1048576 cells, or a size is not positive and finite.
        """
        require_positive(nx, "A grid needs one cell or more along x")
        require_positive(ny, "A grid needs one cell or more along y")
        if nx > MAX_CELLS or ny > MAX_CELLS // nx:
            raise Error("A grid is larger than this port stores")
        var w = width.to(METER)
        var h = height.to(METER)
        require_positive_finite(w, "A grid width must be positive and finite")
        require_positive_finite(h, "A grid height must be positive and finite")
        self.nx = nx
        self.ny = ny
        self.dx = w / Float64(nx)
        self.dy = h / Float64(ny)

    def count(self) -> Int:
        """Return the number of cells.

        Returns:
            The product of nx and ny.
        """
        return self.nx * self.ny

    def cell(self, i: Int, j: Int) raises -> Int:
        """Return the index of a cell in a field.

        Args:
            i: The column, from the west.
            j: The row, from the south.

        Returns:
            The index i + nx j.

        Raises:
            Error: If the column or the row is out of range.
        """
        if i < 0 or i >= self.nx or j < 0 or j >= self.ny:
            raise Error("A cell is out of range")
        return i + self.nx * j

    def center_x(self, i: Int) -> Length64:
        """Return the x coordinate of the centers of a column.

        Args:
            i: The column, from the west.

        Returns:
            The coordinate, from the west side.
        """
        return Length64((Float64(i) + 0.5) * self.dx)

    def center_y(self, j: Int) -> Length64:
        """Return the y coordinate of the centers of a row.

        Args:
            j: The row, from the south.

        Returns:
            The coordinate, from the south side.
        """
        return Length64((Float64(j) + 0.5) * self.dy)

    def neighbor(self, i: Int, j: Int, side: Int) -> Int:
        """Return the cell across a side of a cell.

        Args:
            i: The column of the cell.
            j: The row of the cell.
            side: The value of a `Side`.

        Returns:
            The index of the neighbor, or -1 at the edge of the grid.
        """
        if side == 0:
            if i == 0:
                return -1
            return i - 1 + self.nx * j
        if side == 1:
            if i == self.nx - 1:
                return -1
            return i + 1 + self.nx * j
        if side == 2:
            if j == 0:
                return -1
            return i + self.nx * (j - 1)
        if j == self.ny - 1:
            return -1
        return i + self.nx * (j + 1)


struct Boundary(ImplicitlyCopyable):
    """What one side of the grid fixes."""

    var kind: BoundaryKind
    # The fixed velocity, in meters per second.
    var u: Float64
    var v: Float64
    # The fixed pressure, in pascals.
    var p: Float64

    def __init__(
        out self, kind: BoundaryKind, u: Float64, v: Float64, p: Float64
    ):
        """Hold a boundary. `fixed_velocity`, `wall` and `fixed_pressure`
        make these.

        Args:
            kind: The kind.
            u: The velocity along x, in meters per second.
            v: The velocity along y, in meters per second.
            p: The pressure, in pascals.
        """
        self.kind = kind
        self.u = u
        self.v = v
        self.p = p

    def is_valid(self) -> Bool:
        """Return True if the kind is valid and every value is finite.

        Returns:
            Whether a case can use the boundary.
        """
        if not self.kind.is_valid():
            return False
        return isfinite(self.u) and isfinite(self.v) and isfinite(self.p)


def fixed_velocity(u: Velocity64, v: Velocity64) -> Boundary:
    """Return a side with a fixed velocity.

    An inlet has a velocity through the side. A moving wall has a
    velocity along it.

    Args:
        u: The velocity along x.
        v: The velocity along y.

    Returns:
        The boundary. `FlowCase.set_boundary` refuses a value that is not
        finite.
    """
    return Boundary(
        FIXED_VELOCITY, u.to(METER_PER_SECOND), v.to(METER_PER_SECOND), 0
    )


def wall() -> Boundary:
    """Return a wall at rest.

    Returns:
        A fixed velocity of zero.
    """
    return Boundary(FIXED_VELOCITY, 0, 0, 0)


def fixed_pressure(pressure: Pressure64) -> Boundary:
    """Return a side with a fixed pressure.

    The velocity has no gradient along the normal, so the fluid can leave
    or enter.

    Args:
        pressure: The pressure.

    Returns:
        The boundary. `FlowCase.set_boundary` refuses a value that is not
        finite.
    """
    return Boundary(FIXED_PRESSURE, 0, 0, pressure.to(PASCAL))


struct FlowCase(Copyable, Movable):
    """A grid, a fluid, the boundary of each side and the scheme."""

    var grid: Grid
    # Kilograms per cubic meter.
    var density: Float64
    # The kinematic viscosity, in square meters per second.
    var viscosity: Float64
    # One per side, in the order of `Side`.
    var boundaries: List[Boundary]
    var scheme: ConvectionScheme

    def __init__(
        out self, grid: Grid, density: Density64, viscosity: DynamicViscosity64
    ) raises:
        """Create a case with a wall on each side and the central scheme.

        Args:
            grid: The grid.
            density: The density of the fluid. Positive.
            viscosity: The dynamic viscosity of the fluid. Positive.

        Raises:
            Error: If the density or the viscosity is not positive and
                finite.
        """
        var rho = density.to(KILOGRAM_PER_CUBIC_METER)
        var mu = viscosity.to(PASCAL_SECOND)
        require_positive_finite(rho, "A density must be positive and finite")
        require_positive_finite(mu, "A viscosity must be positive and finite")
        self.grid = grid
        self.density = rho
        self.viscosity = mu / rho
        self.boundaries = [wall(), wall(), wall(), wall()]
        self.scheme = CENTRAL

    def set_boundary(mut self, side: Side, boundary: Boundary) raises:
        """Set what a side fixes.

        Args:
            side: The side.
            boundary: The boundary.

        Raises:
            Error: If the side or the boundary is not valid.
        """
        require_valid(side.is_valid(), "A side must be from 0 to 3")
        require_valid(
            boundary.is_valid(),
            "A boundary needs a valid kind and finite values",
        )
        self.boundaries[side.value] = boundary

    def set_scheme(mut self, scheme: ConvectionScheme) raises:
        """Set the convection scheme.

        Args:
            scheme: `UPWIND` or `CENTRAL`.

        Raises:
            Error: If the scheme is not valid.
        """
        require_valid(scheme.is_valid(), "A convection scheme must be 0 or 1")
        self.scheme = scheme

    def kinematic_viscosity(self) -> KinematicViscosity64:
        """Return the dynamic viscosity over the density.

        Returns:
            The kinematic viscosity.
        """
        return KinematicViscosity64(self.viscosity)


struct FlowOptions(ImplicitlyCopyable):
    """The inner iterations of one time step."""

    var correctors: Int
    var sweeps: Int
    var pressure_tolerance: Float64
    var pressure_iterations: Int

    def __init__(
        out self,
        correctors: Int,
        sweeps: Int,
        pressure_tolerance: Float64,
        pressure_iterations: Int,
    ) raises:
        """Create the options.

        Args:
            correctors: The pressure correctors per step. One or more.
                PISO needs two.
            sweeps: The most Gauss-Seidel sweeps of the momentum
                predictor. One or more.
            pressure_tolerance: The relative residual at which the
                pressure solution stops. Positive.
            pressure_iterations: The budget of the pressure solution.
                One or more.

        Raises:
            Error: If a count is not positive or the tolerance is not
                positive and finite.
        """
        require_positive(correctors, "A step needs one corrector or more")
        require_positive(sweeps, "A step needs one sweep or more")
        require_positive_tolerance(pressure_tolerance)
        require_positive(
            pressure_iterations, "An iteration budget must be one or more"
        )
        self.correctors = correctors
        self.sweeps = sweeps
        self.pressure_tolerance = pressure_tolerance
        self.pressure_iterations = pressure_iterations


def default_options() raises -> FlowOptions:
    """Return two correctors, 50 sweeps and a pressure tolerance of 1e-8.

    Returns:
        The options, with a pressure budget of 10000 iterations.

    Raises:
        Error: Never.
    """
    return FlowOptions(2, 50, 1e-8, 10000)


# The relative size of a Gauss-Seidel update at which the sweeps stop.
comptime _SWEEP_TOLERANCE = 1e-7


def _normal_x(side: Int) -> Float64:
    """Return the x part of the outward normal of a side."""
    if side == 0:
        return -1
    if side == 1:
        return 1
    return 0


def _normal_y(side: Int) -> Float64:
    """Return the y part of the outward normal of a side."""
    if side == 2:
        return -1
    if side == 3:
        return 1
    return 0


def pressure_pattern(grid: Grid) raises -> CsrMatrix:
    """Return the pressure matrix of a grid with every value at zero.

    Row c holds the cell and its neighbors to the south, the west, the
    east and the north, in the order of their indices.

    Args:
        grid: The grid.

    Returns:
        The matrix. `FlowSolver` fills its values at each corrector.

    Raises:
        Error: Never, for a grid made by its constructor.
    """
    var n = grid.count()
    var row_start = List[Int](capacity=n + 1)
    var columns = List[Int](capacity=5 * n)
    row_start.append(0)
    # The sides in the order of their neighbor indices, with the cell
    # itself as -1.
    var order = [2, 0, -1, 1, 3]
    for j in range(grid.ny):  # pragma: no branch
        for i in range(grid.nx):  # pragma: no branch
            for k in range(5):
                var column = i + grid.nx * j
                if order[k] >= 0:
                    column = grid.neighbor(i, j, order[k])
                if column >= 0:
                    columns.append(column)
            row_start.append(len(columns))
    var values = zeros(len(columns))
    return CsrMatrix(n, row_start^, columns^, values^)


def _slot(matrix: CsrMatrix, row: Int, column: Int) -> Int:
    """Return where a stored entry of the pressure matrix is."""
    var at = matrix.row_start[row]
    while matrix.columns[at] != column:
        at += 1
    return at


struct FlowSolver(Movable):
    """A flow case and its fields at one time.

    The fields have one entry per cell, at index i + nx j. The velocity is
    in meters per second. The stored pressure is the pressure over the
    density, in square meters per second squared.
    """

    var flow: FlowCase
    var options: FlowOptions
    var u: List[Float64]
    var v: List[Float64]
    var p: List[Float64]
    # The flux through each face normal to x, positive along x, in square
    # meters per second. Face i + (nx + 1) j is the west face of cell
    # (i, j).
    var flux_x: List[Float64]
    # The flux through each face normal to y, positive along y. Face
    # i + nx j is the south face of cell (i, j).
    var flux_y: List[Float64]
    # The time, in seconds.
    var time: Float64
    # The largest change of a velocity in the last step, in meters per
    # second.
    var last_change: Float64
    # The pressure matrix. Its pattern is fixed and each corrector fills
    # its values.
    var matrix: CsrMatrix

    def __init__(out self, var flow: FlowCase, options: FlowOptions) raises:
        """Create a solver with the fluid at rest.

        The faces of a side with a fixed velocity start with its flux.

        Args:
            flow: The case. The solver keeps it.
            options: The inner iterations of a step.

        Raises:
            Error: If a boundary of the case is not valid. A case changed
                through its fields can hold one.
        """
        for s in range(4):
            require_valid(
                flow.boundaries[s].is_valid(),
                "A boundary needs a valid kind and finite values",
            )
        var grid = flow.grid
        var n = grid.count()
        self.u = zeros(n)
        self.v = zeros(n)
        self.p = zeros(n)
        self.flux_x = zeros((grid.nx + 1) * grid.ny)
        self.flux_y = zeros(grid.nx * (grid.ny + 1))
        self.time = 0
        self.last_change = 0
        self.matrix = pressure_pattern(grid)
        for j in range(grid.ny):  # pragma: no branch
            self.flux_x[(grid.nx + 1) * j] = flow.boundaries[0].u * grid.dy
            self.flux_x[grid.nx + (grid.nx + 1) * j] = (
                flow.boundaries[1].u * grid.dy
            )
        for i in range(grid.nx):  # pragma: no branch
            self.flux_y[i] = flow.boundaries[2].v * grid.dx
            self.flux_y[i + grid.nx * grid.ny] = flow.boundaries[3].v * grid.dx
        self.flow = flow^
        self.options = options

    # --- results ----------------------------------------------------------

    def velocity_x(self, i: Int, j: Int) raises -> Velocity64:
        """Return the velocity along x at the center of a cell.

        Args:
            i: The column, from the west.
            j: The row, from the south.

        Returns:
            The velocity.

        Raises:
            Error: If the cell is out of range.
        """
        return Velocity64(self.u[self.flow.grid.cell(i, j)])

    def velocity_y(self, i: Int, j: Int) raises -> Velocity64:
        """Return the velocity along y at the center of a cell.

        Args:
            i: The column, from the west.
            j: The row, from the south.

        Returns:
            The velocity.

        Raises:
            Error: If the cell is out of range.
        """
        return Velocity64(self.v[self.flow.grid.cell(i, j)])

    def pressure(self, i: Int, j: Int) raises -> Pressure64:
        """Return the pressure at the center of a cell.

        With no side of fixed pressure, the pressure is relative to the
        cell at the south-west corner.

        Args:
            i: The column, from the west.
            j: The row, from the south.

        Returns:
            The pressure.

        Raises:
            Error: If the cell is out of range.
        """
        return Pressure64(self.p[self.flow.grid.cell(i, j)] * self.flow.density)

    def elapsed(self) -> Duration64:
        """Return the time that the solver has advanced.

        Returns:
            The sum of the steps.
        """
        return Duration64(self.time)

    def change(self) -> Velocity64:
        """Return the largest change of a velocity in the last step.

        Returns:
            The change. Zero before the first step.
        """
        return Velocity64(self.last_change)

    def _outward(self, i: Int, j: Int, side: Int) -> Float64:
        """Return the flux that leaves a cell through a side."""
        var grid = self.flow.grid
        if side == 0:
            return -self.flux_x[i + (grid.nx + 1) * j]
        if side == 1:
            return self.flux_x[i + 1 + (grid.nx + 1) * j]
        if side == 2:
            return -self.flux_y[i + grid.nx * j]
        return self.flux_y[i + grid.nx * (j + 1)]

    def imbalance(self) -> KinematicViscosity64:
        """Return the largest net flux that leaves a cell.

        The continuity equation makes it zero. After a step it is as
        small as the pressure tolerance allows.

        Returns:
            The largest absolute sum of the four face fluxes of a cell,
            for a block one meter thick.
        """
        var grid = self.flow.grid
        var worst = Float64(0)
        for j in range(grid.ny):  # pragma: no branch
            for i in range(grid.nx):  # pragma: no branch
                var net = Float64(0)
                for side in range(4):
                    net += self._outward(i, j, side)
                worst = max(worst, abs(net))
        return KinematicViscosity64(worst)

    def _face_pressure(self, i: Int, j: Int, side: Int) -> Float64:
        """Return the pressure over the density on a side of a cell."""
        var grid = self.flow.grid
        var c = i + grid.nx * j
        var other = grid.neighbor(i, j, side)
        if other >= 0:
            return 0.5 * (self.p[c] + self.p[other])
        ref boundary = self.flow.boundaries[side]
        if boundary.kind == FIXED_PRESSURE:
            return boundary.p / self.flow.density
        return self.p[c]

    def _gradient(self, mut gx: List[Float64], mut gy: List[Float64]):
        """Fill the pressure gradient of each cell from its face values."""
        var grid = self.flow.grid
        for j in range(grid.ny):  # pragma: no branch
            for i in range(grid.nx):  # pragma: no branch
                var c = i + grid.nx * j
                gx[c] = (
                    self._face_pressure(i, j, 1) - self._face_pressure(i, j, 0)
                ) / grid.dx
                gy[c] = (
                    self._face_pressure(i, j, 3) - self._face_pressure(i, j, 2)
                ) / grid.dy

    # --- the step ---------------------------------------------------------

    def step(mut self, step: Duration64) raises:
        """Advance the flow by one time step.

        The step is implicit, but PISO loses accuracy when the fluid
        crosses more than about one cell per step.

        Args:
            step: The time step. Positive.

        Raises:
            Error: If the step is not positive and finite, the pressure
                solution does not converge within its budget, or the
                flow is not finite.
        """
        var dt = step.to(SECOND)
        require_positive_finite(dt, "A time step must be positive and finite")
        var grid = self.flow.grid
        var nx = grid.nx
        var ny = grid.ny
        var n = grid.count()
        var nu = self.flow.viscosity
        var volume = grid.dx * grid.dy
        var upwind = self.flow.scheme == UPWIND
        var old_u = self.u.copy()
        var old_v = self.v.copy()
        # The momentum coefficients: A u = Σ a u_neighbor + b - V ∇p.
        var a_center = zeros(n)
        var a_side = zeros(4 * n)
        var bu = zeros(n)
        var bv = zeros(n)
        for j in range(ny):  # pragma: no branch
            for i in range(nx):  # pragma: no branch
                var c = i + nx * j
                a_center[c] = volume / dt
                bu[c] = volume / dt * old_u[c]
                bv[c] = volume / dt * old_v[c]
                for side in range(4):
                    var area = grid.dy
                    var distance = grid.dx
                    if side >= 2:
                        area = grid.dx
                        distance = grid.dy
                    var out = self._outward(i, j, side)
                    if grid.neighbor(i, j, side) >= 0:
                        var diffusion = nu * area / distance
                        if upwind:
                            a_side[4 * c + side] = diffusion + max(-out, 0)
                            a_center[c] += diffusion + max(out, 0)
                        else:
                            a_side[4 * c + side] = diffusion - out / 2
                            a_center[c] += diffusion + out / 2
                        continue
                    ref boundary = self.flow.boundaries[side]
                    if boundary.kind == FIXED_PRESSURE:
                        a_center[c] += out
                        continue
                    var diffusion = 2 * nu * area / distance
                    a_center[c] += diffusion
                    bu[c] += (diffusion - out) * boundary.u
                    bv[c] += (diffusion - out) * boundary.v
        # The momentum predictor, with the old pressure.
        var gx = zeros(n)
        var gy = zeros(n)
        self._gradient(gx, gy)
        for _ in range(self.options.sweeps):  # pragma: no branch
            var update = Float64(0)
            var size = Float64(0)
            for j in range(ny):  # pragma: no branch
                for i in range(nx):  # pragma: no branch
                    var c = i + nx * j
                    var su = bu[c] - volume * gx[c]
                    var sv = bv[c] - volume * gy[c]
                    for side in range(4):
                        var other = grid.neighbor(i, j, side)
                        if other >= 0:
                            su += a_side[4 * c + side] * self.u[other]
                            sv += a_side[4 * c + side] * self.v[other]
                    var new_u = su / a_center[c]
                    var new_v = sv / a_center[c]
                    update = max(update, abs(new_u - self.u[c]))
                    update = max(update, abs(new_v - self.v[c]))
                    size = max(size, max(abs(new_u), abs(new_v)))
                    self.u[c] = new_u
                    self.v[c] = new_v
            if update <= _SWEEP_TOLERANCE * size:
                break
        # The pressure correctors.
        var hu = zeros(n)
        var hv = zeros(n)
        var inverse = zeros(n)
        var has_pressure = False
        for s in range(4):
            if self.flow.boundaries[s].kind == FIXED_PRESSURE:
                has_pressure = True
        for _ in range(self.options.correctors):  # pragma: no branch
            for j in range(ny):  # pragma: no branch
                for i in range(nx):  # pragma: no branch
                    var c = i + nx * j
                    var su = bu[c]
                    var sv = bv[c]
                    for side in range(4):
                        var other = grid.neighbor(i, j, side)
                        if other >= 0:
                            su += a_side[4 * c + side] * self.u[other]
                            sv += a_side[4 * c + side] * self.v[other]
                    hu[c] = su / a_center[c]
                    hv[c] = sv / a_center[c]
                    inverse[c] = volume / a_center[c]
            # The pressure equation: Σ c (p - p_neighbor) = -Σ flux.
            var rhs = zeros(n)
            for j in range(ny):  # pragma: no branch
                for i in range(nx):  # pragma: no branch
                    var c = i + nx * j
                    var diagonal = Float64(0)
                    for side in range(4):
                        var area = grid.dy
                        var distance = grid.dx
                        if side >= 2:
                            area = grid.dx
                            distance = grid.dy
                        var normal_x = _normal_x(side)
                        var normal_y = _normal_y(side)
                        var other = grid.neighbor(i, j, side)
                        if other >= 0:
                            var coefficient = (
                                0.5
                                * (inverse[c] + inverse[other])
                                * area
                                / distance
                            )
                            var flux = (
                                0.5
                                * (
                                    (hu[c] + hu[other]) * normal_x
                                    + (hv[c] + hv[other]) * normal_y
                                )
                                * area
                            )
                            diagonal += coefficient
                            self.matrix.values[
                                _slot(self.matrix, c, other)
                            ] = -coefficient
                            rhs[c] -= flux
                            continue
                        ref boundary = self.flow.boundaries[side]
                        if boundary.kind == FIXED_PRESSURE:
                            var coefficient = 2 * inverse[c] * area / distance
                            var flux = (
                                hu[c] * normal_x + hv[c] * normal_y
                            ) * area
                            diagonal += coefficient
                            rhs[c] += (
                                coefficient * boundary.p / self.flow.density
                                - flux
                            )
                            continue
                        rhs[c] -= (
                            boundary.u * normal_x + boundary.v * normal_y
                        ) * area
                    if c == 0 and not has_pressure:
                        # Every side fixes the velocity, so the pressure
                        # is free by a constant. Hold it near zero in the
                        # first cell.
                        diagonal *= 2
                    self.matrix.values[_slot(self.matrix, c, c)] = diagonal
            # Solve for the change of the pressure, to the tolerance that
            # a solution from zero has.
            var target = self.options.pressure_tolerance * norm(rhs)
            var product = self.matrix.multiply(self.p)
            for c in range(n):  # pragma: no branch
                rhs[c] -= product[c]
            var residual = norm(rhs)
            if residual > target:
                var solved = conjugate_gradient(
                    self.matrix,
                    rhs,
                    target / residual,
                    self.options.pressure_iterations,
                )
                if solved.status != CONVERGED:
                    raise Error(
                        "The pressure solution did not converge within its"
                        " budget"
                    )
                for c in range(n):  # pragma: no branch
                    self.p[c] += solved.x[c]
            # Correct the face fluxes with the new pressure.
            for j in range(ny):  # pragma: no branch
                for i in range(nx):  # pragma: no branch
                    var c = i + nx * j
                    for side in range(4):
                        var area = grid.dy
                        var distance = grid.dx
                        if side >= 2:
                            area = grid.dx
                            distance = grid.dy
                        var normal_x = _normal_x(side)
                        var normal_y = _normal_y(side)
                        var other = grid.neighbor(i, j, side)
                        var out: Float64
                        if other >= 0:
                            out = (
                                0.5
                                * (
                                    (hu[c] + hu[other]) * normal_x
                                    + (hv[c] + hv[other]) * normal_y
                                )
                                * area
                            ) - 0.5 * (
                                inverse[c] + inverse[other]
                            ) * area / distance * (
                                self.p[other] - self.p[c]
                            )
                        elif self.flow.boundaries[side].kind == FIXED_PRESSURE:
                            ref boundary = self.flow.boundaries[side]
                            out = (
                                hu[c] * normal_x + hv[c] * normal_y
                            ) * area - 2 * inverse[c] * area / distance * (
                                boundary.p / self.flow.density - self.p[c]
                            )
                        else:
                            ref boundary = self.flow.boundaries[side]
                            out = (
                                boundary.u * normal_x + boundary.v * normal_y
                            ) * area
                        if side == 0:
                            self.flux_x[i + (nx + 1) * j] = -out
                        elif side == 1:
                            self.flux_x[i + 1 + (nx + 1) * j] = out
                        elif side == 2:
                            self.flux_y[i + nx * j] = -out
                        else:
                            self.flux_y[i + nx * (j + 1)] = out
            # Correct the velocity: u = H / A - (1 / A) ∇p.
            self._gradient(gx, gy)
            for c in range(n):  # pragma: no branch
                self.u[c] = hu[c] - inverse[c] * gx[c]
                self.v[c] = hv[c] - inverse[c] * gy[c]
        var change = Float64(0)
        for c in range(n):  # pragma: no branch
            require_finite(self.u[c], "The flow is not finite")
            require_finite(self.v[c], "The flow is not finite")
            change = max(change, abs(self.u[c] - old_u[c]))
            change = max(change, abs(self.v[c] - old_v[c]))
        self.last_change = change
        self.time += dt

    def run(mut self, step: Duration64, steps: Int) raises:
        """Advance the flow by several equal time steps.

        Args:
            step: The time step. Positive.
            steps: How many steps. Zero or more.

        Raises:
            Error: If a step fails. See `step`.
        """
        for _ in range(steps):
            self.step(step)

    def run_to_steady(
        mut self, step: Duration64, tolerance: Velocity64, budget: Int
    ) raises -> Int:
        """Advance the flow until it stops changing.

        Args:
            step: The time step. Positive.
            tolerance: The largest change of a velocity in one step at
                which the flow is steady. Positive.
            budget: The largest number of steps. One or more.

        Returns:
            The number of steps taken.

        Raises:
            Error: If the tolerance or the budget is not positive, a step
                fails, or the flow is not steady within the budget.
        """
        var limit = tolerance.to(METER_PER_SECOND)
        require_positive_finite(
            limit, "A steady tolerance must be positive and finite"
        )
        require_positive(budget, "A step budget must be one or more")
        for taken in range(1, budget + 1):  # pragma: no branch
            self.step(step)
            if self.last_change <= limit:
                return taken
        raise Error("The flow is not steady within the step budget")
