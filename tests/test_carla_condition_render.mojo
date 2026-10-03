# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent CARLA render condition and cache-key regression controls."""
from core.assets import Assets
from core.scene import Scene
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.render_actors import ActorVisuals, SEDAN, HATCHBACK
from extensions.carla.town import Town, TownSettings, building_geometry
from extensions.carla.assets import AssetRegistry, parse_manifest
from extensions.carla.sensor import GROUND, SIDEWALK
from std.os import makedirs
from std.pathlib import Path
from test_scratch import TestScratch, temporary_path
from test_carla_assets import TOWN_GLTF, _manifest, _entry, _file
from extensions.carla.weather import weather_preset
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_raises
from test_carla_render_scene import _map, _small
from units.si import Length, METER


def test_vehicle_model_cache_keys_height_and_style() raises:
    var assets = Assets()
    var visuals = ActorVisuals()
    var box = BoundingBox(Vector3(2, 1, 0.8))
    _ = visuals._model(assets, box, SEDAN)
    var taller = BoundingBox(Vector3(2, 1, 1.0))
    _ = visuals._model(assets, taller, SEDAN)
    assert_equal(len(visuals.models), 2)
    _ = visuals._model(assets, box, HATCHBACK)
    assert_equal(len(visuals.models), 3)
    _ = visuals._model(assets, box, SEDAN)
    _ = visuals._model(assets, taller, SEDAN)
    _ = visuals._model(assets, box, HATCHBACK)
    assert_equal(len(visuals.models), 3)


def test_building_depth_must_be_positive() raises:
    with assert_raises(contains="positive width"):
        _ = building_geometry(
            Length(10, METER), Length(0, METER), Length(12, METER)
        )


def test_puddle_change_with_unchanged_wetness_updates_town() raises:
    var scene = Scene()
    var assets = Assets()
    var town = Town(_map(), scene, assets, _small())
    var rain = weather_preset("HardRainNoon")
    town.set_weather(scene, assets, rain)
    rain.precipitation_deposits = 0
    town.set_weather(scene, assets, rain)
    assert_equal(town.wet.puddles, 0)


def test_package_sidewalk_and_ground_are_wettable() raises:
    var folder = temporary_path("threemojo_carla_wet_kinds/")
    makedirs(folder, exist_ok=True)
    Path(folder + "town.gltf").write_text(
        String(TOWN_GLTF)
        .replace('"carla_kind":"road_line"', '"carla_kind":"sidewalk"')
        .replace('"carla_kind":"road"', '"carla_kind":"ground"')
    )
    var registry = AssetRegistry(
        parse_manifest(
            _manifest(
                _entry("town", "town", _file("model", "town.gltf")),
                '{"town.Test": "town"}',
            )
        ),
        folder,
    )
    var settings = TownSettings()
    settings.texture_size = 2
    settings.package = "Test"
    var scene = Scene()
    var assets = Assets()
    var map = _map()
    var town = Town(map, scene, assets, settings^, registry)
    assert_equal(town.tags[2], SIDEWALK)
    assert_equal(town.tags[3], GROUND)
    # Both surfaces share one material, which must be tracked only once.
    assert_equal(len(town.wet_materials), 1)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
