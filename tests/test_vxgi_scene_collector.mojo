# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `VXGISceneCollector`: which meshes and triangles
are read, the colors each record carries, the texel a map is read at, and
the split of a long triangle."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, UV, UV1
from core.buffer_geometry import MaterialIndex
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.vxgi_scene_collector import (
    TRIANGLE_STRIDE,
    collect_scene_triangles,
    compute_scene_bounds,
    sample_texture,
)
from materials.material import (
    BACK_SIDE,
    BASIC,
    DEPTH,
    DISTANCE,
    DOUBLE_SIDE,
    GOURAUD,
    LAMBERT,
    MATCAP,
    Material,
    MaterialId,
    MaterialKind,
    NORMALS,
    PHONG,
    PHYSICAL,
    STANDARD,
    TOON,
)
from math.bounds import Box3
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.mesh import Mesh
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from render.framebuffer import Color
from render.srgb import LINEAR
from render.texture import (
    CLAMP,
    MIRROR,
    NEAREST,
    REPEAT,
    Texture,
    UV_CHANNEL_1,
    Wrap,
)
from render.texture_store import TextureId
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Length, METER


comptime WHITE = Color(255, 255, 255)
# A box that holds everything the tests place.
comptime EVERYWHERE = Box3(Vector3(-100, -100, -100), Vector3(100, 100, 100))


def one_triangle(
    a: Vector3, b: Vector3, c: Vector3, uv: Bool = False
) raises -> BufferGeometry:
    """Return a geometry of one triangle, with texture coordinates of the
    first texel's middle when asked."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z], 3),
    )
    if uv:
        geometry.set_attribute(
            UV, BufferAttribute([0.25, 0.25, 0.25, 0.25, 0.25, 0.25], 2)
        )
    return geometry^


def small() raises -> BufferGeometry:
    """Return a small triangle at the origin, in the xy plane."""
    return one_triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))


def placed(
    mut assets: Assets,
    mut scene: Scene,
    var geometry: BufferGeometry,
    material: Material,
) raises -> NodeId:
    """Add a mesh on a node of its own, and return the node."""
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(material),
            node,
        )
    )
    return node


def collect(
    scene: Scene,
    assets: Assets,
    max_edge: Int = 1000,
    min_opacity: Float32 = 0.1,
    bounds: Box3 = EVERYWHERE,
) raises -> List[Float32]:
    """Return the records of a scene, with a sub-voxel of a meter."""
    return collect_scene_triangles(
        scene, assets, bounds, Layers(), 1, max_edge, min_opacity
    )


def a_texture(var pixels: List[UInt8], wrap: Wrap = CLAMP) raises -> Texture:
    """Return a linear texture of two by two texels, read nearest."""
    return Texture(
        2,
        2,
        pixels^,
        wrap=wrap,
        filter=NEAREST,
        color_space=LINEAR,
        mipmapped=False,
    )


def quadrants() raises -> Texture:
    """Return a texture whose four texels are red, green, blue and white,
    stored from the top left."""
    return a_texture(
        [
            255,
            0,
            0,
            255,
            0,
            255,
            0,
            255,
            0,
            0,
            255,
            255,
            255,
            255,
            255,
            128,
        ]
    )


def test_an_empty_scene_has_no_bounds_and_no_triangles() raises:
    var scene = Scene()
    scene.update()
    var assets = Assets()
    assert_true(compute_scene_bounds(scene, assets, Layers()).is_empty())
    assert_equal(len(collect(scene, assets)), 0)


def test_the_bounds_hold_every_vertex_in_the_world() raises:
    var assets = Assets()
    var scene = Scene()
    var node = placed(assets, scene, small(), Material(WHITE))
    var moved = scene.get(node)
    moved.set_position(5, 0, 0)
    scene.set(node, moved^)
    scene.update()
    var bounds = compute_scene_bounds(scene, assets, Layers())
    assert_true(bounds.min == Vector3(5, 0, 0))
    assert_true(bounds.max == Vector3(6, 1, 0))


def test_a_record_holds_the_corners_the_albedo_and_the_side() raises:
    var assets = Assets()
    var scene = Scene()
    _ = placed(assets, scene, small(), Material(Color(255, 0, 255)))
    scene.update()
    var records = collect(scene, assets)
    assert_equal(len(records), TRIANGLE_STRIDE)
    assert_equal(records[4], 1)
    assert_equal(records[9], 1)
    assert_equal(records[12], 1)
    assert_equal(records[13], 0)
    assert_equal(records[14], 1)
    assert_equal(records[15], 0)
    assert_equal(records[16], 0)


def test_a_basic_material_glows_with_its_color() raises:
    var assets = Assets()
    var scene = Scene()
    _ = placed(assets, scene, small(), Material(WHITE, kind=BASIC))
    scene.update()
    var records = collect(scene, assets)
    assert_equal(records[12], 0)
    assert_equal(records[16], 1)
    assert_equal(records[18], 1)


def test_a_lit_material_glows_with_its_emissive_times_its_intensity() raises:
    var kinds: List[MaterialKind] = [
        LAMBERT,
        PHONG,
        TOON,
        STANDARD,
        PHYSICAL,
        GOURAUD,
    ]
    for kind in kinds:
        var assets = Assets()
        var scene = Scene()
        _ = placed(
            assets,
            scene,
            small(),
            Material(WHITE, kind=kind, emissive=WHITE, emissive_intensity=2.0),
        )
        scene.update()
        assert_equal(collect(scene, assets)[16], 2)
    # A matcap has no emissive color, whatever its field holds.
    var assets = Assets()
    var scene = Scene()
    var matcap = Material(WHITE, kind=MATCAP)
    matcap.emissive = WHITE
    _ = placed(assets, scene, small(), matcap)
    scene.update()
    assert_equal(collect(scene, assets)[16], 0)


def test_a_material_with_no_color_is_white() raises:
    var kinds: List[MaterialKind] = [NORMALS, DEPTH, DISTANCE]
    for kind in kinds:
        var assets = Assets()
        var scene = Scene()
        var colorless = Material(WHITE, kind=kind)
        colorless.color = Color(0, 0, 0)
        _ = placed(assets, scene, small(), colorless)
        scene.update()
        assert_equal(collect(scene, assets)[12], 1)


def test_the_side_is_zero_one_or_two() raises:
    var sides = [BACK_SIDE, DOUBLE_SIDE]
    var want: List[Float32] = [1, 2]
    for at in range(2):
        var assets = Assets()
        var scene = Scene()
        _ = placed(assets, scene, small(), Material(WHITE, side=sides[at]))
        scene.update()
        assert_equal(collect(scene, assets)[15], want[at])


def test_a_faint_or_hidden_material_is_skipped() raises:
    var assets = Assets()
    var scene = Scene()
    _ = placed(
        assets, scene, small(), Material(WHITE, opacity=0.05, transparent=True)
    )
    var hidden = Material(WHITE)
    hidden.visible = False
    _ = placed(assets, scene, small(), hidden)
    # An opaque material's opacity is one, whatever it says.
    _ = placed(assets, scene, small(), Material(WHITE, opacity=0.05))
    scene.update()
    assert_equal(len(collect(scene, assets)), TRIANGLE_STRIDE)


def test_a_map_colors_the_albedo_at_the_centroid() raises:
    var assets = Assets()
    var scene = Scene()
    var map = assets.textures.add(quadrants())
    _ = placed(
        assets,
        scene,
        one_triangle(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), True
        ),
        Material(WHITE, map=map),
    )
    scene.update()
    var records = collect(scene, assets)
    # (0.25, 0.25) is the lower left texel: the bottom row of the image,
    # blue, under three.js's `flipY`.
    assert_equal(records[12], 0)
    assert_equal(records[14], 1)


def test_a_map_s_alpha_can_drop_a_triangle() raises:
    var assets = Assets()
    var scene = Scene()
    var faint = a_texture(
        [
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        ]
    )
    var map = assets.textures.add(faint^)
    _ = placed(
        assets,
        scene,
        one_triangle(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), True
        ),
        Material(WHITE, map=map),
    )
    scene.update()
    assert_equal(len(collect(scene, assets)), 0)
    # Kept when nothing is thought too faint.
    assert_equal(len(collect(scene, assets, min_opacity=-1)), TRIANGLE_STRIDE)


def test_an_alpha_test_drops_a_fainter_triangle() raises:
    var assets = Assets()
    var scene = Scene()
    var map = assets.textures.add(quadrants())
    var geometry = one_triangle(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
    )
    # The white texel, at the bottom right: its alpha is 128 / 255.
    geometry.set_attribute(
        UV, BufferAttribute([0.75, 0.25, 0.75, 0.25, 0.75, 0.25], 2)
    )
    _ = placed(
        assets, scene, geometry^, Material(WHITE, map=map, alpha_test=0.6)
    )
    scene.update()
    assert_equal(len(collect(scene, assets)), 0)
    var passing = Assets()
    var kept = Scene()
    var again = passing.textures.add(quadrants())
    var twin = one_triangle(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
    )
    twin.set_attribute(
        UV, BufferAttribute([0.75, 0.25, 0.75, 0.25, 0.75, 0.25], 2)
    )
    _ = placed(passing, kept, twin^, Material(WHITE, map=again, alpha_test=0.4))
    kept.update()
    assert_equal(len(collect(kept, passing)), TRIANGLE_STRIDE)


def test_a_map_read_through_the_second_coordinates() raises:
    var assets = Assets()
    var scene = Scene()
    var texture = quadrants()
    texture.channel = UV_CHANNEL_1
    var map = assets.textures.add(texture^)
    var geometry = one_triangle(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), True
    )
    geometry.set_attribute(
        UV1, BufferAttribute([0.75, 0.25, 0.75, 0.25, 0.75, 0.25], 2)
    )
    _ = placed(assets, scene, geometry^, Material(WHITE, map=map))
    # A second mesh has no second coordinates: its map is not read.
    var reads_uv1 = quadrants()
    reads_uv1.channel = UV_CHANNEL_1
    var unread = assets.textures.add(reads_uv1^)
    _ = placed(assets, scene, small(), Material(Color(0, 255, 0), map=unread))
    scene.update()
    var records = collect(scene, assets)
    # The bottom right texel, white.
    assert_equal(records[12], 1)
    assert_equal(records[13], 1)
    assert_equal(records[TRIANGLE_STRIDE + 13], 1)
    assert_equal(records[TRIANGLE_STRIDE + 12], 0)


def test_an_emissive_map_colors_the_glow() raises:
    var assets = Assets()
    var scene = Scene()
    var glow = assets.textures.add(quadrants())
    _ = placed(
        assets,
        scene,
        one_triangle(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), True
        ),
        Material(WHITE, emissive=WHITE, emissive_map=glow),
    )
    # An unlit material ignores its emissive map.
    var unlit = Material(WHITE, kind=BASIC)
    unlit.emissive = WHITE
    unlit.emissive_map = glow
    _ = placed(
        assets,
        scene,
        one_triangle(
            Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), True
        ),
        unlit,
    )
    scene.update()
    var records = collect(scene, assets)
    assert_equal(records[16], 0)
    assert_equal(records[18], 1)
    assert_equal(records[TRIANGLE_STRIDE + 16], 1)


def test_a_texture_is_read_where_its_wrap_puts_the_coordinate() raises:
    var repeat = a_texture(
        [
            255,
            0,
            0,
            255,
            0,
            255,
            0,
            255,
            0,
            0,
            255,
            255,
            255,
            255,
            255,
            255,
        ],
        REPEAT,
    )
    # 1.25 repeats to 0.25: the left column. v 0.25 is the bottom row.
    assert_equal(sample_texture(repeat, 1.25, 0.25).b, 1)
    var clamp = quadrants()
    # Past the right edge and below the bottom: the bottom right texel.
    assert_equal(sample_texture(clamp, 3, -2).g, 1)
    assert_equal(sample_texture(clamp, 3, -2).a, Float32(128) / 255)
    var mirror = a_texture(
        [
            255,
            0,
            0,
            255,
            0,
            255,
            0,
            255,
            0,
            0,
            255,
            255,
            255,
            255,
            255,
            255,
        ],
        MIRROR,
    )
    # 1.25 lies in an odd tile: it runs back to 0.75, the right column.
    assert_equal(sample_texture(mirror, 1.25, 0.25).g, 1)
    # 2.25 lies in an even tile: 0.25, the left column.
    assert_equal(sample_texture(mirror, 2.25, 0.25).b, 1)
    # A texture that is not flipped reads v down from the first row.
    var unflipped = quadrants()
    unflipped.flip_y = False
    assert_equal(sample_texture(unflipped, 0.25, 0.25).r, 1)
    # The blank texture is white.
    assert_equal(sample_texture(Texture(), 0.5, 0.5).r, 1)
    # The texture's transform moves the coordinate first.
    var moved = quadrants()
    moved.offset.x = 0.5
    assert_equal(sample_texture(moved, 0.25, 0.25).a, Float32(128) / 255)


def test_a_triangle_outside_the_bounds_or_of_no_size_is_skipped() raises:
    var assets = Assets()
    var scene = Scene()
    _ = placed(assets, scene, small(), Material(WHITE))
    _ = placed(
        assets,
        scene,
        one_triangle(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)),
        Material(WHITE),
    )
    scene.update()
    assert_equal(len(collect(scene, assets)), TRIANGLE_STRIDE)
    var far = Box3(Vector3(10, 10, 10), Vector3(11, 11, 11))
    assert_equal(len(collect(scene, assets, bounds=far)), 0)


def test_a_long_triangle_is_split_along_its_longest_edge() raises:
    # Each triangle's longest edge is a different one of the three.
    var corners: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(4, 0, 0),
        Vector3(2, 1, 0),
        Vector3(2, 1, 0),
        Vector3(0, 0, 0),
        Vector3(4, 0, 0),
        Vector3(4, 0, 0),
        Vector3(2, 1, 0),
        Vector3(0, 0, 0),
    ]
    for first in range(3):
        var assets = Assets()
        var scene = Scene()
        _ = placed(
            assets,
            scene,
            one_triangle(
                corners[first * 3],
                corners[first * 3 + 1],
                corners[first * 3 + 2],
            ),
            Material(WHITE),
        )
        scene.update()
        # The long edge is four sub-voxels; three is the most kept. One
        # split halves it, and the halves' edges are all short enough.
        var records = collect(scene, assets, max_edge=3)
        assert_equal(len(records), 2 * TRIANGLE_STRIDE)
        # The middle of the long edge is a corner of both halves.
        var middles = 0
        for at in range(6):
            var base = (at // 3) * TRIANGLE_STRIDE + (at % 3) * 4
            if records[base] == 2 and records[base + 1] == 0:
                middles += 1
        assert_equal(middles, 2)


def test_a_mesh_on_a_hidden_node_or_another_layer_is_skipped() raises:
    var assets = Assets()
    var scene = Scene()
    var hidden = placed(assets, scene, small(), Material(WHITE))
    var node = scene.get(hidden)
    node.visible = False
    scene.set(hidden, node^)
    var elsewhere = placed(assets, scene, small(), Material(WHITE))
    var other = scene.get(elsewhere)
    other.layers.set(3)
    scene.set(elsewhere, other^)
    _ = scene.add(Object3D())
    scene.update()
    assert_equal(len(collect(scene, assets)), 0)
    var three = Layers()
    three.set(3)
    assert_equal(
        len(
            collect_scene_triangles(
                scene, assets, EVERYWHERE, three, 1, 1000, 0.1
            )
        ),
        TRIANGLE_STRIDE,
    )


def test_groups_wear_their_own_materials() raises:
    var assets = Assets()
    var scene = Scene()
    var geometry = one_triangle(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
    )
    geometry.set_attribute(
        POSITION,
        BufferAttribute(
            [
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                1,
                0,
                1,
                0,
                1,
                1,
                0,
                0,
                2,
                1,
                0,
                2,
                0,
                1,
                2,
            ],
            3,
        ),
    )
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(1))
    # A group whose material the list has not got is not drawn.
    geometry.add_group(6, 3, MaterialIndex(5))
    var red = assets.materials.add(Material(Color(255, 0, 0)))
    var green = assets.materials.add(Material(Color(0, 255, 0)))
    var mesh = Mesh(
        assets.geometries.add(geometry^), red, scene.add(Object3D())
    )
    mesh.materials = [red, green]
    scene.add_mesh(mesh)
    scene.update()
    var records = collect(scene, assets)
    assert_equal(len(records), 2 * TRIANGLE_STRIDE)
    assert_equal(records[12], 1)
    assert_equal(records[TRIANGLE_STRIDE + 13], 1)
    assert_equal(records[TRIANGLE_STRIDE + 2], 1)


def test_one_material_draws_every_group_and_a_list_reads_its_first() raises:
    var assets = Assets()
    var scene = Scene()
    var red = assets.materials.add(Material(Color(255, 0, 0)))
    var green = assets.materials.add(Material(Color(0, 255, 0)))
    # One material: the groups are passed over, the whole stream drawn.
    var grouped = small()
    grouped.add_group(0, 3, MaterialIndex(1))
    scene.add_mesh(
        Mesh(assets.geometries.add(grouped^), red, scene.add(Object3D()))
    )
    # A list and no groups: the first material, the whole stream.
    var listed = Mesh(
        assets.geometries.add(small()), red, scene.add(Object3D())
    )
    listed.materials = [green, red]
    scene.add_mesh(listed)
    scene.update()
    var records = collect(scene, assets)
    assert_equal(len(records), 2 * TRIANGLE_STRIDE)
    assert_equal(records[12], 1)
    assert_equal(records[TRIANGLE_STRIDE + 13], 1)


def test_the_draw_range_and_the_index_choose_the_triangles() raises:
    var assets = Assets()
    var scene = Scene()
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0], 3),
    )
    geometry.set_index([0, 1, 2, 2, 1, 3])
    geometry.set_draw_range(3, 3)
    _ = placed(assets, scene, geometry^, Material(WHITE))
    var empty = small()
    empty.set_draw_range(0, 0)
    _ = placed(assets, scene, empty^, Material(WHITE))
    scene.update()
    var records = collect(scene, assets)
    assert_equal(len(records), TRIANGLE_STRIDE)
    # The second triangle: corners 2, 1 and 3.
    assert_equal(records[1], 1)
    assert_equal(records[4], 1)
    assert_equal(records[8], 1)
    assert_equal(records[9], 1)


def test_each_instance_is_collected_where_it_stands() raises:
    var assets = Assets()
    var scene = Scene()
    var group = InstancedMesh(
        assets.geometries.add(small()),
        assets.materials.add(Material(WHITE)),
        scene.add(Object3D()),
        2,
    )
    group.set_matrix_at(1, translation(0, 0, 3))
    scene.add_instanced_mesh(group^)
    # None at all adds nothing.
    scene.add_instanced_mesh(
        InstancedMesh(
            assets.geometries.add(small()),
            assets.materials.add(Material(WHITE)),
            scene.add(Object3D()),
            0,
        )
    )
    scene.update()
    var records = collect(scene, assets)
    assert_equal(len(records), 2 * TRIANGLE_STRIDE)
    assert_equal(records[TRIANGLE_STRIDE + 2], 3)
    var bounds = compute_scene_bounds(scene, assets, Layers())
    assert_true(bounds.min == Vector3(0, 0, 0))
    assert_true(bounds.max == Vector3(1, 1, 3))


def test_a_skinned_mesh_is_collected_at_rest() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_skinned_mesh(
        SkinnedMesh(
            assets.geometries.add(small()),
            assets.materials.add(Material(WHITE)),
            node,
            Skeleton([Bone(node, Matrix4())]),
        )
    )
    scene.update()
    assert_equal(len(collect(scene, assets)), TRIANGLE_STRIDE)
    var bounds = compute_scene_bounds(scene, assets, Layers())
    assert_true(bounds.max == Vector3(1, 1, 0))


def test_a_mesh_of_no_vertices_adds_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    _ = placed(assets, scene, geometry^, Material(WHITE))
    scene.update()
    assert_true(compute_scene_bounds(scene, assets, Layers()).is_empty())
    assert_equal(len(collect(scene, assets)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
