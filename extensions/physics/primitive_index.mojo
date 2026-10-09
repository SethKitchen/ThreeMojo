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
from extensions.physics.bvh import median_order, split_axis
from extensions.physics.shape import component
from std.math import isfinite


@fieldwise_init
struct _Node(ImplicitlyCopyable):
    var box: Box3
    var entry: Int
    var escape: Int


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
        var box = self.boxes[self.order[start]]
        for i in range(start + 1, end):
            box.expand_by_point(self.boxes[self.order[i]].min)
            box.expand_by_point(self.boxes[self.order[i]].max)
        var node = len(self.nodes)
        self.nodes.append(_Node(box, -1, 0))
        if end - start == 1:
            self.nodes[node].entry = self.order[start]
        else:
            median_order(
                self.boxes, self.order, self.buffer, start, end, split_axis(box)
            )
            var middle = start + (end - start) // 2
            self._build(start, middle)
            self._build(middle, end)
        self.nodes[node].escape = len(self.nodes)

    def overlap(self, box: Box3, mut found: List[Int]) -> Int:
        found.clear()
        var visited = 0
        var i = 0
        while i < len(self.nodes):
            visited += 1
            ref node = self.nodes[i]
            if not node.box.intersects_box(box):
                i = node.escape
                continue
            if node.entry >= 0:
                found.append(node.entry)
            i += 1
        return visited

    def ray(self, ray: Ray, mut found: List[Int]) -> Int:
        found.clear()
        var visited = 0
        var i = 0
        while i < len(self.nodes):
            visited += 1
            ref node = self.nodes[i]
            if not ray.intersects_box(node.box):
                i = node.escape
                continue
            if node.entry >= 0:
                found.append(node.entry)
            i += 1
        return visited

    def axis_line(
        self, origin: Vector3, axis: Int, mut found: List[Int]
    ) -> Int:
        # Internal callers admit axis 0..2. Test the full line, not a half-ray:
        # longitudinal culling could change rounded legacy narrow answers.
        found.clear()
        var first = (axis + 1) % 3
        var second = (axis + 2) % 3
        var a = component(origin, first)
        var b = component(origin, second)
        var visited = 0
        var i = 0
        while i < len(self.nodes):
            visited += 1
            ref node = self.nodes[i]
            if (
                a < component(node.box.min, first)
                or a > component(node.box.max, first)
                or b < component(node.box.min, second)
                or b > component(node.box.max, second)
            ):
                i = node.escape
                continue
            if node.entry >= 0:
                found.append(node.entry)
            i += 1
        return visited
