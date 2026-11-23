# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steady heads in one aquifer layer, by block-centered finite differences.

The layer is a grid of equal cells. Each cell has a hydraulic
conductivity K. The flow between two cells follows Darcy: it is their
head difference times a conductance. The conductance is the width of
their common face, over the distance of their centers, times the harmonic
mean of their transmissivities. The transmissivity of a cell is K times
its saturated thickness.

Each active cell keeps its water: the flows from its four neighbors, its
well and its recharge add to zero. A cell of fixed head gives or takes
what its neighbors need. An inactive cell passes no water, so its faces
are no-flow boundaries, as the sides of the grid are.

In a confined layer the thickness is the top less the bottom, and one
solution gives the heads. In an unconfined layer the thickness is the
head less the bottom, so the equations are solved again with the new
heads until the heads stop changing.

These are the equations of McDonald and Harbaugh, "A modular
three-dimensional finite-difference ground-water flow model", US
Geological Survey, 1988, for one layer in steady flow. MODFLOW is in the
public domain, and the code here is original.
"""

from std.math import isfinite
from core.ordinal import require_positive, require_valid
from math.finite import (
    require_finite,
    require_positive_finite,
    require_positive_tolerance,
)
from extensions.groundwater.kinds import (
    ACTIVE,
    AquiferKind,
    CellKind,
    FIXED_HEAD,
    INACTIVE,
    UNCONFINED,
)
from extensions.numerics.skyline import SkylineFactor, reverse_cuthill_mckee
from extensions.numerics.sparse import SparseBuilder
from extensions.numerics.vector import zeros
from units.si import (
    CUBIC_METER_PER_SECOND,
    Length64,
    METER,
    METER_PER_SECOND,
    Velocity64,
    VolumeFlowRate64,
)

# The largest number of cells of one grid.
comptime MAX_AQUIFER_CELLS = 1048576


struct Aquifer(Copyable, Movable):
    """One aquifer layer on a grid of equal cells.

    Cell (i, j) is column i along x and row j along y. Its index in a
    list is i + nx j.
    """

    var nx: Int
    var ny: Int
    # The cell size along x and along y, in meters.
    var dx: Float64
    var dy: Float64
    var kind: AquiferKind
    # The elevation of the bottom and of the top of the layer, in meters.
    var bottom: Float64
    var top: Float64
    # The hydraulic conductivity of each cell, in meters per second.
    var conductivity: List[Float64]
    var kinds: List[CellKind]
    # The head of each cell of fixed head, in meters.
    var fixed: List[Float64]
    # The well of each cell, in cubic meters per second. A positive rate
    # adds water.
    var wells: List[Float64]
    # The recharge of each cell, in meters per second.
    var recharge: List[Float64]

    def __init__(
        out self,
        nx: Int,
        ny: Int,
        width: Length64,
        height: Length64,
        kind: AquiferKind,
        bottom: Length64,
        top: Length64,
        conductivity: Velocity64,
    ) raises:
        """Create a layer of active cells with no well and no recharge.

        Args:
            nx: The number of cells along x. One or more.
            ny: The number of cells along y. One or more.
            width: The size of the grid along x. Positive.
            height: The size of the grid along y. Positive.
            kind: `CONFINED` or `UNCONFINED`.
            bottom: The elevation of the bottom of the layer.
            top: The elevation of the top. Above the bottom. An
                unconfined layer with a head above its top is full, as a
                confined one is.
            conductivity: The hydraulic conductivity of every cell.
                Positive.

        Raises:
            Error: If a count is not positive, the grid has more than
                1048576 cells, a size is not positive and finite, the
                kind is not valid, the top is not above the bottom, or
                the conductivity is not positive and finite.
        """
        require_positive(nx, "An aquifer needs one cell or more along x")
        require_positive(ny, "An aquifer needs one cell or more along y")
        if nx > MAX_AQUIFER_CELLS or ny > MAX_AQUIFER_CELLS // nx:
            raise Error("An aquifer is larger than this port stores")
        var w = width.to(METER)
        var h = height.to(METER)
        require_positive_finite(w, "A grid width must be positive and finite")
        require_positive_finite(h, "A grid height must be positive and finite")
        require_valid(kind.is_valid(), "An aquifer kind must be 0 or 1")
        var low = bottom.to(METER)
        var high = top.to(METER)
        require_finite(low, "A layer bottom must be finite")
        if not (high > low and isfinite(high)):
            raise Error("A layer top must be above its bottom and finite")
        var k = conductivity.to(METER_PER_SECOND)
        require_positive_finite(
            k, "A hydraulic conductivity must be positive and finite"
        )
        var cells = nx * ny
        self.nx = nx
        self.ny = ny
        self.dx = w / Float64(nx)
        self.dy = h / Float64(ny)
        self.kind = kind
        self.bottom = low
        self.top = high
        self.conductivity = List[Float64](length=cells, fill=k)
        self.kinds = List[CellKind](length=cells, fill=ACTIVE)
        self.fixed = List[Float64](length=cells, fill=0)
        self.wells = List[Float64](length=cells, fill=0)
        self.recharge = List[Float64](length=cells, fill=0)

    def cell(self, i: Int, j: Int) raises -> Int:
        """Return the index of a cell in a list.

        Args:
            i: The column, along x.
            j: The row, along y.

        Returns:
            The index i + nx j.

        Raises:
            Error: If the column or the row is out of range.
        """
        if i < 0 or i >= self.nx or j < 0 or j >= self.ny:
            raise Error("A cell is out of range")
        return i + self.nx * j

    def set_conductivity(
        mut self, i: Int, j: Int, conductivity: Velocity64
    ) raises:
        """Set the hydraulic conductivity of one cell.

        Args:
            i: The column.
            j: The row.
            conductivity: The conductivity. Positive.

        Raises:
            Error: If the cell is out of range or the conductivity is not
                positive and finite.
        """
        var c = self.cell(i, j)
        var k = conductivity.to(METER_PER_SECOND)
        require_positive_finite(
            k, "A hydraulic conductivity must be positive and finite"
        )
        self.conductivity[c] = k

    def set_fixed_head(mut self, i: Int, j: Int, head: Length64) raises:
        """Make a cell a cell of fixed head.

        Args:
            i: The column.
            j: The row.
            head: The head of the cell.

        Raises:
            Error: If the cell is out of range or the head is not finite.
        """
        var c = self.cell(i, j)
        var h = head.to(METER)
        require_finite(h, "A fixed head must be finite")
        self.kinds[c] = FIXED_HEAD
        self.fixed[c] = h

    def set_inactive(mut self, i: Int, j: Int) raises:
        """Make a cell inactive, so that no water passes it.

        Args:
            i: The column.
            j: The row.

        Raises:
            Error: If the cell is out of range.
        """
        self.kinds[self.cell(i, j)] = INACTIVE

    def add_well(mut self, i: Int, j: Int, rate: VolumeFlowRate64) raises:
        """Add a well to a cell.

        A well in a cell that is not active has no effect.

        Args:
            i: The column.
            j: The row.
            rate: The flow of the well. A negative rate pumps water out,
                as in MODFLOW.

        Raises:
            Error: If the cell is out of range or the rate is not finite.
        """
        var c = self.cell(i, j)
        var q = rate.to(CUBIC_METER_PER_SECOND)
        require_finite(q, "A well rate must be finite")
        self.wells[c] += q

    def set_recharge(mut self, rate: Velocity64) raises:
        """Set the recharge of every cell.

        Args:
            rate: The water that enters the layer from above, as a
                volume per area and per time.

        Raises:
            Error: If the rate is not finite.
        """
        var r = rate.to(METER_PER_SECOND)
        require_finite(r, "A recharge must be finite")
        for c in range(len(self.recharge)):  # pragma: no branch
            self.recharge[c] = r

    def neighbor(self, c: Int, side: Int) -> Int:
        """Return the cell across a side of a cell.

        Args:
            c: The index of the cell.
            side: 0 for lower x, 1 for higher x, 2 for lower y and 3 for
                higher y.

        Returns:
            The index of the neighbor, or -1 at the edge of the grid.
        """
        var i = c % self.nx
        var j = c // self.nx
        if side == 0:
            if i == 0:
                return -1
            return c - 1
        if side == 1:
            if i == self.nx - 1:
                return -1
            return c + 1
        if side == 2:
            if j == 0:
                return -1
            return c - self.nx
        if j == self.ny - 1:
            return -1
        return c + self.nx


struct HeadOptions(ImplicitlyCopyable):
    """When the solutions of an unconfined layer stop."""

    # The largest change of a head between two solutions, in meters, at
    # which to stop.
    var tolerance: Float64
    var iterations: Int

    def __init__(out self, tolerance: Length64, iterations: Int) raises:
        """Create the options.

        Args:
            tolerance: The largest change of a head between two
                solutions at which the heads are final. Positive.
            iterations: The largest number of solutions. One or more.

        Raises:
            Error: If the tolerance is not positive and finite or the
                iteration count is not positive.
        """
        require_positive_tolerance(tolerance.to(METER))
        require_positive(iterations, "An iteration budget must be one or more")
        self.tolerance = tolerance.to(METER)
        self.iterations = iterations


def default_head_options() raises -> HeadOptions:
    """Return a tolerance of 1e-9 m and a budget of 200 solutions.

    Returns:
        The options.

    Raises:
        Error: Never.
    """
    return HeadOptions(Length64(1e-9), 200)


struct HeadResult(Movable):
    """The heads of a solved layer and its water budget."""

    var nx: Int
    # The head of each cell, in meters. An inactive cell has the bottom
    # elevation.
    var heads: List[Float64]
    # The water that the fixed heads, the wells and the recharge give to
    # the active cells, in cubic meters per second. They add to zero.
    var from_fixed: Float64
    var from_wells: Float64
    var from_recharge: Float64
    var iterations: Int

    def __init__(
        out self,
        nx: Int,
        var heads: List[Float64],
        from_fixed: Float64,
        from_wells: Float64,
        from_recharge: Float64,
        iterations: Int,
    ):
        """Hold a result. `solve_heads` makes these.

        Args:
            nx: The number of cells along x.
            heads: One head per cell.
            from_fixed: The flow from the cells of fixed head.
            from_wells: The flow from the wells.
            from_recharge: The flow from the recharge.
            iterations: How many solutions ran.
        """
        self.nx = nx
        self.heads = heads^
        self.from_fixed = from_fixed
        self.from_wells = from_wells
        self.from_recharge = from_recharge
        self.iterations = iterations

    def head(self, i: Int, j: Int) raises -> Length64:
        """Return the head of a cell.

        Args:
            i: The column.
            j: The row.

        Returns:
            The head.

        Raises:
            Error: If the cell is out of range.
        """
        if i < 0 or i >= self.nx or j < 0:
            raise Error("A cell is out of range")
        var c = i + self.nx * j
        if c >= len(self.heads):
            raise Error("A cell is out of range")
        return Length64(self.heads[c])

    def fixed_head_flow(self) -> VolumeFlowRate64:
        """Return the water that the cells of fixed head give to the layer.

        Returns:
            The flow. A negative flow leaves through the fixed heads.
        """
        return VolumeFlowRate64(self.from_fixed)

    def balance(self) -> VolumeFlowRate64:
        """Return the sum of the three parts of the water budget.

        Returns:
            The flow from the fixed heads, the wells and the recharge.
            It is zero but for round-off.
        """
        return VolumeFlowRate64(
            self.from_fixed + self.from_wells + self.from_recharge
        )


def _transmissivity(aquifer: Aquifer, c: Int, head: Float64) raises -> Float64:
    """Return the conductivity of a cell times its saturated thickness."""
    var thickness = aquifer.top - aquifer.bottom
    if aquifer.kind == UNCONFINED:
        thickness = min(head, aquifer.top) - aquifer.bottom
        if not (thickness > 0):
            raise Error(
                "A cell of an unconfined layer is dry: its head is not"
                " above the bottom"
            )
    return aquifer.conductivity[c] * thickness


def _conductance(
    aquifer: Aquifer, heads: List[Float64], c: Int, other: Int, side: Int
) raises -> Float64:
    """Return the flow between two cells for a head difference of one."""
    var a = _transmissivity(aquifer, c, heads[c])
    var b = _transmissivity(aquifer, other, heads[other])
    var shape = aquifer.dy / aquifer.dx
    if side >= 2:
        shape = aquifer.dx / aquifer.dy
    return shape * 2 * a * b / (a + b)


def solve_heads(aquifer: Aquifer, options: HeadOptions) raises -> HeadResult:
    """Return the steady heads of an aquifer layer.

    Args:
        aquifer: The layer. Each active cell needs a path of cells to a
            cell of fixed head.
        options: The tolerance and the budget of the solutions of an
            unconfined layer. A confined layer needs one solution.

    Returns:
        The heads and the water budget.

    Raises:
        Error: If the layer has no cell of fixed head, an active cell has
            no path to one, a cell of an unconfined layer is dry, or the
            heads do not settle within the budget.
    """
    var cells = aquifer.nx * aquifer.ny
    var equation = List[Int](capacity=cells)
    var count = 0
    var fixed_count = 0
    var mean = Float64(0)
    for c in range(cells):  # pragma: no branch
        if aquifer.kinds[c] == ACTIVE:
            equation.append(count)
            count += 1
        else:
            equation.append(-1)
        if aquifer.kinds[c] == FIXED_HEAD:
            fixed_count += 1
            mean += aquifer.fixed[c]
    if fixed_count == 0:
        raise Error("An aquifer needs a cell of fixed head")
    mean /= Float64(fixed_count)
    # The first heads: the fixed heads, and their mean elsewhere.
    var heads = List[Float64](length=cells, fill=mean)
    for c in range(cells):  # pragma: no branch
        if aquifer.kinds[c] == FIXED_HEAD:
            heads[c] = aquifer.fixed[c]
    var area = aquifer.dx * aquifer.dy
    for iteration in range(1, options.iterations + 1):  # pragma: no branch
        var builder = SparseBuilder(count)
        var rhs = zeros(count)
        for c in range(cells):  # pragma: no branch
            var row = equation[c]
            if row < 0:
                continue
            rhs[row] = aquifer.wells[c] + aquifer.recharge[c] * area
            for side in range(4):
                var other = aquifer.neighbor(c, side)
                if other < 0:
                    continue
                if aquifer.kinds[other] == INACTIVE:
                    continue
                var conductance = _conductance(aquifer, heads, c, other, side)
                builder.add(row, row, conductance)
                if equation[other] >= 0:
                    builder.add(row, equation[other], -conductance)
                else:
                    rhs[row] += conductance * aquifer.fixed[other]
        var solved: List[Float64]
        try:
            var matrix = builder.build()
            var factor = SkylineFactor(matrix, reverse_cuthill_mckee(matrix))
            solved = factor.solve(rhs)
        except:
            raise Error("An active cell has no path of cells to a fixed head")
        var change = Float64(0)
        for c in range(cells):  # pragma: no branch
            if equation[c] >= 0:
                change = max(change, abs(solved[equation[c]] - heads[c]))
                heads[c] = solved[equation[c]]
        if aquifer.kind == UNCONFINED and change > options.tolerance:
            continue
        # The water budget, with the conductances of the final heads.
        var from_fixed = Float64(0)
        var from_wells = Float64(0)
        var from_recharge = Float64(0)
        for c in range(cells):  # pragma: no branch
            if equation[c] < 0:
                continue
            from_wells += aquifer.wells[c]
            from_recharge += aquifer.recharge[c] * area
            for side in range(4):
                var other = aquifer.neighbor(c, side)
                if other < 0:
                    continue
                if aquifer.kinds[other] != FIXED_HEAD:
                    continue
                from_fixed += _conductance(aquifer, heads, c, other, side) * (
                    heads[other] - heads[c]
                )
        for c in range(cells):  # pragma: no branch
            if aquifer.kinds[c] == INACTIVE:
                heads[c] = aquifer.bottom
        return HeadResult(
            aquifer.nx,
            heads^,
            from_fixed,
            from_wells,
            from_recharge,
            iteration,
        )
    raise Error("The heads did not settle within the iteration budget")
