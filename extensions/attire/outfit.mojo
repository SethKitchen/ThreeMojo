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
2. A skirted garment hangs its skirt round both legs below the hips, and
   a shod garment closes each foot in a last. A skirt hangs over the
   skirts under it.
3. Each garment drops what the garments over it hide fully, and the skin
   drops what any garment hides fully. A skirt hides nothing below its
   top, where it hangs clear of the legs. A body in full plate draws few
   of its skin triangles, so a dressed person costs about as many
   triangles as a bare one.
4. Each garment is cut at its hems and along its dye pattern, bound to
   its bones as its articulation says, painted, and given texture
   coordinates in meters round its bones. A fabric 1.5 mm thick or more
   has a rim along each hem, so plate, mail, leather and padding show
   their thickness. It is drawn with its fabric's look and bump map as a
   skinned mesh on the person's own skeleton.

`dress` changes the person's skin, and hides the scalp's hair under a
garment that covers the head. A hat or a helmet is drawn round the head
as its headwear says; a great helm hides the hair, and every other hat
leaves it below its brim. Dress a person once.

This is not a three.js port. See Extensions.

    var outfit = Outfit()
    outfit.add(gambeson())
    outfit.add(hauberk())
    var dressed = dress(scene, assets, person, outfit)
"""

from std.math import sqrt

from core.assets import Assets
from core.object3d import NodeId
from core.buffer_geometry import POSITION, BufferGeometry
from core.scene import Scene
from extensions.attire.cover import cover_values
from extensions.attire.dye import dye_pattern, paint
from extensions.attire.fabric import (
    dye_sheen,
    fabric,
    fabric_material,
    fold_depth,
)
from extensions.attire.garment import Garment
from extensions.attire.cowl import hang_cowl, head_cowl
from extensions.attire.band import belt_band
from extensions.attire.dome import dome_shoulders
from extensions.attire.headwear import head_frame, hat_mesh, press_hair
from extensions.attire.kinds import (
    BANDED,
    COWLED,
    DOMED,
    HATTED,
    PRIMARY_DYE,
    SHOD,
    SKIRTED,
    layer_label,
    slot_label,
)
from extensions.attire.last import FootLast, foot_lasts, shoe
from extensions.attire.mesh_ops import add_rim, cut, merge, normalize_normals
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
from extensions.attire.skirt import (
    SKIRT_RING,
    SkirtEnvelope,
    hang_skirt,
    leg_side,
    skirt_envelope,
    skirt_scale,
    skirt_top,
)
from extensions.attire.surface import SurfaceMaps, garment_uvs
from extensions.humanoid.rig.joints import HEAD
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from math.vector3 import Vector3
from objects.skinned_mesh import SkinnedMesh
from render.framebuffer import Color


comptime RIM_THINNEST = Float32(0.0015)
"""A fabric at least this thick, in meters, has a rim at its hems: velvet,
leather, padding, mail and plate."""
comptime RIM_DEEPEST = Float32(0.006)
"""The deepest a rim runs, in meters."""


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


comptime FULL_DETAIL = Float32(10000)
"""The triangles of a skin whose formed garments take their full detail:
a little less than the body's share of a 16,000-triangle budget, less a
beard's."""
comptime LEAST_DETAIL = Float32(0.5)
"""The least share of their full detail formed garments take."""


def garment_detail(skin: BufferGeometry) raises -> Float32:
    """Return the share of their full detail a skin's formed garments
    take.

    A garment cut from the skin has as many triangles as the skin under
    it. A skirt's rings, a hat's rings and sectors and a boot's last do
    not: they would keep their full count on a coarse skin, and draw more
    than the body. So they take a share that falls with the square root
    of the skin's triangles, as the spacing of its vertices grows.

    Args:
        skin: A person's skin, as drawn.

    Returns:
        One for `FULL_DETAIL` triangles or more; less for fewer, and
        `LEAST_DETAIL` at the least.

    Raises:
        Error: If the skin has no positions.
    """
    var share = sqrt(Float32(skin.triangle_count()) / FULL_DETAIL)
    return min(Float32(1), max(LEAST_DETAIL, share))


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
    # Below its top, a skirt hangs clear of the legs, so it hides neither
    # the skin nor the garments under it there. A band two rings deep
    # below the top stays hidden, so no triangle that crosses the top
    # shows through the shell over it.
    var legs = leg_side(skin)
    var top = skirt_top(person.rig)
    var detail = garment_detail(skin)
    var clear = top - 2 * SKIRT_RING * skirt_scale(person.rig) / detail
    var values = List[List[Float32]]()
    var hides = List[List[Float32]]()
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
        var hide = mine.copy()
        # A band is drawn over the garments under it, so it hides none of
        # them: they show round it whole. A hat stands off the head, so it
        # hides none of the face under it.
        if (
            garment.form == BANDED
            or garment.form == HATTED
            or garment.form == DOMED
        ):
            hide = List[Float32](length=count, fill=0)
        if garment.form == SKIRTED:
            for v in range(count):
                if legs[v] and frame.points[v].y < clear:
                    hide[v] = 0
        hides.append(hide^)
        values.append(mine^)
    over_skin = List[Float32](length=count, fill=0)
    var pieces = List[BufferGeometry](capacity=len(order))
    shells = List[BufferGeometry](capacity=len(order))
    for _ in range(len(order)):
        pieces.append(BufferGeometry())
        shells.append(BufferGeometry())
    var nothing = List[Float32](length=count, fill=0)
    var everything = List[Float32](length=count, fill=1)
    # Each skirt hangs over the skirts under it, from the skin out. A boot
    # closes each foot in a last.
    var skirts = List[SkirtEnvelope]()
    var lasts = List[List[FootLast]]()
    var cowls = List[List[FootLast]]()
    for i in range(len(order)):
        ref garment = outfit.garments[order[i]]
        var whole = garment_piece(skin, places[i], values[i], nothing)
        var envelope = SkirtEnvelope(Vector3(0, top, 0), 0)
        if garment.form == SKIRTED:
            var cloth = fabric(garment.fabric)
            envelope = skirt_envelope(
                whole,
                person.rig,
                garment.flare,
                skirts,
                Float32(cloth.clearance.value + garment.ease.value),
                Float32(cloth.thickness.value),
                Float32(fold_depth(garment.fabric).value),
                detail,
            )
            whole = hang_skirt(whole, envelope, person.rig, False)
        var feet = List[FootLast]()
        if garment.form == SHOD:
            feet = foot_lasts(whole, person.rig)
            whole = shoe(whole, feet, person.rig)
        if garment.form == BANDED:
            # A band's cover, smoothed over a coarse skin, can stay under
            # one half everywhere, so its piece is cut at half its peak.
            var peak = Float32(1.0e-6)
            for v in range(count):  # pragma: no branch
                peak = max(peak, values[i][v])
            var scaled = List[Float32](capacity=count)
            for v in range(count):  # pragma: no branch
                scaled.append(values[i][v] / peak)
            whole = belt_band(
                garment_piece(skin, places[i], everything, nothing),
                garment_piece(skin, places[i], scaled, nothing),
                person.rig,
                Float32(fabric(garment.fabric).thickness.value),
            )
        if garment.form == DOMED:
            whole = dome_shoulders(
                whole,
                person.rig,
                Float32(fabric(garment.fabric).thickness.value),
            )
        if garment.form == HATTED:
            whole = hat_mesh(
                whole,
                person.rig,
                garment.headwear,
                Float32(fabric(garment.fabric).thickness.value),
                detail,
            )
        var head = List[FootLast]()
        if garment.form == COWLED:
            head = head_cowl(whole, person.rig)
            whole = hang_cowl(
                whole,
                head,
                person.rig,
                garment.cover.face_open,
                Float32(fabric(garment.fabric).thickness.value),
            )
        shells[order[i]] = whole^
        skirts.append(envelope^)
        lasts.append(feet^)
        cowls.append(head^)
    for i in range(len(order)):
        var over = List[Float32](length=count, fill=0)
        # A skirt over this one that falls as far hides its skirt, and a
        # last over this one hides its lasts.
        var shown = True
        var feet = lasts[i].copy()
        for j in range(i + 1, len(order)):
            for v in range(count):
                over[v] = max(over[v], hides[j][v])
            if skirts[j].rings() > 1 and skirts[j].hem() <= skirts[i].hem():
                shown = False
            if len(lasts[j]) > 0:
                feet.clear()
        for v in range(count):
            over_skin[v] = max(over_skin[v], hides[i][v])
        ref garment = outfit.garments[order[i]]
        # A band, a hat and a dome are drawn whole, over what lies under
        # them.
        if (
            garment.form == BANDED
            or garment.form == HATTED
            or garment.form == DOMED
        ):
            pieces[order[i]] = shells[order[i]].clone()
            continue
        var piece = hang_skirt(
            garment_piece(skin, places[i], values[i], over),
            skirts[i],
            person.rig,
            True,
            shown,
        )
        piece = shoe(piece, feet, person.rig)
        pieces[order[i]] = hang_cowl(
            piece,
            cowls[i],
            person.rig,
            garment.cover.face_open,
            Float32(fabric(garment.fabric).thickness.value),
        )
    return pieces^


def _gather(mut joined: Optional[BufferGeometry], piece: BufferGeometry) raises:
    """Join a piece onto what was gathered, if it has any triangles."""
    if piece.triangle_count() == 0:
        return
    if joined:
        joined = merge(joined.value(), piece)
    else:
        joined = piece.clone()


def _cut_shell(
    mut scene: Scene, mut assets: Assets, node: NodeId, band: Float32
) raises:
    """Cut a hair shell's mesh level at a hat's band, keeping what lies
    under it."""
    for mesh in scene.meshes:  # pragma: no branch
        if mesh.node != node:
            continue
        var shell = assets.geometries.get(mesh.geometry).clone()
        var under = List[Float32](capacity=shell.vertex_count())
        ref placed = shell.attribute_view(String(POSITION))
        for v in range(placed.count()):  # pragma: no branch
            under.append(band - placed.vector3(v).y)
        assets.geometries.replace(mesh.geometry, cut(shell, under, 0))


def _press_under_hats(
    mut scene: Scene,
    mut assets: Assets,
    mut person: GameHumanoid,
    outfit: Outfit,
) raises:
    """Lay the person's strands and cards under each hat that keeps the
    hair, and draw them where they now lie."""
    for garment in outfit.garments:
        if garment.form != HATTED:
            continue
        var skin = assets.geometries.get(
            scene.skinned_meshes[person.skins[0]].geometry
        ).clone()
        var places = List[Vector3]()
        ref placed = skin.attribute_view(String(POSITION))
        for v in range(placed.count()):  # pragma: no branch
            places.append(placed.vector3(v))
        var head = garment_piece(
            skin,
            places,
            cover_values(skin, person.rig, garment.cover),
            List[Float32](length=len(places), fill=0),
        )
        var frame = head_frame(head, person.rig)
        # A hat that closes over the head hides the hair's shell over its
        # band, which can stand out of the hat over the ears.
        if person.hair and not garment.headwear.is_open():
            _cut_shell(scene, assets, person.hair.value(), frame.band())
        for k in range(len(person.strands)):
            _ = press_hair(person.strands[k].groom, frame)
            person.strands[k].shade(
                assets,
                List[HairLight](),
                frame.center + Vector3(0, 0, 1),
                Vector3(0.1, 0.1, 0.1),
            )
        for k in range(len(person.cards)):
            _ = press_hair(person.cards[k].groom, frame)
            assets.geometries.replace(
                person.cards[k].geometry, person.cards[k].mesh()
            )


def dress(
    mut scene: Scene,
    mut assets: Assets,
    mut person: GameHumanoid,
    outfit: Outfit,
) raises -> Dressed:
    """Make an outfit for a game humanoid and add it to the scene.

    Each garment becomes a skinned mesh on the person's skeleton, drawn
    with its fabric's look. The person's skin drops the triangles the
    outfit hides fully.

    Args:
        scene: The scene the person is in.
        assets: The store of the person's geometry and materials.
        person: A game humanoid that has not been dressed. Its strands and
            cards are laid under a hat that keeps the hair.
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
    # A garment over the head hides the scalp's hair, but a hat that
    # keeps the hair below its brim does not.
    var hooded = False
    for garment in outfit.garments:
        if garment.cover.covers(HEAD) and not (
            garment.form == HATTED and garment.headwear.keeps_hair()
        ):
            hooded = True
    if not hooded:
        _press_under_hats(scene, assets, person, outfit)
    if hooded:
        if person.hair:
            scene.node(person.hair.value()).visible = False
        if person.beard:
            scene.node(person.beard.value()).visible = False
        for k in range(len(person.strands)):
            if person.strands[k].node:
                scene.node(person.strands[k].node.value()).visible = False
        for k in range(len(person.cards)):
            if person.cards[k].node:
                scene.node(person.cards[k].node.value()).visible = False
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
        # A thick fabric shows its thickness at each hem and at each
        # lame's edge.
        var thick = Float32(fabric(garment.fabric).thickness.value)
        if thick >= RIM_THINNEST:
            piece = add_rim(piece, min(thick, RIM_DEEPEST))
        piece = dye_pattern(piece, person.rig, garment.pattern)
        paint(piece, garment.dyes)
        piece = garment_uvs(piece, person.rig)
        normalize_normals(piece)
        var material = fabric_material(
            garment.fabric, Color(255, 255, 255), garment.metal
        )
        dye_sheen(material, garment.dyes[PRIMARY_DYE.value])
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
