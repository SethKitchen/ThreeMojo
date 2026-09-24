# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for what `loaders.gltf` reads beyond triangles and the material
extensions: primitives of points and lines, morph target names,
`EXT_materials_bump`, `KHR_texture_basisu`, and the refusal of a WebP
image, which is not decoded.

Each document is written inline. The KTX 2.0 images are the Basis
Universal fixtures under `assets/ktx2/`, carried in data URIs.
"""

from core.assets import Assets
from core.buffer_geometry import COLOR, POSITION
from core.scene import Scene
from exporters.gltf import encode_base64
from loaders.gltf import (
    GltfModel,
    is_ktx2,
    is_supported_extension,
    load_gltf,
)
from materials.material import BASIC, NO_TEXTURE, PHYSICAL, STANDARD
from objects.line import LOOP, SEGMENTS, STRIP
from render.framebuffer import Color
from render import ktx2
from render.srgb import LINEAR, SRGB
from render.texture import FLOAT_TYPE, UNSIGNED_BYTE_TYPE
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

# A triangle's nine floats, then its three vertex colors, as base64.
comptime TRI = "AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"
# Three sixteen-bit indices: 2, 0, 1.
comptime ORDER = "AgAAAAEA"
# Three RGB float colors: red, green, blue.
comptime RGB = "AACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/"
comptime CHECKER = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC"


def doc(body: String) -> String:
    """Return a glTF 2 document around `body`, which starts with a comma."""
    return '{"asset":{"version":"2.0"}' + body + "}"


def loaded(
    text: String, mut scene: Scene, mut assets: Assets
) raises -> GltfModel:
    """Load an inline document with no binary chunk."""
    return load_gltf(text, List[UInt8](), "", scene, assets)


def refused(text: String) raises -> String:
    """Return the message an inline document is refused with."""
    var scene = Scene()
    var assets = Assets()
    try:
        _ = loaded(text, scene, assets)
    except reason:
        return String(reason)
    raise Error("the document was accepted")


def refuses(text: String, expected: String) raises:
    """Assert that a document is refused with a message holding
    `expected`."""
    var reason = refused(text)
    assert_true(expected in reason, reason)


def geometry_doc(primitives: String, nodes: String = "") -> String:
    """Return a document of one triangle's positions (accessor 0), its
    colors (accessor 1) and three indices (accessor 2), one mesh of
    `primitives`, and `nodes`, or one node of the mesh."""
    var tail = nodes
    if tail == "":
        tail = ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    return doc(
        ',"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
        + TRI
        + '"},{"byteLength":36,"uri":"data:application/octet-stream;base64,'
        + RGB
        + '"},{"byteLength":6,"uri":"data:application/octet-stream;base64,'
        + ORDER
        + '"}]'
        + ',"bufferViews":[{"buffer":0,"byteLength":36},'
        + '{"buffer":1,"byteLength":36},{"buffer":2,"byteLength":6}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},'
        + '{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},'
        + '{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"}]'
        + ',"materials":[{"pbrMetallicRoughness":{"baseColorFactor":[1,0,0,0.5]},"alphaMode":"BLEND"}]'
        + ',"meshes":[{"primitives":['
        + primitives
        + "]}]"
        + tail
    )


def ktx2_uri(name: String) raises -> String:
    """Return a KTX 2.0 fixture as a data URI."""
    return "data:image/ktx2;base64," + encode_base64(
        Path("assets/ktx2/" + name).read_bytes()
    )


def textured(textures: String, images: String, extra: String = "") -> String:
    """Return a triangle drawn with one material whose base color is
    texture zero, with `textures`, `images` and `extra` written out."""
    return doc(
        ',"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
        + TRI
        + '"}]'
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
        + ',"images":'
        + images
        + ',"textures":'
        + textures
        + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}]'
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        + extra
    )


def png_image() -> String:
    """Return the checker as an image entry."""
    return '{"uri":"data:image/png;base64,' + CHECKER + '"}'


# --- points and lines -------------------------------------------------------


def test_points_and_lines_are_drawn_as_three_js_draws_them() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        geometry_doc(
            '{"attributes":{"POSITION":0},"mode":0,"material":0},'
            + '{"attributes":{"POSITION":0,"COLOR_0":1},"mode":1},'
            + '{"attributes":{"POSITION":0},"mode":2,"indices":2},'
            + '{"attributes":{"POSITION":0},"mode":3,"material":0},'
            + '{"attributes":{"POSITION":0},"mode":4}'
        ),
        scene,
        assets,
    )
    assert_equal(model.points_count, 1)
    assert_equal(model.line_count, 3)
    assert_equal(model.mesh_count, 1)
    assert_equal(model.first_line, 0)
    assert_equal(model.first_points, 0)
    # A points material at one pixel that does not shrink, with the file's
    # color and transparency.
    var dots = assets.materials.get(scene.points[0].material)
    assert_equal(dots.kind, BASIC)
    assert_false(dots.size_attenuation)
    assert_equal(dots.color.r, 255)
    assert_equal(dots.color.g, 0)
    assert_equal(dots.opacity, 0.5)
    assert_true(dots.transparent)
    assert_false(dots.vertex_colors)
    # Each kind of line, and a line material that is basic.
    assert_equal(scene.lines[0].mode, SEGMENTS)
    assert_equal(scene.lines[1].mode, LOOP)
    assert_equal(scene.lines[2].mode, STRIP)
    var tinted = assets.materials.get(scene.lines[0].material)
    assert_equal(tinted.kind, BASIC)
    assert_true(tinted.vertex_colors)
    assert_equal(tinted.color.g, 255)
    var red = assets.materials.get(scene.lines[2].material)
    assert_equal(red.color.g, 0)
    assert_true(red.transparent)
    # An indexed loop is read out in index order: an index here is a
    # triangle index.
    ref loop = assets.geometries.get(scene.lines[1].geometry)
    assert_false(loop.is_indexed())
    ref corners = loop.attribute_view(String(POSITION)).data
    assert_equal(corners[0], 0)
    assert_equal(corners[1], 1)
    assert_equal(corners[3], 0)
    assert_equal(corners[6], 1)
    # The triangle is still a mesh.
    assert_equal(scene.meshes[0].node, scene.lines[0].node)


def test_an_indexed_line_keeps_its_morph_targets_in_order() raises:
    var scene = Scene()
    var assets = Assets()
    _ = loaded(
        geometry_doc(
            '{"attributes":{"POSITION":0},"mode":1,"indices":2,'
            + '"targets":[{"POSITION":0,"NORMAL":1}]}'
        ),
        scene,
        assets,
    )
    ref line = assets.geometries.get(scene.lines[0].geometry)
    assert_equal(line.morph_count(), 1)
    assert_true(line.has_morph_normals())
    assert_true(line.morph_relative)
    # The first vertex is the third one the file holds.
    assert_equal(line.morph_positions[0].data[1], 1)
    assert_equal(line.morph_normals[0].data[2], 1)


def test_a_skinned_or_instanced_line_is_refused() raises:
    refuses(
        geometry_doc(
            '{"attributes":{"POSITION":0},"mode":1}',
            ',"nodes":[{"mesh":0,"extensions":{"EXT_mesh_gpu_instancing":'
            + '{"attributes":{"TRANSLATION":0}}}}],"scenes":[{"nodes":[0]}]',
        ),
        "instanced node draws triangles only",
    )
    refuses(
        geometry_doc(
            '{"attributes":{"POSITION":0},"mode":3}',
            ',"nodes":[{"mesh":0,"skin":0},{}],"skins":[{"joints":[1]}]'
            + ',"scenes":[{"nodes":[0,1]}]',
        ),
        "skinned node draws triangles only",
    )
    refuses(
        geometry_doc('{"attributes":{"POSITION":0},"mode":6}'),
        "strips and fans",
    )


# --- morph target names -----------------------------------------------------


def names_doc(extras: String) -> String:
    """Return a triangle with two morph targets and a mesh's `extras`."""
    return doc(
        ',"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
        + TRI
        + '"}]'
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},'
        + '"targets":[{"POSITION":0},{"POSITION":0}]}]'
        + extras
        + "}]"
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    )


def test_target_names_name_the_morph_targets() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        names_doc(',"extras":{"targetNames":["smile","frown"]}'), scene, assets
    )
    ref named = assets.geometries.get(model.geometries[0])
    assert_equal(len(named.morph_names), 2)
    assert_equal(named.morph_names[1], "frown")
    # `extras` of any other shape names nothing, as three.js reads it.
    for extras in [
        String(""),
        String(',"extras":[1]'),
        String(',"extras":{"targetNames":"smile"}'),
        String(',"extras":{"other":1}'),
        String(',"extras":{"targetNames":[]}'),
    ]:
        var again = Scene()
        var more = Assets()
        var other = loaded(names_doc(extras), again, more)
        assert_equal(
            len(more.geometries.get(other.geometries[0]).morph_names), 0
        )
    refuses(
        names_doc(',"extras":{"targetNames":["one"]}'),
        "one name per morph target",
    )


# --- EXT_materials_bump -----------------------------------------------------


def bump_doc(material: String) -> String:
    """Return a textured triangle whose material is `material`."""
    return doc(
        ',"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
        + TRI
        + '"}]'
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
        + ',"images":['
        + png_image()
        + '],"textures":[{"source":0}]'
        + ',"materials":['
        + material
        + "]"
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    )


def test_a_bump_map_makes_a_physical_material() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        bump_doc(
            '{"extensions":{"EXT_materials_bump":{"bumpFactor":0.5,'
            + '"bumpTexture":{"index":0}}}}'
        ),
        scene,
        assets,
    )
    var bumpy = assets.materials.get(model.materials[0])
    assert_equal(bumpy.kind, PHYSICAL)
    assert_true(bumpy.bump_map != NO_TEXTURE)
    assert_equal(bumpy.bump_scale, 0.5)
    assert_equal(assets.textures.get(bumpy.bump_map).color_space, LINEAR)
    # A bump factor with no map draws nothing, and the scale stays one.
    var bare = Assets()
    var plain = loaded(
        bump_doc('{"extensions":{"EXT_materials_bump":{"bumpFactor":3}}}'),
        scene,
        bare,
    )
    var flat = bare.materials.get(plain.materials[0])
    assert_equal(flat.kind, PHYSICAL)
    assert_equal(flat.bump_map, NO_TEXTURE)
    assert_equal(flat.bump_scale, 1)
    # three.js draws the normal map of a material that has both.
    var both = Assets()
    var normal = loaded(
        bump_doc(
            '{"normalTexture":{"index":0},"extensions":{"EXT_materials_bump":'
            + '{"bumpFactor":2,"bumpTexture":{"index":0}}}}'
        ),
        scene,
        both,
    )
    var drawn = both.materials.get(normal.materials[0])
    assert_true(drawn.normal_map != NO_TEXTURE)
    assert_equal(drawn.bump_map, NO_TEXTURE)
    assert_equal(drawn.bump_scale, 1)
    # A material without the extension is standard, as before.
    var none = Assets()
    var still = loaded(bump_doc("{}"), scene, none)
    assert_equal(none.materials.get(still.materials[0]).kind, STANDARD)


# --- KHR_texture_basisu and EXT_texture_webp --------------------------------


def test_a_basisu_texture_reads_its_ktx2_image() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"source":0,"extensions":{"KHR_texture_basisu":{"source":1}}}]',
            "["
            + png_image()
            + ',{"uri":"'
            + ktx2_uri("uastc_gradient.ktx2")
            + '"}]',
            ',"extensionsRequired":["KHR_texture_basisu"]',
        ),
        scene,
        assets,
    )
    var worn = assets.materials.get(model.materials[0])
    ref read = assets.textures.get(worn.map)
    var expected = ktx2.read(
        Path("assets/ktx2/uastc_gradient.ktx2").read_bytes()
    ).texture()
    assert_equal(read.width, expected.width)
    assert_equal(read.height, expected.height)
    assert_equal(read.texel_type, UNSIGNED_BYTE_TYPE)
    for at in range(expected.width * expected.height * 4):
        assert_equal(read.pixels[at], expected.pixels[at])
    # A base color is sRGB, and glTF's rows run down, as the file's do.
    assert_equal(read.color_space, SRGB)
    assert_false(read.flip_y)
    # glTF's default sampler builds the chain.
    assert_true(read.levels > 1)


def test_a_basisu_texture_needs_no_fallback() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"extensions":{"KHR_texture_basisu":{"source":0}},"sampler":0}]',
            '[{"uri":"' + ktx2_uri("uastc_hdr_zstd_mips.ktx2") + '"}]',
            ',"samplers":[{"minFilter":9729}]',
        ),
        scene,
        assets,
    )
    ref hdr = assets.textures.get(assets.materials.get(model.materials[0]).map)
    assert_equal(hdr.texel_type, FLOAT_TYPE)
    assert_equal(hdr.levels, 1)


def test_a_webp_image_is_not_decoded() raises:
    # Required: refused with a message that says what to do.
    refuses(
        textured(
            '[{"source":0,"extensions":{"EXT_texture_webp":{"source":0}}}]',
            "[" + png_image() + "]",
            ',"extensionsRequired":["EXT_texture_webp"]',
        ),
        "WebP images are not decoded",
    )
    # Optional: the fallback source is read.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"source":0,"extensions":{"EXT_texture_webp":{"source":1}}}]',
            "[" + png_image() + ',{"uri":"image.webp"}]',
        ),
        scene,
        assets,
    )
    var worn = assets.materials.get(model.materials[0])
    assert_equal(assets.textures.get(worn.map).width, 2)
    # A WebP image and no fallback.
    refuses(
        textured(
            '[{"extensions":{"EXT_texture_webp":{"source":0}}}]',
            '[{"uri":"image.webp"}]',
        ),
        "names only a WebP image",
    )
    refuses(textured("[{}]", "[" + png_image() + "]"), "source is required")
    assert_true(is_supported_extension("KHR_texture_basisu"))
    assert_true(is_supported_extension("EXT_materials_bump"))
    assert_false(is_supported_extension("EXT_texture_webp"))


def test_ktx2_is_told_by_its_identifier() raises:
    assert_false(is_ktx2(List[UInt8]()))
    assert_false(is_ktx2(List[UInt8](length=12, fill=0xAB)))
    assert_true(is_ktx2(Path("assets/ktx2/etc1s_rgb.ktx2").read_bytes()))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
