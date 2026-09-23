# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CSS color strings, from three.js `Color.setStyle`, `Color.getStyle`,
`Color.getHexString` and `Color.NAMES`.

`parse_style` reads every form three.js's `setStyle` reads, with its
regular expressions written out by hand:

- `rgb(255, 0, 0)` and `rgba(255, 0, 0, 0.5)`, whole numbers capped at 255;
- `rgb(100%, 0%, 0%)` and `rgba(...)`, whole percentages capped at 100;
- `hsl(120, 50%, 50%)` and `hsla(...)`, where each number can have a
  fraction;
- `#ff0` and `#ff0000`;
- the 148 CSS color names in `COLOR_NAMES`, in any case.

The function name must be lowercase, and it must touch its parenthesis.
Text after the closing parenthesis is ignored, as three.js's expression
ignores it. Spaces are the ASCII ones: a space, a tab and the line breaks.

The numbers describe a color in `space`, sRGB unless told otherwise, as
three.js's `setStyle` defaults to. They are decoded to the linear working
space. The alpha of `rgba` and `hsla` is read and then dropped, as three.js
drops it: three.js's `Color` holds no alpha, and the color comes back
opaque.

three.js warns and leaves the color unchanged for a string it cannot read.
Here that string is refused.
"""

from render.framebuffer import FloatColor
from render.srgb import LINEAR, SRGB, ColorSpace, linear_to_srgb, srgb_to_linear
from std.math import floor

# The CSS color names and their sRGB values, three.js's `Color.NAMES`, in
# its order.
comptime COLOR_NAMES: Array[StaticString, 148] = [
    "aliceblue",
    "antiquewhite",
    "aqua",
    "aquamarine",
    "azure",
    "beige",
    "bisque",
    "black",
    "blanchedalmond",
    "blue",
    "blueviolet",
    "brown",
    "burlywood",
    "cadetblue",
    "chartreuse",
    "chocolate",
    "coral",
    "cornflowerblue",
    "cornsilk",
    "crimson",
    "cyan",
    "darkblue",
    "darkcyan",
    "darkgoldenrod",
    "darkgray",
    "darkgreen",
    "darkgrey",
    "darkkhaki",
    "darkmagenta",
    "darkolivegreen",
    "darkorange",
    "darkorchid",
    "darkred",
    "darksalmon",
    "darkseagreen",
    "darkslateblue",
    "darkslategray",
    "darkslategrey",
    "darkturquoise",
    "darkviolet",
    "deeppink",
    "deepskyblue",
    "dimgray",
    "dimgrey",
    "dodgerblue",
    "firebrick",
    "floralwhite",
    "forestgreen",
    "fuchsia",
    "gainsboro",
    "ghostwhite",
    "gold",
    "goldenrod",
    "gray",
    "green",
    "greenyellow",
    "grey",
    "honeydew",
    "hotpink",
    "indianred",
    "indigo",
    "ivory",
    "khaki",
    "lavender",
    "lavenderblush",
    "lawngreen",
    "lemonchiffon",
    "lightblue",
    "lightcoral",
    "lightcyan",
    "lightgoldenrodyellow",
    "lightgray",
    "lightgreen",
    "lightgrey",
    "lightpink",
    "lightsalmon",
    "lightseagreen",
    "lightskyblue",
    "lightslategray",
    "lightslategrey",
    "lightsteelblue",
    "lightyellow",
    "lime",
    "limegreen",
    "linen",
    "magenta",
    "maroon",
    "mediumaquamarine",
    "mediumblue",
    "mediumorchid",
    "mediumpurple",
    "mediumseagreen",
    "mediumslateblue",
    "mediumspringgreen",
    "mediumturquoise",
    "mediumvioletred",
    "midnightblue",
    "mintcream",
    "mistyrose",
    "moccasin",
    "navajowhite",
    "navy",
    "oldlace",
    "olive",
    "olivedrab",
    "orange",
    "orangered",
    "orchid",
    "palegoldenrod",
    "palegreen",
    "paleturquoise",
    "palevioletred",
    "papayawhip",
    "peachpuff",
    "peru",
    "pink",
    "plum",
    "powderblue",
    "purple",
    "rebeccapurple",
    "red",
    "rosybrown",
    "royalblue",
    "saddlebrown",
    "salmon",
    "sandybrown",
    "seagreen",
    "seashell",
    "sienna",
    "silver",
    "skyblue",
    "slateblue",
    "slategray",
    "slategrey",
    "snow",
    "springgreen",
    "steelblue",
    "tan",
    "teal",
    "thistle",
    "tomato",
    "turquoise",
    "violet",
    "wheat",
    "white",
    "whitesmoke",
    "yellow",
    "yellowgreen",
]
comptime COLOR_NAME_HEXES: Array[Int, 148] = [
    0xF0F8FF,
    0xFAEBD7,
    0x00FFFF,
    0x7FFFD4,
    0xF0FFFF,
    0xF5F5DC,
    0xFFE4C4,
    0x000000,
    0xFFEBCD,
    0x0000FF,
    0x8A2BE2,
    0xA52A2A,
    0xDEB887,
    0x5F9EA0,
    0x7FFF00,
    0xD2691E,
    0xFF7F50,
    0x6495ED,
    0xFFF8DC,
    0xDC143C,
    0x00FFFF,
    0x00008B,
    0x008B8B,
    0xB8860B,
    0xA9A9A9,
    0x006400,
    0xA9A9A9,
    0xBDB76B,
    0x8B008B,
    0x556B2F,
    0xFF8C00,
    0x9932CC,
    0x8B0000,
    0xE9967A,
    0x8FBC8F,
    0x483D8B,
    0x2F4F4F,
    0x2F4F4F,
    0x00CED1,
    0x9400D3,
    0xFF1493,
    0x00BFFF,
    0x696969,
    0x696969,
    0x1E90FF,
    0xB22222,
    0xFFFAF0,
    0x228B22,
    0xFF00FF,
    0xDCDCDC,
    0xF8F8FF,
    0xFFD700,
    0xDAA520,
    0x808080,
    0x008000,
    0xADFF2F,
    0x808080,
    0xF0FFF0,
    0xFF69B4,
    0xCD5C5C,
    0x4B0082,
    0xFFFFF0,
    0xF0E68C,
    0xE6E6FA,
    0xFFF0F5,
    0x7CFC00,
    0xFFFACD,
    0xADD8E6,
    0xF08080,
    0xE0FFFF,
    0xFAFAD2,
    0xD3D3D3,
    0x90EE90,
    0xD3D3D3,
    0xFFB6C1,
    0xFFA07A,
    0x20B2AA,
    0x87CEFA,
    0x778899,
    0x778899,
    0xB0C4DE,
    0xFFFFE0,
    0x00FF00,
    0x32CD32,
    0xFAF0E6,
    0xFF00FF,
    0x800000,
    0x66CDAA,
    0x0000CD,
    0xBA55D3,
    0x9370DB,
    0x3CB371,
    0x7B68EE,
    0x00FA9A,
    0x48D1CC,
    0xC71585,
    0x191970,
    0xF5FFFA,
    0xFFE4E1,
    0xFFE4B5,
    0xFFDEAD,
    0x000080,
    0xFDF5E6,
    0x808000,
    0x6B8E23,
    0xFFA500,
    0xFF4500,
    0xDA70D6,
    0xEEE8AA,
    0x98FB98,
    0xAFEEEE,
    0xDB7093,
    0xFFEFD5,
    0xFFDAB9,
    0xCD853F,
    0xFFC0CB,
    0xDDA0DD,
    0xB0E0E6,
    0x800080,
    0x663399,
    0xFF0000,
    0xBC8F8F,
    0x4169E1,
    0x8B4513,
    0xFA8072,
    0xF4A460,
    0x2E8B57,
    0xFFF5EE,
    0xA0522D,
    0xC0C0C0,
    0x87CEEB,
    0x6A5ACD,
    0x708090,
    0x708090,
    0xFFFAFA,
    0x00FF7F,
    0x4682B4,
    0xD2B48C,
    0x008080,
    0xD8BFD8,
    0xFF6347,
    0x40E0D0,
    0xEE82EE,
    0xF5DEB3,
    0xFFFFFF,
    0xF5F5F5,
    0xFFFF00,
    0x9ACD32,
]


def color_name_hex(name: String) -> Optional[Int]:
    """Return the 24-bit sRGB value of a CSS color name, three.js's
    `Color.NAMES` lookup, in any case.

    Args:
        name: The name, such as `"rebeccapurple"` or `"Red"`.

    Returns:
        The value, or None for a name CSS does not have.
    """
    var lower = name.lower()
    var names = materialize[COLOR_NAMES]()
    var hexes = materialize[COLOR_NAME_HEXES]()
    for index in range(len(names)):  # pragma: no branch
        if lower == names[index]:
            return hexes[index]
    return None


def _is_space(byte: UInt8) -> Bool:
    """Return True for an ASCII space, tab or line break."""
    return byte == 32 or (byte >= 9 and byte <= 13)


def _is_digit(byte: UInt8) -> Bool:
    """Return True for an ASCII digit."""
    return byte >= 48 and byte <= 57


def _is_word(byte: UInt8) -> Bool:
    """Return True for a letter, a digit or an underscore: a regular
    expression's `\\w`."""
    var letter = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
    return letter or _is_digit(byte) or byte == 95


def _hex_digit(byte: UInt8) -> Int:
    """Return the value of a hexadecimal digit, or minus one."""
    if _is_digit(byte):
        return Int(byte) - 48
    if byte >= 65 and byte <= 70:
        return Int(byte) - 55
    if byte >= 97 and byte <= 102:
        return Int(byte) - 87
    return -1


struct _Scanner(Movable):
    """A cursor over the bytes of a string, for the few patterns a CSS
    color has."""

    var text: List[UInt8]
    var at: Int

    def __init__(out self, text: String):
        """Start at the first byte.

        Args:
            text: The text to read.
        """
        self.text = List[UInt8](text.as_bytes())
        self.at = 0

    def done(self) -> Bool:
        """Return True at the end of the text."""
        return self.at >= len(self.text)

    def peek(self) -> UInt8:
        """Return the byte at the cursor, or zero at the end."""
        return self.text[self.at] if self.at < len(self.text) else 0

    def skip_spaces(mut self):
        """Move past any spaces: a regular expression's `\\s*`."""
        while not self.done() and _is_space(self.peek()):
            self.at += 1

    def eat(mut self, byte: UInt8) -> Bool:
        """Move past `byte` if it is next. `peek` gives zero at the end,
        which is no byte this is asked for.

        Args:
            byte: The byte expected.

        Returns:
            Whether it was there.
        """
        if self.peek() != byte:
            return False
        self.at += 1
        return True

    def integer(mut self) -> Optional[Int]:
        """Read `\\d+`: one or more digits.

        Returns:
            The number, held at a million so that no string overflows it,
            or None if no digit is next.
        """
        if not _is_digit(self.peek()):
            return None
        var value = 0
        while _is_digit(self.peek()):
            value = min(value * 10 + Int(self.peek()) - 48, 1000000)
            self.at += 1
        return value

    def number(mut self) -> Optional[Float64]:
        """Read `\\d*\\.?\\d+`: digits, or digits with a fraction.

        Returns:
            The number, as `parseFloat` reads it, or None if the text does
            not match. A point with no digit after it does not match.
        """
        var whole = self.at
        var mantissa = Float64(0)
        while _is_digit(self.peek()):
            mantissa = mantissa * 10 + Float64(Int(self.peek()) - 48)
            self.at += 1
        var scale = Float64(1)
        if self.peek() == 46:
            self.at += 1
            if not _is_digit(self.peek()):
                return None
            while _is_digit(self.peek()):
                mantissa = mantissa * 10 + Float64(Int(self.peek()) - 48)
                scale *= 10
                self.at += 1
        if self.at == whole:
            return None
        return mantissa / scale

    def alpha_and_end(mut self) -> Bool:
        """Read `\\s*(?:,\\s*(\\d*\\.?\\d+)\\s*)?$`: an optional alpha,
        then the end.

        Returns:
            Whether the rest of the text matches.
        """
        self.skip_spaces()
        if self.eat(44):
            self.skip_spaces()
            if not Bool(self.number()):
                return False
            self.skip_spaces()
        return self.done()


def _components(
    text: String, percent: Bool, fractions: Bool
) -> Optional[SIMD[DType.float64, 4]]:
    """Read three comma-separated numbers and an optional alpha, the part
    of an `rgb(...)` or `hsl(...)` between the parentheses.

    Args:
        text: The text between the parentheses.
        percent: True when the numbers carry a percent sign: all three
            for `rgb`, the last two for `hsl`.
        fractions: True when each number can have a fraction, as in
            `hsl`; False for whole numbers only, as in `rgb`.

    Returns:
        The three numbers, or None if the text does not match.
    """
    var scan = _Scanner(text)
    var out = SIMD[DType.float64, 4](0)
    for index in range(3):  # pragma: no branch
        scan.skip_spaces()
        var value: Optional[Float64]
        if fractions:
            value = scan.number()
        else:
            var whole = scan.integer()
            value = Float64(whole.value()) if Bool(whole) else Optional[
                Float64
            ](None)
        if not Bool(value):
            return None
        out[index] = value.value()
        var needs_percent = percent and (index > 0 or not fractions)
        if needs_percent and not scan.eat(37):
            return None
        if index < 2:
            scan.skip_spaces()
            if not scan.eat(44):
                return None
    if not scan.alpha_and_end():
        return None
    return out


def _from_srgb_numbers(
    r: Float64, g: Float64, b: Float64, space: ColorSpace
) raises -> FloatColor:
    """Return the color three channels from zero to one describe in
    `space`, three.js's `setRGB` with a color space.

    Args:
        r: Red.
        g: Green.
        b: Blue.
        space: `SRGB` to decode them, `LINEAR` to take them as they are.

    Returns:
        The opaque color, linear.

    Raises:
        Error: If the space is neither of the two.
    """
    var red = Float32(r)
    var green = Float32(g)
    var blue = Float32(b)
    if space == SRGB:
        return FloatColor(
            srgb_to_linear(red), srgb_to_linear(green), srgb_to_linear(blue)
        )
    if space != LINEAR:
        raise Error("A CSS color is read in LINEAR or SRGB")
    return FloatColor(red, green, blue)


def parse_style(style: String, space: ColorSpace = SRGB) raises -> FloatColor:
    """Return the color a CSS string names, three.js's `setStyle`.

    Args:
        style: The string, in any form the module docstring lists.
        space: The space the string's numbers are in: `SRGB`, as three.js
            defaults to, or `LINEAR`.

    Returns:
        The opaque color, in the linear working space.

    Raises:
        Error: If the string is none of the forms, a number in it is out
            of form, or the space is neither of the two.
    """
    var bytes = style.as_bytes()
    var name_end = 0
    while name_end < len(bytes) and _is_word(bytes[name_end]):
        name_end += 1
    var open = name_end
    var close = open + 1
    while close < len(bytes) and bytes[close] != 41:
        close += 1
    var is_call = (
        name_end > 0
        and open < len(bytes)
        and bytes[open] == 40
        and close < len(bytes)
    )
    if is_call:
        var name = String(style[byte=0:name_end])
        var inner = String(style[byte = open + 1 : close])
        if name == "rgb" or name == "rgba":
            var whole = _components(inner, False, False)
            if Bool(whole):
                var v = whole.value()
                return _from_srgb_numbers(
                    min(Float64(255), v[0]) / 255,
                    min(Float64(255), v[1]) / 255,
                    min(Float64(255), v[2]) / 255,
                    space,
                )
            var shares = _components(inner, True, False)
            if Bool(shares):
                var v = shares.value()
                return _from_srgb_numbers(
                    min(Float64(100), v[0]) / 100,
                    min(Float64(100), v[1]) / 100,
                    min(Float64(100), v[2]) / 100,
                    space,
                )
            raise Error("An rgb() color takes three whole numbers or shares")
        if name == "hsl" or name == "hsla":
            var found = _components(inner, True, True)
            if not Bool(found):
                raise Error("An hsl() color takes a hue and two percentages")
            var v = found.value()
            return FloatColor(
                hue=Float32(v[0] / 360),
                saturation=Float32(v[1] / 100),
                lightness=Float32(v[2] / 100),
                space=space,
            )
        raise Error("Unknown CSS color model: " + name)
    if len(bytes) > 1 and bytes[0] == 35:
        return _parse_hex(style, space)
    var named = color_name_hex(style)
    if not Bool(named):
        raise Error("Unknown CSS color: " + style)
    return _from_hex(named.value(), space)


def _parse_hex(style: String, space: ColorSpace) raises -> FloatColor:
    """Return the color of a `#rgb` or `#rrggbb` string.

    Args:
        style: The string, starting with `#`.
        space: The space the digits are in.

    Returns:
        The color.

    Raises:
        Error: If a character after the `#` is not a hexadecimal digit,
            or there are not three or six of them.
    """
    var bytes = style.as_bytes()
    var digits = List[Int]()
    for index in range(1, len(bytes)):  # pragma: no branch
        var digit = _hex_digit(bytes[index])
        if digit < 0:
            raise Error("A hex color holds hexadecimal digits: " + style)
        digits.append(digit)
    if len(digits) == 3:
        return _from_srgb_numbers(
            Float64(digits[0]) / 15,
            Float64(digits[1]) / 15,
            Float64(digits[2]) / 15,
            space,
        )
    if len(digits) != 6:
        raise Error("A hex color has three or six digits: " + style)
    var value = 0
    for index in range(6):  # pragma: no branch
        value = value * 16 + digits[index]
    return _from_hex(value, space)


def _from_hex(value: Int, space: ColorSpace) raises -> FloatColor:
    """Return the color of a 24-bit value in `space`, three.js's `setHex`
    with a color space.

    Args:
        value: Red in the top byte, blue in the bottom.
        space: `SRGB` to decode it, `LINEAR` to take it as it is.

    Returns:
        The color.

    Raises:
        Error: If the space is neither of the two.
    """
    return _from_srgb_numbers(
        Float64((value >> 16) & 255) / 255,
        Float64((value >> 8) & 255) / 255,
        Float64(value & 255) / 255,
        space,
    )


def _round(value: Float64) -> Int:
    """Return `value` rounded to the nearest whole number, a half up, as
    JavaScript's `Math.round` rounds."""
    var whole = floor(value)
    return Int(whole) + (1 if value - whole >= 0.5 else 0)


def _fixed3(value: Float32) -> String:
    """Return `value` with three decimals, as JavaScript's `toFixed(3)`
    writes it: a tie rounds away from zero, and a negative value keeps its
    sign even when it rounds to zero."""
    var magnitude = abs(Float64(value))
    var thousandths = Int(floor(magnitude * 1000 + 0.5))
    var fraction = String(thousandths % 1000)
    while fraction.byte_length() < 3:
        fraction = "0" + fraction
    var sign = "-" if value < 0 else ""
    return sign + String(thousandths // 1000) + "." + fraction


def format_style(color: FloatColor, space: ColorSpace = SRGB) raises -> String:
    """Return a CSS string for a color, three.js's `getStyle`.

    Args:
        color: The color, linear. Its alpha is left out, as three.js has
            none.
        space: `SRGB` for `rgb(r,g,b)` with whole numbers from the encoded
            color, or `LINEAR` for `color(srgb-linear r g b)` with three
            decimals.

    Returns:
        The string. A channel past one or below zero is not clamped, as in
        three.js.

    Raises:
        Error: If the space is neither of the two.
    """
    if space == SRGB:
        return (
            "rgb("
            + String(_round(Float64(linear_to_srgb(color.r)) * 255))
            + ","
            + String(_round(Float64(linear_to_srgb(color.g)) * 255))
            + ","
            + String(_round(Float64(linear_to_srgb(color.b)) * 255))
            + ")"
        )
    if space != LINEAR:
        raise Error("A CSS color is written in LINEAR or SRGB")
    return (
        "color(srgb-linear "
        + _fixed3(color.r)
        + " "
        + _fixed3(color.g)
        + " "
        + _fixed3(color.b)
        + ")"
    )


def hex_string(color: FloatColor) -> String:
    """Return a color's sRGB value as six lowercase hexadecimal digits,
    three.js's `getHexString`.

    Args:
        color: The color, linear.

    Returns:
        The digits, with no `#`.
    """
    var value = color.hex()
    var digits = "0123456789abcdef"
    var out = String()
    for shift in range(20, -4, -4):  # pragma: no branch
        var nibble = (value >> shift) & 15
        out += String(digits[byte = nibble : nibble + 1])
    return out
