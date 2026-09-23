# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `exporters.gltf`.

The key test is the round trip: a scene written in each of the three
containers reads back through `loaders.gltf` to the same node transforms,
the same geometry, the same materials and the same texels. The rest walks
every choice the writer makes and every refusal.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from exporters.gltf import (
    GLB,
    GLTF_EMBEDDED,
    GLTF_SEPARATE,
    GltfContainer,
    binary_name_for,
    encode_base64,
    export_gltf,
    gltf_pixels,
    index_component,
    write_gltf,
)
from loaders.gltf import (
    COMPONENT_UNSIGNED_INT,
    COMPONENT_UNSIGNED_SHORT,
    GltfModel,
    decode_base64,
    load_gltf,
    read_gltf,
    split_glb,
)
from loaders.json import parse_json
from materials.material import (
    BASIC,
    DOUBLE_SIDE,
    NO_TEXTURE,
    PHONG,
    Material,
    MaterialId,
    standard_material,
)
from math.euler import XYZ
from math.matrix4 import Matrix4, translation
from math.vector2 import Vector2
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    MIRROR,
    NEAREST,
    REPEAT,
    Filter,
    Texture,
    Wrap,
    float_texture,
)
from render.texture_store import TextureId
from std.math import sqrt
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE

comptime TOLERANCE = Float64(1e-5)


def image(
    width: Int,
    height: Int,
    seed: Int,
    wrap: Wrap = REPEAT,
    filter: Filter = BILINEAR,
    mipmapped: Bool = True,
) raises -> Texture:
    """Return a texture whose every texel is different."""
    var pixels = List[UInt8]()
    for texel in range(width * height):
        pixels.append(UInt8((seed + texel * 17) % 256))
        pixels.append(UInt8((seed * 3 + texel * 29) % 256))
        pixels.append(UInt8((seed * 7 + texel * 41) % 256))
        pixels.append(255)
    return Texture(width, height, pixels^, wrap, filter, SRGB, mipmapped)


def quad(indexed: Bool) raises -> BufferGeometry:
    """Return a square, two triangles, with every attribute written."""
    var geometry = BufferGeometry()
    if indexed:
        geometry.set_attribute(
            String(POSITION),
            BufferAttribute(
                [Float32(-1), -1, 0, 1, -1, 0, 1, 1, 0.25, -1, 1, 0.5], 3
            ),
        )
        geometry.set_attribute(
            String(NORMAL),
            BufferAttribute(
                [Float32(0), 0, 1, 0, 0, 1, 0, 0.6, 0.8, 0, 0, 1], 3
            ),
        )
        geometry.set_attribute(
            String(UV),
            BufferAttribute([Float32(0), 0, 1, 0, 1, 1, 0, 1], 2),
        )
        geometry.set_attribute(
            String(COLOR),
            BufferAttribute(
                [Float32(1), 0, 0, 0, 1, 0, 0, 0, 1, 0.5, 0.5, 0.5], 3
            ),
        )
        geometry.set_index([0, 1, 2, 0, 2, 3])
    else:
        geometry.set_attribute(
            String(POSITION),
            BufferAttribute(
                [
                    Float32(0),
                    0,
                    0,
                    2,
                    0,
                    0,
                    0,
                    3,
                    -1.5,
                    2,
                    0,
                    0,
                    2,
                    3,
                    0,
                    0,
                    3,
                    0,
                ],
                3,
            ),
        )
        geometry.set_attribute(
            String(COLOR),
            BufferAttribute(
                [
                    Float32(1),
                    0,
                    0,
                    1,
                    0,
                    1,
                    0,
                    0.5,
                    0,
                    0,
                    1,
                    1,
                    1,
                    1,
                    1,
                    1,
                    0,
                    0,
                    0,
                    1,
                    0.25,
                    0.5,
                    0.75,
                    0,
                ],
                4,
            ),
        )
    return geometry^


def assert_floats(got: List[Float32], expected: List[Float32]) raises:
    """Assert two lists of numbers are equal, number by number."""
    assert_equal(len(got), len(expected))
    for index in range(len(got)):
        assert_equal(got[index], expected[index])


def assert_same_geometry(
    got: BufferGeometry, expected: BufferGeometry, colored: Bool
) raises:
    """Assert a geometry read back holds exactly what was written."""
    for name in [String(POSITION), String(NORMAL), String(UV)]:
        assert_equal(got.has_attribute(name), expected.has_attribute(name))
        if expected.has_attribute(name):
            assert_floats(
                got.attribute_view(name).data,
                expected.attribute_view(name).data,
            )
    assert_equal(got.has_attribute(String(COLOR)), colored)
    if colored:
        ref color = got.attribute_view(String(COLOR))
        assert_equal(
            color.item_size, expected.attribute_view(String(COLOR)).item_size
        )
        assert_floats(color.data, expected.attribute_view(String(COLOR)).data)
    assert_equal(len(got.index), len(expected.index))
    for index in range(len(got.index)):
        assert_equal(got.index[index], expected.index[index])


def assert_same_matrix(got: Matrix4, expected: Matrix4) raises:
    """Assert two matrices agree to within rounding."""
    for index in range(16):
        assert_almost_equal(
            got.elements[index], expected.elements[index], atol=TOLERANCE
        )


def assert_flipped(got: Texture, expected: Texture) raises:
    """Assert a texture read back holds the other's rows upside down, and
    samples the same."""
    assert_equal(got.width, expected.width)
    assert_equal(got.height, expected.height)
    var row = expected.width * 4
    for y in range(expected.height):
        for x in range(row):
            assert_equal(
                got.pixels[y * row + x],
                expected.pixels[(expected.height - 1 - y) * row + x],
            )
    assert_equal(got.repeat.y, -1)
    assert_equal(got.offset.y, 1)


def assert_same_texels(got: Texture, expected: Texture) raises:
    """Assert two textures hold the same full-size image."""
    assert_equal(got.width, expected.width)
    assert_equal(got.height, expected.height)
    for index in range(expected.width * expected.height * 4):
        assert_equal(got.pixels[index], expected.pixels[index])


struct Built(Movable):
    """The scene the round trip writes, and what it is made of."""

    var scene: Scene
    var assets: Assets
    var shiny: MaterialId
    var painted: MaterialId
    var flat: MaterialId

    def __init__(out self) raises:
        self.scene = Scene()
        self.assets = Assets()
        var picture = self.assets.textures.add(image(4, 3, 1))
        var data = self.assets.textures.add(
            image(2, 2, 5, CLAMP, NEAREST, True)
        )
        var bumps = self.assets.textures.add(
            image(3, 1, 9, MIRROR, BILINEAR, False)
        )
        var shiny = standard_material(
            Color(200, 100, 50),
            map=picture,
            roughness=0.25,
            metalness=0.75,
            side=DOUBLE_SIDE,
            opacity=0.5,
            roughness_map=data,
            metalness_map=data,
            normal_map=bumps,
            normal_scale=Vector2(0.5, 0.5),
            emissive=Color(10, 20, 30),
            emissive_map=picture,
        )
        shiny.vertex_colors = True
        shiny.alpha_test = 0.25
        self.shiny = self.assets.materials.add(shiny)
        self.painted = self.assets.materials.add(
            Material(
                Color(20, 40, 60), kind=PHONG, transparent=True, opacity=0.75
            )
        )
        self.flat = self.assets.materials.add(
            Material(Color(255, 255, 255), kind=BASIC, vertex_colors=True)
        )
        var square = self.assets.geometries.add(quad(True))
        var strip = self.assets.geometries.add(quad(False))

        var root = Object3D()
        root.name = "root"
        root.set_position(1, 2, 3)
        root.set_euler(
            Angle(10.0, DEGREE), Angle(20.0, DEGREE), Angle(30.0, DEGREE)
        )
        root.set_scale(2, 2, 2)
        var top = self.scene.add(root^)
        var fixed = Object3D()
        fixed.name = "fixed"
        fixed.matrix_auto_update = False
        fixed.matrix = translation(4, 5, 6)
        var child = self.scene.attach(fixed^, top)
        var hidden = Object3D()
        hidden.visible = False
        var gone = self.scene.attach(hidden^, top)
        var plain = Object3D()
        plain.name = 'plain "quoted"'
        var other = self.scene.add(plain^)
        var still = Object3D()
        still.matrix_auto_update = False
        _ = self.scene.attach(still^, other)
        var turned = Object3D()
        turned.set_euler(
            Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE)
        )
        _ = self.scene.attach(turned^, gone)
        self.scene.add_mesh(Mesh(square, self.shiny, top))
        self.scene.add_mesh(Mesh(strip, self.painted, child))
        self.scene.add_mesh(Mesh(strip, self.flat, child))
        self.scene.add_mesh(Mesh(square, self.shiny, child))
        self.scene.add_mesh(Mesh(square, self.flat, gone))
        self.scene.update()


def read_back(
    files_document: List[UInt8], binary: List[UInt8], container: GltfContainer
) raises -> Tuple[Scene, Assets, GltfModel]:
    """Read a written file back through the loader."""
    var scene = Scene()
    var assets = Assets()
    var model: GltfModel
    if container == GLB:
        var parts = split_glb(files_document)
        model = load_gltf(parts[0], parts[1], "", scene, assets)
    else:
        if len(binary) > 0:
            Path("out/export_separate.bin").write_bytes(binary)
        model = load_gltf(
            String(unsafe_from_utf8=files_document),
            List[UInt8](),
            "out/",
            scene,
            assets,
        )
    return (scene^, assets^, model^)


def check_round_trip(container: GltfContainer) raises:
    """Write the built scene in one container and read it back."""
    var built = Built()
    var files = export_gltf(
        built.scene, built.assets, container, "export_separate.bin"
    )
    assert_equal(len(files.binary) > 0, container == GLTF_SEPARATE)
    var back = read_back(files.document, files.binary, container)
    ref scene = back[0]
    ref assets = back[1]
    ref model = back[2]
    scene.update()
    # The hidden node and everything under it are left out.
    assert_equal(model.node_count(), 4)
    assert_equal(scene.count(), 4)
    var kept = [0, 1, 3, 4]
    var names = [
        String("root"),
        String("fixed"),
        String('plain "quoted"'),
        String(""),
    ]
    for at in range(4):
        assert_equal(model.node_names[at], names[at])
        assert_same_matrix(
            scene.world_matrix(model.nodes[at]),
            built.scene.world_matrix(NodeId(kept[at])),
        )
    var root = scene.get(model.nodes[0])
    assert_almost_equal(root.position.y, 2, atol=TOLERANCE)
    assert_almost_equal(root.scale.x, 2, atol=TOLERANCE)
    # Four meshes on two nodes: one on the root, three on the child.
    assert_equal(model.mesh_count, 4)
    assert_equal(len(model.first_primitives), 2)
    assert_equal(model.primitive_counts[1], 3)
    var expected = [0, 1, 2, 3]
    for at in range(4):
        ref got = scene.meshes[at]
        ref wanted = built.scene.meshes[expected[at]]
        var material = assets.materials.get(got.material)
        var original = built.assets.materials.get(wanted.material)
        assert_same_geometry(
            assets.geometries.get(got.geometry),
            built.assets.geometries.get(wanted.geometry),
            original.vertex_colors,
        )
        assert_equal(material.color.r, original.color.r)
        assert_equal(material.color.g, original.color.g)
        assert_equal(material.color.b, original.color.b)
        assert_almost_equal(material.opacity, original.opacity, atol=TOLERANCE)
        assert_equal(material.vertex_colors, original.vertex_colors)
        assert_equal(material.is_transparent(), original.is_transparent())
    # The standard material, field by field.
    var shiny = assets.materials.get(scene.meshes[0].material)
    var original = built.assets.materials.get(built.shiny)
    assert_equal(shiny.roughness, original.roughness)
    assert_equal(shiny.metalness, original.metalness)
    assert_equal(shiny.side, DOUBLE_SIDE)
    assert_equal(shiny.alpha_test, original.alpha_test)
    assert_equal(shiny.normal_scale.x, 0.5)
    assert_equal(shiny.emissive.r, original.emissive.r)
    assert_equal(shiny.emissive.g, original.emissive.g)
    assert_equal(shiny.emissive.b, original.emissive.b)
    assert_true(shiny.roughness_map == shiny.metalness_map)
    assert_flipped(
        assets.textures.get(shiny.map), built.assets.textures.get(original.map)
    )
    assert_flipped(
        assets.textures.get(shiny.roughness_map),
        built.assets.textures.get(original.roughness_map),
    )
    assert_flipped(
        assets.textures.get(shiny.normal_map),
        built.assets.textures.get(original.normal_map),
    )
    assert_flipped(
        assets.textures.get(shiny.emissive_map),
        built.assets.textures.get(original.emissive_map),
    )
    ref data = assets.textures.get(shiny.roughness_map)
    assert_equal(data.filter, NEAREST)
    assert_equal(data.wrap, CLAMP)
    assert_true(data.levels > 1)
    ref bumps = assets.textures.get(shiny.normal_map)
    assert_equal(bumps.wrap, MIRROR)
    assert_equal(bumps.levels, 1)
    # The Phong material comes back with three.js's metalness and
    # roughness for a material that is not physical.
    var painted = assets.materials.get(scene.meshes[1].material)
    assert_equal(painted.metalness, 0)
    assert_equal(painted.roughness, 1)


def test_an_embedded_gltf_reads_back_to_the_same_scene() raises:
    check_round_trip(GLTF_EMBEDDED)


def test_a_gltf_beside_its_bin_reads_back_to_the_same_scene() raises:
    check_round_trip(GLTF_SEPARATE)


def test_a_glb_reads_back_to_the_same_scene() raises:
    check_round_trip(GLB)


def test_the_document_says_what_the_specification_asks() raises:
    var built = Built()
    var files = export_gltf(built.scene, built.assets)
    var document = parse_json(String(unsafe_from_utf8=files.document))
    var root = document.root()
    var asset = document.get(root, "asset")
    assert_equal(document.string(document.get(asset, "version")), "2.0")
    var used = document.get(root, "extensionsUsed")
    assert_equal(document.string(document.at(used, 0)), "KHR_materials_unlit")
    # POSITION carries its bounds; the others do not.
    var accessors = document.get(root, "accessors")
    var first = document.at(accessors, 0)
    var low = document.get(first, "min")
    var high = document.get(first, "max")
    assert_equal(document.number(document.at(low, 0)), -1)
    assert_equal(document.number(document.at(high, 2)), 0.5)
    assert_false(document.has(document.at(accessors, 1), "min"))
    # The node that keeps its own matrix writes it; a node that moves
    # nothing writes no transform at all.
    var nodes = document.get(root, "nodes")
    assert_true(document.has(document.at(nodes, 1), "matrix"))
    assert_false(document.has(document.at(nodes, 1), "translation"))
    var still = document.at(nodes, 3)
    assert_false(document.has(still, "matrix"))
    assert_false(document.has(still, "name"))
    # The shared geometry is written once, its colors once.
    var meshes = document.get(root, "meshes")
    var primitives = document.get(document.at(meshes, 1), "primitives")
    var one = document.get(document.at(primitives, 0), "attributes")
    var two = document.get(document.at(primitives, 1), "attributes")
    assert_equal(
        document.integer(document.get(one, "POSITION")),
        document.integer(document.get(two, "POSITION")),
    )
    assert_false(document.has(one, "COLOR_0"))
    assert_true(document.has(two, "COLOR_0"))
    # Two materials of three with a map share one sampler per setting.
    assert_equal(document.length(document.get(root, "samplers")), 3)
    assert_equal(document.length(document.get(root, "textures")), 3)
    assert_equal(document.length(document.get(root, "materials")), 3)


def test_every_node_is_kept_when_asked() raises:
    var built = Built()
    var files = export_gltf(built.scene, built.assets, GLB, only_visible=False)
    var back = read_back(files.document, List[UInt8](), GLB)
    ref scene = back[0]
    ref model = back[2]
    scene.update()
    assert_equal(model.node_count(), 6)
    assert_equal(model.mesh_count, 5)
    # Nodes are written in `traverse` order, so node 5 is where that
    # order puts it.
    var order = built.scene.traverse()
    var at = 0
    while order[at] != NodeId(5):
        at += 1
    assert_same_matrix(
        scene.world_matrix(model.nodes[at]),
        built.scene.world_matrix(NodeId(5)),
    )


def test_a_file_written_to_disk_reads_back() raises:
    var built = Built()
    write_gltf("out/export_disk.gltf", built.scene, built.assets, GLTF_SEPARATE)
    assert_true(Path("out/export_disk.bin").exists())
    var scene = Scene()
    var assets = Assets()
    var model = read_gltf("out/export_disk.gltf", scene, assets)
    assert_equal(model.mesh_count, 4)
    write_gltf("out/export_disk.glb", built.scene, built.assets, GLB)
    var again = Scene()
    var more = Assets()
    var read = read_gltf("out/export_disk.glb", again, more)
    assert_equal(read.mesh_count, 4)
    # A scene with nothing to put in a buffer writes no .bin.
    var empty = Scene()
    _ = empty.add(Object3D())
    write_gltf("out/export_empty.gltf", empty, Assets(), GLTF_SEPARATE)
    assert_false(Path("out/export_empty.bin").exists())


def test_an_empty_scene_writes_a_file_that_reads() raises:
    for container in [GLTF_EMBEDDED, GLTF_SEPARATE, GLB]:
        var files = export_gltf(Scene(), Assets(), container)
        var back = read_back(files.document, files.binary, container)
        assert_equal(back[2].node_count(), 0)
        assert_equal(len(files.binary), 0)
    # A GLB with no buffer has one chunk.
    var glb = export_gltf(Scene(), Assets(), GLB)
    assert_equal(len(glb.document) % 4, 0)
    var parts = split_glb(glb.document)
    assert_equal(len(parts[1]), 0)


def test_a_texture_read_from_gltf_is_written_as_it_is() raises:
    # Written once, the image is flipped; read back, the texture carries
    # the flip; written again, its image is kept, and the texels agree.
    var built = Built()
    var files = export_gltf(built.scene, built.assets, GLB)
    var first = read_back(files.document, List[UInt8](), GLB)
    first[0].update()
    var again = export_gltf(first[0], first[1], GLB)
    var second = read_back(again.document, List[UInt8](), GLB)
    var once = first[1].materials.get(first[0].meshes[0].material)
    var twice = second[1].materials.get(second[0].meshes[0].material)
    assert_same_texels(
        second[1].textures.get(twice.map), first[1].textures.get(once.map)
    )


def test_two_maps_are_combined_into_one_image() raises:
    var assets = Assets()
    var rough = assets.textures.add(image(2, 2, 3))
    var metal = assets.textures.add(image(2, 2, 8))
    var both = assets.materials.add(
        standard_material(
            Color(255, 255, 255), roughness_map=rough, metalness_map=metal
        )
    )
    var rough_only = assets.materials.add(
        standard_material(Color(255, 255, 255), roughness_map=rough)
    )
    var metal_only = assets.materials.add(
        standard_material(Color(255, 255, 255), metalness_map=metal)
    )
    var shape = assets.geometries.add(quad(True))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, both, node))
    scene.add_mesh(Mesh(shape, rough_only, node))
    scene.add_mesh(Mesh(shape, metal_only, node))
    scene.add_mesh(Mesh(shape, both, node))
    var files = export_gltf(scene, assets, GLB)
    var back = read_back(files.document, List[UInt8](), GLB)
    ref loaded = back[1]
    ref drawn = back[0].meshes
    ref combined = loaded.textures.get(
        loaded.materials.get(drawn[0].material).roughness_map
    )
    ref greens = loaded.textures.get(
        loaded.materials.get(drawn[1].material).roughness_map
    )
    ref blues = loaded.textures.get(
        loaded.materials.get(drawn[2].material).metalness_map
    )
    var source_rough = gltf_pixels(assets.textures.get(rough))
    var source_metal = gltf_pixels(assets.textures.get(metal))
    for texel in range(4):
        var at = texel * 4
        assert_equal(combined.pixels[at], 0)
        assert_equal(combined.pixels[at + 1], source_rough[at + 1])
        assert_equal(combined.pixels[at + 2], source_metal[at + 2])
        assert_equal(greens.pixels[at + 1], source_rough[at + 1])
        assert_equal(greens.pixels[at + 2], 255)
        assert_equal(blues.pixels[at + 1], 255)
        assert_equal(blues.pixels[at + 2], source_metal[at + 2])
    # Three combined textures, the last material reusing the first.
    var document = parse_json(split_glb(files.document)[0])
    assert_equal(document.length(document.get(document.root(), "textures")), 3)


def test_textures_of_one_image_write_it_once() raises:
    # three.js's `processImage` caches by source: two textures of one
    # image, tiled and clamped, are two textures and two samplers over one
    # image. A third image of the same size is its own.
    var assets = Assets()
    var tiled = assets.textures.add(image(2, 2, 3, REPEAT))
    var clamped = assets.textures.add(image(2, 2, 3, CLAMP))
    var other = assets.textures.add(image(2, 2, 8))
    var paint = assets.materials.add(
        standard_material(
            Color(255, 255, 255),
            map=tiled,
            emissive_map=clamped,
            ao_map=other,
        )
    )
    var scene = Scene()
    scene.add_mesh(
        Mesh(assets.geometries.add(quad(True)), paint, scene.add(Object3D()))
    )
    var files = export_gltf(scene, assets, GLB)
    var document = parse_json(split_glb(files.document)[0])
    var root = document.root()
    assert_equal(document.length(document.get(root, "textures")), 3)
    assert_equal(document.length(document.get(root, "samplers")), 2)
    assert_equal(document.length(document.get(root, "images")), 2)
    var back = read_back(files.document, List[UInt8](), GLB)
    var color_map = back[1].materials.get(back[0].meshes[0].material).map
    var glow_map = (
        back[1].materials.get(back[0].meshes[0].material).emissive_map
    )
    var color_pixels = back[1].textures.get(color_map).pixels.copy()
    assert_true(color_pixels == back[1].textures.get(glow_map).pixels)


def test_a_single_vertex_and_a_plain_normal_map_are_written() raises:
    # One vertex, its bounds its own; and a normal map at scale one, which
    # writes no scale.
    var assets = Assets()
    var dot = BufferGeometry()
    dot.set_attribute(String(POSITION), BufferAttribute([Float32(1), 2, 3], 3))
    dot.set_index([0, 0, 0])
    var bumps = assets.textures.add(image(2, 2, 6))
    var scene = one_mesh(
        assets, standard_material(Color(9, 9, 9), normal_map=bumps), dot^
    )
    var files = export_gltf(scene, assets)
    var document = parse_json(String(unsafe_from_utf8=files.document))
    var root = document.root()
    var first = document.at(document.get(root, "accessors"), 0)
    assert_equal(document.number(document.at(document.get(first, "min"), 2)), 3)
    assert_equal(document.number(document.at(document.get(first, "max"), 0)), 1)
    var material = document.at(document.get(root, "materials"), 0)
    assert_false(document.has(document.get(material, "normalTexture"), "scale"))
    var back = read_back(files.document, List[UInt8](), GLTF_EMBEDDED)
    ref loaded = back[1]
    var normal = loaded.materials.get(back[0].meshes[0].material)
    assert_equal(normal.normal_scale.x, 1)


def test_the_small_helpers_give_what_the_format_asks() raises:
    assert_equal(index_component(3), COMPONENT_UNSIGNED_SHORT)
    assert_equal(index_component(65535), COMPONENT_UNSIGNED_SHORT)
    assert_equal(index_component(65536), COMPONENT_UNSIGNED_INT)
    assert_equal(binary_name_for("out/models/scene.gltf"), "scene.bin")
    assert_equal(binary_name_for("scene"), "scene.bin")
    assert_equal(binary_name_for("a.b/.hidden"), ".hidden.bin")
    for length in range(7):
        var bytes = List[UInt8]()
        for index in range(length):
            bytes.append(UInt8(index * 77 % 256))
        var text = encode_base64(bytes)
        assert_equal(text.byte_length() % 4, 0)
        var back = decode_base64(text)
        assert_equal(len(back), length)
        for index in range(length):
            assert_equal(back[index], bytes[index])
    assert_equal(encode_base64([UInt8(77), 97, 110]), "TWFu")
    assert_equal(encode_base64([UInt8(77)]), "TQ==")
    assert_equal(encode_base64([UInt8(77), 97]), "TWE=")
    assert_true(GLB.is_valid())
    assert_false(GltfContainer(3).is_valid())


def one_mesh(
    mut assets: Assets, var material: Material, var geometry: BufferGeometry
) raises -> Scene:
    """Return a scene of one mesh on one node."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var shape = assets.geometries.add(geometry^)
    var paint = assets.materials.add(material)
    scene.add_mesh(Mesh(shape, paint, node))
    return scene^


def test_what_glTF_cannot_hold_is_refused() raises:
    var assets = Assets()
    var scene = one_mesh(assets, Material(Color(1, 2, 3)), quad(True))
    with assert_raises(contains="none of the three"):
        _ = export_gltf(scene, assets, GltfContainer(9))
    with assert_raises(contains="relative name"):
        _ = export_gltf(scene, assets, GLTF_SEPARATE, "")
    with assert_raises(contains="relative name"):
        _ = export_gltf(scene, assets, GLTF_SEPARATE, "http://x/y.bin")
    # A mesh on a node that is not there, past the end or below zero.
    var stray = one_mesh(assets, Material(Color(1, 2, 3)), quad(True))
    stray.meshes[0].node = NodeId(5)
    with assert_raises(contains="not in the scene"):
        _ = export_gltf(stray, assets)
    stray.meshes[0].node = NodeId(-1)
    with assert_raises(contains="not in the scene"):
        _ = export_gltf(stray, assets)
    # A geometry with no vertices.
    var nothing = BufferGeometry()
    nothing.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    var hollow = one_mesh(assets, Material(Color(1, 2, 3)), nothing^)
    with assert_raises(contains="no vertices"):
        _ = export_gltf(hollow, assets)
    # A blank texture, one of an unknown wrap, and two maps of two sizes.
    var blank = assets.textures.add(Texture())
    var blank_map = one_mesh(
        assets, Material(Color(1, 2, 3), map=blank), quad(True)
    )
    with assert_raises(contains="blank"):
        _ = export_gltf(blank_map, assets)
    # An HDR image: no eight-bit PNG holds it.
    var bright = assets.textures.add(float_texture(1, 1, [4, 4, 4, 1]))
    var bright_map = one_mesh(
        assets, Material(Color(1, 2, 3), map=bright), quad(True)
    )
    with assert_raises(contains="float texture"):
        _ = export_gltf(bright_map, assets)
    var odd_texture = image(2, 2, 4)
    odd_texture.wrap = Wrap(9)
    var odd = assets.textures.add(odd_texture^)
    var odd_map = one_mesh(
        assets, Material(Color(1, 2, 3), map=odd), quad(True)
    )
    with assert_raises(contains="wrap"):
        _ = export_gltf(odd_map, assets)
    var small = assets.textures.add(image(2, 2, 4))
    var large = assets.textures.add(image(4, 2, 4))
    var tall = assets.textures.add(image(2, 4, 4))
    for other in [large, tall]:
        var mismatched = one_mesh(
            assets,
            standard_material(
                Color(1, 2, 3), roughness_map=small, metalness_map=other
            ),
            quad(True),
        )
        with assert_raises(contains="one size"):
            _ = export_gltf(mismatched, assets)
    var blank_metal = one_mesh(
        assets,
        standard_material(Color(1, 2, 3), metalness_map=blank),
        quad(True),
    )
    with assert_raises(contains="blank"):
        _ = export_gltf(blank_metal, assets)
    # A material or a texture that is not there.
    var missing = one_mesh(
        assets, Material(Color(1, 2, 3), map=TextureId(99)), quad(True)
    )
    with assert_raises():
        _ = export_gltf(missing, assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
