# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the glTF extensions `loaders.gltf` reads: the material
extensions, `KHR_texture_transform`, `KHR_lights_punctual`,
`KHR_mesh_quantization` and `EXT_mesh_gpu_instancing`, and the refusal of
a required extension that is not read.

Every document is built here by hand. A `Bin` packs the numbers into one
buffer, gives each run of numbers its own buffer view and accessor, and
writes the buffer as a base64 data URI.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_geometry import POSITION, UV
from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from lights.light import DIRECTIONAL, POINT, SPOT, directional_light
from loaders.gltf import GltfModel, is_supported_extension, load_gltf
from materials.material import (
    BASIC,
    NO_TEXTURE,
    PHYSICAL,
    STANDARD,
    MaterialId,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.math import cos, pi, sin
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)
from render.srgb import LINEAR, SRGB
from render.texture import COVERAGE, IGNORED
from units.si import Angle, DEGREE, Length, METER, NANOMETER, RADIAN

comptime TOLERANCE = Float64(1e-5)
comptime ALPHABET = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
)
comptime FLOAT = 5126
comptime UBYTE = 5121
comptime SHORT = 5122
comptime USHORT = 5123
# A two-by-two checker: red at the top left, green at the top right and
# blue at the bottom left.
comptime CHECKER = "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC"


# --- building documents -----------------------------------------------------


def encode_base64(bytes: List[UInt8]) -> String:
    """Return the standard, padded base64 text of some bytes."""
    var table = String(ALPHABET).as_bytes()
    var out = List[UInt8]()
    var at = 0
    while at < len(bytes):
        var left = len(bytes) - at
        var n = Int(bytes[at]) << 16
        if left > 1:
            n |= Int(bytes[at + 1]) << 8
        if left > 2:
            n |= Int(bytes[at + 2])
        out.append(table[(n >> 18) & 63])
        out.append(table[(n >> 12) & 63])
        out.append(table[(n >> 6) & 63] if left > 1 else UInt8(61))
        out.append(table[n & 63] if left > 2 else UInt8(61))
        at += 3
    return String(unsafe_from_utf8=out)


def width_of(kind: String) -> Int:
    """Return how many numbers an accessor type holds."""
    if kind == "VEC2":
        return 2
    if kind == "VEC3":
        return 3
    if kind == "VEC4":
        return 4
    return 1


def size_of(component: Int) -> Int:
    """Return how many bytes a component takes."""
    if component == UBYTE:
        return 1
    if component == SHORT or component == USHORT:
        return 2
    return 4


def doc(body: String) -> String:
    """Return a glTF 2 document around `body`, which starts with a comma."""
    return '{"asset":{"version":"2.0"}' + body + "}"


struct Bin(Movable):
    """One buffer, built a run of numbers at a time, each run its own view
    and accessor."""

    var bytes: List[UInt8]
    var views: String
    var accessors: String
    var view_count: Int
    var accessor_count: Int

    def __init__(out self):
        """Start empty."""
        self.bytes = List[UInt8]()
        self.views = String()
        self.accessors = String()
        self.view_count = 0
        self.accessor_count = 0

    def view(mut self, data: List[UInt8]) -> Int:
        """Add bytes as a buffer view of their own and return its index."""
        var offset = len(self.bytes)
        for index in range(len(data)):
            self.bytes.append(data[index])
        while len(self.bytes) % 4 != 0:
            self.bytes.append(0)
        if self.view_count > 0:
            self.views += ","
        self.views += (
            '{"buffer":0,"byteOffset":'
            + String(offset)
            + ',"byteLength":'
            + String(len(data))
            + "}"
        )
        self.view_count += 1
        return self.view_count - 1

    def accessor(mut self, json: String) -> Int:
        """Add an accessor written out and return its index."""
        if self.accessor_count > 0:
            self.accessors += ","
        self.accessors += json
        self.accessor_count += 1
        return self.accessor_count - 1

    def floats(mut self, values: List[Float32], kind: String) -> Int:
        """Add floats as an accessor of `kind` and return its index."""
        var view = self.view(float_bytes(values))
        return self.accessor(
            '{"bufferView":'
            + String(view)
            + ',"componentType":5126,"count":'
            + String(len(values) // width_of(kind))
            + ',"type":"'
            + kind
            + '"}'
        )

    def ints(
        mut self,
        values: List[Int],
        component: Int,
        kind: String,
        extra: String = "",
    ) -> Int:
        """Add whole numbers as an accessor of `kind` and return its
        index."""
        var view = self.view(int_bytes(values, size_of(component)))
        return self.accessor(
            '{"bufferView":'
            + String(view)
            + ',"componentType":'
            + String(component)
            + ',"count":'
            + String(len(values) // width_of(kind))
            + ',"type":"'
            + kind
            + '"'
            + extra
            + "}"
        )

    def document(self, body: String) -> String:
        """Return the document: this buffer, its views and accessors, and
        `body` after them."""
        return doc(
            ',"buffers":[{"byteLength":'
            + String(len(self.bytes))
            + ',"uri":"data:application/octet-stream;base64,'
            + encode_base64(self.bytes)
            + '"}],"bufferViews":['
            + self.views
            + '],"accessors":['
            + self.accessors
            + "]"
            + body
        )


def float_bytes(values: List[Float32]) -> List[UInt8]:
    """Return floats as little-endian bytes."""
    var out = List[UInt8]()
    for index in range(len(values)):
        var bits = Int(bitcast[DType.uint32](values[index]))
        for shift in range(4):
            out.append(UInt8((bits >> (shift * 8)) & 0xFF))
    return out^


def int_bytes(values: List[Int], size: Int) -> List[UInt8]:
    """Return whole numbers as little-endian bytes of `size` each."""
    var out = List[UInt8]()
    for index in range(len(values)):
        for shift in range(size):
            out.append(UInt8((values[index] >> (shift * 8)) & 0xFF))
    return out^


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


def camera_at(z: Float32) raises -> PerspectiveCamera:
    """Return a square camera on the z axis looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, 0))
    return camera^


def lit_pixels(mut scene: Scene, assets: Assets) raises -> Int:
    """Render the scene from +z and count the pixels that are not black."""
    scene.update()
    var renderer = Renderer(24, 24)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, camera_at(3))
    var drawn = 0
    for y in range(24):
        for x in range(24):
            var pixel = image.get_pixel(x, y)
            if pixel.r > 0 or pixel.g > 0 or pixel.b > 0:
                drawn += 1
    return drawn


def big_triangle() -> List[Float32]:
    """Return a triangle facing +z that covers the middle of the view."""
    return [-1, -1, 0, 1, -1, 0, 0, 1, 0]


def textured(materials: String, extra: String = "") -> String:
    """Return a textured quad's document with `materials` as its materials
    and `extra` after them. The checker is texture zero."""
    var bin = Bin()
    _ = bin.floats(
        [-1, 1, 0, 1, 1, 0, 1, -1, 0, -1, -1, 0],
        "VEC3",
    )
    _ = bin.floats([0, 0, 1, 0, 1, 1, 0, 1], "VEC2")
    _ = bin.ints([0, 2, 1, 0, 3, 2], USHORT, "SCALAR")
    return bin.document(
        ',"images":[{"uri":"data:image/png;base64,'
        + CHECKER
        + '"}],"samplers":[{"magFilter":9728,"minFilter":9728}]'
        + ',"textures":[{"source":0,"sampler":0},{"source":0,"sampler":0}]'
        + ',"materials":'
        + materials
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":1},"indices":2,"material":0}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        + extra
    )


def material_doc(material: String) -> String:
    """Return a triangle's document with one material, written out."""
    var bin = Bin()
    _ = bin.floats(big_triangle(), "VEC3")
    return bin.document(
        ',"materials":['
        + material
        + "]"
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    )


def first_material(material: String, mut assets: Assets) raises -> MaterialId:
    """Load a one-material document and return the material's id."""
    var scene = Scene()
    var model = loaded(material_doc(material), scene, assets)
    return model.materials[0]


# --- required and used ------------------------------------------------------


def test_every_read_extension_can_be_required() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        doc(
            ',"extensionsRequired":["KHR_materials_emissive_strength",'
            + '"KHR_materials_ior","KHR_materials_specular",'
            + '"KHR_materials_clearcoat","KHR_materials_unlit",'
            + '"KHR_materials_sheen","KHR_materials_iridescence",'
            + '"KHR_materials_anisotropy",'
            + '"KHR_texture_transform","KHR_lights_punctual",'
            + '"KHR_mesh_quantization","EXT_mesh_gpu_instancing",'
            + '"KHR_materials_transmission","KHR_materials_volume",'
            + '"KHR_materials_dispersion"]'
        ),
        scene,
        assets,
    )
    assert_equal(model.node_count(), 0)
    assert_true(is_supported_extension("KHR_lights_punctual"))
    assert_true(is_supported_extension("KHR_materials_sheen"))
    assert_true(is_supported_extension("KHR_materials_transmission"))
    assert_false(is_supported_extension("KHR_materials_variants"))


def test_a_required_extension_that_is_not_read_is_refused() raises:
    # The first entry that is not read is named, wherever it is.
    refuses(
        doc(',"extensionsRequired":["KHR_materials_variants"]'),
        "KHR_materials_variants",
    )
    refuses(
        doc(
            ',"extensionsRequired":["KHR_texture_transform",'
            + '"KHR_materials_variants","KHR_draco_mesh_compression"]'
        ),
        "KHR_materials_variants",
    )
    # An extension only used is read without it: the variants are not
    # there.
    var scene = Scene()
    var assets = Assets()
    var index = first_material(
        '{"extensions":{"KHR_materials_variants":{"mappings":[]}}}',
        assets,
    )
    var material = assets.materials.get(index)
    assert_equal(material.kind, STANDARD)
    _ = scene


def test_malformed_extensions_are_refused() raises:
    refuses(material_doc('{"extensions":1}'), "extensions must be an object")
    refuses(
        material_doc('{"extensions":{"KHR_materials_unlit":true}}'),
        "KHR_materials_unlit must be an object",
    )


# --- materials --------------------------------------------------------------


def test_an_unlit_material_is_basic() raises:
    # three.js's `MeshBasicMaterial`: the base color and its map, and
    # nothing that a lit material reads, not even another extension.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"extensions":{"KHR_materials_unlit":{},'
            + '"KHR_materials_emissive_strength":{"emissiveStrength":4},'
            + '"KHR_materials_clearcoat":{"clearcoatFactor":1}},'
            + '"pbrMetallicRoughness":{"baseColorFactor":[1,1,1,0.5],'
            + '"baseColorTexture":{"index":0},"metallicRoughnessTexture":{"index":1}},'
            + '"normalTexture":{"index":1},"emissiveFactor":[1,1,1],'
            + '"alphaMode":"BLEND","doubleSided":true}]'
        ),
        scene,
        assets,
    )
    var flat = assets.materials.get(model.materials[0])
    assert_equal(flat.kind, BASIC)
    assert_equal(flat.map, model.color_textures[0])
    assert_equal(flat.emissive.r, UInt8(0))
    assert_equal(flat.normal_map, NO_TEXTURE)
    assert_equal(flat.roughness_map, NO_TEXTURE)
    assert_almost_equal(flat.opacity, Float32(0.5), atol=TOLERANCE)
    assert_true(flat.transparent)
    assert_equal(model.data_textures[1], NO_TEXTURE)
    # Unlit, it shows its texture with no light in the scene at all.
    assert_true(lit_pixels(scene, assets) > 20)
    # Without a pbrMetallicRoughness it is plain white.
    var more = Assets()
    var index = first_material(
        '{"extensions":{"KHR_materials_unlit":{}}}', more
    )
    var white = more.materials.get(index)
    assert_equal(white.kind, BASIC)
    assert_equal(white.color.g, UInt8(255))


def test_emissive_strength_scales_the_emissive() raises:
    var assets = Assets()
    var index = first_material(
        '{"emissiveFactor":[1,0,0],"extensions":'
        + '{"KHR_materials_emissive_strength":{"emissiveStrength":5}}}',
        assets,
    )
    var bright = assets.materials.get(index)
    assert_equal(bright.kind, STANDARD)
    assert_almost_equal(bright.emissive_intensity, Float32(5), atol=TOLERANCE)
    assert_equal(bright.emissive.r, UInt8(255))
    # With no strength named, one.
    index = first_material(
        '{"extensions":{"KHR_materials_emissive_strength":{}}}', assets
    )
    var plain = assets.materials.get(index)
    assert_almost_equal(plain.emissive_intensity, Float32(1), atol=TOLERANCE)
    # A negative strength is refused by the material.
    refuses(
        material_doc(
            '{"extensions":{"KHR_materials_emissive_strength":'
            + '{"emissiveStrength":-1}}}'
        ),
        "emissive intensity",
    )


def test_ior_specular_and_clearcoat_make_a_physical_material() raises:
    var assets = Assets()
    # Each alone, at its values.
    var index = first_material(
        '{"extensions":{"KHR_materials_ior":{"ior":1.25}}}', assets
    )
    var glass = assets.materials.get(index)
    assert_equal(glass.kind, PHYSICAL)
    assert_almost_equal(glass.ior, Float32(1.25), atol=TOLERANCE)
    assert_almost_equal(glass.specular_intensity, Float32(1), atol=TOLERANCE)
    assert_almost_equal(glass.clearcoat, Float32(0), atol=TOLERANCE)
    index = first_material(
        '{"extensions":{"KHR_materials_specular":{"specularFactor":0.5,'
        + '"specularColorFactor":[1,0,0.2158605]}}}',
        assets,
    )
    var tinted = assets.materials.get(index)
    assert_equal(tinted.kind, PHYSICAL)
    assert_almost_equal(tinted.ior, Float32(1.5), atol=TOLERANCE)
    assert_almost_equal(tinted.specular_intensity, Float32(0.5), atol=TOLERANCE)
    assert_equal(tinted.specular_color.r, UInt8(255))
    assert_equal(tinted.specular_color.g, UInt8(0))
    # The linear factor is written as sRGB, as three.js converts it.
    assert_equal(tinted.specular_color.b, UInt8(128))
    index = first_material(
        '{"extensions":{"KHR_materials_clearcoat":{"clearcoatFactor":0.75,'
        + '"clearcoatRoughnessFactor":0.25}}}',
        assets,
    )
    var coated = assets.materials.get(index)
    assert_equal(coated.kind, PHYSICAL)
    assert_almost_equal(coated.clearcoat, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(
        coated.clearcoat_roughness, Float32(0.25), atol=TOLERANCE
    )
    # Each empty, at three.js's defaults; still physical.
    index = first_material(
        '{"extensions":{"KHR_materials_ior":{},"KHR_materials_specular":{},'
        + '"KHR_materials_clearcoat":{}}}',
        assets,
    )
    var bare = assets.materials.get(index)
    assert_equal(bare.kind, PHYSICAL)
    assert_almost_equal(bare.ior, Float32(1.5), atol=TOLERANCE)
    assert_equal(bare.specular_color.b, UInt8(255))
    assert_almost_equal(bare.clearcoat, Float32(0), atol=TOLERANCE)
    # The metallic-roughness factors still apply.
    index = first_material(
        '{"pbrMetallicRoughness":{"metallicFactor":0.25,"roughnessFactor":0.5},'
        + '"extensions":{"KHR_materials_ior":{}}}',
        assets,
    )
    var rough = assets.materials.get(index)
    assert_almost_equal(rough.metalness, Float32(0.25), atol=TOLERANCE)
    assert_almost_equal(rough.roughness, Float32(0.5), atol=TOLERANCE)


def test_a_physical_factor_out_of_range_is_refused() raises:
    # A Color holds zero to one, so a specular color past either end is
    # refused rather than clamped.
    refuses(
        material_doc(
            '{"extensions":{"KHR_materials_specular":'
            + '{"specularColorFactor":[-0.5,0,0]}}}'
        ),
        "specularColorFactor must be from zero to one",
    )
    refuses(
        material_doc(
            '{"extensions":{"KHR_materials_specular":'
            + '{"specularColorFactor":[0,2,0]}}}'
        ),
        "specularColorFactor must be from zero to one",
    )
    # An index of refraction or a clear coat the material refuses.
    _ = refused(material_doc('{"extensions":{"KHR_materials_ior":{"ior":3}}}'))
    _ = refused(
        material_doc(
            '{"extensions":{"KHR_materials_clearcoat":{"clearcoatFactor":2}}}'
        )
    )
    _ = refused(
        material_doc(
            '{"extensions":{"KHR_materials_specular":{"specularFactor":2}}}'
        )
    )


def test_sheen_iridescence_and_anisotropy_make_a_physical_material() raises:
    var assets = Assets()
    # A sheen is on at one whenever the extension is there, black and
    # smooth by default, as three.js's plugin sets it.
    var bare = assets.materials.get(
        first_material('{"extensions":{"KHR_materials_sheen":{}}}', assets)
    )
    assert_equal(bare.kind, PHYSICAL)
    assert_equal(bare.sheen, Float32(1))
    assert_equal(bare.sheen_color.r, UInt8(0))
    assert_equal(bare.sheen_roughness, Float32(0))
    var velvet = assets.materials.get(
        first_material(
            '{"extensions":{"KHR_materials_sheen":{"sheenColorFactor":'
            + '[1,0,0.2158605],"sheenRoughnessFactor":0.5}}}',
            assets,
        )
    )
    assert_equal(velvet.sheen_color.r, UInt8(255))
    assert_equal(velvet.sheen_color.b, UInt8(128))
    assert_almost_equal(velvet.sheen_roughness, Float32(0.5), atol=TOLERANCE)
    # A film at three.js's defaults, then at the file's numbers.
    var plain_film = assets.materials.get(
        first_material(
            '{"extensions":{"KHR_materials_iridescence":{}}}', assets
        )
    )
    assert_equal(plain_film.kind, PHYSICAL)
    assert_equal(plain_film.iridescence, Float32(0))
    assert_almost_equal(plain_film.iridescence_ior, Float32(1.3), atol=1e-6)
    assert_almost_equal(
        plain_film.iridescence_thickness_minimum.to(NANOMETER),
        Float32(100),
        atol=1e-3,
    )
    var film = assets.materials.get(
        first_material(
            '{"extensions":{"KHR_materials_iridescence":'
            + '{"iridescenceFactor":0.5,"iridescenceIor":1.8,'
            + '"iridescenceThicknessMinimum":50,'
            + '"iridescenceThicknessMaximum":900}}}',
            assets,
        )
    )
    assert_almost_equal(film.iridescence, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(film.iridescence_ior, Float32(1.8), atol=TOLERANCE)
    assert_almost_equal(
        film.iridescence_thickness_minimum.to(NANOMETER),
        Float32(50),
        atol=1e-3,
    )
    assert_almost_equal(
        film.iridescence_thickness_maximum.to(NANOMETER),
        Float32(900),
        atol=1e-3,
    )
    # A stretch, empty and then turned.
    var even = assets.materials.get(
        first_material('{"extensions":{"KHR_materials_anisotropy":{}}}', assets)
    )
    assert_equal(even.kind, PHYSICAL)
    assert_equal(even.anisotropy, Float32(0))
    var brushed = assets.materials.get(
        first_material(
            '{"extensions":{"KHR_materials_anisotropy":'
            + '{"anisotropyStrength":0.75,"anisotropyRotation":1.5}}}',
            assets,
        )
    )
    assert_almost_equal(brushed.anisotropy, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(
        brushed.anisotropy_rotation.to(RADIAN), Float32(1.5), atol=TOLERANCE
    )
    # A factor the material refuses is refused.
    _ = refused(
        material_doc(
            '{"extensions":{"KHR_materials_sheen":{"sheenColorFactor":[2,0,0]}}}'
        )
    )
    _ = refused(
        material_doc(
            '{"extensions":{"KHR_materials_iridescence":{"iridescenceIor":3}}}'
        )
    )
    _ = refused(
        material_doc(
            '{"extensions":{"KHR_materials_anisotropy":'
            + '{"anisotropyStrength":2}}}'
        )
    )


def test_the_layer_extensions_read_their_maps() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"extensions":{"KHR_materials_sheen":{"sheenColorFactor":[1,1,1],'
            + '"sheenColorTexture":{"index":0},'
            + '"sheenRoughnessTexture":{"index":1}},'
            + '"KHR_materials_iridescence":{"iridescenceFactor":1,'
            + '"iridescenceTexture":{"index":1},'
            + '"iridescenceThicknessTexture":{"index":1}},'
            + '"KHR_materials_anisotropy":{"anisotropyStrength":1,'
            + '"anisotropyTexture":{"index":1}}}},'
            + '{"extensions":{"KHR_materials_sheen":{'
            + '"sheenRoughnessTexture":{"index":1}}}}]'
        ),
        scene,
        assets,
    )
    var material = assets.materials.get(model.materials[0])
    # The sheen color is a color whose alpha means nothing, and the sheen
    # roughness a number held in the alpha, which is kept.
    ref tint = assets.textures.get(material.sheen_color_map)
    assert_equal(tint.color_space, SRGB)
    assert_equal(tint.alpha, IGNORED)
    ref cloth = assets.textures.get(material.sheen_roughness_map)
    assert_equal(cloth.color_space, LINEAR)
    assert_equal(cloth.alpha, COVERAGE)
    # The other three are data, as every linear texture is.
    for map in [
        material.iridescence_map,
        material.iridescence_thickness_map,
        material.anisotropy_map,
    ]:
        assert_equal(assets.textures.get(map).color_space, LINEAR)
        assert_equal(assets.textures.get(map).alpha, IGNORED)
    # A second material reading the same roughness texture shares it.
    var second = assets.materials.get(model.materials[1])
    assert_equal(second.sheen_roughness_map, material.sheen_roughness_map)
    # And the renderer draws every one of the maps as it is stored.
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 3))
    assert_true(lit_pixels(scene, assets) > 0, "the layered quad drew nothing")
    # With no film and no stretch, three.js draws neither map, and the
    # loader leaves both out.
    var bare_scene = Scene()
    var bare = loaded(
        textured(
            '[{"extensions":{"KHR_materials_iridescence":'
            + '{"iridescenceTexture":{"index":1}},'
            + '"KHR_materials_anisotropy":{"anisotropyTexture":{"index":1}}}}]'
        ),
        bare_scene,
        assets,
    )
    var unmapped = assets.materials.get(bare.materials[0])
    assert_equal(unmapped.iridescence_map, NO_TEXTURE)
    assert_equal(unmapped.iridescence_thickness_map, NO_TEXTURE)
    assert_equal(unmapped.anisotropy_map, NO_TEXTURE)
    # A layer map moved apart from the base map keeps its own transform.
    var apart_scene = Scene()
    var apart = loaded(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}},'
            + '"extensions":{"KHR_materials_sheen":{"sheenColorTexture":'
            + '{"index":0,"extensions":{"KHR_texture_transform":'
            + '{"offset":[0.5,0]}}}}}}]'
        ),
        apart_scene,
        assets,
    )
    var sheened = assets.materials.get(apart.materials[0])
    assert_true(
        assets.textures.get(sheened.map).uv_transform()
        != assets.textures.get(sheened.sheen_color_map).uv_transform()
    )


# --- texture transforms -----------------------------------------------------


def moved_map(transform: String, mut assets: Assets) raises -> Int:
    """Load the quad with its base map under `transform` and return the
    map's texture index in the store, or -1 for the plain texture."""
    var scene = Scene()
    var model = loaded(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,'
            + '"extensions":{"KHR_texture_transform":'
            + transform
            + "}}}}]"
        ),
        scene,
        assets,
    )
    var map = assets.materials.get(model.materials[0]).map
    if map == model.color_textures[0]:
        return -1
    return map.value


def check_transform(
    offset_u: Float32,
    offset_v: Float32,
    turn: Float32,
    scale_u: Float32,
    scale_v: Float32,
    json: String,
) raises:
    """Assert that the transform `json` names carries glTF coordinates
    where three.js's matrix carries them: every glTF texture has `flip_y`
    off, so no flip follows."""
    var assets = Assets()
    var index = moved_map(json, assets)
    assert_true(index >= 0)
    var matrix = assets.textures.textures[index].uv_transform()
    var c = cos(turn)
    var s = sin(turn)
    var corners: List[Float32] = [0, 0, 1, 0, 0.25, 0.75, 1, 1]
    for at in range(4):
        var u = corners[at * 2]
        var v = corners[at * 2 + 1]
        # three.js's `setUvTransform` with its center at the origin, as
        # `GLTFTextureTransformExtension` leaves it.
        var want_u = scale_u * c * u + scale_u * s * v + offset_u
        var want_v = -scale_v * s * u + scale_v * c * v + offset_v
        var got_u = (
            matrix.get(0, 0) * u + matrix.get(0, 1) * v + matrix.get(0, 2)
        )
        var got_v = (
            matrix.get(1, 0) * u + matrix.get(1, 1) * v + matrix.get(1, 2)
        )
        assert_almost_equal(got_u, want_u, atol=1e-5)
        assert_almost_equal(got_v, want_v, atol=1e-5)


def test_a_texture_transform_moves_turns_and_scales_the_map() raises:
    check_transform(
        0.5,
        0.25,
        0.3,
        2,
        3,
        '{"offset":[0.5,0.25],"rotation":0.3,"scale":[2,3]}',
    )
    # Each part alone, the others at the identity's.
    check_transform(0.5, 0.25, 0, 1, 1, '{"offset":[0.5,0.25]}')
    check_transform(0, 0, 0, 2, 4, '{"scale":[2,4]}')
    check_transform(0, 0, 1, 1, 1, '{"rotation":1}')
    # A transform that only names the first set of coordinates is no
    # transform: the texture is not copied, as three.js does not clone it.
    var assets = Assets()
    assert_equal(moved_map('{"texCoord":0}', assets), -1)
    assert_equal(moved_map("{}", assets), -1)


def test_a_texture_transform_names_the_coordinates_that_are_read() raises:
    # The transform's texCoord wins over the texture's own, as in three.js.
    var assets = Assets()
    var scene = Scene()
    var model = loaded(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,'
            + '"texCoord":1,"extensions":{"KHR_texture_transform":{"texCoord":0}}}}}]'
        ),
        scene,
        assets,
    )
    assert_equal(
        assets.materials.get(model.materials[0]).map, model.color_textures[0]
    )
    # The second set gives the map a copy on `UV_CHANNEL_1`, any map as
    # in three.js, and the transform's texCoord still wins.
    var second = loaded(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,'
            + '"extensions":{"KHR_texture_transform":{"texCoord":1}}}}}]'
        ),
        scene,
        assets,
    )
    var moved = assets.materials.get(second.materials[0]).map
    assert_true(moved != second.color_textures[0])
    assert_equal(assets.textures.get(moved).channel, UV_CHANNEL_1)
    refuses(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,'
            + '"extensions":{"KHR_texture_transform":{"texCoord":2}}}}}]'
        ),
        "first two sets",
    )


def test_the_maps_of_one_material_keep_their_own_transforms() raises:
    # Each map is sampled at its own coordinate, as in three.js: a base
    # map moved and a normal map left alone keep their own transforms.
    var apart_scene = Scene()
    var apart_assets = Assets()
    var apart = loaded(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,'
            + '"extensions":{"KHR_texture_transform":{"offset":[0.5,0]}}}},'
            + '"normalTexture":{"index":1,"texCoord":1}}]'
        ),
        apart_scene,
        apart_assets,
    )
    var parted = apart_assets.materials.get(apart.materials[0])
    var base = apart_assets.textures.get(parted.map).placement()
    var bumps = apart_assets.textures.get(parted.normal_map).placement()
    assert_equal(base.x0, Float32(0.5))
    assert_equal(base.channel, UV_CHANNEL_0)
    assert_equal(bumps.x0, Float32(0))
    assert_equal(bumps.channel, UV_CHANNEL_1)
    # Moved together, they are read alike.
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,'
            + '"extensions":{"KHR_texture_transform":{"offset":[0.5,0]}}},'
            + '"metallicRoughnessTexture":{"index":1,'
            + '"extensions":{"KHR_texture_transform":{"offset":[0.5,0]}}}},'
            + '"emissiveTexture":{"index":0,'
            + '"extensions":{"KHR_texture_transform":{"offset":[0.5,0]}}},'
            + '"normalTexture":{"index":1,"scale":0.5,'
            + '"extensions":{"KHR_texture_transform":{"offset":[0.5,0]}}}}]'
        ),
        scene,
        assets,
    )
    var material = assets.materials.get(model.materials[0])
    assert_true(material.normal_map != NO_TEXTURE)
    assert_almost_equal(material.normal_scale.x, Float32(0.5), atol=TOLERANCE)


def test_a_moved_map_draws_where_the_transform_puts_it() raises:
    # Half a tile across: the quad's top left shows the checker's top
    # right, green, and its top right wraps round to the red top left.
    var scene = Scene()
    var assets = Assets()
    _ = loaded(
        textured(
            '[{"extensions":{"KHR_materials_unlit":{}},'
            + '"pbrMetallicRoughness":{"baseColorTexture":{"index":0,'
            + '"extensions":{"KHR_texture_transform":{"offset":[0.5,0]}}}}}]'
        ),
        scene,
        assets,
    )
    scene.update()
    var renderer = Renderer(24, 24)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, camera_at(3))
    var top_left = image.get_pixel(8, 8)
    var top_right = image.get_pixel(15, 8)
    assert_true(
        top_left.g > 150 and top_left.r < 60, "the top left is not green"
    )
    assert_true(
        top_right.r > 150 and top_right.g < 60, "the top right is not red"
    )


# --- lights -----------------------------------------------------------------


def lights_doc(lights: String, nodes: String) -> String:
    """Return a document of lights and the nodes that carry them, every
    node a root."""
    return doc(
        ',"extensions":{"KHR_lights_punctual":{"lights":'
        + lights
        + '}},"nodes":'
        + nodes
        + ',"scenes":[{"nodes":[0]}]'
    )


def carried(light: Int) -> String:
    """Return a node's extensions naming a light."""
    return (
        '"extensions":{"KHR_lights_punctual":{"light":' + String(light) + "}}"
    )


def test_punctual_lights_ride_their_nodes() raises:
    var scene = Scene()
    var assets = Assets()
    var before = Object3D()
    _ = scene.add(before^)
    scene.add_light(directional_light(Color(255, 255, 255), NO_PARENT))
    var model = loaded(
        doc(
            ',"extensions":{"KHR_lights_punctual":{"lights":['
            + '{"type":"directional","color":[1,0,0.2158605],"intensity":3},'
            + '{"type":"point","range":5,"intensity":20},'
            + '{"type":"spot","spot":{"innerConeAngle":0.25,"outerConeAngle":0.5}},'
            + '{"type":"spot","spot":{}}]}}'
            + ',"nodes":[{"children":[1,2,3,4]},'
            + '{"translation":[0,2,0],'
            + carried(0)
            + "},{"
            + carried(1)
            + "},{"
            + carried(2)
            + "},{"
            + carried(3)
            + "}]"
            + ',"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    assert_equal(model.first_light, 1)
    assert_equal(model.light_count, 4)
    scene.update()
    ref sun = scene.lights[1]
    assert_equal(sun.kind, DIRECTIONAL)
    assert_equal(sun.node, model.nodes[1])
    assert_equal(sun.color.r, UInt8(255))
    assert_equal(sun.color.g, UInt8(0))
    assert_equal(sun.color.b, UInt8(128))
    assert_almost_equal(sun.intensity, Float32(3), atol=TOLERANCE)
    # Its target sits a meter down the node's -z, three.js's.
    var aim = scene.world_position(sun.target)
    assert_almost_equal(aim.y, Float32(2), atol=TOLERANCE)
    assert_almost_equal(aim.z, Float32(-1), atol=TOLERANCE)
    assert_equal(scene.get(sun.target).parent, model.nodes[1])
    ref bulb = scene.lights[2]
    assert_equal(bulb.kind, POINT)
    assert_equal(bulb.color.g, UInt8(255))
    assert_almost_equal(bulb.intensity, Float32(20), atol=TOLERANCE)
    assert_almost_equal(bulb.distance, Float32(5), atol=TOLERANCE)
    assert_almost_equal(bulb.decay, Float32(2), atol=TOLERANCE)
    ref cone = scene.lights[3]
    assert_equal(cone.kind, SPOT)
    assert_almost_equal(cone.intensity, Float32(1), atol=TOLERANCE)
    assert_almost_equal(cone.distance, Float32(0), atol=TOLERANCE)
    assert_almost_equal(cone.angle.to(RADIAN), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(cone.penumbra, Float32(0.5), atol=TOLERANCE)
    assert_equal(scene.get(cone.target).parent, model.nodes[3])
    # A spot with no angles: no inner cone, and a quarter of a half turn.
    ref wide = scene.lights[4]
    assert_almost_equal(wide.angle.to(RADIAN), Float32(pi / 4), atol=TOLERANCE)
    assert_almost_equal(wide.penumbra, Float32(1), atol=TOLERANCE)


def test_a_file_light_lights_a_file_mesh() raises:
    # A standard triangle facing +z, and a directional light on a node at
    # the origin that shines down -z onto it.
    var bin = Bin()
    _ = bin.floats(big_triangle(), "VEC3")
    var body = (
        ',"materials":[{"pbrMetallicRoughness":{"metallicFactor":0}}]'
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0},"material":0}]}]'
        + ',"nodes":[{"mesh":0},{"translation":[0,0,2],'
        + carried(0)
        + '}],"scenes":[{"nodes":[0,1]}]'
    )
    var scene = Scene()
    var assets = Assets()
    _ = loaded(
        bin.document(
            ',"extensions":{"KHR_lights_punctual":{"lights":'
            + '[{"type":"directional","intensity":3}]}}'
            + body
        ),
        scene,
        assets,
    )
    assert_true(lit_pixels(scene, assets) > 20, "the light did not reach")
    # The same file with no light draws nothing but black.
    var dark = Scene()
    var more = Assets()
    _ = loaded(
        bin.document(
            ',"extensions":{"KHR_lights_punctual":{"lights":'
            + '[{"type":"directional","intensity":0}]}}'
            + body
        ),
        dark,
        more,
    )
    assert_equal(lit_pixels(dark, more), 0)


def test_a_malformed_light_is_refused() raises:
    # A node names a light and the file has none.
    refuses(
        doc(',"nodes":[{' + carried(0) + '}],"scenes":[{"nodes":[0]}]'),
        "the file has none",
    )
    # The lights are not an array.
    refuses(
        doc(
            ',"extensions":{"KHR_lights_punctual":{}},"nodes":[{'
            + carried(0)
            + '}],"scenes":[{"nodes":[0]}]'
        ),
        "lights must be an array",
    )
    # A node's light entry without its index.
    refuses(
        lights_doc(
            '[{"type":"point"}]', '[{"extensions":{"KHR_lights_punctual":{}}}]'
        ),
        "light is required",
    )
    # A light index outside the array, either way.
    refuses(
        lights_doc('[{"type":"point"}]', "[{" + carried(-1) + "}]"),
        "names a light that is not there",
    )
    refuses(
        lights_doc('[{"type":"point"}]', "[{" + carried(1) + "}]"),
        "names a light that is not there",
    )
    # A range must be above zero when it is there.
    refuses(
        lights_doc('[{"type":"point","range":0}]', "[{" + carried(0) + "}]"),
        "range must be above zero",
    )
    # A type that is none of the three.
    refuses(
        lights_doc('[{"type":"area"}]', "[{" + carried(0) + "}]"),
        "must be directional, point or spot",
    )
    # A spot light without its spot object, or with one that is not one.
    refuses(
        lights_doc('[{"type":"spot"}]', "[{" + carried(0) + "}]"),
        "needs a spot object",
    )
    refuses(
        lights_doc('[{"type":"spot","spot":1}]', "[{" + carried(0) + "}]"),
        "needs a spot object",
    )
    # An inner cone past the outer one is a negative penumbra, which the
    # light refuses.
    refuses(
        lights_doc(
            '[{"type":"spot","spot":{"innerConeAngle":1,"outerConeAngle":0.5}}]',
            "[{" + carried(0) + "}]",
        ),
        "penumbra",
    )
    # A negative intensity, which the light refuses.
    refuses(
        lights_doc(
            '[{"type":"directional","intensity":-1}]', "[{" + carried(0) + "}]"
        ),
        "intensity",
    )


# --- quantization and instancing --------------------------------------------


def test_quantized_attributes_are_read() raises:
    # KHR_mesh_quantization: positions as whole shorts, coordinates as
    # normalized unsigned bytes.
    var bin = Bin()
    _ = bin.ints([-1, -1, 0, 1, -1, 0, 0, 1, 0], SHORT, "VEC3")
    _ = bin.ints([0, 0, 255, 0, 0, 255], UBYTE, "VEC2", ',"normalized":true')
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        bin.document(
            ',"extensionsUsed":["KHR_mesh_quantization"]'
            + ',"extensionsRequired":["KHR_mesh_quantization"]'
            + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,"TEXCOORD_0":1}}]}]'
            + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
        ),
        scene,
        assets,
    )
    ref shape = assets.geometries.get(model.geometries[0])
    assert_almost_equal(
        shape.attribute_view(String(POSITION)).component(0, 0),
        Float32(-1),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        shape.attribute_view(String(UV)).component(1, 0),
        Float32(1),
        atol=TOLERANCE,
    )


def instanced(mut bin: Bin, attributes: String, node: String = "") -> String:
    """Return a document of a triangle mesh of two primitives, drawn by a
    node whose `EXT_mesh_gpu_instancing` names `attributes`."""
    return bin.document(
        ',"meshes":[{"primitives":[{"attributes":{"POSITION":0}},'
        + '{"attributes":{"POSITION":0},"material":0}]},{"primitives":[]}]'
        + ',"materials":[{}]'
        + ',"nodes":[{"mesh":0'
        + node
        + ',"extensions":{"EXT_mesh_gpu_instancing":'
        + attributes
        + "}}]"
        + ',"scenes":[{"nodes":[0]}]'
    )


def test_an_instanced_node_draws_instanced_meshes() raises:
    var bin = Bin()
    _ = bin.floats(big_triangle(), "VEC3")
    var moves = bin.floats([1, 2, 3, -1, 0, 0], "VEC3")
    # A quarter turn about z, as normalized shorts, and none.
    var turns = bin.ints(
        [0, 0, 23170, 23170, 0, 0, 0, 32767],
        SHORT,
        "VEC4",
        ',"normalized":true',
    )
    var sizes = bin.floats([2, 2, 2, 1, 1, 1], "VEC3")
    var tints = bin.floats([1, 0, 0, 0, 0, 1], "VEC3")
    var ids = bin.floats([7, 8], "SCALAR")
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        instanced(
            bin,
            '{"attributes":{"TRANSLATION":'
            + String(moves)
            + ',"ROTATION":'
            + String(turns)
            + ',"SCALE":'
            + String(sizes)
            + ',"_COLOR_0":'
            + String(tints)
            + ',"_ID":'
            + String(ids)
            + "}}",
        ),
        scene,
        assets,
    )
    # One instanced mesh per primitive, and no plain mesh.
    assert_equal(model.mesh_count, 0)
    assert_equal(model.first_instanced_mesh, 0)
    assert_equal(model.instanced_mesh_count, 2)
    ref crowd = scene.instanced_meshes[0]
    assert_equal(crowd.count(), 2)
    assert_equal(crowd.node, model.nodes[0])
    assert_equal(crowd.geometry, model.geometries[0])
    assert_equal(scene.instanced_meshes[1].material, model.materials[0])
    # The first instance: moved, turned a quarter about z, doubled.
    var first = crowd.matrix_at(0)
    var corner = first.transform_point(Vector3(1, 0, 0))
    assert_almost_equal(corner.x, Float32(1), atol=1e-4)
    assert_almost_equal(corner.y, Float32(4), atol=1e-4)
    assert_almost_equal(corner.z, Float32(3), atol=1e-4)
    var second = crowd.matrix_at(1).transform_point(Vector3(1, 0, 0))
    assert_almost_equal(second.x, Float32(0), atol=1e-4)
    assert_equal(crowd.color_at(0).r, UInt8(255))
    assert_equal(crowd.color_at(1).b, UInt8(255))
    assert_equal(crowd.color_at(1).r, UInt8(0))


def test_an_instanced_node_with_only_translations_or_none() raises:
    var bin = Bin()
    _ = bin.floats(big_triangle(), "VEC3")
    var moves = bin.floats([1, 2, 3], "VEC3")
    var none = bin.accessor('{"componentType":5126,"count":0,"type":"VEC3"}')
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        instanced(bin, '{"attributes":{"TRANSLATION":' + String(moves) + "}}"),
        scene,
        assets,
    )
    ref crowd = scene.instanced_meshes[0]
    assert_equal(crowd.count(), 1)
    assert_equal(len(crowd.colors), 0)
    var at = crowd.matrix_at(0).transform_point(Vector3(0, 0, 0))
    assert_almost_equal(at.z, Float32(3), atol=TOLERANCE)
    _ = model
    # Only a scale: the instance stays at the node, grown.
    var grown = Scene()
    var kept = Assets()
    _ = loaded(
        instanced(bin, '{"attributes":{"SCALE":' + String(moves) + "}}"),
        grown,
        kept,
    )
    var far = grown.instanced_meshes[0].matrix_at(0)
    var tip = far.transform_point(Vector3(1, 1, 1))
    assert_almost_equal(tip.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(tip.z, Float32(3), atol=TOLERANCE)
    # No instance at all: instanced meshes of none.
    var empty = Scene()
    var more = Assets()
    _ = loaded(
        instanced(bin, '{"attributes":{"TRANSLATION":' + String(none) + "}}"),
        empty,
        more,
    )
    assert_equal(empty.instanced_meshes[0].count(), 0)
    # No attribute at all: plain meshes, as three.js draws them.
    var plain = Scene()
    var again = Assets()
    var drawn = loaded(instanced(bin, '{"attributes":{}}'), plain, again)
    assert_equal(drawn.mesh_count, 2)
    assert_equal(drawn.instanced_mesh_count, 0)
    # A mesh of no primitives, instanced, draws nothing.
    var bare = Scene()
    var others = Assets()
    var nothing = loaded(
        bin.document(
            ',"meshes":[{"primitives":[]}],"nodes":[{"mesh":0,'
            + '"extensions":{"EXT_mesh_gpu_instancing":{"attributes":'
            + '{"TRANSLATION":'
            + String(moves)
            + "}}}}]"
            + ',"scenes":[{"nodes":[0]}]'
        ),
        bare,
        others,
    )
    assert_equal(nothing.instanced_mesh_count, 0)


def test_a_malformed_instancing_is_refused() raises:
    var bin = Bin()
    _ = bin.floats(big_triangle(), "VEC3")
    var one = bin.floats([1, 2, 3], "VEC3")
    var two = bin.floats([1, 2, 3, 4, 5, 6], "VEC3")
    var turn = bin.floats([0, 0, 0], "VEC3")
    var four = bin.floats([0, 0, 0, 1], "VEC4")
    refuses(instanced(bin, "{}"), "needs attributes")
    refuses(instanced(bin, '{"attributes":1}'), "needs attributes")
    refuses(
        instanced(
            bin,
            '{"attributes":{"TRANSLATION":'
            + String(one)
            + ',"SCALE":'
            + String(two)
            + "}}",
        ),
        "as many elements",
    )
    refuses(
        instanced(bin, '{"attributes":{"ROTATION":' + String(turn) + "}}"),
        "ROTATION must be a VEC4",
    )
    refuses(
        instanced(bin, '{"attributes":{"_COLOR_0":' + String(four) + "}}"),
        "_COLOR_0 must be a VEC3",
    )
    # A skinned node cannot be instanced.
    refuses(
        instanced(bin, '{"attributes":{}}', ',"skin":0'),
        "a skinned node cannot be instanced",
    )
    # An instanced node that names a mesh the file does not have.
    refuses(
        bin.document(
            ',"nodes":[{"mesh":3,"extensions":{"EXT_mesh_gpu_instancing":'
            + '{"attributes":{"TRANSLATION":'
            + String(one)
            + '}}}}],"scenes":[{"nodes":[0]}]'
        ),
        "names a mesh that is not there",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


# --- transmission, volume and dispersion ------------------------------------

from std.math import inf


def test_transmission_volume_and_dispersion_make_a_glass() raises:
    var assets = Assets()
    var index = first_material(
        '{"extensions":{"KHR_materials_transmission":'
        + '{"transmissionFactor":0.75},'
        + '"KHR_materials_volume":{"thicknessFactor":0.5,'
        + '"attenuationDistance":2,"attenuationColor":[1,0,0.2158605]},'
        + '"KHR_materials_dispersion":{"dispersion":3}}}',
        assets,
    )
    var glass = assets.materials.get(index)
    assert_equal(glass.kind, PHYSICAL)
    assert_true(glass.transmits())
    assert_almost_equal(glass.transmission, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(glass.thickness.to(METER), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(
        glass.attenuation_distance.to(METER), Float32(2), atol=TOLERANCE
    )
    # The linear factor is written as sRGB, as three.js converts it.
    assert_equal(glass.attenuation_color.r, UInt8(255))
    assert_equal(glass.attenuation_color.g, UInt8(0))
    assert_equal(glass.attenuation_color.b, UInt8(128))
    assert_almost_equal(glass.dispersion, Float32(3), atol=TOLERANCE)
    # Each empty: three.js's defaults, and a physical material still.
    index = first_material(
        '{"extensions":{"KHR_materials_transmission":{},'
        + '"KHR_materials_volume":{},"KHR_materials_dispersion":{}}}',
        assets,
    )
    var bare = assets.materials.get(index)
    assert_equal(bare.kind, PHYSICAL)
    assert_equal(bare.transmission, Float32(0))
    assert_equal(bare.thickness.to(METER), Float32(0))
    assert_equal(bare.attenuation_distance.to(METER), inf[DType.float32]())
    assert_equal(bare.attenuation_color.g, UInt8(255))
    assert_equal(bare.dispersion, Float32(0))
    # A distance of zero is none, as three.js's `|| Infinity` reads it.
    index = first_material(
        '{"extensions":{"KHR_materials_volume":{"attenuationDistance":0}}}',
        assets,
    )
    assert_equal(
        assets.materials.get(index).attenuation_distance.to(METER),
        inf[DType.float32](),
    )
    refuses(
        material_doc(
            '{"extensions":{"KHR_materials_transmission":'
            + '{"transmissionFactor":2}}}'
        ),
        "transmission must be between",
    )


def test_the_volume_maps_are_read_as_data() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"extensions":{"KHR_materials_transmission":'
            + '{"transmissionFactor":1,"transmissionTexture":{"index":1}},'
            + '"KHR_materials_volume":{"thicknessFactor":0.2,'
            + '"thicknessTexture":{"index":1}}}}]'
        ),
        scene,
        assets,
    )
    var glass = assets.materials.get(model.materials[0])
    assert_true(glass.transmission_map != NO_TEXTURE)
    assert_true(glass.thickness_map != NO_TEXTURE)
    assert_true(
        assets.textures.get(glass.transmission_map).color_space == LINEAR
    )
    assert_true(assets.textures.get(glass.transmission_map).alpha == IGNORED)
    assert_true(assets.textures.get(glass.thickness_map).alpha == IGNORED)


# --- occlusion --------------------------------------------------------------

from core.buffer_geometry import UV1
from render.texture import UV_CHANNEL_0, UV_CHANNEL_1


def occluded(material: String, second: String = "VEC2") -> String:
    """Return the checker quad's document with a second set of texture
    coordinates of type `second`, and `material` as its one material."""
    var bin = Bin()
    _ = bin.floats([-1, 1, 0, 1, 1, 0, 1, -1, 0, -1, -1, 0], "VEC3")
    _ = bin.floats([0, 0, 1, 0, 1, 1, 0, 1], "VEC2")
    _ = bin.ints([0, 2, 1, 0, 3, 2], USHORT, "SCALAR")
    if second == "VEC2":
        _ = bin.floats([0.5, 0.5, 1, 0.5, 1, 1, 0.25, 0.75], "VEC2")
    else:
        _ = bin.floats([0.5, 0.5, 1, 0.5, 1, 1, 0.25, 0.75, 0, 0, 0, 0], second)
    return bin.document(
        ',"images":[{"uri":"data:image/png;base64,'
        + CHECKER
        + '"}],"samplers":[{"magFilter":9728,"minFilter":9728}]'
        + ',"textures":[{"source":0,"sampler":0}]'
        + ',"materials":['
        + material
        + "]"
        + ',"meshes":[{"primitives":[{"attributes":{"POSITION":0,'
        + '"TEXCOORD_0":1,"TEXCOORD_1":3},"indices":2,"material":0}]}]'
        + ',"nodes":[{"mesh":0}],"scenes":[{"nodes":[0]}]'
    )


def test_an_occlusion_texture_is_the_ao_map() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        occluded(
            '{"occlusionTexture":{"index":0,"texCoord":1,"strength":0.25}}'
        ),
        scene,
        assets,
    )
    var material = assets.materials.get(model.materials[0])
    assert_true(material.ao_map != NO_TEXTURE)
    assert_almost_equal(material.ao_map_intensity, 0.25, atol=TOLERANCE)
    ref ao = assets.textures.get(material.ao_map)
    assert_equal(ao.channel, UV_CHANNEL_1)
    assert_equal(ao.color_space, LINEAR)
    assert_equal(ao.alpha, IGNORED)
    # The data texture the file names is left on the first set.
    assert_equal(
        assets.textures.get(model.data_textures[0]).channel, UV_CHANNEL_0
    )
    ref geometry = assets.geometries.get(model.geometries[0])
    var second = geometry.attribute_view(String(UV1)).data.copy()
    assert_equal(len(second), 8)
    assert_equal(second[7], 0.75)


def test_an_occlusion_texture_on_the_first_set_is_not_copied() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        occluded('{"occlusionTexture":{"index":0}}'), scene, assets
    )
    var material = assets.materials.get(model.materials[0])
    assert_equal(material.ao_map, model.data_textures[0])
    assert_equal(material.ao_map_intensity, 1)
    # The transform's texCoord wins, as three.js lets it.
    var other = Assets()
    var again = Scene()
    var moved = loaded(
        occluded(
            '{"occlusionTexture":{"index":0,"extensions":'
            + '{"KHR_texture_transform":{"texCoord":1,"offset":[0.5,0]}}}}'
        ),
        again,
        other,
    )
    ref ao = other.textures.get(other.materials.get(moved.materials[0]).ao_map)
    assert_equal(ao.channel, UV_CHANNEL_1)
    assert_almost_equal(ao.offset.x, 0.5, atol=TOLERANCE)
    # An unlit material reads no occlusion, as three.js reads it.
    var flat = Assets()
    var plain = Scene()
    var unlit = loaded(
        occluded(
            '{"extensions":{"KHR_materials_unlit":{}},'
            + '"occlusionTexture":{"index":0}}'
        ),
        plain,
        flat,
    )
    assert_equal(flat.materials.get(unlit.materials[0]).ao_map, NO_TEXTURE)


def test_a_malformed_occlusion_is_refused() raises:
    refuses(
        occluded('{"occlusionTexture":{"index":0,"texCoord":2}}'),
        "first two sets",
    )
    refuses(
        occluded('{"occlusionTexture":{"index":0,"texCoord":-1}}'),
        "first two sets",
    )
    refuses(
        occluded('{"normalTexture":{"index":0,"texCoord":-1}}'),
        "first two sets",
    )
    refuses(
        occluded('{"occlusionTexture":{"index":0,"strength":-1}}'),
        "ao map intensity",
    )
    refuses(occluded("{}", "VEC3"), "TEXCOORD_1 must be a VEC2")


# --- specular and clearcoat maps --------------------------------------------


def test_the_specular_and_clearcoat_extensions_read_their_maps() raises:
    var scene = Scene()
    var assets = Assets()
    var model = loaded(
        textured(
            '[{"extensions":{"KHR_materials_specular":{'
            + '"specularTexture":{"index":1},'
            + '"specularColorTexture":{"index":0}},'
            + '"KHR_materials_clearcoat":{"clearcoatFactor":1,'
            + '"clearcoatTexture":{"index":1},'
            + '"clearcoatRoughnessTexture":{"index":1},'
            + '"clearcoatNormalTexture":{"index":1,"scale":0.5}}}},'
            + '{"extensions":{"KHR_materials_clearcoat":{"clearcoatFactor":1,'
            + '"clearcoatNormalTexture":{"index":1}}}}]'
        ),
        scene,
        assets,
    )
    var material = assets.materials.get(model.materials[0])
    # The specular intensity is a number held in the alpha, which is kept,
    # and the specular color a color whose alpha means nothing.
    ref strength = assets.textures.get(material.specular_intensity_map)
    assert_equal(strength.color_space, LINEAR)
    assert_equal(strength.alpha, COVERAGE)
    ref tint = assets.textures.get(material.specular_color_map)
    assert_equal(tint.color_space, SRGB)
    assert_equal(tint.alpha, IGNORED)
    # The coat's three are data, as every linear texture is.
    for map in [
        material.clearcoat_map,
        material.clearcoat_roughness_map,
        material.clearcoat_normal_map,
    ]:
        assert_equal(assets.textures.get(map).color_space, LINEAR)
        assert_equal(assets.textures.get(map).alpha, IGNORED)
    # The normal texture's scale is three.js's, on both axes.
    assert_equal(material.clearcoat_normal_scale.x, Float32(0.5))
    assert_equal(material.clearcoat_normal_scale.y, Float32(0.5))
    # With no scale, the scale is one.
    var second = assets.materials.get(model.materials[1])
    assert_true(second.clearcoat_normal_map != NO_TEXTURE)
    assert_equal(second.clearcoat_normal_scale.x, Float32(1))
    assert_equal(second.clearcoat_map, NO_TEXTURE)
    # And the renderer draws every one of the maps as it is stored.
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 3))
    assert_true(lit_pixels(scene, assets) > 0, "the coated quad drew nothing")
    # With no coat, three.js draws none of its maps, and the loader leaves
    # them out, the normal texture's scale with them.
    var bare_scene = Scene()
    var bare = loaded(
        textured(
            '[{"extensions":{"KHR_materials_clearcoat":{'
            + '"clearcoatTexture":{"index":1},'
            + '"clearcoatRoughnessTexture":{"index":1},'
            + '"clearcoatNormalTexture":{"index":1,"scale":0.5}}}}]'
        ),
        bare_scene,
        assets,
    )
    var unmapped = assets.materials.get(bare.materials[0])
    assert_equal(unmapped.clearcoat_map, NO_TEXTURE)
    assert_equal(unmapped.clearcoat_roughness_map, NO_TEXTURE)
    assert_equal(unmapped.clearcoat_normal_map, NO_TEXTURE)
    assert_equal(unmapped.clearcoat_normal_scale.x, Float32(1))
    # A coat map moved apart from the base map keeps its own transform.
    var apart_scene = Scene()
    var apart = loaded(
        textured(
            '[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}},'
            + '"extensions":{"KHR_materials_clearcoat":{"clearcoatFactor":1,'
            + '"clearcoatNormalTexture":'
            + '{"index":1,"extensions":{"KHR_texture_transform":'
            + '{"offset":[0.5,0]}}}}}}]'
        ),
        apart_scene,
        assets,
    )
    var coated = assets.materials.get(apart.materials[0])
    assert_equal(
        assets.textures.get(coated.clearcoat_normal_map).placement().x0,
        Float32(0.5),
    )
    assert_equal(assets.textures.get(coated.map).placement().x0, Float32(0))
