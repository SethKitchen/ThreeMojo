# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Route search: sequences of reactions from feeds to a product.

`find_routes` searches a library of reactions breadth first. A state is
the set of substances on hand, by name. A reaction can run when every
reactant is on hand and it has a thermodynamic window: some temperature
in the range where it proceeds at the pressure. Its products join the
substances on hand. A route ends when the target is on hand.

The routes come shortest first, each reaction used once. A route that
holds every step of a shorter route is left out, as one of its steps does
nothing. A route is a
candidate, not a process: the search knows only the driving force of
each step. Rates, purity, separations and equipment come from the steps
of `extensions.chemistry.step`, built for each candidate.
"""

from extensions.chemistry.kinds import THERMODYNAMIC
from extensions.chemistry.reaction import Reaction
from extensions.chemistry.requirement import Requirement, proceeds
from extensions.chemistry.window import met_intervals
from units.si import Pressure64
from units.temperature import Temperature64

# The most routes a search returns, by default.
comptime MAX_ROUTES = 100


def _usable(
    library: List[Reaction],
    low: Temperature64,
    high: Temperature64,
    pressure: Pressure64,
) raises -> List[Bool]:
    """Return whether each reaction has a window in the range."""
    var out = List[Bool]()
    for r in library:
        var need = proceeds(THERMODYNAMIC, r.copy(), "proceeds")
        out.append(len(met_intervals(need, low, high, pressure)) > 0)
    return out^


def _contains_route(found: List[List[Int]], steps: List[Int]) -> Bool:
    """Return True if a found route uses only steps of this one."""
    for route in found:
        var inside = True
        # A route found in the search has a step.
        for r in route:  # pragma: no branch
            if not (r in steps):
                inside = False
        if inside:
            return True
    return False


def _holds(names: List[String], name: String) -> Bool:
    """Return True if a list holds a name."""
    for n in names:
        if n == name:
            return True
    return False


struct _Path(Copyable, Movable):
    """A partial route: the reactions used and the substances on hand."""

    var steps: List[Int]
    var on_hand: List[String]

    def __init__(out self, var steps: List[Int], var on_hand: List[String]):
        """Make a path."""
        self.steps = steps^
        self.on_hand = on_hand^


def find_routes(
    library: List[Reaction],
    feeds: List[String],
    target: String,
    low: Temperature64,
    high: Temperature64,
    pressure: Pressure64,
    max_steps: Int,
    max_routes: Int = MAX_ROUTES,
) raises -> List[List[Int]]:
    """Return the routes from feeds to a target, shortest first.

    Args:
        library: The reactions that can be used.
        feeds: The names of the substances on hand at the start.
        target: The name of the substance wanted.
        low: The low end of the temperature range for every step.
        high: The high end.
        pressure: The pressure of every step.
        max_steps: The most reactions in a route, 1 to 8.
        max_routes: The most routes to return.

    Returns:
        Each route as indices into the library, in order.

    Raises:
        Error: If the step limit is out of range, or a window cannot be
            found.
    """
    if not (max_steps >= 1 and max_steps <= 8):
        raise Error("A route takes 1 to 8 steps")
    var usable = _usable(library, low, high, pressure)
    var out = List[List[Int]]()
    if _holds(feeds, target):
        out.append(List[Int]())
        return out^
    var frontier = List[_Path]()
    frontier.append(_Path(List[Int](), feeds.copy()))
    for _ in range(max_steps):  # pragma: no branch
        var next = List[_Path]()
        for path in frontier:
            for r in range(len(library)):
                if not usable[r] or r in path.steps:
                    continue
                var ready = True
                var adds_one = False
                for term in library[r].terms:  # pragma: no branch
                    var name = term.substance.name
                    var have = _holds(path.on_hand, name)
                    if term.coefficient < 0 and not have:
                        ready = False
                    elif term.coefficient > 0 and not have:
                        adds_one = True
                if not (ready and adds_one):
                    continue
                var steps = path.steps.copy()
                steps.append(r)
                var on_hand = path.on_hand.copy()
                for term in library[r].terms:  # pragma: no branch
                    var name = term.substance.name
                    if term.coefficient > 0 and not _holds(on_hand, name):
                        on_hand.append(name)
                if _holds(on_hand, target):
                    # A route that holds a shorter route has a useless step.
                    var minimal = not _contains_route(out, steps)
                    if minimal and len(out) < max_routes:
                        out.append(steps^)
                else:
                    next.append(_Path(steps^, on_hand^))
        frontier = next^
    return out^
