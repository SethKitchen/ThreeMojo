# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Maps over two variables.

- `scan` evaluates constraints on a grid: temperature on a linear scale,
  pressure on a logarithmic one. `boundary` traces the edge of the region
  where every constraint holds, by marching squares.
- `ellingham` gives the Gibbs energy change of an oxidation per mole of
  O2. `oxygen_pressure` is the O2 pressure in balance with it, and
  `reducing_ratio` is the CO/CO2 or H2/H2O ratio in balance with it.
  `ellingham_crossing` finds where two such lines cross.
- `predominance` labels each point of a plane of two gas pressures with
  the most stable compound of a base element, as a Kellogg diagram does.
- `oxide_map` labels each point of a plane of temperature and the
  fraction of a reducing gas, as the Baur-Glaessner diagram of iron does.

A predominance or oxide map compares each candidate per atom of the base
element, with the gases at the pressures of the point. A condensed
candidate is pure. A gaseous candidate of the base element is at a fixed
partial pressure, one bar unless the caller gives another.
"""

from std.math import exp, isfinite, log
from extensions.chemistry.elements import Element, OXYGEN
from extensions.chemistry.quantities import (
    GAS_CONSTANT,
    MolarEnergy64,
    STANDARD_PRESSURE,
)
from extensions.chemistry.reaction import Reaction
from extensions.chemistry.requirement import Constraint
from extensions.chemistry.thermo import Substance
from units.si import Pressure64
from units.temperature import Temperature64

# The most nodes on one side of a map.
comptime MAX_SIDE = 2000
# Bisection steps for a crossing: far below a microkelvin.
comptime _BISECTIONS = 60


# Marching squares: the edge pairs of each of the 16 corner cases, -1 for
# none. Edges: 0 bottom, 1 right, 2 top, 3 left. The two saddle cases, 5
# and 10, keep the held corners apart.
def _cases() -> List[Int]:
    """Return the marching-squares table, four entries per case."""
    # fmt: off
    return [
        -1, -1, -1, -1,
        3, 0, -1, -1,
        0, 1, -1, -1,
        3, 1, -1, -1,
        1, 2, -1, -1,
        3, 0, 1, 2,
        0, 2, -1, -1,
        3, 2, -1, -1,
        2, 3, -1, -1,
        0, 2, -1, -1,
        0, 1, 2, 3,
        1, 2, -1, -1,
        3, 1, -1, -1,
        0, 1, -1, -1,
        3, 0, -1, -1,
        -1, -1, -1, -1,
    ]
    # fmt: on


def _require_side(count: Int, what: String) raises:
    """Refuse a node count outside 2 to MAX_SIDE."""
    if not (count >= 2 and count <= MAX_SIDE):
        raise Error(what + " must have 2 to 2000 nodes")


def _require_temperatures(low: Temperature64, high: Temperature64) raises:
    """Refuse a temperature range that is not physical and increasing."""
    if not (low.is_valid() and high.is_valid() and low.kelvin < high.kelvin):
        raise Error("A temperature range must be physical and increase")


def _require_increasing(low: Float64, high: Float64, what: String) raises:
    """Refuse a range that is not finite and increasing."""
    if not (isfinite(low) and isfinite(high) and low < high):
        raise Error(what + " must be finite and increase")


@fieldwise_init
struct Segment(ImplicitlyCopyable):
    """One piece of a boundary, between two points of the plane."""

    var t1: Temperature64
    var p1: Pressure64
    var t2: Temperature64
    var p2: Pressure64


struct Grid(Copyable, Movable):
    """Where constraints hold, at each node of a temperature-pressure grid."""

    var low: Temperature64
    var high: Temperature64
    var p_low: Pressure64
    var p_high: Pressure64
    var columns: Int
    var rows: Int
    # One flag per node, row by row from the lowest pressure.
    var held: List[Bool]

    def __init__(
        out self,
        low: Temperature64,
        high: Temperature64,
        p_low: Pressure64,
        p_high: Pressure64,
        columns: Int,
        rows: Int,
    ) raises:
        """Make a grid where nothing holds yet.

        Args:
            low: The lowest temperature.
            high: The highest temperature.
            p_low: The lowest pressure.
            p_high: The highest pressure.
            columns: Nodes along temperature, 2 to 2000.
            rows: Nodes along pressure, 2 to 2000.

        Raises:
            Error: If a range is not physical and increasing, or a side
                has too few or too many nodes.
        """
        _require_temperatures(low, high)
        if not (p_low.value > 0 and p_low.value < p_high.value):
            raise Error("A pressure range must be positive and increase")
        _require_increasing(
            log(p_low.value), log(p_high.value), "A pressure range"
        )
        _require_side(columns, "A grid's temperature side")
        _require_side(rows, "A grid's pressure side")
        self.low = low
        self.high = high
        self.p_low = p_low
        self.p_high = p_high
        self.columns = columns
        self.rows = rows
        self.held = List[Bool]()
        for _ in range(columns * rows):  # pragma: no branch
            self.held.append(False)

    def _t(self, column: Float64) -> Temperature64:
        """Return the temperature at a fractional column."""
        var f = column / Float64(self.columns - 1)
        return Temperature64(
            self.low.kelvin + (self.high.kelvin - self.low.kelvin) * f
        )

    def _p(self, row: Float64) -> Pressure64:
        """Return the pressure at a fractional row."""
        var f = row / Float64(self.rows - 1)
        var a = log(self.p_low.value)
        return Pressure64(exp(a + (log(self.p_high.value) - a) * f))

    def temperature(self, column: Int) -> Temperature64:
        """Return the temperature of a column.

        Args:
            column: From 0 to `columns - 1`.

        Returns:
            The temperature, on a linear scale.
        """
        return self._t(Float64(column))

    def pressure(self, row: Int) -> Pressure64:
        """Return the pressure of a row.

        Args:
            row: From 0 to `rows - 1`.

        Returns:
            The pressure, on a logarithmic scale.
        """
        return self._p(Float64(row))

    def holds(self, column: Int, row: Int) raises -> Bool:
        """Return True if every constraint holds at a node.

        Args:
            column: The column.
            row: The row.

        Returns:
            Whether the node is in the region.

        Raises:
            Error: If the node is outside the grid.
        """
        if not (column >= 0 and column < self.columns):
            raise Error("A column is outside the grid")
        if not (row >= 0 and row < self.rows):
            raise Error("A row is outside the grid")
        return self.held[row * self.columns + column]

    def share(self) -> Float64:
        """Return the share of nodes in the region.

        Returns:
            From zero to one.
        """
        var count = 0
        for h in self.held:  # pragma: no branch
            if h:
                count += 1
        return Float64(count) / Float64(len(self.held))


def scan[
    C: Constraint
](
    constraints: List[C],
    low: Temperature64,
    high: Temperature64,
    p_low: Pressure64,
    p_high: Pressure64,
    columns: Int,
    rows: Int,
) raises -> Grid:
    """Return where every constraint holds over a temperature-pressure grid.

    Parameters:
        C: The constraints' type.

    Args:
        constraints: The constraints. With none, every node holds.
        low: The lowest temperature.
        high: The highest temperature.
        p_low: The lowest pressure.
        p_high: The highest pressure.
        columns: Nodes along temperature, 2 to 2000.
        rows: Nodes along pressure, 2 to 2000.

    Returns:
        The grid.

    Raises:
        Error: If a range or a side is not valid, or a constraint cannot
            be evaluated.
    """
    var grid = Grid(low, high, p_low, p_high, columns, rows)
    for row in range(rows):  # pragma: no branch
        var p = grid.pressure(row)
        for column in range(columns):  # pragma: no branch
            var t = grid.temperature(column)
            var all = True
            for c in constraints:
                if not c.holds(t, p):
                    all = False
                    break
            grid.held[row * columns + column] = all
    return grid^


def _edge_point(
    grid: Grid, column: Int, row: Int, edge: Int
) -> Tuple[Float64, Float64]:
    """Return the fractional column and row of a cell edge's midpoint."""
    var c = Float64(column)
    var r = Float64(row)
    var dc: List[Float64] = [0.5, 1.0, 0.5, 0.0]
    var dr: List[Float64] = [0.0, 0.5, 1.0, 0.5]
    return (c + dc[edge], r + dr[edge])


def boundary(grid: Grid) -> List[Segment]:
    """Return the edge of a grid's region, cell by cell.

    Args:
        grid: The grid.

    Returns:
        Segments between the midpoints of cell edges that the region's
        edge crosses. The edge is accurate to half a cell.
    """
    var out = List[Segment]()
    var cases = _cases()
    for row in range(grid.rows - 1):  # pragma: no branch
        for column in range(grid.columns - 1):  # pragma: no branch
            var base = row * grid.columns + column
            var corners = (
                Int(grid.held[base])
                + 2 * Int(grid.held[base + 1])
                + 4 * Int(grid.held[base + grid.columns + 1])
                + 8 * Int(grid.held[base + grid.columns])
            )
            for k in [0, 2]:
                var e1 = cases[4 * corners + k]
                if e1 < 0:
                    continue
                var e2 = cases[4 * corners + k + 1]
                var a = _edge_point(grid, column, row, e1)
                var b = _edge_point(grid, column, row, e2)
                out.append(
                    Segment(
                        grid._t(a[0]),
                        grid._p(a[1]),
                        grid._t(b[0]),
                        grid._p(b[1]),
                    )
                )
    return out^


def _oxygen_moles(reaction: Reaction) raises -> Float64:
    """Return the moles of O2 gas that a reaction uses."""
    for term in reaction.terms:  # pragma: no branch
        ref f = term.substance.phases[0].formula
        var is_o2 = len(f.counts) == 1 and f.count_of(OXYGEN) == 2
        if is_o2 and term.substance.is_gas() and term.coefficient < 0:
            return -term.coefficient
    raise Error("An Ellingham line needs O2 gas as a reactant")


def ellingham(
    reaction: Reaction, temperature: Temperature64
) raises -> MolarEnergy64:
    """Return an oxidation's Gibbs energy change per mole of O2.

    Args:
        reaction: An oxidation with O2 gas as a reactant, such as
            2 Fe + O2 -> 2 FeO.
        temperature: The temperature.

    Returns:
        The standard change at one bar, per mole of O2.

    Raises:
        Error: If O2 gas is not a reactant or the data does not reach the
            temperature.
    """
    var n = _oxygen_moles(reaction)
    return reaction.delta_g(temperature, STANDARD_PRESSURE).scaled(1 / n)


def oxygen_pressure(
    reaction: Reaction, temperature: Temperature64
) raises -> Pressure64:
    """Return the O2 pressure in balance with an oxidation.

    Below it the oxide gives up its oxygen. Above it the metal oxidizes.

    Args:
        reaction: The oxidation.
        temperature: The temperature.

    Returns:
        The pressure p0 exp(dG / RT), with dG per mole of O2.

    Raises:
        Error: If the line cannot be evaluated.
    """
    var g = ellingham(reaction, temperature).value
    var rt = GAS_CONSTANT.value * temperature.kelvin
    return Pressure64(STANDARD_PRESSURE.value * exp(g / rt))


def reducing_ratio(
    couple: Reaction, reaction: Reaction, temperature: Temperature64
) raises -> Float64:
    """Return the reducing-gas ratio in balance with an oxidation.

    Args:
        couple: The oxidation of the reducing gas with two moles of it per
            mole of O2: 2 CO + O2 -> 2 CO2, or 2 H2 + O2 -> 2 H2O.
        reaction: The oxidation of the metal.
        temperature: The temperature.

    Returns:
        The ratio p(CO)/p(CO2), or p(H2)/p(H2O), above which the gas
        reduces the oxide.

    Raises:
        Error: If a line cannot be evaluated.
    """
    var gc = ellingham(couple, temperature).value
    var gm = ellingham(reaction, temperature).value
    var rt = GAS_CONSTANT.value * temperature.kelvin
    return exp((gc - gm) / (2 * rt))


def ellingham_crossing(
    a: Reaction, b: Reaction, low: Temperature64, high: Temperature64
) raises -> Temperature64:
    """Return where two Ellingham lines cross.

    Args:
        a: One oxidation.
        b: The other.
        low: The low end of the search.
        high: The high end of the search.

    Returns:
        The temperature where both changes per mole of O2 are equal.

    Raises:
        Error: If a line cannot be evaluated, or the lines do not cross in
            the range.
    """
    _require_temperatures(low, high)
    var lo = low.kelvin
    var hi = high.kelvin
    var d_lo = ellingham(a, low).value - ellingham(b, low).value
    var d_hi = ellingham(a, high).value - ellingham(b, high).value
    if (d_lo < 0) == (d_hi < 0):
        raise Error("The lines do not cross in the range")
    for _ in range(_BISECTIONS):  # pragma: no branch
        var mid = 0.5 * (lo + hi)
        var t = Temperature64(mid)
        var d = ellingham(a, t).value - ellingham(b, t).value
        if (d < 0) == (d_lo < 0):
            lo = mid
        else:
            hi = mid
    return Temperature64(0.5 * (lo + hi))


struct LabelMap(Copyable, Movable):
    """The label of each node of a plane, by candidate index."""

    var names: List[String]
    var x_low: Float64
    var x_high: Float64
    var y_low: Float64
    var y_high: Float64
    var columns: Int
    var rows: Int
    var labels: List[Int]

    def __init__(
        out self,
        var names: List[String],
        x_low: Float64,
        x_high: Float64,
        y_low: Float64,
        y_high: Float64,
        columns: Int,
        rows: Int,
    ) raises:
        """Make a map with every node labeled 0.

        Args:
            names: The candidates' names, by label.
            x_low: The low end of the first axis.
            x_high: The high end of the first axis.
            y_low: The low end of the second axis.
            y_high: The high end of the second axis.
            columns: Nodes along the first axis, 2 to 2000.
            rows: Nodes along the second axis, 2 to 2000.

        Raises:
            Error: If an axis is not finite and increasing, or a side has
                too few or too many nodes.
        """
        _require_increasing(x_low, x_high, "A first axis")
        _require_increasing(y_low, y_high, "A second axis")
        _require_side(columns, "A map's first side")
        _require_side(rows, "A map's second side")
        self.names = names^
        self.x_low = x_low
        self.x_high = x_high
        self.y_low = y_low
        self.y_high = y_high
        self.columns = columns
        self.rows = rows
        self.labels = List[Int]()
        for _ in range(columns * rows):  # pragma: no branch
            self.labels.append(0)

    def x(self, column: Int) -> Float64:
        """Return the first axis at a column.

        Args:
            column: From 0 to `columns - 1`.

        Returns:
            The value, on a linear scale.
        """
        var f = Float64(column) / Float64(self.columns - 1)
        return self.x_low + (self.x_high - self.x_low) * f

    def y(self, row: Int) -> Float64:
        """Return the second axis at a row.

        Args:
            row: From 0 to `rows - 1`.

        Returns:
            The value, on a linear scale.
        """
        var f = Float64(row) / Float64(self.rows - 1)
        return self.y_low + (self.y_high - self.y_low) * f

    def label(self, column: Int, row: Int) raises -> Int:
        """Return the label at a node.

        Args:
            column: The column.
            row: The row.

        Returns:
            The index of the stable candidate.

        Raises:
            Error: If the node is outside the map.
        """
        if not (column >= 0 and column < self.columns):
            raise Error("A column is outside the map")
        if not (row >= 0 and row < self.rows):
            raise Error("A row is outside the map")
        return self.labels[row * self.columns + column]

    def name_at(self, column: Int, row: Int) raises -> String:
        """Return the name of the stable candidate at a node.

        Args:
            column: The column.
            row: The row.

        Returns:
            The name.

        Raises:
            Error: If the node is outside the map.
        """
        return self.names[self.label(column, row)]


def _single_element(gas: Substance) raises -> Tuple[Element, Int]:
    """Return a one-element gas's element and atoms per molecule."""
    ref counts = gas.phases[0].formula.counts
    if not (gas.is_gas() and len(counts) == 1):
        raise Error("An axis gas must be a gas of one element, such as O2")
    return (counts[0].element, counts[0].count)


def predominance(
    base: Element,
    candidates: List[Substance],
    first: Substance,
    second: Substance,
    temperature: Temperature64,
    x_low: Float64,
    x_high: Float64,
    y_low: Float64,
    y_high: Float64,
    columns: Int,
    rows: Int,
    gas_pressure: Pressure64 = STANDARD_PRESSURE,
) raises -> LabelMap:
    """Return the most stable compound of an element over two gas pressures.

    Args:
        base: The element every candidate holds, such as titanium.
        candidates: Compounds of the base element and of the two gases'
            elements only.
        first: The gas of the first axis, of one element, such as O2.
        second: The gas of the second axis, such as Cl2.
        temperature: The temperature.
        x_low: The lowest log10 of the first gas's pressure in bar.
        x_high: The highest.
        y_low: The lowest log10 of the second gas's pressure in bar.
        y_high: The highest.
        columns: Nodes along the first axis.
        rows: Nodes along the second axis.
        gas_pressure: The partial pressure of a gaseous candidate.

    Returns:
        The label map, with the candidates' names.

    Raises:
        Error: If there is no candidate, an axis gas is not of one
            element, a candidate lacks the base element or holds another, a substance's data does not
            reach the temperature, or the map is not valid.
    """
    if len(candidates) == 0:
        raise Error("A map needs a candidate")
    var e1 = _single_element(first)
    var e2 = _single_element(second)
    var names = List[String]()
    for c in candidates:  # pragma: no branch
        names.append(c.name)
    var out = LabelMap(names^, x_low, x_high, y_low, y_high, columns, rows)
    var rt = GAS_CONSTANT.value * temperature.kelvin
    var g1 = first.gibbs(temperature).value / rt
    var g2 = second.gibbs(temperature).value / rt
    var log_gas = log(gas_pressure.value / STANDARD_PRESSURE.value)
    # Per candidate: atoms of the base, of each gas element, and G/RT.
    var per_base = List[Float64]()
    var share1 = List[Float64]()
    var share2 = List[Float64]()
    var g = List[Float64]()
    for c in candidates:  # pragma: no branch
        ref f = c.phases[0].formula
        var n = f.count_of(base)
        var a = f.count_of(e1[0])
        var b = f.count_of(e2[0])
        if n == 0:
            raise Error(String("Candidate '", c.name, "' lacks the base"))
        if n + a + b != _atoms(c):
            raise Error(
                String("Candidate '", c.name, "' holds another element")
            )
        var gj = c.gibbs(temperature).value / rt
        if c.is_gas():
            gj += log_gas
        per_base.append(Float64(n))
        share1.append(Float64(a) / Float64(e1[1]))
        share2.append(Float64(b) / Float64(e2[1]))
        g.append(gj)
    var ln10 = log(10.0)
    for row in range(rows):  # pragma: no branch
        var mu2 = g2 + out.y(row) * ln10
        for column in range(columns):  # pragma: no branch
            var mu1 = g1 + out.x(column) * ln10
            out.labels[row * columns + column] = _lowest(
                g, share1, share2, per_base, mu1, mu2
            )
    return out^


def _atoms(substance: Substance) -> Int:
    """Return the atoms in a substance's formula."""
    var total = 0
    for c in substance.phases[0].formula.counts:  # pragma: no branch
        total += c.count
    return total


def _lowest(
    g: List[Float64],
    share1: List[Float64],
    share2: List[Float64],
    per_base: List[Float64],
    mu1: Float64,
    mu2: Float64,
) -> Int:
    """Return the candidate with the lowest potential per base atom."""
    var best = 0
    var best_value = Float64(0)
    # A map has a candidate.
    for j in range(len(g)):  # pragma: no branch
        var value = (g[j] - share1[j] * mu1 - share2[j] * mu2) / per_base[j]
        if j == 0 or value < best_value:
            best = j
            best_value = value
    return best


def oxide_map(
    base: Element,
    candidates: List[Substance],
    oxygen_gas: Substance,
    couple: Reaction,
    low: Temperature64,
    high: Temperature64,
    f_low: Float64,
    f_high: Float64,
    columns: Int,
    rows: Int,
) raises -> LabelMap:
    """Return the stable oxide of an element over temperature and gas mix.

    The gas is a reducing gas and its oxidized form, such as CO and CO2,
    in balance with O2 through `couple`. The second axis is the reducing
    gas's fraction of the two.

    Args:
        base: The element, such as iron.
        candidates: The element and its oxides, such as Fe, FeO and Fe3O4.
        oxygen_gas: O2 gas, for its Gibbs energy.
        couple: The oxidation of the reducing gas, with two moles of it
            per mole of O2, such as 2 CO + O2 -> 2 CO2.
        low: The lowest temperature.
        high: The highest temperature.
        f_low: The lowest reducing fraction, above 0.
        f_high: The highest, below 1.
        columns: Nodes along temperature.
        rows: Nodes along the fraction.

    Returns:
        The label map: the first axis is the temperature in kelvin and the
        second the reducing fraction.

    Raises:
        Error: If the fractions are not in (0, 1), there is no candidate,
            a candidate lacks the base or holds an element other than it and oxygen, a line
            cannot be evaluated, or the map is not valid.
    """
    _require_temperatures(low, high)
    if not (f_low > 0 and f_high < 1):
        raise Error("A reducing fraction must lie between 0 and 1")
    if len(candidates) == 0:
        raise Error("A map needs a candidate")
    var e1 = _single_element(oxygen_gas)
    var names = List[String]()
    for c in candidates:  # pragma: no branch
        names.append(c.name)
    var out = LabelMap(
        names^, low.kelvin, high.kelvin, f_low, f_high, columns, rows
    )
    for column in range(columns):  # pragma: no branch
        var t = Temperature64(out.x(column))
        var rt = GAS_CONSTANT.value * t.kelvin
        var g_couple = ellingham(couple, t).value / rt
        var g_o2 = oxygen_gas.gibbs(t).value / rt
        var per_base = List[Float64]()
        var share1 = List[Float64]()
        var zero = List[Float64]()
        var g = List[Float64]()
        for c in candidates:  # pragma: no branch
            ref f = c.phases[0].formula
            var n = f.count_of(base)
            var a = f.count_of(e1[0])
            if n == 0:
                raise Error(String("Candidate '", c.name, "' lacks the base"))
            if n + a != _atoms(c):
                raise Error(
                    String("Candidate '", c.name, "' holds another element")
                )
            per_base.append(Float64(n))
            share1.append(Float64(a) / Float64(e1[1]))
            zero.append(0)
            g.append(c.gibbs(t).value / rt)
        for row in range(rows):  # pragma: no branch
            var x = out.y(row)
            # (p_CO2 / p_CO)^2 / p_O2 = exp(-dG / RT), so:
            var log_o2 = g_couple + 2 * log((1 - x) / x)
            out.labels[row * columns + column] = _lowest(
                g, share1, zero, per_base, g_o2 + log_o2, 0
            )
    return out^
