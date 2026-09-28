# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Regressions for data preservation and boundary cases found in the audit."""

from animation.keyframe_track import (
    BEZIER,
    CUBIC_SPLINE,
    KeyframeTrack,
    MATERIAL_OPACITY,
    material_target,
)
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.geometry_store import GeometryId
from core.object3d import Object3D
from core.scene import Scene
from core.scene_optimizer import (
    SceneOptimizer,
    material_signature,
    _texture_key,
)
from geometries.attribute_utils import (
    interleave_attributes,
    merge_attributes,
    estimate_bytes_used,
)
from geometries.box import cube
from geometries.convex_object_breaker import (
    BreakableObject,
    ConvexObjectBreaker,
)
from geometries.utils import merge_geometries
from loaders.gltf import _Loader, COMPONENT_UNSIGNED_INT
from loaders.json import parse_json
from materials.material import Material, MaterialId, PHONG, BACK_SIDE
from math.bounds import Plane
from math.curve import ellipse_sweep, WHOLE_TURN
from math.matrix3 import Matrix3
from math.matrix4 import Matrix4, scaling
from math.quaternion import Quaternion
from math.utils import (
    UINT32_COMPONENT,
    UINT16_COMPONENT,
    UINT8_COMPONENT,
    INT16_COMPONENT,
    INT8_COMPONENT,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.points import Points
from render.computation import GPUComputationRenderer
from render.framebuffer import Color
from render.texture import CLAMP, REPEAT
from render.texture_store import TextureId
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Duration,
    SECOND,
    Angle,
    RADIAN,
    Length,
    METER,
    Mass,
    KILOGRAM,
)


def test_tangent_curves_keep_their_shape_after_optimization() raises:
    var times: List[Duration] = [
        Duration(0, SECOND),
        Duration(1, SECOND),
        Duration(2, SECOND),
    ]
    var track = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        times,
        in_tangents=[1, 1, 1],
        values=[0, 0, 0],
        out_tangents=[1, 1, 1],
        interpolation=CUBIC_SPLINE,
    )
    var samples = List[Float32]()
    for step in range(21):
        samples.append(track.sample(Duration(Float32(step) / 10, SECOND))[0])
    track.optimize()
    assert_equal(track.key_count(), 3)
    for step in range(21):
        assert_equal(
            track.sample(Duration(Float32(step) / 10, SECOND))[0], samples[step]
        )
    var bezier = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_OPACITY),
        times,
        in_tangents=[0, 0, 0, 0, 0, 0],
        values=[1, 1, 1],
        out_tangents=[1, 2, 1, 2, 1, 2],
        interpolation=BEZIER,
    )
    var before = bezier.sample(Duration(0.5, SECOND))[0]
    bezier.optimize()
    assert_equal(bezier.key_count(), 3)
    assert_equal(bezier.sample(Duration(0.5, SECOND))[0], before)
    with assert_raises(contains="three components"):
        _ = track.sample_vector3(Duration(0, SECOND))


def test_ellipse_range_reduction_is_bounded() raises:
    for angle in [Float32(1e9), Float32(-1e9), Float32(3e38), Float32(-3e38)]:
        var forward = ellipse_sweep(
            Angle(0, RADIAN), Angle(angle, RADIAN), False
        )
        var backward = ellipse_sweep(
            Angle(0, RADIAN), Angle(angle, RADIAN), True
        )
        assert_true(forward > 0 and forward <= WHOLE_TURN)
        assert_true(backward < 0 and backward >= -WHOLE_TURN)
    for angle in [
        inf[DType.float32](),
        -inf[DType.float32](),
        nan[DType.float32](),
    ]:
        with assert_raises(contains="finite"):
            _ = ellipse_sweep(Angle(0, RADIAN), Angle(angle, RADIAN), False)
    assert_equal(
        ellipse_sweep(Angle(0, RADIAN), Angle(WHOLE_TURN, RADIAN), False),
        WHOLE_TURN,
    )


def test_merging_keeps_integer_storage_and_checks_compatibility() raises:
    var exact = BufferAttribute([16777217, 4294967295], 1, UINT32_COMPONENT)
    var merged = merge_attributes([exact.clone(), exact.clone()])
    assert_equal(merged.component_type(), UINT32_COMPONENT)
    assert_equal(
        merged.stored_values(),
        List[Int](
            16777217, 4294967295, 16777217, 4294967295, __list_literal__=None
        ),
    )
    var normalized = BufferAttribute([0, 255], 1, UINT8_COMPONENT, True)
    var joined = merge_attributes([normalized.clone(), normalized.clone()])
    assert_true(joined.is_normalized())
    assert_equal(
        joined.stored_values(), List[Int](0, 255, 0, 255, __list_literal__=None)
    )
    with assert_raises(contains="component type"):
        _ = merge_attributes(
            [exact.clone(), BufferAttribute([1], 1, UINT16_COMPONENT)]
        )
    with assert_raises(contains="normalization"):
        _ = merge_attributes(
            [normalized.clone(), BufferAttribute([1], 1, UINT8_COMPONENT)]
        )
    with assert_raises(contains="instance divisor"):
        _ = merge_attributes(
            [
                BufferAttribute([1], 1),
                BufferAttribute([2], 1, mesh_per_attribute=2),
            ]
        )
    var instanced = merge_attributes(
        [
            BufferAttribute([1], 1, mesh_per_attribute=2),
            BufferAttribute([2], 1, mesh_per_attribute=2),
        ]
    )
    assert_equal(instanced.mesh_per_attribute(), 2)
    assert_equal(instanced.packed(), List[Float32](1, 2, __list_literal__=None))
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute([0, 0, 0, 1, 1, 1], 3))
    geometry.set_attribute("id", exact.clone())
    var combined = merge_geometries([geometry.clone(), geometry.clone()])
    assert_equal(
        combined.attribute_view("id").stored_values(), merged.stored_values()
    )
    geometry.set_attribute("bytes", normalized.clone())
    geometry.set_attribute(
        "shorts", BufferAttribute([1, 2], 1, INT16_COMPONENT)
    )
    geometry.set_attribute("signed", BufferAttribute([1, 2], 1, INT8_COMPONENT))
    geometry.set_attribute(
        "unsigned", BufferAttribute([1, 2], 1, UINT16_COMPONENT)
    )
    assert_equal(estimate_bytes_used(geometry), 44)


def test_morph_normal_transform_preserves_the_blended_direction() raises:
    for relative in [False, True]:
        var geometry = BufferGeometry()
        geometry.set_attribute(POSITION, BufferAttribute([0, 0, 0], 3))
        geometry.set_attribute(NORMAL, BufferAttribute([0, 0, 1], 3))
        geometry.morph_relative = relative
        geometry.add_morph_target(
            BufferAttribute([0, 0, 0], 3), BufferAttribute([0.5, 0, 0], 3)
        )
        geometry.apply_matrix4(Matrix4())
        assert_equal(geometry.morph_normal(0, 0).x, Float32(0.5))
        var matrix = scaling(2, 3, 4)
        var base = Vector3(0, 0, 1)
        var target = geometry.morph_normal(0, 0)
        var weight = Float32(0.4)
        var expected = Matrix3.normal_matrix(matrix).transform(
            base + (target if relative else target - base) * weight
        )
        expected.normalize()
        geometry.apply_matrix4(matrix)
        var actual_base = geometry.attribute_view(NORMAL).vector3(0)
        var actual_target = geometry.morph_normal(0, 0)
        var actual = (
            actual_base
            + (actual_target if relative else actual_target - actual_base)
            * weight
        )
        actual.normalize()
        assert_almost_equal(actual.x, expected.x, atol=1e-6)
        assert_almost_equal(actual.z, expected.z, atol=1e-6)


def test_interleaved_breakup_matches_packed_breakup() raises:
    for indexed in [False, True]:
        var plain = cube(Length(1, METER))
        if not indexed:
            plain = plain.to_non_indexed()
        var shared = plain.clone()
        var attributes = interleave_attributes(
            [plain.clone_attribute(POSITION), plain.clone_attribute(NORMAL)]
        )
        shared.set_attribute(POSITION, attributes[0].clone())
        shared.set_attribute(NORMAL, attributes[1].clone())
        var origin = Vector3(0, 0, 0)
        var object = BreakableObject(
            plain^,
            origin,
            Quaternion.identity(),
            Mass(1, KILOGRAM),
            origin,
            origin,
            True,
        )
        var twin = BreakableObject(
            shared^,
            origin,
            Quaternion.identity(),
            Mass(1, KILOGRAM),
            origin,
            origin,
            True,
        )
        var breaker = ConvexObjectBreaker()
        var cut = breaker.cut_by_plane(object, Plane(Vector3(1, 0, 0), 0))
        var other = breaker.cut_by_plane(twin, Plane(Vector3(1, 0, 0), 0))
        assert_true(Bool(other[0]) and Bool(other[1]))
        assert_equal(
            cut[0].value().geometry.attribute_view(POSITION).packed(),
            other[0].value().geometry.attribute_view(POSITION).packed(),
        )
        assert_equal(
            cut[1].value().geometry.attribute_view(POSITION).packed(),
            other[1].value().geometry.attribute_view(POSITION).packed(),
        )


def test_computation_readback_keeps_each_wrap_axis() raises:
    var computation = GPUComputationRenderer(1, 1)
    var id = computation.add_variable(
        "field",
        "void main() { gl_FragColor = vec4(1.0); }",
        computation.create_texture(),
    )
    computation.variables[id].wrap_s = CLAMP
    computation.variables[id].wrap_t = REPEAT
    var texture = computation.current_texture(id)
    assert_equal(texture.wrap_s, CLAMP)
    assert_equal(texture.wrap_t, REPEAT)


def _loader(
    accessors: String, views: String, bytes: List[UInt8]
) raises -> _Loader:
    var text = (
        '{"asset":{"version":"2.0"},"buffers":[{"byteLength":'
        + String(len(bytes))
        + '}],"bufferViews":['
        + views
        + '],"accessors":['
        + accessors
        + "]}"
    )
    var reader = _Loader(parse_json(text), bytes, "")
    reader.read_buffers()
    return reader^


def test_gltf_checks_offsets_strides_and_both_bounds() raises:
    var bytes = List[UInt8](length=32, fill=0)
    var prefix = '{"bufferView":0,"componentType":5126,"count":1,"type":"VEC3",'
    for offset in [-4, 2, 28]:
        var reader = _loader(
            prefix + '"byteOffset":' + String(offset) + "}",
            '{"buffer":0,"byteOffset":4,"byteLength":24}',
            bytes,
        )
        with assert_raises(contains="glTF"):
            _ = reader.accessor_floats(0)
    for stride in [-4, 4, 13, 256]:
        var reader = _loader(
            prefix + '"byteOffset":0}',
            '{"buffer":0,"byteLength":32,"byteStride":' + String(stride) + "}",
            bytes,
        )
        with assert_raises(contains="byteStride"):
            _ = reader.accessor_floats(0)
    var short = _loader(
        prefix + '"byteOffset":0}', '{"buffer":0,"byteLength":8}', bytes
    )
    with assert_raises(contains="past"):
        _ = short.accessor_floats(0)
    var aligned = _loader(
        prefix + '"byteOffset":0}',
        '{"buffer":0,"byteOffset":1,"byteLength":24}',
        bytes,
    )
    with assert_raises(contains="misaligned"):
        _ = aligned.accessor_floats(0)
    var empty = _loader(
        '{"bufferView":0,"componentType":5126,"count":0,"type":"VEC3"}',
        '{"buffer":0,"byteLength":0}',
        bytes,
    )
    assert_equal(len(empty.accessor_floats(0)[0]), 0)


def test_gltf_keeps_uint32_indices_attributes_and_sparse_values() raises:
    var reader = _loader(
        '{"bufferView":0,"componentType":5125,"count":2,"type":"SCALAR"}',
        '{"buffer":0,"byteLength":8}',
        List[UInt8](1, 0, 0, 1, 255, 255, 255, 255, __list_literal__=None),
    )
    assert_equal(
        reader.accessor_indices(0),
        List[Int](16777217, 4294967295, __list_literal__=None),
    )
    var attribute = reader.vertex_attribute("_ID", 0, None)
    assert_equal(
        attribute.stored_values(),
        List[Int](16777217, 4294967295, __list_literal__=None),
    )
    var sparse = _loader(
        '{"componentType":5125,"count":2,"type":"SCALAR","sparse":{"count":1,"indices":{"bufferView":0,"componentType":5121},"values":{"bufferView":1}}}',
        '{"buffer":0,"byteLength":1},{"buffer":0,"byteOffset":4,"byteLength":4}',
        List[UInt8](1, 0, 0, 0, 1, 0, 0, 1, __list_literal__=None),
    )
    assert_equal(
        sparse.accessor_indices(0),
        List[Int](0, 16777217, __list_literal__=None),
    )


def test_gltf_matrix_columns_skip_alignment_padding() raises:
    var reader = _loader(
        '{"bufferView":0,"componentType":5121,"count":1,"type":"MAT2"}',
        '{"buffer":0,"byteLength":8}',
        List[UInt8](1, 2, 99, 99, 3, 4, 99, 99, __list_literal__=None),
    )
    assert_equal(
        reader.accessor_floats(0)[0],
        List[Float32](1, 2, 3, 4, __list_literal__=None),
    )
    var three = _loader(
        '{"bufferView":0,"componentType":5121,"count":1,"type":"MAT3"}',
        '{"buffer":0,"byteLength":12}',
        List[UInt8](
            1, 2, 3, 99, 4, 5, 6, 99, 7, 8, 9, 99, __list_literal__=None
        ),
    )
    assert_equal(
        three.accessor_floats(0)[0],
        List[Float32](1, 2, 3, 4, 5, 6, 7, 8, 9, __list_literal__=None),
    )


def test_material_key_preserves_rendering_state_and_checks_texture_ids() raises:
    var assets = Assets()
    var original = Material(Color(255, 255, 255), kind=PHONG)
    var key = material_signature(assets, original)
    var variants = List[Material]()
    var other = original
    other.shininess = 99
    variants.append(other)
    other = original
    other.specular = Color(1, 2, 3)
    variants.append(other)
    other = original
    other.normal_scale.x = 0.75
    variants.append(other)
    other = original
    other.emissive_intensity = 2
    variants.append(other)
    other = original
    other.stencil_ref = 2
    variants.append(other)
    other = original
    other.shadow_side = BACK_SIDE
    variants.append(other)
    other = original
    other.opacity = 0.99999994
    variants.append(other)
    other = original
    other.scattering.power = 99
    variants.append(other)
    other = original
    other.set_clipping_planes([Plane(Vector3(1, 0, 0), 1)])
    variants.append(other)
    for variant in variants:
        assert_true(key != material_signature(assets, variant))
    with assert_raises(contains="No texture"):
        _ = _texture_key(assets, TextureId(99))
    with assert_raises(contains="No texture"):
        _ = _texture_key(assets, TextureId(-2))


def test_optimizer_keeps_distinct_uvs_normals_and_integer_values() raises:
    var scene = Scene()
    var assets = Assets()
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    var base = cube(Length(1, METER))
    base.set_attribute(
        "id",
        BufferAttribute(
            List[Int](length=base.vertex_count(), fill=16777216),
            1,
            UINT32_COMPONENT,
        ),
    )
    for variant in range(5):
        var geometry = base.clone()
        if variant == 1:
            var uv = geometry.clone_attribute(UV)
            uv.set_component(0, 0, 0.375)
            geometry.set_attribute(UV, uv^)
        elif variant == 2:
            var normal = geometry.clone_attribute(NORMAL)
            normal.set_component(0, 0, 0.5)
            geometry.set_attribute(NORMAL, normal^)
        elif variant == 3:
            geometry.set_attribute(
                "id",
                BufferAttribute(
                    List[Int](length=geometry.vertex_count(), fill=16777217),
                    1,
                    UINT32_COMPONENT,
                ),
            )
        elif variant == 4:
            # Different interleaved storage, but exactly the base geometry.
            var shared = interleave_attributes(
                [
                    geometry.clone_attribute(POSITION),
                    geometry.clone_attribute(NORMAL),
                ]
            )
            geometry.set_attribute(POSITION, shared[0].clone())
            geometry.set_attribute(NORMAL, shared[1].clone())
        var id = assets.geometries.add(geometry^)
        scene.add_mesh(Mesh(id, paint, scene.add(Object3D())))
    var stats = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_equal(stats.unique_geometries, 4)
    assert_equal(len(scene.batched_meshes[0].geometries), 4)
    assert_equal(scene.batched_meshes[0].count(), 5)


def test_optimizer_keeps_nodes_with_children_other_objects_or_dynamic_state() raises:
    for variant in range(9):
        var scene = Scene()
        var assets = Assets()
        var shape = cube(Length(1, METER))
        if variant == 4:
            shape.add_morph_target(shape.clone_attribute(POSITION))
        elif variant == 5:
            shape.set_draw_range(0, 3)
        elif variant == 6:
            shape.instanced = True
        elif variant == 7:
            shape.set_attribute(
                "instance", BufferAttribute([1], 1, mesh_per_attribute=1)
            )
        var geometry = assets.geometries.add(shape^)
        var material = assets.materials.add(Material(Color(255, 255, 255)))
        var first = scene.add(Object3D())
        var second = scene.add(Object3D())
        var mesh = Mesh(geometry, material, first)
        var child = first
        if variant == 0:
            child = scene.attach(Object3D(), first)
            scene.add_points(Points(geometry, material, child))
        elif variant == 1:
            scene.add_points(Points(geometry, material, first))
        elif variant == 2:
            mesh.custom_depth_material = material
        elif variant == 3:
            mesh.custom_distance_material = material
        elif variant == 8:
            var object = scene.get(first)
            object.user_data.set_string("keep", "metadata")
            scene.set(first, object^)
        scene.add_mesh(mesh^)
        scene.add_mesh(Mesh(geometry, material, second))
        _ = SceneOptimizer().to_batched_mesh(scene, assets)
        assert_true(scene.in_scene(first))
        assert_true(scene.in_scene(second))
        assert_true(scene.in_scene(child))
        assert_equal(len(scene.batched_meshes), 0)


def test_optimizer_keeps_parent_and_node_render_state() raises:
    var scene = Scene()
    var assets = Assets()
    var geometry = assets.geometries.add(cube(Length(1, METER)))
    var material = assets.materials.add(Material(Color(255, 255, 255, 128)))
    for _ in range(2):
        var parent = scene.add(Object3D())
        for _ in range(2):
            var object = Object3D()
            object.visible = False
            object.layers.mask = 4
            object.render_order = 7
            var node = scene.attach(object^, parent)
            var mesh = Mesh(geometry, material, node)
            mesh.frustum_culled = False
            mesh.cast_shadow = True
            mesh.receive_shadow = True
            scene.add_mesh(mesh^)
    var stats = SceneOptimizer().to_batched_mesh(scene, assets)
    assert_equal(stats.batched_meshes, 2)
    for batch in scene.batched_meshes:
        var node = scene.get(batch.node)
        assert_false(node.visible)
        assert_equal(node.layers.mask, UInt32(4))
        assert_equal(node.render_order, 7)
        assert_true(batch.cast_shadow and batch.receive_shadow)
        assert_equal(assets.materials.get(batch.material).color.a, UInt8(128))
        assert_false(batch.frustum_culled)
        assert_false(batch.per_object_frustum_culled)
    assert_true(
        scene.get(scene.batched_meshes[0].node).parent
        != scene.get(scene.batched_meshes[1].node).parent
    )


def test_float_merges_preserve_normalized_metadata() raises:
    for divisor in [0, 2]:
        var attribute = BufferAttribute([1, 2, 3], 1)
        if divisor > 0:
            attribute = BufferAttribute(
                [1, 2, 3], 1, mesh_per_attribute=divisor
            )
        attribute.set_normalized(True)
        var merged = merge_attributes([attribute.clone(), attribute.clone()])
        assert_true(merged.is_normalized())
        assert_equal(merged.mesh_per_attribute(), divisor)
        assert_equal(merged.count(), 6)


def test_morph_normals_without_base_and_with_zero_base() raises:
    for with_base in [False, True]:
        var geometry = BufferGeometry()
        geometry.set_attribute(POSITION, BufferAttribute([0, 0, 0], 3))
        if with_base:
            geometry.set_attribute(NORMAL, BufferAttribute([0, 0, 0], 3))
        geometry.add_morph_target(
            BufferAttribute([0, 0, 0], 3), BufferAttribute([0.5, 0, 0], 3)
        )
        geometry.morph_relative = True
        geometry.apply_matrix4(Matrix4())
        assert_equal(geometry.morph_normal(0, 0).x, Float32(0.5))


def test_optimizer_preserves_keep_lists_duplicate_objects_and_metadata() raises:
    for variant in range(3):
        var scene = Scene()
        var assets = Assets()
        var geometry = assets.geometries.add(cube(Length(1, METER)))
        var material = assets.materials.add(Material(Color(255, 255, 255)))
        var first = scene.add(Object3D())
        var second = scene.add(Object3D())
        scene.add_mesh(Mesh(geometry, material, first))
        scene.add_mesh(Mesh(geometry, material, second))
        if variant == 0:
            _ = SceneOptimizer([first]).to_batched_mesh(scene, assets)
            assert_true(scene.in_scene(first))
        elif variant == 1:
            scene.add_mesh(Mesh(geometry, material, first))
            _ = SceneOptimizer().to_batched_mesh(scene, assets)
            assert_true(scene.in_scene(first))
        else:
            var empty = Object3D()
            empty.user_data.set_string("label", "retained")
            var node = scene.add(empty^)
            _ = SceneOptimizer().to_batched_mesh(scene, assets)
            assert_true(scene.in_scene(node))
            assert_equal(scene.get(node).user_data.string("label"), "retained")


def test_sparse_indices_are_exact_at_the_float32_boundary() raises:
    var reader = _loader(
        '{"componentType":5121,"count":1,"type":"SCALAR","sparse":{"count":1,"indices":{"bufferView":0,"componentType":5125},"values":{"bufferView":1}}}',
        '{"buffer":0,"byteLength":4},{"buffer":0,"byteOffset":4,"byteLength":1}',
        [1, 0, 0, 1, 1],
    )
    var sparse = reader.document.get(reader.entry("accessors", 0), "sparse")
    var output = List[Float32]()
    with assert_raises(contains="stay inside"):
        reader.apply_sparse(sparse, output, 16777217, 1, 5121, False, [0], 1, 1)


def test_gltf_rejects_misaligned_matrix_and_sparse_views() raises:
    var bytes = List[UInt8](length=32, fill=0)
    var matrix = _loader(
        '{"bufferView":0,"componentType":5121,"count":1,"type":"MAT2"}',
        '{"buffer":0,"byteOffset":1,"byteLength":8}',
        bytes,
    )
    with assert_raises(contains="misaligned"):
        _ = matrix.accessor_floats(0)
    for view in [
        '{"buffer":0,"byteOffset":1,"byteLength":8}',
        '{"buffer":0,"byteLength":8,"byteStride":4}',
    ]:
        var reader = _loader(
            '{"componentType":5123,"count":1,"type":"SCALAR","sparse":{"count":1,"indices":{"bufferView":1,"componentType":5121},"values":{"bufferView":0}}}',
            String(view) + ',{"buffer":0,"byteLength":1}',
            bytes,
        )
        with assert_raises(contains="packed and aligned"):
            _ = reader.accessor_floats(0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
