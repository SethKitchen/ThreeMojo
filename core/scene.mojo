# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The flat array of nodes that makes up a scene graph.

three.js walks a tree of objects to update world matrices. Here the nodes live
in one array and each records its parent's index, because Mojo will not let a
struct hold a `List` of itself — see `core.object3d`.

The array is kept in an order where a parent always precedes its children.
`add` enforces it by refusing a parent that does not already exist, which is
not a restriction in practice: you cannot attach something to an object you
have not created. The payoff is that updating every world matrix is a single
forward pass, with each node's parent guaranteed to be finished before the
node is reached. No recursion, no visited set, no cycles possible.

**Stale transforms are refused, not served.** World matrices are cached by
`update` and read back by `world_matrix`. Any edit invalidates them, and
reading one before recomputing raises rather than handing back a matrix from
before the edit. The alternative — recompute automatically on read — hides
how much work a render costs and recomputes the whole scene for one lookup.
The alternative it replaces, serving the stale value, is worse than both: it
produces a plausible wrong image and no error at all.

**A known limitation.** Storing parents before children restricts reparenting.
Moving an older node underneath a newer one is a perfectly valid acyclic
operation and this rejects it, because the array order would no longer match
the dependency order. Nothing needs it yet. When something does, the fix is to
separate a stable node id from the position a node occupies in traversal
order, rather than to relax the check.

The two arrays are named with a leading underscore. Mojo does not enforce
private fields, so that is a convention and not a guarantee — `validate` exists
to catch the case where something reached past it anyway.
"""

from core.object3d import NO_PARENT, Object3D
from math.matrix4 import Matrix4
from math.vector3 import Vector3


struct Scene(Movable):
    """A scene graph held as a parent-before-child array of nodes."""

    var _nodes: List[Object3D]
    var _world: List[Matrix4]
    # False only when every world matrix reflects every node as it stands.
    var _stale: Bool

    def __init__(out self):
        """Create an empty scene."""
        self._nodes = List[Object3D]()
        self._world = List[Matrix4]()
        # An empty scene has nothing to recompute, so it starts current.
        self._stale = False

    def count(self) -> Int:
        """Return how many nodes the scene holds."""
        return len(self._nodes)

    def is_stale(self) -> Bool:
        """Return True if a node has changed since the last `update`."""
        return self._stale

    def add(mut self, var node: Object3D) raises -> Int:
        """Add `node` and return the index it was given.

        Args:
            node: The node to add; its `parent` must already be in the scene.

        Returns:
            The new node's index, usable as a parent for later nodes.

        Raises:
            Error: If the parent index is not an existing earlier node.
        """
        if node.parent != NO_PARENT:
            if node.parent < 0 or node.parent >= len(self._nodes):
                raise Error("A node's parent must already be in the scene")
        self._nodes.append(node^)
        self._world.append(Matrix4())
        self._stale = True
        return len(self._nodes) - 1

    def attach(mut self, var node: Object3D, parent: Int) raises -> Int:
        """Add `node` as a child of `parent` and return its index.

        Args:
            node: The node to add.
            parent: Index of an existing node to attach it to.

        Returns:
            The new node's index.

        Raises:
            Error: If `parent` is not an existing earlier node.
        """
        node.parent = parent
        return self.add(node^)

    def get(self, index: Int) raises -> Object3D:
        """Return a copy of the node at `index`.

        A copy rather than a reference, so editing it does not silently change
        the scene behind `update`'s back. Put it back with `set`.

        Args:
            index: Which node to read.

        Returns:
            A copy of that node.

        Raises:
            Error: If the index is out of range.
        """
        if index < 0 or index >= len(self._nodes):
            raise Error("Scene node index out of range")
        return Object3D(copy=self._nodes[index])

    def set(mut self, index: Int, var node: Object3D) raises:
        """Replace the node at `index`, keeping its place in the order.

        Args:
            index: Which node to replace.
            node: Its replacement.

        Raises:
            Error: If the index is out of range, or the replacement's parent
                is not earlier in the array, which would break the ordering
                the single-pass update depends on.
        """
        if index < 0 or index >= len(self._nodes):
            raise Error("Scene node index out of range")
        # Both halves matter. `>= index` keeps the parent-before-child order
        # the single-pass update depends on; `< 0` catches a parent that is
        # neither NO_PARENT nor a real node, which `add` already refuses.
        # Without it a parent of -2 reached `self._world[parent]` in `update`.
        if node.parent != NO_PARENT:
            if node.parent < 0 or node.parent >= index:
                raise Error("A node's parent must be an earlier existing node")
        self._nodes[index] = node^
        self._stale = True

    def update(mut self) raises:
        """Recompute every node's world matrix.

        One forward pass is enough: a parent always sits earlier in the array,
        so its world matrix is already final by the time a child is reached.

        Raises:
            Error: If a node's local matrix cannot be built.
        """
        for index in range(len(self._nodes)):
            var local = self._nodes[index].local_matrix()
            var parent = self._nodes[index].parent
            if parent == NO_PARENT:
                self._world[index] = local^
            else:
                var combined = Matrix4(copy=self._world[parent])
                combined.multiply(local)
                self._world[index] = combined^
        self._stale = False

    def validate(self) raises:
        """Check the invariants the single-pass update relies on.

        Nothing in normal use can break these — every mutation goes through a
        method that checks — so this is for tests and for the day something
        reaches past the underscore on `_nodes`.

        Raises:
            Error: If the two arrays have drifted apart, or any node's parent
                is not an earlier valid node.
        """
        if len(self._nodes) != len(self._world):
            raise Error("Scene node and world arrays have different lengths")
        for index in range(len(self._nodes)):
            var parent = self._nodes[index].parent
            if parent == NO_PARENT:
                continue
            if parent < 0 or parent >= index:
                raise Error("A node's parent must be an earlier existing node")

    def world_matrix(self, index: Int) raises -> Matrix4:
        """Return the world transform computed for `index` by `update`.

        Args:
            index: Which node to read.

        Returns:
            That node's world matrix.

        Raises:
            Error: If the index is out of range, or the scene has changed
                since `update` was last called — see the module docstring.
        """
        if index < 0 or index >= len(self._world):
            raise Error("Scene node index out of range")
        if self._stale:
            raise Error(
                "The scene has changed since update(); call scene.update()"
                " before reading a world matrix"
            )
        return Matrix4(copy=self._world[index])

    def world_position(self, index: Int) raises -> Vector3:
        """Return where `index` sits in world space.

        Args:
            index: Which node to read.

        Returns:
            The node's origin transformed into world space.

        Raises:
            Error: If the index is out of range, or the scene is stale.
        """
        return self.world_matrix(index).transform_point(Vector3(0, 0, 0))
