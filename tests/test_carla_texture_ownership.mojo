# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA decoded caches and material variants share only immutable texels."""

from core.assets import Assets
from extensions.carla.assets import AssetRegistry, TextureSet, parse_manifest
from extensions.carla.render_textures import SurfaceMaps
from materials.material import Material
from math.vector2 import Vector2
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import BILINEAR, IGNORED, REPEAT, Texture
from render.texture_store import NO_TEXTURE
from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from test_carla_assets import (
    _batch_registry,
    _preload_manifest,
    _write_batch_image,
)
from test_scratch import TestScratch, temporary_path
from units.si import Length


def _map(space: ColorSpace) raises -> Texture:
    return Texture(
        4,
        4,
        List[UInt8](length=64, fill=128),
        REPEAT,
        BILINEAR,
        space,
        True,
        IGNORED,
    )


def _set() raises -> TextureSet:
    var maps = SurfaceMaps(_map(SRGB), _map(LINEAR), _map(LINEAR), Texture())
    var set = TextureSet(maps^, _map(LINEAR), _map(LINEAR), Length(2))
    set.has_bump = True
    return set^


def test_dressing_all_five_maps_shares_payloads_but_keeps_repeat_private() raises:
    var set = _set()
    var assets = Assets()
    var first = set.dress(assets, Material(Color(1, 2, 3)), Vector2(2, 3))
    var second = set.dress(assets, Material(Color(4, 5, 6)), Vector2(7, 11))
    var first_ids = [
        first.map,
        first.roughness_map,
        first.normal_map,
        first.ao_map,
        first.bump_map,
    ]
    var second_ids = [
        second.map,
        second.roughness_map,
        second.normal_map,
        second.ao_map,
        second.bump_map,
    ]
    for i in range(5):
        assert_true(first_ids[i] != second_ids[i])
        assert_true(
            assets.textures.get(first_ids[i]).pixels.shares_with(
                assets.textures.get(second_ids[i]).pixels
            )
        )
        assert_true(assets.textures.get(first_ids[i]).repeat == Vector2(2, 3))
        assert_true(assets.textures.get(second_ids[i]).repeat == Vector2(7, 11))
    assert_true(set.maps.color.repeat == Vector2(1, 1))
    assert_true(
        assets.textures.get(first.map).pixels.shares_with(set.maps.color.pixels)
    )
    assert_true(
        assets.textures.get(first.bump_map).pixels.shares_with(set.bump.pixels)
    )


def test_source_and_dressed_writes_do_not_change_other_materials() raises:
    var set = _set()
    var assets = Assets()
    var first = set.dress(assets, Material(Color(1, 2, 3)), Vector2(2, 3))
    var second = set.dress(assets, Material(Color(4, 5, 6)), Vector2(7, 11))
    assets.textures.textures[first.map.value].pixels[0] = 9
    assert_equal(assets.textures.get(second.map).pixels[0], UInt8(128))
    assert_equal(set.maps.color.pixels[0], UInt8(128))
    set.maps.roughness.pixels[0] = 17
    assert_equal(assets.textures.get(first.roughness_map).pixels[0], UInt8(128))
    assert_equal(
        assets.textures.get(second.roughness_map).pixels[0], UInt8(128)
    )
    var pointer = (
        set.bump.pixels.mutable_values()
        .unsafe_ptr()
        .unsafe_origin_cast[MutAnyOrigin]()
    )
    var third = set.dress(assets, Material(Color(7, 8, 9)), Vector2(1, 1))
    pointer[unsafe_offset=0] = 23
    assert_equal(assets.textures.get(third.bump_map).pixels[0], UInt8(128))
    assert_equal(assets.textures.get(first.bump_map).pixels[0], UInt8(128))
    assert_equal(set.bump.pixels[0], UInt8(23))


def test_repeated_material_variants_keep_one_payload_per_source_map() raises:
    var set = _set()
    var assets = Assets()
    for i in range(128):
        var material = set.dress(
            assets,
            Material(Color(1, 2, 3)),
            Vector2(Float32(i + 1), Float32(i + 2)),
        )
        assert_true(
            assets.textures.get(material.map).pixels.shares_with(
                set.maps.color.pixels
            )
        )
        assert_true(
            assets.textures.get(material.roughness_map).pixels.shares_with(
                set.maps.roughness.pixels
            )
        )
        assert_true(
            assets.textures.get(material.normal_map).pixels.shares_with(
                set.maps.normal.pixels
            )
        )
        assert_true(
            assets.textures.get(material.ao_map).pixels.shares_with(
                set.ao.pixels
            )
        )
        assert_true(
            assets.textures.get(material.bump_map).pixels.shares_with(
                set.bump.pixels
            )
        )
    assert_equal(assets.textures.count(), 640)
    assert_equal(len(set.maps.color.pixels), 84)
    # This fixture retains 5 * 84 payload bytes, not 640 * 84 copied bytes.
    for i in range(128):
        assert_true(
            assets.textures.textures[i * 5].pixels.shares_with(
                set.maps.color.pixels
            )
        )
        assert_true(
            assets.textures.textures[i * 5 + 4].pixels.shares_with(
                set.bump.pixels
            )
        )


def test_optional_maps_do_not_allocate_unused_store_entries() raises:
    var set = _set()
    set.has_roughness = False
    set.has_normal = False
    set.has_ao = False
    set.has_bump = False
    var assets = Assets()
    var material = set.dress(assets, Material(Color(1, 2, 3)), Vector2(1, 1))
    assert_equal(assets.textures.count(), 1)
    assert_true(material.map != NO_TEXTURE)
    assert_equal(material.roughness_map, NO_TEXTURE)
    assert_equal(material.normal_map, NO_TEXTURE)
    assert_equal(material.ao_map, NO_TEXTURE)
    assert_equal(material.bump_map, NO_TEXTURE)


def test_preloaded_color_spaces_and_cache_clear_preserve_live_shares() raises:
    var registry = AssetRegistry(
        parse_manifest(_preload_manifest("gltf/checker.png")), "assets"
    )
    registry.preload(2)
    assert_equal(len(registry.decoded), 2)
    var first = registry.texture_set(0)
    var second = registry.texture_set(0)
    assert_true(first.maps.color.pixels.shares_with(second.maps.color.pixels))
    assert_equal(first.maps.color.color_space, SRGB)
    assert_equal(first.maps.roughness.color_space, LINEAR)
    assert_false(
        first.maps.color.pixels.shares_with(first.maps.roughness.pixels)
    )
    var before = first.maps.color.pixels.copy()
    var assets = Assets()
    var material = first.dress(assets, Material(Color(1, 2, 3)), Vector2(4, 5))
    registry.clear_texture_cache()
    registry.clear_texture_cache()
    assert_equal(len(registry.decoded), 0)
    assert_equal(len(registry.decoded_keys), 0)
    assert_equal(assets.textures.get(material.map).pixels.values(), before)
    assert_equal(second.maps.color.pixels.values(), before)
    first.maps.color.pixels[0] = 37
    assert_equal(second.maps.color.pixels.values(), before)
    assert_equal(assets.textures.get(material.map).pixels.values(), before)


def test_cache_clear_reloads_new_bytes_without_changing_existing_materials() raises:
    var folder = temporary_path("ownership_reload/")
    makedirs(folder, exist_ok=True)
    _write_batch_image(folder, 0)
    var registry = _batch_registry(folder, 1)
    registry.preload(1)
    var first = registry.texture_set(0)
    var assets = Assets()
    var material = first.dress(assets, Material(Color(1, 2, 3)), Vector2(1, 1))
    var image = Framebuffer(2, 2, Color(90, 40, 60))
    Path(folder + "map0.png").write_bytes(encode_png(image))
    registry.clear_texture_cache()
    registry.preload(1)
    var next = registry.texture_set(0)
    assert_equal(first.maps.color.pixels[0], UInt8(20))
    assert_equal(assets.textures.get(material.map).pixels[0], UInt8(20))
    assert_equal(next.maps.color.pixels[0], UInt8(90))
    assert_false(first.maps.color.pixels.shares_with(next.maps.color.pixels))
    var moved = assets^
    assert_equal(moved.textures.get(material.map).pixels[0], UInt8(20))


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
