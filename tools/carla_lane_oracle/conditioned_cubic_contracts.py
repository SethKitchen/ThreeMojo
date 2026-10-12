# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""The exact conditioned-cubic semantic edge for issue #333.

This leaf describes a changed numerical graph, not a legacy equivalence.
It reads no root, stores no verification result, and grants no receipt.
The source owner must bind the complete live source, native witnesses,
primitive provider, theorem, and executing leaf inside its current operation.
Typed adapters are a separate exact edge above this intermediate endpoint.
Historical projection recovers provenance only; it never proves old scalar
bits, expanded stored coefficients, or old enclosures for the new graph.
"""
import hashlib
import json
import sys

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

_EXECUTED_MODULE_CODE = sys._getframe().f_code

LEAF = 'tools/carla_lane_oracle/conditioned_cubic_contracts.py'
MIGRATION = 'tools/carla_lane_oracle/conditioned-cubic-successor.json'
MIGRATION_SHA256 = 'a0cf7af298262796ba1db8292830f683ae2a1c3844e8d8d967fe5f5d4cfa309c'
SOURCE_PATHS = ('extensions/carla/polynomial.mojo',
 'extensions/carla/curve_bounds.mojo',
 'extensions/carla/lane_value_bounds.mojo',
 'extensions/carla/junction_bounds.mojo',
 'extensions/carla/road.mojo',
 'extensions/carla/curve_rounded_arc.mojo')
BEFORE_SHA256 = {'extensions/carla/polynomial.mojo': 'ccbb296800e9b493b0617506b05e51d7ed6ee8ea594b9460bb6c7ff359a0d354',
 'extensions/carla/curve_bounds.mojo': 'a5f662df6bc146010b065341143c75223151289dc0cc633590d96b0a199ab8f5',
 'extensions/carla/lane_value_bounds.mojo': '9028d65fdcb680ec5363f7fc974d8d46532b0f50397d7a348fc16e33821f4121',
 'extensions/carla/junction_bounds.mojo': 'd8b7a6de8e495ab16f0cbe9688459eb544ac9ef6c8ec0c44c952ed5b4743a615',
 'extensions/carla/road.mojo': 'd9b6f60ae0b0b2fe38ef8dbe797a759f3de5e72dc8fb97bff15ca5dfff251db0',
 'extensions/carla/curve_rounded_arc.mojo': '7bc84049fed26cb7b14b4fa4603ee36d55cdeb7055c62df50cf10d6a2ce90745'}
AFTER_SHA256 = {'extensions/carla/polynomial.mojo': '7eadcab8f9148a50644fa9bc9d12affcda8e3361f03151cb4595c6eba257ad07',
 'extensions/carla/curve_bounds.mojo': '48dc6f87cd9ad4da1b16c5781fd7b7994f8394198a0d8c7ab6cdc5e0f142f19b',
 'extensions/carla/lane_value_bounds.mojo': '548ca38dd3bb9ecd8fe8a69cce91f2312c9a2493e4fe7925b609a3d64cb44082',
 'extensions/carla/junction_bounds.mojo': 'c1dadaf7448429f8cf8b43919e80222fbab41d75b501d0b5eed71d18515c12c0',
 'extensions/carla/road.mojo': '4e5857371a9de89c6e41f74e3cdc421760be45603446dd2b2a471f22b53dfd0c',
 'extensions/carla/curve_rounded_arc.mojo': 'd6fbdb466f9e1641f8d3317d03035732883775adfdc46a7913a96178feeb85ec'}
BEFORE_TOKEN_SHA256 = {'extensions/carla/polynomial.mojo': 'd3600fdb1fad0f693d560f56f47c9cf981636279e07ec28d94b73dcb52f96f9b',
 'extensions/carla/curve_bounds.mojo': 'd22b440d4d1d9055701a82fb17a758e64cad1128d041389c653025feab33bec6',
 'extensions/carla/lane_value_bounds.mojo': '58c92f55c0a0e3e5ccdfeedfcbf29eb1040a67db9bb6c7d6d7f857ac5d62b745',
 'extensions/carla/junction_bounds.mojo': 'fa2d376df3050ad4dec11a1ca6fb7abcc6359d8778d043595ede08d66fdc4540',
 'extensions/carla/road.mojo': '8a7ec7dc9c25aba463a47aae9c6bd4bee41cc1f84636efc4da92850afd61a94e',
 'extensions/carla/curve_rounded_arc.mojo': 'e98252c83b51b5421643d388556efcd839ef64dfddb37cef37084d48782642f9'}
AFTER_TOKEN_SHA256 = {'extensions/carla/polynomial.mojo': 'af8d162970677189bcfbd79f878bf34972c46cdc924c48ae235f0da34f21ade5',
 'extensions/carla/curve_bounds.mojo': '800780f5dea1d6aab06269c7b1b285243608ae0cd5b76152d1fcb1c1214bd1c2',
 'extensions/carla/lane_value_bounds.mojo': '234c2bdd3364ba7c66622e4a7d33a469cd498d80b7daf906607879c89868a255',
 'extensions/carla/junction_bounds.mojo': '4f43678a3955ed8ba257df213611626840777884189f3af776459d8365385bd5',
 'extensions/carla/road.mojo': '7893ed53d2fafca05a7b3d3467dd80735711d3bde32f0885373996a5aa7578a7',
 'extensions/carla/curve_rounded_arc.mojo': 'e053b81a90bd4f23f0f815b8ba29b93eae3e7af5264c59b77f2072f1eac7b732'}
EDITS = {'extensions/carla/polynomial.mojo': (('1',
                                       '"""CARLA\'s `geom::CubicPolynomial`: f(x) = a + b x + '
                                       'c x^2 + d x^3.\n'
                                       '\n'
                                       'OpenDRIVE writes lane widths, elevations and lane '
                                       'offsets as cubics in a\n'
                                       'distance ds from the start of their record. CARLA '
                                       'shifts each one to the\n'
                                       "road's own s, so a caller evaluates every record at "
                                       'the same s. The\n'
                                       'coefficients carry mixed units: a is in meters, b has '
                                       'none, c is per\n'
                                       'meter and d is per square meter. They stay plain '
                                       'numbers for that reason.\n'
                                       '"""\n'
                                       '\n'
                                       '\n'
                                       'struct CubicPolynomial(ImplicitlyCopyable):\n'
                                       '    """A cubic in s, shifted so that it reads the '
                                       'road\'s s directly."""\n'
                                       '\n'
                                       '    var a: Float64\n'
                                       '    var b: Float64\n',
                                       '"""CARLA\'s `geom::CubicPolynomial`: f(x) = a + b x + '
                                       'c x^2 + d x^3.\n'
                                       '\n'
                                       'OpenDRIVE writes lane widths, elevations and lane '
                                       'offsets as cubics in a\n'
                                       'distance ds from the start of their record. The record '
                                       'retains its local coefficients and subtracts the '
                                       'record start\n'
                                       'before Horner evaluation. This avoids cancellation at '
                                       'a large road station.\n'
                                       'The coefficients carry mixed units: a is in meters, b '
                                       'has none, c is per\n'
                                       'meter and d is per square meter. They stay plain '
                                       'numbers for that reason.\n'
                                       '"""\n'
                                       '\n'
                                       '\n'
                                       'struct CubicPolynomial(ImplicitlyCopyable):\n'
                                       '    """A local cubic evaluated at a road station or an '
                                       'explicit parameter."""\n'
                                       '\n'
                                       '    var a: Float64\n'
                                       '    var b: Float64\n'),
                                      ('2',
                                       '    ):\n'
                                       '        """Create the cubic of a record that starts at '
                                       '`s`.\n'
                                       '\n'
                                       '        The coefficients are re-expanded about zero, '
                                       'as CARLA does, so\n'
                                       "        `evaluate(x)` equals the record's cubic at `x "
                                       '- s`.\n'
                                       '\n'
                                       '        Args:\n'
                                       '            a: The constant term, in meters.\n',
                                       '    ):\n'
                                       '        """Create the cubic of a record that starts at '
                                       '`s`.\n'
                                       '\n'
                                       '        The original coefficients are stored '
                                       'unchanged. Unlike CARLA\n'
                                       '        1360bb9, evaluation forms the local coordinate '
                                       '`x - s` first.\n'
                                       '        This is a numerical correction, not '
                                       'bit-identical legacy behavior.\n'
                                       '\n'
                                       '        Args:\n'
                                       '            a: The constant term, in meters.\n'),
                                      ('3',
                                       '            d: The cubic term, per square meter.\n'
                                       '            s: Where the record starts along the road, '
                                       'in meters.\n'
                                       '        """\n'
                                       '        self.a = a - b * s + c * s * s - d * s * s * '
                                       's\n'
                                       '        self.b = b - 2 * c * s + 3 * d * s * s\n'
                                       '        self.c = c - 3 * d * s\n'
                                       '        self.d = d\n'
                                       '        self.s = s\n'
                                       '\n',
                                       '            d: The cubic term, per square meter.\n'
                                       '            s: Where the record starts along the road, '
                                       'in meters.\n'
                                       '        """\n'
                                       '        self.a = a\n'
                                       '        self.b = b\n'
                                       '        self.c = c\n'
                                       '        self.d = d\n'
                                       '        self.s = s\n'
                                       '\n'),
                                      ('4',
                                       '        Returns:\n'
                                       '            The value of the cubic.\n'
                                       '        """\n'
                                       '        return self.a + x * (self.b + x * (self.c + x '
                                       '* self.d))\n'
                                       '\n'
                                       '    def tangent(self, x: Float64) -> Float64:\n'
                                       '        """Return df/dx, `CubicPolynomial::Tangent`.\n',
                                       '        Returns:\n'
                                       '            The value of the cubic.\n'
                                       '        """\n'
                                       '        var local = x - self.s\n'
                                       '        return self.a + local * (self.b + local * '
                                       '(self.c + local * self.d))\n'
                                       '\n'
                                       '    def tangent(self, x: Float64) -> Float64:\n'
                                       '        """Return df/dx, '
                                       '`CubicPolynomial::Tangent`.\n'),
                                      ('5',
                                       '        Returns:\n'
                                       '            The slope of the cubic.\n'
                                       '        """\n'
                                       '        return self.b + x * (2 * self.c + x * 3 * '
                                       'self.d)\n',
                                       '        Returns:\n'
                                       '            The slope of the cubic.\n'
                                       '        """\n'
                                       '        var local = x - self.s\n'
                                       '        return self.b + local * (2 * self.c + local * '
                                       '3 * self.d)\n')),
 'extensions/carla/curve_bounds.mojo': (('1',
                                         'def _polynomial_jet(\n'
                                         '    polynomial: CubicPolynomial, s: _Jet, shift: '
                                         'Float64 = 0.0\n'
                                         ') -> _Jet:\n'
                                         '    return (_Jet.constant(polynomial.a) - '
                                         '_Jet.constant(shift)) + s * (\n'
                                         '        _Jet.constant(polynomial.b)\n'
                                         '        + s * (_Jet.constant(polynomial.c) + s * '
                                         '_Jet.constant(polynomial.d))\n'
                                         '    )\n'
                                         '\n'
                                         '\n',
                                         'def _polynomial_jet(\n'
                                         '    polynomial: CubicPolynomial, s: _Jet, shift: '
                                         'Float64 = 0.0\n'
                                         ') -> _Jet:\n'
                                         '    var local = s - _Jet.constant(polynomial.s)\n'
                                         '    return (_Jet.constant(polynomial.a) - '
                                         '_Jet.constant(shift)) + local * (\n'
                                         '        _Jet.constant(polynomial.b)\n'
                                         '        + local * (_Jet.constant(polynomial.c) + '
                                         'local * _Jet.constant(polynomial.d))\n'
                                         '    )\n'
                                         '\n'
                                         '\n'),),
 'extensions/carla/lane_value_bounds.mojo': (('1',
                                              'def _polynomial_value(\n'
                                              '    polynomial: CubicPolynomial, s: _ValueJet, '
                                              'shift: Float64 = 0.0\n'
                                              ') -> _ValueJet:\n'
                                              '    return (\n'
                                              '        _ValueJet.constant(polynomial.a) - '
                                              '_ValueJet.constant(shift)\n'
                                              '    ) + s * (\n'
                                              '        _ValueJet.constant(polynomial.b)\n'
                                              '        + s\n'
                                              '        * (\n'
                                              '            _ValueJet.constant(polynomial.c)\n'
                                              '            + s * '
                                              '_ValueJet.constant(polynomial.d)\n'
                                              '        )\n'
                                              '    )\n'
                                              '\n',
                                              'def _polynomial_value(\n'
                                              '    polynomial: CubicPolynomial, s: _ValueJet, '
                                              'shift: Float64 = 0.0\n'
                                              ') -> _ValueJet:\n'
                                              '    var local = s - '
                                              '_ValueJet.constant(polynomial.s)\n'
                                              '    return (\n'
                                              '        _ValueJet.constant(polynomial.a) - '
                                              '_ValueJet.constant(shift)\n'
                                              '    ) + local * (\n'
                                              '        _ValueJet.constant(polynomial.b)\n'
                                              '        + local\n'
                                              '        * (\n'
                                              '            _ValueJet.constant(polynomial.c)\n'
                                              '            + local * '
                                              '_ValueJet.constant(polynomial.d)\n'
                                              '        )\n'
                                              '    )\n'
                                              '\n'),),
 'extensions/carla/junction_bounds.mojo': (('1',
                                            '"""\n'
                                            '\n'
                                            'from extensions.carla.geometry import ARC, LINE, '
                                            'POLY3, SPIRAL, RoadGeometry\n'
                                            'from extensions.carla.curve_bounds import '
                                            '_lane_jet, _reference_work\n'
                                            'from extensions.carla.lane_value_bounds import '
                                            '_lane_value_bound\n'
                                            'from extensions.carla.curve_interval import '
                                            '_Interval, _Jet, _next_up\n'
                                            'from extensions.carla.lane_refinement import '
                                            '_midpoint\n',
                                            '"""\n'
                                            '\n'
                                            'from extensions.carla.geometry import ARC, LINE, '
                                            'POLY3, SPIRAL, RoadGeometry\n'
                                            'from extensions.carla.curve_bounds import '
                                            '_lane_jet, _polynomial_jet, _reference_work\n'
                                            'from extensions.carla.lane_value_bounds import '
                                            '_lane_value_bound\n'
                                            'from extensions.carla.curve_interval import '
                                            '_Interval, _Jet, _next_up\n'
                                            'from extensions.carla.lane_refinement import '
                                            '_midpoint\n'),
                                           ('2',
                                            'def _polynomial_bounds(\n'
                                            '    p: CubicPolynomial, a: Float64, b: Float64\n'
                                            ') -> Tuple[Float64, Float64, Float64, Float64]:\n'
                                            '    # Bernstein control values bound a cubic and '
                                            'its first two derivatives.\n'
                                            '    var h = b - a\n'
                                            '    var fa = p.evaluate(a)\n'
                                            '    var fb = p.evaluate(b)\n'
                                            '    var da = p.tangent(a)\n'
                                            '    var db = p.tangent(b)\n'
                                            '    var dda = 2.0 * p.c + 6.0 * p.d * a\n'
                                            '    var ddb = 2.0 * p.c + 6.0 * p.d * b\n'
                                            '    # Records are re-expanded about road s. Large '
                                            's can cause cancellation\n'
                                            '    # even for a small local polynomial. Bound '
                                            'Horner error by absolute\n'
                                            '    # coefficient magnitudes, not by the small '
                                            'computed endpoint values.\n'
                                            '    comptime epsilon = 8.0 * '
                                            '2.220446049250313e-16\n'
                                            '    var s = max(abs(a), abs(b))\n'
                                            '    var value_error = epsilon * (\n'
                                            '        abs(p.a) + s * (abs(p.b) + s * (abs(p.c) '
                                            '+ s * abs(p.d)))\n'
                                            '    )\n'
                                            '    var tangent_error = epsilon * (\n'
                                            '        abs(p.b) + s * (2.0 * abs(p.c) + s * 3.0 '
                                            '* abs(p.d))\n'
                                            '    )\n'
                                            '    var second_error = epsilon * (2.0 * abs(p.c) '
                                            '+ s * 6.0 * abs(p.d))\n'
                                            '    return (\n'
                                            '        max(\n'
                                            '            max(abs(fa), abs(fb)),\n'
                                            '            max(abs(fa + h * da / 3.0), abs(fb - '
                                            'h * db / 3.0)),\n'
                                            '        )\n'
                                            '        * (1.0 + epsilon)\n'
                                            '        + value_error\n'
                                            '        + h * tangent_error / 3.0,\n'
                                            '        max(max(abs(da), abs(db)), abs(da + h * '
                                            'dda / 2.0)) * (1.0 + epsilon)\n'
                                            '        + tangent_error\n'
                                            '        + h * second_error / 2.0,\n'
                                            '        max(abs(dda), abs(ddb)) + second_error,\n'
                                            '        value_error,\n'
                                            '    )\n'
                                            '\n'
                                            '\n',
                                            'def _polynomial_bounds(\n'
                                            '    p: CubicPolynomial, a: Float64, b: Float64\n'
                                            ') -> Tuple[Float64, Float64, Float64, Float64]:\n'
                                            '    # Bound the same local Horner graph as the '
                                            'scalar evaluator. The Jet\n'
                                            '    # includes the rounded subtraction of the '
                                            'stored record origin. Its\n'
                                            '    # derivative intervals enclose the exact '
                                            'local polynomial, and its error\n'
                                            '    # encloses the scalar graph (including '
                                            'permitted contraction).\n'
                                            '    var bound = _polynomial_jet(p, '
                                            '_Jet.variable(a, b))\n'
                                            '    return (\n'
                                            '        bound.rounded_value().magnitude(),\n'
                                            '        bound.first.magnitude(),\n'
                                            '        bound.second.magnitude(),\n'
                                            '        bound.error,\n'
                                            '    )\n'
                                            '\n'
                                            '\n'),
                                           ('3',
                                            '    if at < 0 or info_index(road.info.elevations, '
                                            'high) != at:\n'
                                            '        return original\n'
                                            '    ref p = road.info.elevations[at].polynomial\n'
                                            '    var m = _Interval.point(_midpoint(low, '
                                            'high))\n'
                                            '    var a = _Interval.point(p.a)\n'
                                            '    var b = _Interval.point(p.b)\n'
                                            '    var c = _Interval.point(p.c)\n',
                                            '    if at < 0 or info_index(road.info.elevations, '
                                            'high) != at:\n'
                                            '        return original\n'
                                            '    ref p = road.info.elevations[at].polynomial\n'
                                            '    var center = _Interval.point(_midpoint(low, '
                                            'high))\n'
                                            '    var m = center - _Interval.point(p.s)\n'
                                            '    var a = _Interval.point(p.a)\n'
                                            '    var b = _Interval.point(p.b)\n'
                                            '    var c = _Interval.point(p.c)\n'),
                                           ('4',
                                            '        _Interval.point(2.0) * c + m * '
                                            '_Interval.point(3.0) * d\n'
                                            '    )\n'
                                            '    var second = c + _Interval.point(3.0) * m * '
                                            'd\n'
                                            '    var delta = _Interval(low, high) - m\n'
                                            '    var ideal = value + delta * (first + delta * '
                                            '(second + delta * d))\n'
                                            '    var stored = ideal + _Interval(-scalar_error, '
                                            'scalar_error)\n'
                                            '    var lower = max(original.low, stored.low)\n',
                                            '        _Interval.point(2.0) * c + m * '
                                            '_Interval.point(3.0) * d\n'
                                            '    )\n'
                                            '    var second = c + _Interval.point(3.0) * m * '
                                            'd\n'
                                            '    var delta = _Interval(low, high) - center\n'
                                            '    var ideal = value + delta * (first + delta * '
                                            '(second + delta * d))\n'
                                            '    var stored = ideal + _Interval(-scalar_error, '
                                            'scalar_error)\n'
                                            '    var lower = max(original.low, stored.low)\n')),
 'extensions/carla/road.mojo': (('1',
                                 '            return List[Float64]()\n'
                                 '        var offset = info_at(self.info.lane_offsets, '
                                 'low).value().polynomial\n'
                                 '        var q1 = -offset.tangent(low)\n'
                                 '        var q2 = -(offset.c + 3.0 * low * offset.d)\n'
                                 '        var q3 = -offset.d\n'
                                 '        ref lanes = self.sections[section].lanes\n'
                                 '        var id = lanes[lane].id\n',
                                 '            return List[Float64]()\n'
                                 '        var offset = info_at(self.info.lane_offsets, '
                                 'low).value().polynomial\n'
                                 '        var q1 = -offset.tangent(low)\n'
                                 '        var q2 = -(offset.c + 3.0 * (low - offset.s) * '
                                 'offset.d)\n'
                                 '        var q3 = -offset.d\n'
                                 '        ref lanes = self.sections[section].lanes\n'
                                 '        var id = lanes[lane].id\n'),
                                ('2',
                                 '                var width = widths[width_at].polynomial\n'
                                 '                var factor = sign * (0.5 if lanes[i].id == '
                                 'id else 1.0)\n'
                                 '                q1 += factor * width.tangent(low)\n'
                                 '                q2 += factor * (width.c + 3.0 * low * '
                                 'width.d)\n'
                                 '                q3 += factor * width.d\n'
                                 '                done = lanes[i].id == id\n'
                                 '        var point = self._lane_point(section, lane, low)\n',
                                 '                var width = widths[width_at].polynomial\n'
                                 '                var factor = sign * (0.5 if lanes[i].id == '
                                 'id else 1.0)\n'
                                 '                q1 += factor * width.tangent(low)\n'
                                 '                q2 += factor * (width.c + 3.0 * (low - '
                                 'width.s) * width.d)\n'
                                 '                q3 += factor * width.d\n'
                                 '                done = lanes[i].id == id\n'
                                 '        var point = self._lane_point(section, lane, low)\n'),
                                ('3',
                                 '            -q3 * span * span * span * c,\n'
                                 '            point.z - Float64(location.z),\n'
                                 '            elevation.tangent(low) * span,\n'
                                 '            (elevation.c + 3.0 * low * elevation.d) * span * '
                                 'span,\n'
                                 '            elevation.d * span * span * span,\n'
                                 '        ]\n'
                                 '        var scale = span\n',
                                 '            -q3 * span * span * span * c,\n'
                                 '            point.z - Float64(location.z),\n'
                                 '            elevation.tangent(low) * span,\n'
                                 '            (elevation.c + 3.0 * (low - elevation.s) * '
                                 'elevation.d) * span * span,\n'
                                 '            elevation.d * span * span * span,\n'
                                 '        ]\n'
                                 '        var scale = span\n')),
 'extensions/carla/curve_rounded_arc.mojo': (('1',
                                              '\n'
                                              '\n'
                                              'def _rounded_constant(polynomial: '
                                              'CubicPolynomial) -> _RoundedBox:\n'
                                              '    if polynomial.b != 0.0 or polynomial.c != '
                                              '0.0 or polynomial.d != 0.0:\n'
                                              '        return _RoundedBox.unknown()\n'
                                              '    # For finite s, all variable terms are '
                                              'exact zero in either graph.\n'
                                              '    return _RoundedBox.point(polynomial.a)\n'
                                              '\n'
                                              '\n',
                                              '\n'
                                              '\n'
                                              'def _rounded_constant(polynomial: '
                                              'CubicPolynomial) -> _RoundedBox:\n'
                                              '    if (\n'
                                              '        not _rounded_operand(polynomial.s)\n'
                                              '        or polynomial.b != 0.0\n'
                                              '        or polynomial.c != 0.0\n'
                                              '        or polynomial.d != 0.0\n'
                                              '    ):\n'
                                              '        return _RoundedBox.unknown()\n'
                                              '    # The query station and the stored origin '
                                              'must both fit the supported\n'
                                              '    # operand range. Their difference is '
                                              'finite, so every variable term\n'
                                              '    # is exact zero in the conditioned graph.\n'
                                              '    return _RoundedBox.point(polynomial.a)\n'
                                              '\n'
                                              '\n'),)}
EDITS_SHA256 = '704f1ac0b645aa892dacbb980725bafe9b1ca7591703f8351c369e4237758521'
PROVIDER_INPUTS = {'extensions/carla/curve_interval.mojo': 'ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040'}
AUDIT_PROVIDER_SHA256 = {'extensions/carla/curve_rounded_line.mojo': '6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed',
 'extensions/carla/lane_refinement.mojo': '13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737'}
NATIVE_TESTS = ('tests/test_carla_conditioned_polynomial.mojo',)

# These are the reviewed operations, not generalized source normalization.
# Complete endpoint checks and the fixed inverse cover everything else.
GRAPH_SPANS = {
    SOURCE_PATHS[0]: (
        '        self.a = a\n        self.b = b\n        self.c = c\n'
        '        self.d = d\n        self.s = s\n',
        '        var local = x - self.s\n'
        '        return self.a + local * (self.b + local * (self.c + local * self.d))\n',
        '        var local = x - self.s\n'
        '        return self.b + local * (2 * self.c + local * 3 * self.d)\n',
    ),
    SOURCE_PATHS[1]: (
        '    var local = s - _Jet.constant(polynomial.s)\n'
        '    return (_Jet.constant(polynomial.a) - _Jet.constant(shift)) + local * (\n'
        '        _Jet.constant(polynomial.b)\n'
        '        + local * (_Jet.constant(polynomial.c) + local * _Jet.constant(polynomial.d))\n'
        '    )\n',
    ),
    SOURCE_PATHS[2]: (
        '    var local = s - _ValueJet.constant(polynomial.s)\n'
        '    return (\n'
        '        _ValueJet.constant(polynomial.a) - _ValueJet.constant(shift)\n'
        '    ) + local * (\n'
        '        _ValueJet.constant(polynomial.b)\n'
        '        + local\n'
        '        * (\n'
        '            _ValueJet.constant(polynomial.c)\n'
        '            + local * _ValueJet.constant(polynomial.d)\n'
        '        )\n'
        '    )\n',
    ),
    SOURCE_PATHS[3]: (
        '    var bound = _polynomial_jet(p, _Jet.variable(a, b))\n'
        '    return (\n'
        '        bound.rounded_value().magnitude(),\n'
        '        bound.first.magnitude(),\n'
        '        bound.second.magnitude(),\n'
        '        bound.error,\n'
        '    )\n',
        '    var center = _Interval.point(_midpoint(low, high))\n'
        '    var m = center - _Interval.point(p.s)\n',
        '    var delta = _Interval(low, high) - center\n'
        '    var ideal = value + delta * (first + delta * (second + delta * d))\n'
        '    var stored = ideal + _Interval(-scalar_error, scalar_error)\n',
    ),
    SOURCE_PATHS[4]: (
        '        var q2 = -(offset.c + 3.0 * (low - offset.s) * offset.d)\n',
        '                q2 += factor * (width.c + 3.0 * (low - width.s) * width.d)\n',
        '            (elevation.c + 3.0 * (low - elevation.s) * elevation.d) * span * span,\n',
    ),
    SOURCE_PATHS[5]: (
        'def _rounded_constant(polynomial: CubicPolynomial) -> _RoundedBox:\n'
        '    if (\n'
        '        not _rounded_operand(polynomial.s)\n'
        '        or polynomial.b != 0.0\n'
        '        or polynomial.c != 0.0\n'
        '        or polynomial.d != 0.0\n'
        '    ):\n'
        '        return _RoundedBox.unknown()\n',
    ),

}


def require(ok, message):
    """Keep every source obligation active under optimized Python."""
    if not ok:
        raise ValueError('conditioned cubic semantic successor: ' + message)


def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def verify_graph(path, text):
    """Check the explicit current operation obligations before projection.

    Zero-shift Jet/value graphs use the same local subtraction and Horner
    products as the scalar. The unchanged generic Jet bounds every elementary
    rounding and every legal contraction. Nonzero-shift expansions remain
    ideal-only under their existing infinite-error caller contract.
    """
    verify_authority()
    require(path in SOURCE_PATHS and type(text) is str, 'unknown graph source')
    require(set(GRAPH_SPANS) == set(SOURCE_PATHS), 'graph obligation scope changed')
    for index, span in enumerate(GRAPH_SPANS[path]):
        require(text.count(span) == 1,
                'missing or ambiguous current operation: ' + path + ':' + str(index))


def predecessor_source(path, text):
    """Recover historical bytes after checking one sealed semantic endpoint.

    This is an exact provenance inverse. It does not assert that evaluating
    the recovered source agrees with evaluating the current source.
    """
    verify_authority()
    require(path in SOURCE_PATHS and type(text) is str, 'unknown source')
    require(sha(text) == AFTER_SHA256[path]
            and source.token_sha256(text) == AFTER_TOKEN_SHA256[path],
            'unknown complete semantic endpoint: ' + path)
    verify_graph(path, text)
    require(hashlib.sha256(json.dumps(EDITS, sort_keys=True).encode()).hexdigest()
            == EDITS_SHA256, 'semantic inverse inventory changed')
    projected = text
    for name, before, after in reversed(EDITS[path]):
        require(bool(before) and bool(after) and projected.count(after) == 1,
                'missing or ambiguous semantic inverse: ' + path + ':' + name)
        projected = projected.replace(after, before, 1)
    require(sha(projected) == BEFORE_SHA256[path]
            and source.token_sha256(projected) == BEFORE_TOKEN_SHA256[path],
            'semantic inverse endpoint changed: ' + path)
    return projected


def verify_sources(texts):
    """Require one complete old or new scalar-and-certificate graph.

    Mixing a conditioned scalar with an old bound, or the reverse, is unsound.
    A typed API successor must first prove its exact mapping to these six
    complete intermediate endpoints, using the same owned live observations.
    """
    verify_authority()
    require(type(texts) is dict and set(texts) == set(SOURCE_PATHS),
            'incomplete semantic source scope')
    active = []
    for path in SOURCE_PATHS:
        text = texts[path]
        require(type(text) is str, 'source is not text: ' + path)
        if sha(text) == BEFORE_SHA256[path]:
            require(source.token_sha256(text) == BEFORE_TOKEN_SHA256[path],
                    'historical semantic tokens changed: ' + path)
        else:
            predecessor_source(path, text)
            active.append(path)
    require(not active or tuple(active) == SOURCE_PATHS,
            'mixed old/new scalar and certificate graphs')
    return tuple(active)


def edges(paths):
    """Describe a sealed edge without granting source admission."""
    verify_authority()
    require(type(paths) is tuple and paths in ((), SOURCE_PATHS),
            'incomplete semantic edge scope')
    return {path: {'path': path,
                   'before_sha256': BEFORE_SHA256[path],
                   'after_sha256': AFTER_SHA256[path],
                   'before_token_sha256': BEFORE_TOKEN_SHA256[path],
                   'after_token_sha256': AFTER_TOKEN_SHA256[path]}
            for path in paths}


# Complete reviewed proof inputs; native execution remains a separate gate.
BINDING_INPUTS = {'tests/test_carla_conditioned_polynomial.mojo': '03dd1897b7c43e4cfd4f14e595c136753dae139a16cf505ede804f3a417a4273',
 'tools/carla_lane_oracle/conditioned-cubic-successor.json': 'a0cf7af298262796ba1db8292830f683ae2a1c3844e8d8d967fe5f5d4cfa309c',
 'tools/carla_lane_oracle/test_conditioned_cubic_contracts.py': 'e6de36edf8083671416d28f90c129bed042a6e1f9fa2dcbb5b6fc2826f3d2e48',
 'docs/validation/conditioned-cubic-333.md': '20b3e2ddf5d979999cae5f262560e3f3a41bab773346351791a3b355dc0b0a2a',
 'assets/carla/town.xodr': '4130289eab48e8cc3c6cf928a054d6af15566e3cd1e5d6c95ecbe5d84377f797',
 'extensions/carla/curve_interval.mojo': 'ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040'}


def verify_authority():
    """Bind the data namespace to a digest carried in executed function code.

    Physical file identity alone does not detect a late edit of a loaded
    source/test/provider table. The owner invokes this at capture and final
    recheck, without retaining any result or trusting a mutable digest global.
    """
    payload = {name: globals()[name] for name in ('LEAF', 'MIGRATION', 'MIGRATION_SHA256', 'SOURCE_PATHS', 'BEFORE_SHA256', 'AFTER_SHA256', 'BEFORE_TOKEN_SHA256', 'AFTER_TOKEN_SHA256', 'EDITS', 'EDITS_SHA256', 'PROVIDER_INPUTS', 'AUDIT_PROVIDER_SHA256', 'NATIVE_TESTS', 'GRAPH_SPANS', 'BINDING_INPUTS')}
    actual = hashlib.sha256(json.dumps(payload, sort_keys=True,
        separators=(',', ':')).encode('utf-8')).hexdigest()
    if actual != 'bd9663e17970394c5b91dac1f1e0fe43cb421e336793a3044025a611713c6c94':
        raise ValueError('conditioned cubic authority namespace changed')
