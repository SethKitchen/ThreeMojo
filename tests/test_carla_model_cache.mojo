# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cached CARLA models retain resource ownership and instance isolation."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry
from core.geometry_store import GeometryId, GeometryStore
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from extensions.carla.assets import AssetRegistry, parse_manifest
from extensions.carla.model_cache import ModelCache
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.opendrive import load_opendrive_file
from extensions.carla.render_actors import (
    ActorVisuals,
    BRAKE_GLOW,
    HIGH_BEAM_GLOW,
    LOW_BEAM_GLOW,
    TAIL_GLOW,
    SEDAN,
    HATCHBACK,
)
from extensions.carla.transform import CarlaTransform, CarlaRotation
from extensions.carla.vehicle import (
    LIGHT_BRAKE,
    LIGHT_HIGH_BEAM,
    LIGHT_LOW_BEAM,
)
from extensions.carla.world import World
from materials.material import MaterialStore
from math.vector3 import Vector3
from render.framebuffer import Color
from render.texture_store import TextureId, TextureStore
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
from test_carla_assets import (
    TAGGED_GLTF,
    _bare_triangle,
    _entry,
    _file,
    _manifest,
)
from test_scratch import TestScratch, temporary_path
from test_gltf_animation import Bin, rig
from units.si import DEGREE, METER, Angle, Length


def _gltf() -> String:
    return (
        String(TAGGED_GLTF)
        .replace(
            '"materials":[',
            (
                '"images":[{"uri":"checker.png"}],'
                '"textures":[{"source":0}],"materials":['
            ),
        )
        .replace(
            '"extras":{"carla":"paint"}',
            (
                '"extras":{"carla":"paint"},"pbrMetallicRoughness":'
                '{"baseColorTexture":{"index":0}}'
            ),
        )
    )


def _registry(
    name: String = "models", text: String = _gltf()
) raises -> AssetRegistry:
    var folder = temporary_path(name + "/")
    makedirs(folder, exist_ok=True)
    Path(folder + "model.gltf").write_text(text)
    Path(folder + "checker.png").write_bytes(
        Path("assets/gltf/checker.png").read_bytes()
    )
    return AssetRegistry(
        parse_manifest(
            _manifest(
                _entry(
                    "car",
                    "model",
                    _file("model", "model.gltf")
                    + ","
                    + _file("support", "checker.png"),
                    ',"forward":"+x"',
                ),
                '{"vehicle.*":"car"}',
            )
        ),
        folder,
    )


def test_identical_models_share_bytes_but_not_materials_or_nodes() raises:
    var registry = _registry()
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    var first = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(assets.geometries.count(), 6)
    assert_equal(assets.textures.count(), 1)
    assert_equal(assets.materials.count(), 6)
    var first_paint = assets.materials.get(first.paint[0])
    var image = first_paint.map
    assets.materials.materials[first.paint[0].value].color = Color(255, 0, 0)
    assets.materials.materials[first.heads[0].value].emissive_intensity = 17
    scene.node(first.pivot).set_position(100, 10, 50)
    for i in range(96):
        var next = cache.place(
            registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
        )
        assert_equal(assets.geometries.count(), 6)
        assert_equal(assets.textures.count(), 1)
        assert_equal(assets.materials.count(), 6 * (i + 2))
        assert_true(next.pivot != first.pivot)
        assert_true(next.paint[0] != first.paint[0])
        assert_equal(assets.materials.get(next.paint[0]).map, image)
        assert_equal(
            assets.materials.get(next.paint[0]).color.r, first_paint.color.r
        )
        assert_equal(
            assets.materials.get(next.paint[0]).color.g, first_paint.color.g
        )
        assert_equal(
            assets.materials.get(next.paint[0]).color.b, first_paint.color.b
        )
        assert_equal(assets.materials.get(next.heads[0]).emissive_intensity, 1)
        assert_almost_equal(scene.world_position(next.pivot).x, -1, atol=1e-6)
        for m in range(first.mesh_count):
            assert_equal(
                scene.meshes[first.first_mesh + m].geometry,
                scene.meshes[next.first_mesh + m].geometry,
            )
    # The source graph does not belong to any instance's scene.
    scene = Scene()
    var again = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(again.mesh_count, 6)
    assert_equal(assets.geometries.count(), 6)


def test_cache_and_stores_move_without_changing_resource_identity() raises:
    var registry = _registry()
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    var moved_assets = assets^
    var moved_cache = cache^
    _ = moved_cache.place(
        registry, 0, scene, moved_assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(moved_assets.geometries.count(), 6)
    assert_equal(moved_assets.textures.count(), 1)
    # A fresh materials store needs no resource reload: values are private.
    moved_assets.materials = MaterialStore()
    scene = Scene()
    var placed = moved_cache.place(
        registry, 0, scene, moved_assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(placed.paint[0].value, 0)
    assert_equal(moved_assets.materials.count(), 6)
    assert_equal(moved_assets.geometries.count(), 6)


def test_fresh_and_replaced_resource_stores_cannot_reuse_stale_ids() raises:
    var registry = _registry()
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assets = Assets()
    scene = Scene()
    _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assert_equal(assets.geometries.count(), 6)
    assert_equal(assets.textures.count(), 1)
    assets.geometries = GeometryStore()
    scene = Scene()
    _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assert_equal(assets.geometries.count(), 6)
    assert_equal(assets.textures.count(), 2)
    assets.textures = TextureStore()
    scene = Scene()
    var placed = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(assets.geometries.count(), 12)
    assert_equal(assets.textures.count(), 1)
    assert_equal(assets.materials.get(placed.paint[0]).map.value, 0)
    # Repeated destruction cannot hit a retained old allocation token.
    for _ in range(32):
        assets = Assets()
        scene = Scene()
        _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2))
        assert_equal(assets.geometries.count(), 6)
        assert_equal(assets.textures.count(), 1)


def test_clear_reloads_changed_bytes_and_preserves_existing_instances() raises:
    var registry = _registry()
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    var before = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    Path(registry.path("model.gltf")).write_text(
        _gltf()
        .replace(
            '"nodes":[0]',
            '"nodes":[0,1]',
        )
        .replace(
            '"nodes":[{"mesh":0}]',
            '"nodes":[{"mesh":0},{"mesh":0,"translation":[3,0,0]}]',
        )
    )
    var stale = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(stale.mesh_count, 6)
    cache.clear()
    cache.clear()
    var after = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(after.mesh_count, 12)
    assert_equal(assets.geometries.count(), 12)
    assert_equal(assets.textures.count(), 2)
    assert_equal(scene.meshes[before.first_mesh].geometry.value, 0)
    assert_equal(scene.meshes[after.first_mesh].geometry.value, 6)


def test_key_tracks_digest_path_root_and_entry_without_index_aliases() raises:
    var registry = _registry()
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    registry.manifest.entries.append(registry.manifest.entries[0].copy())
    _ = cache.place(registry, 1, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assert_equal(assets.geometries.count(), 6)
    registry.manifest.entries[1].files[1].sha256 = "1" * 64
    _ = cache.place(registry, 1, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assert_equal(assets.geometries.count(), 12)
    registry.manifest.entries[1].id = "other"
    _ = cache.place(registry, 1, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assert_equal(assets.geometries.count(), 18)
    Path(registry.path("copy.gltf")).write_text(_gltf())
    registry.manifest.entries[1].files[0].path = "copy.gltf"
    _ = cache.place(registry, 1, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assert_equal(assets.geometries.count(), 24)
    var other = _registry("other")
    _ = cache.place(other, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2))
    assert_equal(assets.geometries.count(), 30)
    # An orientation change changes placement, without copying source bytes.
    other.manifest.entries[0].yaw = Angle(90, DEGREE)
    var turned = cache.place(
        other, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(assets.geometries.count(), 30)
    assert_equal(turned.mesh_count, 6)


def test_failed_load_rolls_back_resources_and_can_be_retried() raises:
    var registry = _registry(text=_gltf().replace('"mesh":0', '"mesh":99'))
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    for _ in range(3):
        with assert_raises():
            _ = cache.place(
                registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
            )
        assert_equal(assets.geometries.count(), 0)
        assert_equal(assets.textures.count(), 0)
        assert_equal(assets.materials.count(), 0)
        assert_equal(scene.count(), 0)
    Path(registry.path("model.gltf")).write_text(_gltf())
    var placed = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(4, 2, 2)
    )
    assert_equal(placed.mesh_count, 6)
    assert_equal(assets.geometries.count(), 6)


def test_invalid_entry_parent_and_instanced_model_are_refused() raises:
    var registry = _registry(text=_bare_triangle("instance", True))
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    for index in [-1, 1]:
        with assert_raises(contains="No asset entry"):
            _ = cache.place(
                registry, index, scene, assets, NO_PARENT, Vector3(1, 1, 1)
            )
    with assert_raises():
        _ = cache.place(
            registry, 0, scene, assets, NodeId(20), Vector3(1, 1, 1)
        )
    with assert_raises(contains="only plain meshes"):
        _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(1, 1, 1))
    assert_equal(assets.geometries.count(), 0)
    Path(registry.path("model.gltf")).write_text('{"asset":{"version":"2.0"}}')
    with assert_raises(contains="has no mesh"):
        _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(1, 1, 1))
    registry.manifest.entries[0].kind.value = 0
    with assert_raises(contains="is not a model"):
        _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(1, 1, 1))


def test_skinned_model_is_refused_without_retaining_resources() raises:
    var buffer = Bin()
    var registry = _registry(
        text=rig(buffer, '[{"joints":[1],"inverseBindMatrices":3}]')
    )
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    with assert_raises(contains="only plain meshes"):
        _ = cache.place(registry, 0, scene, assets, NO_PARENT, Vector3(1, 1, 1))
    assert_equal(assets.geometries.count(), 0)
    assert_equal(assets.materials.count(), 0)
    assert_equal(scene.count(), 0)


def test_materialless_mesh_gets_a_fresh_default_material() raises:
    var registry = _registry(text=_bare_triangle("bare", False))
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    var first = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(1, 1, 1)
    )
    var second = cache.place(
        registry, 0, scene, assets, NO_PARENT, Vector3(1, 1, 1)
    )
    assert_equal(len(first.paint), 0)
    assert_true(
        scene.meshes[first.first_mesh].material
        != scene.meshes[second.first_mesh].material
    )
    assert_equal(assets.geometries.count(), 1)


def test_vehicle_spawns_share_resources_with_independent_colors_lights_and_pose() raises:
    var registry = _registry()
    var assets = Assets()
    var scene = Scene()
    var visuals = ActorVisuals()
    var world = World(load_opendrive_file("assets/carla/town.xodr"))
    var library = world.get_blueprint_library()
    var blueprint = library.at("vehicle.lincoln.mkz")
    blueprint.set_attribute("color", "190,30,28")
    var pose = CarlaTransform(
        Length(0, METER),
        Length(0, METER),
        Length(3, METER),
        CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
    )
    var first = world.spawn_actor(blueprint, pose)
    world.set_light_state(first, LIGHT_HIGH_BEAM | LIGHT_BRAKE)
    visuals.sync(world, scene, assets, registry)
    assert_equal(assets.geometries.count(), 6)
    assert_equal(assets.textures.count(), 1)
    blueprint.set_attribute("color", "20,40,200")
    pose.location.x = 20
    var second = world.spawn_actor(blueprint, pose)
    world.set_light_state(second, LIGHT_LOW_BEAM)
    visuals.sync(world, scene, assets, registry)
    assert_equal(assets.geometries.count(), 6)
    assert_equal(assets.textures.count(), 1)
    ref a = visuals.vehicles[0]
    ref b = visuals.vehicles[1]
    assert_equal(assets.materials.get(a.paint).color.r, 190)
    assert_equal(assets.materials.get(b.paint).color.b, 200)
    assert_equal(
        assets.materials.get(a.heads).emissive_intensity, HIGH_BEAM_GLOW
    )
    assert_equal(assets.materials.get(a.tails).emissive_intensity, BRAKE_GLOW)
    assert_equal(
        assets.materials.get(b.heads).emissive_intensity, LOW_BEAM_GLOW
    )
    assert_equal(assets.materials.get(b.tails).emissive_intensity, TAIL_GLOW)
    assert_true(a.paint != b.paint)
    assert_equal(scene.world_position(a.node).x, 0)
    assert_equal(scene.world_position(b.node).x, 20)
    for v in visuals.vehicles:
        assert_equal(scene.meshes[v.first_mesh].material, v.paint)
        assert_equal(scene.meshes[v.first_mesh + 1].material, v.heads)
        assert_equal(scene.meshes[v.first_mesh + 2].material, v.tails)
    _ = world.destroy_actor(first)
    visuals.sync(world, scene, assets, registry)
    assert_false(scene.get(visuals.vehicles[0].node).visible)
    # A new instance after destruction must not inherit the first's lights.
    pose.location.x = 40
    _ = world.spawn_actor(blueprint, pose)
    visuals.sync(world, scene, assets, registry)
    assert_equal(
        assets.materials.get(visuals.vehicles[2].heads).emissive_intensity, 0
    )
    assert_equal(assets.geometries.count(), 6)
    assert_equal(assets.textures.count(), 1)


def test_hierarchy_line_points_and_light_targets_match_direct_placement() raises:
    var text = (
        _gltf()
        .replace(
            '"nodes":[{"mesh":0}]',
            (
                '"nodes":[{"translation":[2,3,4],"children":[1,2,3]},'
                '{"mesh":0,"translation":[-1,0,2],"extensions":{"KHR_lights_punctual":{"light":0}}},'
                '{"extensions":{"KHR_lights_punctual":{"light":1}}},'
                '{"extensions":{"KHR_lights_punctual":{"light":2}}}]'
            ),
        )
        .replace(
            '"materials":[',
            (
                '"extensionsUsed":["KHR_lights_punctual"],'
                '"extensions":{"KHR_lights_punctual":{"lights":[{"type":"directional"},{"type":"point"},{"type":"spot","spot":{"innerConeAngle":0.1,"outerConeAngle":0.3}}]}},"materials":['
            ),
        )
        .replace('"material":4}', '"material":4,"mode":1}')
        .replace('"material":5}', '"material":5,"mode":0}')
    )
    var registry = _registry(text=text)
    var direct = Scene()
    var direct_assets = Assets()
    var root = direct.add(Object3D())
    direct.node(root).set_position(12, -4, 5)
    var expected = registry.place_model(
        0, direct, direct_assets, root, Vector3(4, 2, 2)
    )
    var cache = ModelCache()
    var assets = Assets()
    var scene = Scene()
    root = scene.add(Object3D())
    scene.node(root).set_position(12, -4, 5)
    for _ in range(2):
        var mesh_start = len(scene.meshes)
        var line_start = len(scene.lines)
        var point_start = len(scene.points)
        var light_start = len(scene.lights)
        var actual = cache.place(
            registry, 0, scene, assets, root, Vector3(4, 2, 2)
        )
        assert_equal(actual.mesh_count, expected.mesh_count)
        assert_equal(actual.scale, expected.scale)
        assert_equal(len(scene.lines) - line_start, 1)
        assert_equal(len(scene.points) - point_start, 1)
        assert_equal(len(scene.lights) - light_start, 3)
        for m in range(expected.mesh_count):
            var a = scene.world_matrix(scene.meshes[mesh_start + m].node)
            var b = direct.world_matrix(direct.meshes[m].node)
            for k in range(16):
                assert_almost_equal(a.elements[k], b.elements[k], atol=1e-6)
        for i in range(3):
            var lamp = scene.lights[light_start + i]
            assert_equal(lamp.kind, direct.lights[i].kind)
            if lamp.target != NO_PARENT:
                var a = scene.world_position(lamp.target)
                var b = direct.world_position(direct.lights[i].target)
                assert_almost_equal(a.x, b.x, atol=1e-6)
                assert_almost_equal(a.y, b.y, atol=1e-6)
                assert_almost_equal(a.z, b.z, atol=1e-6)
    assert_equal(assets.geometries.count(), direct_assets.geometries.count())
    assert_equal(assets.textures.count(), direct_assets.textures.count())


def test_failed_vehicle_sync_does_not_accumulate_actor_resources() raises:
    var registry = _registry(text=_gltf().replace('"mesh":0', '"mesh":99'))
    var cache_assets = Assets()
    var scene = Scene()
    var visuals = ActorVisuals()
    var world = World(load_opendrive_file("assets/carla/town.xodr"))
    var library = world.get_blueprint_library()
    _ = world.spawn_actor(
        library.at("vehicle.lincoln.mkz"),
        CarlaTransform(
            Length(0, METER),
            Length(0, METER),
            Length(3, METER),
            CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE)),
        ),
    )
    for _ in range(3):
        with assert_raises():
            visuals.sync(world, scene, cache_assets, registry)
        assert_equal(scene.count(), 0)
        assert_equal(len(scene.meshes), 0)
        assert_equal(len(visuals.vehicles), 0)
        assert_equal(cache_assets.materials.count(), 5)
        assert_equal(cache_assets.geometries.count(), 0)
        assert_equal(cache_assets.textures.count(), 0)
    Path(registry.path("model.gltf")).write_text(_gltf())
    visuals.sync(world, scene, cache_assets, registry)
    assert_equal(len(visuals.vehicles), 1)
    assert_equal(cache_assets.geometries.count(), 6)
    assert_equal(cache_assets.textures.count(), 1)


def test_store_boundaries_and_replacement_keep_the_live_owner() raises:
    var assets = Assets()
    var owner = assets.geometries._cache_owner
    var id = assets.geometries.add(BufferGeometry())
    assets.geometries.replace(id, BufferGeometry())
    assert_true(owner.ptr() == assets.geometries._cache_owner.ptr())
    assert_equal(assets.geometries.get(id).attribute_count(), 0)
    for bad in [GeometryId(-1), GeometryId(1)]:
        with assert_raises(contains="No geometry"):
            _ = assets.geometries.get(bad)
        with assert_raises(contains="No geometry"):
            assets.geometries.replace(bad, BufferGeometry())
    for bad in [TextureId(-1), TextureId(0)]:
        with assert_raises(contains="No texture"):
            _ = assets.textures.get(bad)


def test_procedural_model_reuse_distinguishes_height_and_style() raises:
    var assets = Assets()
    var visuals = ActorVisuals()
    var size = BoundingBox(Vector3(0, 0, 0.75), Vector3(2.4, 1, 0.75))
    _ = visuals._model(assets, size, SEDAN)
    _ = visuals._model(assets, size, HATCHBACK)
    size.extent.z = 0.9
    _ = visuals._model(assets, size, SEDAN)
    assert_equal(len(visuals.models), 3)
    var resources = assets.geometries.count()
    _ = visuals._model(assets, size, SEDAN)
    assert_equal(len(visuals.models), 3)
    assert_equal(assets.geometries.count(), resources)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
