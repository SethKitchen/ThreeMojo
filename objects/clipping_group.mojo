# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clipping planes held by a node of the scene graph, ported from three.js
`src/objects/ClippingGroup.js` and the part of
`src/renderers/common/ClippingContext.js` that reads it.

three.js's `ClippingGroup` is a `Group` with `clippingPlanes`, `enabled`,
`clipIntersection` and `clipShadows`. Every object under it is cut by its
planes. Here a `ClippingGroup` names a node, as a mesh names one, and
`Scene.add_clipping_group` adds it. The node is usually one that `group()`
built. The renderer cuts every draw at that node and under it.

## How nested groups add up

`Clipping` is three.js's `ClippingContext`: two lists of planes, in world
space. A group under the union rule adds its planes to `union_planes`, and
a kept point must be in front of each of them. A group under
`clip_intersection` adds its planes to `intersection_planes`, and a kept
point must be in front of one of them only. A group below another adds to
what the group above gave, so an inner group can only cut more.

A group whose `enabled` is off adds nothing, and nor does a group without
`clip_shadows` in a light's view for a shadow map, as three.js's
`getGroupContext` returns its parent's context for both.
"""

from core.object3d import NodeId
from math.bounds import Plane


struct ClippingGroup(Copyable, Movable):
    """Clipping planes that cut everything at a node and under it, three.js's
    `ClippingGroup`."""

    # The node that holds the planes. What is drawn at it and under it is
    # cut.
    var node: NodeId
    # The planes, in world space, three.js's `clippingPlanes`. A kept point
    # is on the side each normal faces.
    var clipping_planes: List[Plane]
    # Whether the planes cut anything, three.js's `enabled`. True by
    # default.
    var enabled: Bool
    # Whether a kept point needs to be in front of one plane only, three.js's
    # `clipIntersection`. False by default: in front of every plane.
    var clip_intersection: Bool
    # Whether the planes also cut what a light sees for its shadow map,
    # three.js's `clipShadows`. False by default.
    var clip_shadows: Bool

    def __init__(
        out self,
        node: NodeId,
        var clipping_planes: List[Plane] = List[Plane](),
        *,
        enabled: Bool = True,
        clip_intersection: Bool = False,
        clip_shadows: Bool = False,
    ) raises:
        """Create a clipping group at a node, three.js's
        `new ClippingGroup()`.

        Args:
            node: The node that holds the planes.
            clipping_planes: The planes, in world space. None by default,
                as in three.js.
            enabled: Whether the planes cut anything.
            clip_intersection: Whether a kept point needs to be in front of
                one plane only.
            clip_shadows: Whether the planes also cut a shadow map.

        Raises:
            Error: If the node id is negative.
        """
        if node.value < 0:
            raise Error("A clipping group must name a scene node")
        self.node = node
        self.clipping_planes = clipping_planes^
        self.enabled = enabled
        self.clip_intersection = clip_intersection
        self.clip_shadows = clip_shadows


struct Clipping(Copyable, Movable):
    """The planes the clipping groups above a node give it, three.js's
    `ClippingContext`."""

    # The planes a kept point must be in front of, each one, in world
    # space, three.js's `unionPlanes`.
    var union_planes: List[Plane]
    # The planes a kept point must be in front of one of, in world space,
    # three.js's `intersectionPlanes`. None means no such test.
    var intersection_planes: List[Plane]

    def __init__(out self):
        """Create a context with no planes, which cuts nothing."""
        self.union_planes = List[Plane]()
        self.intersection_planes = List[Plane]()

    def add_group(mut self, group: ClippingGroup, shadow_pass: Bool):
        """Add a group's planes, three.js's `getGroupContext` and `update`.

        Args:
            group: The group, below every group added before it.
            shadow_pass: Whether this is a light's view for a shadow map.
                A group then adds its planes only under `clip_shadows`.
        """
        if not group.enabled:
            return
        if shadow_pass and not group.clip_shadows:
            return
        if group.clip_intersection:
            self.intersection_planes.extend(Span(group.clipping_planes))
        else:
            self.union_planes.extend(Span(group.clipping_planes))

    def is_empty(self) -> Bool:
        """Return True if the context holds no plane, and so cuts nothing.

        Returns:
            Whether both lists are empty.
        """
        return (
            len(self.union_planes) == 0 and len(self.intersection_planes) == 0
        )
