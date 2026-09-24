# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for displacement maps: the material that names one, the vertex
stage in `core.deform` that applies one, and the renderer, the shadow pass
and the raycaster that all read it.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    NORMAL,
    POSITION,
    UV,
)
from core.deform import displaced_positions
from core.morph import MorphInfluences
from core.object3d import NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from materials.material import (
    BASIC,
    DEPTH,
    DEFAULT_DISPLACEMENT_SCALE,
    DOUBLE_SIDE,
    LAMBERT,
    MATCAP,
    NORMALS,
    NO_DISPLACEMENT_BIAS,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    TOON,
    Color,
    Material,
    MaterialId,
    depth_material,
    matcap_material,
    normal_material,
    phong_material,
    physical_material,
    shadow_material,
    standard_material,
    toon_material,
)
from math.matrix4 import Matrix4, scaling
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Framebuffer
from render.texture import COVERAGE, IGNORED, NEAREST, Texture, data_texture
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from renderers.renderer import Renderer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-5)
comptime WIDTH = 48
comptime HEIGHT = 48


def heights() raises -> Texture:
    """Return a two-by-two height field, one channel, nearest, stored as
    data: 0 and 0.2 on the top row, 0.6 and 1 on the bottom."""
    var data: List[Float32] = [0.0, 0.2, 0.6, 1.0]
    return data_texture(2, 2, data, channels=1, alpha=IGNORED)


def meters(value: Float32) -> Length:
    """Return a length of that many meters."""
    return Length(value, METER)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking down at the origin from an angle, so a
    height shows as a change in the image."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, -3, 4), Vector3(0, 0, 0))
    return camera^


def pre_displaced(
    var geometry: BufferGeometry,
    texture: Texture,
    scale: Float32,
    bias: Float32,
) raises -> BufferGeometry:
    """Return a flat geometry facing +z with each vertex lifted by hand, as
    a displacement map would lift it, with the same arithmetic.

    Every normal is +z, so the lift is the height along z and nothing
    else; `x + 0 * h` is `x` exactly.
    """
    ref points = geometry.attribute_view(String(POSITION))
    ref uvs = geometry.attribute_view(String(UV))
    var to_uv = texture.uv_transform()
    var lifted = List[Float32]()
    for vertex in range(points.count()):
        var at = to_uv.transform_point(
            Vector2(uvs.component(vertex, 0), uvs.component(vertex, 1))
        )
        var height = texture.sample(at.x, at.y).r * scale + bias
        var point = points.vector3(vertex)
        lifted.append(point.x)
        lifted.append(point.y)
        lifted.append(point.z + height)
    geometry.set_attribute(String(POSITION), BufferAttribute(lifted^, 3))
    return geometry^


def a_grid() raises -> BufferGeometry:
    """Return a two-meter plane of four by four quads facing +z."""
    return plane(meters(2), meters(2), 4, 4)


def lit_scene(
    mut assets: Assets, var geometry: BufferGeometry, material: Material
) raises -> Scene:
    """Return a scene with one mesh at the origin and a sun above it."""
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(1, -1, 3)
    var sun = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), sun, 3.0))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(material),
            NodeId(0),
        )
    )
    scene.update()
    return scene^


def same_image(first: Framebuffer, second: Framebuffer) raises -> Bool:
    """Return True if two images hold the same bytes and the same depths."""
    assert_equal(len(first.pixels), len(second.pixels))
    for index in range(len(first.pixels)):
        if first.pixels[index] != second.pixels[index]:
            return False
    for index in range(len(first.depth)):
        if first.depth[index] != second.depth[index]:
            return False
    return True


def displacing(
    var material: Material, map: TextureId, scale: Float32, bias: Float32
) raises -> Material:
    """Return the material with a displacement map set."""
    material.set_displacement(map, meters(scale), meters(bias))
    return material^


# --- the material -----------------------------------------------------------


def test_a_material_starts_with_no_displacement() raises:
    var material = Material(Color(255, 255, 255))
    assert_false(material.has_displacement_map())
    assert_true(material.displacement_map == NO_TEXTURE)
    assert_equal(material.displacement_scale.to(METER), Float32(1))
    assert_equal(material.displacement_bias.to(METER), Float32(0))
    assert_equal(DEFAULT_DISPLACEMENT_SCALE.to(METER), Float32(1))
    assert_equal(NO_DISPLACEMENT_BIAS.to(METER), Float32(0))
    material.check_displacement()


def test_a_material_takes_a_displacement_map() raises:
    var material = Material(Color(255, 255, 255))
    material.set_displacement(TextureId(0), meters(0.5), meters(-0.25))
    assert_true(material.has_displacement_map())
    assert_equal(material.displacement_scale.to(METER), Float32(0.5))
    assert_equal(material.displacement_bias.to(METER), Float32(-0.25))
    # Cleared, it takes the defaults back.
    material.set_displacement(NO_TEXTURE)
    assert_false(material.has_displacement_map())


def test_the_kinds_three_js_displaces_are_every_kind_but_two() raises:
    assert_false(BASIC.displaces())
    assert_false(SHADOW.displaces())
    assert_true(LAMBERT.displaces())
    assert_true(PHONG.displaces())
    assert_true(TOON.displaces())
    assert_true(STANDARD.displaces())
    assert_true(PHYSICAL.displaces())
    assert_true(MATCAP.displaces())
    assert_true(NORMALS.displaces())
    assert_true(DEPTH.displaces())


def test_a_displacement_the_material_cannot_carry_is_refused() raises:
    var material = Material(Color(255, 255, 255))
    with assert_raises(contains="cannot be negative"):
        material.set_displacement(TextureId(-2))
    with assert_raises(contains="finite"):
        material.set_displacement(TextureId(0), meters(nan[DType.float32]()))
    with assert_raises(contains="finite"):
        material.set_displacement(
            TextureId(0), meters(1), meters(inf[DType.float32]())
        )
    with assert_raises(contains="needs a displacement map"):
        material.set_displacement(NO_TEXTURE, meters(2))
    with assert_raises(contains="needs a displacement map"):
        material.set_displacement(NO_TEXTURE, meters(1), meters(0.5))
    # Each refusal left the material as it was.
    assert_false(material.has_displacement_map())
    assert_equal(material.displacement_scale.to(METER), Float32(1))
    var flat = Material(Color(255, 255, 255), kind=BASIC)
    with assert_raises(contains="basic or shadow"):
        flat.set_displacement(TextureId(0))
    var catcher = shadow_material()
    with assert_raises(contains="basic or shadow"):
        catcher.set_displacement(TextureId(0))
    # The fields are open, and the check catches what is set on them.
    flat.displacement_map = TextureId(0)
    with assert_raises(contains="basic or shadow"):
        flat.check_displacement()


# --- the vertex stage -------------------------------------------------------


def no_morphs() -> MorphInfluences:
    """Return the influences of a mesh that wears nothing."""
    return MorphInfluences()


def one_triangle(
    normals: Bool = True, uvs: Bool = True
) raises -> BufferGeometry:
    """Return one triangle in the z equals zero plane, facing +z, with its
    first vertex at uv (0, 1), which is the map's top-left texel."""
    var geometry = BufferGeometry()
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    if normals:
        var facing: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
        geometry.set_attribute(String(NORMAL), BufferAttribute(facing^, 3))
    if uvs:
        var coordinates: List[Float32] = [0.1, 0.9, 0.9, 0.9, 0.1, 0.1]
        geometry.set_attribute(String(UV), BufferAttribute(coordinates^, 2))
    return geometry^


def store() raises -> TextureStore:
    """Return a store holding the height field at id zero."""
    var textures = TextureStore()
    _ = textures.add(heights())
    return textures^


def test_each_vertex_moves_along_its_normal_by_the_red_channel() raises:
    var textures = store()
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 2, 0.5
    )
    var moved = displaced_positions(
        one_triangle(), no_morphs(), List[Matrix4](), material, textures
    )
    # Top left, 0: only the bias. Top right, 0.2: 0.4 + 0.5. Bottom
    # left, 0.6: 1.2 + 0.5.
    assert_almost_equal(moved[0].z, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(moved[1].z, Float32(0.9), atol=TOLERANCE)
    assert_almost_equal(moved[2].z, Float32(1.7), atol=TOLERANCE)
    assert_almost_equal(moved[1].x, Float32(1), atol=TOLERANCE)


def test_the_map_is_sampled_through_its_own_transform() raises:
    # Slid half the image to the right, the top-left corner reads the
    # top-right texel.
    var textures = TextureStore()
    var slid = heights()
    slid.offset = Vector2(0.5, 0)
    _ = textures.add(slid^)
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 1, 0
    )
    var moved = displaced_positions(
        one_triangle(), no_morphs(), List[Matrix4](), material, textures
    )
    assert_almost_equal(moved[0].z, Float32(0.2), atol=0.002)


def test_a_geometry_without_coordinates_samples_the_origin() raises:
    # (0, 0) is the bottom-left texel, 0.6, for every vertex.
    var textures = store()
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 1, 0
    )
    var moved = displaced_positions(
        one_triangle(uvs=False),
        no_morphs(),
        List[Matrix4](),
        material,
        textures,
    )
    for vertex in range(3):
        assert_almost_equal(moved[vertex].z, Float32(0.6), atol=0.002)


def test_the_normal_is_made_unit_length_first() raises:
    var textures = store()
    var geometry = one_triangle()
    var long: List[Float32] = [0, 0, 4, 0, 0, 4, 0, 0, 4]
    geometry.set_attribute(String(NORMAL), BufferAttribute(long^, 3))
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 1, 0.5
    )
    var moved = displaced_positions(
        geometry, no_morphs(), List[Matrix4](), material, textures
    )
    assert_almost_equal(moved[0].z, Float32(0.5), atol=TOLERANCE)


def test_a_morph_moves_the_normal_the_map_pushes_along() raises:
    # A target that turns every normal to +x, worn whole: the bias moves
    # the vertex along x, after the target has moved it.
    var textures = store()
    var geometry = one_triangle()
    var places: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 2, 0]
    var turned: List[Float32] = [1, 0, 0, 1, 0, 0, 1, 0, 0]
    geometry.add_morph_target(
        BufferAttribute(places^, 3), BufferAttribute(turned^, 3)
    )
    var worn = no_morphs()
    worn.set(0, 1)
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 0, 0.5
    )
    var moved = displaced_positions(
        geometry, worn, List[Matrix4](), material, textures
    )
    assert_almost_equal(moved[2].x, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(moved[2].y, Float32(2), atol=TOLERANCE)
    assert_almost_equal(moved[2].z, Float32(0), atol=TOLERANCE)


def test_the_bones_carry_the_vertex_before_the_map_moves_it() raises:
    # Doubled by its carrier, a vertex lands twice as far out, but it is
    # lifted by the bias once: three.js displaces after skinning, along
    # the skinned normal made unit length.
    var textures = store()
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 0, 0.5
    )
    var doubled = scaling(2, 2, 2)
    var carriers: List[Matrix4] = [doubled, doubled, doubled]
    var moved = displaced_positions(
        one_triangle(), no_morphs(), carriers, material, textures
    )
    assert_almost_equal(moved[1].x, Float32(2), atol=TOLERANCE)
    assert_almost_equal(moved[1].z, Float32(0.5), atol=TOLERANCE)


def test_a_geometry_with_no_vertices_moves_none() raises:
    var textures = store()
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](), 3)
    )
    geometry.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 3))
    geometry.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 1, 0
    )
    var moved = displaced_positions(
        geometry, no_morphs(), List[Matrix4](), material, textures
    )
    assert_equal(len(moved), 0)


def test_the_vertex_stage_refuses_what_it_cannot_move() raises:
    var textures = store()
    var material = displacing(
        Material(Color(255, 255, 255)), TextureId(0), 1, 0
    )
    # No normals to move along.
    with assert_raises(contains="no normals"):
        _ = displaced_positions(
            one_triangle(normals=False),
            no_morphs(),
            List[Matrix4](),
            material,
            textures,
        )
    # Fewer normals than vertices.
    var short = one_triangle()
    var two: List[Float32] = [0, 0, 1, 0, 0, 1]
    short.set_attribute(String(NORMAL), BufferAttribute(two^, 3))
    with assert_raises(contains="a normal for every vertex"):
        _ = displaced_positions(
            short, no_morphs(), List[Matrix4](), material, textures
        )
    # A map that is not in the store, and no map at all.
    var missing = displacing(Material(Color(255, 255, 255)), TextureId(5), 1, 0)
    with assert_raises(contains="not there"):
        _ = displaced_positions(
            one_triangle(), no_morphs(), List[Matrix4](), missing, textures
        )
    with assert_raises(contains="not there"):
        _ = displaced_positions(
            one_triangle(),
            no_morphs(),
            List[Matrix4](),
            Material(Color(255, 255, 255)),
            textures,
        )
    # A map that reads its alpha is not stored as data.
    var covered = TextureStore()
    var data: List[Float32] = [0.5]
    _ = covered.add(data_texture(1, 1, data, channels=1, alpha=COVERAGE))
    with assert_raises(contains="A displacement map"):
        _ = displaced_positions(
            one_triangle(), no_morphs(), List[Matrix4](), material, covered
        )
    # A displacement the material cannot carry, set on its open fields.
    var bent = material
    bent.displacement_scale = meters(nan[DType.float32]())
    with assert_raises(contains="finite"):
        _ = displaced_positions(
            one_triangle(), no_morphs(), List[Matrix4](), bent, textures
        )


# --- the renderer -----------------------------------------------------------


def test_a_displaced_render_matches_a_pre_displaced_geometry() raises:
    # Pixel for pixel, and depth for depth: the map moves the vertices
    # and nothing else, so a geometry lifted by hand draws the same image.
    # The normals are not recomputed, in either, as three.js leaves them.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var map = assets.textures.add(heights())
    var material = displacing(Material(Color(200, 180, 160)), map, 0.8, 0.1)
    var displaced = lit_scene(assets, a_grid(), material)
    var drawn = renderer.render(displaced, assets, a_camera())

    var by_hand = Assets()
    var lifted = pre_displaced(a_grid(), heights(), 0.8, 0.1)
    var plain = lit_scene(by_hand, lifted^, Material(Color(200, 180, 160)))
    var expected = renderer.render(plain, by_hand, a_camera())
    assert_true(same_image(drawn, expected))

    # And not the image of the flat plane, so the match means something.
    var flat_assets = Assets()
    var flat = lit_scene(flat_assets, a_grid(), Material(Color(200, 180, 160)))
    assert_false(
        same_image(drawn, renderer.render(flat, flat_assets, a_camera()))
    )


def test_every_kind_that_displaces_draws_the_moved_vertices() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var kinds = List[Material]()
    kinds.append(Material(Color(255, 255, 255)))
    kinds.append(phong_material(Color(255, 255, 255)))
    kinds.append(toon_material(Color(255, 255, 255)))
    kinds.append(standard_material(Color(255, 255, 255)))
    kinds.append(physical_material(Color(255, 255, 255)))
    kinds.append(matcap_material())
    kinds.append(normal_material())
    kinds.append(depth_material())
    for index in range(len(kinds)):
        var assets = Assets()
        var map = assets.textures.add(heights())
        var scene = lit_scene(
            assets, a_grid(), displacing(kinds[index], map, 0.8, 0.1)
        )
        var corners = renderer.prepare(scene, assets, a_camera())
        var by_hand = Assets()
        var plain = lit_scene(
            by_hand, pre_displaced(a_grid(), heights(), 0.8, 0.1), kinds[index]
        )
        var expected = renderer.prepare(plain, by_hand, a_camera())
        assert_equal(len(corners), len(expected))
        for corner in range(len(corners)):
            assert_equal(corners[corner].world.z, expected[corner].world.z)


def test_the_renderer_refuses_a_displacement_it_cannot_draw() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var material = Material(Color(255, 255, 255))
    # A bias with no map, set on the open fields.
    material.displacement_bias = meters(1)
    var scene = lit_scene(assets, a_grid(), material)
    with assert_raises(contains="needs a displacement map"):
        _ = renderer.prepare(scene, assets, a_camera())
    # A map that is not there.
    var missing = Assets()
    var named = displacing(Material(Color(255, 255, 255)), TextureId(3), 1, 0)
    var nowhere = lit_scene(missing, a_grid(), named)
    with assert_raises(contains="not there"):
        _ = renderer.prepare(nowhere, missing, a_camera())


def test_a_displaced_mesh_is_not_culled_by_the_bound_it_has_left() raises:
    # The plane sits at the origin, behind a camera at z = -60 that looks
    # along -z. A bias of minus eighty meters lifts it out of its
    # geometry's bound and twenty meters in front of the camera, which it
    # faces.
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        1,
        Length(0.1, METER),
        Length(200.0, METER),
    )
    camera.place(Vector3(0, 0, -60), Vector3(0, 0, -100))
    var assets = Assets()
    var map = assets.textures.add(heights())
    var scene = lit_scene(
        assets,
        a_grid(),
        displacing(Material(Color(255, 255, 255)), map, 0, -80),
    )
    # Behind the camera, the bound alone would drop it.
    var plain_assets = Assets()
    var plain = lit_scene(
        plain_assets, a_grid(), Material(Color(255, 255, 255))
    )
    assert_equal(len(renderer.prepare(plain, plain_assets, camera)), 0)
    var corners = renderer.prepare(scene, assets, camera)
    assert_true(len(corners) > 0)
    assert_almost_equal(corners[0].world.z, Float32(-80), atol=TOLERANCE)


def test_a_culled_draw_naming_no_material_is_still_culled_unread() raises:
    # The culling asks a draw's material whether it displaces. An id
    # naming nothing answers no, so the draw is culled as before and
    # nothing is read.
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(200.0, METER)
    )
    camera.place(Vector3(0, 0, -60), Vector3(0, 0, -100))
    var assets = Assets()
    var scene = lit_scene(assets, a_grid(), Material(Color(255, 255, 255)))
    scene.meshes[0].material = MaterialId(7)
    assert_equal(len(renderer.prepare(scene, assets, camera)), 0)
    scene.meshes[0].material = MaterialId(-1)
    assert_equal(len(renderer.prepare(scene, assets, camera)), 0)


def test_a_skinned_mesh_is_carried_before_it_is_displaced() raises:
    # One bone scaled to twice its size carries the triangle out to two
    # meters, and the bias lifts it by half a meter along the carried
    # normal, once: the renderer does not carry the moved vertex again.
    var assets = Assets()
    var geometry = one_triangle()
    var bones: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var weights: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    geometry.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    var map = assets.textures.add(heights())
    var scene = Scene()
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton([NodeId(1)], [scene.world_matrix(NodeId(1))])
    var material = displacing(
        Material(Color(255, 255, 255), side=DOUBLE_SIDE), map, 0, 0.5
    )
    scene.add_skinned_mesh(
        SkinnedMesh(
            assets.geometries.add(geometry^),
            assets.materials.add(material),
            NodeId(0),
            skeleton^,
        )
    )
    scene.node(NodeId(1)).set_scale(2, 2, 2)
    scene.update()
    var camera = a_camera()
    camera.place(Vector3(0, 0, 8), Vector3(0, 0, 0))
    var corners = Renderer(WIDTH, HEIGHT).prepare(scene, assets, camera)
    assert_equal(len(corners), 3)
    assert_almost_equal(corners[1].world.x, Float32(2), atol=TOLERANCE)
    assert_almost_equal(corners[1].world.z, Float32(0.5), atol=TOLERANCE)
    # The raycaster picks it at the same height.
    var ray = Raycaster(Vector3(0.5, 0.5, 5), Vector3(0, 0, -1))
    var hits = ray.intersect_skinned_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_almost_equal(hits[0].point.z, Float32(0.5), atol=TOLERANCE)


# --- shadows ----------------------------------------------------------------


def shadow_scene(
    mut assets: Assets, var caster: BufferGeometry, material: Material
) raises -> Scene:
    """Return a floor under a caster at the origin, lifted by its own
    node, and a sun above that casts."""
    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, 0, -2)
    var floor_node = scene.add(ground^)
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(0.5, 0.5, 4)
    var sun_node = scene.add(lamp^)
    var sun = directional_light(Color(255, 255, 255), sun_node, 3.0)
    sun.cast_shadow = True
    sun.shadow.map_size = 64
    scene.add_light(sun)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(plane(meters(8), meters(8))),
            assets.materials.add(Material(Color(200, 200, 200))),
            floor_node,
            receive_shadow=True,
        )
    )
    scene.add_mesh(
        Mesh(
            assets.geometries.add(caster^),
            assets.materials.add(material),
            NodeId(1),
            cast_shadow=True,
        )
    )
    scene.update()
    return scene^


def test_a_displaced_caster_casts_the_shadow_of_its_moved_surface() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var map = assets.textures.add(heights())
    var displaced = shadow_scene(
        assets,
        a_grid(),
        displacing(Material(Color(200, 60, 60)), map, 0.8, 0.1),
    )
    var by_hand = Assets()
    var lifted = shadow_scene(
        by_hand,
        pre_displaced(a_grid(), heights(), 0.8, 0.1),
        Material(Color(200, 60, 60)),
    )
    var flat_assets = Assets()
    var flat = shadow_scene(flat_assets, a_grid(), Material(Color(200, 60, 60)))
    var moved = renderer.shadow_maps(displaced, assets)
    var expected = renderer.shadow_maps(lifted, by_hand)
    var unmoved = renderer.shadow_maps(flat, flat_assets)
    assert_equal(len(moved), 1)
    var differs = False
    for texel in range(len(moved[0].depths)):
        assert_equal(moved[0].depths[texel], expected[0].depths[texel])
        if moved[0].depths[texel] != unmoved[0].depths[texel]:
            differs = True
    assert_true(differs)
    # And the image it lights is the pre-displaced one's.
    assert_true(
        same_image(
            renderer.render(displaced, assets, a_camera()),
            renderer.render(lifted, by_hand, a_camera()),
        )
    )


# --- the raycaster ----------------------------------------------------------


def test_the_raycaster_picks_the_displaced_surface() raises:
    var assets = Assets()
    var map = assets.textures.add(heights())
    var scene = lit_scene(
        assets,
        a_grid(),
        displacing(Material(Color(255, 255, 255)), map, 0, 0.5),
    )
    var ray = Raycaster(Vector3(0.3, 0.1, 5), Vector3(0, 0, -1))
    var hits = ray.intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_almost_equal(hits[0].point.z, Float32(0.5), atol=TOLERANCE)
    # A ray that passes under the lifted surface, where the modelled one
    # was, meets nothing.
    var under = Raycaster(Vector3(0.3, 0.1, 0.25), Vector3(0, 0, -1))
    assert_equal(len(under.intersect_mesh(scene, assets, 0)), 0)


def test_the_raycaster_refuses_a_displacement_it_cannot_read() raises:
    var assets = Assets()
    var material = Material(Color(255, 255, 255))
    material.displacement_scale = meters(3)
    var scene = lit_scene(assets, a_grid(), material)
    var ray = Raycaster(Vector3(0.3, 0.1, 5), Vector3(0, 0, -1))
    with assert_raises(contains="needs a displacement map"):
        _ = ray.intersect_mesh(scene, assets, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
