# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""SVG files, from three.js `examples/jsm/loaders/SVGLoader.js`.

`parse_svg` reads the text of an SVG file into `SvgShapePath`s, one for
each element that draws, as three.js's `SVGLoader.parse` does.
`loaders.svg_shapes` has `create_shapes` and `points_to_stroke`, which
turn them into fills and strokes.

**What is read.** The elements three.js reads: `path`, `rect`, `polygon`,
`polyline`, `circle`, `ellipse` and `line` draw; `svg` and `g` carry a
style to their children; `style` holds CSS rules; `defs` hides what it
holds, except its `style` and `defs` children; and `use` draws the
element its `xlink:href` names. Any other element draws nothing, and
its children are read with its parent's style.

**Style.** Each drawing element takes its parent's style, then each
property from an attribute, from a CSS rule that names its class or id,
and from its `style` attribute, in that order. The properties are
three.js's: `fill`, `fill-opacity`, `fill-rule`, `opacity`, `stroke`,
`stroke-opacity`, `stroke-width`, `stroke-linejoin`, `stroke-linecap`,
`stroke-miterlimit` and `visibility`. The fill sets the path's `color`.

**Transforms.** `transform` attributes are read, `translate`, `rotate`,
`scale`, `skewX`, `skewY` and `matrix`, and a `use` element's `x` and
`y`. Each element's transform is the product of its ancestors', and it
moves the element's curves before they are kept.

**Units.** A length with `mm`, `cm`, `in`, `pt`, `pc` or `px` after it is
converted to `default_unit`, with `default_dpi` dots an inch between
pixels and the others: three.js's `defaultUnit` and `defaultDPI`.

**Where this port differs.** three.js hands the text to the browser's
`DOMParser`. This reads it with `loaders.xml`, which refuses a file that
is not well formed; the browser gives a `parsererror` document instead.
The browser also parses CSS; `parse_css_rules` reads the part three.js
uses: rules of selectors and declarations, with comments and at-rules
skipped. A `use` element with only one of `x` and `y` takes the other as
zero; three.js reads it as `NaN`.

**What is refused.** Where three.js throws, or goes on with `NaN` or
`undefined`: a path that draws before it moves; a path command that is
not known, or whose numbers do not fill its last step; a number that is
not one; a `rect` with no `width` or `height`; a `polygon` or
`polyline` with no points; a `use` that names no element, or itself
through another; and a transform with no parenthesis. A fill three.js
cannot read, such as `url(#gradient)`, leaves the path white, as it does
in three.js.
"""

from loaders.svg_path import (
    SvgMatrix,
    SvgShapePath,
    SvgStyle,
    SvgSubPath,
    SvgVector,
    js_remainder,
    same_point,
    svg_rotation,
    svg_scale,
    svg_translation,
    transform_path,
)
from loaders.js_number import js_parse_float
from loaders.xml import XmlDocument, parse_xml
from render.css_color import parse_style
from std.math import acos, cos, isnan, pi, sin, sqrt, tan
from std.pathlib import Path

# The namespace an `xlink:href` attribute is in.
comptime XLINK_NAMESPACE = "http://www.w3.org/1999/xlink"


@fieldwise_init
struct SvgUnit(Equatable, ImplicitlyCopyable, Writable):
    """A unit an SVG length can carry, as a type rather than a bare int.

    `svg_unit_scale` refuses one that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six units there are."""
        return self.value >= SVG_MM.value and self.value <= SVG_PX.value


comptime SVG_MM = SvgUnit(0)
comptime SVG_CM = SvgUnit(1)
comptime SVG_IN = SvgUnit(2)
comptime SVG_PT = SvgUnit(3)
comptime SVG_PC = SvgUnit(4)
comptime SVG_PX = SvgUnit(5)


def svg_unit(name: String) raises -> SvgUnit:
    """Return the unit a suffix names.

    Args:
        name: `mm`, `cm`, `in`, `pt`, `pc` or `px`.

    Returns:
        The unit.

    Raises:
        Error: If the name is none of the six.
    """
    var names: List[String] = ["mm", "cm", "in", "pt", "pc", "px"]
    for index in range(len(names)):  # pragma: no branch
        if names[index] == name:
            return SvgUnit(index)
    raise Error("SVG: a unit that is not known: `" + name + "`")


def _inches(unit: SvgUnit) -> Float64:
    """Return how many of a unit make an inch; not for `px`."""
    if unit == SVG_MM:
        return 25.4
    if unit == SVG_CM:
        return 2.54
    if unit == SVG_IN:
        return 1
    if unit == SVG_PT:
        return 72
    return 6


def svg_unit_scale(
    unit: SvgUnit, default_unit: SvgUnit, dpi: Float64
) raises -> Float64:
    """Return what a length in one unit is multiplied by to give it in
    another, three.js's `unitConversion` table and `defaultDPI`.

    Args:
        unit: The unit the length is written in.
        default_unit: The unit wanted.
        dpi: Pixels an inch.

    Returns:
        The scale.

    Raises:
        Error: If either unit is not valid.
    """
    var refused = not unit.is_valid() or not default_unit.is_valid()
    if refused:
        raise Error("SVG: a unit that is not valid")
    if unit == SVG_PX:
        if default_unit == SVG_PX:
            return 1
        return _inches(default_unit) / dpi
    if default_unit == SVG_PX:
        return 1 / _inches(unit) * dpi
    return _inches(default_unit) / _inches(unit)


def _is_space(byte: UInt8) -> Bool:
    """Return True for an ASCII white space byte, as `\\s` takes it."""
    return byte == 32 or (byte >= 9 and byte <= 13)


def _is_digit(byte: UInt8) -> Bool:
    """Return True for `0` to `9`."""
    return byte >= 48 and byte <= 57


def _digit_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a digit at `i`."""
    return i < len(bytes) and _is_digit(bytes[i])


def _in_number_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a byte a number can hold at `i`."""
    return i < len(bytes) and _in_number(bytes[i])


def _number(text: String) raises -> Float64:
    """Return JavaScript's `Number(text)` for the text a number of
    `parse_floats` collects.

    Raises:
        Error: If it is not a number, where three.js gives NaN.
    """
    try:
        return Float64(text)
    except:
        raise Error("SVG: `" + text + "` is not a number")


def _new_number(
    mut result: List[Float64], mut number: String, mut exponent: String
) raises:
    """End the number being collected, three.js's `newNumber`."""
    if number.byte_length() > 0:
        if exponent.byte_length() == 0:
            result.append(_number(number))
        else:
            result.append(_number(number) * 10.0 ** _number(exponent))
    number = String()
    exponent = String()


def parse_floats(
    input: String, flags: List[Int] = List[Int](), stride: Int = 1
) raises -> List[Float64]:
    """Read the numbers of a path command or a transform, three.js's
    `parseFloats`.

    Numbers are split by white space, a comma, a sign that starts the
    next one, or a second point. At a position in `flags`, counted modulo
    `stride`, a `0` or a `1` is a number of its own, as an arc's flags
    are.

    Args:
        input: The text.
        flags: The positions that are flags.
        stride: How many numbers a step takes.

    Returns:
        The numbers.

    Raises:
        Error: If a character cannot be in a number list, two commas or two
            signs come together, a number has two points, or what is
            collected is not a number.
    """
    comptime SEP = 0
    comptime INT = 1
    comptime FLOAT = 2
    comptime EXP = 3
    var state = SEP
    var seen_comma = True
    var number = String()
    var exponent = String()
    var result = List[Float64]()
    var bytes = input.as_bytes()

    for i in range(len(bytes)):
        var c = bytes[i]
        var current = String(chr(Int(c)))
        var is_space = c == 32 or c == 9 or c == 13 or c == 10
        var is_sign = c == 43 or c == 45
        var is_exp = c == 101 or c == 69
        var is_flag = c == 48 or c == 49
        var at_flag = (
            len(flags) > 0 and is_flag and (len(result) % stride) in flags
        )
        if at_flag:
            state = INT
            number = current
            _new_number(result, number, exponent)
            continue
        if state == SEP:
            if is_space:
                continue
            var starts = _is_digit(c) or is_sign
            if starts:
                state = INT
                number = current
                continue
            if c == 46:
                state = FLOAT
                number = current
                continue
            if c == 44:
                if seen_comma:
                    raise Error("SVG: unexpected `,` at index " + String(i))
                seen_comma = True
        if state == INT:
            if _is_digit(c):
                number += current
                continue
            if c == 46:
                number += current
                state = FLOAT
                continue
            if is_exp:
                state = EXP
                continue
            var lone_sign = is_sign and number.byte_length() == 1
            if lone_sign:
                var first = number.as_bytes()[0]
                var doubled = first == 43 or first == 45
                if doubled:
                    raise Error(
                        "SVG: unexpected `"
                        + current
                        + "` at index "
                        + String(i)
                    )
        if state == FLOAT:
            if _is_digit(c):
                number += current
                continue
            if is_exp:
                state = EXP
                continue
            var second_point = c == 46 and number.endswith(".")
            if second_point:
                raise Error("SVG: unexpected `.` at index " + String(i))
        if state == EXP:
            if _is_digit(c):
                exponent += current
                continue
            if is_sign:
                if exponent.byte_length() == 0:
                    exponent += current
                    continue
                if exponent.byte_length() == 1:
                    var first = exponent.as_bytes()[0]
                    var doubled = first == 43 or first == 45
                    if doubled:
                        raise Error(
                            "SVG: unexpected `"
                            + current
                            + "` at index "
                            + String(i)
                        )
        if is_space:
            _new_number(result, number, exponent)
            state = SEP
            seen_comma = False
        elif c == 44:
            _new_number(result, number, exponent)
            state = SEP
            seen_comma = True
        elif is_sign:
            _new_number(result, number, exponent)
            state = INT
            number = current
        elif c == 46:
            _new_number(result, number, exponent)
            state = FLOAT
            number = current
        else:
            raise Error(
                "SVG: unexpected character "
                + String(Int(c))
                + " at index "
                + String(i)
            )
    _new_number(result, number, exponent)
    return result^


def _in_number(byte: UInt8) -> Bool:
    """Return True for a byte `[+-]?\\d*\\.?\\d+(?:e[+-]?\\d+)?` can hold."""
    return (
        _is_digit(byte)
        or byte == 46
        or byte == 43
        or byte == 45
        or (byte == 101)
    )


def _number_end(bytes: Span[UInt8, _], start: Int) -> Int:
    """Return where the longest match of `[+-]?\\d*\\.?\\d+(?:e[+-]?\\d+)?`
    from `start` ends, or -1 for none."""
    var n = len(bytes)
    var i = start
    var signed = i < n and (bytes[i] == 43 or bytes[i] == 45)
    if signed:
        i += 1
    var digits = 0
    while _digit_at(bytes, i):
        i += 1
        digits += 1
    var fraction = i + 1 < n and bytes[i] == 46 and _is_digit(bytes[i + 1])
    if fraction:
        i += 1
        while _digit_at(bytes, i):
            i += 1
    elif digits == 0:
        return -1
    var exp = i < n and bytes[i] == 101
    if exp:
        var j = i + 1
        var exp_signed = j < n and (bytes[j] == 43 or bytes[j] == 45)
        if exp_signed:
            j += 1
        var exponent = j
        while _digit_at(bytes, j):
            j += 1
        if j > exponent:
            i = j
    return i


def svg_point_pairs(text: String) -> List[String]:
    """Return the coordinate pairs of a `points` attribute, as three.js's
    regular expression finds them.

    A pair is a number, one comma or white space, and a number:
    `([+-]?\\d*\\.?\\d+(?:e[+-]?\\d+)?)(?:,|\\s)(` the same `)`, found
    left to right. So `1, 2` is not a pair, as it is not in three.js.

    Args:
        text: The attribute.

    Returns:
        The numbers' texts, two a pair.
    """
    var out = List[String]()
    var bytes = text.as_bytes()
    var n = len(bytes)
    var s = 0
    while s < n:
        var run = s
        while _in_number_at(bytes, run):
            run += 1
        var no_pair = (
            run == s
            or run >= n
            or not (_is_space(bytes[run]) or bytes[run] == 44)
        )
        if no_pair:
            s += 1
            continue
        if _number_end(bytes, s) != run:
            s += 1
            continue
        var second = _number_end(bytes, run + 1)
        if second < 0:
            s += 1
            continue
        out.append(String(text[byte=s:run]))
        out.append(String(text[byte = run + 1 : second]))
        s = second
    return out^


struct CssRule(Copyable, Movable):
    """One CSS rule: its selector text and its declarations."""

    var selectors: String
    var names: List[String]
    var values: List[String]

    def __init__(out self, var selectors: String):
        """Start a rule with no declarations.

        Args:
            selectors: The text before `{`, trimmed.
        """
        self.selectors = selectors^
        self.names = List[String]()
        self.values = List[String]()


def _strip_comments(text: String) -> String:
    """Return CSS text with its `/* */` comments removed."""
    var out = String()
    var rest = text
    while True:
        var open = rest.find("/*")
        if open < 0:
            out += rest
            break
        out += String(rest[byte=:open])
        var close = rest.find("*/", open + 2)
        if close < 0:
            break
        var tail = String(rest[byte = close + 2 :])
        rest = tail^
    return out^


def parse_css_declarations(text: String) -> CssRule:
    """Read the declarations of a CSS block or a `style` attribute.

    Each is `name: value`, and they are split by `;`. A name is trimmed
    and lowercased, a value trimmed and stripped of `!important`. An
    empty value is dropped, as three.js drops it. A later declaration of
    a name replaces an earlier one.

    Args:
        text: The declarations.

    Returns:
        A rule with no selectors that holds them.
    """
    var rule = CssRule(String())
    # A split gives at least one piece: the loop always runs.
    for piece in _strip_comments(text).split(";"):  # pragma: no branch
        var part = String(piece)
        var colon = part.find(":")
        if colon < 0:
            continue
        var name = String(String(part[byte=:colon]).strip()).lower()
        var value = String(String(part[byte = colon + 1 :]).strip())
        if value.endswith("!important"):
            value = String(
                String(value[byte = : value.byte_length() - 10]).strip()
            )
        var empty = name.byte_length() == 0 or value.byte_length() == 0
        if empty:
            continue
        _set(rule, name, value)
    return rule^


def _set(mut rule: CssRule, name: String, value: String):
    """Set a declaration, replacing one of the same name."""
    for index in range(len(rule.names)):
        if rule.names[index] == name:
            rule.values[index] = value
            return
    rule.names.append(name)
    rule.values.append(value)


def _get(rule: CssRule, name: String) -> String:
    """Return a declaration's value, or empty."""
    for index in range(len(rule.names)):
        if rule.names[index] == name:
            return rule.values[index]
    return String()


def parse_css_rules(text: String) -> List[CssRule]:
    """Read the style rules of a style sheet, the `cssRules` of type one
    three.js reads.

    An at-rule, such as `@media`, is skipped with its block.

    Args:
        text: The style sheet.

    Returns:
        The rules, in order.
    """
    var rules = List[CssRule]()
    var css = _strip_comments(text)
    var at = 0
    while True:
        var open = css.find("{", at)
        if open < 0:
            break
        var head = String(String(css[byte=at:open]).strip())
        var depth = 1
        var i = open + 1
        var bytes = css.as_bytes()
        while depth > 0:
            if i >= len(bytes):
                break
            if bytes[i] == 123:
                depth += 1
            elif bytes[i] == 125:
                depth -= 1
            i += 1
        var body_end = i - 1 if depth == 0 else i
        at = i
        if head.startswith("@"):
            continue
        var rule = parse_css_declarations(
            String(css[byte = open + 1 : body_end])
        )
        rule.selectors = head
        rules.append(rule^)
    return rules^


struct SvgData(Movable):
    """What `parse_svg` gives: the shape paths, and the document, three.js's
    `{ paths, xml }`."""

    var paths: List[SvgShapePath]
    var document: XmlDocument

    def __init__(
        out self, var paths: List[SvgShapePath], var document: XmlDocument
    ):
        """Hold the result.

        Args:
            paths: One shape path for each element that draws.
            document: The parsed file.
        """
        self.paths = paths^
        self.document = document^


def _reflection(a: Float64, b: Float64) -> Float64:
    """Return `b` mirrored about `a`, three.js's `getReflection`."""
    return a - (b - a)


def _svg_angle(ux: Float64, uy: Float64, vx: Float64, vy: Float64) -> Float64:
    """Return the signed angle from one vector to another, three.js's
    `svgAngle`."""
    var dot = ux * vx + uy * vy
    var length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
    var ang = acos(max(Float64(-1), min(Float64(1), dot / length)))
    if ux * vy - uy * vx < 0:
        ang = -ang
    return ang


def parse_arc_command(
    mut path: SvgShapePath,
    rx_in: Float64,
    ry_in: Float64,
    rotation_degrees: Float64,
    large_arc_flag: Float64,
    sweep_flag: Float64,
    start: SvgVector,
    end: SvgVector,
) raises:
    """Draw an arc given by its ends, three.js's `parseArcCommand`: the
    SVG implementation notes' conversion to a center and angles.

    Args:
        path: The shape path to draw on.
        rx_in: The x radius; a line is drawn when it is zero.
        ry_in: The y radius; a line is drawn when it is zero.
        rotation_degrees: The ellipse's turn, in degrees.
        large_arc_flag: One for the larger arc.
        sweep_flag: One for the arc that runs the positive way.
        start: Where the arc starts.
        end: Where it ends.

    Raises:
        Error: If the path has no current outline.
    """
    var flat = rx_in == 0 or ry_in == 0
    if flat:
        path.line_to(end[0], end[1])
        return
    var rotation = rotation_degrees * pi / 180
    var rx = abs(rx_in)
    var ry = abs(ry_in)
    var dx2 = (start[0] - end[0]) / 2.0
    var dy2 = (start[1] - end[1]) / 2.0
    var x1p = cos(rotation) * dx2 + sin(rotation) * dy2
    var y1p = -sin(rotation) * dx2 + cos(rotation) * dy2
    var rxs = rx * rx
    var rys = ry * ry
    var x1ps = x1p * x1p
    var y1ps = y1p * y1p
    var cr = x1ps / rxs + y1ps / rys
    if cr > 1:
        var s = sqrt(cr)
        rx = s * rx
        ry = s * ry
        rxs = rx * rx
        rys = ry * ry
    var dq = rxs * y1ps + rys * x1ps
    var pq = (rxs * rys - dq) / dq
    var q = sqrt(max(Float64(0), pq))
    if large_arc_flag == sweep_flag:
        q = -q
    var cxp = q * rx * y1p / ry
    var cyp = -q * ry * x1p / rx
    var cx = cos(rotation) * cxp - sin(rotation) * cyp + (start[0] + end[0]) / 2
    var cy = sin(rotation) * cxp + cos(rotation) * cyp + (start[1] + end[1]) / 2
    var theta = _svg_angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    var delta = _svg_angle(
        (x1p - cxp) / rx,
        (y1p - cyp) / ry,
        (-x1p - cxp) / rx,
        (-y1p - cyp) / ry,
    )
    delta = js_remainder(delta, pi * 2)
    path._check()
    path.sub_paths[path.current].abs_ellipse(
        cx, cy, rx, ry, theta, theta + delta, sweep_flag == 0, rotation
    )


def _command_start(byte: UInt8) -> Bool:
    """Return True for a letter that starts a path command: any ASCII
    letter but `e` and `E`."""
    var lower = byte | 32
    return lower >= 97 and lower <= 122 and lower != 101


def _check_stride(numbers: List[Float64], stride: Int, command: String) raises:
    """Refuse a command whose numbers do not fill its last step."""
    if len(numbers) % stride != 0:
        raise Error(
            "SVG: path command `"
            + command
            + "` needs its numbers in groups of "
            + String(stride)
        )


def parse_path_data(d: String) raises -> SvgShapePath:
    """Read a `d` attribute into a shape path, three.js's `parsePathNode`.

    Args:
        d: The path data.

    Returns:
        The shape path; one with no outlines for `""` or `none`.

    Raises:
        Error: If the data has no command, a command is not known, a
            command's numbers do not fill its last step, a number is not
            one, or the path draws before it moves.
    """
    var path = SvgShapePath()
    var blank = d == "" or d == "none"
    if blank:
        return path^
    var point = SvgVector(0, 0)
    var control = SvgVector(0, 0)
    var first_point = SvgVector(0, 0)
    var is_first_point = True
    var do_set_first_point = False

    var bytes = d.as_bytes()
    var starts = List[Int]()
    # The data is not empty here: the loop always runs.
    for i in range(len(bytes)):  # pragma: no branch
        if _command_start(bytes[i]):
            starts.append(i)
    if len(starts) == 0:
        raise Error("SVG: path data with no command")
    starts.append(len(bytes))

    # There is a command: the loop always runs.
    for c in range(len(starts) - 1):  # pragma: no branch
        var command = String(chr(Int(bytes[starts[c]])))
        var data = String(
            String(d[byte = starts[c] + 1 : starts[c + 1]]).strip()
        )
        if is_first_point:
            do_set_first_point = True
            is_first_point = False
        var relative = command == command.lower()
        var kind = command.upper()
        var numbers: List[Float64]
        if kind == "A":
            numbers = parse_floats(data, [3, 4], 7)
        else:
            numbers = parse_floats(data)

        if kind == "M":
            _check_stride(numbers, 2, command)
            for j in range(0, len(numbers), 2):
                if relative:
                    point += SvgVector(numbers[j], numbers[j + 1])
                else:
                    point = SvgVector(numbers[j], numbers[j + 1])
                control = point
                if j == 0:
                    path.move_to(point[0], point[1])
                    first_point = point
                else:
                    path.line_to(point[0], point[1])
        elif kind in "HV":
            var axis = 0 if kind == "H" else 1
            for j in range(len(numbers)):
                if relative:
                    point[axis] += numbers[j]
                else:
                    point[axis] = numbers[j]
                control = point
                path.line_to(point[0], point[1])
                var first = j == 0 and do_set_first_point
                if first:
                    first_point = point
        elif kind == "L":
            _check_stride(numbers, 2, command)
            for j in range(0, len(numbers), 2):
                if relative:
                    point += SvgVector(numbers[j], numbers[j + 1])
                else:
                    point = SvgVector(numbers[j], numbers[j + 1])
                control = point
                path.line_to(point[0], point[1])
                var first = j == 0 and do_set_first_point
                if first:
                    first_point = point
        elif kind == "C":
            _check_stride(numbers, 6, command)
            for j in range(0, len(numbers), 6):
                var base = point if relative else SvgVector(0, 0)
                var c1 = base + SvgVector(numbers[j], numbers[j + 1])
                var c2 = base + SvgVector(numbers[j + 2], numbers[j + 3])
                var to = base + SvgVector(numbers[j + 4], numbers[j + 5])
                path.bezier_curve_to(c1[0], c1[1], c2[0], c2[1], to[0], to[1])
                control = c2
                point = to
                var first = j == 0 and do_set_first_point
                if first:
                    first_point = point
        elif kind == "S":
            _check_stride(numbers, 4, command)
            for j in range(0, len(numbers), 4):
                var base = point if relative else SvgVector(0, 0)
                var c2 = base + SvgVector(numbers[j], numbers[j + 1])
                var to = base + SvgVector(numbers[j + 2], numbers[j + 3])
                path.bezier_curve_to(
                    _reflection(point[0], control[0]),
                    _reflection(point[1], control[1]),
                    c2[0],
                    c2[1],
                    to[0],
                    to[1],
                )
                control = c2
                point = to
                var first = j == 0 and do_set_first_point
                if first:
                    first_point = point
        elif kind == "Q":
            _check_stride(numbers, 4, command)
            for j in range(0, len(numbers), 4):
                var base = point if relative else SvgVector(0, 0)
                var c1 = base + SvgVector(numbers[j], numbers[j + 1])
                var to = base + SvgVector(numbers[j + 2], numbers[j + 3])
                path.quadratic_curve_to(c1[0], c1[1], to[0], to[1])
                control = c1
                point = to
                var first = j == 0 and do_set_first_point
                if first:
                    first_point = point
        elif kind == "T":
            _check_stride(numbers, 2, command)
            for j in range(0, len(numbers), 2):
                var base = point if relative else SvgVector(0, 0)
                var rx = _reflection(point[0], control[0])
                var ry = _reflection(point[1], control[1])
                var to = base + SvgVector(numbers[j], numbers[j + 1])
                path.quadratic_curve_to(rx, ry, to[0], to[1])
                control = SvgVector(rx, ry)
                point = to
                var first = j == 0 and do_set_first_point
                if first:
                    first_point = point
        elif kind == "A":
            _check_stride(numbers, 7, command)
            for j in range(0, len(numbers), 7):
                var to = SvgVector(numbers[j + 5], numbers[j + 6])
                if relative:
                    var still = to[0] == 0 and to[1] == 0
                    if still:
                        continue
                    to += point
                elif same_point(to, point):
                    continue
                var start = point
                point = to
                control = point
                parse_arc_command(
                    path,
                    numbers[j],
                    numbers[j + 1],
                    numbers[j + 2],
                    numbers[j + 3],
                    numbers[j + 4],
                    start,
                    point,
                )
                var first = j == 0 and do_set_first_point
                if first:
                    first_point = point
        elif kind == "Z":
            path._check()
            ref sub = path.sub_paths[path.current]
            sub.auto_close = True
            if len(sub.curves) > 0:
                point = first_point
                sub.current_point = point
                is_first_point = True
        else:
            raise Error(
                "SVG: a path command that is not known: `" + command + "`"
            )
        do_set_first_point = False
    return path^


struct _Parser(Movable):
    """Walks the document, three.js's `parse` and its inner functions."""

    var doc: XmlDocument
    var paths: List[SvgShapePath]
    var rules: List[CssRule]
    var stack: List[SvgMatrix]
    var current: SvgMatrix
    var unit: SvgUnit
    var dpi: Float64
    # The `use` elements being drawn, to refuse one that draws itself.
    var uses: List[Int]

    def __init__(out self, var doc: XmlDocument, unit: SvgUnit, dpi: Float64):
        """Start at the root.

        Args:
            doc: The document.
            unit: The unit lengths are wanted in.
            dpi: Pixels an inch.
        """
        self.doc = doc^
        self.paths = List[SvgShapePath]()
        self.rules = List[CssRule]()
        self.stack = List[SvgMatrix]()
        self.current = SvgMatrix()
        self.unit = unit
        self.dpi = dpi
        self.uses = List[Int]()

    def result(deinit self) -> SvgData:
        """Return the paths and the document.

        Returns:
            What `parse_svg` gives.
        """
        return SvgData(self.paths^, self.doc^)

    def length(self, text: String) raises -> Float64:
        """Return a length in the default unit, three.js's
        `parseFloatWithUnits`.

        Args:
            text: The text, with a unit or none.

        Returns:
            The value.

        Raises:
            Error: If it is not a number.
        """
        var unit = SVG_PX
        var body = text
        var names: List[String] = ["mm", "cm", "in", "pt", "pc", "px"]
        for name in names:  # pragma: no branch
            if text.endswith(name):
                unit = svg_unit(name)
                body = String(text[byte = : text.byte_length() - 2])
                break
        var value = js_parse_float(body)
        if isnan(value):
            raise Error("SVG: `" + text + "` is not a number")
        return svg_unit_scale(unit, self.unit, self.dpi) * value

    def attribute_length(self, node: Int, name: String) raises -> Float64:
        """Return an attribute as a length, zero when absent or empty, as
        three.js's `getAttribute(name) || 0` gives.

        Raises:
            Error: If it is not a number.
        """
        var text = self.doc.attribute(node, name)
        if text == "":
            return 0
        return self.length(text)

    def parse_style(self, node: Int, parent: SvgStyle) raises -> SvgStyle:
        """Return an element's style, three.js's `parseStyle`.

        Raises:
            Error: If a number property is not a number.
        """
        var style = parent.copy()
        var sheet = CssRule(String())
        if self.doc.has_attribute(node, "class"):
            for cls in self.doc.attribute(node, "class").split():
                self._merge(sheet, "." + String(cls))
        if self.doc.has_attribute(node, "id"):
            self._merge(sheet, "#" + self.doc.attribute(node, "id"))
        var inline = parse_css_declarations(self.doc.attribute(node, "style"))
        var names: List[String] = [
            "fill",
            "fill-opacity",
            "fill-rule",
            "opacity",
            "stroke",
            "stroke-opacity",
            "stroke-width",
            "stroke-linejoin",
            "stroke-linecap",
            "stroke-miterlimit",
            "visibility",
        ]
        for name in names:  # pragma: no branch
            var values = List[String]()
            if self.doc.has_attribute(node, name):
                values.append(self.doc.attribute(node, name))
            var from_sheet = _get(sheet, name)
            if from_sheet != "":
                values.append(from_sheet)
            var from_inline = _get(inline, name)
            if from_inline != "":
                values.append(from_inline)
            for value in values:
                self._apply(style, name, value)
        return style^

    def _apply(self, mut style: SvgStyle, name: String, value: String) raises:
        """Set one style property from its text."""
        if name == "fill":
            style.fill = value
        elif name == "fill-opacity":
            style.fill_opacity = self._clamp(value)
        elif name == "fill-rule":
            style.fill_rule = value
        elif name == "opacity":
            style.opacity = self._clamp(value)
            style.has_opacity = True
        elif name == "stroke":
            style.stroke = value
        elif name == "stroke-opacity":
            style.stroke_opacity = self._clamp(value)
        elif name == "stroke-width":
            style.stroke_width = max(Float64(0), self.length(value))
        elif name == "stroke-linejoin":
            style.stroke_line_join = value
        elif name == "stroke-linecap":
            style.stroke_line_cap = value
        elif name == "stroke-miterlimit":
            style.stroke_miter_limit = max(Float64(0), self.length(value))
        else:
            style.visibility = value

    def _clamp(self, value: String) raises -> Float64:
        """Return a number clamped to zero through one."""
        return max(Float64(0), min(Float64(1), self.length(value)))

    def _merge(self, mut into: CssRule, selector: String):
        """Add the declarations of every rule for a selector."""
        for rule in self.rules:
            # A split gives at least one piece: the loop always runs.
            for piece in rule.selectors.split(","):  # pragma: no branch
                if String(piece).strip() == selector:
                    for index in range(len(rule.names)):
                        _set(into, rule.names[index], rule.values[index])

    def parse_stylesheet(mut self, node: Int) raises:
        """Keep the rules of a `style` element, three.js's
        `parseCSSStylesheet`.

        Raises:
            Error: If the index names no element.
        """
        self.rules.extend(parse_css_rules(self.doc.text_content(node)))

    def node_transform(mut self, node: Int) raises -> Bool:
        """Push an element's transform, three.js's `getNodeTransform`.

        Returns:
            Whether a transform was pushed.

        Raises:
            Error: If `parse_node_transform` refuses it.
        """
        var name = self.doc.name(node)
        var has_xy = self.doc.has_attribute(
            node, "x"
        ) or self.doc.has_attribute(node, "y")
        var none = not self.doc.has_attribute(node, "transform") and not (
            name == "use" and has_xy
        )
        if none:
            return False
        var transform = self.parse_node_transform(node)
        if len(self.stack) > 0:
            transform = self.stack[len(self.stack) - 1].times(transform)
        self.current = transform.copy()
        self.stack.append(transform^)
        return True

    def parse_node_transform(self, node: Int) raises -> SvgMatrix:
        """Return an element's own transform, three.js's
        `parseNodeTransform`.

        Raises:
            Error: If a transform has no parenthesis, or its numbers are
                not numbers.
        """
        var transform = SvgMatrix()
        var has_xy = self.doc.has_attribute(
            node, "x"
        ) or self.doc.has_attribute(node, "y")
        var use_xy = self.doc.name(node) == "use" and has_xy
        if use_xy:
            var tx = self.attribute_length(node, "x")
            var ty = self.attribute_length(node, "y")
            transform = svg_translation(tx, ty).times(transform)
        if not self.doc.has_attribute(node, "transform"):
            return transform^
        var texts = self.doc.attribute(node, "transform").split(")")
        for t in range(len(texts) - 1, -1, -1):  # pragma: no branch
            var text = String(String(texts[t]).strip())
            if text == "":
                continue
            var open = text.find("(")
            if open <= 0:
                raise Error(
                    "SVG: a transform with no parenthesis: `" + text + "`"
                )
            var type = String(text[byte=:open])
            var array = parse_floats(String(text[byte = open + 1 :]))
            var current = SvgMatrix()
            var count = len(array)
            if type == "translate":
                if count >= 1:
                    var ty = array[1] if count >= 2 else 0
                    current = svg_translation(array[0], ty)
            elif type == "rotate":
                if count >= 1:
                    var angle = array[0] * pi / 180
                    var cx = Float64(0)
                    var cy = Float64(0)
                    if count >= 3:
                        cx = array[1]
                        cy = array[2]
                    current = svg_translation(cx, cy).times(
                        svg_rotation(angle).times(svg_translation(-cx, -cy))
                    )
            elif type == "scale":
                if count >= 1:
                    var sy = array[1] if count >= 2 else array[0]
                    current = svg_scale(array[0], sy)
            elif type == "skewX":
                if count == 1:
                    current = SvgMatrix(
                        1, tan(array[0] * pi / 180), 0, 0, 1, 0, 0, 0, 1
                    )
            elif type == "skewY":
                if count == 1:
                    current = SvgMatrix(
                        1, 0, 0, tan(array[0] * pi / 180), 1, 0, 0, 0, 1
                    )
            elif type == "matrix":
                if count == 6:
                    current = SvgMatrix(
                        array[0],
                        array[2],
                        array[4],
                        array[1],
                        array[3],
                        array[5],
                        0,
                        0,
                        1,
                    )
            transform = current.times(transform)
        return transform^

    def parse_rect(self, node: Int) raises -> SvgShapePath:
        """Return a `rect`'s outline, three.js's `parseRectNode`.

        Raises:
            Error: If `width` or `height` is missing, or a number is not
                one.
        """
        var x = self.attribute_length(node, "x")
        var y = self.attribute_length(node, "y")
        var rx_text = self.doc.attribute(node, "rx")
        if rx_text == "":
            rx_text = self.doc.attribute(node, "ry")
        var ry_text = self.doc.attribute(node, "ry")
        if ry_text == "":
            ry_text = self.doc.attribute(node, "rx")
        var rx = self.length(rx_text) if rx_text != "" else 0
        var ry = self.length(ry_text) if ry_text != "" else 0
        var sized = self.doc.has_attribute(
            node, "width"
        ) and self.doc.has_attribute(node, "height")
        if not sized:
            raise Error("SVG: a `rect` needs a `width` and a `height`")
        var w = self.length(self.doc.attribute(node, "width"))
        var h = self.length(self.doc.attribute(node, "height"))
        var bci = 1 - 0.551915024494
        var round = rx != 0 or ry != 0
        var path = SvgShapePath()
        path.move_to(x + rx, y)
        path.line_to(x + w - rx, y)
        if round:
            path.bezier_curve_to(
                x + w - rx * bci, y, x + w, y + ry * bci, x + w, y + ry
            )
        path.line_to(x + w, y + h - ry)
        if round:
            path.bezier_curve_to(
                x + w,
                y + h - ry * bci,
                x + w - rx * bci,
                y + h,
                x + w - rx,
                y + h,
            )
        path.line_to(x + rx, y + h)
        if round:
            path.bezier_curve_to(
                x + rx * bci, y + h, x, y + h - ry * bci, x, y + h - ry
            )
        path.line_to(x, y + ry)
        if round:
            path.bezier_curve_to(x, y + ry * bci, x + rx * bci, y, x + rx, y)
        return path^

    def parse_poly(self, node: Int, closed: Bool) raises -> SvgShapePath:
        """Return a `polygon`'s or a `polyline`'s outline, three.js's
        `parsePolygonNode` and `parsePolylineNode`.

        Raises:
            Error: If it has no points, or a number is not one.
        """
        var pairs = svg_point_pairs(self.doc.attribute(node, "points"))
        if len(pairs) == 0:
            raise Error("SVG: a `" + self.doc.name(node) + "` with no points")
        var path = SvgShapePath()
        for i in range(0, len(pairs), 2):  # pragma: no branch
            var x = self.length(pairs[i])
            var y = self.length(pairs[i + 1])
            if i == 0:
                path.move_to(x, y)
            else:
                path.line_to(x, y)
        path.sub_paths[path.current].auto_close = closed
        return path^

    def parse_ellipse(self, node: Int, circle: Bool) raises -> SvgShapePath:
        """Return a `circle`'s or an `ellipse`'s outline, three.js's
        `parseCircleNode` and `parseEllipseNode`.

        Raises:
            Error: If a number is not one.
        """
        var x = self.attribute_length(node, "cx")
        var y = self.attribute_length(node, "cy")
        var sub = SvgSubPath()
        if circle:
            var r = self.attribute_length(node, "r")
            sub.abs_arc(x, y, r, 0, pi * 2)
        else:
            var rx = self.attribute_length(node, "rx")
            var ry = self.attribute_length(node, "ry")
            sub.abs_ellipse(x, y, rx, ry, 0, pi * 2)
        var path = SvgShapePath()
        path.sub_paths.append(sub^)
        return path^

    def parse_line(self, node: Int) raises -> SvgShapePath:
        """Return a `line`'s outline, three.js's `parseLineNode`.

        Raises:
            Error: If a number is not one.
        """
        var path = SvgShapePath()
        path.move_to(
            self.attribute_length(node, "x1"), self.attribute_length(node, "y1")
        )
        path.line_to(
            self.attribute_length(node, "x2"), self.attribute_length(node, "y2")
        )
        return path^

    def viewport(self, node: Int) raises -> Int:
        """Return the nearest `svg` element above an element, or -1."""
        var at = self.doc.parent(node)
        while at >= 0:
            if self.doc.name(at) == "svg":
                return at
            at = self.doc.parent(at)
        return -1

    def find_id(self, root: Int, id: String) raises -> Int:
        """Return the first element under `root`, in document order, whose
        `id` is `id`, or -1."""
        for child in self.doc.children(root):
            if self.doc.attribute(child, "id") == id:
                return child
            var found = self.find_id(child, id)
            if found >= 0:
                return found
        return -1

    def xlink_href(self, node: Int) raises -> String:
        """Return a `use` element's `href` in the XLink namespace, the
        prefix found by the `xmlns:` declarations above it, or empty."""
        var at = node
        while at >= 0:
            ref element = self.doc.elements[at]
            for index in range(len(element.attribute_names)):
                var name = element.attribute_names[index]
                var declares = name.startswith("xmlns:") and (
                    element.attribute_values[index] == XLINK_NAMESPACE
                )
                if declares:
                    var prefix = String(name[byte=6:])
                    if self.doc.has_attribute(node, prefix + ":href"):
                        return self.doc.attribute(node, prefix + ":href")
            at = element.parent
        return String()

    def parse_node(mut self, node: Int, parent_style: SvgStyle) raises:
        """Read an element and its children, three.js's `parseNode`.

        Raises:
            Error: For anything the module docstring lists.
        """
        var pushed = self.node_transform(node)
        var name = self.doc.name(node)
        var style = parent_style.copy()
        var is_defs = False
        var draws = False
        var path = SvgShapePath()
        if name == "svg":
            style = self.parse_style(node, style)
        elif name == "g":
            style = self.parse_style(node, style)
        elif name == "style":
            self.parse_stylesheet(node)
        elif name == "path":
            style = self.parse_style(node, style)
            if self.doc.has_attribute(node, "d"):
                var d = self.doc.attribute(node, "d")
                draws = d != "" and d != "none"
                path = parse_path_data(d)
        elif name == "rect":
            style = self.parse_style(node, style)
            path = self.parse_rect(node)
            draws = True
        elif name == "polygon":
            style = self.parse_style(node, style)
            path = self.parse_poly(node, True)
            draws = True
        elif name == "polyline":
            style = self.parse_style(node, style)
            path = self.parse_poly(node, False)
            draws = True
        elif name == "circle":
            style = self.parse_style(node, style)
            path = self.parse_ellipse(node, True)
            draws = True
        elif name == "ellipse":
            style = self.parse_style(node, style)
            path = self.parse_ellipse(node, False)
            draws = True
        elif name == "line":
            style = self.parse_style(node, style)
            path = self.parse_line(node)
            draws = True
        elif name == "defs":
            is_defs = True
        elif name == "use":
            style = self.parse_style(node, style)
            var href = self.xlink_href(node)
            var id = String(href[byte = min(1, href.byte_length()) :])
            var svg = self.viewport(node)
            var used = -1
            var named = svg >= 0 and id != ""
            if named:
                used = self.find_id(svg, id)
            if used < 0:
                raise Error("SVG: a `use` names no element: `" + href + "`")
            if node in self.uses:
                raise Error("SVG: a `use` draws itself: `" + href + "`")
            self.uses.append(node)
            self.parse_node(used, style)
            _ = self.uses.pop()
        if draws:
            var filled = style.fill != "" and style.fill != "none"
            if filled:
                try:
                    path.color = parse_style(style.fill)
                except:
                    pass
            transform_path(path, self.current)
            path.style = style.copy()
            path.node = node
            self.paths.append(path^)
        for child in self.doc.children(node):
            var child_name = self.doc.name(child)
            var hidden = (
                is_defs and child_name != "style" and child_name != "defs"
            )
            if hidden:
                continue
            self.parse_node(child, style)
        if pushed:
            _ = self.stack.pop()
            if len(self.stack) > 0:
                self.current = self.stack[len(self.stack) - 1].copy()
            else:
                self.current = SvgMatrix()


def parse_svg(
    text: String, default_unit: SvgUnit = SVG_PX, default_dpi: Float64 = 90
) raises -> SvgData:
    """Read an SVG file's text, three.js's `SVGLoader.parse`.

    Args:
        text: The file.
        default_unit: The unit lengths come out in, three.js's
            `defaultUnit`.
        default_dpi: Pixels an inch, three.js's `defaultDPI`.

    Returns:
        One shape path for each element that draws, in document order,
        and the document.

    Raises:
        Error: If the unit is not valid, the text is not well-formed XML,
            or for anything the module docstring lists.
    """
    if not default_unit.is_valid():
        raise Error("SVG: a default unit that is not valid")
    var parser = _Parser(parse_xml(text), default_unit, default_dpi)
    parser.parse_node(parser.doc.root(), SvgStyle())
    return parser^.result()


def read_svg(
    path: String, default_unit: SvgUnit = SVG_PX, default_dpi: Float64 = 90
) raises -> SvgData:
    """Read an SVG file.

    Args:
        path: The file.
        default_unit: The unit lengths come out in.
        default_dpi: Pixels an inch.

    Returns:
        What `parse_svg` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_svg`
            refuses.
    """
    return parse_svg(Path(path).read_text(), default_unit, default_dpi)
