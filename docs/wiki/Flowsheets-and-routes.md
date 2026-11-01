# Flowsheets and routes

A process is many steps joined by streams, and some streams return to an earlier step. `extensions/chemistry/flowsheet.mojo` solves the steady state of such a loop. `routes.mojo` searches a library of reactions for the sequences that make a product from what is on hand.

This page is a reference. For the rest of the library, see [Process chemistry](Process-chemistry).

![The Kroll loop: chlorinator, condenser, reducer, tapping and electrolysis, with the magnesium and chlorine recycles and their flows](out/kroll-loop.png)

## Build a flowsheet

A `Flowsheet` has components, the substances its streams carry. `add_stream(name)` returns a `StreamId`. A stream is a feed, which the caller sets, or the outlet of one unit.

| Method | Unit |
|---|---|
| `set_feed(id, names, amounts)` | Sets a feed stream |
| `mixer(name, inlets, outlet)` | Adds its inlets |
| `reactor(name, inlet, outlet, reaction, conversion)` | Runs a reaction to a share of its limiting reactant |
| `splitter(name, inlet, first, second, names, shares)` | Sends a share of each named component to the first outlet, and the rest to the second |

The units run in the order they were added. A stream has one source, a feed or one unit, and it goes to one unit at most.

## Solve a loop

A recycle makes a loop. `set_guess(id, names, amounts)` gives a stream in the loop a starting value. `solve()` then runs the units again and again until every stream stops changing. This is successive substitution on the loop's tear streams. It returns the passes taken, and it raises an error if the streams do not settle.

`amount(id, name)` reads a component of a stream. `net(element)` is the element balance of the whole sheet: what the feeds bring in, less what leaves in streams that no unit takes. At steady state, it is zero.

The amounts are on any basis the caller chooses: per second, per hour or per batch.

## The Kroll loop

`processes.titanium.kroll_loop()` returns the Kroll route as a flowsheet:

1. The chlorinator turns rutile, coke and chlorine into TiCl4 gas and CO2.
2. The condenser takes the TiCl4. The rest leaves as off-gas.
3. Magnesium reduces the TiCl4 to titanium sponge and MgCl2.
4. An electrolysis cell splits the MgCl2. Its magnesium returns to the reducer, and its chlorine returns to the chlorinator.

The feeds are one mole of rutile and of carbon, and 0.1 mole of make-up chlorine. The loop settles in 22 passes to one mole of titanium, with two moles each of magnesium and chlorine in the recycles. `examples/kroll_loop.mojo` draws the figure above from the solved sheet.

## Search for routes

`find_routes(library, feeds, target, low, high, pressure, max_steps)` searches a list of reactions breadth first. A state is the set of substances on hand, by name. A reaction can run when every reactant is on hand and it has a window: a temperature in the range where it proceeds. Its products join the substances on hand.

Each route is a list of indices into the library, shortest first, each reaction used once. A route that holds every step of a shorter route is left out, because one of its steps does nothing. `max_routes` limits the count, 100 by default.

From rutile, chlorine, coke and magnesium, the search finds the Kroll route and the magnesiothermic reduction of rutile. It does not find carbothermic reduction, because that has no window below 1500 K.

A route is a candidate, not a process. The search knows only the driving force of each step. Build a `Step` for each candidate to check its rates, phases and equipment.

## Limits

The units have no energy balance. Use `heat_duty` from `balance` for each unit. A reactor runs to a fixed conversion, not to equilibrium. Use [Chemical equilibrium](Chemical-equilibrium) to find a conversion. Successive substitution converges slowly where a loop's recycle is much larger than its feed.
