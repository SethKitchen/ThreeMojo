# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.gltf`: the three fixtures under `assets/gltf/`, which
hold one cube three ways, and small documents written inline for every
accessor shape and every refusal.

The fixtures were written by a Python script with `struct` and `zlib`
alone: a cube of twenty-four corners with normals and texture coordinates,
thirty-six sixteen-bit indices, three materials, one two-by-two checker
texture, four nodes in two scenes. `box.gltf` names `box.bin` and
`checker.png`; `embedded.gltf` holds both as data URIs; `box.glb` holds
both in its binary chunk.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV
from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from lights.light import directional_light
from loaders.gltf import (
    GltfModel,
    decode_base64,
    decode_image,
    load_gltf,
    read_gltf,
    split_glb,
)
from materials.material import DOUBLE_SIDE, FRONT_SIDE, NO_TEXTURE, STANDARD
from math.vector3 import Vector3
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    IGNORED,
    LINEAR_MIPMAP_LINEAR,
    LINEAR_MIPMAP_NEAREST,
    MIRROR,
    NEAREST,
    REPEAT,
)
from renderers.renderer import Renderer
from std.math import pi
from std.pathlib import Path
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
comptime HERE = "assets/gltf/"
# A triangle's nine floats, as a base64 buffer.
comptime TRI = "AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"
# Three RGBA bytes: red, green, and blue at half alpha.
comptime COLORS = "/wAA/wD/AP8AAP9/"
comptime IDX16 = "AAABAAIA"
comptime IDX32 = "AAAAAAEAAAACAAAA"
comptime IDX8 = "AAEC"
# Two signed bytes and two signed shorts at their extremes.
comptime SIGNED = "gH8AgP9/"
# Two positions sixteen bytes apart, a float of padding after each.
comptime STRIDED = "AACAPwAAAEAAAEBAAADGQgAAgEAAAKBAAADAQAAAxEI="
# A two-by-two quad's corners, its coordinates and its indices.
comptime QUAD = "AACAvwAAgD8AAAAAAACAPwAAgD8AAAAAAACAPwAAgL8AAAAAAACAvwAAgL8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAgD8AAIA/AAAAAAAAgD8AAAIAAQAAAAMAAgA="
comptime CHECKER = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC"


def doc(body: String) -> String:
    """Return a glTF 2 document around `body`."""
    return '{"asset":{"version":"2.0"},' + body + "}"


def buffer(base64: String, length: Int) -> String:
    """Return a `buffers` array holding one data URI."""
    return (
        '"buffers":[{"byteLength":'
        + String(length)
        + ',"uri":"data:application/octet-stream;base64,'
        + base64
        + '"}]'
    )


def loaded(
    text: String, mut scene: Scene, mut assets: Assets
) raises -> GltfModel:
    """Load an inline document with no binary chunk."""
    return load_gltf(text, List[UInt8](), HERE, scene, assets)


def refused(text: String) raises -> String:
    """Return the message an inline document is refused with."""
    var scene = Scene()
    var assets = Assets()
    try:
        _ = loaded(text, scene, assets)
    except reason:
        return String(reason)
    raise Error("the document was accepted")


def triangle(extra: String = "", material: String = "") -> String:
    """Return a document with one triangle, `extra` after the primitive's
    attributes and `material` after the materials key."""
    return doc(
        buffer(TRI, 36)
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}'
        + extra
        + "}]}]"
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        + material
    )


def check_cube(
    model: GltfModel, scene: Scene, assets: Assets, first_mesh: Int
) raises:
    """Assert everything the three fixtures share."""
    # Four nodes, three reached from the first scene, each after its
    # parent, with the file's names.
    assert_equal(model.node_count(), 4)
    assert_equal(model.node_names[0], "Parent")
    assert_equal(model.node_names[3], "Elsewhere")
    assert_true(model.nodes[0] != NO_PARENT)
    assert_true(model.nodes[1] != NO_PARENT)
    assert_true(model.nodes[2] != NO_PARENT)
    assert_equal(model.nodes[3], NO_PARENT)
    var parent = scene.get(model.nodes[0])
    assert_almost_equal(parent.position.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(parent.position.z, Float32(3), atol=TOLERANCE)
    assert_equal(parent.parent, NO_PARENT)
    var child = scene.get(model.nodes[1])
    assert_equal(child.parent, model.nodes[0])
    assert_almost_equal(child.scale.y, Float32(2), atol=TOLERANCE)
    assert_almost_equal(child.quaternion.y, Float32(0.7071068), atol=1e-6)
    assert_almost_equal(child.quaternion.w, Float32(0.7071068), atol=1e-6)
    # The matrix node: a quarter turn about z at twice the size, moved.
    var twisted = scene.get(model.nodes[2])
    assert_almost_equal(twisted.position.x, Float32(5), atol=TOLERANCE)
    assert_almost_equal(twisted.position.y, Float32(6), atol=TOLERANCE)
    assert_almost_equal(twisted.position.z, Float32(7), atol=TOLERANCE)
    assert_almost_equal(twisted.scale.x, Float32(2), atol=1e-5)
    assert_almost_equal(twisted.scale.z, Float32(2), atol=1e-5)
    assert_almost_equal(twisted.quaternion.z, Float32(0.7071068), atol=1e-5)
    assert_almost_equal(twisted.quaternion.w, Float32(0.7071068), atol=1e-5)
    assert_almost_equal(twisted.quaternion.x, Float32(0), atol=1e-6)
    # Two meshes, three primitives, three geometries.
    assert_equal(len(model.first_primitives), 2)
    assert_equal(model.primitive_counts[0], 1)
    assert_equal(model.primitive_counts[1], 2)
    assert_equal(len(model.geometries), 3)
    assert_equal(len(model.mesh_geometries(1)), 2)
    assert_equal(model.mesh_geometries(1)[0], model.geometries[1])
    with assert_raises():
        _ = model.mesh_geometries(2)
    ref box = assets.geometries.get(model.geometries[0])
    assert_equal(box.vertex_count(), 24)
    assert_equal(box.triangle_count(), 12)
    assert_true(box.is_indexed())
    assert_true(box.has_attribute(String(NORMAL)))
    assert_true(box.has_attribute(String(UV)))
    var first = box.corner(0, 0)
    assert_almost_equal(first.x, Float32(-0.5), atol=TOLERANCE)
    assert_almost_equal(first.z, Float32(0.5), atol=TOLERANCE)
    assert_equal(box.corner_index(1, 2), 3)
    ref uv = box.attribute_view(String(UV))
    assert_equal(uv.component(0, 0), Float32(0))
    assert_equal(uv.component(0, 1), Float32(1))
    ref plain = assets.geometries.get(model.geometries[1])
    assert_false(plain.has_attribute(String(NORMAL)))
    assert_false(plain.is_indexed())
    assert_equal(plain.triangle_count(), 8)
    # Three materials, and a default for the primitive that names none.
    assert_equal(len(model.materials), 3)
    var painted = assets.materials.get(model.materials[0])
    assert_equal(painted.kind, STANDARD)
    assert_equal(painted.color.r, UInt8(255))
    assert_equal(painted.color.g, UInt8(188))
    assert_equal(painted.color.b, UInt8(137))
    assert_almost_equal(painted.roughness, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(painted.metalness, Float32(0.25), atol=TOLERANCE)
    assert_equal(painted.side, DOUBLE_SIDE)
    assert_equal(painted.emissive.g, UInt8(137))
    assert_equal(painted.emissive.r, UInt8(0))
    assert_true(painted.map != NO_TEXTURE)
    assert_equal(painted.map, model.color_textures[0])
    assert_equal(model.data_textures[0], NO_TEXTURE)
    var glass = assets.materials.get(model.materials[1])
    assert_true(glass.transparent)
    assert_almost_equal(glass.opacity, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(glass.metalness, Float32(0), atol=TOLERANCE)
    assert_equal(glass.side, FRONT_SIDE)
    assert_equal(glass.map, NO_TEXTURE)
    var cutout = assets.materials.get(model.materials[2])
    assert_almost_equal(cutout.alpha_test, Float32(0.3), atol=TOLERANCE)
    assert_almost_equal(cutout.metalness, Float32(1), atol=TOLERANCE)
    assert_almost_equal(cutout.roughness, Float32(1), atol=TOLERANCE)
    assert_equal(cutout.color.r, UInt8(255))
    # The checker at its sampler's settings, with `flipY` off as three.js
    # reads every glTF texture, and no transform.
    ref checker = assets.textures.get(model.color_textures[0])
    assert_equal(checker.width, 2)
    assert_equal(checker.wrap_s, CLAMP)
    assert_equal(checker.mag_filter, NEAREST)
    assert_equal(checker.color_space, SRGB)
    assert_equal(checker.levels, 1)
    assert_equal(checker.texel(0, 0).r, UInt8(255))
    assert_equal(checker.texel(1, 1).b, UInt8(255))
    assert_false(checker.flip_y)
    assert_almost_equal(checker.repeat.y, Float32(1), atol=TOLERANCE)
    assert_almost_equal(checker.offset.y, Float32(0), atol=TOLERANCE)
    # Four meshes in the scene: one on each of the first two nodes and
    # two on the third, the last two drawing the default and the glass.
    assert_equal(model.first_mesh, first_mesh)
    assert_equal(model.mesh_count, 4)
    assert_equal(len(scene.meshes), first_mesh + 4)
    assert_equal(scene.meshes[first_mesh].node, model.nodes[0])
    assert_equal(scene.meshes[first_mesh].material, model.materials[0])
    assert_equal(scene.meshes[first_mesh + 1].node, model.nodes[1])
    assert_equal(scene.meshes[first_mesh + 2].node, model.nodes[2])
    assert_equal(scene.meshes[first_mesh + 2].geometry, model.geometries[1])
    assert_equal(scene.meshes[first_mesh + 3].material, model.materials[1])
    var fallback = assets.materials.get(scene.meshes[first_mesh + 2].material)
    assert_equal(fallback.kind, STANDARD)
    assert_equal(fallback.color.r, UInt8(255))
    assert_true(scene.meshes[first_mesh + 2].material != model.materials[0])


# --- the fixtures -----------------------------------------------------------


def test_a_gltf_beside_its_bin_and_its_image_reads_the_cube() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var assets = Assets()
    var model = read_gltf(HERE + "box.gltf", scene, assets)
    check_cube(model, scene, assets, 0)
    assert_equal(scene.count(), 4)
    assert_equal(scene.get(model.nodes[1]).parent, model.nodes[0])


def test_an_embedded_gltf_reads_the_same_cube() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_gltf(HERE + "embedded.gltf", scene, assets)
    check_cube(model, scene, assets, 0)


def test_a_glb_reads_the_same_cube_from_its_chunks() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_gltf(HERE + "box.glb", scene, assets)
    check_cube(model, scene, assets, 0)
    var parts = split_glb(Path(HERE + "box.glb").read_bytes())
    assert_true(parts[0].startswith('{"asset"'))
    assert_true(len(parts[1]) > 840)


def test_a_file_that_is_not_there_or_not_gltf_is_refused() raises:
    var scene = Scene()
    var assets = Assets()
    with assert_raises():
        _ = read_gltf(HERE + "missing.gltf", scene, assets)
    with assert_raises():
        _ = read_gltf(HERE + "checker.png", scene, assets)
    with assert_raises():
        _ = read_gltf("assets/cube.obj", scene, assets)


def test_the_loaded_cube_draws() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_gltf(HERE + "box.gltf", scene, assets)
    var lamp = Object3D()
    lamp.set_position(3, 4, 5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp_node, Float32(pi))
    )
    scene.update()
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(24) / Float32(18),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(3, 3.5, 6), Vector3(1, 2, 3))
    var renderer = Renderer(24, 18)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, camera)
    var drawn = 0
    for y in range(18):
        for x in range(24):
            if image.get_pixel(x, y).r > 0:
                drawn += 1
    assert_true(drawn > 20, "the cube did not draw")
    assert_true(drawn < 24 * 18, "the cube filled the image")
    _ = model


# --- the container ----------------------------------------------------------


def glb_of(json: String, bin: List[UInt8], version: Int = 2) -> List[UInt8]:
    """Return a container around a JSON text and a binary chunk."""
    var out = List[UInt8]()
    var text = List[UInt8]()
    for byte in json.as_bytes():
        text.append(byte)
    while len(text) % 4 != 0:
        text.append(32)
    var total = 12 + 8 + len(text)
    if len(bin) > 0:
        total += 8 + len(bin)
    push32(out, 0x46546C67)
    push32(out, version)
    push32(out, total)
    push32(out, len(text))
    push32(out, 0x4E4F534A)
    for byte in text:
        out.append(byte)
    if len(bin) > 0:
        push32(out, len(bin))
        push32(out, 0x004E4942)
        for byte in bin:
            out.append(byte)
    return out^


def push32(mut out: List[UInt8], value: Int):
    """Append a little-endian word."""
    out.append(UInt8(value & 0xFF))
    out.append(UInt8((value >> 8) & 0xFF))
    out.append(UInt8((value >> 16) & 0xFF))
    out.append(UInt8((value >> 24) & 0xFF))


def test_a_container_is_checked_chunk_by_chunk() raises:
    var bin = List[UInt8]()
    for byte in "abcd".as_bytes():
        bin.append(byte)
    var good = glb_of('{"asset":{"version":"2.0"}}', bin)
    var parts = split_glb(good)
    assert_equal(parts[0], '{"asset":{"version":"2.0"}} ')
    assert_equal(len(parts[1]), 4)
    var alone = split_glb(glb_of('{"a":1}', List[UInt8]()))
    assert_equal(len(alone[1]), 0)
    with assert_raises():
        _ = split_glb(List[UInt8]())
    with assert_raises():
        _ = split_glb(glb_of("{}", bin, version=1))
    var short = good.copy()
    _ = short.pop()
    with assert_raises():
        _ = split_glb(short)
    var wrong_length = good.copy()
    wrong_length[8] = 1
    with assert_raises():
        _ = split_glb(wrong_length)
    # A chunk header that runs past the file, and a chunk that does.
    var stub = List[UInt8]()
    push32(stub, 0x46546C67)
    push32(stub, 2)
    push32(stub, 16)
    push32(stub, 0)
    with assert_raises():
        _ = split_glb(stub)
    var overrun = List[UInt8]()
    push32(overrun, 0x46546C67)
    push32(overrun, 2)
    push32(overrun, 20)
    push32(overrun, 100)
    push32(overrun, 0x4E4F534A)
    with assert_raises():
        _ = split_glb(overrun)
    # A binary chunk before the JSON, two of either, an unknown type,
    # and no JSON at all.
    var bin_first = good.copy()
    bin_first[16] = 0x42
    bin_first[17] = 0x49
    bin_first[18] = 0x4E
    bin_first[19] = 0x00
    with assert_raises():
        _ = split_glb(bin_first)
    var two_json = good.copy()
    two_json[52] = 0x4A
    two_json[53] = 0x53
    two_json[54] = 0x4F
    two_json[55] = 0x4E
    with assert_raises():
        _ = split_glb(two_json)
    var unknown = good.copy()
    unknown[52] = 0x58
    with assert_raises():
        _ = split_glb(unknown)
    var twice_bin = good.copy()
    push32(twice_bin, 4)
    push32(twice_bin, 0x004E4942)
    for byte in bin:
        twice_bin.append(byte)
    twice_bin[8] = UInt8(len(twice_bin))
    with assert_raises():
        _ = split_glb(twice_bin)
    var no_json = List[UInt8]()
    push32(no_json, 0x46546C67)
    push32(no_json, 2)
    push32(no_json, 12)
    with assert_raises():
        _ = split_glb(no_json)
    # A container loads through `load_gltf` with its chunk as the first
    # buffer, and refuses a second buffer without a URI or no chunk.
    var scene = Scene()
    var assets = Assets()
    var tri = List[UInt8]()
    for byte in decode_base64(TRI):
        tri.append(byte)
    var text = doc(
        '"buffers":[{"byteLength":36}]'
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    )
    var model = load_gltf(text, tri, HERE, scene, assets)
    assert_equal(assets.geometries.get(model.geometries[0]).vertex_count(), 3)
    with assert_raises():
        _ = load_gltf(text, List[UInt8](), HERE, scene, assets)
    with assert_raises():
        _ = loaded(
            doc(
                '"buffers":[{"byteLength":1,"uri":"data:x;base64,AA=="},{"byteLength":1}]'
            ),
            scene,
            assets,
        )


# --- base64 and images ------------------------------------------------------


def test_base64_decodes_with_and_without_padding() raises:
    var bytes = decode_base64("TWFu")
    assert_equal(len(bytes), 3)
    assert_equal(bytes[0], UInt8(77))
    assert_equal(bytes[2], UInt8(110))
    assert_equal(len(decode_base64("TWE=")), 2)
    assert_equal(len(decode_base64("TWE")), 2)
    assert_equal(len(decode_base64("TQ==")), 1)
    assert_equal(decode_base64("TQ")[0], UInt8(77))
    assert_equal(len(decode_base64("")), 0)
    var all = decode_base64("+/8=")
    assert_equal(all[0], UInt8(0xFB))
    assert_equal(all[1], UInt8(0xFF))
    var digits = decode_base64("0123")
    assert_equal(digits[0], UInt8(0xD3))
    with assert_raises():
        _ = decode_base64("TW-u")
    with assert_raises():
        _ = decode_base64("TQ==TQ")
    with assert_raises():
        _ = decode_base64("T Q")


def test_an_image_is_told_by_its_first_bytes() raises:
    var png = decode_image(Path(HERE + "checker.png").read_bytes())
    assert_equal(png.width, 2)
    assert_equal(png.pixels[0], UInt8(255))
    var jpeg = decode_image(Path("assets/jpeg/gradient420.jpg").read_bytes())
    assert_true(jpeg.width > 0)
    # A TGA has no signature: one true-color pixel, blue, green and red.
    var tga = List[UInt8](length=18, fill=0)
    tga[2] = 2
    tga[12] = 1
    tga[14] = 1
    tga[16] = 24
    tga.append(10)
    tga.append(20)
    tga.append(30)
    var pixel = decode_image(tga).get_pixel(0, 0)
    assert_equal(pixel.r, UInt8(30))
    assert_equal(pixel.b, UInt8(10))
    with assert_raises(contains="not a TGA"):
        _ = decode_image(Path("assets/cube.obj").read_bytes())
    with assert_raises():
        _ = decode_image(List[UInt8]())


# --- accessors --------------------------------------------------------------


def test_every_component_type_is_read_and_normalized_when_asked() raises:
    var scene = Scene()
    var assets = Assets()
    # Unsigned bytes as colors, normalized: a red, a green, a half-alpha
    # blue, four per vertex.
    var tinted = loaded(
        doc(
            '"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
            + TRI
            + '"},{"byteLength":12,"uri":"data:application/octet-stream;base64,'
            + COLORS
            + '"}]'
            + ',"bufferViews":[{"buffer":0,"byteLength":36},{"buffer":1,"byteLength":12}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},'
            + '{"bufferView":1,"componentType":5121,"count":3,"type":"VEC4","normalized":true}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":1}}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    ref colors = assets.geometries.get(tinted.geometries[0]).attribute_view(
        String(COLOR)
    )
    assert_equal(colors.item_size, 4)
    assert_almost_equal(colors.component(0, 0), Float32(1), atol=TOLERANCE)
    assert_almost_equal(colors.component(1, 1), Float32(1), atol=TOLERANCE)
    assert_almost_equal(
        colors.component(2, 3), Float32(127.0 / 255.0), atol=TOLERANCE
    )
    # A colored primitive draws with a copy of its material that reads
    # the colors, made once per material.
    var tint = assets.materials.get(scene.meshes[0].material)
    assert_true(tint.vertex_colors)
    # Sixteen-bit, thirty-two-bit and eight-bit indices all read.
    for spelling in range(3):
        var index_text = String(IDX16)
        var kind = 5123
        var length = 6
        if spelling == 1:
            index_text = String(IDX32)
            kind = 5125
            length = 12
        elif spelling == 2:
            index_text = String(IDX8)
            kind = 5121
            length = 3
        var indexed = loaded(
            doc(
                '"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
                + TRI
                + '"},{"byteLength":'
                + String(length)
                + ',"uri":"data:application/octet-stream;base64,'
                + index_text
                + '"}]'
                + ',"bufferViews":[{"buffer":0,"byteLength":36},{"buffer":1,"byteLength":'
                + String(length)
                + "}]"
                + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},'
                + '{"bufferView":1,"componentType":'
                + String(kind)
                + ',"count":3,"type":"SCALAR"}]'
                + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}]'
                + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
            ),
            scene,
            assets,
        )
        ref shape = assets.geometries.get(indexed.geometries[0])
        assert_true(shape.is_indexed())
        assert_equal(shape.corner_index(0, 2), 2)
    # Signed bytes and shorts, normalized, held at minus one below.
    var signed = loaded(
        doc(
            buffer(SIGNED, 6)
            + ',"bufferViews":[{"buffer":0,"byteLength":2},{"buffer":0,"byteOffset":2,"byteLength":4}]'
            + ',"accessors":[{"bufferView":0,"componentType":5120,"count":2,"type":"SCALAR","normalized":true},'
            + '{"bufferView":1,"componentType":5122,"count":2,"type":"SCALAR","normalized":true},'
            + '{"bufferView":0,"componentType":5120,"count":2,"type":"SCALAR"},'
            + '{"bufferView":1,"componentType":5122,"count":2,"type":"SCALAR"}]'
        ),
        scene,
        assets,
    )
    _ = signed
    # Read through the loader's own accessor path by way of a geometry:
    # the values ride as a one-lane attribute is not a shape a primitive
    # takes, so they are checked through `accessor_floats` below.
    var strided = loaded(
        doc(
            buffer(STRIDED, 32)
            + ',"bufferViews":[{"buffer":0,"byteLength":32,"byteStride":16}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":2,"type":"VEC3"}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    ref stepped = assets.geometries.get(strided.geometries[0]).attribute_view(
        String(POSITION)
    )
    assert_equal(stepped.count(), 2)
    assert_almost_equal(stepped.component(1, 0), Float32(4), atol=TOLERANCE)
    assert_almost_equal(stepped.component(1, 2), Float32(6), atol=TOLERANCE)
    # An accessor with no buffer view is all zeros, and an accessor's own
    # byte offset steps into its view.
    var zeros = loaded(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
            + ',"accessors":[{"componentType":5126,"count":3,"type":"VEC3"},'
            + '{"bufferView":0,"byteOffset":12,"componentType":5126,"count":2,"type":"VEC3"}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1}}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    ref flat = assets.geometries.get(zeros.geometries[0])
    assert_equal(
        flat.attribute_view(String(POSITION)).component(2, 1), Float32(0)
    )
    ref stepped_in = flat.attribute_view(String(NORMAL))
    assert_equal(stepped_in.count(), 2)
    assert_almost_equal(stepped_in.component(0, 0), Float32(1), atol=TOLERANCE)


def colors_of(
    component: Int,
    count: Int,
    normalized: Bool,
    mut scene: Scene,
    mut assets: Assets,
) raises -> List[Float32]:
    """Load the six `SIGNED` bytes as a VEC3 color attribute of one
    component type and return its floats."""
    var flag = "false"
    if normalized:
        flag = "true"
    var model = loaded(
        doc(
            '"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
            + TRI
            + '"},{"byteLength":6,"uri":"data:application/octet-stream;base64,'
            + SIGNED
            + '"}]'
            + ',"bufferViews":[{"buffer":0,"byteLength":36},{"buffer":1,"byteLength":6}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},'
            + '{"bufferView":1,"componentType":'
            + String(component)
            + ',"count":'
            + String(count)
            + ',"type":"VEC3","normalized":'
            + flag
            + "}]"
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":1}}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    ref view = assets.geometries.get(model.geometries[0]).attribute_view(
        String(COLOR)
    )
    var out = List[Float32]()
    for index in range(view.count()):
        for lane in range(3):
            out.append(view.component(index, lane))
    return out^


def test_the_signed_and_wide_components_normalize_by_the_specification() raises:
    # The six bytes are -128, 127, 0, -128, -1, 127 as signed bytes, and
    # 32640, -32768, 32767 as signed shorts or 32640, 32768, 32767 as
    # unsigned ones. Normalized, a signed value divides by the largest
    # positive one and is held at minus one; an unsigned one divides by
    # the largest.
    var scene = Scene()
    var assets = Assets()
    var bytes = colors_of(5120, 2, True, scene, assets)
    assert_almost_equal(bytes[0], Float32(-1), atol=TOLERANCE)
    assert_almost_equal(bytes[1], Float32(1), atol=TOLERANCE)
    assert_almost_equal(bytes[2], Float32(0), atol=TOLERANCE)
    assert_almost_equal(bytes[4], Float32(-1.0 / 127.0), atol=TOLERANCE)
    var raw_bytes = colors_of(5120, 2, False, scene, assets)
    assert_almost_equal(raw_bytes[0], Float32(-128), atol=TOLERANCE)
    assert_almost_equal(raw_bytes[4], Float32(-1), atol=TOLERANCE)
    var shorts = colors_of(5122, 1, True, scene, assets)
    assert_almost_equal(shorts[0], Float32(32640.0 / 32767.0), atol=TOLERANCE)
    assert_almost_equal(shorts[1], Float32(-1), atol=TOLERANCE)
    assert_almost_equal(shorts[2], Float32(1), atol=TOLERANCE)
    var raw_shorts = colors_of(5122, 1, False, scene, assets)
    assert_almost_equal(raw_shorts[1], Float32(-32768), atol=TOLERANCE)
    var unsigned = colors_of(5123, 1, True, scene, assets)
    assert_almost_equal(unsigned[1], Float32(32768.0 / 65535.0), atol=TOLERANCE)
    var raw_unsigned = colors_of(5123, 1, False, scene, assets)
    assert_almost_equal(raw_unsigned[1], Float32(32768), atol=TOLERANCE)
    var wide = colors_of(5121, 2, False, scene, assets)
    assert_almost_equal(wide[0], Float32(128), atol=TOLERANCE)


def test_a_document_that_is_not_gltf_2_is_refused() raises:
    assert_true(refused("[1]").find("not an object") >= 0)
    assert_true(refused("{}").find("no asset") >= 0)
    assert_true(refused('{"asset":{}}').find("no asset version") >= 0)
    assert_true(refused('{"asset":{"version":"1.0"}}').find("version 2") >= 0)
    assert_true(
        refused('{"asset":{"version":2}}').find("no asset version") >= 0
    )
    assert_true(
        refused(doc('"extensionsRequired":["KHR_materials_variants"]')).find(
            "KHR_materials_variants"
        )
        >= 0
    )
    # An extension only used is read without it.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        doc('"extensionsUsed":["KHR_materials_unlit"]'), scene, assets
    )
    assert_equal(model.node_count(), 0)
    assert_equal(model.mesh_count, 0)
    # Not JSON at all.
    assert_true(refused("{").find("JSON") >= 0)


def test_a_malformed_buffer_view_or_accessor_is_refused() raises:
    var views = ',"bufferViews":[{"buffer":0,"byteLength":36}]'
    _ = refused(
        doc('"buffers":[{"byteLength":40,"uri":"data:x;base64,' + TRI + '"}]')
    )
    _ = refused(doc('"buffers":[{"uri":"data:x;base64,' + TRI + '"}]'))
    _ = refused(doc('"buffers":[{"byteLength":36,"uri":"http://x/y.bin"}]'))
    _ = refused(doc('"buffers":[{"byteLength":36,"uri":"data:x,' + TRI + '"}]'))
    _ = refused(doc('"buffers":[{"byteLength":36,"uri":"data:x;base64"}]'))
    _ = refused(doc('"buffers":[{"byteLength":36,"uri":"nowhere.bin"}]'))
    _ = refused(doc('"buffers":{}'))
    _ = refused(doc('"buffers":[1]'))
    var accessor = ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
    var primitive = ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    # A view past its buffer, naming no buffer, and an accessor past its
    # view, of an unknown type or component, sparse, or absent.
    _ = refused(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":0,"byteLength":40}]'
            + accessor
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":1,"byteLength":36}]'
            + accessor
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":0,"byteOffset":8,"byteLength":36}]'
            + accessor
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":0}]'
            + accessor
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":4,"type":"VEC3"}]'
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":-1,"type":"VEC3"}]'
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC5"}]'
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":0,"componentType":5124,"count":3,"type":"VEC3"}]'
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","sparse":{}}]'
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":0,"count":3,"type":"VEC3"}]'
            + primitive
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":5,"componentType":5126,"count":3,"type":"VEC3"}]'
            + primitive
        )
    )
    _ = refused(doc(buffer(TRI, 36) + views + primitive))
    # The wrong width for each attribute, and indices of the wrong kind.
    var vec2 = ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC2"}]'
    _ = refused(doc(buffer(TRI, 36) + views + vec2 + primitive))
    var vec3 = accessor
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + vec3
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":0}}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + vec2
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":0}}]}]'
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + vec2
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":0}}]}]'
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + vec3
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":0}]}]'
        )
    )
    _ = refused(
        doc(
            buffer(TRI, 36)
            + views
            + ',"accessors":[{"bufferView":0,"componentType":5123,"count":3,"type":"VEC3"}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":0}]}]'
        )
    )
    # A number that is not finite is refused where a float is read.
    _ = refused(
        doc('"materials":[{"pbrMetallicRoughness":{"roughnessFactor":1e400}}]')
    )


def test_a_malformed_mesh_or_node_is_refused() raises:
    var head = (
        buffer(TRI, 36)
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
    )
    _ = refused(
        doc(
            head
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"mode":5}]}]'
        )
    )
    _ = refused(
        doc(
            head
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"mode":-1}]}]'
        )
    )
    _ = refused(
        doc(head + ',"meshes":[{"primitives":[{"attributes":{"NORMAL":0}}]}]')
    )
    _ = refused(doc(head + ',"meshes":[{"primitives":[{}]}]'))
    _ = refused(doc(head + ',"meshes":[{"primitives":{}}]'))
    _ = refused(doc(head + ',"meshes":[{}]'))
    _ = refused(
        doc(
            head
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":3}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        )
    )
    _ = refused(doc(head + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'))
    _ = refused(doc(head + ',"nodes":[{}],"scenes":[{"nodes":[1]}]'))
    _ = refused(doc(head + ',"nodes":[{}],"scenes":[{"nodes":[0,0]}]'))
    _ = refused(
        doc(head + ',"nodes":[{"children":[0]}],"scenes":[{"nodes":[0]}]')
    )
    _ = refused(
        doc(head + ',"nodes":[{"children":{}}],"scenes":[{"nodes":[0]}]')
    )
    _ = refused(doc(head + ',"nodes":[{}],"scenes":[{"nodes":{}}]'))
    _ = refused(
        doc(
            head
            + ',"nodes":[{"matrix":[0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}],"scenes":[{"nodes":[0]}]'
        )
    )
    _ = refused(
        doc(head + ',"nodes":[{"translation":[1,2]}],"scenes":[{"nodes":[0]}]')
    )
    _ = refused(
        doc(head + ',"nodes":[{"scale":[1,2,"x"]}],"scenes":[{"nodes":[0]}]')
    )
    _ = refused(doc(head + ',"nodes":[{}],"scenes":[{"nodes":[0]}],"scene":3'))
    # A scene with no nodes, no scenes at all, and a mirrored matrix.
    var scene = Scene()
    var assets = Assets()
    var empty = loaded(
        doc(head + ',"nodes":[{"name":"lonely"}],"scenes":[{}]'), scene, assets
    )
    assert_equal(empty.nodes[0], NO_PARENT)
    assert_equal(empty.node_names[0], "lonely")
    var none = loaded(doc(head + ',"nodes":[{}]'), scene, assets)
    assert_equal(none.node_count(), 1)
    assert_equal(scene.count(), 0)
    var mirrored = loaded(
        doc(
            head
            + ',"nodes":[{"matrix":[-1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    var flipped = scene.get(mirrored.nodes[0])
    assert_almost_equal(flipped.scale.x, Float32(-1), atol=TOLERANCE)
    assert_almost_equal(flipped.quaternion.w, Float32(1), atol=TOLERANCE)
    # A second scene is chosen by `scene`, and a node with a mesh but no
    # material on a second node shares the one default material.
    var chosen = loaded(
        doc(
            head
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}],"nodes":[{"mesh":0},{"mesh":0}],"scenes":[{"nodes":[0]},{"nodes":[1]}],"scene":1'
        ),
        scene,
        assets,
    )
    assert_equal(chosen.nodes[0], NO_PARENT)
    assert_true(chosen.nodes[1] != NO_PARENT)
    var shared = loaded(
        doc(
            head
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}},{"attributes":{"POSITION":0}}]}],"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    assert_equal(shared.mesh_count, 2)
    assert_equal(
        scene.meshes[shared.first_mesh].material,
        scene.meshes[shared.first_mesh + 1].material,
    )


def test_a_malformed_material_or_texture_is_refused() raises:
    var image = '"images":[{"uri":"checker.png"}]'
    var texture = ',"textures":[{"source":0}]'
    _ = refused(doc('"textures":[{"source":0}]'))
    _ = refused(doc('"textures":[{}]' + image))
    _ = refused(
        doc(
            image
            + texture
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":1}}}]'
        )
    )
    _ = refused(
        doc(
            image
            + texture
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,"texCoord":2}}}]'
        )
    )
    _ = refused(
        doc(
            image
            + texture
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":5}}]'
        )
    )
    _ = refused(
        doc(
            image
            + texture
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{}}}]'
        )
    )
    _ = refused(
        doc(
            image
            + texture
            + ',"samplers":[{"wrapS":7}],"textures":[{"source":0,"sampler":0}]'
            + ',"materials":[{"normalTexture":{"index":0}}]'
        )
    )
    # A magnified sample reads one level, and a filter must be one of the
    # six glTF names.
    for sampler in [
        '{"magFilter":9987}',
        '{"minFilter":1}',
        '{"magFilter":1}',
        '{"wrapT":7}',
    ]:
        _ = refused(
            doc(
                image
                + texture
                + ',"samplers":['
                + sampler
                + '],"textures":[{"source":0,"sampler":0}]'
                + ',"materials":[{"normalTexture":{"index":0}}]'
            )
        )
    _ = refused(
        doc(
            '"images":[{}]'
            + texture
            + ',"materials":[{"normalTexture":{"index":0}}]'
        )
    )
    _ = refused(
        doc(
            '"images":[{"uri":"box.bin"}]'
            + texture
            + ',"materials":[{"normalTexture":{"index":0}}]'
        )
    )
    _ = refused(doc('"materials":[{"alphaMode":"SOLID"}]'))
    _ = refused(
        doc(
            '"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[1,1,1]}}]'
        )
    )
    _ = refused(doc('"materials":[{"emissiveFactor":[1,"x",1]}]'))
    _ = refused(doc('"materials":[{"doubleSided":1}]'))
    _ = refused(
        doc('"materials":[{"pbrMetallicRoughness":{"metallicFactor":"x"}}]')
    )
    # Every map kind is read in its color space, once per space.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        doc(
            image
            + ',"samplers":[{"wrapS":33648,"wrapT":33071,"magFilter":9729,"minFilter":9985}]'
            + ',"textures":[{"source":0,"sampler":0},{"source":0}]'
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicRoughnessTexture":{"index":0}},'
            + '"normalTexture":{"index":0,"scale":0.5},"emissiveTexture":{"index":1},"alphaMode":"MASK"},'
            + '{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}},"normalTexture":{"index":0}}]'
        ),
        scene,
        assets,
    )
    var first = assets.materials.get(model.materials[0])
    assert_equal(first.map, model.color_textures[0])
    assert_equal(first.roughness_map, model.data_textures[0])
    assert_equal(first.metalness_map, model.data_textures[0])
    assert_equal(first.normal_map, model.data_textures[0])
    assert_almost_equal(first.normal_scale.x, Float32(0.5), atol=TOLERANCE)
    assert_equal(first.emissive_map, model.color_textures[1])
    assert_almost_equal(first.alpha_test, Float32(0.5), atol=TOLERANCE)
    assert_true(model.color_textures[0] != model.data_textures[0])
    assert_equal(model.data_textures[1], NO_TEXTURE)
    var second = assets.materials.get(model.materials[1])
    assert_equal(second.map, first.map)
    assert_equal(second.normal_map, first.normal_map)
    assert_equal(assets.textures.count(), 3)
    ref mirrored = assets.textures.get(model.color_textures[0])
    assert_equal(mirrored.wrap_s, MIRROR)
    assert_equal(mirrored.wrap_t, CLAMP)
    assert_equal(mirrored.mag_filter, BILINEAR)
    assert_equal(mirrored.min_filter, LINEAR_MIPMAP_NEAREST)
    assert_true(mirrored.levels > 1)
    assert_equal(
        assets.textures.get(model.data_textures[0]).color_space, LINEAR
    )
    ref bare = assets.textures.get(model.color_textures[1])
    assert_equal(bare.wrap_s, REPEAT)
    assert_equal(bare.wrap_t, REPEAT)
    assert_equal(bare.min_filter, LINEAR_MIPMAP_LINEAR)
    assert_true(bare.levels > 1)


def test_a_textured_quad_shows_the_images_top_at_the_top() raises:
    # glTF's (0, 0) is the image's top left. The quad's top-left corner
    # carries (0, 0), so it must show the checker's red texel, and the
    # bottom-left corner its blue one: three.js reads every glTF texture
    # with `flipY = false`, and so does this.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        doc(
            buffer(QUAD, 92)
            + ',"bufferViews":[{"buffer":0,"byteLength":48},{"buffer":0,"byteOffset":48,"byteLength":32},{"buffer":0,"byteOffset":80,"byteLength":12}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":4,"type":"VEC3"},'
            + '{"bufferView":1,"componentType":5126,"count":4,"type":"VEC2"},'
            + '{"bufferView":2,"componentType":5123,"count":6,"type":"SCALAR"}]'
            + ',"images":[{"uri":"data:image/png;base64,'
            + CHECKER
            + '"}],"samplers":[{"magFilter":9728,"minFilter":9728}],"textures":[{"source":0,"sampler":0}]'
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0}}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":1},"indices":2,"material":0}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    assert_equal(model.mesh_count, 1)
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp_node, Float32(pi))
    )
    scene.update()
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(24) / Float32(24),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    var renderer = Renderer(24, 24)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, camera)
    var top_left = image.get_pixel(8, 8)
    var bottom_left = image.get_pixel(8, 15)
    var top_right = image.get_pixel(15, 8)
    assert_true(top_left.r > 150 and top_left.g < 60, "the top left is not red")
    assert_true(
        bottom_left.b > 150 and bottom_left.r < 60,
        "the bottom left is not blue",
    )
    assert_true(
        top_right.g > 150 and top_right.r < 60, "the top right is not green"
    )


def test_a_metallic_roughness_map_is_data_that_can_be_drawn() raises:
    # A linear texture holds numbers, so its alpha is ignored: the renderer
    # refuses a data map that reads its alpha as coverage, and a model
    # with a metallic-roughness texture could not be drawn at all.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        doc(
            buffer(QUAD, 92)
            + ',"bufferViews":[{"buffer":0,"byteLength":48},{"buffer":0,"byteOffset":48,"byteLength":32},{"buffer":0,"byteOffset":80,"byteLength":12}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":4,"type":"VEC3"},'
            + '{"bufferView":1,"componentType":5126,"count":4,"type":"VEC2"},'
            + '{"bufferView":2,"componentType":5123,"count":6,"type":"SCALAR"}]'
            + ',"images":[{"uri":"data:image/png;base64,'
            + CHECKER
            + '"}],"textures":[{"source":0}]'
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicRoughnessTexture":{"index":0}}}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":1},"indices":2,"material":0}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    assert_true(
        assets.textures.get(model.data_textures[0]).alpha == IGNORED,
        "a data texture reads its alpha as coverage",
    )
    assert_true(assets.textures.get(model.color_textures[0]).alpha == COVERAGE)
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(
        directional_light(Color(255, 255, 255), lamp_node, Float32(pi))
    )
    scene.update()
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    var renderer = Renderer(24, 24)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, camera)
    var middle = image.get_pixel(12, 12)
    assert_true(middle.r + middle.g + middle.b > 0, "the quad was not drawn")


def test_the_edges_of_every_check_are_reached() raises:
    # A file too short to hold a magic reads as JSON; a name with no slash
    # that is not there is refused.
    var scene = Scene()
    var assets = Assets()
    Path("out/tiny.gltf").write_text("{}")
    with assert_raises():
        _ = read_gltf("out/tiny.gltf", scene, assets)
    with assert_raises():
        _ = read_gltf("no_such_file.gltf", scene, assets)
    # A container that is long enough but not a container.
    var words = List[UInt8]()
    for byte in "not a glb at all, no".as_bytes():
        words.append(byte)
    with assert_raises():
        _ = split_glb(words)
    # A binary chunk of no bytes.
    var empty_bin = glb_of('{"asset":{"version":"2.0"}}', List[UInt8]())
    push32(empty_bin, 0)
    push32(empty_bin, 0x004E4942)
    empty_bin[8] = UInt8(len(empty_bin))
    var parts = split_glb(empty_bin)
    assert_equal(len(parts[1]), 0)
    # A data URI with nothing after its comma is a buffer of no bytes.
    assert_true(
        refused(
            doc('"buffers":[{"byteLength":36,"uri":"data:x;base64,"}]')
        ).find("shorter")
        >= 0
    )
    # A scene with no nodes adds nothing.
    var no_roots = loaded(doc('"scenes":[{"nodes":[]}]'), scene, assets)
    assert_equal(no_roots.mesh_count, 0)
    # An empty list of required extensions, an asset that is not an
    # object, and a base64 character past the letters.
    _ = loaded(doc('"extensionsRequired":[]'), scene, assets)
    assert_true(refused('{"asset":5}').find("no asset") >= 0)
    with assert_raises():
        _ = decode_base64("TW~u")
    # A number that fits a Float64 and not a Float32.
    _ = refused(
        doc('"materials":[{"pbrMetallicRoughness":{"roughnessFactor":1e39}}]')
    )
    _ = refused(doc('"materials":[{"emissiveFactor":[1e39,0,0]}]'))
    # A view naming a negative buffer, a texture naming a negative image,
    # a material naming a negative texture.
    _ = refused(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":-1,"byteLength":36}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}]'
        )
    )
    _ = refused(
        doc('"images":[{"uri":"checker.png"}],"textures":[{"source":-1}]')
    )
    _ = refused(
        doc(
            '"images":[{"uri":"checker.png"}],"textures":[{"source":0}]'
            + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":-1}}}]'
        )
    )
    # An image in a view of no bytes.
    _ = refused(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":0,"byteLength":0}]'
            + ',"images":[{"bufferView":0,"mimeType":"image/png"}],"textures":[{"source":0}]'
            + ',"materials":[{"normalTexture":{"index":0}}]'
        )
    )
    # An explicit OPAQUE.
    var opaque = loaded(
        doc('"materials":[{"alphaMode":"OPAQUE"}]'), scene, assets
    )
    assert_false(assets.materials.get(opaque.materials[0]).transparent)
    # Attributes that are not an object, a NORMAL and a COLOR_0 of the
    # wrong width, and the matrix types as widths.
    var two = (
        buffer(TRI, 36)
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},'
        + '{"bufferView":0,"componentType":5126,"count":2,"type":"VEC2"},'
        + '{"bufferView":0,"componentType":5126,"count":2,"type":"MAT2"},'
        + '{"bufferView":0,"componentType":5126,"count":1,"type":"MAT3"},'
        + '{"bufferView":0,"componentType":5126,"count":0,"type":"MAT4"}]'
    )
    _ = refused(doc(two + ',"meshes":[{"primitives":[{"attributes":5}]}]'))
    _ = refused(
        doc(
            two
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1}}]}]'
        )
    )
    _ = refused(
        doc(
            two
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":1}}]}]'
        )
    )
    var squares = loaded(
        doc(
            two
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":2}}]}]'
        ),
        scene,
        assets,
    )
    assert_equal(
        assets.geometries.get(squares.geometries[0])
        .attribute_view(String(COLOR))
        .item_size,
        4,
    )
    _ = refused(
        doc(
            two
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":3}}]}]'
        )
    )
    _ = refused(
        doc(
            two
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":4}}]}]'
        )
    )
    # Accessors of no elements, with and without a view, and no indices.
    var none = loaded(
        doc(
            buffer(TRI, 36)
            + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":0,"type":"VEC3"},'
            + '{"componentType":5126,"count":0,"type":"VEC3"},'
            + '{"bufferView":0,"componentType":5123,"count":0,"type":"SCALAR"}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]}]'
        ),
        scene,
        assets,
    )
    ref bare = assets.geometries.get(none.geometries[0])
    assert_equal(bare.attribute_view(String(POSITION)).count(), 0)
    assert_equal(bare.attribute_view(String(NORMAL)).count(), 0)
    # A mesh of no primitives on a node, and a scene and a node with no
    # children.
    var hollow = loaded(
        doc(
            '"meshes":[{"primitives":[]}],"nodes":[{"mesh":0,"children":[]}],"scenes":[{"nodes":[]},{"nodes":[0]}],"scene":1'
        ),
        scene,
        assets,
    )
    assert_equal(len(hollow.mesh_geometries(0)), 0)
    assert_equal(hollow.mesh_count, 0)
    with assert_raises():
        _ = hollow.mesh_geometries(-1)
    _ = refused(doc('"nodes":[{}],"scenes":[{"nodes":[-1]}]'))
    # A colored primitive with a material gets one tinted copy, shared by
    # the next colored primitive of that material.
    var tinted = loaded(
        doc(
            '"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
            + TRI
            + '"},{"byteLength":12,"uri":"data:application/octet-stream;base64,'
            + COLORS
            + '"}]'
            + ',"bufferViews":[{"buffer":0,"byteLength":36},{"buffer":1,"byteLength":12}]'
            + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},'
            + '{"bufferView":1,"componentType":5121,"count":3,"type":"VEC4","normalized":true}]'
            + ',"materials":[{}]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"COLOR_0":1},"material":0},'
            + '{"attributes":{"POSITION":0,"COLOR_0":1},"material":0},{"attributes":{"POSITION":0},"material":0}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    var first = scene.meshes[tinted.first_mesh].material
    assert_equal(scene.meshes[tinted.first_mesh + 1].material, first)
    assert_true(scene.meshes[tinted.first_mesh + 2].material != first)
    assert_equal(
        scene.meshes[tinted.first_mesh + 2].material, tinted.materials[0]
    )
    assert_true(assets.materials.get(first).vertex_colors)
    assert_false(assets.materials.get(tinted.materials[0]).vertex_colors)
    # Bytes that begin like a PNG or a JPEG and then do not.
    var almost_png = List[UInt8](length=8, fill=0)
    almost_png[0] = 0x89
    with assert_raises():
        _ = decode_image(almost_png)
    var almost_jpeg = List[UInt8](length=8, fill=0)
    almost_jpeg[0] = 0xFF
    with assert_raises():
        _ = decode_image(almost_jpeg)
    # A matrix that flattens y, and one that flattens z.
    _ = refused(
        doc(
            '"nodes":[{"matrix":[1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,1]}],"scenes":[{"nodes":[0]}]'
        )
    )
    _ = refused(
        doc(
            '"nodes":[{"matrix":[1,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1]}],"scenes":[{"nodes":[0]}]'
        )
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
