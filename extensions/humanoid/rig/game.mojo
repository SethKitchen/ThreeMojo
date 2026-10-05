# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A humanoid for a game: its skin on a skeleton, ready to animate.

`add_game_humanoid` builds one person's skin, the body's and each
hand's, places a bone at each joint of the rig and binds the skin to
them. The eyes and the scalp's hair hang from the head's bone, so they
turn with it. The bones are scene nodes: an `AnimationMixer` playing
the clips of `extensions.humanoid.rig.clips` moves them, and the skin
follows on the renderer's skinning.

A game can ask for fewer triangles. The skin is then decimated to the
budget, and its colors and thinness are carried over from the nearest
point of the full mesh, which decimation does not keep.

This is not a three.js port. See Extensions.

    var person = add_game_humanoid(scene, assets, root, spec, 20000)
    var mixer = AnimationMixer()
    _ = mixer.add(AnimationAction(walk_clip(person.bones, person.rig)))
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.humanoid.fidelity import (
    CANONICAL_RECIPE,
    FIDELITY_KEY,
    GAME_RECIPE,
    VISUAL_USE,
    HumanoidUse,
    humanoid_provenance,
    require_humanoid_use,
)
from core.user_data import UserData
from extensions.humanoid.rig.joints import (
    HEAD,
    HIPS,
    LEFT_FOREARM,
    LEFT_HAND,
    RIGHT_FOREARM,
    RIGHT_HAND,
    Joint,
    HumanoidRig,
    humanoid_rig,
    joint_label,
    joint_parent,
    named_joints,
)
from extensions.humanoid.rig.game_face import (
    GameFace,
    attach_game_face,
    GAME_FACE_RECIPE,
)
from extensions.humanoid.skeleton.head.expression import face_rig_shapes
from extensions.humanoid.skeleton.head.face_model import TEETH, GUMS_AND_TONGUE
from extensions.humanoid.skeleton.head.skin.mouth import mouth_mesh
from extensions.humanoid.skeleton.isosurface import check_detail
from extensions.humanoid.rig.weights import part_legs, skin_weights
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.arm.assembly import UNSET_PAINT
from extensions.humanoid.skeleton.arm.frame import arm_muscle_dimensions
from extensions.humanoid.skeleton.hand.skin.geometry import (
    hand_skin_from_dimensions,
)
from extensions.humanoid.skeleton.arm.assembly import place_mesh, resolved_paint
from extensions.humanoid.skeleton.complexion import iris_albedo
from extensions.humanoid.skeleton.head.eyes import eyeball_mesh
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.dimensions import SCALP_HAIR
from extensions.humanoid.skeleton.head.hair.geometry import (
    head_hair_from_dimensions,
)
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    add_groom,
)
from extensions.humanoid.skeleton.head.hair.styles import GROWN, HairStyle
from extensions.humanoid.skeleton.head.skin.tint import THINNESS, untinted
from extensions.humanoid.skeleton.look import (
    eye_physical,
    gum_physical,
    teeth_physical,
    hair_phong,
    skin_phong,
)
from extensions.humanoid.skeleton.simplify import simplify
from extensions.humanoid.skeleton.torso.body import (
    body_skin_mesh,
    body_skin_parts,
)
from extensions.humanoid.spec import HumanoidSpec
from materials.material import MaterialId
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SkinnedMesh

# The share of a triangle budget the body's skin takes, and the hair's
# shell; each hand takes half of the rest.
comptime BODY_SHARE = Float32(0.76)
comptime HAIR_SHARE = Float32(0.12)
# Half the slot that parts the legs, so they can swing apart, in meters
# on the template.
comptime LEG_GAP = Float32(0.014)
# How far below the hips the legs part, in meters on the template.
comptime CROTCH = Float32(0.06)
# The cell a nearest point is sought in when carrying colors over, in
# meters.
comptime CARRY_CELL = Float32(0.01)


struct GameHumanoid(Movable):
    """A humanoid in a scene: its rig, its bones and its skinned meshes."""

    var rig: HumanoidRig
    # The node the humanoid stands on, at the pelvis frame's origin.
    var root: NodeId
    # One bone per joint, in the order of the joints.
    var bones: List[NodeId]
    # The skinned meshes: the body, the right hand and the left.
    var skins: List[Int]
    # The scalp's hair as strands, if any were grown.
    var strands: List[HairStrands]
    # Present only when original facial correspondence was requested.
    var face: Optional[GameFace]

    def __init__(
        out self,
        var rig: HumanoidRig,
        root: NodeId,
        var bones: List[NodeId],
        var skins: List[Int],
        var strands: List[HairStrands],
        var face: Optional[GameFace] = None,
    ):
        """Hold a humanoid's parts.

        Args:
            rig: Its rig.
            root: The node it stands on.
            bones: One node per joint.
            skins: Its skinned meshes' indices in the scene.
            strands: Its hair's strands, or none.
            face: Preserved face and mouth binding, or no facial animation.
        """
        self.rig = rig^
        self.root = root
        self.bones = bones^
        self.skins = skins^
        self.strands = strands^
        self.face = face^


def _key(p: Vector3) -> Int:
    """Return the cell of the grid a point falls in, as one integer."""
    var i = Int(p.x / CARRY_CELL + 4096)
    var j = Int(p.y / CARRY_CELL + 4096)
    var k = Int(p.z / CARRY_CELL + 4096)
    return (i * 8192 + j) * 8192 + k


def carry_attributes(source: BufferGeometry, mut target: BufferGeometry) raises:
    """Give a decimated mesh the colors and the thinness of the mesh it
    was decimated from, each vertex those of the nearest source vertex.

    Args:
        source: The full mesh, with `position` and any of `color` and
            `thinness`.
        target: The decimated mesh, in the same frame.

    Raises:
        Error: If either mesh has no positions, or a nonempty target
            has no source vertices.
    """
    ref from_points = source.attribute_view(String(POSITION))
    ref to_points = target.attribute_view(String(POSITION))
    if from_points.count() == 0 and to_points.count() > 0:
        raise Error("Attribute transfer needs source vertices")
    var cells = Dict[Int, List[Int]]()
    for v in range(from_points.count()):
        var key = _key(from_points.vector3(v))
        if key not in cells:
            cells[key] = List[Int]()
        cells[key].append(v)
    var nearest = List[Int](capacity=to_points.count())
    for v in range(to_points.count()):
        var p = to_points.vector3(v)
        var best = 0
        var closest = Float32(1e30)
        var ring = 1
        while True:
            for dx in range(-ring, ring + 1):  # pragma: no branch
                for dy in range(-ring, ring + 1):  # pragma: no branch
                    for dz in range(-ring, ring + 1):  # pragma: no branch
                        if (
                            ring > 1
                            and max(abs(dx), max(abs(dy), abs(dz))) < ring
                        ):
                            continue
                        var key = _key(
                            p
                            + Vector3(
                                Float32(dx) * CARRY_CELL,
                                Float32(dy) * CARRY_CELL,
                                Float32(dz) * CARRY_CELL,
                            )
                        )
                        if key not in cells:
                            continue
                        for s in cells[key]:  # pragma: no branch
                            var d = (from_points.vector3(s) - p).length()
                            if d < closest:
                                closest = d
                                best = s
            # An unvisited cell is at least this far away. Leave one
            # extra cell for the grid key's floating-point rounding.
            if closest <= Float32(ring - 1) * CARRY_CELL:
                break
            ring += 1
        nearest.append(best)
    var names: List[String] = [String(COLOR), String(THINNESS)]
    for name in names:  # pragma: no branch
        if not source.has_attribute(name):
            continue
        ref values = source.attribute_view(name)
        var size = values.item_size
        var data = List[Float32](capacity=size * len(nearest))
        for v in range(len(nearest)):
            for c in range(size):  # pragma: no branch
                data.append(values.component(nearest[v], c))
        target.set_attribute(name, BufferAttribute(data^, size))


def _outline(mut points: List[Float32], mesh: BufferGeometry) raises:
    """Append a mesh's positions to a flat list of points."""
    ref placed = mesh.attribute_view(String(POSITION))
    for v in range(placed.count()):  # pragma: no branch
        var p = placed.vector3(v)
        points.append(p.x)
        points.append(p.y)
        points.append(p.z)


def _budgeted(
    var mesh: BufferGeometry, triangles: Int
) raises -> BufferGeometry:
    """Return `mesh` decimated to `triangles`, its colors carried over, or
    as it is if it is already within the budget or there is none."""
    if triangles <= 0 or mesh.triangle_count() <= triangles:
        return mesh^
    var fewer = simplify(mesh, triangles)
    # Hair shells have neither attribute. Do not build a nearest-vertex
    # map when there is no color or thinness to transfer.
    if mesh.has_attribute(String(COLOR)) or mesh.has_attribute(
        String(THINNESS)
    ):
        carry_attributes(mesh, fewer)
    return fewer^


comptime _FACIAL_PART_MINIMUM = 4 * 32


def add_game_humanoid(
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
    spec: HumanoidSpec,
    triangles: Int = 0,
    detail: Int = 56,
    hand_detail: Int = 24,
    hair_detail: Int = 32,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
    eye_paint: MaterialId = UNSET_PAINT,
    hair_style: HairStyle = GROWN,
    guides: Int = 0,
    followers: Int = 0,
    workers: Int = 1,
    use: HumanoidUse = VISUAL_USE,
    facial_animation: Bool = False,
) raises -> GameHumanoid:
    """Build one person's skin on a skeleton under `parent`.

    Args:
        scene: The scene that receives the bones and the meshes.
        assets: The store for their geometry and materials.
        parent: The node the humanoid stands on; its origin is the
            pelvis frame's.
        spec: Standing height, osteological sex, athleticism and genome.
        triangles: The skin's budget of triangles, or zero for the full
            mesh. A positive facial budget below 128 is refused before
            geometry is built; the face and eyes require additional triangles.
        detail: Cells along the body's skin, eight through sixty-four.
        hand_detail: Cells along each hand's skin.
        hair_detail: Cells along the head for the hair's shell.
        skin_paint: Skin look, or a tinted Phong in the genome's tone.
        hair_paint: Hair look, or the default in the genome's color.
        eye_paint: Eye look, or the default.
        hair_style: How the hair is cut and laid.
        guides: Guide strands of hair to grow, or none for the hair's
            shell alone.
        followers: Follow strands round each guide.
        workers: How many threads mesh the skin.
        use: Visual use only. Engineering use is refused before scene edits.
        facial_animation: Keep original face, teeth and gums/tongue under HEAD.
            The total mesh budget then includes those parts and both eyes.
            Insufficient budgets raise instead of dropping targets or exceeding it.

    Returns:
        The humanoid: its rig, its bones and its meshes.

    Raises:
        Error: If the spec, a detail, style or visual use is refused; if
            the budget is negative or cannot preserve the facial and body
            requirements; if facial animation requests strand guides; or if
            a scene node, mesh or geometry operation fails.
    """
    require_humanoid_use(use)
    var settings = game_build_settings(
        triangles,
        detail,
        hand_detail,
        hair_detail,
        hair_style,
        guides,
        followers,
        skin_paint,
        hair_paint,
        eye_paint,
        facial_animation,
    )
    var node = Object3D()
    node.user_data.set_json(
        String(FIDELITY_KEY),
        humanoid_provenance(
            spec,
            settings,
            String(CANONICAL_RECIPE),
            String(GAME_RECIPE),
            "unverified-converted-ICTF-THRS",
        ).to_json(),
    )
    var gap = LEG_GAP * Float32(spec.stature.value) / 1.8288
    var body: BufferGeometry
    var facial_meshes = List[BufferGeometry]()
    var dims = head_muscle_dimensions(spec)
    if facial_animation and triangles > 0 and triangles < _FACIAL_PART_MINIMUM:
        # Every positive facial budget already reserves 32 triangles each
        # for the body, both hands, and hair before adding the face and eyes.
        # Preserve cheap argument checks before refusing this impossible case.
        check_detail(detail, "body skin")
        check_detail(hair_detail, "scalp hair")
        check_detail(hand_detail, "hand skin")
        raise Error(
            "Facial LOD budget must keep at least "
            + String(_FACIAL_PART_MINIMUM)
            + " triangles before the face and eyes"
        )
    if facial_animation:
        var shapes = face_rig_shapes()
        var split = body_skin_parts(spec, detail, workers, gap, shapes)
        body = split.pop(0)
        facial_meshes.append(split.pop(0))
        facial_meshes.append(mouth_mesh(dims, TEETH, shapes))
        facial_meshes.append(mouth_mesh(dims, GUMS_AND_TONGUE, shapes))
    else:
        body = body_skin_mesh(spec, detail, workers, gap)
    var shell = head_hair_from_dimensions(
        dims, SCALP_HAIR, RIGHT, hair_detail, workers, hair_style
    )
    var eyes = List[BufferGeometry]()
    for side in [RIGHT, LEFT]:
        eyes.append(eyeball_mesh(dims, side, 12))
    var arms = arm_muscle_dimensions(spec)
    var right = hand_skin_from_dimensions(arms, RIGHT, hand_detail)
    var left = hand_skin_from_dimensions(arms, LEFT, hand_detail)
    untinted(right)
    untinted(left)
    # The rig reads the crown, the fingertips and the toes off the skin.
    var outline = List[Float32]()
    _outline(outline, body)
    if facial_animation:
        _outline(outline, facial_meshes[0])
    _outline(outline, right)
    _outline(outline, left)
    var whole = BufferGeometry()
    whole.set_attribute(String(POSITION), BufferAttribute(outline^, 3))
    var rig = humanoid_rig(spec, whole)
    var remaining = triangles
    var reserve = 0
    if facial_animation and triangles > 0:
        for i in range(len(facial_meshes)):
            reserve += facial_meshes[i].triangle_count()
        for i in range(len(eyes)):
            reserve += eyes[i].triangle_count()
        # Preserve the complete facial submesh and reserve 32 per body,
        # hand and hair part. Safe-collapse limits can require more.
        if triangles < reserve + _FACIAL_PART_MINIMUM:
            raise Error(
                "Facial LOD budget must keep at least "
                + String(reserve + _FACIAL_PART_MINIMUM)
                + " triangles"
            )
        remaining = triangles - reserve - _FACIAL_PART_MINIMUM
    var body_budget = Int(Float32(remaining) * BODY_SHARE)
    var hand_budget = Int(
        Float32(remaining) * (1 - BODY_SHARE - HAIR_SHARE) / 2
    )
    var hair_budget = Int(Float32(remaining) * HAIR_SHARE)
    if facial_animation and triangles > 0:
        body_budget += 32
        hand_budget += 32
        hair_budget += 32
    elif triangles > 0:
        hair_budget = max(1, hair_budget)
    var parts = List[BufferGeometry]()
    if facial_animation and triangles > 0:
        # Establish the hands' and shell's actual counts before reducing
        # the body. A protected hair shell can exceed its nominal share.
        # Giving the body the actual remainder avoids a second body
        # decimation and attribute-transfer pass in the usual case.
        shell = _budgeted(shell^, hair_budget)
        right = _budgeted(right^, hand_budget)
        left = _budgeted(left^, hand_budget)
        body_budget = max(
            32,
            triangles
            - reserve
            - shell.triangle_count()
            - right.triangle_count()
            - left.triangle_count(),
        )
        parts.append(_budgeted(body^, body_budget))
        parts.append(right^)
        parts.append(left^)
    else:
        parts.append(_budgeted(body^, body_budget))
        parts.append(_budgeted(right^, hand_budget))
        parts.append(_budgeted(left^, hand_budget))
        shell = _budgeted(shell^, hair_budget)
    if facial_animation and triangles > 0:
        var retained = reserve + shell.triangle_count()
        for i in range(len(parts)):
            retained += parts[i].triangle_count()
        # A part can exceed its initial share at a safe-collapse limit.
        # Reclaim that excess from parts that can still shrink before
        # refusing the total budget. The face and eyes are never touched.
        for i in range(len(parts)):
            if retained <= triangles:
                break
            var before = parts[i].triangle_count()
            var target = max(32, before - (retained - triangles))
            var reduced = _budgeted(parts[i].clone(), target)
            retained += reduced.triangle_count() - before
            parts[i] = reduced^
        if retained > triangles:
            var before = shell.triangle_count()
            var target = max(32, before - (retained - triangles))
            shell = _budgeted(shell^, target)
            retained += shell.triangle_count() - before
        if retained > triangles:
            raise Error(
                "Facial LOD safe-collapse limit exceeds budget: retained "
                + String(retained)
                + ", requested "
                + String(triangles)
            )
    var root = scene.attach(node^, parent)
    # A bone at each joint, each hung from its parent's.
    var bones = List[NodeId]()
    for joint in named_joints():  # pragma: no branch
        var node = Object3D()
        node.name = joint_label(joint)
        var at = rig.local(joint)
        node.set_position(at.x, at.y, at.z)
        var hang = root
        if joint != HIPS:
            hang = bones[joint_parent(joint).value]
        bones.append(scene.attach(node^, hang))
    scene.update()
    var placed = List[Matrix4]()
    for bone in bones:  # pragma: no branch
        placed.append(scene.world_matrix(bone))
    var skeleton = bind_skeleton(bones, placed)
    var skin = skin_paint
    if skin.value < 0:
        skin = assets.materials.add(skin_phong(genome=spec.genome, tinted=True))
    var skins = List[Int]()
    # The hands' own meshes draw the hands: the body's skin is turned by
    # every joint but theirs, and each hand only by its own forearm and
    # hand.
    var allowed = List[List[Joint]]()
    var body_joints = List[Joint]()
    for joint in named_joints():  # pragma: no branch
        if joint != RIGHT_HAND and joint != LEFT_HAND:
            body_joints.append(joint)
    allowed.append(body_joints^)
    allowed.append([RIGHT_FOREARM, RIGHT_HAND])
    allowed.append([LEFT_FOREARM, LEFT_HAND])
    for k in range(3):  # pragma: no branch
        var part = parts.pop(0)
        skin_weights(part, rig, allowed[k])
        if k == 0:
            part_legs(part, rig.at(HIPS).y - CROTCH * rig.stature / 1.8288)
        skins.append(len(scene.skinned_meshes))
        scene.add_skinned_mesh(
            SkinnedMesh(
                assets.geometries.add(part^),
                skin,
                root,
                skeleton.copy(),
                scene.world_matrix(root),
            )
        )
    # The eyes and the hair turn with the head: they hang from its bone,
    # moved back by where it stands, so they keep the pelvis frame.
    var holder = Object3D()
    var head = rig.at(HEAD)
    holder.set_position(-head.x, -head.y, -head.z)
    var holder_id = scene.attach(holder^, bones[HEAD.value])
    var hair = resolved_paint(assets, hair_paint, hair_phong(spec.genome))
    place_mesh(scene, assets, holder_id, shell^, hair)
    var face = Optional[GameFace](None)
    if facial_animation:
        var paints = List[MaterialId]()
        paints.append(skin)
        paints.append(assets.materials.add(teeth_physical()))
        paints.append(assets.materials.add(gum_physical()))
        face = attach_game_face(
            scene, assets, holder_id, facial_meshes^, paints
        )
    var eye = eye_paint
    if eye.value < 0:
        var iris = assets.textures.add(iris_albedo(64, spec.genome))
        eye = assets.materials.add(eye_physical(iris))
    for _ in range(2):  # pragma: no branch
        place_mesh(scene, assets, holder_id, eyes.pop(0), eye)
    var strands = List[HairStrands]()
    if guides > 0:
        strands.append(
            add_groom(
                scene,
                assets,
                holder_id,
                spec,
                guides,
                followers,
                style=hair_style,
            )
        )
    return GameHumanoid(rig^, root, bones^, skins^, strands^, face^)


def game_build_settings(
    triangles: Int = 0,
    detail: Int = 56,
    hand_detail: Int = 24,
    hair_detail: Int = 32,
    hair_style: HairStyle = GROWN,
    guides: Int = 0,
    followers: Int = 0,
    skin_paint: MaterialId = UNSET_PAINT,
    hair_paint: MaterialId = UNSET_PAINT,
    eye_paint: MaterialId = UNSET_PAINT,
    facial_animation: Bool = False,
) raises -> UserData:
    """Record every game-builder option that changes a visual recipe.

    Material IDs refer to the caller's asset store. This is not a material
    content digest. Worker count changes execution, not the visual recipe.

    Args:
        triangles: Triangle budget.
        detail: Body sampling detail.
        hand_detail: Hand sampling detail.
        hair_detail: Hair sampling detail.
        hair_style: Named hair style.
        guides: Guide count.
        followers: Follower count.
        skin_paint: Skin material ID, or the default sentinel.
        hair_paint: Hair material ID, or the default sentinel.
        eye_paint: Eye material ID, or the default sentinel.
        facial_animation: Preserve original face correspondence for audio playback.

    Returns:
        A value snapshot independent of the canonical spec.

    Raises:
        Error: If the hair style is unnamed, the triangle budget is
            negative, or facial animation requests guide strands.
    """
    if triangles < 0:
        raise Error("Game triangle budget must be nonnegative")
    if facial_animation and guides > 0:
        raise Error(
            "Facial triangle budgets do not support strand hair; use the shell"
        )
    if not hair_style.is_valid():
        raise Error("Game build settings require a named hair style")
    var settings = UserData()
    if facial_animation:
        settings.set_string("facial_recipe", String(GAME_FACE_RECIPE))
    settings.set_string("triangles", String(triangles))
    settings.set_string("body_detail", String(detail))
    settings.set_string("hand_detail", String(hand_detail))
    settings.set_string("hair_detail", String(hair_detail))
    settings.set_string("hair_style", String(hair_style.value))
    settings.set_string("guides", String(guides))
    settings.set_string("followers", String(followers))
    settings.set_string("skin_material_id", String(skin_paint.value))
    settings.set_string("hair_material_id", String(hair_paint.value))
    settings.set_string("eye_material_id", String(eye_paint.value))
    settings.set_number("leg_gap_m_at_template_stature", Float64(LEG_GAP))
    settings.set_number("crotch_m_at_template_stature", Float64(CROTCH))
    return settings^
