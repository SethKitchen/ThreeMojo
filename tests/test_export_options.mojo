# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the exporter and loader options of issue 200, against
three.js.

`assets/exporters/three.json` holds what three.js 0.180 writes and reads
for the scenes built here; `assets/exporters/three_exporters.mjs` writes
it. The key tests compare the OBJ, STL, PLY and USDZ files byte for
byte: one scene of a mesh, a skinned mesh, an instanced mesh, three
lines and points. The glTF tests compare `extras` and `extensions`, and
what `read_gltf` and `parse_ply` read. The rest walks every refusal.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from core.user_data import UserData, json_value_text
from exporters.common import (
    WORLD_LINE,
    WORLD_MESH,
    WORLD_POINTS,
    WorldKind,
    WorldOptions,
    format_js_float32,
    world_meshes,
)
from exporters.gltf import GltfExportOptions, export_gltf, write_gltf
from exporters.obj import export_obj, srgb_channel
from exporters.ply import export_ply, write_ply
from exporters.stl import STL_BINARY, export_stl
from exporters.usdz import usdz_files
from loaders.gltf import decode_base64, load_gltf
from loaders.json import JsonDocument, NO_NODE, parse_json
from loaders.ply import (
    PLY_BINARY_BIG_ENDIAN,
    PLY_BINARY_LITTLE_ENDIAN,
    PlyOptions,
    parse_ply,
    read_ply,
)
from loaders.mtl import (
    MtlOptions,
    parse_mtl,
    read_mtl,
    read_obj_with_materials,
)
from materials.material import (
    BACK_SIDE,
    BASIC,
    DOUBLE_SIDE,
    Material,
    MaterialId,
    Side,
    standard_material,
)
from math.matrix4 import translation
from objects.instanced_mesh import InstancedMesh
from objects.line import LOOP, SEGMENTS, STRIP, Line
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Color
from render.texture import CLAMP, MIRROR, Texture, Wrap
from std.math import inf
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TRIANGLE: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]


def shape(
    var positions: List[Float32],
    normals: List[Float32] = List[Float32](),
    uvs: List[Float32] = List[Float32](),
    colors: List[Float32] = List[Float32](),
) raises -> BufferGeometry:
    """Return a geometry of positions and the attributes given."""
    var out = BufferGeometry()
    out.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    if len(normals) > 0:
        out.set_attribute(String(NORMAL), BufferAttribute(normals.copy(), 3))
    if len(uvs) > 0:
        out.set_attribute(String(UV), BufferAttribute(uvs.copy(), 2))
    if len(colors) > 0:
        out.set_attribute(String(COLOR), BufferAttribute(colors.copy(), 3))
    return out^


def named(name: String, x: Float32, y: Float32, z: Float32) -> Object3D:
    """Return a node with a name at a place."""
    var node = Object3D()
    node.name = name
    node.set_position(x, y, z)
    return node^


struct Model(Movable):
    """The scene `three_exporters.mjs` builds: a mesh, a skinned mesh and
    an instanced mesh, and with `lines` three lines and points.

    three.js has made nine geometries and five materials before the ones
    `USDZExporter` names, so the stores start with as many unused ones.
    """

    var scene: Scene
    var assets: Assets
    var bone: NodeId

    def __init__(out self, lines: Bool) raises:
        self.scene = Scene()
        self.assets = Assets()
        for _ in range(9):
            _ = self.assets.geometries.add(shape(materialize[TRIANGLE]()))
        for _ in range(5):
            _ = self.assets.materials.add(Material(Color(0, 0, 0)))
        var standard = self.assets.materials.add(
            standard_material(Color(255, 255, 255))
        )
        var square = shape(
            [0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0],
            normals=[0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1],
            uvs=[0, 0, 1, 0, 1, 1, 0, 1],
        )
        square.set_index([0, 1, 2, 0, 2, 3])
        var plain = named("plain", 1, 2, 3)
        plain.set_scale(2, 2, 2)
        var one = self.scene.add(plain^)
        self.scene.add_mesh(
            Mesh(self.assets.geometries.add(square^), standard, one)
        )
        var limb = shape(materialize[TRIANGLE]())
        limb.set_attribute(
            String(SKIN_INDEX),
            BufferAttribute(List[Float32](length=12, fill=0), 4),
        )
        limb.set_attribute(
            String(SKIN_WEIGHT),
            BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4),
        )
        var limb_id = self.assets.geometries.add(limb^)
        var two = self.scene.add(named("skin", 0, 0, 0))
        self.bone = self.scene.attach(named("bone", 0, 1, 0), two)
        self.scene.update()
        var skeleton = bind_skeleton(
            [self.bone], [self.scene.world_matrix(self.bone)]
        )
        self.scene.add_skinned_mesh(
            SkinnedMesh(limb_id, standard, two, skeleton^)
        )
        self.scene.node(self.bone).set_position(0, 3, 0)
        var three = self.scene.add(named("many", -2, 0, 0))
        var many = InstancedMesh(
            self.assets.geometries.add(shape(materialize[TRIANGLE]())),
            standard,
            three,
            2,
        )
        many.set_matrix_at(1, translation(5, 0, 0))
        self.scene.add_instanced_mesh(many^)
        if lines:
            var ink = self.assets.materials.add(Material(Color(255, 255, 255)))
            var path = self.scene.add(named("path", 0, 0, 1))
            self.scene.add_line(
                Line(
                    self.assets.geometries.add(
                        shape([0, 0, 0, 1, 0, 0, 1, 1, 0])
                    ),
                    ink,
                    path,
                )
            )
            var sticks = self.scene.add(named("sticks", 0, 0, 0))
            self.scene.add_line(
                Line(
                    self.assets.geometries.add(
                        shape([0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 4, 0, 0])
                    ),
                    ink,
                    sticks,
                    mode=SEGMENTS,
                )
            )
            var loop = self.scene.add(named("loop", 0, 0, 0))
            self.scene.add_line(
                Line(
                    self.assets.geometries.add(shape(materialize[TRIANGLE]())),
                    ink,
                    loop,
                    mode=LOOP,
                )
            )
            var cloud = self.scene.add(named("cloud", 0, -1, 0))
            self.scene.add_points(
                Points(
                    self.assets.geometries.add(
                        shape(
                            [0, 0, 0, 0.5, 0, 0, 0, 0.25, 0],
                            normals=[0, 1, 0, 0, 1, 0, 0, 1, 0],
                            colors=[0, 0.002, 1, 1, 0, 0, 0.001, 1, 0],
                        )
                    ),
                    ink,
                    cloud,
                )
            )
        self.scene.update()


struct Reference(Movable):
    """The file three.js wrote, parsed."""

    var document: JsonDocument

    def __init__(out self) raises:
        self.document = parse_json(
            Path("assets/exporters/three.json").read_text()
        )

    def node(self, key: String) raises -> Int:
        """Return a top-level entry."""
        return self.document.get(self.document.root(), key)

    def text(self, key: String) raises -> String:
        """Return a top-level string."""
        return self.document.string(self.node(key))

    def bytes(self, key: String) raises -> List[UInt8]:
        """Return a top-level base64 string's bytes."""
        return decode_base64(self.text(key))

    def json(self, node: Int) raises -> String:
        """Return a value as canonical JSON text."""
        return json_value_text(self.document, node)


def as_text(bytes: List[UInt8]) -> String:
    """Return bytes as text."""
    return String(unsafe_from_utf8=bytes)


# --- the model exporters against three.js ------------------------------------


def test_obj_matches_three_js() raises:
    var model = Model(True)
    assert_equal(export_obj(model.scene, model.assets), Reference().text("obj"))


def test_stl_matches_three_js_with_the_skin_posed() raises:
    var model = Model(True)
    var three = Reference()
    assert_equal(
        as_text(export_stl(model.scene, model.assets)), three.text("stl_ascii")
    )
    assert_true(
        export_stl(model.scene, model.assets, STL_BINARY)
        == three.bytes("stl_binary")
    )


def test_ply_matches_three_js() raises:
    var full = Model(True)
    var meshes = Model(False)
    var three = Reference()
    assert_equal(
        as_text(export_ply(full.scene, full.assets, exclude_colors=True)),
        three.text("ply_points_ascii"),
    )
    assert_true(
        export_ply(
            full.scene,
            full.assets,
            PLY_BINARY_LITTLE_ENDIAN,
            exclude_colors=True,
        )
        == three.bytes("ply_points_little")
    )
    assert_equal(
        as_text(export_ply(meshes.scene, meshes.assets)),
        three.text("ply_faces_ascii"),
    )
    assert_true(
        export_ply(meshes.scene, meshes.assets, PLY_BINARY_BIG_ENDIAN)
        == three.bytes("ply_faces_big")
    )
    assert_equal(
        as_text(
            export_ply(
                meshes.scene,
                meshes.assets,
                exclude_index=True,
                exclude_normals=True,
                exclude_uvs=True,
            )
        ),
        three.text("ply_cloud_ascii"),
    )


def test_usdz_matches_three_js() raises:
    var model = Model(False)
    var files = usdz_files(model.scene, model.assets)
    var three = Reference()
    var written = three.document.get(three.node("usdz"), "files")
    assert_equal(len(files.names), three.document.length(written))
    for at in range(len(files.names)):
        var name = files.names[at]
        assert_equal(
            files.text(name),
            three.document.string(three.document.get(written, name)),
        )


# --- what world_meshes gathers ------------------------------------------------


def test_world_meshes_gathers_by_the_exporter_s_options() raises:
    var model = Model(True)
    var rest = world_meshes(model.scene, model.assets)
    assert_equal(len(rest), 3)
    # The skin at rest, and posed by its bone two up.
    assert_equal(rest[1].positions[7], 1)
    var posed = world_meshes(
        model.scene, model.assets, WorldOptions(posed=True)
    )
    assert_equal(posed[1].positions[7], 3)
    assert_false(posed[1].with_normals)
    var all = world_meshes(
        model.scene, model.assets, WorldOptions(lines=True, points=True)
    )
    assert_equal(len(all), 7)
    assert_true(all[3].kind == WORLD_LINE and all[3].line_mode == STRIP)
    assert_true(all[4].line_mode == SEGMENTS)
    assert_true(all[6].kind == WORLD_POINTS and all[6].with_normals)
    assert_true(all[0].kind == WORLD_MESH)
    assert_true(WORLD_POINTS.is_valid())
    assert_false(WorldKind(3).is_valid())
    # A removed node is left out with what it carries.
    model.scene.remove(NodeId(0))
    model.scene.update()
    assert_equal(len(world_meshes(model.scene, model.assets)), 2)


def test_an_object_on_a_node_the_scene_has_not_got_is_refused() raises:
    var model = Model(True)
    model.scene.points[0].node = NodeId(99)
    with assert_raises(contains="Points names a node"):
        _ = export_obj(model.scene, model.assets)
    model.scene.lines[0].node = NodeId(-1)
    with assert_raises(contains="A line names a node"):
        _ = export_obj(model.scene, model.assets)
    model.scene.instanced_meshes[0].node = NodeId(99)
    with assert_raises(contains="A mesh names a node"):
        _ = export_stl(model.scene, model.assets)
    model.scene.skinned_meshes[0].node = NodeId(99)
    with assert_raises(contains="A mesh names a node"):
        _ = export_stl(model.scene, model.assets)
    model.scene.meshes[0].node = NodeId(99)
    with assert_raises(contains="A mesh names a node"):
        _ = export_stl(model.scene, model.assets)


def test_a_posed_skin_without_its_attributes_is_refused() raises:
    var model = Model(False)
    model.assets.geometries.geometries[10] = shape(materialize[TRIANGLE]())
    # At rest, the skin is not read.
    _ = export_obj(model.scene, model.assets)
    with assert_raises(contains="skinIndex"):
        _ = export_stl(model.scene, model.assets)


# --- OBJ lines and points ------------------------------------------------------


def test_an_obj_point_color_is_encoded_as_three_js_encodes_it() raises:
    assert_equal(srgb_channel(0.001), 0.012920000613667071)
    assert_equal(srgb_channel(1), 0.9999999999999999)
    assert_equal(format_js_float32(0.5), "0.5")
    assert_equal(format_js_float32(0.1), "0.10000000149011612")
    with assert_raises(contains="finite"):
        _ = format_js_float32(inf[DType.float32]())


def test_an_obj_line_of_no_points_and_points_with_no_colors() raises:
    var assets = Assets()
    var ink = assets.materials.add(Material(Color(0, 0, 0)))
    var scene = Scene()
    var node = scene.add(named("n", 0, 0, 0))
    var empty = assets.geometries.add(shape(List[Float32]()))
    scene.add_line(Line(empty, ink, node))
    scene.add_line(Line(empty, ink, node, mode=SEGMENTS))
    scene.add_points(Points(assets.geometries.add(shape([1, 2, 3])), ink, node))
    scene.update()
    assert_equal(
        export_obj(scene, assets), "o n\nl \no n\no n\nv 1 2 3\np 1 \n"
    )


# --- PLY options ---------------------------------------------------------------


def test_a_ply_with_faces_needs_whole_triangles() raises:
    var assets = Assets()
    var paint = assets.materials.add(Material(Color(0, 0, 0)))
    var scene = Scene()
    var node = scene.add(Object3D())
    var ragged = shape([0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0])
    scene.add_mesh(Mesh(assets.geometries.add(ragged^), paint, node))
    scene.update()
    with assert_raises(contains="whole triangles to be written"):
        _ = export_ply(scene, assets)
    # A point cloud has no faces, and needs none.
    var text = as_text(export_ply(scene, assets, exclude_index=True))
    assert_equal(text.find("element face"), -1)
    assert_true(text.endswith("1 1 0\n\n"))
    write_ply("out/cloud.ply", scene, assets, exclude_index=True)
    assert_equal(read_ply("out/cloud.ply").vertex_count(), 4)
    # Points with texture coordinates write them once a mesh has some.
    var dotted = Scene()
    var spot = dotted.add(Object3D())
    var square = shape([0, 0, 0, 1, 0, 0, 0, 1, 0], uvs=[0, 0, 1, 0, 0, 1])
    dotted.add_mesh(Mesh(assets.geometries.add(square^), paint, spot))
    var marks = shape([5, 5, 5], uvs=[0.5, 0.25], colors=[0, 0, 0])
    dotted.add_points(Points(assets.geometries.add(marks^), paint, spot))
    dotted.update()
    var both = as_text(export_ply(dotted, assets))
    assert_true(
        both.endswith("0 1 0 0 1 255 255 255\n5 5 5 0.5 0.25 0 0 0\n\n")
    )


# --- glTF user data and options ----------------------------------------------


def user_scene(
    mut assets: Assets, mut options: GltfExportOptions
) raises -> Scene:
    """Return the scene of `userScene` in `three_exporters.mjs`."""
    var scene = Scene()
    options.scene_user_data.set_string("s", "scene")
    options.scene_user_data.set_json(
        "gltfExtensions", '{"EXT_scene":{"on":true}}'
    )
    var holder = Object3D()
    holder.name = "holder"
    holder.user_data.set_string("tag", "node")
    holder.user_data.set_number("n", 1)
    holder.user_data.set_json("list", '[1,"two",null]')
    holder.user_data.set_json("gltfExtensions", '{"EXT_node":{"a":1}}')
    var top = scene.add(holder^)
    var paint = assets.materials.add(standard_material(Color(255, 255, 255)))
    var worn = UserData()
    worn.set_boolean("m", True)
    worn.set_json("gltfExtensions", '{"EXT_mat":{"b":[1,2]}}')
    options.set_material_user_data(paint, worn)
    var thing = Object3D()
    thing.name = "thing"
    thing.user_data.set_json("only", '{"gltfExtensions":3}')
    var under = scene.attach(thing^, top)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(shape(materialize[TRIANGLE]())), paint, under
        )
    )
    var bare = Object3D()
    bare.name = "bare"
    bare.user_data.set_json("gltfExtensions", '{"EXT_bare":{}}')
    _ = scene.add(bare^)
    scene.update()
    return scene^


def compare_user_parts(
    ours: JsonDocument, three: Reference, theirs: Int
) raises:
    """Assert the extras and extensions of the nodes, the material and the
    scene match three.js's, and the extensions used."""
    var one = ours.root()
    var two = theirs
    ref doc = three.document
    for list in [String("nodes"), String("materials"), String("scenes")]:
        var mine = ours.get(one, list)
        var their = doc.get(two, list)
        assert_equal(ours.length(mine), doc.length(their))
        for at in range(ours.length(mine)):
            for key in [String("extras"), String("extensions")]:
                var a = ours.get(ours.at(mine, at), key)
                var b = doc.get(doc.at(their, at), key)
                assert_equal(a == NO_NODE, b == NO_NODE, list + " " + key)
                if a != NO_NODE:
                    assert_equal(
                        json_value_text(ours, a), json_value_text(doc, b)
                    )
    var used = ours.get(one, "extensionsUsed")
    var expected = doc.get(two, "extensionsUsed")
    assert_equal(used == NO_NODE, expected == NO_NODE)
    if used != NO_NODE:
        assert_equal(ours.length(used), doc.length(expected))
        for at in range(doc.length(expected)):
            var name = doc.string(doc.at(expected, at))
            var found = False
            for slot in range(ours.length(used)):
                found = found or ours.string(ours.at(used, slot)) == name
            assert_true(found, name)


def test_gltf_user_data_matches_three_js() raises:
    var three = Reference()
    for custom in [False, True]:
        var assets = Assets()
        var options = GltfExportOptions()
        options.include_custom_extensions = custom
        var scene = user_scene(assets, options)
        var files = export_gltf(scene, assets, options=options)
        var ours = parse_json(as_text(files.document))
        compare_user_parts(
            ours, three, three.node("gltf_custom" if custom else "gltf_plain")
        )


def test_gltf_custom_extensions_merge_with_the_exporter_s() raises:
    var assets = Assets()
    var options = GltfExportOptions()
    options.include_custom_extensions = True
    var scene = Scene()
    var node = Object3D()
    node.user_data.set_json(
        "gltfExtensions", '{"EXT_first":1,"EXT_mesh_gpu_instancing":{"x":1}}'
    )
    var id = scene.add(node^)
    var many = InstancedMesh(
        assets.geometries.add(shape(materialize[TRIANGLE]())),
        assets.materials.add(standard_material(Color(1, 2, 3))),
        id,
        1,
    )
    scene.add_instanced_mesh(many^)
    var text = as_text(export_gltf(scene, assets, options=options).document)
    var found = parse_json(text)
    var extensions = found.get(
        found.at(found.get(found.root(), "nodes"), 0), "extensions"
    )
    assert_equal(found.key(extensions, 0), "EXT_first")
    assert_equal(found.key(extensions, 1), "EXT_mesh_gpu_instancing")
    assert_true(
        found.has(
            found.get(extensions, "EXT_mesh_gpu_instancing"), "attributes"
        )
    )
    # Not an object: refused.
    var wrong = Scene()
    var odd = Object3D()
    odd.user_data.set_number("gltfExtensions", 3)
    _ = wrong.add(odd^)
    with assert_raises(contains="must be an object"):
        _ = export_gltf(wrong, assets, options=options)
    # Off, it is only extras.
    _ = export_gltf(wrong, assets)


def test_gltf_material_user_data_is_set_once_per_material() raises:
    var options = GltfExportOptions()
    var first = UserData()
    first.set_number("a", 1)
    var second = UserData()
    second.set_number("a", 2)
    options.set_material_user_data(MaterialId(3), first)
    options.set_material_user_data(MaterialId(3), second)
    options.set_material_user_data(MaterialId(4), first)
    assert_equal(len(options.material_ids), 2)
    assert_equal(options.material_data(MaterialId(3)).number("a"), 2)
    assert_equal(options.material_data(MaterialId(9)).count(), 0)


def test_gltf_max_texture_size_clamps_each_side() raises:
    var assets = Assets()
    var pixels = List[UInt8]()
    for texel in range(8):
        pixels.append(UInt8(texel * 30))
        pixels.append(0)
        pixels.append(0)
        pixels.append(255)
    var picture = Texture(4, 2, pixels^)
    var map = assets.textures.add(picture^)
    var scene = Scene()
    var id = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(shape(materialize[TRIANGLE]())),
            assets.materials.add(
                standard_material(Color(255, 255, 255), map=map)
            ),
            id,
        )
    )
    var options = GltfExportOptions()
    options.max_texture_size = 2
    var big = export_gltf(scene, assets)
    var small = export_gltf(scene, assets, options=options)
    assert_true(len(small.document) < len(big.document))
    options.max_texture_size = 8
    assert_equal(
        len(export_gltf(scene, assets, options=options).document),
        len(big.document),
    )
    options.max_texture_size = 0
    with assert_raises(contains="maxTextureSize"):
        _ = export_gltf(scene, assets, options=options)
    write_gltf("out/extras.gltf", scene, assets, options=GltfExportOptions())


def test_gltf_extras_read_as_three_js_reads_them() raises:
    var three = Reference()
    var expected = three.node("gltf_extras")
    ref doc = three.document
    var scene = Scene()
    var assets = Assets()
    var model = load_gltf(
        doc.string(doc.get(expected, "text")), List[UInt8](), "", scene, assets
    )
    var nodes = doc.get(expected, "nodes")
    for at in range(3):
        assert_equal(
            scene.get(model.nodes[at]).user_data.to_json(),
            json_value_text(doc, doc.at(nodes, at)),
        )
    assert_equal(
        model.mesh_extras[1].to_json(),
        json_value_text(doc, doc.at(doc.get(expected, "parts"), 0)),
    )
    assert_equal(
        model.material_extras[0].to_json(),
        json_value_text(doc, doc.get(expected, "material")),
    )
    assert_equal(
        model.scene_extras.to_json(),
        json_value_text(doc, doc.get(expected, "scene")),
    )


# --- the PLY loader's mappings -------------------------------------------------


def test_ply_property_names_map_as_three_js_maps_them() raises:
    var three = Reference()
    var expected = three.node("ply_mapped")
    ref doc = three.document
    var options = PlyOptions()
    options.set_property_name("cr", "red")
    options.set_property_name("cg", "blue")
    options.set_property_name("cg", "green")
    options.set_property_name("cb", "blue")
    options.set_custom_attribute("quality", ["q2"])
    options.set_custom_attribute("quality", ["q1", "q2"])
    options.set_custom_attribute("nothing", List[String]())
    var text = doc.string(doc.get(expected, "text"))
    var got = parse_ply(List[UInt8](text.as_bytes()), options)
    for name in [String("position"), String("color"), String("quality")]:
        var want = doc.get(expected, name)
        ref read = got.attribute_view(name)
        assert_equal(len(read.data), doc.length(want))
        for at in range(len(read.data)):
            assert_equal(Float64(read.data[at]), doc.number(doc.at(want, at)))
    assert_equal(got.attribute_view("quality").item_size, 2)
    assert_false(got.has_attribute("nothing"))
    var missing = PlyOptions()
    missing.set_custom_attribute("quality", ["q3"])
    with assert_raises(contains="which a vertex has not got"):
        _ = parse_ply(List[UInt8](text.as_bytes()), missing)
    Path("out/mapped.ply").write_text(text)
    assert_equal(read_ply("out/mapped.ply", options).vertex_count(), 2)


def test_a_posed_skin_and_indexed_points_and_lines() raises:
    var model = Model(False)
    # A posed skin carries no normals: STL writes face normals only.
    ref limb = model.assets.geometries.geometries[10]
    limb.set_attribute(
        String(NORMAL), BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    var posed = world_meshes(
        model.scene, model.assets, WorldOptions(posed=True)
    )
    assert_false(posed[1].with_normals)
    assert_true(world_meshes(model.scene, model.assets)[1].with_normals)
    # Points and a line read every vertex in order, whatever the index,
    # and a line's index need not be whole triangles.
    var assets = Assets()
    var ink = assets.materials.add(Material(Color(0, 0, 0)))
    var scene = Scene()
    var node = scene.add(named("n", 0, 0, 0))
    var dots = shape([0, 0, 0, 1, 0, 0, 2, 0, 0])
    dots.set_index([2, 1, 0])
    scene.add_points(Points(assets.geometries.add(dots^), ink, node))
    var pair = shape([0, 0, 0, 1, 0, 0])
    pair.index = [1, 0]
    scene.add_line(Line(assets.geometries.add(pair^), ink, node, mode=SEGMENTS))
    scene.add_points(
        Points(assets.geometries.add(shape(List[Float32]())), ink, node)
    )
    scene.update()
    var found = world_meshes(
        scene, assets, WorldOptions(lines=True, points=True)
    )
    assert_equal(found[1].triangles[0], 0)
    assert_equal(
        export_obj(scene, assets),
        (
            "o n\nv 0 0 0\nv 1 0 0\nl 1 2\no n\nv 0 0 0\nv 1 0 0\nv 2 0 0\np 3"
            " 4 5 \no n\np \n"
        ),
    )


def test_a_usdz_skinned_or_instanced_mesh_on_a_missing_node_is_refused() raises:
    var model = Model(False)
    model.scene.instanced_meshes[0].node = NodeId(99)
    with assert_raises(contains="USDZ: a mesh names a node"):
        _ = usdz_files(model.scene, model.assets)
    model.scene.skinned_meshes[0].node = NodeId(99)
    with assert_raises(contains="USDZ: a mesh names a node"):
        _ = usdz_files(model.scene, model.assets)


def test_gltf_custom_extensions_beside_a_material_s_own() raises:
    var assets = Assets()
    var options = GltfExportOptions()
    options.include_custom_extensions = True
    var paint = assets.materials.add(Material(Color(9, 9, 9), kind=BASIC))
    var worn = UserData()
    worn.set_json("gltfExtensions", '{"EXT_a":1,"EXT_b":2}')
    options.set_material_user_data(paint, worn)
    var scene = Scene()
    var holder = Object3D()
    holder.user_data.set_json("gltfExtensions", "{}")
    var id = scene.add(holder^)
    scene.add_mesh(
        Mesh(assets.geometries.add(shape(materialize[TRIANGLE]())), paint, id)
    )
    var found = parse_json(
        as_text(export_gltf(scene, assets, options=options).document)
    )
    var material = found.at(found.get(found.root(), "materials"), 0)
    var extensions = found.get(material, "extensions")
    assert_equal(found.length(extensions), 3)
    assert_equal(found.key(extensions, 2), "KHR_materials_unlit")
    assert_false(found.has(material, "extras"))
    var node = found.at(found.get(found.root(), "nodes"), 0)
    assert_false(found.has(node, "extensions"))
    assert_false(found.has(node, "extras"))


def test_gltf_texture_sides_clamp_one_at_a_time() raises:
    var assets = Assets()
    var scene = Scene()
    var id = scene.add(Object3D())
    for size in [(4, 2), (2, 4)]:
        var pixels = List[UInt8](length=size[0] * size[1] * 4, fill=200)
        var map = assets.textures.add(Texture(size[0], size[1], pixels^))
        scene.add_mesh(
            Mesh(
                assets.geometries.add(shape(materialize[TRIANGLE]())),
                assets.materials.add(
                    standard_material(Color(255, 255, 255), map=map)
                ),
                id,
            )
        )
    var options = GltfExportOptions()
    options.max_texture_size = 3
    var clamped = parse_json(
        as_text(export_gltf(scene, assets, options=options).document)
    )
    # Both images clamp to three by two and two by three, and differ.
    assert_equal(clamped.length(clamped.get(clamped.root(), "images")), 2)


def test_gltf_extras_of_joints_cameras_and_lights() raises:
    var text = String(
        '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0,1,2,3]}],'
        '"nodes":[{"mesh":0},{"mesh":0},{"mesh":0,"camera":0},'
        '{"mesh":0,"extensions":{"KHR_lights_punctual":{"light":0}}}],'
        '"extensionsUsed":["KHR_lights_punctual"],'
        '"extensions":{"KHR_lights_punctual":{"lights":[{"type":"point"}]}},'
        '"cameras":[{"type":"perspective","perspective":{"yfov":1,"znear":0.1}}],'
        '"skins":[{"joints":[]},{"joints":[0]}],'
        '"meshes":[{"primitives":[{"attributes":{"POSITION":0}}],'
        '"extras":{"m":1}}],'
        '"accessors":[{"bufferView":0,"componentType":5126,"count":3,'
        '"type":"VEC3"}],"bufferViews":[{"buffer":0,"byteLength":36}],'
        '"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;'
        'base64,AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"}]}'
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_gltf(text, List[UInt8](), "", scene, assets)
    # A joint is a bone, a node with a camera or a light is a group: none
    # of them is the mesh, so none takes its extras.
    assert_equal(scene.get(model.nodes[0]).user_data.count(), 0)
    assert_equal(scene.get(model.nodes[1]).user_data.to_json(), '{"m":1}')
    assert_equal(scene.get(model.nodes[2]).user_data.count(), 0)
    assert_equal(scene.get(model.nodes[3]).user_data.count(), 0)
    assert_equal(model.scene_extras.count(), 0)


def test_mtl_options_read_as_three_js_reads_them() raises:
    var assets = Assets()
    var text = String(
        "newmtl a\nKd 255 0 51\nKs 0 0 0\nKe 1 0 0\nTr 0.25\n"
        "map_Kd brick.png\nmap_Ke -clamp on brick.png\n"
    )
    var library = parse_mtl(
        text,
        "assets/",
        assets,
        MtlOptions(
            side=DOUBLE_SIDE,
            wrap=MIRROR,
            normalize_rgb=True,
            ignore_zero_rgbs=True,
            invert_tr_property=True,
        ),
    )
    var made = assets.materials.get(library.materials[0])
    assert_equal(made.color.r, 255)
    assert_equal(made.color.b, 51)
    # A `Ks` of zeros is skipped, so the default stays.
    assert_equal(made.specular.r, 17)
    assert_equal(made.emissive.r, 255)
    assert_true(made.side == DOUBLE_SIDE)
    assert_equal(made.opacity, 0.25)
    assert_true(assets.textures.get(made.map).wrap_s == MIRROR)
    assert_true(assets.textures.get(made.emissive_map).wrap_s == CLAMP)
    # A default material takes the side too.
    var fallback = library.create("missing", assets)
    assert_true(assets.materials.get(fallback).side == DOUBLE_SIDE)
    # Without the options: a zero specular is kept, and `Tr` is clear.
    var plain = parse_mtl("newmtl b\nKs 0 0 0\nKd 0 0 0\nTr 0.25\n", "", assets)
    var kept = assets.materials.get(plain.materials[0])
    assert_equal(kept.specular.r, 0)
    assert_equal(kept.opacity, 0.75)
    var black = parse_mtl(
        "newmtl c\nKd 0 0 0\nKs 1 1 1\n",
        "",
        assets,
        MtlOptions(ignore_zero_rgbs=True),
    )
    assert_equal(assets.materials.get(black.materials[0]).color.r, 255)
    with assert_raises(contains="from zero to one"):
        _ = parse_mtl(
            "newmtl d\nKd 256 0 0\n", "", assets, MtlOptions(normalize_rgb=True)
        )
    with assert_raises(contains="a side"):
        _ = parse_mtl("", "", assets, MtlOptions(side=Side(7)))
    with assert_raises(contains="a wrap"):
        _ = read_mtl("assets/mtl/first.mtl", assets, MtlOptions(wrap=Wrap(7)))
    with assert_raises(contains="a side"):
        _ = read_obj_with_materials(
            "assets/mtl/bare.obj", assets, MtlOptions(side=Side(9))
        )
    var read = read_obj_with_materials(
        "assets/mtl/bare.obj", assets, MtlOptions(side=BACK_SIDE)
    )
    assert_true(assets.materials.get(read.materials[0][0]).side == BACK_SIDE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
