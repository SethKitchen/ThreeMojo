# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A skirt that the legs push out of the way.

A skirt is skinned to the hips and the thighs, half to each thigh at the
middle of its front. As one knee rises high, the front follows it half
way, and the knee passes out through the cloth. `HemPush` keeps the cloth
out of the legs each frame, as a garment's collision would, with no cloth
to simulate:

1. **The target.** `add_hem_push` adds one more morph target to each
   piece of a skirted garment, at zero: it holds how far each vertex of
   the skirt moves this frame.
2. **The skin.** `HemPush.push` finds where each vertex of the skirt
   stands in the world, as the renderer's skin puts it: its rest place
   moved by the other targets at their weights, carried by its four bones.
3. **The legs.** A vertex within `HEM_GAP` of a capsule round a thigh or a
   shin is moved out along the capsule's normal to `HEM_GAP` from it. So
   the cloth lies over the knee as it rises, and does not show it through.
4. **Back to rest.** The move is in the world. The target moves the
   vertex before its bones carry it, so the move is turned back through
   the vertex's own blend of its bones: the inverse of that blend's
   linear part, then of the bind matrix's.

The colliders are `body_colliders`'s, round the thighs and the shins.

This is not a three.js port. See Extensions.

    var push = add_hem_push(scene, assets, mesh, person, skirt_top(rig))
    push.value().push(scene, assets)
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.scene import Scene
from extensions.attire.springs import (
    SpringCollider,
    body_colliders,
    nearest_on_segment,
)
from extensions.humanoid.rig.game import GameHumanoid
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh

comptime HEM_GAP = Float32(0.04)
"""How far outside a leg's capsule the cloth is kept, in meters."""
comptime HEM_PASSES = 3
"""How many times, at the most, the moves out of the legs' capsules are
made: a move out of one capsule can end in the next. A pass that moves
nothing ends them."""
comptime HEM_TARGET_NAME = "hem-push"
"""The name of the target that holds the push."""
comptime LEG_COLLIDERS = 4
"""How many of `body_colliders`'s capsules, after the trunk's three, are
the legs': the two thighs and the two shins."""
comptime TRUNK_COLLIDERS = 3
"""How many of `body_colliders`'s capsules come before the legs'."""


struct HemPush(Movable):
    """The push that keeps one piece of a skirt out of the legs."""

    var mesh: Int
    """The piece's skinned mesh in `scene.skinned_meshes`."""
    var target: Int
    """The piece's morph target that holds the push."""
    var skirt: List[Int]
    """The piece's vertices below the skirt's top: the ones pushed."""
    var legs: List[SpringCollider]
    """The capsules round the thighs and the shins."""

    def __init__(
        out self,
        mesh: Int,
        target: Int,
        var skirt: List[Int],
        var legs: List[SpringCollider],
    ):
        """Hold a piece's push.

        Args:
            mesh: The piece's skinned mesh.
            target: Its morph target that holds the push.
            skirt: Its vertices that are pushed.
            legs: The capsules they are pushed out of.
        """
        self.mesh = mesh
        self.target = target
        self.skirt = skirt^
        self.legs = legs^

    def push(self, scene: Scene, mut assets: Assets) raises -> Int:
        """Push the piece's skirt out of the legs as the bones stand now.

        Call it after the animation has moved the bones, the other targets
        have their weights, and the scene has been updated.

        Args:
            scene: The scene, updated.
            assets: The store of the piece's geometry. The geometry is
                replaced by one whose push target holds this frame's push.

        Returns:
            How many vertices were pushed.

        Raises:
            Error: If the scene is stale, or the mesh or its geometry is
                not in it.
        """
        ref skinned = scene.skinned_meshes[self.mesh]
        var piece = assets.geometries.get(skinned.geometry).clone()
        var bones = _bones(scene, self.mesh)
        var ends = self._ends(scene)
        ref points = piece.attribute_view(String(POSITION))
        ref indices = piece.attribute_view(String(SKIN_INDEX))
        ref shares = piece.attribute_view(String(SKIN_WEIGHT))
        var weights = _weights(skinned, self.target)
        var moves = List[Float32](length=3 * points.count(), fill=0)
        var pushed = 0
        for v in self.skirt:  # pragma: no branch
            var carry = _carry(indices, shares, bones, v)
            var at = carry.transform_point(_rest(piece, points, weights, v))
            var moved = at
            # The thigh's and the shin's capsules meet at the knee: a move
            # out of one can end in the other, so the moves are made
            # `HEM_PASSES` times.
            for _ in range(HEM_PASSES):  # pragma: no branch
                # A pass that moves the vertex out of no capsule ends them:
                # the next would move it no more.
                var still = True
                for c in range(len(self.legs)):  # pragma: no branch
                    var near = nearest_on_segment(
                        moved, ends[2 * c], ends[2 * c + 1]
                    )
                    var away = moved - near
                    var reach = away.length()
                    var keep = self.legs[c].radius + HEM_GAP
                    # A vertex on the capsule's axis stays where it is: it
                    # has no way out.
                    if reach < keep:
                        moved = near + away * (
                            keep / max(reach, Float32(1.0e-6))
                        )
                        still = False
                if still:
                    break
            var shift = moved - at
            if shift.length() == 0:
                continue
            pushed += 1
            var back = _linear_inverse(carry).transform_direction(shift)
            moves[3 * v] = back.x
            moves[3 * v + 1] = back.y
            moves[3 * v + 2] = back.z
        piece.morph_positions[self.target] = BufferAttribute(moves^, 3)
        assets.geometries.replace(skinned.geometry, piece^)
        return pushed

    def clearance(self, scene: Scene, assets: Assets) raises -> Float32:
        """Return how near the skirt comes to the legs, as the renderer's
        skin puts it with every target at its weight, the push's too.

        Args:
            scene: The scene, updated.
            assets: The store of the piece's geometry.

        Returns:
            The least distance, in meters, from a vertex of the skirt to
            the surface of a leg's capsule; less than zero inside one.

        Raises:
            Error: If the scene is stale, or the mesh or its geometry is
                not in it.
        """
        ref skinned = scene.skinned_meshes[self.mesh]
        ref piece = assets.geometries.get(skinned.geometry)
        var bones = _bones(scene, self.mesh)
        var ends = self._ends(scene)
        ref points = piece.attribute_view(String(POSITION))
        ref indices = piece.attribute_view(String(SKIN_INDEX))
        ref shares = piece.attribute_view(String(SKIN_WEIGHT))
        var weights = _weights(skinned, piece.morph_count())
        var least = Float32(1.0e30)
        for v in self.skirt:  # pragma: no branch
            var carry = _carry(indices, shares, bones, v)
            var at = carry.transform_point(_rest(piece, points, weights, v))
            for c in range(len(self.legs)):  # pragma: no branch
                var near = nearest_on_segment(at, ends[2 * c], ends[2 * c + 1])
                least = min(least, (at - near).length() - self.legs[c].radius)
        return least

    def _ends(self, scene: Scene) raises -> List[Vector3]:
        """Return the two ends of each leg's capsule, in the world."""
        var ends = List[Vector3](capacity=2 * len(self.legs))
        for leg in self.legs:  # pragma: no branch
            var world = scene.world_matrix(leg.node)
            ends.append(world.transform_point(leg.start))
            ends.append(world.transform_point(leg.end))
        return ends^


def _bones(scene: Scene, mesh: Int) raises -> List[Matrix4]:
    """Return each bone's matrix, with the mesh's bind matrix: where it
    carries a vertex of the mesh in the world. A vertex's blend of these is
    its blend of the bones, then the bind matrix, as the renderer's skin
    takes it."""
    ref skinned = scene.skinned_meshes[mesh]
    ref skeleton = skinned.skeleton
    var bones = List[Matrix4](capacity=skeleton.bone_count())
    for bone in skeleton.bones:  # pragma: no branch
        bones.append(
            scene.world_matrix(bone.node)
            * bone.inverse_bind
            * skinned.bind_matrix
        )
    return bones^


def _carry(
    indices: BufferAttribute,
    shares: BufferAttribute,
    bones: List[Matrix4],
    v: Int,
) raises -> Matrix4:
    """Return a vertex's blend of its four bones, by their weights."""
    var blend = Matrix4()
    for e in range(16):  # pragma: no branch
        blend.elements[e] = 0
    for slot in range(4):  # pragma: no branch
        var share = shares.component(v, slot)
        # A bone of no weight carries the vertex nowhere.
        if share == 0:
            continue
        ref bone = bones[Int(indices.component(v, slot))]
        for e in range(16):  # pragma: no branch
            blend.elements[e] += bone.elements[e] * share
    return blend^


def _rest(
    piece: BufferGeometry,
    points: BufferAttribute,
    weights: List[Float32],
    v: Int,
) raises -> Vector3:
    """Return where a vertex rests, moved by the first targets, as many as
    there are weights, at those weights."""
    var rest = points.vector3(v)
    # A piece with a push has its sway's targets, at the least.
    for k in range(len(weights)):  # pragma: no branch
        # A target at no weight moves nothing.
        if weights[k] == 0:
            continue
        rest = rest + piece.morph_positions[k].vector3(v) * weights[k]
    return rest


def _weights(skinned: SkinnedMesh, targets: Int) raises -> List[Float32]:
    """Return the weights of a mesh's first targets."""
    var weights = List[Float32](capacity=targets)
    for k in range(targets):  # pragma: no branch
        weights.append(skinned.morph_influence(k))
    return weights^


def _linear_inverse(m: Matrix4) -> Matrix4:
    """Return the inverse of a matrix's linear part, with no move."""
    var linear = m
    linear.elements[12] = 0
    linear.elements[13] = 0
    linear.elements[14] = 0
    linear.invert()
    return linear^


def add_hem_push(
    mut scene: Scene,
    mut assets: Assets,
    mesh: Int,
    person: GameHumanoid,
    top: Float32,
) raises -> Optional[HemPush]:
    """Give a piece of a skirted garment a target that keeps it out of the
    legs.

    Args:
        scene: The scene the piece is in.
        assets: The store of its geometry. The geometry is replaced by one
            that wears the target, at zero.
        mesh: The piece's skinned mesh in `scene.skinned_meshes`.
        person: The person who wears it: the legs' capsules are theirs.
        top: The height the skirt hangs from, in meters, in the body's
            frame.

    Returns:
        The push, or none for a piece with no vertex below `top`, or with
        no morph targets yet: its targets must be relative.

    Raises:
        Error: If the mesh is not in the scene.
    """
    var id = scene.skinned_meshes[mesh].geometry
    var piece = assets.geometries.get(id).clone()
    if piece.morph_count() == 0 or not piece.morph_relative:
        return None
    ref points = piece.attribute_view(String(POSITION))
    var skirt = List[Int]()
    for v in range(points.count()):  # pragma: no branch
        if points.vector3(v).y < top:
            skirt.append(v)
    if len(skirt) == 0:
        return None
    var target = piece.morph_count()
    piece.add_morph_target(
        BufferAttribute(List[Float32](length=3 * points.count(), fill=0), 3),
        name=HEM_TARGET_NAME,
    )
    scene.skinned_meshes[mesh].update_morph_targets(piece)
    assets.geometries.replace(id, piece^)
    scene.skinned_meshes[mesh].set_morph_influence(target, 1)
    var all = body_colliders(person)
    var legs = List[SpringCollider]()
    for k in range(
        TRUNK_COLLIDERS, TRUNK_COLLIDERS + LEG_COLLIDERS
    ):  # pragma: no branch
        legs.append(all[k])
    return HemPush(mesh, target, skirt^, legs^)
