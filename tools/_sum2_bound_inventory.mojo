# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live bound inventories.

The curve-bounds file keeps two reviewed spans. The junction-bounds file
keeps seven reviewed spans. Restoring those spans matches the pinned use
digests.
"""

from std.pathlib import Path

from tools._python_json import PY_STR, PyJson
from tools._sum2_guard_inventory import _digest


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"

comptime _CURVE_LIVE_0 = (
    "    _SpiralRootCapture,\n    _SpiralDomainProof,\n    _spiral_proof_"
    "matches,\n    _spiral_proof_branch,\n)\nfrom extensions.carla.spiral"
    "_roundoff_proof import _try_spiral_roundoff_envelope\nfrom extension"
    "s.carla.polynomial import CubicPolynomial\nfrom extensions.carla.roa"
    "d import Road\nfrom extensions.carla.road_info import _info_index_si"
    " as info_index\nfrom math.vector3 import Vector3\nfrom std.math impo"
    "rt ceil, inf, isfinite\n\n\ndef _polynomial_jet(\n    polynomial: Cu"
    "bicPolynomial, s: _Jet, shift: Float64 = 0.0\n) -> _Jet:\n    var lo"
    "cal = s - _Jet.constant(polynomial.s)\n    return (_Jet.constant(pol"
    "ynomial.a) - _Jet.constant(shift)) + local * (\n        _Jet.constan"
    "t(polynomial.b)\n        + local\n        * (_Jet.constant(polynomia"
    "l.c) + local * _Jet.constant(polynomial.d))\n    )\n\n\ndef _square_"
    "jet(value: _Jet) -> _Jet:\n    var result = value * value\n    resul"
    "t.value = value.value.square()\n    return result\n\n"
)

comptime _CURVE_OLD_0 = (
    "    _SpiralRootCapture,\n    _SpiralDomainProof,\n    _spiral_proof_"
    "matches,\n    _spiral_proof_branch,\n)\nfrom extensions.carla.spiral"
    "_roundoff_proof import _try_spiral_roundoff_envelope\nfrom extension"
    "s.carla.polynomial import CubicPolynomial\nfrom extensions.carla.roa"
    "d import Road\nfrom extensions.carla.road_info import info_index\nfr"
    "om math.vector3 import Vector3\nfrom std.math import ceil, inf, isfi"
    "nite\n\n\ndef _polynomial_jet(\n    polynomial: CubicPolynomial, s: "
    "_Jet, shift: Float64 = 0.0\n) -> _Jet:\n    return (_Jet.constant(po"
    "lynomial.a) - _Jet.constant(shift)) + s * (\n        _Jet.constant(p"
    "olynomial.b)\n        + s * (_Jet.constant(polynomial.c) + s * _Jet."
    "constant(polynomial.d))\n    )\n\n\ndef _square_jet(value: _Jet) -> "
    "_Jet:\n    var result = value * value\n    result.value = value.valu"
    "e.square()\n    return result\n\n"
)

comptime _CURVE_LIVE_1 = (
    "    )\n    # Both expressions enclose the same exact real quantity. "
    "Intersection\n    # also retains the original finite enclosure if th"
    "e local difference\n    # overflows even though the weighted express"
    "ion remains bounded.\n    result.value = _intersect_ideal_bounds(res"
    "ult.value, ideal.value)\n    result.first = _intersect_ideal_bounds("
    "result.first, ideal.first)\n    result.second = _intersect_ideal_bou"
    "nds(result.second, ideal.second)\n    var coupled_error = _stored_bl"
    "end_error(rate, one, two)\n    # The concrete producer returns a non"
    "negative allowance or infinity.\n    # Keep the finite fallback; a f"
    "inite negative result is not produced.\n    if isfinite(coupled_erro"
    "r):\n        result.error = min(result.error, coupled_error)\n    re"
    "turn result\n\n\ndef _sample_jet(\n    geometry: RoadGeometry, d: _J"
    "et, index: Int, translation: Vector3\n) -> Tuple[_Jet, _Jet, _Jet]:"
    "\n    var one = geometry.samples[index]\n"
)

comptime _CURVE_OLD_1 = (
    "    )\n    # Both expressions enclose the same exact real quantity. "
    "Intersection\n    # also retains the original finite enclosure if th"
    "e local difference\n    # overflows even though the weighted express"
    "ion remains bounded.\n    result.value = _intersect_ideal_bounds(res"
    "ult.value, ideal.value)\n    result.first = _intersect_ideal_bounds("
    "result.first, ideal.first)\n    result.second = _intersect_ideal_bou"
    "nds(result.second, ideal.second)\n    var coupled_error = _stored_bl"
    "end_error(rate, one, two)\n    if isfinite(coupled_error) and couple"
    "d_error >= 0.0:\n        result.error = min(result.error, coupled_er"
    "ror)\n    return result\n\n\ndef _sample_jet(\n    geometry: RoadGeo"
    "metry, d: _Jet, index: Int, translation: Vector3\n) -> Tuple[_Jet, _"
    "Jet, _Jet]:\n    var one = geometry.samples[index]\n"
)

comptime _JUNCTION_LIVE_0 = (
    "one centimeter. This bounds the supported lane-center model, not the"
    "\nlane surface or the exact OpenDRIVE polynomial behind a sampled ta"
    "ble.\nSeparate numerical allowances cover Float32 rounding, Float64 "
    "cubic\nevaluation, and spiral quadrature. They are not part of the 1"
    " cm chord\ntarget. The returned bounds must fit in finite Float32 co"
    'ordinates.\n"""\n\nfrom extensions.carla.geometry import ARC, LIN'
    "E, POLY3, SPIRAL, RoadGeometry\nfrom extensions.carla.curve_bounds i"
    "mport (\n    _lane_jet,\n    _polynomial_jet,\n    _reference_work,"
    "\n)\nfrom extensions.carla.lane_value_bounds import _lane_value_boun"
    "d\nfrom extensions.carla.curve_interval import _Interval, _Jet, _nex"
    "t_up\nfrom extensions.carla.lane_refinement import _midpoint\nfrom e"
    "xtensions.carla.map_search import MapBuildBudget, _MapBuildWork\nfro"
    "m extensions.carla.map_validation import (\n    _preflight_road_reco"
    "rds,\n    _reserve_lane_boundaries,\n    _reserve_lane_scalars,\n)\n"
    "from extensions.carla.polynomial import CubicPolynomial\nfrom extens"
    "ions.carla.road import Road\nfrom extensions.carla.road_info import "
    "RoadInfo, _info_index_si as info_index\nfrom math.bounds import Box3"
    "\nfrom math.vector3 import Vector3\nfrom std.math import ceil, isfin"
    "ite, sqrt\nfrom std.memory import bitcast\n\ncomptime _CHORD_ERROR ="
    " 0.01\ncomptime _ROUNDING = 4.0 * 1.1920928955078125e-7\ncomptime _M"
    "AX_PIECES = 65536\n\n\ndef _polynomial_bounds(\n    p: CubicPolynomi"
    "al, a: Float64, b: Float64\n) -> Tuple[Float64, Float64, Float64, Fl"
    "oat64]:\n    # Bound the same local Horner graph as the scalar evalu"
    "ator. The Jet\n    # includes the rounded subtraction of the stored "
    "record origin. Its\n    # derivative intervals enclose the exact loc"
    "al polynomial, and its error\n    # encloses the scalar graph (inclu"
    "ding permitted contraction).\n    var bound = _polynomial_jet(p, _Je"
    "t.variable(a, b))\n    return (\n        bound.rounded_value().magni"
    "tude(),\n        bound.first.magnitude(),\n        bound.second.magn"
    "itude(),\n        bound.error,\n    )\n\n\ndef _insert_break(mut val"
    "ues: List[Float64], s: Float64):\n    if s <= values[0] or s >= valu"
    "es[len(values) - 1]:\n        return\n    var lo = 0\n    var hi = l"
    "en(values)\n"
)

comptime _JUNCTION_OLD_0 = (
    "one centimeter. This bounds the supported lane-center model, not the"
    "\nlane surface or the exact OpenDRIVE polynomial behind a sampled ta"
    "ble.\nSeparate numerical allowances cover Float32 rounding, Float64 "
    "cubic\nevaluation, and spiral quadrature. They are not part of the 1"
    " cm chord\ntarget. The returned bounds must fit in finite Float32 co"
    'ordinates.\n"""\n\nfrom extensions.carla.geometry import ARC, LIN'
    "E, POLY3, SPIRAL, RoadGeometry\nfrom extensions.carla.curve_bounds i"
    "mport _lane_jet, _reference_work\nfrom extensions.carla.lane_value_b"
    "ounds import _lane_value_bound\nfrom extensions.carla.curve_interval"
    " import _Interval, _Jet, _next_up\nfrom extensions.carla.lane_refine"
    "ment import _midpoint\nfrom extensions.carla.map_search import MapBu"
    "ildBudget, _MapBuildWork\nfrom extensions.carla.map_validation impor"
    "t (\n    _preflight_road_records,\n    _reserve_lane_boundaries,\n  "
    "  _reserve_lane_scalars,\n)\nfrom extensions.carla.polynomial import"
    " CubicPolynomial\nfrom extensions.carla.road import Road\nfrom exten"
    "sions.carla.road_info import RoadInfo, info_index\nfrom math.bounds "
    "import Box3\nfrom math.vector3 import Vector3\nfrom std.math import "
    "ceil, isfinite, sqrt\nfrom std.memory import bitcast\n\ncomptime _CH"
    "ORD_ERROR = 0.01\ncomptime _ROUNDING = 4.0 * 1.1920928955078125e-7\n"
    "comptime _MAX_PIECES = 65536\n\n\ndef _polynomial_bounds(\n    p: Cu"
    "bicPolynomial, a: Float64, b: Float64\n) -> Tuple[Float64, Float64, "
    "Float64, Float64]:\n    # Bernstein control values bound a cubic and"
    " its first two derivatives.\n    var h = b - a\n    var fa = p.evalu"
    "ate(a)\n    var fb = p.evaluate(b)\n    var da = p.tangent(a)\n    v"
    "ar db = p.tangent(b)\n    var dda = 2.0 * p.c + 6.0 * p.d * a\n    v"
    "ar ddb = 2.0 * p.c + 6.0 * p.d * b\n    # Records are re-expanded ab"
    "out road s. Large s can cause cancellation\n    # even for a small l"
    "ocal polynomial. Bound Horner error by absolute\n    # coefficient m"
    "agnitudes, not by the small computed endpoint values.\n    comptime "
    "epsilon = 8.0 * 2.220446049250313e-16\n    var s = max(abs(a), abs(b"
    "))\n    var value_error = epsilon * (\n        abs(p.a) + s * (abs(p"
    ".b) + s * (abs(p.c) + s * abs(p.d)))\n    )\n    var tangent_error ="
    " epsilon * (\n        abs(p.b) + s * (2.0 * abs(p.c) + s * 3.0 * abs"
    "(p.d))\n    )\n    var second_error = epsilon * (2.0 * abs(p.c) + s "
    "* 6.0 * abs(p.d))\n    return (\n        max(\n            max(abs(f"
    "a), abs(fb)),\n            max(abs(fa + h * da / 3.0), abs(fb - h * "
    "db / 3.0)),\n        )\n        * (1.0 + epsilon)\n        + value_e"
    "rror\n        + h * tangent_error / 3.0,\n        max(max(abs(da), a"
    "bs(db)), abs(da + h * dda / 2.0)) * (1.0 + epsilon)\n        + tange"
    "nt_error\n        + h * second_error / 2.0,\n        max(abs(dda), a"
    "bs(ddb)) + second_error,\n        value_error,\n    )\n\n\ndef _inse"
    "rt_break(mut values: List[Float64], s: Float64):\n    if s <= values"
    "[0] or s >= values[len(values) - 1]:\n        return\n    var lo = 0"
    "\n    var hi = len(values)\n"
)

comptime _JUNCTION_LIVE_1 = (
    "        else:\n            hi = mid\n    if values[lo] != s:\n      "
    "  values.insert(lo, s)\n\n\ndef _record_breaks[T: RoadInfo](mut valu"
    "es: List[Float64], records: List[T]):\n    for record in records:\n "
    "       _insert_break(values, record._distance_si())\n\n\ndef _geomet"
    "ry_rates(\n    geometry: RoadGeometry, a: Float64, b: Float64\n) rai"
    "ses -> Tuple[Float64, Float64, Float64, Bool]:\n    # Bounds on |hea"
    "ding'|, |heading''|, and |reference_position''|.\n    # All geometry"
    " clamps at its end. Sampled geometry is piecewise linear\n    # in p"
    "osition, but its interpolated tangent can still turn.\n"
)

comptime _JUNCTION_OLD_1 = (
    "        else:\n            hi = mid\n    if values[lo] != s:\n      "
    "  values.insert(lo, s)\n\n\ndef _record_breaks[T: RoadInfo](mut valu"
    "es: List[Float64], records: List[T]):\n    for record in records:\n "
    "       _insert_break(values, record.distance())\n\n\ndef _geometry_r"
    "ates(\n    geometry: RoadGeometry, a: Float64, b: Float64\n) raises "
    "-> Tuple[Float64, Float64, Float64, Bool]:\n    # Bounds on |heading"
    "'|, |heading''|, and |reference_position''|.\n    # All geometry cla"
    "mps at its end. Sampled geometry is piecewise linear\n    # in posit"
    "ion, but its interpolated tangent can still turn.\n"
)

comptime _JUNCTION_LIVE_2 = (
    "        1.1e-7 * geometry.length if geometry.kind == SPIRAL else 0.0"
    "\n    )\n    if not rates[3] or wanted > Float64(_MAX_PIECES):\n    "
    "    # Uncertified proposal for a singular tangent or excessive work."
    "\n        # The historical reference chord and offset disk only sugg"
    "est a box;\n        # _certify_junction_span must still prove the ac"
    "tual lane graph fits.\n        # This proposal deliberately has no 1"
    " cm tightness claim.\n        _reserve_reference_point(road, a, work"
    ")\n        var first = (\n            road._directed_point_no_lane_o"
    "ffset_si(a).to_carla().location\n        )\n        _reserve_referen"
    "ce_point(road, b, work)\n        var last = road._directed_point_no_"
    "lane_offset_si(b).to_carla().location\n        var pad = (\n        "
    "    rates[2] * (b - a) * (b - a) / 8.0\n            + q[0]\n        "
    "    + q[3]\n            + quadrature\n            + arc_error\n     "
    "   )\n        out = Box3(first, first)\n"
)

comptime _JUNCTION_OLD_2 = (
    "        1.1e-7 * geometry.length if geometry.kind == SPIRAL else 0.0"
    "\n    )\n    if not rates[3] or wanted > Float64(_MAX_PIECES):\n    "
    "    # Uncertified proposal for a singular tangent or excessive work."
    "\n        # The historical reference chord and offset disk only sugg"
    "est a box;\n        # _certify_junction_span must still prove the ac"
    "tual lane graph fits.\n        # This proposal deliberately has no 1"
    " cm tightness claim.\n        _reserve_reference_point(road, a, work"
    ")\n        var first = road.directed_point_no_lane_offset(a).to_carl"
    "a().location\n        _reserve_reference_point(road, b, work)\n     "
    "   var last = road.directed_point_no_lane_offset(b).to_carla().locat"
    "ion\n        var pad = (\n            rates[2] * (b - a) * (b - a) /"
    " 8.0\n            + q[0]\n            + q[3]\n            + quadratu"
    "re\n            + arc_error\n        )\n        out = Box3(first, fi"
    "rst)\n"
)

comptime _JUNCTION_LIVE_3 = (
    "\ndef _budgeted_pose(\n    road: Road, section: Int, lane: Int, s: F"
    "loat64, mut work: _MapBuildWork\n) raises -> Vector3:\n    _reserve_"
    "lane_scalars(road, section, work, 2)\n    _reserve_reference_point(r"
    "oad, s, work)\n    var terms = _reference_work(road, s, s)\n    work"
    ".term(terms)\n    return road._lane_transform_si(section, lane, s).l"
    "ocation\n\n\ndef _canonical_endpoint(\n    road: Road, section: Int,"
    " lane: Int, s: Float64, mut work: _MapBuildWork\n) raises -> Vector3"
    ":\n    _reserve_lane_scalars(road, section, work)\n    _reserve_refe"
    "rence_point(road, s, work)\n    var point = road._lane_center(sectio"
    "n, lane, s)\n"
)

comptime _JUNCTION_OLD_3 = (
    "\ndef _budgeted_pose(\n    road: Road, section: Int, lane: Int, s: F"
    "loat64, mut work: _MapBuildWork\n) raises -> Vector3:\n    _reserve_"
    "lane_scalars(road, section, work, 2)\n    _reserve_reference_point(r"
    "oad, s, work)\n    var terms = _reference_work(road, s, s)\n    work"
    ".term(terms)\n    return road.lane_transform(section, lane, s).locat"
    "ion\n\n\ndef _canonical_endpoint(\n    road: Road, section: Int, lan"
    "e: Int, s: Float64, mut work: _MapBuildWork\n) raises -> Vector3:\n "
    "   _reserve_lane_scalars(road, section, work)\n    _reserve_referenc"
    "e_point(road, s, work)\n    var point = road._lane_center(section, l"
    "ane, s)\n"
)

comptime _JUNCTION_LIVE_4 = (
    "    work.step()\n    work.term(128)\n    if not isfinite(scalar_erro"
    "r) or scalar_error < 0.0:\n        return original\n    var at = inf"
    "o_index(road.info.elevations, low)\n    if at < 0 or info_index(road"
    ".info.elevations, high) != at:\n        return original\n    ref p ="
    " road.info.elevations[at].polynomial\n    var center = _Interval.poi"
    "nt(_midpoint(low, high))\n    var m = center - _Interval.point(p.s)"
    "\n    var a = _Interval.point(p.a)\n    var b = _Interval.point(p.b)"
    "\n    var c = _Interval.point(p.c)\n    var d = _Interval.point(p.d)"
    "\n    var value = a + m * (b + m * (c + m * d))\n    var first = b +"
    " m * (\n        _Interval.point(2.0) * c + m * _Interval.point(3.0) "
    "* d\n    )\n    var second = c + _Interval.point(3.0) * m * d\n    v"
    "ar delta = _Interval(low, high) - center\n    var ideal = value + de"
    "lta * (first + delta * (second + delta * d))\n    var stored = ideal"
    " + _Interval(-scalar_error, scalar_error)\n    var lower = max(origi"
    "nal.low, stored.low)\n    var upper = min(original.high, stored.high"
    ")\n    if not stored.is_finite() or lower > upper:\n        return o"
    "riginal\n    return _Interval(lower, upper)\n\n"
)

comptime _JUNCTION_OLD_4 = (
    "    work.step()\n    work.term(128)\n    if not isfinite(scalar_erro"
    "r) or scalar_error < 0.0:\n        return original\n    var at = inf"
    "o_index(road.info.elevations, low)\n    if at < 0 or info_index(road"
    ".info.elevations, high) != at:\n        return original\n    ref p ="
    " road.info.elevations[at].polynomial\n    var m = _Interval.point(_m"
    "idpoint(low, high))\n    var a = _Interval.point(p.a)\n    var b = _"
    "Interval.point(p.b)\n    var c = _Interval.point(p.c)\n    var d = _"
    "Interval.point(p.d)\n    var value = a + m * (b + m * (c + m * d))\n"
    "    var first = b + m * (\n        _Interval.point(2.0) * c + m * _I"
    "nterval.point(3.0) * d\n    )\n    var second = c + _Interval.point("
    "3.0) * m * d\n    var delta = _Interval(low, high) - m\n    var idea"
    "l = value + delta * (first + delta * (second + delta * d))\n    var "
    "stored = ideal + _Interval(-scalar_error, scalar_error)\n    var low"
    "er = max(original.low, stored.low)\n    var upper = min(original.hig"
    "h, stored.high)\n    if not stored.is_finite() or lower > upper:\n  "
    "      return original\n    return _Interval(lower, upper)\n\n"
)

comptime _JUNCTION_LIVE_5 = (
    "def _lane_section_box_with_work(\n    road: Road, section: Int, lane"
    ": Int, mut work: _MapBuildWork\n) raises -> Box3:\n    road._check_l"
    "ane(section, lane)\n    var a = road.sections[section].s\n    # Use "
    "the stored endpoint. Re-adding a rounded section length can\n    # o"
    "vershoot it, including for a=10.2 and road.length=50.1.\n    work.st"
    "ep(len(road.sections))\n    var b = min(road._upper_bound_si(a), roa"
    "d.length)\n    if not (isfinite(a) and isfinite(b) and a >= 0.0 and "
    'b >= a):\n        raise Error("A junction lane has an invalid secti'
    'on interval")\n    if a == b:\n        var point = _canonical_endpo'
    "int(road, section, lane, a, work)\n        return Box3(point, point)"
    "\n    var before = work.steps\n    _reserve_lane_boundaries(road, se"
    "ction, work)\n    var boundary_count = work.steps - before\n"
)

comptime _JUNCTION_OLD_5 = (
    "def _lane_section_box_with_work(\n    road: Road, section: Int, lane"
    ": Int, mut work: _MapBuildWork\n) raises -> Box3:\n    road._check_l"
    "ane(section, lane)\n    var a = road.sections[section].s\n    # Use "
    "the stored endpoint. Re-adding a rounded section length can\n    # o"
    "vershoot it, including for a=10.2 and road.length=50.1.\n    work.st"
    "ep(len(road.sections))\n    var b = min(road.upper_bound(a), road.le"
    "ngth)\n    if not (isfinite(a) and isfinite(b) and a >= 0.0 and b >="
    ' a):\n        raise Error("A junction lane has an invalid section i'
    'nterval")\n    if a == b:\n        var point = _canonical_endpoint('
    "road, section, lane, a, work)\n        return Box3(point, point)\n  "
    "  var before = work.steps\n    _reserve_lane_boundaries(road, sectio"
    "n, work)\n    var boundary_count = work.steps - before\n"
)

comptime _JUNCTION_LIVE_6 = (
    "    # canonical lane graph is covered, including both sides of recor"
    "d jumps.\n    for i in range(len(breaks) - 1):\n        work.step()"
    "\n        var start = breaks[i]\n        out.expand_by_point(\n     "
    "       _canonical_endpoint(road, section, lane, start, work)\n      "
    "  )\n        var end = min(breaks[i + 1], b)\n        # Finite, dist"
    "inct sorted cuts and the retained final endpoint b\n        # make e"
    "nd strictly greater than start. Adjacent stations still\n        # n"
    "eed the inner check after both endpoints move into the interior.\n  "
    "      end = bitcast[DType.float64](bitcast[DType.uint64](end) - 1)\n"
    "        start = _next_up(start)\n        if start <= end:\n         "
    "   _certify_junction_span(road, section, lane, start, end, out, work"
    ")\n    out.expand_by_point(_canonical_endpoint(road, section, lane, "
    "b, work))\n    return out\n"
)

comptime _JUNCTION_OLD_6 = (
    "    # canonical lane graph is covered, including both sides of recor"
    "d jumps.\n    for i in range(len(breaks) - 1):\n        work.step()"
    "\n        var start = breaks[i]\n        out.expand_by_point(\n     "
    "       _canonical_endpoint(road, section, lane, start, work)\n      "
    "  )\n        var end = min(breaks[i + 1], b)\n        if end > start"
    ":\n            end = bitcast[DType.float64](bitcast[DType.uint64](en"
    "d) - 1)\n            start = _next_up(start)\n            if start <"
    "= end:\n                _certify_junction_span(\n                   "
    " road, section, lane, start, end, out, work\n                )\n    "
    "out.expand_by_point(_canonical_endpoint(road, section, lane, b, work"
    "))\n    return out\n"
)


def _fail(message: String) raises:
    """Raise a bound-inventory error.

    Args:
        message: The failure text.

    Raises:
        Error: A live bound inventory changed.
    """
    raise Error(message)


def _message(module: String) -> String:
    """Return the inventory failure for `module`.

    Args:
        module: The caller module.

    Returns:
        The failure text.
    """
    return "global protected-helper use/import inventory changed: " + module


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`.

    Args:
        text: The source.
        needle: The exact byte sequence.

    Returns:
        The number of non-overlapping matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def _curve_live(index: Int) -> String:
    """Return one live curve-bounds span.

    Args:
        index: The span number.

    Returns:
        The live text.
    """
    if index == 0:
        return _CURVE_LIVE_0
    return _CURVE_LIVE_1


def _curve_old(index: Int) -> String:
    """Return one pinned curve-bounds span.

    Args:
        index: The span number.

    Returns:
        The pinned text.
    """
    if index == 0:
        return _CURVE_OLD_0
    return _CURVE_OLD_1


def _junction_live(index: Int) -> String:
    """Return one live junction-bounds span.

    Args:
        index: The span number.

    Returns:
        The live text.
    """
    if index == 0:
        return _JUNCTION_LIVE_0
    if index == 1:
        return _JUNCTION_LIVE_1
    if index == 2:
        return _JUNCTION_LIVE_2
    if index == 3:
        return _JUNCTION_LIVE_3
    if index == 4:
        return _JUNCTION_LIVE_4
    if index == 5:
        return _JUNCTION_LIVE_5
    return _JUNCTION_LIVE_6


def _junction_old(index: Int) -> String:
    """Return one pinned junction-bounds span.

    Args:
        index: The span number.

    Returns:
        The pinned text.
    """
    if index == 0:
        return _JUNCTION_OLD_0
    if index == 1:
        return _JUNCTION_OLD_1
    if index == 2:
        return _JUNCTION_OLD_2
    if index == 3:
        return _JUNCTION_OLD_3
    if index == 4:
        return _JUNCTION_OLD_4
    if index == 5:
        return _JUNCTION_OLD_5
    return _JUNCTION_OLD_6


def _apply(source: String, module: String, curve: Bool) raises -> String:
    """Restore the reviewed spans in `source`.

    Args:
        source: The live module.
        module: The module name used in a failure.
        curve: True for the curve-bounds spans.

    Returns:
        The restored source.

    Raises:
        Error: A reviewed span moved.
    """
    var current = source
    if curve:
        var index = 0
        while index < 2:
            var span = _curve_live(index)
            var pinned = _curve_old(index)
            if _count(current, span) != 1:
                _fail(_message(module))
            current = current.replace(span, pinned)
            index += 1
        return current
    var index = 0
    while index < 7:
        var span = _junction_live(index)
        var pinned = _junction_old(index)
        if _count(current, span) != 1:
            _fail(_message(module))
        current = current.replace(span, pinned)
        index += 1
    return current


def _check(base: String, doc: PyJson, module: String, curve: Bool) raises:
    """Require one restored module to keep its pinned use digest.

    Args:
        base: The repository root.
        doc: The pin document.
        module: The caller module.
        curve: True for the curve-bounds spans.

    Raises:
        Error: The pin or the restored digest changed.
    """
    var path = "extensions/carla/" + module + ".mojo"
    var inventory = doc.at(doc.root, "protected_inventory")
    var pinned = doc.at(inventory, path)
    if doc.kind(pinned) != PY_STR:
        _fail(_message(module))
    var source = Path(base + "/" + path).read_text()
    var restored = _apply(source, module, curve)
    if _digest(restored) != doc.text(pinned):
        _fail(_message(module))


def sum2_bound_inventory(root: String) raises:
    """Require the live curve-bounds and junction-bounds inventories.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed span or a pinned use digest changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    _check(base, doc, "curve_bounds", True)
    _check(base, doc, "junction_bounds", False)
