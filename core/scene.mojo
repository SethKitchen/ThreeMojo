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
"""

from core.object3d import NO_PARENT, Object3D
from math.matrix4 import Matrix4
from math.vector3 import Vector3


struct Scene(Movable):
    """A scene graph held as a parent-before-child array of nodes."""

    var nodes: List[Object3D]
    var world: List[Matrix4]

    def __init__(out self):
        """Create an empty scene."""
        self.nodes = List[Object3D]()
        self.world = List[Matrix4]()

    def count(self) -> Int:
        """Return how many nodes the scene holds."""
        return len(self.nodes)

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
            if node.parent < 0 or node.parent >= len(self.nodes):
                raise Error("A node's parent must already be in the scene")
        self.nodes.append(node^)
        self.world.append(Matrix4())
        return len(self.nodes) - 1

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
        """Return a copy of the node at `index`."""
        if index < 0 or index >= len(self.nodes):
            raise Error("Scene node index out of range")
        return Object3D(copy=self.nodes[index])

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
        if index < 0 or index >= len(self.nodes):
            raise Error("Scene node index out of range")
        if node.parent != NO_PARENT and node.parent >= index:
            raise Error("A node's parent must come before it")
        self.nodes[index] = node^

    def update(mut self) raises:
        """Recompute every node's world matrix.

        One forward pass is enough: a parent always sits earlier in the array,
        so its world matrix is already final by the time a child is reached.

        Raises:
            Error: If a node's local matrix cannot be built.
        """
        for index in range(len(self.nodes)):
            var local = self.nodes[index].local_matrix()
            var parent = self.nodes[index].parent
            if parent == NO_PARENT:
                self.world[index] = local^
            else:
                var combined = Matrix4(copy=self.world[parent])
                combined.multiply(local)
                self.world[index] = combined^

    def world_matrix(self, index: Int) raises -> Matrix4:
        """Return the world transform computed for `index` by `update`.

        Args:
            index: Which node to read.

        Returns:
            That node's world matrix.

        Raises:
            Error: If the index is out of range.
        """
        if index < 0 or index >= len(self.world):
            raise Error("Scene node index out of range")
        return Matrix4(copy=self.world[index])

    def world_position(self, index: Int) raises -> Vector3:
        """Return where `index` sits in world space.

        Args:
            index: Which node to read.

        Returns:
            The node's origin transformed into world space.

        Raises:
            Error: If the index is out of range.
        """
        return self.world_matrix(index).transform_point(Vector3(0, 0, 0))
