# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for what `loaders.gltf` reads beyond triangles and the material
extensions: primitives of points and lines, morph target names,
`EXT_materials_bump`, `KHR_texture_basisu` and `EXT_texture_webp`.

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
from loaders.image_batch import decode_batch_size
from materials.material import BASIC, NO_TEXTURE, PHYSICAL, STANDARD
from objects.line import LOOP, SEGMENTS, STRIP
from render.framebuffer import Color
from render import ktx2
from render.srgb import LINEAR, SRGB
from render.texture import FLOAT_TYPE, UNSIGNED_BYTE_TYPE, Texture
from render.texture_store import TextureId
from render.webp import decode as decode_webp
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
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


def test_a_webp_image_is_read_before_the_fallback() raises:
    # The WebP source wins over the texture's own, as three.js's plugin
    # is registered: required or not, with a fallback or without.
    var webp = "data:image/webp;base64," + encode_base64(
        Path("assets/webp/lossless_alpha.webp").read_bytes()
    )
    var expected = decode_webp(
        Path("assets/webp/lossless_alpha.webp").read_bytes()
    )
    var cases: List[String] = [
        textured(
            '[{"source":0,"extensions":{"EXT_texture_webp":{"source":1}}}]',
            "[" + png_image() + ',{"uri":"' + webp + '"}]',
            ',"extensionsRequired":["EXT_texture_webp"]',
        ),
        textured(
            '[{"extensions":{"EXT_texture_webp":{"source":0}}}]',
            '[{"uri":"' + webp + '"}]',
        ),
    ]
    for text in cases:
        var scene = Scene()
        var assets = Assets()
        var model = loaded(text, scene, assets)
        var worn = assets.materials.get(model.materials[0])
        ref read = assets.textures.get(worn.map)
        assert_equal(read.width, expected.width)
        assert_equal(read.height, expected.height)
        for at in range(len(expected.pixels)):
            assert_equal(read.pixels[at], expected.pixels[at])
    refuses(textured("[{}]", "[" + png_image() + "]"), "source is required")
    assert_true(is_supported_extension("KHR_texture_basisu"))
    assert_true(is_supported_extension("EXT_materials_bump"))
    assert_true(is_supported_extension("EXT_texture_webp"))


def test_ktx2_is_told_by_its_identifier() raises:
    assert_false(is_ktx2(List[UInt8]()))
    assert_false(is_ktx2(List[UInt8](length=12, fill=0xAB)))
    assert_true(is_ktx2(Path("assets/ktx2/etc1s_rgb.ktx2").read_bytes()))


# --- decoding with workers ----------------------------------------------------


def maps_doc(images: String, materials: String) -> String:
    """Return a triangle drawn with material zero of `materials`, with a
    PNG texture (0) and a KTX 2.0 one (1) over `images`."""
    return doc(
        ',"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
        + TRI
        + '"}]'
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
        + ',"images":'
        + images
        + ',"textures":[{"source":0},{"source":0,"extensions":'
        + '{"KHR_texture_basisu":{"source":1}}}]'
        + ',"materials":'
        + materials
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        + ',"extensionsRequired":["KHR_texture_basisu"]'
    )


# A KTX 2.0 base color, the PNG as the normal, occlusion and metal and
# roughness maps (one texture as numbers) and as the emissive map (the same
# texture in sRGB), and a second material with no metal and roughness.
comptime CORE_MAPS = (
    '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":1},'
    '"metallicRoughnessTexture":{"index":0}},"normalTexture":{"index":0},'
    '"occlusionTexture":{"index":0},"emissiveTexture":{"index":0},'
    '"emissiveFactor":[1,1,1]},{"normalTexture":{"index":0}}]'
)


def test_decode_batches_never_exceed_the_worker_limit() raises:
    assert_equal(decode_batch_size(0, 2), 0)
    assert_equal(decode_batch_size(3, 0), 1)
    assert_equal(decode_batch_size(3, 1), 1)
    for workers in range(2, 9):
        for total in range(1, 18):
            var remaining = total
            var batches = 0
            while remaining > 0:
                var batch = decode_batch_size(remaining, workers)
                assert_true(batch > 0)
                assert_true(batch <= workers)
                assert_true(batch <= remaining)
                remaining -= batch
                batches += 1
            assert_equal(batches, (total + workers - 1) // workers)


def test_workers_keep_texture_order_across_multiple_batches() raises:
    # Five distinct one-pixel images use alternating color spaces.
    # Two workers cross two batch boundaries and leave one final image.
    # Their RGBA colors are (10,30,70,255), (20,80,150,255),
    # (230,20,40,255), (40,200,60,255) and (50,100,220,255).
    var text = doc(
        ',"images":['
        '{"uri":"data:image/png;base64,'
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPgknP7DwACEgFuYigxcAAAAABJRU5ErkJggg=="
        '"},'
        '{"uri":"data:image/png;base64,'
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQCZj2HwADcAH6gpIUEAAAAABJRU5ErkJggg=="
        '"},'
        '{"uri":"data:image/png;base64,'
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN4JqLxHwAFKAIiKKFFLAAAAABJRU5ErkJggg=="
        '"},'
        '{"uri":"data:image/png;base64,'
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPQOGHzHwAEdAIsrzhaoQAAAABJRU5ErkJggg=="
        '"},'
        '{"uri":"data:image/png;base64,'
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwSrnzHwAEsAJyiQKTRQAAAABJRU5ErkJggg=="
        '"}'
        '],"textures":[{"source":0},{"source":1},{"source":2},'
        '{"source":3},{"source":4}]'
        ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},'
        '{"normalTexture":{"index":1}},'
        '{"pbrMetallicRoughness":{"baseColorTexture":{"index":2}}},'
        '{"normalTexture":{"index":3}},'
        '{"pbrMetallicRoughness":{"baseColorTexture":{"index":4}}}]'
    )
    var one_scene = Scene()
    var one_assets = Assets()
    var one = load_gltf(text, List[UInt8](), "", one_scene, one_assets)
    var many_scene = Scene()
    var many_assets = Assets()
    var many = load_gltf(text, List[UInt8](), "", many_scene, many_assets, 2)
    assert_equal(many_assets.textures.count(), 5)
    for index in range(5):
        var a = one.color_textures[index]
        var b = many.color_textures[index]
        if index % 2 == 1:
            a = one.data_textures[index]
            b = many.data_textures[index]
        assert_equal(a, b)
        ref x = one_assets.textures.get(a)
        ref y = many_assets.textures.get(b)
        assert_equal(x.pixels, y.pixels)
        assert_equal(x.levels, y.levels)
        assert_true(x.color_space == y.color_space)


def test_workers_decode_the_core_maps_as_one_worker_does() raises:
    var text = maps_doc(
        "["
        + png_image()
        + ',{"uri":"'
        + ktx2_uri("uastc_gradient.ktx2")
        + '"}]',
        CORE_MAPS,
    )
    var one_scene = Scene()
    var one_assets = Assets()
    var one = load_gltf(text, List[UInt8](), "", one_scene, one_assets)
    var many_scene = Scene()
    var many_assets = Assets()
    var many = load_gltf(text, List[UInt8](), "", many_scene, many_assets, 4)
    # Each texture is decoded once in each space it is read in.
    assert_equal(many_assets.textures.count(), one_assets.textures.count())
    var a = one_assets.materials.get(one.materials[0])
    var b = many_assets.materials.get(many.materials[0])
    var pairs: List[Tuple[TextureId, TextureId]] = [
        (a.map, b.map),
        (a.normal_map, b.normal_map),
        (a.emissive_map, b.emissive_map),
        (a.ao_map, b.ao_map),
    ]
    for pair in pairs:
        ref x = one_assets.textures.get(pair[0])
        ref y = many_assets.textures.get(pair[1])
        assert_equal(x.width, y.width)
        assert_equal(x.levels, y.levels)
        assert_true(x.color_space == y.color_space)
        assert_equal(x.flip_y, y.flip_y)
        for at in range(len(x.pixels)):
            assert_equal(x.pixels[at], y.pixels[at])
    assert_true(many_assets.textures.get(b.emissive_map).color_space == SRGB)


def test_workers_preserve_the_first_source_error() raises:
    # The first images are malformed. A later image has an invalid URI.
    # Concurrent reads must not replace the earliest job's decode error
    # with the later URI error, even if that read finishes first.
    var text = doc(
        ',"images":[{"uri":"data:image/png;base64,AAAA"},'
        '{"uri":"data:image/png;base64,AAAA"},'
        '{"uri":"data:invalid-third-batch-uri"}]'
        ',"textures":[{"source":0},{"source":1},{"source":2}]'
        ',"materials":[{"normalTexture":{"index":0}},'
        '{"normalTexture":{"index":1}},{"normalTexture":{"index":2}}]'
    )
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="neither PNG nor JPEG"):
        _ = load_gltf(text, List[UInt8](), "", scene, assets, 2)


def test_workers_match_file_data_uri_and_buffer_view_images() raises:
    var bytes = Path("assets/gltf/checker.png").read_bytes()
    var text = doc(
        ',"buffers":[{"byteLength":'
        + String(len(bytes))
        + "}]"
        + ',"bufferViews":[{"buffer":0,"byteLength":'
        + String(len(bytes))
        + "}]"
        + ',"images":[{"uri":"data:image/png;base64,'
        + encode_base64(bytes)
        + '"},'
        '{"uri":"assets/gltf/checker.png"},{"bufferView":0,"mimeType":"image/png"}]'
        + ',"samplers":[{"wrapS":33071,"wrapT":33648,"magFilter":9728,"minFilter":9984},'
        '{"wrapS":10497,"wrapT":33071,"magFilter":9729,"minFilter":9729}]'
        + ',"textures":[{"source":0,"sampler":0},{"source":1,"sampler":1},{"source":2,"sampler":0}]'
        + ',"materials":[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}},"normalTexture":{"index":0}},'
        '{"pbrMetallicRoughness":{"baseColorTexture":{"index":1}},"normalTexture":{"index":1}},'
        '{"pbrMetallicRoughness":{"baseColorTexture":{"index":2}},"normalTexture":{"index":2}},'
        '{"normalTexture":{"index":0}}]'
    )
    var serial_scene = Scene()
    var serial_assets = Assets()
    var serial = load_gltf(text, bytes, "", serial_scene, serial_assets, 1)
    for workers in [2, 8]:
        var scene = Scene()
        var assets = Assets()
        var model = load_gltf(text, bytes, "", scene, assets, workers)
        assert_equal(assets.textures.count(), 6)
        assert_equal(model.color_textures, serial.color_textures)
        assert_equal(model.data_textures, serial.data_textures)
        for index in range(6):
            ref a = serial_assets.textures.get(TextureId(index))
            ref b = assets.textures.get(TextureId(index))
            assert_equal(a.pixels, b.pixels)
            assert_equal(a.offsets, b.offsets)
            assert_equal(a.levels, b.levels)
            assert_true(a.color_space == b.color_space)
            assert_true(a.alpha == b.alpha)
            assert_true(a.min_filter == b.min_filter)
            assert_true(a.mag_filter == b.mag_filter)
            assert_true(a.wrap_s == b.wrap_s)
            assert_true(a.wrap_t == b.wrap_t)
            assert_equal(a.flip_y, b.flip_y)


def test_workers_select_source_errors_across_acquisition_and_decode() raises:
    for workers in [2, 8]:
        for first in [True, False]:
            var images = (
                '[{"uri":"data:invalid-uri"},{"uri":"data:image/png;base64,AAAA"}]' if first else '[{"uri":"data:image/png;base64,AAAA"},{"uri":"data:invalid-uri"}]'
            )
            var text = doc(
                ',"images":'
                + images
                + ',"textures":[{"source":0},{"source":1}]'
                + ',"materials":[{"normalTexture":{"index":0}},'
                '{"normalTexture":{"index":1}}]'
            )
            var scene = Scene()
            var assets = Assets()
            with assert_raises(
                contains="without a comma" if first else "neither PNG nor JPEG"
            ):
                _ = load_gltf(text, List[UInt8](), "", scene, assets, workers)
            assert_equal(assets.textures.count(), 0)


def test_failed_predecode_keeps_existing_textures_and_exact_read_error() raises:
    var text = doc(
        ',"images":['
        + png_image()
        + ","
        + png_image()
        + ',{"uri":"data:invalid-uri"}]'
        + ',"textures":[{"source":0},{"source":1},{"source":2}]'
        + ',"materials":[{"normalTexture":{"index":0}},'
        '{"normalTexture":{"index":1}},{"normalTexture":{"index":2}}]'
    )
    for workers in [2, 8]:
        var scene = Scene()
        var assets = Assets()
        _ = assets.textures.add(Texture())
        var raised = False
        var message = String("")
        try:
            _ = load_gltf(text, List[UInt8](), "", scene, assets, workers)
        except e:
            raised = True
            message = String(e)
        assert_true(raised)
        assert_equal(message, "glTF: a data URI without a comma")
        assert_equal(assets.textures.count(), 1)


def test_workers_refuse_what_one_worker_refuses() raises:
    # An image that is not one, in a core slot.
    var broken = maps_doc(
        '[{"uri":"data:image/png;base64,AAAA"},{"uri":"'
        + ktx2_uri("uastc_gradient.ktx2")
        + '"}]',
        CORE_MAPS,
    )
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="glTF: "):
        _ = load_gltf(broken, List[UInt8](), "", scene, assets, 4)
    # A texture that is not there, which the materials then refuse.
    var missing = maps_doc(
        "["
        + png_image()
        + ',{"uri":"'
        + ktx2_uri("uastc_gradient.ktx2")
        + '"}]',
        '[{"normalTexture":{"index":7}}]',
    )
    with assert_raises(contains="not there"):
        _ = load_gltf(missing, List[UInt8](), "", scene, assets, 4)


def test_workers_read_a_file_with_no_materials() raises:
    var text = doc(
        ',"buffers":[{"byteLength":36,"uri":"data:application/octet-stream;base64,'
        + TRI
        + '"}]'
        + ',"bufferViews":[{"buffer":0,"byteLength":36}]'
        + ',"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}]'
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    )
    var scene = Scene()
    var assets = Assets()
    var model = load_gltf(text, List[UInt8](), "", scene, assets, 4)
    assert_equal(model.mesh_count, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
