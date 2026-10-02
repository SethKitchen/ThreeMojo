# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for how a genome shapes the frame, the head and the face, and
for the eyes, the lids, the ears, the skin's tint and the hair."""

from core.assets import Assets
from core.buffer_geometry import COLOR, POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import (
    ARM_LENGTH,
    BROW_ARCH,
    BROW_HEIGHT,
    BROW_RIDGE,
    BROW_THICKNESS,
    CHEEKBONES,
    CHEST_DEPTH,
    CHIN,
    EAR_LOBE,
    EAR_PROTRUSION,
    EAR_SIZE,
    EYE_DEPTH,
    EYE_SIZE,
    EYE_SPACING,
    EYE_TILT,
    FACE_SHAPE_1,
    FACE_SHAPE_2,
    FACE_SHAPES,
    Expression,
    Gene,
    Genome,
    HAIR_LENGTH,
    HEAD_HEIGHT,
    HEAD_LENGTH,
    HEAD_WIDTH,
    JAW_WIDTH,
    LIP_FULLNESS,
    MELANIN,
    MOUTH_WIDTH,
    NECK_LENGTH,
    NOSE_BRIDGE,
    NOSE_LENGTH,
    NOSE_PROJECTION,
    NOSE_WIDTH,
    SHOULDER_BREADTH,
)
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.frame import arm_dimensions, arm_frame
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import EYES, HAIR, SKIN
from extensions.humanoid.skeleton.head.eyes import (
    EYEBALL_RADIUS,
    eye_center,
    eye_radius,
    eyeball_mesh,
)
from extensions.humanoid.skeleton.head.frame import (
    head_dimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.hair.dimensions import (
    EYEBROWS,
    SCALP_HAIR,
    HairShape,
    head_hair_field,
)
from extensions.humanoid.skeleton.head.skin.dimensions import (
    EyeLids,
    HeadSkinField,
)
from extensions.humanoid.skeleton.head.skin.scan import ear_weight, warp_ear
from extensions.humanoid.skeleton.head.skin.geometry import (
    head_skin_from_dimensions,
)
from extensions.humanoid.skeleton.head.skin.tint import (
    _Brows,
    tint_head_skin,
    untinted,
)
from extensions.humanoid.skeleton.head.face_model import (
    FACE_MODEL_PATH,
    FaceModel,
    LEFT_EYEBALL,
    RIGHT_EYEBALL,
)
from extensions.humanoid.skeleton.head.skin.scan import scan_to_template
from extensions.humanoid.skeleton.morph import (
    IDENTITY_SPREAD,
    HeadMorph,
    bump,
    smoothstep,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    shoulder_girdle,
    torso_dimensions,
)
from materials.material import MaterialId
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def _one(gene: Gene, value: Float32) raises -> Genome:
    return Genome().with_gene(gene, Expression(value))


def _broken() -> Genome:
    var genome = Genome()
    genome.expressions[3] = 7
    return genome


def _person(genome: Genome = Genome(), sex: Sex = MALE) -> HumanoidSpec:
    return HumanoidSpec(Length(6.0, FOOT), sex, TONED, genome)


def _moved(gene: Gene, value: Float32, point: Vector3) raises -> Vector3:
    """Return where the morph of one gene moves a template point."""
    return HeadMorph(_one(gene, value)).apply(point)


def test_helpers() raises:
    assert_equal(smoothstep(0, 1, -1), 0)
    assert_equal(smoothstep(0, 1, 2), 1)
    assert_equal(smoothstep(0, 1, 0.5), 0.5)
    assert_equal(bump(Vector3(0, 0, 0), Vector3(0, 0, 0), 1), 1)
    assert_equal(bump(Vector3(2, 0, 0), Vector3(0, 0, 0), 1), 0)


def test_the_template_morph_is_the_identity() raises:
    var p = Vector3(1.2, 70.0, 9.0)
    assert_true(HeadMorph().apply(p) == p)
    var template = HeadMorph(Genome())
    assert_false(template.active)
    assert_true(template.apply(p) == p)
    assert_equal(template.eye_scale(), 1)
    assert_equal(template.lip_scale(), 1)
    # The female template is itself a morph of the male one.
    var female = HeadMorph(Genome(), FEMALE)
    assert_true(female.active)
    assert_true(female.brow_ridge < 0)
    with assert_raises(contains="head"):
        _ = HeadMorph(_broken())
    # Below the neck's base the morph leaves every point alone.
    var low = Vector3(4.0, 40.0, 2.0)
    assert_true(HeadMorph(_one(NECK_LENGTH, 1)).apply(low) == low)


def test_each_face_gene_moves_its_feature() raises:
    var tip = Vector3(0, 68.9, 10.5)
    assert_true(_moved(NOSE_LENGTH, 1, tip).y < tip.y)
    assert_true(_moved(NOSE_PROJECTION, 1, tip).z > tip.z)
    var wing = Vector3(1.2, 68.3, 9.5)
    assert_true(_moved(NOSE_WIDTH, 1, wing).x > wing.x)
    var bridge = Vector3(0, 72.2, 9.1)
    assert_true(_moved(NOSE_BRIDGE, 1, bridge).z > bridge.z)
    var corner = Vector3(2.3, 64.7, 8.3)
    assert_true(_moved(MOUTH_WIDTH, 1, corner).x > corner.x)
    var lip = Vector3(0, 65.1, 9.5)
    assert_true(_moved(LIP_FULLNESS, 1, lip).y > lip.y)
    assert_true(HeadMorph(_one(LIP_FULLNESS, 1)).lip_scale() > 1)
    var chin = Vector3(0, 61.2, 8.0)
    assert_true(_moved(CHIN, 1, chin).z > chin.z)
    var angle = Vector3(5.0, 63.8, 0.2)
    assert_true(_moved(JAW_WIDTH, 1, angle).x > angle.x)
    assert_true(_moved(JAW_WIDTH, 1, Vector3(-5.0, 63.8, 0.2)).x < -5.0)
    var cheek = Vector3(5.2, 70.4, 5.6)
    assert_true(_moved(CHEEKBONES, 1, cheek).x > cheek.x)
    var brow = Vector3(2.6, 74.6, 8.6)
    assert_true(_moved(BROW_RIDGE, 1, brow).z > brow.z)
    assert_true(_moved(BROW_HEIGHT, 1, brow).y > brow.y)
    assert_true(_moved(BROW_ARCH, 1, Vector3(2.6, 74.8, 8.8)).y > 74.8)


def test_each_eye_gene_moves_the_eye() raises:
    var right = Vector3(3.2, 72.1, 7.4)
    var edge = Vector3(4.4, 72.1, 7.4)
    assert_true(_moved(EYE_SIZE, 1, edge).x > edge.x)
    assert_true(HeadMorph(_one(EYE_SIZE, 1)).eye_scale() > 1)
    assert_true(_moved(EYE_SPACING, 1, right).x > right.x)
    assert_true(_moved(EYE_SPACING, 1, Vector3(-3.2, 72.1, 7.4)).x < -3.2)
    # A lifted outer corner, and a deep-set eye.
    assert_true(_moved(EYE_TILT, 1, edge).y > edge.y)
    assert_true(_moved(EYE_DEPTH, 1, right).z < right.z)
    var morph = HeadMorph(_one(EYE_SPACING, 1))
    assert_true(morph.eye_center(1).x > 3.2)
    assert_true(morph.eye_center(-1).x < -3.2)


def test_face_shape_genes_weigh_the_face_models_modes() raises:
    var morph = HeadMorph(_one(FACE_SHAPE_2, -0.5))
    var weights = morph.identity_weights(10)
    assert_equal(len(weights), 10)
    assert_equal(weights[1], -0.5 * IDENTITY_SPREAD)
    assert_equal(weights[0], 0)
    assert_equal(weights[FACE_SHAPES], 0)
    assert_equal(len(morph.identity_weights(1)), 1)
    assert_true(HeadMorph().eye_shift(1) == Vector3(0, 0, 0))
    # Each eyeball moves as the face model's eyeball moves: the mean of
    # its vertices, the one at plus x on the right.
    var model = FaceModel(FACE_MODEL_PATH, FACE_SHAPES, False)
    var mean = model.shape(model.no_identity(), model.no_expression())
    for mode in range(FACE_SHAPES):  # pragma: no branch
        var identity = model.no_identity()
        identity[mode] = 1
        var shaped = model.shape(identity, model.no_expression())
        var genome = _one(FACE_SHAPE_1, 0)
        genome.expressions[FACE_SHAPE_1.value + mode] = 1 / IDENTITY_SPREAD
        var shift = HeadMorph(genome).eye_shift(1)
        var sum = Vector3(0, 0, 0)
        for v in range(
            LEFT_EYEBALL.first, LEFT_EYEBALL.end
        ):  # pragma: no branch
            sum = sum + (
                scan_to_template(shaped[v]) - scan_to_template(mean[v])
            )
        var measured = sum * (
            Float32(1) / Float32(LEFT_EYEBALL.end - LEFT_EYEBALL.first)
        )
        assert_true((measured - shift).length() < 1e-3)
        var left = HeadMorph(genome).eye_shift(-1)
        assert_true(abs(left.x + shift.x) < 1e-6)
    assert_true(RIGHT_EYEBALL.first == LEFT_EYEBALL.end)


def test_head_genes_reshape_the_cranium() raises:
    var side = Vector3(8.0, 75.0, -1.0)
    assert_true(_moved(HEAD_WIDTH, 1, side).x > side.x)
    var back = Vector3(0, 75.0, -11.0)
    assert_true(_moved(HEAD_LENGTH, 1, back).z < back.z)
    var top = Vector3(0, 84.4, -1.0)
    assert_true(_moved(HEAD_HEIGHT, 1, top).y > top.y)
    assert_true(_moved(NECK_LENGTH, 1, top).y > top.y)
    var scale = HeadMorph(_one(HEAD_WIDTH, -1)).cranium_scale()
    assert_true(scale.x < 1 and scale.y == 1 and scale.z == 1)
    # The frame carries the morph: the head's top rises with the neck.
    var plain = head_dimensions(Length(6.0, FOOT), MALE)
    var long = head_dimensions(Length(6.0, FOOT), MALE, _one(NECK_LENGTH, 1))
    assert_true(long.at(0, 84.4, -1).y > plain.at(0, 84.4, -1).y)
    assert_true(long.cranium(8, 9, 10).y == plain.cranium(8, 9, 10).y)
    var wide = head_dimensions(Length(6.0, FOOT), MALE, _one(HEAD_WIDTH, 1))
    assert_true(wide.cranium(8, 9, 10).x > plain.cranium(8, 9, 10).x)
    with assert_raises(contains="gene"):
        _ = head_dimensions(Length(6.0, FOOT), MALE, _broken())


def test_frame_genes_move_the_skeleton() raises:
    var stature = Length(6.0, FOOT)
    var plain = torso_dimensions(stature, MALE)
    var broad = torso_dimensions(stature, MALE, _one(SHOULDER_BREADTH, 1))
    assert_true(
        shoulder_girdle(broad).acromion.x > shoulder_girdle(plain).acromion.x
    )
    # The waist, low in the frame, keeps its width.
    assert_true(
        abs(broad.frame.at(10, 12, 0).x - plain.frame.at(10, 12, 0).x) < 1e-5
    )
    var deep = torso_dimensions(stature, MALE, _one(CHEST_DEPTH, 1))
    assert_true(deep.frame.at(0, 36, 9).z > plain.frame.at(0, 36, 9).z)
    var long = arm_dimensions(stature, MALE, _one(ARM_LENGTH, 1))
    var short = arm_dimensions(stature, MALE)
    assert_true(long.frame.wrist.y < short.frame.wrist.y)
    assert_true(long.frame.reach > 1)
    with assert_raises(contains="torso"):
        _ = torso_dimensions(stature, MALE, _broken())
    var bad = plain.copy()
    bad.genome = _broken()
    with assert_raises(contains="torso"):
        bad.validate()
    with assert_raises(contains="arm"):
        _ = arm_frame(bad)


def test_eyes() raises:
    var dims = head_muscle_dimensions(_person())
    var right = eye_center(dims.head, RIGHT)
    var left = eye_center(dims.head, LEFT)
    assert_true(right.x > 0 and abs(right.x + left.x) < 1e-5)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = eye_center(dims.head, BodySide(5))
    assert_true(
        abs(eye_radius(dims.head) - dims.head.cm(EYEBALL_RADIUS)) < 1e-6
    )
    var big = head_muscle_dimensions(_person(_one(EYE_SIZE, 1)))
    assert_true(eye_radius(big.head) > eye_radius(dims.head))
    var mesh = eyeball_mesh(dims, RIGHT, 8)
    assert_equal(mesh.triangle_count(), 8 * 16 * 2 - 2 * 16)
    # The cornea stands proud of the sphere at the front.
    ref points = mesh.attribute_view(String(POSITION))
    var front = points.vector3(0)
    assert_true(front.z - right.z > eye_radius(dims.head))
    with assert_raises(contains="at least eight"):
        _ = eyeball_mesh(dims, RIGHT, 7)
    with assert_raises(contains="sixty-four"):
        _ = eyeball_mesh(dims, RIGHT, 65)


def test_lids_open_on_the_eye() raises:
    var dims = head_muscle_dimensions(_person())
    var h = dims.head.copy()
    var lids = EyeLids(h)
    var skin = HeadSkinField(dims)
    var eye = eye_center(h, RIGHT)
    var r = eye_radius(h)
    # In front of the pupil the slit is open: air.
    assert_true(skin.distance(eye + Vector3(0, 0, r + h.cm(0.1))) > 0)
    # Above the slit the upper lid covers the eyeball.
    var shell = r + h.cm(0.19)
    var lid = eye + Vector3(0, shell * 0.64, shell * 0.77)
    assert_true(lids.distance(lid) < 0)
    # Far off, the lids are far.
    assert_true(lids.distance(eye + Vector3(0, 0, 0.2)) > 0.1)
    var left = eye_center(h, LEFT)
    assert_true(
        lids.distance(left + Vector3(0, shell * 0.64, shell * 0.77)) < 0
    )
    # Behind the eyeball's equator there are no lids.
    assert_true(lids.distance(eye + Vector3(0, r + h.cm(0.2), -h.cm(0.5))) > 0)


def test_ears_follow_their_genes() raises:
    # The ear genes move the auricle and leave the head alone.
    var rim = Vector3(8.8, 72.0, -3.0)
    assert_true(ear_weight(rim) > 0.5)
    var crown = Vector3(0, 80.0, 0)
    assert_equal(ear_weight(crown), 0)
    assert_equal(warp_ear(crown, 1, 1, 1).y, crown.y)
    # Its back edge stands out, on either side.
    assert_true(warp_ear(rim, 0, 1, 0).x > rim.x)
    var left = Vector3(-rim.x, rim.y, rim.z)
    assert_true(warp_ear(left, 0, 1, 0).x < left.x)
    # A larger ear reaches farther from its root; a longer lobe hangs.
    assert_true(warp_ear(rim, 1, 0, 0).x > rim.x)
    var lobe = Vector3(7.9, 66.8, -1.2)
    assert_true(warp_ear(lobe, 0, 0, 1).y < lobe.y)
    var big = HeadSkinField(head_muscle_dimensions(_person(_one(EAR_SIZE, 1))))
    var small = HeadSkinField(
        head_muscle_dimensions(_person(_one(EAR_SIZE, -1)))
    )
    assert_true(
        big.ears.high.y - big.ears.low.y > small.ears.high.y - small.ears.low.y
    )
    var lobes = HeadSkinField(
        head_muscle_dimensions(_person(_one(EAR_LOBE, 1)))
    )
    assert_true(
        lobes.ears.low.y
        < HeadSkinField(head_muscle_dimensions(_person())).ears.low.y
    )
    var out = HeadSkinField(
        head_muscle_dimensions(_person(_one(EAR_PROTRUSION, 1)))
    )
    assert_true(out.ears.high.x > small.ears.high.x)


def test_the_skin_is_tinted() raises:
    var dims = head_muscle_dimensions(_person())
    var skin = head_skin_from_dimensions(dims, 8)
    assert_true(skin.has_attribute(String(COLOR)))
    ref colors = skin.attribute_view(String(COLOR))
    ref points = skin.attribute_view(String(POSITION))
    var h = dims.head.copy()
    var lips = h.at(0, 65.6, 10.8)
    var brow = h.at(0, 78.0, 9.0)
    var lip_red = Float32(0)
    var brow_red = Float32(0)
    var near_lip = Float32(1)
    var near_brow = Float32(1)
    for index in range(points.count()):  # pragma: no branch
        var p = points.vector3(index)
        var c = colors.vector3(index)
        if (p - lips).length() < near_lip:
            near_lip = (p - lips).length()
            lip_red = c.x - c.y
        if (p - brow).length() < near_brow:
            near_brow = (p - brow).length()
            brow_red = c.x - c.y
    assert_true(lip_red > brow_red + 0.1)
    # A woman's skin has no beard's shadow; a dark skin's lips are
    # darker.
    var her = head_muscle_dimensions(_person(Genome(), FEMALE))
    var hers = head_skin_from_dimensions(her, 8)
    assert_true(hers.has_attribute(String(COLOR)))
    var dark = head_muscle_dimensions(_person(_one(MELANIN, 1)))
    tint_head_skin(skin, dark)
    untinted(skin)
    ref white = skin.attribute_view(String(COLOR))
    assert_equal(white.vector3(0).x, 1)
    var bad = dims.copy()
    bad.athleticism.value = 9
    with assert_raises():
        tint_head_skin(skin, bad)


def test_hair_follows_the_skin() raises:
    var dims = head_muscle_dimensions(_person())
    var h = dims.head.copy()
    var scalp = HairShape(dims, SCALP_HAIR, RIGHT)
    var skin = HeadSkinField(dims)
    var top = h.at(0, 84.4, -1.0)
    # Just outside the skin at the crown is hair.
    var crown = top + skin.gradient(top) * h.cm(0.4)
    assert_true(scalp.distance(crown) < 0)
    # Below the sideburns, on the cheek, there is none.
    assert_true(scalp.distance(h.at(6.5, 68.0, 3.0)) > 0)
    assert_true(scalp.high.y > top.y)
    var broad = HairShape(
        head_muscle_dimensions(_person(_one(HEAD_WIDTH, 1))), SCALP_HAIR, RIGHT
    )
    # A broader head's hair reaches farther out at the side.
    var side = h.at(9.2, 77.0, -1.0)
    assert_true(broad.distance(side) < scalp.distance(side))
    # A bob hangs over the nape; a crop is thinner on the crown.
    var nape = h.at(0, 65.0, -10.6)
    assert_true(scalp.distance(nape) > 0)
    var bob = HairShape(
        head_muscle_dimensions(_person(_one(HAIR_LENGTH, 1))), SCALP_HAIR, RIGHT
    )
    assert_true(bob.distance(nape) < 0)
    assert_true(bob.low.y < scalp.low.y)
    # The bob stays open over the face.
    assert_true(bob.distance(h.at(0, 66.0, 10.5)) > 0)
    var crop = HairShape(
        head_muscle_dimensions(_person(_one(HAIR_LENGTH, -1))),
        SCALP_HAIR,
        RIGHT,
    )
    var above = top + skin.gradient(top) * h.cm(0.8)
    assert_true(scalp.distance(above) < 0)
    assert_true(crop.distance(above) > 0)
    # A woman's hairline recedes less at the temples.
    var her = HairShape(
        head_muscle_dimensions(_person(Genome(), FEMALE)), SCALP_HAIR, RIGHT
    )
    assert_true(her.line_recess < scalp.line_recess)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = head_hair_field(dims, EYEBROWS, BodySide(5), skin)
    var brow = HairShape(dims, EYEBROWS, LEFT)
    var group = head_hair_field(dims, EYEBROWS, LEFT)
    var p = h.at(-2.5, 74.4, 9.5)
    assert_equal(brow.distance(p), group.distance(p))
    # A fuller brow reaches farther.
    var full = head_hair_field(
        head_muscle_dimensions(_person(_one(BROW_THICKNESS, 1))), EYEBROWS, LEFT
    )
    assert_true(full.high.y - full.low.y > group.high.y - group.low.y)


def test_add_head_draws_the_eyes() raises:
    var assets = Assets()
    var scene = Scene()
    var root = scene.add(Object3D())
    var paint = MaterialId(0)
    _ = add_head(
        scene, assets, root, _person(), paint, paint, paint, paint, EYES, 8, 8
    )
    assert_equal(len(scene.meshes), 2)
    assert_equal(assets.textures.count(), 1)
    _ = add_head(
        scene,
        assets,
        root,
        _person(),
        paint,
        paint,
        paint,
        paint,
        EYES.plus(SKIN).plus(HAIR),
        8,
        8,
        eye_paint=paint,
        workers=2,
    )
    assert_equal(len(scene.meshes), 2 + 2 + 1 + 1)


def test_brow_box_rejects_each_side() raises:
    var dims = head_muscle_dimensions(_person())
    var brows = _Brows(dims, HeadSkinField(dims))
    var middle = (brows.low + brows.high) * 0.5
    assert_equal(brows.weight(Vector3(brows.low.x - 1, middle.y, middle.z)), 0)
    assert_equal(brows.weight(Vector3(brows.high.x + 1, middle.y, middle.z)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
