# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Many nodes that play one clip as one, from three.js
`src/animation/AnimationObjectGroup.js`.

A crowd of the same model walks with the same walk. three.js lets one
action drive them all: give `clipAction` a group instead of an object, and
every track is bound once for every member. The group is what a track's
string path is resolved against.

Here a group is a list of nodes, and an action given one with
`AnimationAction.use_group` plays every track on every member instead of
on the target the track names. Each member is to the track what the object
is to a three.js path:

    POSITION, SCALE, QUATERNION, VISIBLE    the member node itself
    MORPH_INFLUENCE                         every mesh at the member
    MATERIAL_...                            the material of every such mesh
    LIGHT_...                               every light at the member

That is three.js's `.morphTargetInfluences`, `.material.opacity` and
`.color` read off the object. Two members whose meshes share a material
drive it once, not twice.

## What differs from three.js

three.js's group is shared: an action holds it by reference, and adding a
member later binds that member into every action playing on the group.
Here an action holds its own copy, so a member added to it after
`use_group` is added through `AnimationMixer.action(i).group`. three.js's
`uncache` and its statistics are not ported: nothing here caches a
binding per member that would need to be let go.

## What is refused

A node index below zero, when it is added. A member that the scene does not
have is refused at `AnimationMixer.update`, where the scene is known.
"""

from core.object3d import NodeId


struct AnimationObjectGroup(Copyable, Movable):
    """A list of nodes that one action plays one clip on together."""

    var members: List[NodeId]

    def __init__(out self):
        """Create a group with no members."""
        self.members = List[NodeId]()

    def __init__(out self, *, copy: Self):
        """Copy another group, its members included."""
        self.members = copy.members.copy()

    def add(mut self, node: NodeId) raises:
        """Add a node to the group, three.js's `add`.

        A node already in the group is left where it is, as three.js leaves
        it.

        Args:
            node: The node to add.

        Raises:
            Error: If the node index is below zero.
        """
        if node.value < 0:
            raise Error("A group member must name a node")
        if self.contains(node):
            return
        self.members.append(node)

    def remove(mut self, node: NodeId):
        """Take a node out of the group, three.js's `remove`.

        A node that is not in the group is ignored, as three.js ignores it.

        Args:
            node: The node to take out.
        """
        var kept = List[NodeId]()
        for index in range(len(self.members)):
            if self.members[index] != node:
                kept.append(self.members[index])
        self.members = kept^

    def contains(self, node: NodeId) -> Bool:
        """Return True if the node is in the group.

        Args:
            node: The node to look for.

        Returns:
            True if it is a member.
        """
        for index in range(len(self.members)):
            if self.members[index] == node:
                return True
        return False

    def count(self) -> Int:
        """Return how many nodes the group holds."""
        return len(self.members)
