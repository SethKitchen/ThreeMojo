# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Flowsheets: steps joined by streams, with recycle.

A `Flowsheet` has components, the substances its streams carry, and
streams, each an amount of every component. A stream is a feed, which the
caller sets, or the outlet of one unit. Units run in the order they were
added:

- A mixer adds its inlets.
- A reactor runs a reaction to a share of its limiting reactant.
- A splitter sends a share of each component to its first outlet and the
  rest to its second.

A recycle makes a loop. `set_guess` gives a stream a starting value, and
`solve` runs the units again and again until every stream stops changing:
successive substitution on the loop's tear streams. `net` is the element
balance of the whole sheet: what the feeds bring in less what leaves in
streams that no unit takes. At steady state it is zero.

The amounts are per any basis the caller chooses: per second, per hour or
per batch.
"""

from std.math import isfinite
from core.ordinal import ordinal_label, ordinal_valid, require_valid
from extensions.chemistry.elements import Element
from extensions.chemistry.quantities import Amount64
from extensions.chemistry.reaction import Reaction
from extensions.chemistry.thermo import Substance

# Passes allowed for a recycle to settle, by default.
comptime MAX_PASSES = 1000
# A settled stream changes each amount by less than this share of the
# largest amount in the sheet.
comptime TOLERANCE = 1e-12


@fieldwise_init
struct StreamId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a stream in a `Flowsheet`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a stream.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct UnitKind(Equatable, ImplicitlyCopyable, Writable):
    """What a unit of a flowsheet does."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)

    def name(self) -> String:
        """Return the kind's name.

        Returns:
            The name, or "?" if not valid.
        """
        var names: List[String] = ["mixer", "reactor", "splitter"]
        return ordinal_label(self.is_valid(), self.value, names, "?")


# Adds its inlets into one outlet.
comptime MIXER = UnitKind(0)
# Runs a reaction to a share of its limiting reactant.
comptime REACTOR = UnitKind(1)
# Sends a share of each component to its first outlet, the rest to its
# second.
comptime SPLITTER = UnitKind(2)


struct Unit(Copyable, Movable):
    """One unit of a flowsheet."""

    var name: String
    var kind: UnitKind
    var inlets: List[StreamId]
    var outlets: List[StreamId]
    # A reactor's coefficient for each component, zero if absent.
    var coefficients: List[Float64]
    # A reactor's share of its limiting reactant converted.
    var conversion: Float64
    # A splitter's share of each component to its first outlet.
    var fractions: List[Float64]

    def __init__(
        out self,
        name: String,
        kind: UnitKind,
        var inlets: List[StreamId],
        var outlets: List[StreamId],
        var coefficients: List[Float64],
        conversion: Float64,
        var fractions: List[Float64],
    ) raises:
        """Make a unit. The flowsheet's methods are shorter to call.

        Args:
            name: The unit's name.
            kind: `MIXER`, `REACTOR` or `SPLITTER`.
            inlets: The streams it takes.
            outlets: The streams it makes.
            coefficients: A reactor's coefficient per component.
            conversion: A reactor's conversion.
            fractions: A splitter's shares.

        Raises:
            Error: If the kind is not valid.
        """
        require_valid(kind.is_valid(), "A unit kind is not valid")
        self.name = name
        self.kind = kind
        self.inlets = inlets^
        self.outlets = outlets^
        self.coefficients = coefficients^
        self.conversion = conversion
        self.fractions = fractions^


struct Flowsheet(Copyable, Movable):
    """Units joined by streams of components."""

    var components: List[Substance]
    var stream_names: List[String]
    # The amount of each component in each stream.
    var flows: List[List[Float64]]
    var feeds: List[Bool]
    # The unit that makes each stream, or -1.
    var made_by: List[Int]
    # Whether some unit takes each stream.
    var taken: List[Bool]
    var units: List[Unit]

    def __init__(out self, var components: List[Substance]) raises:
        """Make an empty flowsheet over its components.

        Args:
            components: The substances the streams carry, each name once.

        Raises:
            Error: If there is no component or two share a name.
        """
        if len(components) == 0:
            raise Error("A flowsheet needs a component")
        for i in range(len(components)):  # pragma: no branch
            for j in range(i):
                if components[j].name == components[i].name:
                    raise Error("Two components share a name")
        self.components = components^
        self.stream_names = List[String]()
        self.flows = List[List[Float64]]()
        self.feeds = List[Bool]()
        self.made_by = List[Int]()
        self.taken = List[Bool]()
        self.units = List[Unit]()

    def _zeros(self) -> List[Float64]:
        """Return a stream of nothing."""
        var out = List[Float64]()
        for _ in range(len(self.components)):  # pragma: no branch
            out.append(0)
        return out^

    def _index(self, name: String) raises -> Int:
        """Return a component's index by name."""
        # A flowsheet has a component.
        for i in range(len(self.components)):  # pragma: no branch
            if self.components[i].name == name:
                return i
        raise Error(String("No component is named '", name, "'"))

    def _check(self, id: StreamId) raises:
        """Refuse a stream id that is not in range."""
        if not (id.is_valid() and id.value < len(self.flows)):
            raise Error("A stream id is out of range")

    def add_stream(mut self, name: String) -> StreamId:
        """Add an empty stream.

        Args:
            name: The stream's name.

        Returns:
            Its id.
        """
        self.stream_names.append(name)
        self.flows.append(self._zeros())
        self.feeds.append(False)
        self.made_by.append(-1)
        self.taken.append(False)
        return StreamId(len(self.flows) - 1)

    def _set(
        mut self, id: StreamId, names: List[String], amounts: List[Amount64]
    ) raises:
        """Set a stream's amounts by component name."""
        self._check(id)
        if len(names) != len(amounts):
            raise Error("Give one amount per component name")
        var flow = self._zeros()
        for i in range(len(names)):
            var a = amounts[i].value
            if not (isfinite(a) and a >= 0):
                raise Error("An amount must be finite and not negative")
            flow[self._index(names[i])] += a
        self.flows[id.value] = flow^

    def set_feed(
        mut self, id: StreamId, names: List[String], amounts: List[Amount64]
    ) raises:
        """Make a stream a feed with fixed amounts.

        Args:
            id: The stream.
            names: Component names.
            amounts: The amount of each, zero or more.

        Raises:
            Error: If the id is out of range, a unit makes the stream, a
                name is not a component, the lists differ in length, or an
                amount is negative.
        """
        self._check(id)
        if self.made_by[id.value] >= 0:
            raise Error("A unit's outlet cannot be a feed")
        self._set(id, names, amounts)
        self.feeds[id.value] = True

    def set_guess(
        mut self, id: StreamId, names: List[String], amounts: List[Amount64]
    ) raises:
        """Give a recycle stream a starting value.

        Args:
            id: The stream.
            names: Component names.
            amounts: The amount of each, zero or more.

        Raises:
            Error: As for `set_feed`, except that a unit makes the stream.
        """
        self._set(id, names, amounts)

    def _outlet(mut self, id: StreamId, unit: Int) raises:
        """Mark a stream as a unit's outlet."""
        self._check(id)
        if self.feeds[id.value] or self.made_by[id.value] >= 0:
            raise Error("A stream has one source: a feed or one unit")
        self.made_by[id.value] = unit

    def _inlet(mut self, id: StreamId) raises:
        """Mark a stream as taken by a unit."""
        self._check(id)
        if self.taken[id.value]:
            raise Error("A stream goes to one unit")
        self.taken[id.value] = True

    def mixer(
        mut self, name: String, var inlets: List[StreamId], outlet: StreamId
    ) raises:
        """Add a mixer.

        Args:
            name: The unit's name.
            inlets: The streams to add, at least one.
            outlet: The stream it makes.

        Raises:
            Error: If there is no inlet, or a stream is out of range,
                already taken, or already made.
        """
        if len(inlets) == 0:
            raise Error("A mixer needs an inlet")
        var unit = len(self.units)
        for s in inlets:  # pragma: no branch
            self._inlet(s)
        self._outlet(outlet, unit)
        self.units.append(
            Unit(
                name,
                MIXER,
                inlets^,
                [outlet],
                List[Float64](),
                0,
                List[Float64](),
            )
        )

    def reactor(
        mut self,
        name: String,
        inlet: StreamId,
        outlet: StreamId,
        reaction: Reaction,
        conversion: Float64,
    ) raises:
        """Add a reactor.

        Args:
            name: The unit's name.
            inlet: The stream it takes.
            outlet: The stream it makes.
            reaction: The reaction, over the sheet's components by name.
            conversion: The share of the limiting reactant converted,
                from 0 to 1.

        Raises:
            Error: If the conversion is out of range, a substance of the
                reaction is not a component, or a stream is not valid.
        """
        if not (conversion >= 0 and conversion <= 1):
            raise Error("A conversion must lie from 0 to 1")
        var coefficients = self._zeros()
        for term in reaction.terms:  # pragma: no branch
            coefficients[self._index(term.substance.name)] += term.coefficient
        var unit = len(self.units)
        self._inlet(inlet)
        self._outlet(outlet, unit)
        self.units.append(
            Unit(
                name,
                REACTOR,
                [inlet],
                [outlet],
                coefficients^,
                conversion,
                List[Float64](),
            )
        )

    def splitter(
        mut self,
        name: String,
        inlet: StreamId,
        first: StreamId,
        second: StreamId,
        names: List[String],
        shares: List[Float64],
    ) raises:
        """Add a splitter.

        Args:
            name: The unit's name.
            inlet: The stream it takes.
            first: The outlet that gets the named shares.
            second: The outlet that gets the rest.
            names: Components with a share other than zero.
            shares: The share of each to the first outlet, 0 to 1.

        Raises:
            Error: If a share is out of range, a name is not a component,
                the lists differ, or a stream is not valid.
        """
        if len(names) != len(shares):
            raise Error("Give one share per component name")
        var fractions = self._zeros()
        for i in range(len(names)):
            if not (shares[i] >= 0 and shares[i] <= 1):
                raise Error("A share must lie from 0 to 1")
            fractions[self._index(names[i])] = shares[i]
        var unit = len(self.units)
        self._inlet(inlet)
        self._outlet(first, unit)
        self._outlet(second, unit)
        self.units.append(
            Unit(
                name,
                SPLITTER,
                [inlet],
                [first, second],
                List[Float64](),
                0,
                fractions^,
            )
        )

    def _run(mut self, u: Int):
        """Run one unit: set its outlets from its inlets."""
        ref unit = self.units[u]
        var n = len(self.components)
        if unit.kind == MIXER:
            var out = self._zeros()
            for s in unit.inlets:  # pragma: no branch
                for i in range(n):  # pragma: no branch
                    out[i] += self.flows[s.value][i]
            self.flows[unit.outlets[0].value] = out^
        elif unit.kind == REACTOR:
            var feed = self.flows[unit.inlets[0].value].copy()
            var extent = Float64(-1)
            for i in range(n):  # pragma: no branch
                var c = unit.coefficients[i]
                if c < 0:
                    var most = feed[i] / -c
                    if extent < 0 or most < extent:
                        extent = most
            extent = max(extent, 0.0) * unit.conversion
            for i in range(n):  # pragma: no branch
                # Round-off can leave a limiting reactant a hair below zero.
                feed[i] = max(feed[i] + unit.coefficients[i] * extent, 0.0)
            self.flows[unit.outlets[0].value] = feed^
        else:
            var feed = self.flows[unit.inlets[0].value].copy()
            var first = self._zeros()
            var second = self._zeros()
            for i in range(n):  # pragma: no branch
                first[i] = feed[i] * unit.fractions[i]
                second[i] = feed[i] - first[i]
            self.flows[unit.outlets[0].value] = first^
            self.flows[unit.outlets[1].value] = second^

    def solve(
        mut self, max_passes: Int = MAX_PASSES, tolerance: Float64 = TOLERANCE
    ) raises -> Int:
        """Run the units until every stream settles.

        Args:
            max_passes: The passes allowed.
            tolerance: The change that counts as settled, as a share of
                the largest amount in the sheet.

        Returns:
            The passes taken.

        Raises:
            Error: If the sheet has no unit, or the streams do not settle
                in the passes allowed.
        """
        if len(self.units) == 0:
            raise Error("A flowsheet needs a unit")
        for p in range(max_passes):
            var before = self.flows.copy()
            for u in range(len(self.units)):  # pragma: no branch
                self._run(u)
            var largest = Float64(0)
            var change = Float64(0)
            for s in range(len(self.flows)):  # pragma: no branch
                for i in range(len(self.components)):  # pragma: no branch
                    var now = self.flows[s][i]
                    largest = max(largest, abs(now))
                    change = max(change, abs(now - before[s][i]))
            if change <= tolerance * max(largest, 1.0):
                return p + 1
        raise Error("The flowsheet did not settle")

    def amount(self, id: StreamId, name: String) raises -> Amount64:
        """Return the amount of a component in a stream.

        Args:
            id: The stream.
            name: The component's name.

        Returns:
            Its amount.

        Raises:
            Error: If the id is out of range or no component has the name.
        """
        self._check(id)
        return Amount64(self.flows[id.value][self._index(name)])

    def net(self, element: Element) -> Float64:
        """Return the moles of an element that enter less those that leave.

        Args:
            element: The element.

        Returns:
            What the feeds bring less what the streams no unit takes carry
            away. Zero at steady state.
        """
        var total = Float64(0)
        for s in range(len(self.flows)):
            var sign = Float64(0)
            if self.feeds[s]:
                sign = 1
            elif not self.taken[s]:
                sign = -1
            for i in range(len(self.components)):  # pragma: no branch
                var atoms = (
                    self.components[i].phases[0].formula.count_of(element)
                )
                total += sign * Float64(atoms) * self.flows[s][i]
        return total
