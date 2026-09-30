# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's asset registry: the manifest's rules, the bindings, the cache
and what each kind of entry becomes.

The cache in these tests is `assets/`, so the entries name the repository's
own fixtures: `gltf/checker.png` as a map, `hdr_cube/px.hdr` as a panorama
and `gltf/box.gltf` as a model. The expected sizes are the fixtures' own:
the box's glTF holds several boxes, some moved and scaled, so a placement
is checked against the rules it keeps rather than a size.
"""

from core.assets import Assets
from core.object3d import NO_PARENT, Object3D
from core.scene import Scene
from extensions.carla.assets import (
    ALBEDO_ROLE,
    AO_ROLE,
    AssetEntry,
    AssetKind,
    AssetLicense,
    AssetManifest,
    AssetRegistry,
    AssetRole,
    CC0_LICENSE,
    CC_BY_LICENSE,
    DISPLACEMENT_ROLE,
    HDRI_ASSET,
    HDRI_ROLE,
    MODEL_ASSET,
    MODEL_ROLE,
    NORMAL_ROLE,
    ROUGHNESS_ROLE,
    SUPPORT_ROLE,
    TEXTURE_SET_ASSET,
    asset_kind_of,
    asset_license_of,
    asset_role_of,
    binding_kind,
    forward_yaw,
    parse_manifest,
    repeat_model,
    surface_key,
    wildcard_key,
)
from extensions.carla.mesh_factory import (
    ROAD_SURFACE,
    SurfaceKind,
    YELLOW_MARK_SURFACE,
)
from materials.material import standard_material
from math.bounds import Box3
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.cube_texture_store import SCENE_ENVIRONMENT
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE
from std.os import makedirs
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER

comptime CACHE = "assets"


def _file(role: String, path: String) -> String:
    return (
        '{"role": "'
        + role
        + '", "url": null, "sha256": "'
        + "0" * 64
        + '", "path": "'
        + path
        + '"}'
    )


def _entry(
    id: String,
    kind: String,
    files: String,
    extra: String = "",
    license: String = "CC0-1.0",
) -> String:
    return (
        '{"id": "'
        + id
        + '", "kind": "'
        + kind
        + '", "license": "'
        + license
        + '", "author": "A. Scanner", "source": "https://example.org/'
        + id
        + '", "provenance": "A test fixture.", "files": ['
        + files
        + "]"
        + extra
        + "}"
    )


def _manifest(entries: String, bindings: String = "{}") -> String:
    return (
        '{"format": 1, "entries": ['
        + entries
        + '], "bindings": '
        + bindings
        + "}"
    )


def _texture_set(id: String = "scan", tile: String = "2") -> String:
    return _entry(
        id,
        "texture_set",
        _file("albedo", "gltf/checker.png")
        + ", "
        + _file("roughness", "gltf/checker.png")
        + ", "
        + _file("normal", "gltf/checker.png")
        + ", "
        + _file("ao", "gltf/checker.png"),
        ', "tile_meters": ' + tile,
    )


def _fixtures() -> String:
    """A manifest of one entry of each kind, bound, and a few more."""
    var bare = _entry(
        "bare",
        "texture_set",
        _file("albedo", "gltf/checker.png")
        + ", "
        + _file("displacement", "gltf/checker.png"),
        ', "tile_meters": 4',
    )
    var sky = _entry("sky", "hdri", _file("hdri", "hdr_cube/px.hdr"))
    var box = _entry(
        "box",
        "model",
        _file("model", "gltf/box.gltf") + ", " + _file("support", "gltf/box.bin"),
        ', "forward": "+z", "title": "Box"',
        "CC-BY-4.0",
    )
    var gone = _entry(
        "gone",
        "model",
        _file("model", "gltf/missing.gltf"),
        ', "forward": "+x"',
    )
    var rigged = _entry(
        "rigged",
        "model",
        _file("model", "gltf/three_export.gltf"),
        ', "forward": "-x"',
    )
    return _manifest(
        _texture_set()
        + ", "
        + bare
        + ", "
        + sky
        + ", "
        + box
        + ", "
        + gone
        + ", "
        + rigged,
        '{"surface.road": "scan", "surface.curb": "bare", "sky.clear":'
        ' "sky", "vehicle.audi.a2": "box", "vehicle.gone": "gone",'
        ' "vehicle.rigged": "rigged",'
        ' "vehicle.mini.cooper": null, "vehicle.*": null}',
    )


def _registry() raises -> AssetRegistry:
    return AssetRegistry(parse_manifest(_fixtures()), CACHE)


# The kinds, the roles and the licenses.


def test_kinds_roles_and_licenses_are_named() raises:
    assert_true(asset_kind_of("texture_set") == TEXTURE_SET_ASSET)
    assert_true(asset_kind_of("hdri") == HDRI_ASSET)
    assert_true(asset_kind_of("model") == MODEL_ASSET)
    with assert_raises(contains="texture_set, hdri or model"):
        _ = asset_kind_of("sound")
    assert_true(asset_role_of("albedo") == ALBEDO_ROLE)
    assert_true(asset_role_of("support") == SUPPORT_ROLE)
    with assert_raises(contains="role"):
        _ = asset_role_of("archive")
    assert_true(asset_license_of("CC0-1.0") == CC0_LICENSE)
    assert_true(asset_license_of("CC-BY-4.0") == CC_BY_LICENSE)
    with assert_raises(contains="CC0-1.0 or CC-BY-4.0"):
        _ = asset_license_of("GPL-3.0")
    assert_true(CC_BY_LICENSE.needs_credit())
    assert_false(CC0_LICENSE.needs_credit())


def test_each_type_knows_its_values() raises:
    assert_true(MODEL_ASSET.is_valid())
    assert_false(AssetKind(3).is_valid())
    assert_false(AssetKind(-1).is_valid())
    assert_true(SUPPORT_ROLE.is_valid())
    assert_false(AssetRole(8).is_valid())
    assert_false(AssetRole(-1).is_valid())
    assert_true(CC_BY_LICENSE.is_valid())
    assert_false(AssetLicense(2).is_valid())
    assert_equal(String(HDRI_ASSET), "AssetKind(1)")
    assert_equal(String(NORMAL_ROLE), "AssetRole(1)")
    assert_equal(String(CC_BY_LICENSE), "AssetLicense(1)")


def test_a_forward_axis_turns_to_plus_x() raises:
    assert_equal(forward_yaw("+x").to(DEGREE), 0)
    assert_equal(forward_yaw("-x").to(DEGREE), 180)
    assert_equal(forward_yaw("+z").to(DEGREE), 90)
    assert_equal(forward_yaw("-z").to(DEGREE), -90)
    with assert_raises(contains="+x, -x, +z or -z"):
        _ = forward_yaw("+y")


# The manifest.


def test_a_manifest_reads_each_kind() raises:
    var manifest = parse_manifest(_fixtures())
    assert_equal(len(manifest.entries), 6)
    ref scan = manifest.entries[0]
    assert_equal(scan.title, "scan")
    assert_equal(scan.author, "A. Scanner")
    assert_equal(scan.source, "https://example.org/scan")
    assert_equal(scan.provenance, "A test fixture.")
    assert_equal(scan.tile.to(METER), 2)
    assert_equal(scan.files[0].sha256, "0" * 64)
    assert_equal(scan.file(AO_ROLE).value(), "gltf/checker.png")
    assert_false(Bool(scan.file(DISPLACEMENT_ROLE)))
    assert_equal(String(scan), "AssetEntry(scan, AssetKind(0))")
    ref box = manifest.entries[3]
    assert_equal(box.title, "Box")
    assert_equal(box.yaw.to(DEGREE), 90)
    assert_true(box.kind == MODEL_ASSET)
    assert_equal(manifest.entries[2].file(HDRI_ROLE).value(), "hdr_cube/px.hdr")


def test_an_archive_contributes_its_members() raises:
    var archive = (
        '{"role": "archive", "url": null, "sha256": "'
        + "1" * 64
        + '", "path": "scan.zip", "extract": ['
        + _file("albedo", "scan/color.jpg")
        + ", "
        + _file("normal", "scan/normal.jpg")
        + "]}"
    )
    var manifest = parse_manifest(
        _manifest(_entry("zip", "texture_set", archive, ', "tile_meters": 3'))
    )
    ref entry = manifest.entries[0]
    assert_equal(len(entry.files), 2)
    assert_equal(entry.file(NORMAL_ROLE).value(), "scan/normal.jpg")
    # A null sum reads as no sum.
    var unpinned = parse_manifest(
        _manifest(
            _entry(
                "loose",
                "hdri",
                '{"role": "hdri", "url": null, "sha256": null, "path": "a.hdr"}',
            )
        )
    )
    assert_equal(unpinned.entries[0].files[0].sha256, "")


def test_a_manifest_without_bindings_binds_nothing() raises:
    var manifest = parse_manifest(
        '{"format": 1, "entries": [' + _texture_set() + "]}"
    )
    assert_equal(len(manifest.keys), 0)
    assert_false(manifest.is_bound("surface.road"))


def _refused(text: String, reason: String) raises:
    with assert_raises(contains=reason):
        _ = parse_manifest(text)


def test_each_broken_rule_is_refused() raises:
    _refused("[]", "JSON object")
    _refused('{"entries": []}', "format 1")
    _refused('{"format": "1", "entries": []}', "format 1")
    _refused('{"format": 2, "entries": []}', "format 1")
    _refused('{"format": 1}', "list of entries")
    _refused('{"format": 1, "entries": [7]}', "must be an object")
    _refused(
        _manifest(
            '{"id": "x", "kind": "hdri", "license": "CC0-1.0", "files": []}'
        ),
        "the string author",
    )
    _refused(
        _manifest(_entry("x", "hdri", "", "").replace('"files": []', '"files": 1')),
        "list of files",
    )
    # A role that does not fit the kind, for each kind.
    _refused(
        _manifest(_entry("x", "texture_set", _file("hdri", "a.hdr"))),
        "does not fit",
    )
    _refused(
        _manifest(_entry("x", "hdri", _file("albedo", "a.jpg"))),
        "does not fit",
    )
    _refused(
        _manifest(_entry("x", "model", _file("normal", "a.jpg"))),
        "does not fit",
    )
    # A path out of the cache.
    for path in ["", "/etc/passwd", "../up.jpg"]:
        _refused(
            _manifest(_entry("x", "hdri", _file("hdri", path))),
            "stay inside the cache",
        )
    _refused(
        _manifest(
            _entry(
                "x",
                "hdri",
                '{"role": "archive", "url": null, "path": "a.zip"}',
            )
        ),
        "list what it extracts",
    )
    # A texture set's tile and albedo.
    _refused(
        _manifest(_entry("x", "texture_set", _file("albedo", "a.jpg"))),
        "needs its tile_meters",
    )
    _refused(
        _manifest(
            _entry(
                "x", "texture_set", _file("albedo", "a.jpg"), ', "tile_meters": "2"'
            )
        ),
        "needs its tile_meters",
    )
    _refused(_manifest(_texture_set("x", "0")), "must be positive")
    _refused(
        _manifest(
            _entry(
                "x", "texture_set", _file("normal", "a.jpg"), ', "tile_meters": 2'
            )
        ),
        "needs an albedo map",
    )
    # A model's forward axis and file, and an HDRI's panorama.
    _refused(
        _manifest(_entry("x", "model", _file("model", "a.gltf"))),
        "the string forward",
    )
    _refused(
        _manifest(
            _entry("x", "model", _file("support", "a.bin"), ', "forward": "+x"')
        ),
        "needs its model file",
    )
    _refused(
        _manifest(_entry("x", "hdri", _file("support", "a.bin"))),
        "does not fit",
    )
    _refused(_manifest(_entry("x", "hdri", "")), "needs its panorama")
    # Two entries with one id, and bindings that break a rule.
    _refused(
        _manifest(_texture_set() + ", " + _texture_set()), "share the id scan"
    )
    _refused(_manifest(_texture_set(), "[]"), "must be an object")
    _refused(
        _manifest(_texture_set(), '{"surface.road": "nothing"}'),
        "names no entry",
    )
    _refused(
        _manifest(_texture_set(), '{"sky.clear": "scan"}'),
        "names the wrong kind",
    )


def test_bindings_and_credits() raises:
    var manifest = parse_manifest(_fixtures())
    assert_equal(manifest.find("sky").value(), 2)
    assert_false(Bool(manifest.find("nothing")))
    assert_equal(manifest.binding("surface.road").value(), "scan")
    assert_false(Bool(manifest.binding("vehicle.mini.cooper")))
    assert_false(Bool(manifest.binding("surface.sidewalk")))
    assert_true(manifest.is_bound("vehicle.mini.cooper"))
    assert_false(manifest.is_bound("vehicle.tesla.model3"))
    var credits = manifest.credits()
    assert_equal(len(credits), 1)
    assert_equal(
        credits[0], '"Box" by A. Scanner, https://example.org/box, CC BY 4.0'
    )
    assert_equal(len(AssetManifest().credits()), 0)


def test_binding_keys() raises:
    assert_true(binding_kind("surface.road") == TEXTURE_SET_ASSET)
    assert_true(binding_kind("ground.grass") == TEXTURE_SET_ASSET)
    assert_true(binding_kind("facade.brick") == TEXTURE_SET_ASSET)
    assert_true(binding_kind("sky.overcast") == HDRI_ASSET)
    assert_true(binding_kind("tree") == MODEL_ASSET)
    assert_equal(surface_key(ROAD_SURFACE), "surface.road")
    assert_equal(surface_key(YELLOW_MARK_SURFACE), "surface.yellow_mark")
    with assert_raises(contains="one of the seven"):
        _ = surface_key(SurfaceKind(7))
    assert_equal(wildcard_key("vehicle.tesla.model3"), "vehicle.*")
    assert_equal(wildcard_key("tree"), "tree.*")


# The registry.


def test_an_empty_registry_falls_back_everywhere() raises:
    var registry = AssetRegistry()
    assert_false(Bool(registry.cached_entry("surface.road")))
    assert_equal(registry.model_key("vehicle.audi.a2"), "vehicle.*")


def test_the_repository_manifest_opens() raises:
    var registry = AssetRegistry.open(
        "assets/carla/manifest.json", ".cache/no-such-cache"
    )
    assert_equal(registry.cache, ".cache/no-such-cache/")
    assert_true(registry.manifest.is_bound("vehicle.*"))
    # Nothing is cached, so every key keeps its procedural asset.
    assert_false(Bool(registry.cached_entry("surface.road")))
    assert_false(Bool(registry.cached_entry("vehicle.audi.a2")))


def test_the_cache_decides_what_is_used() raises:
    var registry = _registry()
    assert_equal(registry.path("gltf/box.gltf"), "assets/gltf/box.gltf")
    assert_equal(registry.cached_entry("surface.road").value(), 0)
    assert_equal(registry.cached_entry("vehicle.audi.a2").value(), 3)
    # Bound, but a file is not in the cache.
    assert_false(Bool(registry.cached_entry("vehicle.gone")))
    assert_false(registry.is_cached(registry.manifest.entries[4]))
    # Bound to null, and not bound at all.
    assert_false(Bool(registry.cached_entry("vehicle.mini.cooper")))
    assert_false(Bool(registry.cached_entry("surface.sidewalk")))
    assert_equal(registry.model_key("vehicle.mini.cooper"), "vehicle.mini.cooper")
    assert_equal(registry.model_key("vehicle.tesla.model3"), "vehicle.*")


def test_a_texture_set_reads_its_maps() raises:
    var registry = _registry()
    var set = registry.texture_set(0)
    assert_true(set.has_normal and set.has_roughness and set.has_ao)
    assert_false(set.has_bump)
    assert_equal(set.maps.color.width, 2)
    var repeat = set.per_meter()
    assert_equal(repeat.x, 0.5)
    assert_equal(repeat.y, 0.5)
    var assets = Assets()
    var material = set.dress(
        assets, standard_material(Color(255, 255, 255)), repeat
    )
    assert_true(material.map != NO_TEXTURE)
    assert_true(material.roughness_map != NO_TEXTURE)
    assert_true(material.normal_map != NO_TEXTURE)
    assert_true(material.ao_map != NO_TEXTURE)
    assert_true(material.bump_map == NO_TEXTURE)
    assert_equal(assets.textures.get(material.map).repeat.x, 0.5)


def test_a_bare_texture_set_is_flat_and_bumped() raises:
    var registry = _registry()
    var set = registry.texture_set(1)
    assert_false(set.has_normal or set.has_roughness or set.has_ao)
    # With no normal map, the displacement is the bump map.
    assert_true(set.has_bump)
    assert_equal(set.maps.roughness.width, 1)
    assert_equal(set.ao.width, 1)
    var assets = Assets()
    var material = set.dress(
        assets, standard_material(Color(255, 255, 255)), Vector2(1, 1)
    )
    assert_true(material.map != NO_TEXTURE)
    assert_true(material.roughness_map == NO_TEXTURE)
    assert_true(material.normal_map == NO_TEXTURE)
    assert_true(material.ao_map == NO_TEXTURE)
    assert_true(material.bump_map != NO_TEXTURE)
    with assert_raises(contains="is not a texture set"):
        _ = registry.texture_set(2)


def test_an_hdri_reads_its_panorama() raises:
    var registry = _registry()
    var sky = registry.hdri(2)
    assert_true(sky.width > 0)
    assert_true(sky.height > 0)
    with assert_raises(contains="is not an HDRI"):
        _ = registry.hdri(0)


def _bounds(
    scene: Scene, assets: Assets, first: Int, count: Int
) raises -> Box3:
    var bounds = Box3.empty()
    for m in range(first, first + count):
        var box = assets.geometries.get(scene.meshes[m].geometry).bounding_box()
        box.apply_matrix4(scene.world_matrix(scene.meshes[m].node))
        bounds.union(box)
    return bounds


def test_a_model_is_fitted_and_stood_on_its_holder() raises:
    var registry = _registry()
    var scene = Scene()
    var assets = Assets()
    var holder = Object3D()
    holder.set_position(10, 0, 0)
    var parent = scene.add(holder^)
    scene.update()
    var fit = Vector3(2, 4, 3)
    var placed = registry.place_model(3, scene, assets, parent, fit)
    assert_true(placed.mesh_count > 0)
    assert_true(scene.meshes[placed.first_mesh].cast_shadow)
    assert_true(scene.meshes[placed.first_mesh].receive_shadow)
    var material = scene.meshes[placed.first_mesh].material
    assert_true(assets.materials.get(material).env_map == SCENE_ENVIRONMENT)
    var box = _bounds(scene, assets, placed.first_mesh, placed.mesh_count)
    # Centered on the holder in x and z, and standing on it in y.
    assert_almost_equal(box.min.y, 0, atol=1e-3)
    assert_almost_equal((box.min.x + box.max.x) / 2, 10, atol=1e-3)
    assert_almost_equal((box.min.z + box.max.z) / 2, 0, atol=1e-3)
    # Inside the box to fit, and touching it on one axis.
    var size = box.size()
    assert_true(size.x <= fit.x + 1e-3)
    assert_true(size.y <= fit.y + 1e-3)
    assert_true(size.z <= fit.z + 1e-3)
    var slack = min(fit.x - size.x, min(fit.y - size.y, fit.z - size.z))
    assert_almost_equal(slack, 0, atol=1e-3)
    # A copy under another holder shares the geometry, in its own place.
    var geometry = scene.meshes[placed.first_mesh].geometry
    var other = Object3D()
    other.set_position(-10, 0, 0)
    var second = scene.add(other^)
    scene.update()
    var copy = repeat_model(placed, scene, second)
    assert_equal(copy.mesh_count, placed.mesh_count)
    assert_equal(copy.scale, placed.scale)
    assert_true(scene.meshes[copy.first_mesh].geometry == geometry)
    var moved = _bounds(scene, assets, copy.first_mesh, copy.mesh_count)
    assert_almost_equal((moved.min.x + moved.max.x) / 2, -10, atol=1e-3)
    assert_almost_equal(moved.min.y, 0, atol=1e-3)
    assert_almost_equal(moved.size().y, size.y, atol=1e-3)


def test_a_model_the_town_cannot_use_is_refused() raises:
    var registry = _registry()
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    scene.update()
    with assert_raises(contains="is not a model"):
        _ = registry.place_model(0, scene, assets, parent, Vector3(1, 1, 1))
    with assert_raises(contains="only plain meshes"):
        _ = registry.place_model(5, scene, assets, parent, Vector3(1, 1, 1))
    # A glTF with a node and no mesh.
    var folder = "/tmp/threemojo_carla_assets/"
    makedirs(folder, exist_ok=True)
    Path(folder + "bare.gltf").write_text(
        '{"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes":'
        ' [0]}], "nodes": [{"name": "marker"}]}'
    )
    var bare = AssetRegistry(
        parse_manifest(
            _manifest(
                _entry(
                    "bare",
                    "model",
                    _file("model", "bare.gltf"),
                    ', "forward": "+x"',
                )
            )
        ),
        folder,
    )
    with assert_raises(contains="has no mesh"):
        _ = bare.place_model(0, scene, assets, parent, Vector3(1, 1, 1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
