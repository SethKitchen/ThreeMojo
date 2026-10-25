# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A live shared helper keeps its provider, and an old pair does not."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tests._shared_helper_provider import (
    provider_pin,
    required_providers,
    restored_curve_distance,
    restored_render_sky,
    restored_render_weather,
)
from tools._sha256 import sha256_hex


comptime _DISTANCE = "extensions/carla/curve_distance.mojo"
"""The distance consumer."""
comptime _SKY = "extensions/carla/render_sky.mojo"
"""The sky consumer."""
comptime _WEATHER = "extensions/carla/render_weather.mojo"
"""The weather consumer."""
comptime _INTERVAL = "extensions/carla/curve_interval.mojo"
"""The distance helper provider."""
comptime _COLOR = "render/color_math.mojo"
"""The sky and weather helper provider."""
comptime _DISTANCE_BEFORE = (
    "46176387129dd37a5887f3aeec7c96bbb386e4980063cb96f09619832cb09a79"
)
"""The distance file before helper extraction."""
comptime _SKY_BEFORE = (
    "4b99faa687940af925a5cedd09d33d7b44dd7e317f892a1be269ccd8deaedaa7"
)
"""The sky file before helper extraction."""
comptime _WEATHER_BEFORE = (
    "5e2c6ed0db903e2c1dd484d73a100cfb816562655722c69e8461d1079d178460"
)
"""The weather file before helper extraction."""


def _fill(
    mut paths: List[String],
    mut texts: List[String],
    path: String,
    text: String,
):
    """Append one consumer.

    Args:
        paths: The consumer paths.
        texts: The consumer sources.
        path: The consumer to add.
        text: That consumer's source.
    """
    paths.append(path)
    texts.append(text)


def test_old_endpoints_require_no_provider() raises:
    """Restored sky and weather require no color provider."""
    var sky = restored_render_sky(Path(_SKY).read_text())
    var weather = restored_render_weather(Path(_WEATHER).read_text())
    var distance = restored_curve_distance(Path(_DISTANCE).read_text())
    assert_equal(sha256_hex(sky.as_bytes()), _SKY_BEFORE)
    assert_equal(sha256_hex(weather.as_bytes()), _WEATHER_BEFORE)
    assert_equal(sha256_hex(distance.as_bytes()), _DISTANCE_BEFORE)
    var paths = List[String]()
    var texts = List[String]()
    var providers = List[String]()
    _fill(paths, texts, _SKY, sky)
    _fill(paths, texts, _WEATHER, weather)
    required_providers(paths, texts, providers)
    assert_equal(len(providers), 0)
    providers.clear()
    paths.clear()
    texts.clear()
    _fill(paths, texts, _DISTANCE, distance)
    required_providers(paths, texts, providers)
    assert_equal(len(providers), 0)


def test_live_consumers_require_their_provider_digest() raises:
    """A live consumer names its provider and checks that digest."""
    var distance = Path(_DISTANCE).read_text()
    var sky = Path(_SKY).read_text()
    var weather = Path(_WEATHER).read_text()
    var interval = Path(_INTERVAL).read_text()
    var color = Path(_COLOR).read_text()
    var paths = List[String]()
    var texts = List[String]()
    var providers = List[String]()
    _fill(paths, texts, _DISTANCE, distance)
    required_providers(paths, texts, providers)
    assert_equal(len(providers), 1)
    assert_equal(providers[0], _INTERVAL)
    assert_equal(sha256_hex(interval.as_bytes()), provider_pin(providers[0]))
    providers.clear()
    paths.clear()
    texts.clear()
    _fill(paths, texts, _SKY, sky)
    _fill(paths, texts, _WEATHER, restored_render_weather(weather))
    required_providers(paths, texts, providers)
    assert_equal(len(providers), 1)
    assert_equal(providers[0], _COLOR)
    assert_equal(
        provider_pin(providers[0]),
        "328a3e43b19b8ab6120563014d19a121284175444c09732d30dffe74eb416c84",
    )
    assert_true(sha256_hex(color.as_bytes()) != provider_pin(_COLOR))
    providers.clear()
    paths.clear()
    texts.clear()
    _fill(paths, texts, _SKY, restored_render_sky(sky))
    _fill(paths, texts, _WEATHER, weather)
    required_providers(paths, texts, providers)
    assert_equal(providers[0], _COLOR)


def test_a_changed_consumer_is_refused() raises:
    """A consumer that is neither endpoint is refused."""
    var sky = Path(_SKY).read_text() + "\n"
    var paths = List[String]()
    var texts = List[String]()
    var providers = List[String]()
    _fill(paths, texts, _SKY, sky)
    with assert_raises(contains="unknown endpoint"):
        required_providers(paths, texts, providers)
    with assert_raises(contains="unknown provider"):
        _ = provider_pin("loaders/utf8.mojo")


def main() raises:
    """Run the shared-helper provider tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
