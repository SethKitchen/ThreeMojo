# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the surface of a fabric: texture coordinates round each
bone, and the bump maps of mail, quilting and weave."""

from std.math import cos, pi, sin

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, UV, BufferGeometry
from extensions.attire.fabric import fabric_material
from extensions.attire.kinds import (
    LEATHER,
    LINEN,
    MAIL,
    MAIL_RINGS,
    NO_BUMP,
    PADDING,
    QUILTING,
    TWILL,
    Bump,
    PLATE,
    SILK,
    VELVET,
    WOOL,
    FELT,
    FUR,
    FUR_LOCKS,
    PLAIT,
    STRAW,
    FabricKind,
)
from extensions.attire.surface import (
    FUR_TILE,
    PLAIT_TILE,
    fur_heights,
    plait_heights,
    MAIL_TILE,
    QUILT_TILE,
    TEXELS,
    WEAVE_TILE,
    BoneChains,
    BoneFrame,
    SurfaceLook,
    SurfaceMaps,
    bump_texture,
    garment_uvs,
    mail_heights,
    quilt_heights,
    surface_look,
    weave_heights,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    JOINT_COUNT,
    RIGHT_FOREARM,
    RIGHT_HAND,
    RIGHT_THIGH,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
)
from math.vector3 import Vector3
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from render.framebuffer import Color
from render.srgb import LINEAR
from render.texture import IGNORED, REPEAT
from render.texture_store import NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, line_rig, strip


def bent_rig() raises -> HumanoidRig:
    """Return the line rig with the right upper arm turned to point +x.

    Its chains: the right upper arm alone, the right forearm and hand, and
    every other bone in the chain from the hips.
    """
    var rig = line_rig()
    var at = rig.joints[RIGHT_UPPER_ARM.value]
    rig.ends[RIGHT_UPPER_ARM.value] = at + Vector3(1, 0, 0)
    return rig^


def tube(
    rig: HumanoidRig, joint: Int, radius: Float32, around: Int, rings: Int
) raises -> BufferGeometry:
    """Return an open tube round one bone of a rig, bound wholly to it."""
    var flat = List[Float32]()
    var bones = List[Float32]()
    var weights = List[Float32]()
    var top = rig.joints[joint]
    for r in range(rings + 1):
        var y = top.y - Float32(r) / Float32(rings)
        for k in range(around):
            var angle = 2 * Float32(pi) * Float32(k) / Float32(around)
            flat.append(top.x + radius * sin(angle))
            flat.append(y)
            flat.append(top.z + radius * cos(angle))
            bones.append(Float32(joint))
            for _ in range(3):
                bones.append(0)
            weights.append(1)
            for _ in range(3):
                weights.append(0)
    var index = List[Int]()
    for r in range(rings):
        for k in range(around):
            var a = r * around + k
            var b = r * around + (k + 1) % around
            index.append(a)
            index.append(b)
            index.append(a + around)
            index.append(b)
            index.append(b + around)
            index.append(a + around)
    var mesh = BufferGeometry()
    mesh.set_attribute(String(POSITION), BufferAttribute(flat^, 3))
    mesh.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    mesh.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    mesh.set_index(index^)
    return mesh^


def area(mesh: BufferGeometry) raises -> Float64:
    """Return the area of a mesh."""
    ref points = mesh.attribute_view(String(POSITION))
    var total = Float64(0)
    for t in range(mesh.triangle_count()):
        var a = points.vector3(mesh.corner_index(t, 0))
        var b = points.vector3(mesh.corner_index(t, 1))
        var c = points.vector3(mesh.corner_index(t, 2))
        var normal = b - a
        normal.cross(c - a)
        total += Float64(normal.length()) / 2
    return total


def widest_u(mesh: BufferGeometry) raises -> Float32:
    """Return the widest span of `u` across one triangle."""
    ref uv = mesh.attribute_view(String(UV))
    var widest = Float32(0)
    for t in range(mesh.triangle_count()):
        var low = Float32(1e30)
        var high = Float32(-1e30)
        for c in range(3):
            var u = uv.component(mesh.corner_index(t, c), 0)
            low = min(low, u)
            high = max(high, u)
        widest = max(widest, high - low)
    return widest


def weigh(
    mut mesh: BufferGeometry,
    vertex: Int,
    joints: List[Int],
    shares: List[Float32],
) raises:
    """Bind one vertex of a mesh to up to four joints."""
    var bones = List[Float32]()
    var weights = List[Float32]()
    ref old_bones = mesh.attribute_view(String(SKIN_INDEX))
    ref old_weights = mesh.attribute_view(String(SKIN_WEIGHT))
    for v in range(old_bones.count()):
        for k in range(4):
            if v == vertex:
                bones.append(Float32(joints[k]) if k < len(joints) else 0)
                weights.append(shares[k] if k < len(shares) else 0)
            else:
                bones.append(old_bones.component(v, k))
                weights.append(old_weights.component(v, k))
    mesh.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    mesh.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))


def test_each_fabric_has_its_surface() raises:
    var mail = surface_look(MAIL)
    assert_true(mail.has_map())
    assert_true(mail.kind == MAIL_RINGS)
    assert_almost_equal(mail.tiles, 1 / MAIL_TILE, atol=1e-4)
    var padding = surface_look(PADDING)
    assert_true(padding.kind == QUILTING)
    assert_almost_equal(padding.tiles, 1 / QUILT_TILE, atol=1e-4)
    var cloth: List[FabricKind] = [LINEN, WOOL, SILK, VELVET]
    for kind in cloth:
        var look = surface_look(kind)
        assert_true(look.kind == TWILL)
        assert_almost_equal(look.tiles, 1 / WEAVE_TILE, atol=1e-2)
    assert_false(surface_look(LEATHER).has_map())
    assert_false(surface_look(PLATE).has_map())
    assert_false(surface_look(FELT).has_map())
    assert_true(surface_look(FUR).kind == FUR_LOCKS)
    assert_almost_equal(surface_look(FUR).tiles, 1 / FUR_TILE, atol=1e-3)
    assert_true(surface_look(STRAW).kind == PLAIT)
    assert_almost_equal(surface_look(STRAW).tiles, 1 / PLAIT_TILE, atol=1e-3)
    with assert_raises(contains="fabric"):
        _ = surface_look(FabricKind(99))


def test_the_height_maps_tile_and_stay_in_range() raises:
    var maps: List[List[Float32]] = [
        mail_heights(),
        quilt_heights(),
        weave_heights(),
        fur_heights(),
        plait_heights(),
    ]
    for m in range(5):
        assert_equal(len(maps[m]), TEXELS * TEXELS)
        for h in maps[m]:
            assert_true(h >= 0 and h <= 1)
    # A ring of mail rises from a flat ground.
    var lowest = Float32(1)
    var highest = Float32(0)
    for h in maps[0]:
        lowest = min(lowest, h)
        highest = max(highest, h)
    assert_equal(lowest, 0)
    assert_true(highest > 0.95)
    # The quilting is pressed down where the diagonals cross, at the
    # middle of the tile, and full between them.
    var middle = (TEXELS // 2) * TEXELS + TEXELS // 2
    assert_true(maps[1][middle] < 0.1)
    assert_true(maps[1][TEXELS // 2] > 0.9)
    # A warp thread is over in the first cell of the twill and under in
    # the third.
    var cell = TEXELS // 4
    var over = (cell // 2) * TEXELS + cell // 2
    var under = (cell // 2) * TEXELS + 2 * cell + cell // 2
    assert_true(maps[2][over] > 0.9)
    assert_true(maps[2][under] < 0.6)
    # Fur's locks stand out of bare ground between them.
    var lowest_fur = Float32(1)
    var highest_fur = Float32(0)
    for h in maps[3]:
        lowest_fur = min(lowest_fur, h)
        highest_fur = max(highest_fur, h)
    assert_equal(lowest_fur, 0)
    assert_true(highest_fur > 0.6)
    # A straw is over in the first quarter of the plait and under in the
    # quarter beside it.
    var half = TEXELS // 2
    assert_true(maps[4][(half // 2) * TEXELS + half // 2] > 0.9)
    assert_true(maps[4][(half // 2) * TEXELS + half + half // 2] < 0.6)


def test_a_bump_map_tiles_at_its_true_size() raises:
    var texture = bump_texture(surface_look(MAIL))
    assert_equal(texture.width, TEXELS)
    assert_equal(texture.height, TEXELS)
    assert_almost_equal(texture.repeat.x, 1 / MAIL_TILE, atol=1e-4)
    assert_almost_equal(texture.repeat.y, 1 / MAIL_TILE, atol=1e-4)
    assert_true(texture.wrap_s == REPEAT)
    assert_true(texture.color_space == LINEAR)
    assert_true(texture.alpha == IGNORED)
    assert_true(texture.levels > 1)
    _ = bump_texture(surface_look(PADDING))
    _ = bump_texture(surface_look(WOOL))
    _ = bump_texture(surface_look(FUR))
    _ = bump_texture(surface_look(STRAW))
    with assert_raises(contains="no bump map"):
        _ = bump_texture(SurfaceLook(NO_BUMP, 0, 1))
    with assert_raises(contains="named"):
        _ = bump_texture(SurfaceLook(Bump(9), 0, 1))


def test_each_map_is_made_once() raises:
    var assets = Assets()
    var maps = SurfaceMaps()
    var hauberk = fabric_material(MAIL, Color(255, 255, 255))
    var coif = fabric_material(MAIL, Color(255, 255, 255))
    var gambeson = fabric_material(PADDING, Color(255, 255, 255))
    var boots = fabric_material(LEATHER, Color(255, 255, 255))
    maps.apply(hauberk, assets, MAIL)
    maps.apply(coif, assets, MAIL)
    maps.apply(gambeson, assets, PADDING)
    maps.apply(boots, assets, LEATHER)
    assert_equal(assets.textures.count(), 2)
    assert_true(hauberk.bump_map != NO_TEXTURE)
    assert_true(hauberk.bump_map == coif.bump_map)
    assert_true(gambeson.bump_map != hauberk.bump_map)
    assert_almost_equal(hauberk.bump_scale, surface_look(MAIL).scale)
    assert_true(boots.bump_map == NO_TEXTURE)


def test_a_bone_frame_runs_down_and_across_the_bone() raises:
    var rig = line_rig()
    var frame = BoneFrame(rig, RIGHT_THIGH.value)
    assert_almost_equal(frame.axis.y, -1, atol=1e-6)
    assert_almost_equal(frame.forward.z, 1, atol=1e-6)
    assert_almost_equal(abs(frame.side.x), 1, atol=1e-6)
    # A bone of no length points down. A bone along z turns its front up.
    rig.ends[HIPS.value] = rig.joints[HIPS.value]
    rig.ends[SPINE.value] = rig.joints[SPINE.value] + Vector3(0, 0, 1)
    assert_almost_equal(BoneFrame(rig, HIPS.value).axis.y, -1, atol=1e-6)
    var along_z = BoneFrame(rig, SPINE.value)
    assert_almost_equal(along_z.axis.z, 1, atol=1e-6)
    assert_almost_equal(abs(along_z.forward.y), 1, atol=1e-6)


def test_a_chain_runs_on_until_a_bone_bends() raises:
    var straight = BoneChains(line_rig())
    for j in range(JOINT_COUNT):
        assert_equal(straight.roots[j], 0)
    assert_almost_equal(straight.starts[SPINE.value], 1, atol=1e-6)
    assert_almost_equal(straight.starts[CHEST.value], 2, atol=1e-6)
    assert_almost_equal(straight.starts[RIGHT_UPPER_ARM.value], 3, atol=1e-6)
    var bent = BoneChains(bent_rig())
    assert_equal(bent.roots[RIGHT_UPPER_ARM.value], RIGHT_UPPER_ARM.value)
    assert_equal(bent.starts[RIGHT_UPPER_ARM.value], 0)
    assert_equal(bent.roots[RIGHT_FOREARM.value], RIGHT_FOREARM.value)
    assert_equal(bent.roots[RIGHT_HAND.value], RIGHT_FOREARM.value)
    assert_almost_equal(bent.starts[RIGHT_HAND.value], 1, atol=1e-6)
    assert_equal(bent.roots[RIGHT_THIGH.value], 0)


def test_a_sleeve_opens_along_its_back_seam() raises:
    var rig = line_rig()
    var sleeve = tube(rig, RIGHT_THIGH.value, 0.1, 16, 4)
    var laid = garment_uvs(sleeve, rig)
    assert_true(laid.vertex_count() > sleeve.vertex_count())
    assert_almost_equal(area(laid), area(sleeve), rtol=1e-4)
    ref uv = laid.attribute_view(String(UV))
    ref points = laid.attribute_view(String(POSITION))
    var start = BoneChains(rig).starts[RIGHT_THIGH.value]
    var widest = Float32(0)
    for v in range(laid.vertex_count()):
        var p = points.vector3(v)
        # Down the chain, in meters.
        assert_almost_equal(uv.component(v, 1), start - p.y, atol=1e-5)
        # Round the bone, at most half the way round either side.
        assert_true(abs(uv.component(v, 0)) <= Float32(pi) * 0.1 + 1e-5)
        widest = max(widest, abs(uv.component(v, 0)))
        # The front of the sleeve is the middle of the map.
        if p.z > 0.0999:
            assert_almost_equal(uv.component(v, 0), 0, atol=1e-5)
    assert_almost_equal(widest, Float32(pi) * 0.1, atol=1e-3)
    # No triangle wraps round the seam.
    assert_true(widest_u(laid) < 0.1)


def test_a_garment_is_cut_where_one_chain_gives_way_to_another() raises:
    var rig = bent_rig()
    var chains = BoneChains(rig)
    # A strip at the forearm: its top rows on the hips' chain, its bottom
    # rows on the forearm's, its middle row split between three chains.
    var piece = strip(rig.joints[RIGHT_FOREARM.value].x, 4, HIPS)
    for v in range(4, 10):
        weigh(piece, v, [RIGHT_FOREARM.value], [1])
    weigh(
        piece,
        4,
        [HIPS.value, RIGHT_UPPER_ARM.value, RIGHT_FOREARM.value],
        [0.34, 0.33, 0.33],
    )
    weigh(
        piece,
        5,
        [HIPS.value, RIGHT_UPPER_ARM.value, RIGHT_FOREARM.value],
        [0.34, 0.33, 0.33],
    )
    var laid = garment_uvs(piece, rig)
    assert_almost_equal(area(laid), area(piece), rtol=1e-4)
    # The hips' chain lays the strip out round a bone six meters off, the
    # forearm's round a bone through the strip. No triangle mixes them.
    assert_true(chains.roots[RIGHT_FOREARM.value] != chains.roots[HIPS.value])
    assert_true(widest_u(laid) < 2)


def test_a_weight_that_names_no_joint_is_refused() raises:
    var rig = line_rig()
    var piece = strip(0, 2, HIPS)
    weigh(piece, 0, [HIPS.value, 40], [0.5, 0.5])
    with assert_raises(contains="names no joint"):
        _ = garment_uvs(piece, rig)
    var below = strip(0, 2, HIPS)
    weigh(below, 0, [HIPS.value, -1], [0.5, 0.5])
    with assert_raises(contains="names no joint"):
        _ = garment_uvs(below, rig)


def test_an_empty_garment_gets_empty_coordinates() raises:
    var empty = empty_mesh()
    var laid = garment_uvs(empty, line_rig())
    assert_equal(laid.vertex_count(), 0)
    assert_equal(laid.attribute_view(String(UV)).count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
