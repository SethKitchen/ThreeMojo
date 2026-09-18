# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bones a skinned mesh is deformed by, from three.js
`src/objects/Bone.js` and `src/objects/Skeleton.js`.

A bone is a scene node. three.js says so too -- its `Bone` adds nothing to
`Object3D` but a name -- and it matters here, because it means an arm is
posed by moving nodes, which the scene graph and the animation mixer
already do. Nothing new drives a skeleton: a `KeyframeTrack` on a bone's
node is what animates it, and that already works.

What a bone needs *besides* a node is the one thing a node cannot carry:
where the bone stood when the mesh was attached to it. That is the inverse
bind matrix, and it turns "where this bone is now" into "how far this bone
has moved since the mesh was bound to it". three.js keeps the bones and
their inverses in two parallel arrays; here one `Bone` holds both, because
a bone without its inverse is not usable and two arrays can fall out of
step.

## The pose

`pose` returns one matrix per bone:

    bone_matrix = world(bone.node) * inverse_bind

which is three.js's `Skeleton.update` exactly. A bone standing where it was
bound gives the identity, and a mesh bound to it is left alone. That is the
property which makes a skeleton testable: pose the scene as it was bound,
and nothing may move.

## Why the world matrices are handed in

`pose` takes the bones' world matrices rather than the scene they came
from. A skeleton is an object, `core.scene` imports the objects, and a
skeleton that reached back for the scene would be a circle. The renderer
has both and does the looking up, which is also where every other world
matrix in a frame is read.

## What is refused

A skeleton with no bones. An inverse bind that is not a finite affine
transform, or one with no inverse of its own, which is not the inverse of
anything. A pose given a different number of world matrices than there are
bones, which is the one way the caller's lookup and the skeleton can
disagree.

A weight that is not a number, one below zero, or a set that does not sum
to one. Negative weights are not a mixture: two bones at minus one and two
sum to one and send a vertex to twice the distance of the further one,
outside anything either bone names. glTF forbids them for the same
reason.
"""

from core.object3d import NodeId
from math.matrix4 import Matrix4
from std.math import isfinite


@fieldwise_init
struct Bone(ImplicitlyCopyable):
    """One scene node, and where it stood when the mesh was bound to it."""

    var node: NodeId
    # The inverse of the bone's world matrix at bind time: three.js's entry
    # in `Skeleton.boneInverses`.
    var inverse_bind: Matrix4


struct Skeleton(Copyable, Movable):
    """The bones a skinned mesh is deformed by."""

    var bones: List[Bone]

    def __init__(out self, var bones: List[Bone]) raises:
        """Create a skeleton from bones that already know their binds.

        Args:
            bones: One per bone, each naming a node and carrying the
                inverse of its world matrix at bind time.

        Raises:
            Error: If there are no bones, or one carries an inverse bind
                that is not a finite affine transform.
        """
        if len(bones) == 0:
            raise Error("A skeleton needs at least one bone")
        for index in range(len(bones)):  # pragma: no branch
            if not bones[index].inverse_bind.is_finite():
                raise Error("A bone's inverse bind must be a real transform")
            if not bones[index].inverse_bind.is_affine():
                raise Error("A bone's inverse bind must be affine")
            # A matrix with no inverse is not the inverse of anything.
            # `bind_skeleton` refuses a bone bound at a scale of zero
            # before it inverts one; a caller handing the inverses in
            # directly has to meet the same bar.
            if bones[index].inverse_bind.determinant() == 0:
                raise Error("A bone's inverse bind must be invertible")
        self.bones = bones^

    def bone_count(self) -> Int:
        """Return how many bones the skeleton has."""
        return len(self.bones)

    def node(self, index: Int) raises -> NodeId:
        """Return which node one bone is.

        Args:
            index: Which bone, from zero.

        Returns:
            Its node.

        Raises:
            Error: If the skeleton has no bone at that index.
        """
        if index < 0 or index >= len(self.bones):
            raise Error("The skeleton has no bone at that index")
        return self.bones[index].node

    def pose(self, placed: List[Matrix4]) raises -> List[Matrix4]:
        """Return one matrix per bone, saying how far it has moved since
        the mesh was bound to it.

        three.js's `Skeleton.update`: each bone's world matrix times its
        inverse bind.

        Args:
            placed: Each bone's world matrix now, in the skeleton's own
                order; as many as there are bones.

        Returns:
            One matrix per bone, in the same order.

        Raises:
            Error: If there is not one world matrix per bone.
        """
        if len(placed) != len(self.bones):
            raise Error("A pose needs one world matrix for every bone")
        var matrices = List[Matrix4]()
        for index in range(len(self.bones)):  # pragma: no branch
            var moved = Matrix4(copy=placed[index])
            moved.multiply(self.bones[index].inverse_bind)
            matrices.append(moved^)
        return matrices^


# How far the four weights carrying one vertex may sum from one. glTF
# requires them normalized and three.js's loader normalizes them, so a set
# that misses is a rig with a mistake in it rather than a convention this
# does not know: weights summing to two make a vertex twice as far from the
# origin as the bones put it, which reads as a mesh that swells where it
# bends.
comptime WEIGHT_SLACK = Float32(1e-3)


def blend_bones(
    palette: List[Matrix4], bones: List[Int], weights: List[Float32]
) raises -> Matrix4:
    """Return the one matrix that carries a vertex, blended from the bones
    that hold it.

    three.js's `skinMatrix`: the weighted sum of the named bones' matrices,
    element by element.

    The same matrix then serves the position and the normal, as three.js's
    `skinning_vertex` and `skinnormal_vertex` share theirs. That is a
    compatibility choice and not a correctness one: a normal is properly
    carried by the inverse transpose, which differs from the matrix itself
    wherever the blend scales unevenly -- and a blend of two rotations
    does scale unevenly. It is close enough for a rig of rotations and
    translations, which is what a skeleton is, and it is what every engine
    doing this on a GPU uses.

    It is also why an elbow made of two bones pinches slightly when it
    bends: the average of two rotations taken through their matrices is not
    a rotation. Every engine that does this on a GPU has the same pinch, and
    the alternatives -- dual quaternions among them -- are a different
    feature rather than a better version of this one.

    Args:
        palette: One matrix per bone, from `Skeleton.pose`.
        bones: Which bones carry this vertex; as many as `weights`.
        weights: How much of each, summing to one.

    Returns:
        The blended matrix.

    Raises:
        Error: If the two lists are different lengths, if a weight is not a
            number or is below zero, if a weight names a bone the palette
            does not have, or if the weights do not sum to one.
    """
    if len(bones) != len(weights):
        raise Error("A vertex needs one weight for every bone it names")
    var summed = Array[Float32, 16](fill=0.0)
    var total = Float32(0)
    for slot in range(len(bones)):
        var weight = weights[slot]
        if not isfinite(weight):
            raise Error("A vertex's bone weights must be numbers")
        if weight < 0:
            raise Error("A vertex's bone weights cannot be negative")
        total += weight
        if weight == 0:
            continue
        var bone = bones[slot]
        if bone < 0 or bone >= len(palette):
            raise Error("A vertex names a bone the skeleton does not have")
        for element in range(16):  # pragma: no branch
            summed[element] += palette[bone].elements[element] * weight
    # Written so that a total which is not a number fails. `abs(nan - 1) >
    # slack` is false, so the obvious spelling lets one through, and the
    # same spelling let a rotation key through before it.
    if not (abs(total - 1) <= WEIGHT_SLACK):
        raise Error("A vertex's bone weights must sum to one")
    var blended = Matrix4()
    for element in range(16):  # pragma: no branch
        blended.elements[element] = summed[element]
    return blended^


def bind_skeleton(
    nodes: List[NodeId], placed: List[Matrix4]
) raises -> Skeleton:
    """Return a skeleton binding `nodes` where they stand now.

    three.js's `Skeleton.calculateInverses`, which is what happens when a
    skeleton is built without inverses given: each bone's inverse bind is
    the inverse of its world matrix at this moment. Pose the scene the way
    the mesh was modelled, call this, and the mesh is attached to the bones
    in that pose.

    Args:
        nodes: One node per bone, in the order the mesh's skin indices name
            them.
        placed: Each of those nodes' world matrices now.

    Returns:
        The skeleton.

    Raises:
        Error: If there are no nodes, if the two lists are different
            lengths, or if a world matrix cannot be inverted -- a bone
            bound at a scale of zero, which no later pose can measure
            against.
    """
    if len(nodes) != len(placed):
        raise Error("Binding needs one world matrix for every bone")
    var bones = List[Bone]()
    for index in range(len(nodes)):  # pragma: no branch
        var stood = Matrix4(copy=placed[index])
        if stood.determinant() == 0:
            raise Error("A bone cannot be bound where it has no size")
        stood.invert()
        bones.append(Bone(nodes[index], stood^))
    return Skeleton(bones^)
