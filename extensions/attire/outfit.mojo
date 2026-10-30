# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An outfit, and how it is made for a game humanoid.

An outfit is a list of garments. Two garments cannot share a slot and a
layer: a person wears one tunic, over one shirt. `dress` makes every
garment from the person's own skin, from the skin out:

1. Each garment's shell stands off the skin, and off the outer face of
   every garment before it in the outfit's layer order.
2. Each garment drops what the garments over it hide fully, and the skin
   drops what any garment hides fully. A body in full plate draws few of
   its skin triangles, so a dressed person costs about as many triangles
   as a bare one.
3. Each garment is cut at its hems and along its dye pattern, bound to
   its bones as its articulation says, painted, and given texture
   coordinates in meters round its bones. It is drawn with its fabric's
   look and bump map as a skinned mesh on the person's own skeleton.

`dress` changes the person's skin, and hides the scalp's hair under a
garment that covers the head. Dress a person once.

This is not a three.js port. See Extensions.

    var outfit = Outfit()
    outfit.add(gambeson())
    outfit.add(hauberk())
    var dressed = dress(scene, assets, person, outfit)
"""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.scene import Scene
from extensions.attire.cover import cover_values
from extensions.attire.dye import dye_pattern, paint
from extensions.attire.fabric import fabric, fabric_material
from extensions.attire.garment import Garment
from extensions.attire.kinds import layer_label, slot_label
from extensions.attire.mesh_ops import merge, normalize_normals
from extensions.attire.plates import articulate
from extensions.attire.shell import (
    COVER_SMOOTHING,
    SkinFrame,
    garment_piece,
    hide_under,
    outer_faces,
    shell_positions,
    smooth_values,
    standoff,
)
from extensions.attire.surface import SurfaceMaps, garment_uvs
from extensions.humanoid.rig.joints import HEAD
from extensions.humanoid.rig.game import GameHumanoid
from math.vector3 import Vector3
from objects.skinned_mesh import SkinnedMesh
from render.framebuffer import Color


struct Outfit(Copyable, Movable):
    """The garments one person wears."""

    var garments: List[Garment]
    """The garments, in the order they were added."""

    def __init__(out self):
        """Hold no garments."""
        self.garments = List[Garment]()

    def add(mut self, var garment: Garment) raises:
        """Add a garment.

        Args:
            garment: A garment that checks.

        Raises:
            Error: If the garment does not check, or the outfit already
                has a garment in its slot and layer.
        """
        garment.check()
        for other in self.garments:
            if other.slot == garment.slot and other.layer == garment.layer:
                raise Error(
                    "The outfit already has a "
                    + layer_label(garment.layer)
                    + " garment in the "
                    + slot_label(garment.slot)
                    + " slot"
                )
        self.garments.append(garment^)

    def check(self) raises:
        """Refuse an outfit that cannot be made.

        Raises:
            Error: If a garment does not check, or two share a slot and
                a layer.
        """
        var seen = Outfit()
        for garment in self.garments:
            seen.add(garment.copy())

    def order(self) -> List[Int]:
        """Return the garments from the skin out.

        A garment in a lower layer comes first. Within one layer, the
        garment added first comes first.

        Returns:
            Indices into `garments`.
        """
        var order = List[Int]()
        for layer in range(5):  # pragma: no branch
            for k in range(len(self.garments)):
                if self.garments[k].layer.value == layer:
                    order.append(k)
        return order^


struct Dressed(Movable):
    """What `dress` added to the scene, and each garment's whole shell."""

    var meshes: List[Int]
    """The skinned mesh of each garment, in the outfit's order, or -1
    for a garment that draws nothing."""
    var shells: List[BufferGeometry]
    """Each garment's whole shell, with nothing hidden, bound to its
    bones: what it weighs is its shell's. Empty for a garment that
    covers none of the person."""

    def __init__(
        out self, var meshes: List[Int], var shells: List[BufferGeometry]
    ) raises:
        """Hold the garments' meshes and shells.

        Args:
            meshes: One skinned mesh index, or -1, per garment.
            shells: One whole shell per garment.

        Raises:
            Error: If there is not one shell per mesh.
        """
        if len(meshes) != len(shells):
            raise Error("A dressed outfit needs one shell per garment")
        self.meshes = meshes^
        self.shells = shells^


def dress_pieces(
    skin: BufferGeometry,
    person: GameHumanoid,
    outfit: Outfit,
    mut over_skin: List[Float32],
    mut shells: List[BufferGeometry],
) raises -> List[BufferGeometry]:
    """Make every garment of an outfit from one skin.

    Args:
        skin: One of the person's skinned meshes, in the pelvis frame.
        person: The person.
        outfit: An outfit that checks.
        over_skin: Filled with, per skin vertex, the greatest cover value
            of any garment.
        shells: Filled with each garment's whole piece, with nothing
            hidden, in the outfit's order.

    Returns:
        One piece per garment, in the outfit's order, without what the
        garments over it hide. A piece has no triangles where its garment
        covers none of this skin.

    Raises:
        Error: If the skin is malformed.
    """
    var frame = SkinFrame(skin)
    var count = frame.count()
    var order = outfit.order()
    var values = List[List[Float32]]()
    var faces = List[List[Float32]]()
    var places = List[List[Vector3]]()
    for k in order:
        ref garment = outfit.garments[k]
        var cloth = fabric(garment.fabric)
        var drape = cloth.drape
        if garment.drape >= 0:
            drape = garment.drape
        var mine = smooth_values(
            frame,
            cover_values(skin, person.rig, garment.cover),
            COVER_SMOOTHING,
        )
        var standoffs = List[Float32](capacity=count)
        for v in range(count):
            standoffs.append(
                standoff(
                    Float32(cloth.clearance.value + garment.ease.value),
                    values,
                    faces,
                    v,
                )
            )
        var shell = shell_positions(frame, standoffs, mine, drape)
        faces.append(outer_faces(frame, shell, Float32(cloth.thickness.value)))
        places.append(shell^)
        values.append(mine^)
    over_skin = List[Float32](length=count, fill=0)
    var pieces = List[BufferGeometry](capacity=len(order))
    shells = List[BufferGeometry](capacity=len(order))
    for _ in range(len(order)):
        pieces.append(BufferGeometry())
        shells.append(BufferGeometry())
    var nothing = List[Float32](length=count, fill=0)
    for i in range(len(order)):
        var over = List[Float32](length=count, fill=0)
        for j in range(i + 1, len(order)):
            for v in range(count):
                over[v] = max(over[v], values[j][v])
        for v in range(count):
            over_skin[v] = max(over_skin[v], values[i][v])
        pieces[order[i]] = garment_piece(skin, places[i], values[i], over)
        shells[order[i]] = garment_piece(skin, places[i], values[i], nothing)
    return pieces^


def _gather(mut joined: Optional[BufferGeometry], piece: BufferGeometry) raises:
    """Join a piece onto what was gathered, if it has any triangles."""
    if piece.triangle_count() == 0:
        return
    if joined:
        joined = merge(joined.value(), piece)
    else:
        joined = piece.clone()


def dress(
    mut scene: Scene,
    mut assets: Assets,
    person: GameHumanoid,
    outfit: Outfit,
) raises -> Dressed:
    """Make an outfit for a game humanoid and add it to the scene.

    Each garment becomes a skinned mesh on the person's skeleton, drawn
    with its fabric's look. The person's skin drops the triangles the
    outfit hides fully.

    Args:
        scene: The scene the person is in.
        assets: The store of the person's geometry and materials.
        person: A game humanoid that has not been dressed.
        outfit: An outfit that checks.

    Returns:
        The skinned mesh of each garment, and its whole shell.

    Raises:
        Error: If the outfit does not check, the person has no skin, or
            the person's meshes are not in the scene.
    """
    outfit.check()
    if len(person.skins) == 0:
        raise Error("Only a person with a skin can be dressed")
    var count = len(outfit.garments)
    var joined = List[Optional[BufferGeometry]]()
    var wholes = List[Optional[BufferGeometry]]()
    for _ in range(count):
        joined.append(None)
        wholes.append(None)
    for k in person.skins:  # pragma: no branch
        var id = scene.skinned_meshes[k].geometry
        var skin = assets.geometries.get(id).clone()
        var over_skin = List[Float32]()
        var shells = List[BufferGeometry]()
        var pieces = dress_pieces(skin, person, outfit, over_skin, shells)
        for g in range(count):
            _gather(joined[g], pieces[g])
            _gather(wholes[g], shells[g])
        hide_under(skin, over_skin)
        assets.geometries.replace(id, skin^)
    # A garment over the head hides the scalp's hair.
    var hooded = False
    for garment in outfit.garments:
        if garment.cover.covers(HEAD):
            hooded = True
    if hooded:
        if person.hair:
            scene.node(person.hair.value()).visible = False
        if person.beard:
            scene.node(person.beard.value()).visible = False
        for k in range(len(person.strands)):
            if person.strands[k].node:
                scene.node(person.strands[k].node.value()).visible = False
    ref body = scene.skinned_meshes[person.skins[0]]
    var skeleton = body.skeleton.copy()
    var bind = body.bind_matrix
    var meshes = List[Int]()
    var shells = List[BufferGeometry]()
    var maps = SurfaceMaps()
    for g in range(count):
        ref garment = outfit.garments[g]
        if wholes[g]:
            shells.append(articulate(wholes[g].take(), garment))
        else:
            shells.append(BufferGeometry())
        if not joined[g]:
            meshes.append(-1)
            continue
        var piece = articulate(joined[g].take(), garment)
        piece = dye_pattern(piece, person.rig, garment.pattern)
        paint(piece, garment.dyes)
        piece = garment_uvs(piece, person.rig)
        normalize_normals(piece)
        var material = fabric_material(garment.fabric, Color(255, 255, 255))
        maps.apply(material, assets, garment.fabric)
        var look = assets.materials.add(material)
        meshes.append(len(scene.skinned_meshes))
        scene.add_skinned_mesh(
            SkinnedMesh(
                assets.geometries.add(piece^),
                look,
                person.root,
                skeleton.copy(),
                bind,
            )
        )
    return Dressed(meshes^, shells^)
