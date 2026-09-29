# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Stable frame ordering, separate from scene collection and pass execution.

The renderer re-exports RenderItem and RenderSort for API compatibility.
Each run keeps its source, order, and depth together through every sort.
"""

from core.geometry_store import GeometryId
from core.object3d import NodeId
from materials.material import MaterialId
from math.sort_utils import stable_sort
from render.rasterizer import Draw, DrawKind


@fieldwise_init
struct _Source(ImplicitlyCopyable):
    """The object a run of primitives came from: its node, its geometry
    and the material it was drawn with."""

    var node: NodeId
    var geometry: GeometryId
    var material: MaterialId


@fieldwise_init
struct RenderItem(ImplicitlyCopyable):
    """One run of a prepared frame, what three.js's render list holds for
    one object: what a render hook is told, and what a custom sort
    compares.

    The node, the geometry and the material drawn with, the scene's
    `override_material` when it replaced the object's own. A sprite names
    no geometry, and its `geometry` is -1.
    """

    var node: NodeId
    var geometry: GeometryId
    var material: MaterialId
    # Which primitives the run holds, and how many: `DRAW_TRIANGLES`,
    # `DRAW_SEGMENTS` or `DRAW_POINTS`.
    var kind: DrawKind
    var count: Int
    # The node's render order, three.js's `renderOrder`.
    var order: Int
    # How far ahead of the camera the object's origin is, in meters: the
    # larger, the further. It orders as three.js's `z` does.
    var z: Float32


# How a caller orders a frame's runs, three.js's `setOpaqueSort` and
# `setTransparentSort`: True when the first is drawn before the second. A
# plain function, as three.js's is, and the sort is stable.
comptime RenderSort = def(RenderItem, RenderItem) thin -> Bool


struct _Span(ImplicitlyCopyable):
    """One draw's run of primitives in a prepared list, with its sort key.

    What `_prepared` and `_prepared_lines` record beside the corners they
    emit, and what `prepare_frame` turns into `Draw` records: the run,
    which list it is in, how deep the draw was, whether it blends, and
    whether it transmits.
    """

    var kind: DrawKind
    # The first primitive of the run, a triangle or a segment.
    var first: Int
    var count: Int
    var depth: Float32
    var blends: Bool
    # The draw's node's render order, which sorts before the depth.
    var order: Int
    # Whether the draw's material transmits, three.js's `transmissive`
    # list: drawn after every opaque run and before every blended one.
    var transmits: Bool
    # What drew the run.
    var source: _Source

    def __init__(
        out self,
        kind: DrawKind,
        first: Int,
        count: Int,
        depth: Float32,
        blends: Bool,
        order: Int,
        source: _Source,
        transmits: Bool = False,
    ):
        """Record one run.

        Args:
            kind: Which list the run is in.
            first: Its first primitive.
            count: How many primitives it holds.
            depth: The draw's camera-space depth.
            blends: Whether its material blends.
            order: Its node's render order.
            source: What drew it.
            transmits: Whether its material transmits. Only a filled
                surface can.
        """
        self.kind = kind
        self.first = first
        self.count = count
        self.depth = depth
        self.blends = blends
        self.order = order
        self.source = source
        self.transmits = transmits

    def item(self) -> RenderItem:
        """Return the run as a hook and a sort see it."""
        return RenderItem(
            self.source.node,
            self.source.geometry,
            self.source.material,
            self.kind,
            self.count,
            self.order,
            -self.depth,
        )


@fieldwise_init
struct _SortEntry(ImplicitlyCopyable):
    """A draw index with the order and depth that must stay beside it."""

    var item: Int
    var key: Float32
    var order: Int


def _entry_before(first: _SortEntry, second: _SortEntry) -> Bool:
    """Return whether the first draw precedes the second."""
    return _after(second.order, second.key, first.order, first.key)


def _sort_by(
    mut items: List[Int], mut keys: List[Float32], mut orders: List[Int]
):
    """Sort `items` by render order, then by `keys`, ascending, in place
    and stably.

    Small lists use insertion sort without allocation. Larger scenes use
    the shared stable merge sorter so reverse order takes O(n log n)
    comparisons. Keep each draw's key and order beside its index.
    """
    if len(items) > 32:
        # Avoid packing or allocating when the draw list is already ordered.
        var inversions = 0
        for position in range(1, len(items)):  # pragma: no branch
            if _after(
                orders[position - 1],
                keys[position - 1],
                orders[position],
                keys[position],
            ):
                inversions += 1
                break
        if inversions == 0:
            return
        var entries = List[_SortEntry](capacity=len(items))
        # This path has at least 33 entries in both passes.
        for position in range(len(items)):  # pragma: no branch
            entries.append(
                _SortEntry(items[position], keys[position], orders[position])
            )
        stable_sort[_entry_before](entries)
        for position in range(len(items)):  # pragma: no branch
            items[position] = entries[position].item
            keys[position] = entries[position].key
            orders[position] = entries[position].order
        return
    for position in range(len(items)):
        var item = items[position]
        var key = keys[position]
        var order = orders[position]
        var slot = position
        while slot > 0 and _after(orders[slot - 1], keys[slot - 1], order, key):
            items[slot] = items[slot - 1]
            keys[slot] = keys[slot - 1]
            orders[slot] = orders[slot - 1]
            slot -= 1
        items[slot] = item
        keys[slot] = key
        orders[slot] = order


def _after(
    order: Int, key: Float32, other_order: Int, other_key: Float32
) -> Bool:
    """Return True if an entry sorts after another: a higher render order,
    or the same order and a larger key."""
    return order > other_order or (order == other_order and key > other_key)


def _sort_with(mut runs: List[_Span], before: RenderSort):
    """Sort runs in place, stably, by a caller's function, three.js's
    custom sort: a run moves in front of the one before it while the
    function says it is drawn first."""

    def precedes(first: _Span, second: _Span) capturing -> Bool:
        return before(first.item(), second.item())

    stable_sort[precedes](runs)


def _furthest_first(mut runs: List[_Span], custom: Optional[RenderSort]):
    """Sort blended or transmissive runs in place: by the caller's
    transparent sort when there is one, and otherwise by render order
    and then furthest first, as `_draws` sorts its translucent draws."""
    var sorted = Bool(custom)
    if sorted:
        _sort_with(runs, custom.value())
        return
    var order = List[Int]()
    var depths = List[Float32]()
    var orders = List[Int]()
    for position in range(len(runs)):
        order.append(position)
        depths.append(runs[position].depth)
        orders.append(runs[position].order)
    _sort_by(order, depths, orders)
    var kept = runs.copy()
    for position in range(len(order)):
        runs[position] = kept[order[position]]


def _add_run(mut draws: List[Draw], mut items: List[RenderItem], run: _Span):
    """Append one run to a frame's draw order, and its item beside it."""
    draws.append(Draw(run.kind, run.first, run.count))
    items.append(run.item())
