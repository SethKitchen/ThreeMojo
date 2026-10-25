# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the shared-helper consumers and name their providers."""

from tools._sha256 import sha256_hex


def _replace_once(
    text: String, before: String, after: String, path: String
) raises -> String:
    """Replace one exact `before`.

    Args:
        text: The source.
        before: The fragment that must occur once.
        after: The replacement.
        path: The module, named when the fragment is missing.

    Returns:
        The source with that fragment replaced.

    Raises:
        Error: `before` is missing or repeated.
    """
    var count = 0
    var rest = text
    while True:
        var at = rest.find(before)
        if at < 0:
            break
        count += 1
        var tail = String(rest[byte = at + before.byte_length() :])
        rest = tail
    if count != 1:
        raise Error("shared-helper provider: missing inverse: " + path)
    var start = text.find(before)
    var head = String(text[byte=:start])
    var tail = String(text[byte = start + before.byte_length() :])
    return head + after + tail


def restored_curve_distance(text: String) raises -> String:
    """Restore the old `curve_distance.mojo` helper endpoint.

    Args:
        text: The live module.

    Returns:
        The module before helper extraction.

    Raises:
        Error: An inverse fragment is missing.
    """
    var current = text
    var earlier_0 = (
        '"""\n\nfrom extensions.carla.curve_interval import _next_down, _n'
        "ext_up\nfrom std.math import inf, isfinite, isnan, sqrt\nfrom std.me"
        "mory import bitcast\n\n\n"
    )
    var later_0 = (
        '"""\n\nfrom std.math import inf, isfinite, isnan, sqrt\nfrom std.'
        "memory import bitcast\n\n\ndef _next_up(value: Float64) -> Float64:\n"
        "    # Observe the rounded bits before any following arithmetic. Unli"
        "ke an\n    # epsilon multiplier, this also handles zero and subnorma"
        "l results.\n    if isnan(value) or value == inf[DType.float64]():\n "
        "       return value\n    if value == 0.0:\n        return bitcast[DT"
        "ype.float64](UInt64(1))\n    var bits = bitcast[DType.uint64](value)"
        "\n    if value < 0.0:\n        return bitcast[DType.float64](bits - "
        "1)\n    return bitcast[DType.float64](bits + 1)\n\n\ndef _next_down("
        "value: Float64) -> Float64:\n    return -_next_up(-value)\n\n\n"
    )
    current = _replace_once(
        current, earlier_0, later_0, "extensions/carla/curve_distance.mojo"
    )
    return current


def restored_render_sky(text: String) raises -> String:
    """Restore the old `render_sky.mojo` helper endpoint.

    Args:
        text: The live module.

    Returns:
        The module before helper extraction.

    Raises:
        Error: An inverse fragment is missing.
    """
    var current = text
    var earlier_0 = (
        "                    data[at] * gain, data[at + 1] * gain, data[at + "
        "2] * gain\n                )\n                var seen = mix_opaque("
        "ground, sky, above)\n                data[at] = seen.r\n            "
        "    data[at + 1] = seen.g\n                data[at + 2] = seen.b\n  "
        "  return _lighting(assets, cube^)\n"
    )
    var later_0 = (
        "                    data[at] * gain, data[at + 1] * gain, data[at + "
        "2] * gain\n                )\n                var seen = _mix(ground"
        ", sky, above)\n                data[at] = seen.r\n                da"
        "ta[at + 1] = seen.g\n                data[at + 2] = seen.b\n    retu"
        "rn _lighting(assets, cube^)\n\n\ndef _mix(a: FloatColor, b: FloatCol"
        'or, t: Float32) -> FloatColor:\n    """Return `a` moved toward `b'
        '` by `t`."""\n    return FloatColor(\n        a.r + (b.r - a.r) *'
        " t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t\n    )\n"
    )
    current = _replace_once(
        current, earlier_0, later_0, "extensions/carla/render_sky.mojo"
    )
    var earlier_1 = (
        "        shade + light.b * silver * day + light.b * Float32(0.05) * d"
        "ay,\n    )\n    var colored = mix_opaque(overcast, lit, cloud)\n    "
        "return mix_opaque(\n        _ground_color(ground),\n        colored,"
        "\n"
    )
    var later_1 = (
        "        shade + light.b * silver * day + light.b * Float32(0.05) * d"
        "ay,\n    )\n    var colored = _mix(overcast, lit, cloud)\n    return"
        " _mix(\n        _ground_color(ground),\n        colored,\n"
    )
    current = _replace_once(
        current, earlier_1, later_1, "extensions/carla/render_sky.mojo"
    )
    var earlier_2 = (
        "    # Overcast: the whole sky goes gray as the cover grows.\n    var"
        " gray = (clear.r + clear.g + clear.b) / 3\n    var overcast = mix_op"
        "aque(\n        clear,\n        FloatColor(gray, gray * 1.02, gray * "
        "1.06),\n"
    )
    var later_2 = (
        "    # Overcast: the whole sky goes gray as the cover grows.\n    var"
        " gray = (clear.r + clear.g + clear.b) / 3\n    var overcast = _mix(\n"
        "        clear,\n        FloatColor(gray, gray * 1.02, gray * 1.06),\n"
    )
    current = _replace_once(
        current, earlier_2, later_2, "extensions/carla/render_sky.mojo"
    )
    var earlier_3 = (
        '    """\n    var up = max(direction.y, 0)\n    var night = mix_op'
        "aque(NIGHT_HORIZON, NIGHT_ZENITH, sqrt(up))\n    var clear = FloatCo"
        "lor(\n        sky.r * gain * day + night.r,\n"
    )
    var later_3 = (
        '    """\n    var up = max(direction.y, 0)\n    var night = _mix(N'
        "IGHT_HORIZON, NIGHT_ZENITH, sqrt(up))\n    var clear = FloatColor(\n"
        "        sky.r * gain * day + night.r,\n"
    )
    current = _replace_once(
        current, earlier_3, later_3, "extensions/carla/render_sky.mojo"
    )
    var earlier_4 = (
        '"""\n\nfrom render.color_math import mix_opaque\nfrom core.assets'
        " import Assets\nfrom core.object3d import Object3D\n"
    )
    var later_4 = (
        '"""\n\nfrom core.assets import Assets\nfrom core.object3d import '
        "Object3D\n"
    )
    current = _replace_once(
        current, earlier_4, later_4, "extensions/carla/render_sky.mojo"
    )
    return current


def restored_render_weather(text: String) raises -> String:
    """Restore the old `render_weather.mojo` helper endpoint.

    Args:
        text: The live module.

    Returns:
        The module before helper extraction.

    Raises:
        Error: An inverse fragment is missing.
    """
    var current = text
    var earlier_0 = "        Float32(0.3) + Float32(0.3) * rain,\n    )\n"
    var later_0 = (
        "        Float32(0.3) + Float32(0.3) * rain,\n    )\n\n\ndef _mix(a: "
        'FloatColor, b: FloatColor, t: Float32) -> FloatColor:\n    """Ret'
        'urn `a` moved toward `b` by `t`."""\n    return FloatColor(\n    '
        "    a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) "
        "* t\n    )\n"
    )
    current = _replace_once(
        current, earlier_0, later_0, "extensions/carla/render_weather.mojo"
    )
    var earlier_1 = (
        "    var warm = kelvin_color(Temperature(kelvin, KELVIN))\n    var gr"
        "ay = _percent(weather.cloudiness) * Float32(0.6)\n    return mix_opa"
        "que(warm, FloatColor(0.9, 0.92, 1.0), gray)\n\n\n"
    )
    var later_1 = (
        "    var warm = kelvin_color(Temperature(kelvin, KELVIN))\n    var gr"
        "ay = _percent(weather.cloudiness) * Float32(0.6)\n    return _mix(wa"
        "rm, FloatColor(0.9, 0.92, 1.0), gray)\n\n\n"
    )
    current = _replace_once(
        current, earlier_1, later_1, "extensions/carla/render_weather.mojo"
    )
    var earlier_2 = (
        '"""\n\nfrom render.color_math import mix_opaque\nfrom extensions.'
        "carla.weather import WeatherParameters\nfrom math.smoothstep import "
        "smoothstep\n"
    )
    var later_2 = (
        '"""\n\nfrom extensions.carla.weather import WeatherParameters\nfr'
        "om math.smoothstep import smoothstep\n"
    )
    current = _replace_once(
        current, earlier_2, later_2, "extensions/carla/render_weather.mojo"
    )
    return current


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
comptime _DISTANCE_AFTER = (
    "e349b4b9f7bdb417d84a9451d769c59f7ce1285a6ac99d887722dbc0ff1466e3"
)
"""The live distance file digest."""
comptime _DISTANCE_BEFORE = (
    "46176387129dd37a5887f3aeec7c96bbb386e4980063cb96f09619832cb09a79"
)
"""The distance file before helper extraction."""
comptime _SKY_AFTER = (
    "19e9c8493ffe16a79d24238b480be0904d8ccd490bcee0435554932b5897bff3"
)
"""The live sky file digest."""
comptime _SKY_BEFORE = (
    "4b99faa687940af925a5cedd09d33d7b44dd7e317f892a1be269ccd8deaedaa7"
)
"""The sky file before helper extraction."""
comptime _WEATHER_AFTER = (
    "4f6fbd3dd6597a05900dd64a4dcc799f2e9ffed0b22be63bc96c2d0a6f1822c4"
)
"""The live weather file digest."""
comptime _WEATHER_BEFORE = (
    "5e2c6ed0db903e2c1dd484d73a100cfb816562655722c69e8461d1079d178460"
)
"""The weather file before helper extraction."""
comptime _INTERVAL_PIN = (
    "ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040"
)
"""The interval provider digest."""
comptime _COLOR_PIN = (
    "328a3e43b19b8ab6120563014d19a121284175444c09732d30dffe74eb416c84"
)
"""The color provider digest."""


def _digest(text: String) -> String:
    """Return the SHA-256 of `text`.

    Args:
        text: The source.

    Returns:
        The digest.
    """
    return sha256_hex(text.as_bytes())


def _kind(path: String, text: String) raises -> Int:
    """Return 1 for the live endpoint and 0 for the old endpoint.

    Args:
        path: One shared-helper consumer.
        text: That consumer's source.

    Returns:
        The endpoint kind. `-1` is neither endpoint.

    Raises:
        Error: `path` is not one of the three consumers.
    """
    var digest = _digest(text)
    if path == _DISTANCE:
        if digest == _DISTANCE_AFTER:
            return 1
        if digest == _DISTANCE_BEFORE:
            return 0
        return -1
    if path == _SKY:
        if digest == _SKY_AFTER:
            return 1
        if digest == _SKY_BEFORE:
            return 0
        return -1
    if path == _WEATHER:
        if digest == _WEATHER_AFTER:
            return 1
        if digest == _WEATHER_BEFORE:
            return 0
        return -1
    raise Error("shared-helper provider: unknown consumer: " + path)


def required_providers(
    paths: List[String], texts: List[String], mut providers: List[String]
) raises:
    """Name the providers a live helper consumer still requires.

    Args:
        paths: The selected consumer paths.
        texts: The source of each consumer, in the same order.
        providers: The required provider paths.

    Raises:
        Error: A consumer is unknown or is neither endpoint.
    """
    var color = False
    var interval = False
    for index in range(len(paths)):
        var kind = _kind(paths[index], texts[index])
        if kind < 0:
            raise Error(
                "shared-helper provider: unknown endpoint: " + paths[index]
            )
        if kind == 0:
            continue
        if paths[index] == _DISTANCE:
            interval = True
        else:
            color = True
    if interval:
        providers.append(_INTERVAL)
    if color:
        providers.append(_COLOR)


def provider_pin(path: String) raises -> String:
    """Return the pinned digest of one helper provider.

    Args:
        path: The interval module or the color module.

    Returns:
        The pinned digest.

    Raises:
        Error: `path` is not one of those providers.
    """
    if path == _INTERVAL:
        return _INTERVAL_PIN
    if path == _COLOR:
        return _COLOR_PIN
    raise Error("shared-helper provider: unknown provider: " + path)
