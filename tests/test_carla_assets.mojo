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
    TOWN_ASSET,
    asset_kind_of,
    asset_license_of,
    asset_role_of,
    binding_kind,
    forward_yaw,
    parse_manifest,
    repeat_model,
    surface_key,
    town_tile,
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
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from render.texture_store import NO_TEXTURE
from std.os import makedirs
from test_scratch import TestScratch, temporary_path
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, Length

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
        _file("model", "gltf/box.gltf")
        + ", "
        + _file("support", "gltf/box.bin"),
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
        (
            '{"surface.road": "scan", "surface.curb": "bare", "sky.clear":'
            ' "sky", "vehicle.audi.a2": "box", "vehicle.gone": "gone",'
            ' "vehicle.rigged": "rigged",'
            ' "vehicle.mini.cooper": null, "vehicle.*": null}'
        ),
    )


def _registry() raises -> AssetRegistry:
    return AssetRegistry(parse_manifest(_fixtures()), CACHE)


# The kinds, the roles and the licenses.


def test_kinds_roles_and_licenses_are_named() raises:
    assert_true(asset_kind_of("texture_set") == TEXTURE_SET_ASSET)
    assert_true(asset_kind_of("hdri") == HDRI_ASSET)
    assert_true(asset_kind_of("model") == MODEL_ASSET)
    assert_true(asset_kind_of("town") == TOWN_ASSET)
    with assert_raises(contains="texture_set, hdri, model or town"):
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
    assert_true(TOWN_ASSET.is_valid())
    assert_false(AssetKind(4).is_valid())
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
                (
                    '{"role": "hdri", "url": null, "sha256": null, "path":'
                    ' "a.hdr"}'
                ),
            )
        )
    )
    assert_equal(unpinned.entries[0].files[0].sha256, "")


def test_tile_sizes_are_positive_and_finite_after_float32_conversion() raises:
    for value in ["1e100", "3.5e38", "1e-100", "0", "-1"]:
        _refused(_manifest(_texture_set("scan", value)), "positive and finite")
    for value in ["1", "0.25", "1e-40", "3.4028234663852886e38"]:
        var manifest = parse_manifest(_manifest(_texture_set("scan", value)))
        assert_true(manifest.entries[0].tile.to(METER) > 0)


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
        _manifest(
            _entry("x", "hdri", "", "").replace('"files": []', '"files": 1')
        ),
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
                "x",
                "texture_set",
                _file("albedo", "a.jpg"),
                ', "tile_meters": "2"',
            )
        ),
        "needs its tile_meters",
    )
    _refused(_manifest(_texture_set("x", "0")), "must be positive")
    _refused(
        _manifest(
            _entry(
                "x",
                "texture_set",
                _file("normal", "a.jpg"),
                ', "tile_meters": 2',
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
    _refused(
        _manifest(_entry("x", "town", _file("support", "a.bin"))),
        "town entry needs its model file",
    )
    # Members of the wrong type: an id, a title, the files, an archive's
    # members and the entries.
    var common = (
        '"kind": "model", "license": "CC0-1.0", "author": "A", "source":'
        ' "s", "provenance": "p"'
    )
    _refused(
        _manifest('{"id": 5, ' + common + ', "files": []}'),
        "needs the string id",
    )
    _refused(
        _manifest(
            _entry(
                "x",
                "texture_set",
                _file("albedo", "a.jpg"),
                ', "tile_meters": 2, "title": 5',
            )
        ),
        "title must be a string",
    )
    _refused(_manifest('{"id": "x", ' + common + "}"), "needs a list of files")
    _refused(
        _manifest(
            _entry(
                "x",
                "texture_set",
                (
                    '{"role": "archive", "url": null, "path": "a.zip",'
                    ' "extract": 5}'
                ),
                ', "tile_meters": 2',
            )
        ),
        "must list what it extracts",
    )
    _refused('{"format": 1, "entries": 5}', "needs a list of entries")
    # An archive that extracts nothing adds no file.
    var empty = parse_manifest(
        _manifest(
            _entry(
                "x",
                "texture_set",
                _file("albedo", "a.jpg")
                + ', {"role": "archive", "url": null, "path": "a.zip",'
                ' "extract": []}',
                ', "tile_meters": 2',
            )
        )
    )
    assert_equal(len(empty.entries[0].files), 1)
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
    assert_true(binding_kind("town.Town02") == TOWN_ASSET)
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
    assert_equal(
        registry.model_key("vehicle.mini.cooper"), "vehicle.mini.cooper"
    )
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
    var folder = temporary_path("threemojo_carla_assets/")
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


# A glTF of one triangle drawn six times, each with a material that tags
# it: paint, head lamps, tail lamps, a tag the town does not use, a tag
# that is not a string, and none.
comptime TAGGED_GLTF = (
    '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],'
    '"nodes":[{"mesh":0}],"buffers":[{"byteLength":36,"uri":'
    '"data:application/octet-stream;base64,'
    'AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"}],'
    '"bufferViews":[{"buffer":0,"byteLength":36}],"accessors":'
    '[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3",'
    '"min":[0,0,0],"max":[1,1,0]}],"materials":[{"extras":{"carla":'
    '"paint"}},{"extras":{"carla":"heads"}},{"extras":{"carla":"tails"}},'
    '{"extras":{"carla":"other"}},{"extras":{"carla":7}},{}],"meshes":'
    '[{"primitives":[{"attributes":{"POSITION":0},"material":0},'
    '{"attributes":{"POSITION":0},"material":1},{"attributes":'
    '{"POSITION":0},"material":2},{"attributes":{"POSITION":0},'
    '"material":3},{"attributes":{"POSITION":0},"material":4},'
    '{"attributes":{"POSITION":0},"material":5}]}]}'
)


def test_a_model_reports_its_tagged_materials() raises:
    var folder = temporary_path("threemojo_carla_assets/")
    makedirs(folder, exist_ok=True)
    Path(folder + "tagged.gltf").write_text(TAGGED_GLTF)
    var registry = AssetRegistry(
        parse_manifest(
            _manifest(
                _entry(
                    "car",
                    "model",
                    _file("model", "tagged.gltf"),
                    ', "forward": "+x"',
                )
            )
        ),
        folder,
    )
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    scene.update()
    var placed = registry.place_model(
        0, scene, assets, parent, Vector3(4, 2, 2)
    )
    assert_equal(placed.mesh_count, 6)
    assert_equal(len(placed.paint), 1)
    assert_equal(len(placed.heads), 1)
    assert_equal(len(placed.tails), 1)
    assert_true(scene.meshes[placed.first_mesh].material == placed.paint[0])
    assert_true(scene.meshes[placed.first_mesh + 1].material == placed.heads[0])
    assert_true(scene.meshes[placed.first_mesh + 2].material == placed.tails[0])
    # A copy keeps the tags.
    var second = scene.add(Object3D())
    scene.update()
    var copy = repeat_model(placed, scene, second)
    assert_true(copy.paint[0] == placed.paint[0])
    assert_equal(len(copy.heads), 1)
    assert_equal(len(copy.tails), 1)


def _preload_manifest(albedo: String) -> String:
    """Two texture sets that share their maps, one bound to null, one
    whose file is not in the cache, and an HDRI."""
    var gone = _entry(
        "gone",
        "texture_set",
        _file("albedo", "gltf/none.png"),
        ', "tile_meters": 1',
    )
    var shared = _entry(
        "shared",
        "texture_set",
        _file("albedo", albedo)
        + ", "
        + _file("normal", "gltf/checker.png")
        + ", "
        + _file("displacement", "gltf/checker.png"),
        ', "tile_meters": 2',
    )
    var sky = _entry("sky", "hdri", _file("hdri", "hdr_cube/px.hdr"))
    return _manifest(
        _texture_set() + ", " + shared + ", " + gone + ", " + sky,
        (
            '{"surface.road": "scan", "surface.curb": "shared", "surface.wall":'
            ' "shared", "surface.sidewalk": "gone", "ground.grass": null,'
            ' "sky.clear": "sky"}'
        ),
    )


def test_preload_decodes_each_map_once() raises:
    for workers in [-1, 0, 1, 2, 4]:
        var registry = AssetRegistry(
            parse_manifest(_preload_manifest("gltf/checker.png")), CACHE
        )
        registry.preload(workers)
        # One checker in sRGB for the albedo and one in linear light for
        # every other map; the displacement is not read beside a normal
        # map, and the missing set and the sky are not texture sets read.
        assert_equal(len(registry.decoded), 2)
        assert_true(registry.decoded_keys[0].endswith("checker.png|srgb"))
        # A second preload finds them all decoded.
        registry.preload(workers)
        assert_equal(len(registry.decoded), 2)
        var set = registry.texture_set(0)
        assert_equal(set.maps.color.width, 2)


def test_preload_refuses_a_file_that_is_not_an_image() raises:
    for workers in [-1, 0, 1, 2, 4]:
        var registry = AssetRegistry(
            parse_manifest(_preload_manifest("gltf/box.gltf")), CACHE
        )
        with assert_raises():
            registry.preload(workers)


def _batch_registry(folder: String, count: Int) raises -> AssetRegistry:
    var entries = String("")
    var bindings = String("{")
    for index in range(count):
        var name = "map" + String(index)
        if index > 0:
            entries += ","
            bindings += ","
        entries += _entry(
            name,
            "texture_set",
            _file("albedo", name + ".png"),
            ', "tile_meters": 1',
        )
        bindings += '"surface.' + name + '":"' + name + '"'
    bindings += "}"
    return AssetRegistry(parse_manifest(_manifest(entries, bindings)), folder)


def _write_batch_image(folder: String, index: Int) raises:
    var image = Framebuffer(2, 2, Color(UInt8(20 + index), 40, 60))
    Path(folder + "map" + String(index) + ".png").write_bytes(encode_png(image))


def test_preload_preserves_order_across_multiple_batches() raises:
    var folder = temporary_path("threemojo_carla_preload_batches/")
    makedirs(folder, exist_ok=True)
    for index in range(5):
        _write_batch_image(folder, index)
    for workers in [1, 2, 3, 8]:
        var registry = _batch_registry(folder, 5)
        registry.preload(workers)
        assert_equal(len(registry.decoded), 5)
        for index in range(5):
            assert_equal(
                registry.decoded_keys[index],
                folder + "map" + String(index) + ".png|srgb",
            )
            assert_equal(registry.decoded[index].pixels[0], UInt8(20 + index))
            assert_equal(registry.decoded[index].levels, 2)
        registry.preload(workers)
        assert_equal(len(registry.decoded), 5)


def test_preload_failure_does_not_publish_a_partial_batch_or_cache() raises:
    var folder = temporary_path("threemojo_carla_preload_failure/")
    makedirs(folder, exist_ok=True)
    for index in range(5):
        _write_batch_image(folder, index)
    for workers in [1, 2, 3]:
        # The last image fails after at least one complete batch.
        Path(folder + "map4.png").write_text("invalid image")
        var registry = _batch_registry(folder, 5)
        with assert_raises():
            registry.preload(workers)
        assert_equal(len(registry.decoded), 0)
        assert_equal(len(registry.decoded_keys), 0)
        _write_batch_image(folder, 4)
        registry.preload(workers)
        assert_equal(len(registry.decoded), 5)
        assert_equal(registry.decoded[4].pixels[0], UInt8(24))


def test_preload_queue_preserves_existing_entries_on_failure_and_retry() raises:
    var folder = temporary_path("threemojo_carla_queue_retry/")
    makedirs(folder, exist_ok=True)
    for workers in [1, 2, 8]:
        for index in range(5):
            _write_batch_image(folder, index)
        var registry = _batch_registry(folder, 1)
        registry.preload(workers)
        var original = registry.decoded[0].pixels.copy()
        var address = (
            registry.decoded[0]
            .pixels.unsafe_ptr()
            .unsafe_origin_cast[ImmutAnyOrigin]()
        )
        # Add new bindings after one entry is already cached. Two distinct
        # later failures must not publish even the new successful image.
        var expanded = _batch_registry(folder, 5)
        registry.manifest = expanded.manifest.copy()
        Path(folder + "map2.png").write_text("invalid second image")
        Path(folder + "map4.png").write_text("invalid fourth image")
        with assert_raises():
            registry.preload(workers)
        assert_equal(len(registry.decoded), 1)
        assert_equal(len(registry.decoded_keys), 1)
        assert_equal(registry.decoded[0].pixels.values(), original)
        assert_equal(
            registry.decoded[0]
            .pixels.unsafe_ptr()
            .unsafe_origin_cast[ImmutAnyOrigin](),
            address,
        )
        _write_batch_image(folder, 2)
        _write_batch_image(folder, 4)
        registry.preload(workers)
        assert_equal(len(registry.decoded), 5)
        for index in range(5):
            assert_equal(
                registry.decoded_keys[index],
                folder + "map" + String(index) + ".png|srgb",
            )
            assert_equal(registry.decoded[index].pixels[0], UInt8(20 + index))
        registry.preload(workers)
        assert_equal(len(registry.decoded), 5)


def test_preload_queue_matches_serial_pixels_and_complete_mip_chains() raises:
    var folder = temporary_path("threemojo_carla_queue_skew/")
    makedirs(folder, exist_ok=True)
    var sizes: List[Int] = [128, 2, 16, 4, 64]
    for index in range(len(sizes)):
        var image = Framebuffer(
            sizes[index], sizes[index], Color(UInt8(20 + index), 40, 60)
        )
        Path(folder + "map" + String(index) + ".png").write_bytes(
            encode_png(image)
        )
    var serial = _batch_registry(folder, 5)
    serial.preload(1)
    for workers in [2, 8]:
        var parallel = _batch_registry(folder, 5)
        parallel.preload(workers)
        assert_equal(parallel.decoded_keys, serial.decoded_keys)
        for index in range(5):
            ref a = serial.decoded[index]
            ref b = parallel.decoded[index]
            assert_equal(a.width, b.width)
            assert_equal(a.height, b.height)
            assert_equal(a.pixels, b.pixels)
            assert_equal(a.levels, b.levels)
            assert_equal(a.offsets, b.offsets)
            assert_true(a.color_space == b.color_space)
            assert_true(a.alpha == b.alpha)
            assert_true(a.min_filter == b.min_filter)
            assert_true(a.wrap_s == b.wrap_s)
            assert_true(a.wrap_t == b.wrap_t)


def test_preload_preserves_serial_and_parallel_error_text() raises:
    var folder = temporary_path("threemojo_carla_queue_errors/")
    makedirs(folder, exist_ok=True)
    Path(folder + "map0.png").write_text("invalid")
    var registry = _batch_registry(folder, 1)
    var raw = String("")
    try:
        _ = registry.texture_set(0)
    except e:
        raw = String(e)
    assert_true(raw.byte_length() > 0)
    for workers in [1, 2, 8]:
        var message = String("")
        try:
            registry.preload(workers)
        except e:
            message = String(e)
        assert_equal(
            message, raw if workers == 1 else folder + "map0.png: " + raw
        )
        assert_equal(len(registry.decoded), 0)


def test_preload_queue_matches_both_color_spaces_and_mips() raises:
    var serial = AssetRegistry(
        parse_manifest(_preload_manifest("gltf/checker.png")), CACHE
    )
    serial.preload(1)
    for workers in [2, 8]:
        var parallel = AssetRegistry(
            parse_manifest(_preload_manifest("gltf/checker.png")), CACHE
        )
        parallel.preload(workers)
        assert_equal(len(parallel.decoded), 2)
        assert_equal(parallel.decoded_keys, serial.decoded_keys)
        for index in range(2):
            ref a = serial.decoded[index]
            ref b = parallel.decoded[index]
            assert_equal(a.pixels, b.pixels)
            assert_equal(a.offsets, b.offsets)
            assert_equal(a.levels, b.levels)
            assert_true(a.color_space == b.color_space)
            assert_true(a.alpha == b.alpha)


# A town package of one triangle drawn seven times, as `build_towns.py`
# names and tags its nodes: two levels of a building's tile, a road's
# paint and a road that share a material, a traffic light whose glass is
# a lamp's, a node of another name with no tags, and a kind that is not a
# string at a level past the far one. Its scene lists three lamp heads.
comptime TOWN_GLTF = (
    '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":'
    '[0,1,2,3,4,5,6,7],"extras":{"carla_lamps":[0,5,0,10,5,0,100,5,0]}}],'
    '"nodes":['
    '{"name":"building_0_0_lod0","mesh":0,"extras":{"carla_kind":"building",'
    '"carla_lod":0}},'
    '{"name":"building_0_0_lod1","mesh":1,"extras":{"carla_kind":"building",'
    '"carla_lod":1}},'
    '{"name":"road_line_1_0_lod0","mesh":2,"extras":{"carla_kind":'
    '"road_line","carla_lod":0}},'
    '{"name":"road_1_0_lod1","mesh":3,"extras":{"carla_kind":"road",'
    '"carla_lod":1}},'
    '{"name":"traffic_light_1_0_lod0","mesh":4,"extras":{"carla_kind":'
    '"traffic_light","carla_lod":0}},'
    '{"name":"odd","mesh":5},'
    '{"name":"stone_0_0_lod9","mesh":6,"extras":{"carla_kind":7}},'
    '{"name":"traffic_sign_1_0_lod0","mesh":7,"extras":{"carla_kind":'
    '"traffic_sign","carla_lod":0}}],'
    '"buffers":[{"byteLength":36,"uri":'
    '"data:application/octet-stream;base64,'
    'AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"}],'
    '"bufferViews":[{"buffer":0,"byteLength":36}],"accessors":'
    '[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3",'
    '"min":[0,0,0],"max":[1,1,0]}],"materials":[{},'
    '{"pbrMetallicRoughness":{"roughnessFactor":0.5}},'
    '{"extras":{"carla":"lamp"}}],"meshes":['
    '{"primitives":[{"attributes":{"POSITION":0},"material":0}]},'
    '{"primitives":[{"attributes":{"POSITION":0},"material":0}]},'
    '{"primitives":[{"attributes":{"POSITION":0},"material":1}]},'
    '{"primitives":[{"attributes":{"POSITION":0},"material":1}]},'
    '{"primitives":[{"attributes":{"POSITION":0},"material":2}]},'
    '{"primitives":[{"attributes":{"POSITION":0},"material":0}]},'
    '{"primitives":[{"attributes":{"POSITION":0},"material":0}]},'
    '{"primitives":[{"attributes":{"POSITION":0},"material":0}]}]}'
)


def town_registry() raises -> AssetRegistry:
    """A registry whose cache holds the town package, as `town.Town02`,
    the rigged model as a town that cannot be used, and the package with
    no lamps and no lamp glass, as `town.Town03`."""
    var folder = temporary_path("threemojo_carla_town/")
    makedirs(folder, exist_ok=True)
    Path(folder + "town.gltf").write_text(TOWN_GLTF)
    Path(folder + "plain.gltf").write_text(
        String(TOWN_GLTF)
        .replace(',"extras":{"carla_lamps":[0,5,0,10,5,0,100,5,0]}', "")
        .replace('{"extras":{"carla":"lamp"}}', "{}")
    )
    Path(folder + "rigged.gltf").write_bytes(
        Path("assets/gltf/three_export.gltf").read_bytes()
    )
    return AssetRegistry(
        parse_manifest(
            _manifest(
                _entry("town", "town", _file("model", "town.gltf"))
                + ", "
                + _entry("rigged", "town", _file("model", "rigged.gltf"))
                + ", "
                + _entry("plain", "town", _file("model", "plain.gltf")),
                '{"town.Town02": "town", "town.Town03": "plain"}',
            )
        ),
        folder,
    )


def test_a_town_node_names_its_tile() raises:
    var tile = town_tile("road_line_3_-2_lod1")
    assert_equal(tile[0], "3_-2")
    assert_equal(tile[1], 1)
    for name in ["odd", "a_b_c_lodx", "a_1_2_lod", "a_1_2_near"]:
        var other = town_tile(name)
        assert_equal(other[0], "")
        assert_equal(other[1], 0)


def test_a_town_is_placed_as_it_is_in_tiles() raises:
    var registry = town_registry()
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    scene.update()
    var index = registry.cached_entry("town.Town02").value()
    var placed = registry.place_town(
        index, scene, assets, parent, Length(10, METER)
    )
    assert_equal(placed.mesh_count, 8)
    assert_equal(placed.kinds[0], "building")
    assert_equal(placed.kinds[2], "road_line")
    # A node with no kind, or a kind that is not a string, is a prop.
    assert_equal(placed.kinds[5], "prop")
    assert_equal(placed.kinds[6], "prop")
    assert_equal(placed.lods[1], 1)
    assert_equal(placed.lods[5], 0)
    # A level past the far one is the far one.
    assert_equal(placed.lods[6], 1)
    # Three tiles: 0_0, 1_0, and the one of the node named otherwise.
    assert_equal(placed.lod_count, 3)
    assert_equal(len(scene.lods), placed.first_lod + 3)
    # The package stays where it is: the triangle's corner is at the
    # origin.
    var box = assets.geometries.get(scene.meshes[0].geometry).bounding_box()
    box.apply_matrix4(scene.world_matrix(scene.meshes[0].node))
    assert_almost_equal(box.min.x, 0, atol=1e-5)
    assert_almost_equal(box.max.y, 1, atol=1e-5)
    assert_true(scene.meshes[0].cast_shadow)
    # The scene's lamp heads, and the lamps' glass.
    assert_equal(len(placed.lamps), 3)
    assert_almost_equal(placed.lamps[1].x, 10, atol=1e-5)
    assert_almost_equal(placed.lamps[1].y, 5, atol=1e-5)
    assert_equal(len(placed.lamp_materials), 1)
    assert_true(placed.lamp_materials[0] == scene.meshes[4].material)
    assert_true(
        assets.materials.get(scene.meshes[0].material).env_map
        == SCENE_ENVIRONMENT
    )
    # Near a tile, its near level shows; far from it, its far level.
    scene.update_lods(Vector3(0, 0, 0))
    assert_equal(scene.lods[placed.first_lod].shown, 0)
    assert_true(scene.is_shown(scene.meshes[0].node))
    assert_false(scene.is_shown(scene.meshes[1].node))
    scene.update_lods(Vector3(100, 0, 0))
    assert_equal(scene.lods[placed.first_lod].shown, 1)
    assert_false(scene.is_shown(scene.meshes[0].node))
    assert_true(scene.is_shown(scene.meshes[1].node))


def test_a_town_the_renderer_cannot_use_is_refused() raises:
    var registry = town_registry()
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    scene.update()
    var near = Length(10, METER)
    with assert_raises(contains="only plain meshes"):
        _ = registry.place_town(1, scene, assets, parent, near)
    with assert_raises(contains="is not a town"):
        _ = _registry().place_town(0, scene, assets, parent, near)
    var folder = temporary_path("threemojo_carla_town/")
    Path(folder + "bare.gltf").write_text(
        '{"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes":'
        ' [0]}], "nodes": [{"name": "marker"}]}'
    )
    var bare = AssetRegistry(
        parse_manifest(
            _manifest(_entry("bare", "town", _file("model", "bare.gltf")))
        ),
        folder,
    )
    with assert_raises(contains="has no mesh"):
        _ = bare.place_town(0, scene, assets, parent, near)
    # Lamps that are not numbers three at a time.
    for lamps in ["[0,5]", '[0,5,"up"]', '{"a":1}']:
        Path(folder + "lamps.gltf").write_text(
            String(TOWN_GLTF).replace("[0,5,0,10,5,0,100,5,0]", lamps)
        )
        var odd = AssetRegistry(
            parse_manifest(
                _manifest(_entry("odd", "town", _file("model", "lamps.gltf")))
            ),
            folder,
        )
        with assert_raises(contains="three numbers each"):
            _ = odd.place_town(0, scene, assets, parent, near)


# One triangle with no material, as a node named `name`, and the same
# triangle drawn at three places by `EXT_mesh_gpu_instancing`.
def _bare_triangle(name: String, instanced: Bool) -> String:
    var node = '{"name":"' + name + '","mesh":0'
    if instanced:
        node += (
            ',"extensions":{"EXT_mesh_gpu_instancing":{"attributes":'
            '{"TRANSLATION":0}}}'
        )
    return (
        '{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],'
        + '"extensionsUsed":["EXT_mesh_gpu_instancing"],"nodes":['
        + node
        + '}],"buffers":[{"byteLength":36,"uri":'
        + '"data:application/octet-stream;base64,'
        + 'AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"}],'
        + '"bufferViews":[{"buffer":0,"byteLength":36}],"accessors":'
        + '[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3",'
        + '"min":[0,0,0],"max":[1,1,0]}],"meshes":[{"primitives":'
        + '[{"attributes":{"POSITION":0}}]}]}'
    )


def test_the_edges_of_a_manifest_and_a_cache() raises:
    # A manifest with no entry reads, and a registry over it has nothing
    # to decode.
    var none = parse_manifest('{"format": 1, "entries": []}')
    assert_equal(len(none.entries), 0)
    var empty = AssetRegistry(none^, CACHE)
    empty.preload(1)
    assert_equal(len(empty.decoded), 0)
    # A displacement map with no normal map is read, as the bump.
    var bumpy = AssetRegistry(
        parse_manifest(
            _manifest(
                _entry(
                    "bumpy",
                    "texture_set",
                    _file("albedo", "gltf/checker.png")
                    + ", "
                    + _file("displacement", "gltf/checker.png"),
                    ', "tile_meters": 2',
                ),
                '{"surface.road": "bumpy"}',
            )
        ),
        CACHE,
    )
    bumpy.preload(1)
    assert_equal(len(bumpy.decoded), 2)


def test_models_and_towns_with_no_material_or_with_instances() raises:
    var folder = temporary_path("threemojo_carla_bare/")
    makedirs(folder, exist_ok=True)
    Path(folder + "model.gltf").write_text(_bare_triangle("part", False))
    Path(folder + "town.gltf").write_text(
        _bare_triangle("building_0_0_lod0", False)
    )
    Path(folder + "crowd.gltf").write_text(_bare_triangle("part", True))
    Path(folder + "lampless.gltf").write_text(
        String(TOWN_GLTF).replace("[0,5,0,10,5,0,100,5,0]", "[]")
    )
    var registry = AssetRegistry(
        parse_manifest(
            _manifest(
                _entry(
                    "model",
                    "model",
                    _file("model", "model.gltf"),
                    ', "forward": "+x"',
                )
                + ", "
                + _entry("town", "town", _file("model", "town.gltf"))
                + ", "
                + _entry(
                    "crowd",
                    "model",
                    _file("model", "crowd.gltf"),
                    ', "forward": "+x"',
                )
                + ", "
                + _entry("crowds", "town", _file("model", "crowd.gltf"))
                + ", "
                + _entry("lampless", "town", _file("model", "lampless.gltf"))
            )
        ),
        folder,
    )
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    scene.update()
    var near = Length(10, METER)
    # No material: nothing to reflect the environment or to tag.
    var model = registry.place_model(0, scene, assets, parent, Vector3(1, 1, 1))
    assert_equal(model.mesh_count, 1)
    assert_equal(len(model.paint), 0)
    var town = registry.place_town(1, scene, assets, parent, near)
    assert_equal(town.mesh_count, 1)
    assert_equal(len(town.lamp_materials), 0)
    # Instances are refused by both.
    with assert_raises(contains="only plain meshes"):
        _ = registry.place_model(2, scene, assets, parent, Vector3(1, 1, 1))
    with assert_raises(contains="only plain meshes"):
        _ = registry.place_town(3, scene, assets, parent, near)
    # An empty list of lamps is no lamp.
    var lampless = registry.place_town(4, scene, assets, parent, near)
    assert_equal(len(lampless.lamps), 0)


def test_town_lamp_tag_requires_the_exact_string() raises:
    var folder = temporary_path("threemojo_carla_lamp_tags/")
    makedirs(folder, exist_ok=True)
    for tag in ["7", '"glass"']:
        Path(folder + "town.gltf").write_text(
            String(TOWN_GLTF).replace('"carla":"lamp"', '"carla":' + tag)
        )
        var registry = AssetRegistry(
            parse_manifest(
                _manifest(_entry("town", "town", _file("model", "town.gltf")))
            ),
            folder,
        )
        var scene = Scene()
        var assets = Assets()
        var parent = scene.add(Object3D())
        var placed = registry.place_town(
            0, scene, assets, parent, Length(10, METER)
        )
        assert_equal(placed.mesh_count, 8)
        assert_equal(len(placed.lamp_materials), 0)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
