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
        "                    data[at] * gain, data[at + 1] * gain, da"
        "ta[at + 2] * gain\n                )\n                var se"
        "en = mix_opaque(ground, sky, above)\n                data[at"
        "] = seen.r\n                data[at + 1] = seen.g\n         "
        "       data[at + 2] = seen.b\n    return _lighting(assets, c"
        "ube^)\n"
    )
    var later_0 = (
        "                    data[at] * gain, data[at + 1] * gain, da"
        "ta[at + 2] * gain\n                )\n                var se"
        "en = _mix(ground, sky, above)\n                data[at] = se"
        "en.r\n                data[at + 1] = seen.g\n               "
        " data[at + 2] = seen.b\n    return _lighting(assets, cube^)"
        "\n\n\ndef _mix(a: FloatColor, b: FloatColor, t: Float32) -> "
        'FloatColor:\n    """Return `a` moved toward `b` by `t`."'
        '""\n    return FloatColor(\n        a.r + (b.r - a.r) * t,'
        " a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t\n    )\n"
    )
    current = _replace_once(
        current, earlier_0, later_0, "extensions/carla/render_sky.mojo"
    )
    var earlier_1 = (
        '        center\'s place on the face, from -1 to 1.\n    ""'
        '"\n    var a: Float32\n    var b: Float32\n    if size > 83'
        "88608:\n        a = texel_ndc(x, size)\n        b = texel_nd"
        "c(y, size)\n    else:\n        a = (Float32(x) + 0.5) / Floa"
        "t32(size) * 2 - 1\n        b = (Float32(y) + 0.5) / Float32("
        "size) * 2 - 1\n    var side = Float32(2) / Float32(size)\n  "
        "  return side * side / pow(1 + a * a + b * b, Float32(1.5))"
        "\n"
    )
    var later_1 = (
        '        center\'s place on the face, from -1 to 1.\n    ""'
        '"\n    var a = (Float32(x) + 0.5) / Float32(size) * 2 - 1\n'
        "    var b = (Float32(y) + 0.5) / Float32(size) * 2 - 1\n    "
        "var side = Float32(2) / Float32(size)\n    return side * sid"
        "e / pow(1 + a * a + b * b, Float32(1.5))\n"
    )
    current = _replace_once(
        current, earlier_1, later_1, "extensions/carla/render_sky.mojo"
    )
    var earlier_2 = (
        '    """Return the solid angle a cube face\'s texel covers.'
        "\n\n    A face above 8388608 texels measures the center in `"
        "Float64`.\n\n    Args:\n        x: The texel's column.\n"
    )
    var later_2 = (
        '    """Return the solid angle a cube face\'s texel covers.'
        "\n\n    Args:\n        x: The texel's column.\n"
    )
    current = _replace_once(
        current, earlier_2, later_2, "extensions/carla/render_sky.mojo"
    )
    var earlier_3 = (
        "        shade + light.b * silver * day + light.b * Float32(0"
        ".05) * day,\n    )\n    var colored = mix_opaque(overcast, l"
        "it, cloud)\n    return mix_opaque(\n        _ground_color(gr"
        "ound),\n        colored,\n"
    )
    var later_3 = (
        "        shade + light.b * silver * day + light.b * Float32(0"
        ".05) * day,\n    )\n    var colored = _mix(overcast, lit, cl"
        "oud)\n    return _mix(\n        _ground_color(ground),\n    "
        "    colored,\n"
    )
    current = _replace_once(
        current, earlier_3, later_3, "extensions/carla/render_sky.mojo"
    )
    var earlier_4 = (
        "    # Overcast: the whole sky goes gray as the cover grows."
        "\n    var gray = (clear.r + clear.g + clear.b) / 3\n    var "
        "overcast = mix_opaque(\n        clear,\n        FloatColor(g"
        "ray, gray * 1.02, gray * 1.06),\n"
    )
    var later_4 = (
        "    # Overcast: the whole sky goes gray as the cover grows."
        "\n    var gray = (clear.r + clear.g + clear.b) / 3\n    var "
        "overcast = _mix(\n        clear,\n        FloatColor(gray, g"
        "ray * 1.02, gray * 1.06),\n"
    )
    current = _replace_once(
        current, earlier_4, later_4, "extensions/carla/render_sky.mojo"
    )
    var earlier_5 = (
        '    """\n    var up = max(direction.y, 0)\n    var night '
        "= mix_opaque(NIGHT_HORIZON, NIGHT_ZENITH, sqrt(up))\n    var"
        " clear = FloatColor(\n        sky.r * gain * day + night.r,"
        "\n"
    )
    var later_5 = (
        '    """\n    var up = max(direction.y, 0)\n    var night '
        "= _mix(NIGHT_HORIZON, NIGHT_ZENITH, sqrt(up))\n    var clear"
        " = FloatColor(\n        sky.r * gain * day + night.r,\n"
    )
    current = _replace_once(
        current, earlier_5, later_5, "extensions/carla/render_sky.mojo"
    )
    var earlier_6 = (
        "from math.noise import ImprovedNoise\nfrom math.smoothstep i"
        "mport smoothstep\nfrom math.utils import texel_ndc\nfrom mat"
        "h.vector3 import Vector3\nfrom objects.sky import Sky\n"
    )
    var later_6 = (
        "from math.noise import ImprovedNoise\nfrom math.smoothstep i"
        "mport smoothstep\nfrom math.vector3 import Vector3\nfrom obj"
        "ects.sky import Sky\n"
    )
    current = _replace_once(
        current, earlier_6, later_6, "extensions/carla/render_sky.mojo"
    )
    var earlier_7 = (
        "\nfrom render.color_math import mix_opaque\nfrom core.assets"
        " import Assets\nfrom core.object3d import Object3D\n"
    )
    var later_7 = (
        "\nfrom core.assets import Assets\nfrom core.object3d import Object3D\n"
    )
    current = _replace_once(
        current, earlier_7, later_7, "extensions/carla/render_sky.mojo"
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
        "        Float32(0.3) + Float32(0.3) * rain,\n    )\n\n\ndef "
        "_mix(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor"
        ':\n    """Return `a` moved toward `b` by `t`."""\n    '
        "return FloatColor(\n        a.r + (b.r - a.r) * t, a.g + (b."
        "g - a.g) * t, a.b + (b.b - a.b) * t\n    )\n"
    )
    current = _replace_once(
        current, earlier_0, later_0, "extensions/carla/render_weather.mojo"
    )
    var earlier_1 = (
        "\n        Returns:\n            The density times the pixels"
        ", in millions, rounded down. Zero\n            when a side i"
        "s below one.\n\n        Raises:\n            Error: If the d"
        "ensity is not a finite number that is not\n                n"
        'egative, or the streak count is above 16777216.\n        "'
        '""\n        if not isfinite(self.density) or not (self.den'
        'sity >= 0):\n            raise Error(\n                "A r'
        'ain density must be a finite number that is not negative"\n'
        "            )\n        if width < 1 or height < 1:\n        "
        "    return 0\n        var pixels = Float64(width) * Float64("
        "height)\n        var count = pixels * Float64(self.density) "
        "/ 1e6\n        if not (count < Float64(MAX_RAIN_STREAKS + 1)"
        '):\n            raise Error("A rain streak count is larger '
        'than this port draws")\n        return Int(count)\n\n    de'
        "f write_to(self, mut writer: Some[Writer]):\n"
    )
    var later_1 = (
        "\n        Returns:\n            The density times the pixels"
        ', in millions, rounded down.\n        """\n        return'
        " Int(self.density * Float32(width * height) / 1e6)\n\n    de"
        "f write_to(self, mut writer: Some[Writer]):\n"
    )
    current = _replace_once(
        current, earlier_1, later_1, "extensions/carla/render_weather.mojo"
    )
    var earlier_2 = (
        "        return self.density > 0\n\n    def streaks(self, wid"
        'th: Int, height: Int) raises -> Int:\n        """Return h'
        "ow many streaks an image of a size gets.\n\n"
    )
    var later_2 = (
        "        return self.density > 0\n\n    def streaks(self, wid"
        'th: Int, height: Int) -> Int:\n        """Return how many'
        " streaks an image of a size gets.\n\n"
    )
    current = _replace_once(
        current, earlier_2, later_2, "extensions/carla/render_weather.mojo"
    )
    var earlier_3 = (
        "    var warm = kelvin_color(Temperature(kelvin, KELVIN))\n  "
        "  var gray = _percent(weather.cloudiness) * Float32(0.6)\n  "
        "  return mix_opaque(warm, FloatColor(0.9, 0.92, 1.0), gray)"
        "\n\n\n"
    )
    var later_3 = (
        "    var warm = kelvin_color(Temperature(kelvin, KELVIN))\n  "
        "  var gray = _percent(weather.cloudiness) * Float32(0.6)\n  "
        "  return _mix(warm, FloatColor(0.9, 0.92, 1.0), gray)\n\n\n"
    )
    current = _replace_once(
        current, earlier_3, later_3, "extensions/carla/render_weather.mojo"
    )
    var earlier_4 = (
        "# Rain streaks per million pixels at a precipitation of 100 "
        "percent.\ncomptime RAIN_STREAKS = Float32(6000)\n# The most "
        "streaks one image draws. A larger count does not finish, and"
        "\n# `Int` of a count past 2^63 is not that count.\ncomptime "
        "MAX_RAIN_STREAKS = 16777216\n# How far a streak leans at ful"
        "l wind.\ncomptime RAIN_LEAN = Angle(18, DEGREE)\n"
    )
    var later_4 = (
        "# Rain streaks per million pixels at a precipitation of 100 "
        "percent.\ncomptime RAIN_STREAKS = Float32(6000)\n# How far a"
        " streak leans at full wind.\ncomptime RAIN_LEAN = Angle(18, "
        "DEGREE)\n"
    )
    current = _replace_once(
        current, earlier_4, later_4, "extensions/carla/render_weather.mojo"
    )
    var earlier_5 = (
        "from render.color_utils import kelvin_color\nfrom render.fra"
        "mebuffer import FloatColor\nfrom std.math import cos, exp, i"
        "sfinite, pow, sin, sqrt\nfrom units.si import (\n    DEGREE,"
        "\n"
    )
    var later_5 = (
        "from render.color_utils import kelvin_color\nfrom render.fra"
        "mebuffer import FloatColor\nfrom std.math import cos, exp, p"
        "ow, sin, sqrt\nfrom units.si import (\n    DEGREE,\n"
    )
    current = _replace_once(
        current, earlier_5, later_5, "extensions/carla/render_weather.mojo"
    )
    var earlier_6 = (
        "\nfrom render.color_math import mix_opaque\nfrom extensions."
        "carla.weather import WeatherParameters\nfrom math.smoothstep"
        " import smoothstep\n"
    )
    var later_6 = (
        "\nfrom extensions.carla.weather import WeatherParameters\nfr"
        "om math.smoothstep import smoothstep\n"
    )
    current = _replace_once(
        current, earlier_6, later_6, "extensions/carla/render_weather.mojo"
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
    "959a2e6bb586f0d10654f5f5bff2af261cab75da75db6e3fdd42b069133c3afc"
)
"""The live sky file digest."""
comptime _SKY_BEFORE = (
    "4b99faa687940af925a5cedd09d33d7b44dd7e317f892a1be269ccd8deaedaa7"
)
"""The sky file before helper extraction."""
comptime _WEATHER_AFTER = (
    "b227b692f690d6614d16f055927ade3b3fdcaf2237b03e5d2ff8df2a28ba3804"
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
