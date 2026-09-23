# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the newer material features `exporters.gltf` writes: the
occlusion texture and the second set of texture coordinates,
`KHR_texture_transform`, `KHR_materials_emissive_strength`, and the
physical material extensions `loaders.gltf` reads.

Each test writes a scene, reads it back, writes what was read and reads
that again. The material must survive both trips.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, UV1, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from exporters.gltf import GLB, GLTF_EMBEDDED, GltfPlacement, export_gltf
from loaders.gltf import load_gltf, split_glb
from loaders.json import JsonDocument, NO_NODE, parse_json
from materials.material import (
    BASIC,
    NO_TEXTURE,
    PHYSICAL,
    STANDARD,
    Material,
    MaterialId,
    physical_material,
    standard_material,
)
from math.vector2 import Vector2
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import (
    IGNORED,
    UV_CHANNEL_0,
    UV_CHANNEL_1,
    Texture,
)
from render.texture_store import TextureId
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Length, METER, RADIAN

comptime TOLERANCE = Float64(1e-5)


def image(
    seed: Int, color_space: ColorSpace = SRGB, alpha_ignored: Bool = False
) raises -> Texture:
    """Return a three-by-two texture whose every texel is different."""
    var pixels = List[UInt8]()
    for texel in range(6):
        pixels.append(UInt8((seed + texel * 17) % 256))
        pixels.append(UInt8((seed * 3 + texel * 29) % 256))
        pixels.append(UInt8((seed * 7 + texel * 41) % 256))
        pixels.append(255)
    var built = Texture(3, 2, pixels^, color_space=color_space)
    if alpha_ignored:
        return built.ignoring_alpha()
    return built^


def data_image(seed: Int) raises -> Texture:
    """Return a texture of numbers: linear, its alpha ignored."""
    return image(seed, LINEAR, True)


def square(second_set: Bool) raises -> BufferGeometry:
    """Return a square with normals and one or two sets of coordinates."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([Float32(-1), -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0], 3),
    )
    geometry.set_attribute(
        String(NORMAL),
        BufferAttribute([Float32(0), 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 3),
    )
    geometry.set_attribute(
        String(UV), BufferAttribute([Float32(0), 0, 1, 0, 1, 1, 0, 1], 2)
    )
    if second_set:
        geometry.set_attribute(
            String(UV1),
            BufferAttribute([Float32(0.5), 0.5, 1, 0.5, 1, 1, 0.25, 0.75], 2),
        )
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


def one_mesh(
    mut assets: Assets, material: Material, second_set: Bool = False
) raises -> Scene:
    """Return a scene of one square on one node."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var shape = assets.geometries.add(square(second_set))
    scene.add_mesh(Mesh(shape, assets.materials.add(material), node))
    return scene^


struct Trip(Movable):
    """A scene read back from a GLB, and the JSON it was read from."""

    var scene: Scene
    var assets: Assets
    var json: String

    def __init__(out self, scene: Scene, assets: Assets) raises:
        """Write a scene as a GLB and read it back."""
        var files = export_gltf(scene, assets, GLB)
        self.json = split_glb(files.document)[0]
        self.scene = Scene()
        self.assets = Assets()
        var parts = split_glb(files.document)
        _ = load_gltf(parts[0], parts[1], "", self.scene, self.assets)

    def material(self) raises -> Material:
        """Return the first mesh's material."""
        return self.assets.materials.get(self.scene.meshes[0].material)

    def again(self) raises -> Trip:
        """Write what was read and read it back once more."""
        return Trip(self.scene, self.assets)

    def document(self) raises -> JsonDocument:
        """Return the JSON that was written."""
        return parse_json(self.json)

    def first_material(self) raises -> Int:
        """Return the written document's first material node."""
        var document = self.document()
        return document.at(document.get(document.root(), "materials"), 0)


def extension_of(
    document: JsonDocument, owner: Int, name: String
) raises -> Int:
    """Return an object's extension, or `NO_NODE`."""
    var extensions = document.get(owner, "extensions")
    if extensions == NO_NODE:
        return NO_NODE
    return document.get(extensions, name)


def uses(document: JsonDocument, name: String) raises -> Bool:
    """Return True if `extensionsUsed` names an extension."""
    var used = document.get(document.root(), "extensionsUsed")
    if used == NO_NODE:
        return False
    for at in range(document.length(used)):
        if document.string(document.at(used, at)) == name:
            return True
    return False


# --- occlusion --------------------------------------------------------------


def check_occlusion(trip: Trip, original: Texture) raises:
    """Assert an ao map on the second set came back as it was written."""
    var material = trip.material()
    assert_true(material.ao_map != NO_TEXTURE)
    assert_almost_equal(material.ao_map_intensity, 0.5, atol=TOLERANCE)
    ref ao = trip.assets.textures.get(material.ao_map)
    assert_equal(ao.channel, UV_CHANNEL_1)
    assert_equal(ao.color_space, LINEAR)
    assert_equal(ao.alpha, IGNORED)
    assert_equal(ao.width, original.width)
    ref geometry = trip.assets.geometries.get(trip.scene.meshes[0].geometry)
    assert_true(geometry.has_attribute(String(UV1)))
    ref second = geometry.attribute_view(String(UV1)).data
    assert_equal(second[0], 0.5)
    assert_equal(second[7], 0.75)


def test_an_ao_map_on_the_second_set_survives_two_trips() raises:
    var assets = Assets()
    var baked = data_image(3)
    baked.channel = UV_CHANNEL_1
    var original = Texture(copy=baked)
    var ao = assets.textures.add(baked^)
    var scene = one_mesh(
        assets,
        standard_material(
            Color(200, 200, 200), ao_map=ao, ao_map_intensity=0.5
        ),
        second_set=True,
    )
    var first = Trip(scene, assets)
    var document = first.document()
    var occlusion = document.get(first.first_material(), "occlusionTexture")
    assert_equal(document.integer(document.get(occlusion, "texCoord")), 1)
    assert_equal(document.number(document.get(occlusion, "strength")), 0.5)
    var primitive = document.at(
        document.get(
            document.at(document.get(document.root(), "meshes"), 0),
            "primitives",
        ),
        0,
    )
    assert_true(
        document.has(document.get(primitive, "attributes"), "TEXCOORD_1")
    )
    check_occlusion(first, original)
    check_occlusion(first.again(), original)


def test_an_ao_map_on_the_first_set_writes_no_set_and_no_strength() raises:
    var assets = Assets()
    var ao = assets.textures.add(data_image(5))
    var scene = one_mesh(
        assets, standard_material(Color(200, 200, 200), ao_map=ao)
    )
    var trip = Trip(scene, assets)
    var document = trip.document()
    var occlusion = document.get(trip.first_material(), "occlusionTexture")
    assert_false(document.has(occlusion, "texCoord"))
    assert_false(document.has(occlusion, "strength"))
    var material = trip.material()
    assert_equal(material.ao_map_intensity, 1)
    assert_equal(
        trip.assets.textures.get(material.ao_map).channel, UV_CHANNEL_0
    )
    # A basic material's ao map is written, as three.js writes it, and read
    # as no occlusion, as three.js reads an unlit material.
    var flat = one_mesh(
        assets, Material(Color(200, 200, 200), kind=BASIC, ao_map=ao)
    )
    var unlit = Trip(flat, assets)
    assert_true(
        unlit.document().has(unlit.first_material(), "occlusionTexture")
    )
    assert_equal(unlit.material().ao_map, NO_TEXTURE)


# --- texture transforms -----------------------------------------------------


def check_same_sampling(got: Texture, expected: Texture) raises:
    """Assert a texture read back samples where the original samples.

    An original whose `repeat.y` is not negative is written upside down,
    so the texture read back holds its rows the other way up and its
    coordinate `v` is the original's `1 - v`. Any other original is
    written as it is and read back the same.
    """
    var flipped = expected.repeat.y >= 0
    var mine = got.uv_transform()
    var theirs = expected.uv_transform()
    var corners: List[Float32] = [0, 0, 1, 0, 0.25, 0.75, 1, 1]
    for at in range(4):
        var point = Vector2(corners[at * 2], corners[at * 2 + 1])
        var want = theirs.transform_point(point)
        var have = mine.transform_point(point)
        assert_almost_equal(have.x, want.x, atol=TOLERANCE)
        assert_almost_equal(
            have.y, 1 - want.y if flipped else want.y, atol=TOLERANCE
        )
    var row = expected.width * 4
    for y in range(expected.height):
        var source = expected.height - 1 - y if flipped else y
        for x in range(row):
            assert_equal(
                got.pixels[y * row + x], expected.pixels[source * row + x]
            )


def test_a_moved_texture_is_written_with_a_transform() raises:
    var assets = Assets()
    var moved = image(1)
    moved.offset = Vector2(0.25, 0.5)
    moved.repeat = Vector2(2, 3)
    moved.rotation = Angle(0.5, RADIAN)
    moved.center = Vector2(0.5, 0.25)
    var original = Texture(copy=moved)
    var map = assets.textures.add(moved^)
    var scene = one_mesh(assets, standard_material(Color(9, 9, 9), map=map))
    var first = Trip(scene, assets)
    var document = first.document()
    assert_true(uses(document, "KHR_texture_transform"))
    var pbr = document.get(first.first_material(), "pbrMetallicRoughness")
    var transform = extension_of(
        document, document.get(pbr, "baseColorTexture"), "KHR_texture_transform"
    )
    assert_true(transform != NO_NODE)
    assert_equal(document.number(document.get(transform, "rotation")), 0.5)
    ref once = first.assets.textures.get(first.material().map)
    check_same_sampling(once, original)
    # Written again, the texture read back is written as it is, with the
    # same transform, and reads back to the same.
    var second = first.again()
    ref twice = second.assets.textures.get(second.material().map)
    var mine = twice.uv_transform()
    var theirs = once.uv_transform()
    for row in range(2):
        for column in range(3):
            assert_almost_equal(
                mine.get(row, column), theirs.get(row, column), atol=TOLERANCE
            )
    for index in range(len(once.pixels)):
        assert_equal(twice.pixels[index], once.pixels[index])


def transform_of(texture: Texture) raises -> Tuple[Bool, Bool, Bool, Bool]:
    """Write a texture as a base map and return which of `offset`,
    `rotation` and `scale` its transform names, and whether it has one."""
    var assets = Assets()
    var map = assets.textures.add(Texture(copy=texture))
    var scene = one_mesh(assets, standard_material(Color(9, 9, 9), map=map))
    var trip = Trip(scene, assets)
    var document = trip.document()
    var pbr = document.get(trip.first_material(), "pbrMetallicRoughness")
    var transform = extension_of(
        document, document.get(pbr, "baseColorTexture"), "KHR_texture_transform"
    )
    if transform == NO_NODE:
        return (False, False, False, False)
    ref back = trip.assets.textures.get(trip.material().map)
    check_same_sampling(back, texture)
    return (
        True,
        document.has(transform, "offset"),
        document.has(transform, "rotation"),
        document.has(transform, "scale"),
    )


def test_a_transform_names_only_what_moves() raises:
    var slid = image(2)
    slid.offset = Vector2(0.5, 0)
    var parts = transform_of(slid)
    assert_true(parts[0] and parts[1])
    assert_false(parts[2] or parts[3])
    var turned = image(2)
    turned.rotation = Angle(1.0, RADIAN)
    parts = transform_of(turned)
    assert_true(parts[2])
    assert_false(parts[1] or parts[3])
    var tiled = image(2)
    tiled.repeat = Vector2(1, 2)
    parts = transform_of(tiled)
    assert_true(parts[3])
    assert_false(parts[1] or parts[2])
    tiled.repeat = Vector2(2, 1)
    parts = transform_of(tiled)
    assert_true(parts[3])
    # A texture whose `v` already runs down is written as it is, and its
    # transform folds the flip in: here that is a move of one in `v`.
    var mirrored = image(2)
    mirrored.repeat = Vector2(1, -1)
    parts = transform_of(mirrored)
    assert_true(parts[0] and parts[1])
    assert_false(parts[2] or parts[3])
    mirrored.repeat = Vector2(1, -2)
    parts = transform_of(mirrored)
    assert_true(parts[3])


def test_the_placement_folds_the_flip_in() raises:
    var upright = image(4)
    var plain = GltfPlacement.of(upright)
    assert_false(plain.moves())
    var flipped = image(4)
    flipped.repeat = Vector2(1, -1)
    flipped.offset = Vector2(0, 1)
    assert_true(GltfPlacement.of(flipped) == plain)
    flipped.channel = UV_CHANNEL_1
    assert_false(GltfPlacement.of(flipped) == plain)
    assert_equal(GltfPlacement.of(flipped).set, 1)
    var turned = image(4)
    turned.rotation = Angle(0.25, RADIAN)
    assert_true(GltfPlacement.of(turned).moves())
    assert_false(GltfPlacement.of(turned) == plain)
    var tiled = image(4)
    tiled.repeat = Vector2(1, 3)
    assert_true(GltfPlacement.of(tiled).moves())
    assert_false(GltfPlacement.of(tiled) == plain)
    var slid = image(4)
    slid.offset = Vector2(0.5, 0.5)
    assert_true(GltfPlacement.of(slid).moves())
    assert_false(GltfPlacement.of(slid) == plain)


def test_two_maps_combined_must_share_one_placement() raises:
    var assets = Assets()
    var rough = assets.textures.add(data_image(1))
    var shifted = data_image(2)
    shifted.offset = Vector2(0.5, 0)
    var metal = assets.textures.add(shifted^)
    var scene = one_mesh(
        assets,
        standard_material(
            Color(9, 9, 9), roughness_map=rough, metalness_map=metal
        ),
    )
    with assert_raises(contains="share one transform"):
        _ = export_gltf(scene, assets)
    # Moved together, they are combined and the reference carries the
    # transform once.
    var both = data_image(2)
    both.offset = Vector2(0.5, 0)
    var same = data_image(3)
    same.offset = Vector2(0.5, 0)
    var first = assets.textures.add(both^)
    var second = assets.textures.add(same^)
    var together = one_mesh(
        assets,
        standard_material(
            Color(9, 9, 9), roughness_map=first, metalness_map=second
        ),
    )
    var trip = Trip(together, assets)
    var material = trip.material()
    assert_true(material.roughness_map != NO_TEXTURE)
    assert_almost_equal(
        trip.assets.textures.get(material.roughness_map).offset.x,
        0.5,
        atol=TOLERANCE,
    )


# --- emissive strength ------------------------------------------------------


def test_an_emissive_intensity_is_written_as_a_strength() raises:
    var assets = Assets()
    var scene = one_mesh(
        assets,
        standard_material(
            Color(9, 9, 9), emissive=Color(255, 128, 0), emissive_intensity=4
        ),
    )
    var first = Trip(scene, assets)
    var document = first.document()
    assert_true(uses(document, "KHR_materials_emissive_strength"))
    var strength = extension_of(
        document, first.first_material(), "KHR_materials_emissive_strength"
    )
    assert_equal(document.number(document.get(strength, "emissiveStrength")), 4)
    for trip in [first.again(), first.again().again()]:
        var material = trip.material()
        assert_equal(material.emissive_intensity, 4)
        assert_equal(material.emissive.r, 255)
        assert_equal(material.emissive.g, 128)
        assert_equal(material.emissive.b, 0)
    # At one, nothing is written.
    var plain = one_mesh(
        assets, standard_material(Color(9, 9, 9), emissive=Color(10, 0, 0))
    )
    var trip = Trip(plain, assets)
    assert_false(uses(trip.document(), "KHR_materials_emissive_strength"))


# --- physical extensions ----------------------------------------------------


def check_glass(trip: Trip) raises:
    """Assert every physical field came back as `glass` sets it."""
    var material = trip.material()
    assert_equal(material.kind, PHYSICAL)
    assert_almost_equal(material.ior, 1.25, atol=TOLERANCE)
    assert_almost_equal(material.specular_intensity, 0.5, atol=TOLERANCE)
    assert_equal(material.specular_color.r, 255)
    assert_equal(material.specular_color.g, 128)
    assert_equal(material.specular_color.b, 0)
    assert_almost_equal(material.clearcoat, 0.75, atol=TOLERANCE)
    assert_almost_equal(material.clearcoat_roughness, 0.25, atol=TOLERANCE)
    assert_almost_equal(material.transmission, 0.5, atol=TOLERANCE)
    assert_true(material.transmission_map != NO_TEXTURE)
    assert_almost_equal(material.thickness.to(METER), 0.125, atol=TOLERANCE)
    assert_true(material.thickness_map != NO_TEXTURE)
    assert_almost_equal(
        material.attenuation_distance.to(METER), 2, atol=TOLERANCE
    )
    assert_equal(material.attenuation_color.r, 64)
    assert_equal(material.attenuation_color.g, 200)
    assert_equal(material.attenuation_color.b, 255)
    assert_almost_equal(material.dispersion, 3, atol=TOLERANCE)
    ref through = trip.assets.textures.get(material.transmission_map)
    assert_equal(through.color_space, LINEAR)
    assert_equal(through.alpha, IGNORED)


def test_every_physical_extension_survives_two_trips() raises:
    var assets = Assets()
    var through = assets.textures.add(data_image(6))
    var deep = assets.textures.add(data_image(7))
    var scene = one_mesh(
        assets,
        physical_material(
            Color(9, 9, 9),
            ior=1.25,
            specular_color=Color(255, 128, 0),
            specular_intensity=0.5,
            clearcoat=0.75,
            clearcoat_roughness=0.25,
            transmission=0.5,
            transmission_map=through,
            thickness=Length(0.125, METER),
            thickness_map=deep,
            attenuation_color=Color(64, 200, 255),
            attenuation_distance=Length(2.0, METER),
            dispersion=3,
        ),
    )
    var first = Trip(scene, assets)
    var document = first.document()
    for name in [
        "KHR_materials_ior",
        "KHR_materials_specular",
        "KHR_materials_clearcoat",
        "KHR_materials_transmission",
        "KHR_materials_volume",
        "KHR_materials_dispersion",
    ]:
        assert_true(uses(document, name), name)
    check_glass(first)
    check_glass(first.again())


def physical_names(material: Material) raises -> List[String]:
    """Write a material and return the extensions its JSON names."""
    var assets = Assets()
    var scene = one_mesh(assets, material)
    var trip = Trip(scene, assets)
    var document = trip.document()
    var names = List[String]()
    var extensions = document.get(trip.first_material(), "extensions")
    if extensions == NO_NODE:
        return names^
    for name in [
        "KHR_materials_ior",
        "KHR_materials_specular",
        "KHR_materials_clearcoat",
        "KHR_materials_transmission",
        "KHR_materials_volume",
        "KHR_materials_dispersion",
    ]:
        if document.has(extensions, name):
            names.append(name)
    return names^


def test_each_extension_is_written_only_when_it_says_something() raises:
    # A physical material at every default writes none, and reads back
    # as a standard one, as in three.js.
    var assets = Assets()
    var plain = one_mesh(assets, physical_material(Color(9, 9, 9)))
    var trip = Trip(plain, assets)
    assert_false(trip.document().has(trip.first_material(), "extensions"))
    assert_equal(trip.material().kind, STANDARD)
    # Each field alone writes its own extension.
    var only = physical_names(
        physical_material(Color(9, 9, 9), specular_color=Color(255, 0, 0))
    )
    assert_equal(len(only), 1)
    assert_equal(only[0], "KHR_materials_specular")
    only = physical_names(
        physical_material(Color(9, 9, 9), clearcoat_roughness=0.5)
    )
    assert_equal(only[0], "KHR_materials_clearcoat")
    only = physical_names(physical_material(Color(9, 9, 9), transmission=0.5))
    assert_equal(len(only), 1)
    assert_equal(only[0], "KHR_materials_transmission")
    only = physical_names(
        physical_material(
            Color(9, 9, 9), attenuation_distance=Length(3.0, METER)
        )
    )
    assert_equal(len(only), 1)
    assert_equal(only[0], "KHR_materials_volume")
    only = physical_names(
        physical_material(Color(9, 9, 9), attenuation_color=Color(0, 0, 0))
    )
    assert_equal(only[0], "KHR_materials_volume")
    # A volume with no distance writes none, and reads back infinite.
    var assets_two = Assets()
    var deep = assets_two.textures.add(data_image(8))
    var through = assets_two.textures.add(data_image(9))
    var glass = one_mesh(
        assets_two,
        physical_material(
            Color(9, 9, 9), thickness_map=deep, transmission_map=through
        ),
    )
    var back = Trip(glass, assets_two)
    var document = back.document()
    var volume = extension_of(
        document, back.first_material(), "KHR_materials_volume"
    )
    assert_false(document.has(volume, "attenuationDistance"))
    assert_equal(
        back.material().attenuation_distance.to(METER), inf[DType.float32]()
    )
    assert_true(back.material().thickness_map != NO_TEXTURE)
    assert_equal(back.material().transmission, 0)
    assert_true(back.material().transmission_map != NO_TEXTURE)


def test_an_extension_is_listed_once_for_many_materials() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    var shape = assets.geometries.add(square(False))
    for ior in [Float32(1.25), Float32(1.75)]:
        scene.add_mesh(
            Mesh(
                shape,
                assets.materials.add(
                    physical_material(Color(9, 9, 9), ior=ior)
                ),
                node,
            )
        )
    var trip = Trip(scene, assets)
    var document = trip.document()
    var used = document.get(document.root(), "extensionsUsed")
    assert_equal(document.length(used), 1)
    assert_almost_equal(
        trip.assets.materials.get(trip.scene.meshes[1].material).ior,
        1.75,
        atol=TOLERANCE,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
