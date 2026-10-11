# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact shared-helper extraction edges (#738), below the source-proof graph.

This leaf proves only four fixed source rewrites and their helper correspondence.
It does not read files, admit a root, qualify native execution or grant receipts.
Owners bind physical providers, regression tests, resolver closure and final reads.
Historical records and the separate #703 consumer ledger remain unchanged.
"""
import hashlib
import sys
import tokenize

if __package__:
    from . import source_contracts as source
    from . import map_station_contracts as station
else:
    import source_contracts as source
    import map_station_contracts as station

_EXECUTED_MODULE_CODE = sys._getframe().f_code

SOURCE_PATHS = ('extensions/carla/curve_distance.mojo',
 'loaders/xml.mojo',
 'extensions/carla/render_sky.mojo',
 'extensions/carla/render_weather.mojo')
BEFORE_SHA256 = {'extensions/carla/curve_distance.mojo': '46176387129dd37a5887f3aeec7c96bbb386e4980063cb96f09619832cb09a79',
 'loaders/xml.mojo': '560daaf80b836fe72069a3100747c38096674219980662d3587e72ed2a480458',
 'extensions/carla/render_sky.mojo': '4b99faa687940af925a5cedd09d33d7b44dd7e317f892a1be269ccd8deaedaa7',
 'extensions/carla/render_weather.mojo': '5e2c6ed0db903e2c1dd484d73a100cfb816562655722c69e8461d1079d178460'}
AFTER_SHA256 = {'extensions/carla/curve_distance.mojo': 'e349b4b9f7bdb417d84a9451d769c59f7ce1285a6ac99d887722dbc0ff1466e3',
 'loaders/xml.mojo': '51d3769e382f9e52f38d9a2b694f50bf61abfd87ab17bbeed7e1f40a33b7f510',
 'extensions/carla/render_sky.mojo': '19e9c8493ffe16a79d24238b480be0904d8ccd490bcee0435554932b5897bff3',
 'extensions/carla/render_weather.mojo': '4f6fbd3dd6597a05900dd64a4dcc799f2e9ffed0b22be63bc96c2d0a6f1822c4'}
BEFORE_TOKEN_SHA256 = {'extensions/carla/curve_distance.mojo': 'fcad8481ac4d5a1d088fd2c51917f111791ea32f44c7595997848593d797385b',
 'loaders/xml.mojo': '45bc22c2c4fe3e7e9ac4a8c166da22e385563fe0bdcd9640517f3ac8c694adeb',
 'extensions/carla/render_sky.mojo': '678091cc7e0804582cbeea464d4d628c430b71fb75807e43ded12e9c8a0362d8',
 'extensions/carla/render_weather.mojo': '1666c0bbff6f1868e41d938c9e0e2b7124b2062247cc56c09a7c94ea0d851159'}
AFTER_TOKEN_SHA256 = {'extensions/carla/curve_distance.mojo': 'db3b5ce370465a8f4089838ec11f8a4ec4cca2ec2bd151acc1160cc962159364',
 'loaders/xml.mojo': '6da831cb85ccf0325aea13d7569b56d4e20402e1ae7704211a9fe6e54f6e14ff',
 'extensions/carla/render_sky.mojo': 'aef0fe5e18e88bbc735cbb372bfa925c517cb1a80241977a53adcf5a71f09233',
 'extensions/carla/render_weather.mojo': 'e45de6f4e05e534ef922e3a42d871ad85e6873f6f57df0ad315e4f413fa880dc'}
EDITS = {'extensions/carla/curve_distance.mojo': (('1',
                                           '"""\n'
                                           '\n'
                                           'from std.math import inf, isfinite, isnan, sqrt\n'
                                           'from std.memory import bitcast\n'
                                           '\n'
                                           '\n'
                                           'def _next_up(value: Float64) -> Float64:\n'
                                           '    # Observe the rounded bits before any following '
                                           'arithmetic. Unlike an\n'
                                           '    # epsilon multiplier, this also handles zero and '
                                           'subnormal results.\n'
                                           '    if isnan(value) or value == inf[DType.float64]():\n'
                                           '        return value\n'
                                           '    if value == 0.0:\n'
                                           '        return bitcast[DType.float64](UInt64(1))\n'
                                           '    var bits = bitcast[DType.uint64](value)\n'
                                           '    if value < 0.0:\n'
                                           '        return bitcast[DType.float64](bits - 1)\n'
                                           '    return bitcast[DType.float64](bits + 1)\n'
                                           '\n'
                                           '\n'
                                           'def _next_down(value: Float64) -> Float64:\n'
                                           '    return -_next_up(-value)\n'
                                           '\n'
                                           '\n',
                                           '"""\n'
                                           '\n'
                                           'from extensions.carla.curve_interval import '
                                           '_next_down, _next_up\n'
                                           'from std.math import inf, isfinite, isnan, sqrt\n'
                                           'from std.memory import bitcast\n'
                                           '\n'
                                           '\n'),),
 'loaders/xml.mojo': (('1',
                       'not validated. Encoding declarations do not change the input encoding.\n'
                       '"""\n'
                       '\n'
                       '# What `XmlDocument.child` returns when there is no such child, and what\n',
                       'not validated. Encoding declarations do not change the input encoding.\n'
                       '"""\n'
                       '\n'
                       'from loaders.utf8 import append_utf8\n'
                       '\n'
                       '# What `XmlDocument.child` returns when there is no such child, and '
                       'what\n'),
                      ('2',
                       '\n'
                       '\n'
                       'def _append_utf8(mut out: List[UInt8], point: Int):\n'
                       '    """Append a code point as UTF-8."""\n'
                       '    if point < 0x80:\n'
                       '        out.append(UInt8(point))\n'
                       '    elif point < 0x800:\n'
                       '        out.append(UInt8(0xC0 | (point >> 6)))\n'
                       '        out.append(UInt8(0x80 | (point & 0x3F)))\n'
                       '    elif point < 0x10000:\n'
                       '        out.append(UInt8(0xE0 | (point >> 12)))\n'
                       '        out.append(UInt8(0x80 | ((point >> 6) & 0x3F)))\n'
                       '        out.append(UInt8(0x80 | (point & 0x3F)))\n'
                       '    else:\n'
                       '        out.append(UInt8(0xF0 | (point >> 18)))\n'
                       '        out.append(UInt8(0x80 | ((point >> 12) & 0x3F)))\n'
                       '        out.append(UInt8(0x80 | ((point >> 6) & 0x3F)))\n'
                       '        out.append(UInt8(0x80 | (point & 0x3F)))\n'
                       '\n'
                       '\n'
                       'def _is_character(point: Int) -> Bool:\n'
                       '    """Return True if a character reference names a character XML '
                       'allows:\n',
                       '\n'
                       '\n'
                       'def _is_character(point: Int) -> Bool:\n'
                       '    """Return True if a character reference names a character XML '
                       'allows:\n'),
                      ('3',
                       '        elif word.startswith("#"):\n'
                       '            var point = self.code_point(word, start)\n'
                       '            _append_utf8(out, point)\n'
                       '        else:\n'
                       '            self.at = start\n',
                       '        elif word.startswith("#"):\n'
                       '            var point = self.code_point(word, start)\n'
                       '            append_utf8(out, point)\n'
                       '        else:\n'
                       '            self.at = start\n')),
 'extensions/carla/render_sky.mojo': (('1',
                                       '"""\n'
                                       '\n'
                                       'from core.assets import Assets\n'
                                       'from core.object3d import Object3D\n',
                                       '"""\n'
                                       '\n'
                                       'from render.color_math import mix_opaque\n'
                                       'from core.assets import Assets\n'
                                       'from core.object3d import Object3D\n'),
                                      ('2',
                                       '    """\n'
                                       '    var up = max(direction.y, 0)\n'
                                       '    var night = _mix(NIGHT_HORIZON, NIGHT_ZENITH, '
                                       'sqrt(up))\n'
                                       '    var clear = FloatColor(\n'
                                       '        sky.r * gain * day + night.r,\n',
                                       '    """\n'
                                       '    var up = max(direction.y, 0)\n'
                                       '    var night = mix_opaque(NIGHT_HORIZON, NIGHT_ZENITH, '
                                       'sqrt(up))\n'
                                       '    var clear = FloatColor(\n'
                                       '        sky.r * gain * day + night.r,\n'),
                                      ('3',
                                       '    # Overcast: the whole sky goes gray as the cover '
                                       'grows.\n'
                                       '    var gray = (clear.r + clear.g + clear.b) / 3\n'
                                       '    var overcast = _mix(\n'
                                       '        clear,\n'
                                       '        FloatColor(gray, gray * 1.02, gray * 1.06),\n',
                                       '    # Overcast: the whole sky goes gray as the cover '
                                       'grows.\n'
                                       '    var gray = (clear.r + clear.g + clear.b) / 3\n'
                                       '    var overcast = mix_opaque(\n'
                                       '        clear,\n'
                                       '        FloatColor(gray, gray * 1.02, gray * 1.06),\n'),
                                      ('4',
                                       '        shade + light.b * silver * day + light.b * '
                                       'Float32(0.05) * day,\n'
                                       '    )\n'
                                       '    var colored = _mix(overcast, lit, cloud)\n'
                                       '    return _mix(\n'
                                       '        _ground_color(ground),\n'
                                       '        colored,\n',
                                       '        shade + light.b * silver * day + light.b * '
                                       'Float32(0.05) * day,\n'
                                       '    )\n'
                                       '    var colored = mix_opaque(overcast, lit, cloud)\n'
                                       '    return mix_opaque(\n'
                                       '        _ground_color(ground),\n'
                                       '        colored,\n'),
                                      ('5',
                                       '                    data[at] * gain, data[at + 1] * gain, '
                                       'data[at + 2] * gain\n'
                                       '                )\n'
                                       '                var seen = _mix(ground, sky, above)\n'
                                       '                data[at] = seen.r\n'
                                       '                data[at + 1] = seen.g\n'
                                       '                data[at + 2] = seen.b\n'
                                       '    return _lighting(assets, cube^)\n'
                                       '\n'
                                       '\n'
                                       'def _mix(a: FloatColor, b: FloatColor, t: Float32) -> '
                                       'FloatColor:\n'
                                       '    """Return `a` moved toward `b` by `t`."""\n'
                                       '    return FloatColor(\n'
                                       '        a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b '
                                       '+ (b.b - a.b) * t\n'
                                       '    )\n',
                                       '                    data[at] * gain, data[at + 1] * gain, '
                                       'data[at + 2] * gain\n'
                                       '                )\n'
                                       '                var seen = mix_opaque(ground, sky, above)\n'
                                       '                data[at] = seen.r\n'
                                       '                data[at + 1] = seen.g\n'
                                       '                data[at + 2] = seen.b\n'
                                       '    return _lighting(assets, cube^)\n')),
 'extensions/carla/render_weather.mojo': (('1',
                                           '"""\n'
                                           '\n'
                                           'from extensions.carla.weather import '
                                           'WeatherParameters\n'
                                           'from math.smoothstep import smoothstep\n',
                                           '"""\n'
                                           '\n'
                                           'from render.color_math import mix_opaque\n'
                                           'from extensions.carla.weather import '
                                           'WeatherParameters\n'
                                           'from math.smoothstep import smoothstep\n'),
                                          ('2',
                                           '    var warm = kelvin_color(Temperature(kelvin, '
                                           'KELVIN))\n'
                                           '    var gray = _percent(weather.cloudiness) * '
                                           'Float32(0.6)\n'
                                           '    return _mix(warm, FloatColor(0.9, 0.92, 1.0), '
                                           'gray)\n'
                                           '\n'
                                           '\n',
                                           '    var warm = kelvin_color(Temperature(kelvin, '
                                           'KELVIN))\n'
                                           '    var gray = _percent(weather.cloudiness) * '
                                           'Float32(0.6)\n'
                                           '    return mix_opaque(warm, FloatColor(0.9, 0.92, '
                                           '1.0), gray)\n'
                                           '\n'
                                           '\n'),
                                          ('3',
                                           '        Float32(0.3) + Float32(0.3) * rain,\n'
                                           '    )\n'
                                           '\n'
                                           '\n'
                                           'def _mix(a: FloatColor, b: FloatColor, t: Float32) -> '
                                           'FloatColor:\n'
                                           '    """Return `a` moved toward `b` by `t`."""\n'
                                           '    return FloatColor(\n'
                                           '        a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, '
                                           'a.b + (b.b - a.b) * t\n'
                                           '    )\n',
                                           '        Float32(0.3) + Float32(0.3) * rain,\n    )\n'))}
PROVIDERS = {'extensions/carla/curve_interval.mojo': 'ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040',
 'loaders/utf8.mojo': 'bb37934501add6d7236cbc0897ffe9dbb5b99d285d5d29f44217693cbc2120e9',
 'render/color_math.mojo': '328a3e43b19b8ab6120563014d19a121284175444c09732d30dffe74eb416c84'}
TESTS = {'tests/test_carla_curve_distance.mojo': 'a5c6b76cff9757ebdfe194b6c2e27e3e1de46583daa3d97f4d3052b9d1f51776',
 'tests/test_carla_curve_distance_fraction.mojo': 'cbf5fbf6f13a98147c4df989bd86ec007851c37738e5555e05405b7f72a82380',
 'tests/test_xml.mojo': '3e8f4193cee7fe65cbbf630cf70f33410e90eadbbf6f9af72f2ddbdc799486b6',
 'tests/test_carla_render_scene.mojo': '71e667f85fbaf24cd5e6d5e3cffa7a369d0fc9a78e5609413e356987e95081a7',
 'tests/test_carla_render_weathers.mojo': '5a66ac764a55f9cec74ed5ca188c3054f28c6544a48900757a6bf892855172ec'}
IMPORTS = {'extensions/carla/curve_distance.mojo': 'from extensions.carla.curve_interval import _next_down, '
                                         '_next_up',
 'loaders/xml.mojo': 'from loaders.utf8 import append_utf8',
 'extensions/carla/render_sky.mojo': 'from render.color_math import mix_opaque',
 'extensions/carla/render_weather.mojo': 'from render.color_math import mix_opaque'}
CALL_COUNTS = {'extensions/carla/curve_distance.mojo': {'_next_down': 2, '_next_up': 2},
 'loaders/xml.mojo': {'append_utf8': 1},
 'extensions/carla/render_sky.mojo': {'mix_opaque': 5},
 'extensions/carla/render_weather.mojo': {'mix_opaque': 1}}


def require(value, message):
    if not value:
        raise ValueError('reviewed shared-helper successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def _tokens(text):
    return [(item.type, item.string) for item in source.tokens(text)
            if item.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER)]


def verify_routing(path, text):
    """Bind the exact import and each direct call, before reversing any source."""
    require(path in SOURCE_PATHS, 'unknown consumer')
    require(text.splitlines().count(IMPORTS[path]) == 1, 'live import changed: ' + path)
    stream = _tokens(text)
    for name, count in CALL_COUNTS[path].items():
        require(sum(item == (tokenize.NAME, name) and
                    stream[index + 1] == (tokenize.OP, '(')
                    for index, item in enumerate(stream[:-1])) == count,
                'live helper call count changed: ' + path + ':' + name)
        require((tokenize.NAME, 'def') not in [stream[index - 1]
                for index, item in enumerate(stream) if index and item == (tokenize.NAME, name)],
                'local helper hides import: ' + path + ':' + name)


def predecessor_source(path, text):
    """Reconstruct one complete old consumer through its unique exact spans."""
    require(path in SOURCE_PATHS and type(text) is str, 'unknown source')
    require(sha(text) == AFTER_SHA256[path] and
            source.token_sha256(text) == AFTER_TOKEN_SHA256[path], 'unknown exact endpoint: ' + path)
    verify_routing(path, text)
    edits = EDITS[path]
    require(tuple(item[0] for item in edits) == tuple(str(i + 1) for i in range(len(edits))),
            'inverse order changed: ' + path)
    for name, before, after in reversed(edits):
        require(bool(before) and bool(after) and text.count(after) == 1,
                'missing or ambiguous inverse: ' + path + ':' + name)
        text = text.replace(after, before, 1)
    require(sha(text) == BEFORE_SHA256[path] and
            source.token_sha256(text) == BEFORE_TOKEN_SHA256[path], 'inverse endpoint changed: ' + path)
    return text


def _helper_tokens(text, name, replacement, docstring):
    """Change only the declared name and the one explicitly bound docstring."""
    declaration = station.declaration(text, name, ())
    stream = _tokens(declaration)
    require(stream[:2] == [(tokenize.NAME, 'def'), (tokenize.NAME, name)],
            'helper declaration owner changed: ' + name)
    stream[1] = (tokenize.NAME, replacement)
    if docstring is not None:
        indices = [i for i, item in enumerate(stream) if item == (tokenize.STRING, docstring)]
        require(len(indices) == 1 and indices[0] > 0 and
                stream[indices[0] - 1][0] == tokenize.INDENT,
                'helper docstring changed: ' + name)
        index = indices[0]
        require(stream[index + 1][0] == tokenize.NEWLINE, 'helper docstring statement changed')
        del stream[index:index + 2]
    return stream


ARITHMETIC_PATHS = ('extensions/carla/curve_distance.mojo', 'loaders/xml.mojo')

PACKAGE_INPUTS = {'extensions/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/carla/__init__.mojo': '13bda95e7b80d111a65052af5508e95af88c7a17871fcf33f3eaf5dc75fd1a2d',
 'loaders/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'render/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479'}

TEST_PATHS = {
    'extensions/carla/curve_distance.mojo': ('tests/test_carla_curve_distance.mojo',
                                           'tests/test_carla_curve_distance_fraction.mojo'),
    'loaders/xml.mojo': ('tests/test_xml.mojo',),
    'extensions/carla/render_sky.mojo': ('tests/test_carla_render_scene.mojo',
                                       'tests/test_carla_render_weathers.mojo'),
    'extensions/carla/render_weather.mojo': ('tests/test_carla_render_scene.mojo',
                                           'tests/test_carla_render_weathers.mojo'),
}


PROVIDER_PATHS = {
    'extensions/carla/curve_distance.mojo': ('extensions/carla/curve_interval.mojo',),
    'loaders/xml.mojo': ('loaders/utf8.mojo',),
    'extensions/carla/render_sky.mojo': ('render/color_math.mojo',),
    'extensions/carla/render_weather.mojo': ('render/color_math.mojo',),
}


def verify_correspondence(texts):
    """Check live helpers against the exact reconstructed local definitions."""
    require(type(texts) is dict, 'helper sources are not an object')
    selected = tuple(path for path in SOURCE_PATHS if path in texts)
    require(bool(selected), 'empty helper source set')
    before = {}
    active = []
    for path in selected:
        text = texts[path]
        if sha(text) == BEFORE_SHA256[path]:
            require(source.token_sha256(text) == BEFORE_TOKEN_SHA256[path], 'old source tokens changed')
        else:
            before[path] = predecessor_source(path, text)
            active.append(path)
    providers = {provider for path in active for provider in PROVIDER_PATHS[path]}
    require(set(texts) == {*selected, *providers}, 'incomplete helper source set')
    if not active:
        return ()
    for path in providers:
        require(sha(texts[path]) == PROVIDERS[path], 'live helper provider changed: ' + path)
    for path, old_name, provider, new_name, old_doc, new_doc in CORRESPONDENCE:
        if path in before:
            require(_helper_tokens(before[path], old_name, new_name, old_doc) ==
                    _helper_tokens(texts[provider], new_name, new_name, new_doc),
                    'helper implementation differs: ' + path + ':' + old_name)
    return tuple(active)


def package_inputs(paths):
    """Return exact existing package bytes on the selected resolution paths."""
    require(set(paths) <= {*SOURCE_PATHS, *PROVIDERS}, 'unknown package scope')
    return {path: digest for path, digest in PACKAGE_INPUTS.items()
            if any(name.startswith(path.removesuffix('__init__.mojo')) for name in paths)}


def edges(paths):
    """Describe the requested fixed edges; descriptors grant no admission."""
    require(set(paths) <= set(SOURCE_PATHS), 'unknown edge scope')
    return {path: {'path': path, 'before_sha256': BEFORE_SHA256[path],
                   'after_sha256': AFTER_SHA256[path],
                   'before_token_sha256': BEFORE_TOKEN_SHA256[path],
                   'after_token_sha256': AFTER_TOKEN_SHA256[path]} for path in paths}


CORRESPONDENCE = (('extensions/carla/curve_distance.mojo',
  '_next_up',
  'extensions/carla/curve_interval.mojo',
  '_next_up',
  None,
  None),
 ('extensions/carla/curve_distance.mojo',
  '_next_down',
  'extensions/carla/curve_interval.mojo',
  '_next_down',
  None,
  None),
 ('loaders/xml.mojo',
  '_append_utf8',
  'loaders/utf8.mojo',
  'append_utf8',
  '"""Append a code point as UTF-8."""',
  '"""Append one code point as UTF-8.\n'
  '\n'
  '    Args:\n'
  '        out: The bytes to extend.\n'
  '        point: A Unicode code point from 0 through 0x10FFFF.\n'
  '    """'),
 ('extensions/carla/render_sky.mojo',
  '_mix',
  'render/color_math.mojo',
  'mix_opaque',
  '"""Return `a` moved toward `b` by `t`."""',
  '"""Return `a` moved toward `b` by `t`, and opaque.\n'
  '\n'
  '    Args:\n'
  '        a: The start color. Its alpha is not kept.\n'
  '        b: The color to move toward.\n'
  "        t: How far. Zero leaves `a`. One takes `b`'s red, green and blue.\n"
  '\n'
  '    Returns:\n'
  '        The mixed color, with alpha one.\n'
  '    """'),
 ('extensions/carla/render_weather.mojo',
  '_mix',
  'render/color_math.mojo',
  'mix_opaque',
  '"""Return `a` moved toward `b` by `t`."""',
  '"""Return `a` moved toward `b` by `t`, and opaque.\n'
  '\n'
  '    Args:\n'
  '        a: The start color. Its alpha is not kept.\n'
  '        b: The color to move toward.\n'
  "        t: How far. Zero leaves `a`. One takes `b`'s red, green and blue.\n"
  '\n'
  '    Returns:\n'
  '        The mixed color, with alpha one.\n'
  '    """'))
