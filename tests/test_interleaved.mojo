# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.interleaved_buffer`, the interleaved and instanced
forms of `core.buffer_attribute`, instanced `BufferGeometry`, and every
reader of them: the renderer, the raycaster, the deformers, the
utilities, the exporters and the JSON Object loader.

The claim the reader tests make is the same each time: a geometry whose
attributes share one interleaved buffer reads, draws, picks and exports
exactly as the same geometry with an array per attribute. The claim the
instancing tests make is that an instanced geometry draws pixel for pixel
as the same instances drawn as plain meshes.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
)
from core.deform import morphed_positions
from core.geometry_store import GeometryId
from core.interleaved_buffer import InterleavedBuffer
from core.morph import MorphInfluences
from core.object3d import NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from exporters.gltf import export_gltf
from exporters.obj import export_obj
from exporters.object_json import object_to_json
from geometries.box import cube
from geometries.sphere import sphere
from geometries.utils import merge_geometries, merge_vertices
from lights.light import ambient_light, directional_light
from loaders.object_loader import read_object_json
from materials.material import BASIC, LAMBERT, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 24
comptime HEIGHT = 18


# --- helpers ----------------------------------------------------------------


def interleave(geometry: BufferGeometry) raises -> BufferGeometry:
    """Return a geometry whose position, normal and uv share one buffer.

    Args:
        geometry: A geometry with all three, per vertex.

    Returns:
        The same vertices, index and groups, interleaved eight to a vertex.

    Raises:
        Error: If the geometry lacks one of the three.
    """
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    ref uvs = geometry.attribute_view(String(UV))
    var numbers = List[Float32]()
    for vertex in range(positions.count()):
        for lane in range(3):
            numbers.append(positions.component(vertex, lane))
        for lane in range(3):
            numbers.append(normals.component(vertex, lane))
        for lane in range(2):
            numbers.append(uvs.component(vertex, lane))
    var buffer = InterleavedBuffer(numbers^, 8)
    var out = BufferGeometry()
    out.set_attribute(String(POSITION), BufferAttribute(buffer, 3, 0))
    out.set_attribute(String(NORMAL), BufferAttribute(buffer, 3, 3))
    out.set_attribute(String(UV), BufferAttribute(buffer, 2, 6))
    out.set_index(geometry.index.copy())
    out.groups = geometry.groups.copy()
    return out^


def a_camera() raises -> PerspectiveCamera:
    """Return a camera four meters up z looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def assert_same_image(got: Framebuffer, wanted: Framebuffer) raises:
    """Assert two images agree on every channel and depth of every pixel."""
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var one = got.get_pixel(x, y)
            var two = wanted.get_pixel(x, y)
            assert_equal(one.r, two.r)
            assert_equal(one.g, two.g)
            assert_equal(one.b, two.b)
            assert_equal(one.a, two.a)
            assert_equal(got.depth_at(x, y), wanted.depth_at(x, y))


def count_drawn(image: Framebuffer, background: Color) raises -> Int:
    """Return how many pixels are not the background."""
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r != background.r
                or pixel.g != background.g
                or pixel.b != background.b
            ):
                drawn += 1
    return drawn


def lit_scene() raises -> Scene:
    """Return a scene with a lamp and one node at the origin, node 1."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 0.75))
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def meshes_at(
    material: Material, offsets: List[Vector3]
) raises -> Tuple[Scene, Assets]:
    """Return a scene with one plain box per offset, and its assets.

    Args:
        material: The material, added once per mesh.
        offsets: Where each mesh's node sits.

    Returns:
        The scene and its assets.

    Raises:
        Error: If the scene is invalid, which it is not.
    """
    var assets = Assets()
    var shape = assets.geometries.add(cube(Length(0.8, METER)))
    var scene = Scene()
    for index in range(len(offsets)):
        var node = Object3D()
        node.set_position(offsets[index].x, offsets[index].y, offsets[index].z)
        var paint = assets.materials.add(material.copy())
        scene.add_mesh(Mesh(shape, paint, scene.add(node^)))
    scene.update()
    return (scene^, assets^)


def one_mesh_scene(geometry: BufferGeometry) raises -> Tuple[Scene, Assets]:
    """Return a scene of one mesh of a geometry at the origin, and its
    assets."""
    return one_mesh_scene(geometry, Material(Color(10, 20, 30)))


def one_mesh_scene(
    geometry: BufferGeometry, material: Material
) raises -> Tuple[Scene, Assets]:
    """Return a scene of one mesh of a geometry and a material at the
    origin, and its assets."""
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry.clone()),
            assets.materials.add(material.copy()),
            node,
        )
    )
    return (scene^, assets^)


# --- the buffer -------------------------------------------------------------


def test_a_buffer_holds_runs_of_its_stride() raises:
    var buffer = InterleavedBuffer([1, 2, 3, 4, 5, 6], 3)
    assert_equal(buffer.count(), 2)
    assert_equal(buffer.stride(), 3)
    assert_equal(buffer.length(), 6)
    assert_equal(buffer.mesh_per_attribute(), 0)
    assert_false(buffer.is_instanced())
    assert_equal(buffer.value(4), 5)
    var instanced = InterleavedBuffer([1, 2, 3, 4], 2, mesh_per_attribute=3)
    assert_true(instanced.is_instanced())
    assert_equal(instanced.mesh_per_attribute(), 3)
    assert_equal(instanced.count(), 2)


def test_a_buffer_refuses_a_shape_it_cannot_have() raises:
    with assert_raises(contains="stride must be positive"):
        _ = InterleavedBuffer([1, 2], 0)
    with assert_raises(contains="stride must be positive"):
        _ = InterleavedBuffer([1, 2], -2)
    with assert_raises(contains="divide evenly"):
        _ = InterleavedBuffer([1, 2, 3], 2)
    with assert_raises(contains="one instance a run"):
        _ = InterleavedBuffer([1, 2], 2, mesh_per_attribute=0)
    var buffer = InterleavedBuffer([1, 2], 2)
    with assert_raises(contains="out of range"):
        _ = buffer.value(2)
    with assert_raises(contains="out of range"):
        _ = buffer.value(-1)
    with assert_raises(contains="out of range"):
        buffer.set_value(2, 0)
    with assert_raises(contains="out of range"):
        buffer.set_value(-1, 0)


def test_a_copy_of_a_buffer_shares_and_a_clone_does_not() raises:
    var buffer = InterleavedBuffer([1, 2, 3, 4], 2, mesh_per_attribute=2)
    var handle = buffer.copy()
    var cloned = buffer.clone()
    handle.set_value(1, 9)
    assert_equal(buffer.value(1), 9)
    assert_equal(cloned.value(1), 2)
    assert_true(buffer.shares_with(handle))
    assert_false(buffer.shares_with(cloned))
    assert_equal(cloned.stride(), 2)
    assert_equal(cloned.mesh_per_attribute(), 2)


# --- the attribute ----------------------------------------------------------


def test_an_interleaved_attribute_reads_with_the_stride() raises:
    # Two vertices of a position and a uv each.
    var buffer = InterleavedBuffer([1, 2, 3, 10, 20, 4, 5, 6, 40, 50], 5)
    var positions = BufferAttribute(buffer, 3, 0)
    var uvs = BufferAttribute(buffer, 2, 3)
    assert_true(positions.is_interleaved())
    assert_equal(positions.count(), 2)
    assert_equal(uvs.count(), 2)
    assert_equal(positions.stride(), 5)
    assert_equal(uvs.offset(), 3)
    assert_equal(len(uvs.data), 0)
    assert_equal(positions.vector3(1).z, 6)
    assert_equal(uvs.component(1, 0), 40)
    assert_equal(uvs.component(0, 1), 20)
    var packed = uvs.packed()
    assert_equal(len(packed), 4)
    assert_equal(packed[2], 40)
    assert_equal(packed[3], 50)
    assert_false(positions.is_instanced())
    assert_equal(positions.mesh_per_attribute(), 0)
    assert_true(positions.interleaved_buffer().shares_with(buffer))
    var empty = BufferAttribute(InterleavedBuffer(List[Float32](), 2), 1, 1)
    assert_equal(len(empty.packed()), 0)


def test_a_write_through_one_attribute_shows_through_the_buffer() raises:
    var buffer = InterleavedBuffer([1, 2, 3, 4, 5, 6], 3)
    var first = BufferAttribute(buffer, 2, 0)
    var last = BufferAttribute(buffer, 2, 1)
    first.set_component(1, 1, 50)
    assert_equal(last.component(1, 0), 50)
    assert_equal(buffer.value(4), 50)
    # A copy of the attribute reads the same buffer; a clone does not.
    var copied = first.copy()
    var cloned = first.clone()
    buffer.set_value(0, 7)
    assert_equal(copied.component(0, 0), 7)
    assert_equal(cloned.component(0, 0), 1)
    assert_false(cloned.is_interleaved())
    assert_equal(cloned.count(), 2)
    # A plain attribute writes its own array.
    var plain = BufferAttribute([1, 2], 2)
    plain.set_component(0, 1, 5)
    assert_equal(plain.data[1], 5)
    with assert_raises(contains="not interleaved"):
        _ = plain.interleaved_buffer()


def test_an_interleaved_attribute_refuses_an_item_outside_its_run() raises:
    var buffer = InterleavedBuffer([1, 2, 3, 4, 5, 6], 3)
    with assert_raises(contains="item size must be positive"):
        _ = BufferAttribute(buffer, 0, 0)
    with assert_raises(contains="inside the stride"):
        _ = BufferAttribute(buffer, 1, -1)
    with assert_raises(contains="inside the stride"):
        _ = BufferAttribute(buffer, 2, 2)
    var attribute = BufferAttribute(buffer, 2, 1)
    with assert_raises(contains="vertex index out of range"):
        _ = attribute.component(2, 0)
    with assert_raises(contains="component offset out of range"):
        _ = attribute.component(0, 2)
    with assert_raises(contains="component offset out of range"):
        attribute.set_component(0, -1, 0)
    # The item size is an open field. Grown past the run, it is refused
    # when read rather than read out of the next vertex.
    attribute.item_size = 3
    with assert_raises(contains="inside the stride"):
        _ = attribute.component(0, 2)
    with assert_raises(contains="inside the stride"):
        _ = attribute.packed()


def test_an_instanced_attribute_advances_per_instance() raises:
    var offsets = BufferAttribute([1, 2, 3, 4, 5, 6], 3, mesh_per_attribute=2)
    assert_true(offsets.is_instanced())
    assert_equal(offsets.mesh_per_attribute(), 2)
    assert_equal(offsets.count(), 2)
    assert_equal(offsets.stride(), 3)
    var cloned = offsets.clone()
    assert_equal(cloned.mesh_per_attribute(), 2)
    var buffer = InterleavedBuffer([1, 2, 3, 4], 2, mesh_per_attribute=1)
    var shared = BufferAttribute(buffer, 1, 1)
    assert_true(shared.is_instanced())
    assert_equal(shared.clone().mesh_per_attribute(), 1)
    with assert_raises(contains="one instance or more"):
        _ = BufferAttribute([1, 2, 3], 3, mesh_per_attribute=0)
    with assert_raises(contains="divide evenly"):
        _ = BufferAttribute([1, 2], 3, mesh_per_attribute=1)


def test_an_attribute_moves_onto_another_buffer() raises:
    var buffer = InterleavedBuffer([1, 2, 3, 4], 2)
    var other = buffer.clone()
    var moved = BufferAttribute(buffer, 1, 1).on_buffer(other)
    assert_true(moved.interleaved_buffer().shares_with(other))
    assert_equal(moved.offset(), 1)
    # One that is not interleaved stays as it is.
    var plain = BufferAttribute([1, 2], 1).on_buffer(other)
    assert_false(plain.is_interleaved())
    assert_equal(plain.count(), 2)


# --- the geometry -----------------------------------------------------------


def test_an_interleaved_geometry_measures_as_the_plain_one() raises:
    var plain = sphere(Length(1.0, METER), 8, 6)
    var mixed = interleave(plain)
    assert_equal(mixed.vertex_count(), plain.vertex_count())
    assert_equal(mixed.triangle_count(), plain.triangle_count())
    var one = plain.bounding_sphere()
    var two = mixed.bounding_sphere()
    assert_equal(one.radius, two.radius)
    assert_equal(one.center.x, two.center.x)
    mixed.compute_vertex_normals()
    plain.compute_vertex_normals()
    for vertex in range(plain.vertex_count()):
        var a = plain.attribute_view(String(NORMAL)).vector3(vertex)
        var b = mixed.attribute_view(String(NORMAL)).vector3(vertex)
        assert_equal(a.x, b.x)
        assert_equal(a.y, b.y)
        assert_equal(a.z, b.z)
    var flat = mixed.to_non_indexed()
    assert_false(flat.attribute_view(String(UV)).is_interleaved())
    assert_equal(flat.vertex_count(), plain.to_non_indexed().vertex_count())


def test_centering_moves_positions_in_the_shared_buffer_only() raises:
    var buffer = InterleavedBuffer([2, 0, 0, 7, 4, 0, 0, 7, 2, 2, 0, 7], 4)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(buffer, 3, 0))
    geometry.set_attribute(String("weight"), BufferAttribute(buffer, 1, 3))
    geometry.center()
    ref positions = geometry.attribute_view(String(POSITION))
    assert_equal(positions.component(0, 0), -1)
    assert_equal(positions.component(2, 1), 1)
    assert_equal(geometry.attribute_view(String("weight")).component(1, 0), 7)
    assert_equal(buffer.value(0), -1)


def test_a_clone_copies_each_buffer_once_and_keeps_the_sharing() raises:
    var buffer = InterleavedBuffer([0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1], 4)
    var geometry = BufferGeometry(instanced=True)
    geometry.set_attribute(String(POSITION), BufferAttribute(buffer, 3, 0))
    geometry.set_attribute(String("weight"), BufferAttribute(buffer, 1, 3))
    geometry.set_attribute(String(UV), BufferAttribute([0, 0, 1, 0, 0, 1], 2))
    var targets = InterleavedBuffer([0, 0, 1, 1, 0, 1, 0, 1, 1], 3)
    geometry.add_morph_target(BufferAttribute(targets, 3, 0))
    geometry.set_instance_count(4)
    var copied = geometry.clone()
    assert_true(copied.instanced)
    assert_equal(copied.instance_count.value(), 4)
    var position = copied.attribute_view(String(POSITION)).interleaved_buffer()
    var weight = copied.attribute_view(String("weight")).interleaved_buffer()
    assert_true(position.shares_with(weight))
    assert_false(position.shares_with(buffer))
    assert_false(copied.attribute_view(String(UV)).is_interleaved())
    assert_true(copied.morph_positions[0].is_interleaved())
    buffer.set_value(0, 5)
    assert_equal(copied.attribute_view(String(POSITION)).component(0, 0), 0)
    # clone_attribute gives an array of its own.
    var own = geometry.clone_attribute(String("weight"))
    assert_false(own.is_interleaved())
    assert_equal(own.data[2], 1)


def test_an_instanced_geometry_counts_its_instances() raises:
    var plain = BufferGeometry()
    assert_false(plain.instanced)
    assert_equal(plain.drawn_instances(), 1)
    with assert_raises(contains="Only an instanced geometry"):
        plain.set_instance_count(2)
    var geometry = BufferGeometry(instanced=True)
    with assert_raises(contains="needs an instance count"):
        _ = geometry.drawn_instances()
    with assert_raises(contains="cannot be negative"):
        geometry.set_instance_count(-1)
    geometry.set_instance_count(5)
    assert_equal(geometry.drawn_instances(), 5)
    # A per-vertex attribute does not cap the count; per-instance ones
    # do, each by its items times its mesh per attribute.
    geometry.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    geometry.set_attribute(
        String("offset"),
        BufferAttribute([0, 0, 0, 1, 1, 1], 3, mesh_per_attribute=2),
    )
    assert_equal(geometry.drawn_instances(), 4)
    geometry.set_attribute(
        String(COLOR), BufferAttribute([1, 1, 1], 3, mesh_per_attribute=3)
    )
    assert_equal(geometry.drawn_instances(), 3)
    geometry.set_attribute(
        String("more"),
        BufferAttribute([1, 2, 3, 4, 5], 1, mesh_per_attribute=1),
    )
    assert_equal(geometry.drawn_instances(), 3)
    geometry.set_instance_count(2)
    assert_equal(geometry.drawn_instances(), 2)
    geometry.instance_count = None
    assert_equal(geometry.drawn_instances(), 3)
    # The field is open; a negative count put there is refused when read.
    geometry.instance_count = -3
    with assert_raises(contains="cannot be negative"):
        _ = geometry.drawn_instances()


def test_an_instanced_geometry_keeps_its_instances_when_flattened() raises:
    var geometry = BufferGeometry(instanced=True)
    geometry.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    geometry.set_attribute(
        String("offset"),
        BufferAttribute([0, 0, 0, 2, 0, 0], 3, mesh_per_attribute=1),
    )
    geometry.set_index([0, 1, 2, 2, 1, 0])
    geometry.set_instance_count(1)
    var flat = geometry.to_non_indexed()
    assert_true(flat.instanced)
    assert_equal(flat.instance_count.value(), 1)
    assert_equal(flat.vertex_count(), 6)
    assert_equal(flat.attribute_view(String("offset")).count(), 2)
    assert_true(flat.attribute_view(String("offset")).is_instanced())


def test_the_utilities_refuse_an_instanced_geometry() raises:
    var geometry = BufferGeometry(instanced=True)
    geometry.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    var parts = List[BufferGeometry]()
    parts.append(cube(Length(1.0, METER)))
    parts.append(geometry.clone())
    with assert_raises(contains="instanced geometry is not merged"):
        _ = merge_geometries(parts)
    with assert_raises(contains="instanced geometry is not welded"):
        _ = merge_vertices(geometry)


def test_the_utilities_read_an_interleaved_geometry() raises:
    var plain = cube(Length(1.0, METER))
    var parts = List[BufferGeometry]()
    parts.append(interleave(plain))
    parts.append(plain.clone())
    var merged = merge_geometries(parts)
    assert_equal(merged.vertex_count(), 2 * plain.vertex_count())
    assert_equal(
        merged.attribute_view(String(UV)).component(3, 1),
        plain.attribute_view(String(UV)).component(3, 1),
    )
    var welded = merge_vertices(interleave(plain))
    assert_equal(welded.vertex_count(), merge_vertices(plain).vertex_count())
    # Morph targets on a shared buffer merge as plain ones do.
    var one = BufferGeometry()
    one.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    var target = InterleavedBuffer([1, 2, 3, 4, 5, 6], 6)
    one.add_morph_target(
        BufferAttribute(target, 3, 0), BufferAttribute(target, 3, 3)
    )
    var twice = List[BufferGeometry]()
    twice.append(one.clone())
    twice.append(one.clone())
    var both = merge_geometries(twice)
    assert_equal(both.morph_positions[0].data[4], 2)
    assert_equal(both.morph_normals[0].data[5], 6)


def test_the_morph_evaluator_reads_an_interleaved_target() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    var target = InterleavedBuffer([9, 2, 4, 6], 4)
    geometry.add_morph_target(BufferAttribute(target, 3, 1))
    var influences = MorphInfluences()
    influences.set(0, 0.5)
    var worn = morphed_positions(geometry, influences)
    assert_equal(worn[0].x, 1)
    assert_equal(worn[0].y, 2)
    assert_equal(worn[0].z, 3)


# --- the renderer -----------------------------------------------------------


def test_an_interleaved_sphere_draws_as_the_plain_one() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var plain = Assets()
    var mixed = Assets()
    var ball = sphere(Length(1.2, METER), 12, 8)
    var one = plain.geometries.add(ball.clone())
    var two = mixed.geometries.add(interleave(ball))
    var paint = Material(Color(200, 120, 40), kind=LAMBERT)
    var first = plain.materials.add(paint.copy())
    var second = mixed.materials.add(paint.copy())
    var scene = lit_scene()
    scene.add_mesh(Mesh(one, first, NodeId(1)))
    var other = lit_scene()
    other.add_mesh(Mesh(two, second, NodeId(1)))
    var image = renderer.render(other, mixed, a_camera())
    assert_true(count_drawn(image, renderer.background) > 15, "little drawn")
    assert_same_image(image, renderer.render(scene, plain, a_camera()))


def instanced_boxes(
    offsets: List[Float32], colors: List[Float32], per: Int
) raises -> BufferGeometry:
    """Return an instanced box with per-instance offsets and colors.

    Args:
        offsets: Three numbers an instance.
        colors: Three numbers every `per` instances, or none.
        per: The colors' mesh per attribute.

    Returns:
        The geometry.

    Raises:
        Error: If the numbers do not divide into items.
    """
    var box = cube(Length(0.8, METER))
    var geometry = BufferGeometry(instanced=True)
    for slot in range(box.attribute_count()):
        geometry.set_attribute(box.names[slot], box.values[slot].copy())
    geometry.set_index(box.index.copy())
    geometry.set_attribute(
        String("offset"),
        BufferAttribute(offsets.copy(), 3, mesh_per_attribute=1),
    )
    if len(colors) > 0:
        geometry.set_attribute(
            String(COLOR),
            BufferAttribute(colors.copy(), 3, mesh_per_attribute=per),
        )
    return geometry^


def test_an_instanced_geometry_draws_as_meshes_at_its_offsets() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var places: List[Vector3] = [
        Vector3(-1.5, 0, 0),
        Vector3(0, 0.6, -1),
        Vector3(1.5, -0.4, 0.5),
    ]
    var offsets: List[Float32] = [-1.5, 0, 0, 0, 0.6, -1, 1.5, -0.4, 0.5]
    var paint = Material(Color(90, 200, 60), kind=BASIC)
    var plain = meshes_at(paint, places)
    var geometry = instanced_boxes(offsets, List[Float32](), 1)
    var drawn = one_mesh_scene(geometry, paint)
    var image = renderer.render(drawn[0], drawn[1], a_camera())
    assert_true(count_drawn(image, renderer.background) > 15, "little drawn")
    assert_same_image(image, renderer.render(plain[0], plain[1], a_camera()))
    # No instances: nothing drawn.
    geometry.set_instance_count(0)
    var none = one_mesh_scene(geometry, paint)
    assert_equal(
        count_drawn(
            renderer.render(none[0], none[1], a_camera()), renderer.background
        ),
        0,
    )


def test_instances_without_offsets_draw_in_one_place() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var paint = Material(Color(90, 200, 60), kind=BASIC)
    var box = cube(Length(0.8, METER))
    var twice = BufferGeometry(instanced=True)
    for slot in range(box.attribute_count()):
        twice.set_attribute(box.names[slot], box.values[slot].copy())
    twice.set_index(box.index.copy())
    twice.set_instance_count(2)
    var drawn = one_mesh_scene(twice, paint)
    var wanted = one_mesh_scene(box, paint)
    var image = renderer.render(drawn[0], drawn[1], a_camera())
    assert_true(count_drawn(image, renderer.background) > 15, "little drawn")
    assert_same_image(image, renderer.render(wanted[0], wanted[1], a_camera()))


def test_a_per_instance_color_colors_each_instance() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    # Two instances share the first color, as `mesh_per_attribute` two
    # says, and the third takes the second.
    var offsets: List[Float32] = [-1.5, 0, 0, 0, 0, 0, 1.5, 0, 0]
    var colors: List[Float32] = [1, 0.5, 0.25, 0.2, 0.4, 1]
    var paint = Material(Color(255, 255, 255), kind=BASIC)
    paint.vertex_colors = True
    var drawn = one_mesh_scene(instanced_boxes(offsets, colors, 2), paint)
    # The same boxes as plain meshes, each with its color per vertex.
    var plain = Assets()
    var wanted = Scene()
    var box = cube(Length(0.8, METER))
    var which: List[Int] = [0, 0, 1]
    for index in range(3):
        var tinted = box.clone()
        var own = List[Float32]()
        for _ in range(box.vertex_count()):
            for lane in range(3):
                own.append(colors[which[index] * 3 + lane])
        tinted.set_attribute(String(COLOR), BufferAttribute(own^, 3))
        var node = Object3D()
        node.set_position(offsets[index * 3], 0, 0)
        wanted.add_mesh(
            Mesh(
                plain.geometries.add(tinted^),
                plain.materials.add(paint.copy()),
                wanted.add(node^),
            )
        )
    wanted.update()
    var image = renderer.render(drawn[0], drawn[1], a_camera())
    assert_true(count_drawn(image, renderer.background) > 15, "little drawn")
    assert_same_image(image, renderer.render(wanted, plain, a_camera()))


def test_a_per_instance_color_outside_an_instanced_draw_reads_the_first() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var paint = Material(Color(255, 255, 255), kind=BASIC)
    paint.vertex_colors = True
    var box = cube(Length(1.0, METER))
    var first = box.clone()
    first.set_attribute(
        String(COLOR),
        BufferAttribute([0.2, 0.9, 0.4, 1, 0, 0], 3, mesh_per_attribute=1),
    )
    var second = box.clone()
    var own = List[Float32]()
    for _ in range(box.vertex_count()):
        own.append(0.2)
        own.append(0.9)
        own.append(0.4)
    second.set_attribute(String(COLOR), BufferAttribute(own^, 3))
    var one = one_mesh_scene(first, paint)
    var two = one_mesh_scene(second, paint)
    var image = renderer.render(one[0], one[1], a_camera())
    assert_true(count_drawn(image, renderer.background) > 15, "little drawn")
    assert_same_image(image, renderer.render(two[0], two[1], a_camera()))


def test_the_renderer_refuses_what_it_does_not_draw_per_instance() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var paint = Material(Color(255, 255, 255), kind=BASIC)
    for name in [
        String(POSITION),
        String(NORMAL),
        String(UV),
        String("tangent"),
    ]:
        var geometry = instanced_boxes([0, 0, 0], List[Float32](), 1)
        geometry.set_attribute(
            name, BufferAttribute([0, 0, 1, 0], 2, mesh_per_attribute=1)
        )
        var drawn = one_mesh_scene(geometry, paint)
        with assert_raises(contains="per-instance"):
            _ = renderer.render(drawn[0], drawn[1], a_camera())


def test_a_hidden_mesh_is_not_read() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.node(node).visible = False
    scene.update()
    # Names a geometry that is not there, which is never asked for.
    scene.add_mesh(
        Mesh(
            GeometryId(4),
            assets.materials.add(Material(Color(1, 2, 3))),
            node,
        )
    )
    var image = renderer.render(scene, assets, a_camera())
    assert_equal(count_drawn(image, renderer.background), 0)


# --- the raycaster ----------------------------------------------------------


def test_a_ray_meets_an_interleaved_geometry_where_it_meets_the_plain() raises:
    var ball = sphere(Length(1.0, METER), 12, 8)
    var hits = List[Float32]()
    var scenes = List[Tuple[Scene, Assets]]()
    scenes.append(one_mesh_scene(ball))
    scenes.append(one_mesh_scene(interleave(ball)))
    for which in range(2):
        var ray = Raycaster(Vector3(0.1, 0.2, 5), Vector3(0, 0, -1))
        var found = ray.intersect_scene(scenes[which][0], scenes[which][1])
        assert_equal(len(found), 1)
        hits.append(found[0].distance)
        hits.append(found[0].point.x)
    assert_equal(hits[0], hits[2])
    assert_equal(hits[1], hits[3])


# --- the exporters and the loader -------------------------------------------


def test_the_exporters_write_an_interleaved_geometry_as_the_plain() raises:
    var box = cube(Length(1.0, METER))
    var tinted = box.clone()
    var colors = List[Float32]()
    for vertex in range(box.vertex_count()):
        colors.append(Float32(vertex % 3) * 0.5)
        colors.append(0.25)
        colors.append(1)
    tinted.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var mixed = interleave(box)
    var shared = InterleavedBuffer(
        tinted.attribute_view(String(COLOR)).packed(), 3
    )
    mixed.set_attribute(String(COLOR), BufferAttribute(shared, 3, 0))
    var one = one_mesh_scene(tinted)
    var two = one_mesh_scene(mixed)
    assert_equal(export_obj(one[0], one[1]), export_obj(two[0], two[1]))
    assert_equal(object_to_json(one[0], one[1]), object_to_json(two[0], two[1]))
    var first = export_gltf(one[0], one[1])
    var second = export_gltf(two[0], two[1])
    assert_equal(len(first.document), len(second.document))
    for at in range(len(first.document)):
        assert_equal(first.document[at], second.document[at])


def test_an_instanced_geometry_round_trips_through_json() raises:
    var geometry = instanced_boxes([0, 0, 0, 1, 0, 0], [1, 0, 0], 2)
    geometry.set_instance_count(2)
    var written = one_mesh_scene(geometry)
    var text = object_to_json(written[0], written[1])
    assert_true("InstancedBufferGeometry" in text)
    var scene = Scene()
    var assets = Assets()
    _ = read_object_json(text, scene, assets)
    ref read = assets.geometries.get(GeometryId(0))
    assert_true(read.instanced)
    assert_equal(read.instance_count.value(), 2)
    assert_equal(read.attribute_view(String(COLOR)).mesh_per_attribute(), 2)
    assert_false(read.attribute_view(String(POSITION)).is_instanced())
    # Left unbounded, the count is written as null and read back as none.
    var unbounded = instanced_boxes([0, 0, 0], List[Float32](), 1)
    var again = one_mesh_scene(unbounded)
    var open_text = object_to_json(again[0], again[1])
    assert_true('"instanceCount":null' in open_text)
    var other = Scene()
    var more = Assets()
    _ = read_object_json(open_text, other, more)
    assert_false(Bool(more.geometries.get(GeometryId(0)).instance_count))


def wrap(geometry: String) -> String:
    """Return an Object document of one geometry and a group."""
    return (
        '{"metadata":{"version":4.6,"type":"Object"},"geometries":['
        + geometry
        + '],"object":{"uuid":"o","type":"Group"}}'
    )


# One triangle, a position and a uv a vertex, as three.js writes it: the
# floats as the 32-bit words of their bytes. 1065353216 is 1.0.
comptime WORDS = (
    "[0,0,0,0,0,1065353216,0,0,1065353216,0,0,1065353216,0,0,1065353216]"
)
comptime ATTRIBUTES = (
    '"attributes":{"position":{"isInterleavedBufferAttribute":true,'
    '"itemSize":3,"data":"ib","offset":0,"normalized":false},'
    '"uv":{"isInterleavedBufferAttribute":true,"itemSize":2,"data":"ib",'
    '"offset":3,"normalized":false}}'
)


def interleaved_document(buffer: String, words: String) -> String:
    """Return a document of one interleaved geometry.

    Args:
        buffer: The `interleavedBuffers` entry for `ib`.
        words: The `arrayBuffers` entry for `ab`.

    Returns:
        The document.
    """
    return wrap(
        '{"uuid":"g","type":"BufferGeometry","data":{'
        + ATTRIBUTES
        + ',"interleavedBuffers":{"ib":'
        + buffer
        + '},"arrayBuffers":{"ab":'
        + words
        + "}}}"
    )


def read_one(document: String) raises -> BufferGeometry:
    """Return the first geometry a document holds."""
    var scene = Scene()
    var assets = Assets()
    _ = read_object_json(document, scene, assets)
    return assets.geometries.get(GeometryId(0)).clone()


def refuses(document: String, message: String) raises:
    """Assert a document is refused with a message."""
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains=message):
        _ = read_object_json(document, scene, assets)


comptime BUFFER = '{"uuid":"ib","buffer":"ab","type":"Float32Array","stride":5}'


def test_the_loader_reads_an_interleaved_geometry_as_three_js_writes_it() raises:
    var geometry = read_one(interleaved_document(BUFFER, WORDS))
    ref positions = geometry.attribute_view(String(POSITION))
    ref uvs = geometry.attribute_view(String(UV))
    assert_true(positions.is_interleaved())
    assert_true(
        positions.interleaved_buffer().shares_with(uvs.interleaved_buffer())
    )
    assert_equal(positions.count(), 3)
    assert_equal(positions.vector3(1).x, 1)
    assert_equal(uvs.component(2, 1), 1)
    assert_equal(uvs.component(1, 1), 0)
    # An instanced interleaved buffer keeps its mesh per attribute.
    var instanced = read_one(
        interleaved_document(
            '{"uuid":"ib","buffer":"ab","type":"Float32Array","stride":5,'
            + '"isInstancedInterleavedBuffer":true,"meshPerAttribute":3}',
            WORDS,
        )
    )
    assert_equal(instanced.attribute_view(String(UV)).mesh_per_attribute(), 3)


def test_the_loader_reads_an_instanced_geometry() raises:
    var head = '{"uuid":"g","type":"InstancedBufferGeometry",'
    var tail = (
        '"data":{"attributes":{"offset":{"itemSize":3,"type":"Float32Array",'
        + '"array":[0,0,0,1,1,1],"isInstancedBufferAttribute":true},'
        + '"color":{"itemSize":3,"type":"Float32Array","array":[1,1,1],'
        + '"isInstancedBufferAttribute":true,"meshPerAttribute":2}}}}'
    )
    var counted = read_one(
        wrap(
            head + '"isInstancedBufferGeometry":true,"instanceCount":3,' + tail
        )
    )
    assert_true(counted.instanced)
    assert_equal(counted.instance_count.value(), 3)
    assert_equal(
        counted.attribute_view(String("offset")).mesh_per_attribute(), 1
    )
    assert_equal(counted.attribute_view(String(COLOR)).mesh_per_attribute(), 2)
    var unbounded = read_one(
        wrap(head + '"isInstancedBufferGeometry":true,' + tail)
    )
    assert_false(Bool(unbounded.instance_count))
    # A geometry that does not say it is instanced is not, and its
    # instance count is not read.
    var plain = read_one(wrap(head + '"instanceCount":-4,' + tail))
    assert_false(plain.instanced)
    refuses(
        wrap(
            head + '"isInstancedBufferGeometry":true,"instanceCount":-1,' + tail
        ),
        "cannot be negative",
    )


def test_the_loader_refuses_an_interleaved_attribute_it_cannot_build() raises:
    refuses(
        interleaved_document(
            '{"uuid":"ib","buffer":"ab","type":"Uint8Array","stride":5}', WORDS
        ),
        "only a Float32Array buffer",
    )
    refuses(
        interleaved_document(
            '{"uuid":"ib","buffer":"xx","type":"Float32Array","stride":5}',
            WORDS,
        ),
        "has no array",
    )
    refuses(interleaved_document(BUFFER, "[0,-1,0,0,0]"), "32 bits")
    refuses(interleaved_document(BUFFER, "[0,4294967296,0,0,0]"), "32 bits")
    refuses(interleaved_document(BUFFER, "[0,2143289344,0,0,0]"), "not finite")
    refuses(interleaved_document(BUFFER, "[0,0,0,0]"), "divide evenly")
    # An empty array is a buffer of no vertices.
    assert_equal(read_one(interleaved_document(BUFFER, "[]")).vertex_count(), 0)
    var no_buffers = wrap(
        '{"uuid":"g","type":"BufferGeometry","data":{' + ATTRIBUTES + "}}"
    )
    refuses(no_buffers, "names no interleaved buffer")
    var no_arrays = wrap(
        '{"uuid":"g","type":"BufferGeometry","data":{'
        + ATTRIBUTES
        + ',"interleavedBuffers":{"ib":'
        + BUFFER
        + "}}}"
    )
    refuses(no_arrays, "has no array")
    var other_buffer = wrap(
        '{"uuid":"g","type":"BufferGeometry","data":{'
        + ATTRIBUTES
        + ',"interleavedBuffers":{"other":'
        + BUFFER
        + "}}}"
    )
    refuses(other_buffer, "names no interleaved buffer")
    # An instance matrix is not in a geometry, so it has no buffers.
    refuses(
        '{"metadata":{"version":4.6,"type":"Object"},"geometries":[{"uuid":'
        + '"g","type":"BufferGeometry","data":{"attributes":{}}}],'
        + '"materials":[{"uuid":"m","type":"MeshBasicMaterial"}],'
        + '"object":{"uuid":"o","type":"InstancedMesh","geometry":"g",'
        + '"material":"m","count":1,"instanceMatrix":{'
        + '"isInterleavedBufferAttribute":true,"itemSize":16,"data":"ib"}}}',
        "outside a geometry",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
