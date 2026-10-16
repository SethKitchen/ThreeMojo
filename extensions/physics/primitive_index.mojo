# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""One bounded primitive index for frozen physics query experiments.

This index is not a PhysicsWorld cache. Every entry owns a copy
of its bounds. Rebuild after changing membership or owner ids. Refit can
update bounds while preserving entry slots.
Nodes have escape links, so queries use no traversal stack. Each entry
occurs in one leaf. Median partitions bound the depth even for coincident
bounds. Queries return input indices; callers restore their own tie order.
"""

from math.bounds import Box3
from math.ray import Ray
from math.vector3 import Vector3
from extensions.physics.center_order import _MedianNode, build_median
from extensions.physics.shape import component
from std.math import isfinite


@fieldwise_init
struct _Node(ImplicitlyCopyable, Movable, _MedianNode):
    var box: Box3
    var entry: Int
    var escape: Int

    @staticmethod
    def blank(box: Box3) -> Self:
        """Return an interior node whose box is `box`.

        Args:
            box: The bounds of this node.

        Returns:
            A node with no entry and an unset escape.
        """
        return _Node(box, -1, 0)

    def set_entry(mut self, entry: Int):
        """Record the leaf's entry.

        Args:
            entry: The index this leaf holds.
        """
        self.entry = entry

    def set_escape(mut self, escape: Int):
        """Record the index just past this node's subtree.

        Args:
            escape: One past the last node of the subtree.
        """
        self.escape = escape


def _overlap_misses(query: Box3, box: Box3) -> Bool:
    """Return True when `box` misses `query`."""
    return not box.intersects_box(query)


def _ray_misses(query: Ray, box: Box3) -> Bool:
    """Return True when `box` misses `query`."""
    return not query.intersects_box(box)


@fieldwise_init
struct _AxisLine(ImplicitlyCopyable):
    """Two coordinates of an infinite line, and the axes they lie on."""

    var a: Float32
    var b: Float32
    var first: Int
    var second: Int


def _axis_misses(query: _AxisLine, box: Box3) -> Bool:
    """Return True when `box` misses the infinite line `query`."""
    return (
        query.a < component(box.min, query.first)
        or query.a > component(box.max, query.first)
        or query.b < component(box.min, query.second)
        or query.b > component(box.max, query.second)
    )


struct _PrimitiveIndex(Movable):
    var nodes: List[_Node]
    var boxes: List[Box3]
    var order: List[Int]
    var buffer: List[Int]

    def __init__(out self):
        self.nodes = List[_Node]()
        self.boxes = List[Box3]()
        self.order = List[Int]()
        self.buffer = List[Int]()

    def _validate(self, boxes: List[Box3]) raises:
        for box in boxes:
            if box.is_empty():
                raise Error("An index entry must have nonempty bounds")
            var values = SIMD[DType.float32, 8](
                box.min.x,
                box.min.y,
                box.min.z,
                box.max.x,
                box.max.y,
                box.max.z,
                0,
                0,
            )
            # The six stored coordinates always exist.
            for i in range(6):  # pragma: no branch
                if not isfinite(values[i]):
                    raise Error("An index entry must have finite bounds")

    def rebuild(mut self, boxes: List[Box3]) raises:
        # Validate the batch before replacing the previous valid snapshot.
        self._validate(boxes)
        self.boxes = boxes.copy()
        self.order = List[Int](capacity=len(boxes))
        for i in range(len(boxes)):
            self.order.append(i)
        self.buffer = self.order.copy()
        self.nodes = List[_Node](capacity=2 * len(boxes))
        if len(boxes) > 0:
            self._build(0, len(boxes))

    def refit(mut self, boxes: List[Box3]) raises:
        if len(boxes) != len(self.boxes):
            raise Error("A refit must retain entry count and owner mapping")
        self._validate(boxes)
        for i in range(len(boxes)):
            self.boxes[i] = boxes[i]
        for i in range(len(self.nodes) - 1, -1, -1):
            var entry = self.nodes[i].entry
            if entry >= 0:
                self.nodes[i].box = self.boxes[entry]
            else:
                var left = i + 1
                var right = self.nodes[left].escape
                var box = self.nodes[left].box
                box.expand_by_point(self.nodes[right].box.min)
                box.expand_by_point(self.nodes[right].box.max)
                self.nodes[i].box = box

    def _build(mut self, start: Int, end: Int):
        build_median(
            self.nodes, self.boxes, self.order, self.buffer, start, end
        )

    def _collect[
        Q: ImplicitlyCopyable, //, misses: def(Q, Box3) thin -> Bool
    ](self, query: Q, mut found: List[Int]) -> Int:
        """Walk the tree and keep every leaf `misses` does not reject.

        Parameters:
            Q: The query.
            misses: True when a node's box is outside the query.

        Args:
            query: What `misses` tests each box against.
            found: The leaf entries, replaced.

        Returns:
            How many nodes the walk read.
        """
        found.clear()
        var visited = 0
        var i = 0
        while i < len(self.nodes):
            visited += 1
            ref node = self.nodes[i]
            if misses(query, node.box):
                i = node.escape
                continue
            if node.entry >= 0:
                found.append(node.entry)
            i += 1
        return visited

    def overlap(self, box: Box3, mut found: List[Int]) -> Int:
        return self._collect[_overlap_misses](box, found)

    def ray(self, ray: Ray, mut found: List[Int]) -> Int:
        return self._collect[_ray_misses](ray, found)

    def axis_line(
        self, origin: Vector3, axis: Int, mut found: List[Int]
    ) -> Int:
        # Internal callers admit axis 0..2. Test the full line, not a half-ray:
        # longitudinal culling could change rounded legacy narrow answers.
        var first = (axis + 1) % 3
        var second = (axis + 2) % 3
        return self._collect[_axis_misses](
            _AxisLine(
                component(origin, first),
                component(origin, second),
                first,
                second,
            ),
            found,
        )
