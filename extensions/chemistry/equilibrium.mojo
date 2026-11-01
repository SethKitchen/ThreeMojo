# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Chemical equilibrium at a temperature and a pressure.

`equilibrate` finds the amounts of a set of candidate substances that
minimize the Gibbs energy of a charge, with every element conserved. The
gases form one ideal mixture. Each condensed substance is a pure phase.

The method is the one of NASA CEA (Gordon and McBride, NASA RP-1311,
1994). A Newton iteration solves for the element potentials, the change
in the total gas and the change in each condensed amount. The gas amounts
follow from the potentials. The step is damped as CEA damps it, so that a
trace species cannot jump by many orders at once.

Condensed phases enter and leave. After each solution, a condensed phase
with a negative amount leaves, and the absent condensed phase with the
most negative driving force enters. The search repeats until no phase
changes. A condensed substance whose data does not reach the temperature
is left out. A candidate that holds an element the charge does not hold is
left out too.

    var result = equilibrate(
        [graphite(), carbon_monoxide(), carbon_dioxide(), oxygen()],
        [Charge(graphite(), Amount64(2, MOLE)),
         Charge(carbon_dioxide(), Amount64(1, MOLE))],
        Temperature64(1000), Pressure64(1e5),
    )
    result.mole_fraction("CO(g)")   # about 0.69

`EquilibriumShare` is a `Constraint`: it holds where the share of an
element that ends in a product reaches a minimum.
"""

from std.math import exp, isfinite, log
from extensions.chemistry.elements import Element
from extensions.chemistry.quantities import (
    Amount64,
    GAS_CONSTANT,
    STANDARD_PRESSURE,
)
from extensions.chemistry.requirement import Constraint
from extensions.chemistry.thermo import Substance
from extensions.numerics.dense import DenseMatrix, solve
from loaders.js_number import js_to_fixed
from units.si import Pressure64
from units.temperature import Temperature64

# The Newton steps allowed for one set of phases, by default.
comptime MAX_ITERATIONS = 500
# The phase changes allowed in one equilibrium, by default.
comptime MAX_PHASE_CHANGES = 50
# A converged step changes each amount by less than this share of the total.
comptime _TOLERANCE = 1e-8
# A converged state balances each element to this share of its target.
comptime _BALANCE = 1e-9
# CEA's limits on the log mole fraction of a trace species.
comptime _TRACE = -18.420681
comptime _TRACE_TARGET = -9.2103404
# A driving force below this, per RT, lets a condensed phase enter.
comptime _ENTER = -1e-9


struct Charge(Copyable, Movable):
    """An amount of a substance put into an equilibrium."""

    var substance: Substance
    var amount: Amount64

    def __init__(out self, var substance: Substance, amount: Amount64):
        """Make a charge. `equilibrate` checks it.

        Args:
            substance: The substance.
            amount: How many moles.
        """
        self.substance = substance^
        self.amount = amount


struct Equilibrium(Copyable, Movable):
    """The amounts at equilibrium, one per candidate that took part."""

    # The candidates that took part, in the order given.
    var substances: List[Substance]
    # Moles of each, zero for an absent condensed phase.
    var amounts: List[Float64]
    var temperature: Temperature64
    var pressure: Pressure64
    # Newton steps over every set of phases.
    var iterations: Int

    def __init__(
        out self,
        var substances: List[Substance],
        var amounts: List[Float64],
        temperature: Temperature64,
        pressure: Pressure64,
        iterations: Int,
    ):
        """Make a result. `equilibrate` makes it.

        Args:
            substances: The candidates that took part.
            amounts: Moles of each.
            temperature: The temperature.
            pressure: The pressure.
            iterations: The Newton steps taken.
        """
        self.substances = substances^
        self.amounts = amounts^
        self.temperature = temperature
        self.pressure = pressure
        self.iterations = iterations

    def _index(self, name: String) raises -> Int:
        """Return the index of a substance by name."""
        for i in range(len(self.substances)):
            if self.substances[i].name == name:
                return i
        raise Error(String("No substance named '", name, "' took part"))

    def amount_of(self, name: String) raises -> Amount64:
        """Return the amount of a substance at equilibrium.

        Args:
            name: The substance's name.

        Returns:
            Its moles. An absent condensed phase has none.

        Raises:
            Error: If no substance of that name took part.
        """
        return Amount64(self.amounts[self._index(name)])

    def gas_amount(self) -> Amount64:
        """Return the moles of gas.

        Returns:
            The sum over the gases.
        """
        var total = Float64(0)
        for i in range(len(self.substances)):
            if self.substances[i].is_gas():
                total += self.amounts[i]
        return Amount64(total)

    def mole_fraction(self, name: String) raises -> Float64:
        """Return a gas's mole fraction of the gas.

        Args:
            name: The gas's name.

        Returns:
            Its share of the moles of gas.

        Raises:
            Error: If no substance of that name took part, or it is not a
                gas.
        """
        var i = self._index(name)
        if not self.substances[i].is_gas():
            raise Error("A mole fraction is of a gas")
        return self.amounts[i] / self.gas_amount().value

    def share(self, element: Element, name: String) raises -> Float64:
        """Return the share of an element's atoms held by one substance.

        Args:
            element: The element.
            name: The substance's name.

        Returns:
            From zero to one.

        Raises:
            Error: If no substance of that name took part, or no
                substance holds the element.
        """
        var total = Float64(0)
        for i in range(len(self.substances)):
            var n = self.substances[i].phases[0].formula.count_of(element)
            total += Float64(n) * self.amounts[i]
        if total <= 0:
            raise Error("No substance at equilibrium holds the element")
        var j = self._index(name)
        var mine = self.substances[j].phases[0].formula.count_of(element)
        return Float64(mine) * self.amounts[j] / total


struct _System(Movable):
    """The working state of one equilibrium."""

    var substances: List[Substance]
    var gas: List[Bool]
    # Atoms of element i in candidate j, at [j * elements + i].
    var atoms: List[Float64]
    var elements: Int
    # The target moles of each element.
    var target: List[Float64]
    # The standard chemical potential of each candidate, per RT.
    var g: List[Float64]
    # Log moles of each gas; moles of each condensed phase.
    var log_n: List[Float64]
    var n: List[Float64]
    var active: List[Bool]
    # Log of the total moles of gas, as CEA carries it.
    var log_total: Float64
    # The element potentials of the last solution, per RT.
    var potentials: List[Float64]
    # Every element of the charge, before the dependent ones are dropped:
    # the atoms at [j * all_elements + i], and the targets.
    var all_atoms: List[Float64]
    var all_elements: Int
    var all_target: List[Float64]

    def __init__(out self):
        """Make an empty system."""
        self.substances = List[Substance]()
        self.gas = List[Bool]()
        self.atoms = List[Float64]()
        self.elements = 0
        self.target = List[Float64]()
        self.g = List[Float64]()
        self.log_n = List[Float64]()
        self.n = List[Float64]()
        self.active = List[Bool]()
        self.log_total = log(0.1)
        self.potentials = List[Float64]()
        self.all_atoms = List[Float64]()
        self.all_elements = 0
        self.all_target = List[Float64]()

    def a(self, species: Int, element: Int) -> Float64:
        """Return the atoms of an element in a candidate."""
        return self.atoms[species * self.elements + element]

    def moles(self, j: Int) -> Float64:
        """Return the moles of a candidate."""
        if self.gas[j]:
            return exp(self.log_n[j])
        return self.n[j]

    def mu(self, j: Int) -> Float64:
        """Return a candidate's chemical potential per RT."""
        if self.gas[j]:
            return self.g[j] + self.log_n[j] - self.log_total
        return self.g[j]

    def driving_force(self, j: Int) -> Float64:
        """Return a condensed phase's potential less its atoms' potentials."""
        var d = self.g[j]
        for i in range(self.elements):  # pragma: no branch
            d -= self.a(j, i) * self.potentials[i]
        return d


def _holds(elements: List[Element], element: Element) -> Bool:
    """Return True if a list holds an element."""
    for e in elements:
        if e == element:
            return True
    return False


def _elements_of(feed: List[Charge]) raises -> List[Element]:
    """Return the elements of a charge, in order of appearance."""
    var out = List[Element]()
    for c in feed:  # pragma: no branch
        if not (isfinite(c.amount.value) and c.amount.value >= 0):
            raise Error("A charge must be finite and not negative")
        # A substance has a formula, which has an element.
        for e in c.substance.phases[0].formula.counts:  # pragma: no branch
            if not _holds(out, e.element):
                out.append(e.element)
    return out^


def _build(
    candidates: List[Substance],
    feed: List[Charge],
    temperature: Temperature64,
    pressure: Pressure64,
) raises -> _System:
    """Set up the candidates, the targets and the standard potentials."""
    if len(feed) == 0:
        raise Error("An equilibrium needs a charge")
    var elements = _elements_of(feed)
    var m = len(elements)
    var system = _System()
    system.elements = m
    for _ in range(m):  # pragma: no branch
        system.target.append(0)
        system.potentials.append(0)
    for c in feed:  # pragma: no branch
        ref counts = c.substance.phases[0].formula.counts
        for e in counts:  # pragma: no branch
            for i in range(m):  # pragma: no branch
                if elements[i] == e.element:
                    system.target[i] += Float64(e.count) * c.amount.value
    var rt = GAS_CONSTANT.value * temperature.kelvin
    var log_p = log(pressure.value / STANDARD_PRESSURE.value)
    var gases = 0
    for s in candidates:
        for k in range(len(system.substances)):
            if system.substances[k].name == s.name:
                raise Error(String("Two candidates are named '", s.name, "'"))
        ref counts = s.phases[0].formula.counts
        var foreign = False
        # A formula has an element.
        for e in counts:  # pragma: no branch
            if not _holds(elements, e.element):
                foreign = True
        if foreign:
            continue
        if s.is_gas():
            if not s.covers(temperature):
                raise Error(
                    String("The data of gas '", s.name, "' does not reach")
                    + " the temperature"
                )
            gases += 1
        elif not s.covers(temperature):
            continue
        system.substances.append(s.copy())
        system.gas.append(s.is_gas())
        for i in range(m):  # pragma: no branch
            system.atoms.append(
                Float64(s.phases[0].formula.count_of(elements[i]))
            )
        var g = s.gibbs(temperature).value / rt
        if s.is_gas():
            g += log_p
        else:
            var v = s.molar_volume_at(temperature).value
            g += v * (pressure.value - STANDARD_PRESSURE.value) / rt
        system.g.append(g)
        system.log_n.append(0)
        system.n.append(0)
        system.active.append(s.is_gas())
    if gases == 0:
        raise Error("An equilibrium needs a gas candidate")
    for i in range(m):  # pragma: no branch
        var carried = False
        for j in range(len(system.substances)):  # pragma: no branch
            if system.a(j, i) > 0:
                carried = True
        if not carried:
            raise Error(
                String("No candidate holds ", elements[i].symbol())
                + " at this temperature"
            )
    _drop_dependent(system)
    m = system.elements
    var start = log(0.1 / Float64(gases))
    for j in range(len(system.substances)):  # pragma: no branch
        if system.gas[j]:
            system.log_n[j] = start
    # An element that no gas carries starts in its cheapest condensed phase.
    for i in range(m):  # pragma: no branch
        var by_gas = False
        var best = -1
        var best_g = Float64(0)
        for j in range(len(system.substances)):  # pragma: no branch
            var atoms = system.a(j, i)
            if atoms > 0 and system.gas[j]:
                by_gas = True
            elif atoms > 0:
                var per_atom = system.g[j] / atoms
                if best < 0 or per_atom < best_g:
                    best = j
                    best_g = per_atom
        if not by_gas:
            system.active[best] = True
    return system^


def _drop_dependent(mut system: _System):
    """Keep only elements whose balances are independent over the candidates.

    When every candidate's atoms lie in fewer directions than there are
    elements, as CaO, CaCO3 and CO2 do in Ca, C and O, some balances are
    sums of others and the element potentials are not unique. Gaussian
    elimination over the candidates finds the independent elements.
    """
    var count = len(system.substances)
    var m = system.elements
    system.all_atoms = system.atoms.copy()
    system.all_elements = m
    system.all_target = system.target.copy()
    var work = system.atoms.copy()
    var used = List[Bool]()
    for _ in range(count):  # pragma: no branch
        used.append(False)
    var keep = List[Int]()
    for i in range(m):  # pragma: no branch
        var pivot = -1
        var size = Float64(1e-9)
        for j in range(count):  # pragma: no branch
            var value = abs(work[j * m + i])
            if not used[j] and value > size:
                pivot = j
                size = value
        if pivot < 0:
            continue
        used[pivot] = True
        keep.append(i)
        for j in range(count):  # pragma: no branch
            if j != pivot:
                var factor = work[j * m + i] / work[pivot * m + i]
                for k in range(m):  # pragma: no branch
                    work[j * m + k] -= factor * work[pivot * m + k]
    var atoms = List[Float64]()
    for j in range(count):  # pragma: no branch
        for i in keep:  # pragma: no branch
            atoms.append(system.all_atoms[j * m + i])
    var target = List[Float64]()
    for i in keep:  # pragma: no branch
        target.append(system.all_target[i])
    system.atoms = atoms^
    system.target = target^
    system.elements = len(keep)
    system.potentials = List[Float64]()
    for _ in range(len(keep)):  # pragma: no branch
        system.potentials.append(0)


def _balanced(system: _System) -> Bool:
    """Return True if every element of the charge balances."""
    var m = system.all_elements
    for i in range(m):  # pragma: no branch
        var held = Float64(0)
        for j in range(len(system.substances)):  # pragma: no branch
            held += system.all_atoms[j * m + i] * system.moles(j)
        var scale = max(Float64(1), abs(system.all_target[i]))
        if abs(held - system.all_target[i]) > 1e-6 * scale:
            return False
    return True


def _best_absent(system: _System) -> Int:
    """Return the absent condensed phase with the most negative force."""
    var best = -1
    var best_force = Float64(_ENTER)
    for j in range(len(system.substances)):  # pragma: no branch
        # A gas is always active.
        if not system.active[j]:
            var force = system.driving_force(j)
            if force < best_force:
                best = j
                best_force = force
    return best


def _converge(mut system: _System, max_iterations: Int) raises -> Int:
    """Run Newton steps on the active phases until they converge.

    Returns the steps taken, or -1 when the active phases cannot hold the
    charge and the matrix is singular.
    """
    var m = system.elements
    var count = len(system.substances)
    var small = False
    for iteration in range(max_iterations):
        var condensed = List[Int]()
        for j in range(count):  # pragma: no branch
            if system.active[j] and not system.gas[j]:
                condensed.append(j)
        var size = m + len(condensed) + 1
        var matrix = DenseMatrix(size, size)
        var rhs = List[Float64]()
        for _ in range(size):  # pragma: no branch
            rhs.append(0)
        var last = size - 1
        var total = exp(system.log_total)
        var gas_sum = Float64(0)
        var gas_mu = Float64(0)
        for j in range(count):  # pragma: no branch
            if system.gas[j]:
                var nj = system.moles(j)
                gas_sum += nj
                gas_mu += nj * system.mu(j)
        for i in range(m):  # pragma: no branch
            var held = Float64(0)
            var by_gas = Float64(0)
            var by_gas_mu = Float64(0)
            for j in range(count):  # pragma: no branch
                var aij = system.a(j, i)
                if system.gas[j]:
                    var nj = system.moles(j)
                    held += aij * nj
                    by_gas += aij * nj
                    by_gas_mu += aij * nj * system.mu(j)
                    for k in range(m):  # pragma: no branch
                        matrix.add(i, k, aij * system.a(j, k) * nj)
                elif system.active[j]:
                    held += aij * system.n[j]
            for c in range(len(condensed)):
                matrix.set(i, m + c, system.a(condensed[c], i))
            matrix.set(i, last, by_gas)
            matrix.set(last, i, by_gas)
            rhs[i] = system.target[i] - held + by_gas_mu
            var scale = max(Float64(1), abs(system.target[i]))
            if abs(system.target[i] - held) > _BALANCE * scale:
                small = False
        # The last step was small and every element balances.
        if small:
            return iteration
        for c in range(len(condensed)):
            var j = condensed[c]
            for k in range(m):  # pragma: no branch
                matrix.set(m + c, k, system.a(j, k))
            rhs[m + c] = system.mu(j)
        matrix.set(last, last, gas_sum - total)
        rhs[last] = total - gas_sum + gas_mu
        var x: List[Float64]
        try:
            x = solve(matrix, rhs)
        except:
            return -1
        var d_total = x[last]
        # CEA's damping: a step changes no major gas by more than e^2,
        # and brings no trace gas past a mole fraction of 1e-4.
        var largest = 5 * abs(d_total)
        var trace_limit = Float64(1)
        var steps = List[Float64]()
        for j in range(count):  # pragma: no branch
            var step = Float64(0)
            if system.gas[j]:
                step = d_total - system.mu(j)
                for k in range(m):  # pragma: no branch
                    step += system.a(j, k) * x[k]
                var share = system.log_n[j] - system.log_total
                if step > 0 and share > _TRACE:
                    largest = max(largest, step)
                elif step > 0:
                    var limit = abs((-share + _TRACE_TARGET) / (step - d_total))
                    trace_limit = min(trace_limit, limit)
            steps.append(step)
        var damping = min(Float64(1), trace_limit)
        if largest > 2:
            damping = min(damping, 2 / largest)
        var all_moles = gas_sum
        for c in range(len(condensed)):
            all_moles += max(system.n[condensed[c]], 0.0)
        var converged = abs(d_total) <= _TOLERANCE
        for j in range(count):  # pragma: no branch
            if system.gas[j]:
                var change = system.moles(j) * abs(steps[j])
                if change > _TOLERANCE * all_moles:
                    converged = False
                system.log_n[j] += damping * steps[j]
        for c in range(len(condensed)):
            var j = condensed[c]
            var change = x[m + c]
            if abs(change) > _TOLERANCE * all_moles:
                converged = False
            system.n[j] += damping * change
        system.log_total += damping * d_total
        system.potentials = List[Float64]()
        for k in range(m):  # pragma: no branch
            system.potentials.append(x[k])
        small = converged
    raise Error("The equilibrium did not converge")


def equilibrate(
    candidates: List[Substance],
    feed: List[Charge],
    temperature: Temperature64,
    pressure: Pressure64,
    max_iterations: Int = MAX_ITERATIONS,
    max_phase_changes: Int = MAX_PHASE_CHANGES,
) raises -> Equilibrium:
    """Return the equilibrium amounts of the candidates for a charge.

    Args:
        candidates: The substances that can form. Each name must be
            unique, and at least one must be a gas.
        feed: The charge. Its elements are conserved.
        temperature: The temperature.
        pressure: The total pressure.
        max_iterations: The Newton steps allowed for one set of phases.
        max_phase_changes: The times a condensed phase can enter or leave.

    Returns:
        The amount of each candidate that took part.

    Raises:
        Error: If the temperature or the pressure is not physical, the
            charge is empty or negative, two candidates share a name, no
            candidate is a gas, a gas's data does not reach the
            temperature, an element of the charge is in no candidate, or
            the iteration does not converge, or the phases change more
            often than allowed.
    """
    if not temperature.is_valid():
        raise Error("A temperature must be finite and above absolute zero")
    if not (isfinite(pressure.value) and pressure.value > 0):
        raise Error("A pressure must be finite and positive")
    var system = _build(candidates, feed, temperature, pressure)
    var count = len(system.substances)
    var iterations = 0
    for _ in range(max_phase_changes):
        var steps = _converge(system, max_iterations)
        if steps < 0:
            # The active phases cannot hold the charge. A condensed phase
            # with a negative force must enter.
            var needed = _best_absent(system)
            if needed < 0:
                raise Error("No set of these candidates can hold the charge")
            system.active[needed] = True
            continue
        iterations += steps
        var changed = False
        # A condensed phase with a negative amount leaves.
        for j in range(count):  # pragma: no branch
            var leaving = system.active[j] and not system.gas[j]
            if leaving and system.n[j] < 0:
                system.active[j] = False
                system.n[j] = 0
                changed = True
        if changed:
            continue
        # The absent condensed phase with the most negative force enters.
        var best = _best_absent(system)
        if best < 0:
            if not _balanced(system):
                raise Error(
                    "The candidates cannot hold the charge's elements"
                    + " in its proportions"
                )
            var amounts = List[Float64]()
            for j in range(count):  # pragma: no branch
                amounts.append(system.moles(j))
            return Equilibrium(
                system.substances.copy(),
                amounts^,
                temperature,
                pressure,
                iterations,
            )
        system.active[best] = True
    raise Error("The phases of the equilibrium did not settle")


struct EquilibriumShare(Constraint):
    """A constraint: enough of an element ends in a product."""

    var candidates: List[Substance]
    var feed: List[Charge]
    var element: Element
    var product: String
    # The least share, from zero to one.
    var minimum: Float64

    def __init__(
        out self,
        var candidates: List[Substance],
        var feed: List[Charge],
        element: Element,
        product: String,
        minimum: Float64,
    ) raises:
        """Make the constraint.

        Args:
            candidates: The substances that can form.
            feed: The charge.
            element: The element to follow.
            product: The name of the substance it must end in.
            minimum: The least share, above 0 and at most 1.

        Raises:
            Error: If the element is not valid or the minimum is out of
                range.
        """
        if not element.is_valid():
            raise Error("The element must be in the table")
        if not (minimum > 0 and minimum <= 1):
            raise Error("A share must be above 0 and at most 1")
        self.candidates = candidates^
        self.feed = feed^
        self.element = element
        self.product = product
        self.minimum = minimum

    def holds(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> Bool:
        """Return True if the product holds the minimum share.

        Args:
            temperature: The temperature.
            pressure: The total pressure.

        Returns:
            Whether the equilibrium share reaches the minimum.

        Raises:
            Error: If the equilibrium cannot be found.
        """
        var result = equilibrate(
            self.candidates, self.feed, temperature, pressure
        )
        return result.share(self.element, self.product) >= self.minimum

    def describe(
        self, temperature: Temperature64, pressure: Pressure64
    ) raises -> String:
        """Return the share at a condition, for a report.

        Args:
            temperature: The temperature.
            pressure: The total pressure.

        Returns:
            Text such as "Ti in TiCl4(g): 0.9990 of 0.9900 needed".

        Raises:
            Error: If the equilibrium cannot be found.
        """
        var result = equilibrate(
            self.candidates, self.feed, temperature, pressure
        )
        var s = result.share(self.element, self.product)
        return String(
            self.element.symbol(),
            " in ",
            self.product,
            ": ",
            js_to_fixed(s, 4),
            " of ",
            js_to_fixed(self.minimum, 4),
            " needed",
        )
