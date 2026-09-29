# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's blueprint library: actor attributes, blueprints and the catalog.

A blueprint names a kind of actor, such as `vehicle.lincoln.mkz` or
`sensor.camera.rgb`, and carries its attributes. An attribute has an id,
a type and a value kept as text. A modifiable attribute starts at its
first recommended value, and `set` changes it. `BlueprintLibrary.filter`
keeps the blueprints whose id or one of whose tags matches a shell
wildcard, as `fnmatch` matches it.

The sources are CARLA's `LibCarla/source/carla/client/ActorAttribute.cpp`,
`ActorBlueprint.cpp`, `BlueprintLibrary.cpp`, `rpc/ActorAttribute.h`,
`rpc/ActorAttributeType.h` and `StringUtil.cpp`, and the definitions in
CARLA's simulator plugin, `Carla/Actor/ActorBlueprintFunctionLibrary.cpp`,
`Carla/Actor/StaticMeshFactory.cpp`, `Carla/Actor/UtilActorFactory.cpp`
and `Carla/Sensor/DVSCamera.cpp`.

**Text to number.** An integer reads as C's `atoi` reads it on a 64-bit
system, and a float as `atof`: leading blanks, a sign, then the longest
number, and zero when there is none. So `"3.5f"` is 3.5 and `""` is 0.
A hexadecimal float reads as the zero before the `x`, where C reads it
in full.

**The catalog.** CARLA keeps its vehicle and pedestrian models as
assets, not code. `vehicle_catalog` lists the vehicles of CARLA's
vehicle catalog page with their make, model, base type, special type,
generation, lights and doors. `pedestrian_catalog` lists the pedestrians
of CARLA's pedestrian catalog page. The colors, the genders, the
generations of the pedestrians and their speeds are not published; this
port chooses them, and says so where it does.

**Differences from CARLA.**

- CARLA keeps the blueprints in a hash map and lists them in hash order.
  `BlueprintLibrary` lists them sorted by id, and a blueprint lists its
  attributes in the order they are defined.
- The props of `static.prop.*` other than `static.prop.mesh` are assets,
  and are left out. So are the sensors that need a third-party library.
- CARLA's client does not enforce `restrict_to_recommended`, and this
  port does not either. `ActorAttribute.is_recommended` tells.
"""

from render.framebuffer import Color
from std.math import inf, nan

comptime _INT32_MAX = 2147483647
# `std::numeric_limits<float>::max()`.
comptime _FLOAT_MAX = 3.4028234663852886e38


@fieldwise_init
struct ActorAttributeType(Equatable, ImplicitlyCopyable, Writable):
    """The type of an attribute's value, `rpc::ActorAttributeType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a type: bool, int, float, string,
        color or vector.

        Returns:
            Whether the value is from 0 to 5.
        """
        return self.value >= 0 and self.value <= 5


comptime ATTRIBUTE_BOOL = ActorAttributeType(0)
comptime ATTRIBUTE_INT = ActorAttributeType(1)
comptime ATTRIBUTE_FLOAT = ActorAttributeType(2)
comptime ATTRIBUTE_STRING = ActorAttributeType(3)
comptime ATTRIBUTE_RGB_COLOR = ActorAttributeType(4)
# A type CARLA's client refuses when it checks a value.
comptime ATTRIBUTE_VECTOR = ActorAttributeType(5)


# --- matching and reading text ---------------------------------------------


def _byte(text: String, i: Int) -> Int:
    return Int(text.as_bytes()[i])


def _is_space(c: Int) -> Bool:
    # C's `isspace`: blank, tab, newline, vertical tab, form feed, return.
    return c == 32 or (c >= 9 and c <= 13)


def _is_digit(c: Int) -> Bool:
    return c >= 48 and c <= 57


def _class_end(pattern: String, start: Int) -> Int:
    """Return the index of the `]` that closes a class, or -1."""
    var n = pattern.byte_length()
    var i = start + 1
    if i < n and (_byte(pattern, i) == 33 or _byte(pattern, i) == 94):
        i += 1
    # A `]` first in the class is a member, not the end.
    if i < n and _byte(pattern, i) == 93:
        i += 1
    while i < n:
        if _byte(pattern, i) == 93:
            return i
        i += 1
    return -1


def _class_matches(pattern: String, start: Int, end: Int, c: Int) -> Bool:
    """Return whether a byte is in the class `pattern[start..end]`."""
    var i = start + 1
    var negate = False
    if _byte(pattern, i) == 33 or _byte(pattern, i) == 94:
        negate = True
        i += 1
    var found = False
    # `end` is the class's closing bracket, so no other `]` ends it early.
    while i < end:
        var low = _byte(pattern, i)
        if i + 2 < end and _byte(pattern, i + 1) == 45:
            if c >= low and c <= _byte(pattern, i + 2):
                found = True
            i += 3
        else:
            if c == low:
                found = True
            i += 1
    return found != negate


def wildcard_match(text: String, pattern: String) -> Bool:
    """Return whether text matches a shell wildcard, `StringUtil::Match`.

    This is `fnmatch` with no flags: `*` matches any run of characters,
    `?` any one, `[abc]`, `[a-z]` and `[!a]` a class, and a backslash
    makes the next character plain.

    Args:
        text: The text, such as a blueprint id.
        pattern: The wildcard, such as `vehicle.*`.

    Returns:
        Whether the whole text matches the whole pattern.
    """
    var n = text.byte_length()
    var m = pattern.byte_length()
    var t = 0
    var p = 0
    # Where to resume after the last `*`: its pattern index and the text
    # index it has eaten up to.
    var star = -1
    var resume = 0
    while t < n:
        var step = False
        if p < m:
            var c = _byte(pattern, p)
            if c == 42:
                star = p
                resume = t
                p += 1
                continue
            if c == 63:
                step = True
                p += 1
            elif c == 91 and _class_end(pattern, p) > 0:
                var end = _class_end(pattern, p)
                if _class_matches(pattern, p, end, _byte(text, t)):
                    step = True
                    p = end + 1
            elif c == 92:
                # A backslash at the end of the pattern matches nothing.
                if p + 1 < m and _byte(pattern, p + 1) == _byte(text, t):
                    step = True
                    p += 2
            elif c == _byte(text, t):
                step = True
                p += 1
        if step:
            t += 1
        elif star >= 0:
            resume += 1
            t = resume
            p = star + 1
        else:
            return False
    while p < m and _byte(pattern, p) == 42:
        p += 1
    return p == m


def read_int(text: String) -> Int:
    """Read an integer as C's `atoi` does on a 64-bit system.

    Args:
        text: The text.

    Returns:
        The leading integer after any blanks, or 0 when there is none.
        As `atoi` calls `strtol` and keeps the low 32 bits, a value
        beyond 64 bits saturates and one beyond 32 bits wraps.
    """
    var n = text.byte_length()
    var i = 0
    while i < n and _is_space(_byte(text, i)):
        i += 1
    var negative = False
    if i < n and (_byte(text, i) == 43 or _byte(text, i) == 45):
        negative = _byte(text, i) == 45
        i += 1
    # The magnitude, held as a UInt64 so that 2^63 fits.
    var value = UInt64(0)
    var limit = UInt64(9223372036854775807) + UInt64(1 if negative else 0)
    while i < n and _is_digit(_byte(text, i)):
        var digit = UInt64(_byte(text, i) - 48)
        if value > (limit - digit) // 10:
            value = limit
        else:
            value = value * 10 + digit
        i += 1
    if negative:
        value = ~value + 1
    # Keep the low 32 bits as a signed number.
    var low = Int(value & 0xFFFFFFFF)
    return low - 4294967296 if low > _INT32_MAX else low


def read_float(text: String) raises -> Float64:
    """Read a number as C's `atof` does.

    Args:
        text: The text.

    Returns:
        The leading decimal number after any blanks, `inf` or `nan` in
        any case, or 0 when there is none.

    Raises:
        Error: Never for these inputs; the standard parser's error is
            passed on.
    """
    var n = text.byte_length()
    var i = 0
    while i < n and _is_space(_byte(text, i)):
        i += 1
    var start = i
    var negative = False
    if i < n and (_byte(text, i) == 43 or _byte(text, i) == 45):
        negative = _byte(text, i) == 45
        i += 1
    var rest = String(text[byte=i:]).lower()
    if rest.startswith("inf"):
        return -inf[DType.float64]() if negative else inf[DType.float64]()
    if rest.startswith("nan"):
        return nan[DType.float64]()
    var digits = 0
    while i < n and _is_digit(_byte(text, i)):
        i += 1
        digits += 1
    if i < n and _byte(text, i) == 46:
        i += 1
        while i < n and _is_digit(_byte(text, i)):
            i += 1
            digits += 1
    if digits == 0:
        return 0.0
    if i < n and (_byte(text, i) == 101 or _byte(text, i) == 69):
        var j = i + 1
        if j < n and (_byte(text, j) == 43 or _byte(text, j) == 45):
            j += 1
        var k = j
        while k < n and _is_digit(_byte(text, k)):
            k += 1
        if k > j:
            i = k
    return Float64(String(text[byte=start:i]))


def _check_value(id: String, type: ActorAttributeType, value: String) raises:
    """Check a value against its type, CARLA's `Validate`."""
    if type == ATTRIBUTE_BOOL:
        _ = _as_bool(id, type, value)
    elif type == ATTRIBUTE_FLOAT:
        _ = _as_float(id, type, value)
    elif type == ATTRIBUTE_RGB_COLOR:
        _ = _as_color(id, type, value)
    elif not (type == ATTRIBUTE_INT or type == ATTRIBUTE_STRING):
        raise Error(id + ": invalid value type")


def _cast(
    id: String, type: ActorAttributeType, want: ActorAttributeType, name: String
) raises:
    if type != want:
        raise Error(id + ": bad attribute cast: cannot convert to " + name)


def _as_bool(
    id: String, type: ActorAttributeType, value: String
) raises -> Bool:
    _cast(id, type, ATTRIBUTE_BOOL, "Bool")
    var lower = value.lower()
    if lower == "true":
        return True
    if lower == "false":
        return False
    raise Error(id + ": invalid bool: " + value)


def _as_float(
    id: String, type: ActorAttributeType, value: String
) raises -> Float32:
    _cast(id, type, ATTRIBUTE_FLOAT, "Float")
    var x = read_float(value)
    if x > _FLOAT_MAX or x < -_FLOAT_MAX:
        raise Error(id + ": float overflow")
    return Float32(x)


def _as_color(
    id: String, type: ActorAttributeType, value: String
) raises -> Color:
    _cast(id, type, ATTRIBUTE_RGB_COLOR, "RGBColor")
    var channels = value.split(",")
    if len(channels) != 3:
        raise Error(id + ": colors must have 3 channels (R,G,B)")
    var rgb = List[UInt8]()
    # There are three channels, checked above.
    for channel in channels:  # pragma: no branch
        var i = read_int(String(channel))
        if i > 255:
            raise Error(id + ": integer overflow in color channel")
        # A negative channel wraps, as a cast to an unsigned byte does.
        rgb.append(UInt8(i & 255))
    return Color(rgb[0], rgb[1], rgb[2])


# --- attributes ------------------------------------------------------------


@fieldwise_init
struct ActorAttributeValue(Copyable, Movable, Writable):
    """An attribute's id, type and value, `ActorAttributeValue`.

    An actor keeps these: the values its blueprint had when it spawned.
    """

    var id: String
    var type: ActorAttributeType
    var value: String

    def as_bool(self) raises -> Bool:
        """Return the value as a bool, `As<bool>`.

        Returns:
            True for "true" and False for "false", in any case.

        Raises:
            Error: If the type is not bool, or the text is neither.
        """
        return _as_bool(self.id, self.type, self.value)

    def as_int(self) raises -> Int:
        """Return the value as an integer, `As<int>`.

        Returns:
            The value as `atoi` reads it.

        Raises:
            Error: If the type is not int.
        """
        _cast(self.id, self.type, ATTRIBUTE_INT, "Int")
        return read_int(self.value)

    def as_float(self) raises -> Float32:
        """Return the value as a float, `As<float>`.

        Returns:
            The value as `atof` reads it.

        Raises:
            Error: If the type is not float, or the value does not fit a
                32-bit float.
        """
        return _as_float(self.id, self.type, self.value)

    def as_string(self) raises -> String:
        """Return the value as text, `As<std::string>`.

        Returns:
            The text.

        Raises:
            Error: If the type is not string.
        """
        _cast(self.id, self.type, ATTRIBUTE_STRING, "String")
        return self.value

    def as_color(self) raises -> Color:
        """Return the value as a color, `As<Color>`.

        Returns:
            The opaque color of the text "r,g,b".

        Raises:
            Error: If the type is not a color, there are not three
                channels, or a channel is more than 255.
        """
        return _as_color(self.id, self.type, self.value)

    def write_to(self, mut writer: Some[Writer]):
        """Write the attribute as CARLA prints it.

        Args:
            writer: The destination.
        """
        writer.write("ActorAttribute(id=", self.id, ",type=", self.type.value)
        writer.write(",value=", self.value, ")")


struct ActorAttribute(Copyable, Movable, Writable):
    """A blueprint's attribute, CARLA's client `ActorAttribute`."""

    var id: String
    var type: ActorAttributeType
    var value: String
    var recommended_values: List[String]
    var is_modifiable: Bool
    var restrict_to_recommended: Bool

    def __init__(
        out self,
        id: String,
        type: ActorAttributeType,
        var recommended_values: List[String],
        restrict_to_recommended: Bool = False,
    ) raises:
        """Create a modifiable attribute, a variation in CARLA's words.

        Args:
            id: The attribute's id.
            type: Its type.
            recommended_values: The values it suggests. The first is the
                value it starts with; with none it starts empty.
            restrict_to_recommended: Whether only these values are meant.

        Raises:
            Error: If the type is not valid, or the first value does not
                read as the type.
        """
        if not type.is_valid():
            raise Error("Attribute type is not valid")
        self.id = id
        self.type = type
        self.value = (
            recommended_values[0] if len(recommended_values) > 0 else ""
        )
        self.recommended_values = recommended_values^
        self.is_modifiable = True
        self.restrict_to_recommended = restrict_to_recommended
        _check_value(self.id, self.type, self.value)

    def __init__(
        out self,
        *,
        id: String,
        type: ActorAttributeType,
        value: String,
        var recommended_values: List[String],
        modifiable: Bool,
        restrict_to_recommended: Bool,
    ):
        """Create an attribute from its fields, with no check.

        Args:
            id: The attribute's id.
            type: Its type.
            value: Its value.
            recommended_values: The values it suggests.
            modifiable: Whether `set` may change it.
            restrict_to_recommended: Whether only those values are meant.
        """
        self.id = id
        self.type = type
        self.value = value
        self.recommended_values = recommended_values^
        self.is_modifiable = modifiable
        self.restrict_to_recommended = restrict_to_recommended

    @staticmethod
    def fixed(
        id: String, type: ActorAttributeType, value: String
    ) raises -> ActorAttribute:
        """Return a read-only attribute.

        Args:
            id: The attribute's id.
            type: Its type.
            value: Its value.

        Raises:
            Error: If the type is not valid, or the value does not read as
                the type.

        Returns:
            The attribute. It has no recommended values.
        """
        if not type.is_valid():
            raise Error("Attribute type is not valid")
        _check_value(id, type, value)
        return ActorAttribute(
            id=id,
            type=type,
            value=value,
            recommended_values=List[String](),
            modifiable=False,
            restrict_to_recommended=False,
        )

    def set(mut self, var value: String) raises:
        """Change the value, `ActorAttribute::Set`.

        A bool's text is kept in lower case.

        Args:
            value: The new value.

        Raises:
            Error: If the attribute is read-only, or the value does not
                read as its type. The value is kept either way, as in
                CARLA, when only the type check fails.
        """
        if not self.is_modifiable:
            raise Error(self.id + ": read-only attribute")
        if self.type == ATTRIBUTE_BOOL:
            value = value.lower()
        self.value = value^
        _check_value(self.id, self.type, self.value)

    def is_recommended(self, value: String) -> Bool:
        """Return whether a value is one of the recommended values.

        Args:
            value: The value.

        Returns:
            True if it is listed, or if the list is empty.
        """
        if len(self.recommended_values) == 0:
            return True
        # The list is not empty, checked above.
        for v in self.recommended_values:  # pragma: no branch
            if v == value:
                return True
        return False

    def to_value(self) -> ActorAttributeValue:
        """Return the id, the type and the value.

        Returns:
            The value an actor keeps.
        """
        return ActorAttributeValue(self.id, self.type, self.value)

    def as_bool(self) raises -> Bool:
        """Return the value as a bool, `As<bool>`.

        Returns:
            True for "true" and False for "false", in any case.

        Raises:
            Error: If the type is not bool, or the text is neither.
        """
        return self.to_value().as_bool()

    def as_int(self) raises -> Int:
        """Return the value as an integer, `As<int>`.

        Returns:
            The value as `atoi` reads it.

        Raises:
            Error: If the type is not int.
        """
        return self.to_value().as_int()

    def as_float(self) raises -> Float32:
        """Return the value as a float, `As<float>`.

        Returns:
            The value as `atof` reads it.

        Raises:
            Error: If the type is not float, or it overflows.
        """
        return self.to_value().as_float()

    def as_string(self) raises -> String:
        """Return the value as text, `As<std::string>`.

        Returns:
            The text.

        Raises:
            Error: If the type is not string.
        """
        return self.to_value().as_string()

    def as_color(self) raises -> Color:
        """Return the value as a color, `As<Color>`.

        Returns:
            The color.

        Raises:
            Error: If the type is not a color or the text is not one.
        """
        return self.to_value().as_color()

    def __eq__(self, other: Self) -> Bool:
        """Return True if the types and the values are equal, as CARLA.

        Args:
            other: The other attribute.

        Returns:
            Whether the type and the value text match.
        """
        return self.type == other.type and self.value == other.value

    def write_to(self, mut writer: Some[Writer]):
        """Write the attribute as CARLA prints it.

        Args:
            writer: The destination.
        """
        writer.write(self.to_value())


def _variation(
    id: String, type: ActorAttributeType, value: String
) raises -> ActorAttribute:
    return ActorAttribute(id, type, [value])


# --- blueprints ------------------------------------------------------------


struct ActorBlueprint(Copyable, Movable, Writable):
    """A kind of actor and its attributes, CARLA's `ActorBlueprint`."""

    # CARLA's definition number, from one, in library order.
    var uid: Int
    var id: String
    var tags: List[String]
    var attributes: List[ActorAttribute]

    def __init__(
        out self, id: String, tags: String, var attributes: List[ActorAttribute]
    ):
        """Create a blueprint from a definition.

        Args:
            id: The blueprint's id.
            tags: The tags, joined by commas. A repeated tag is kept once.
            attributes: The attributes, variations first.
        """
        self.uid = 0
        self.id = id
        self.tags = List[String]()
        # A split gives one part at least.
        for tag in tags.split(","):  # pragma: no branch
            var t = String(tag)
            var seen = False
            for have in self.tags:
                if have == t:
                    seen = True
            if not seen:
                self.tags.append(t)
        self.attributes = attributes^

    def contains_tag(self, tag: String) -> Bool:
        """Return whether the blueprint has a tag, `ContainsTag`.

        Args:
            tag: The tag.

        Returns:
            Whether a tag equals it.
        """
        # A blueprint has one tag at least.
        for t in self.tags:  # pragma: no branch
            if t == tag:
                return True
        return False

    def match_tags(self, pattern: String) -> Bool:
        """Return whether the id or a tag matches a wildcard, `MatchTags`.

        Args:
            pattern: The wildcard.

        Returns:
            Whether the id or one of the tags matches.
        """
        if wildcard_match(self.id, pattern):
            return True
        # A blueprint has one tag at least.
        for t in self.tags:  # pragma: no branch
            if wildcard_match(t, pattern):
                return True
        return False

    def _index(self, id: String) -> Int:
        for i in range(len(self.attributes)):
            if self.attributes[i].id == id:
                return i
        return -1

    def contains_attribute(self, id: String) -> Bool:
        """Return whether the blueprint has an attribute, `ContainsAttribute`.

        Args:
            id: The attribute's id.

        Returns:
            Whether it has one with that id.
        """
        return self._index(id) >= 0

    def attribute(self, id: String) raises -> ActorAttribute:
        """Return an attribute, `GetAttribute`.

        Args:
            id: The attribute's id.

        Returns:
            A copy of the attribute.

        Raises:
            Error: If there is no such attribute.
        """
        var i = self._index(id)
        if i < 0:
            raise Error("attribute '" + id + "' not found")
        return self.attributes[i].copy()

    def set_attribute(mut self, id: String, value: String) raises:
        """Change an attribute's value, `SetAttribute`.

        Args:
            id: The attribute's id.
            value: The new value.

        Raises:
            Error: If there is no such attribute, or `ActorAttribute.set`
                refuses the value.
        """
        var i = self._index(id)
        if i < 0:
            raise Error("attribute '" + id + "' not found")
        self.attributes[i].set(value)

    def size(self) -> Int:
        """Return how many attributes the blueprint has.

        Returns:
            The count.
        """
        return len(self.attributes)

    def description(self) -> List[ActorAttributeValue]:
        """Return the values an actor spawned from it keeps,
        `MakeActorDescription`.

        Returns:
            Every attribute's id, type and value.
        """
        var out = List[ActorAttributeValue]()
        for a in self.attributes:
            out.append(a.to_value())
        return out^

    def write_to(self, mut writer: Some[Writer]):
        """Write the blueprint as CARLA prints it.

        Args:
            writer: The destination.
        """
        writer.write("ActorBlueprint(id=", self.id, ",tags=[")
        # A blueprint has one tag at least.
        for i in range(len(self.tags)):  # pragma: no branch
            if i > 0:
                writer.write(", ")
            writer.write(self.tags[i])
        writer.write("])")


struct BlueprintLibrary(Copyable, Movable):
    """A list of blueprints, CARLA's `BlueprintLibrary`."""

    var blueprints: List[ActorBlueprint]

    def __init__(out self, var blueprints: List[ActorBlueprint]):
        """Create a library, sorted by id.

        Args:
            blueprints: The blueprints. A blueprint whose id is already in
                the list is dropped, as a map keeps one per key.
        """
        self.blueprints = List[ActorBlueprint]()
        for b in blueprints:
            var at = 0
            var repeated = False
            for i in range(len(self.blueprints)):
                if self.blueprints[i].id == b.id:
                    repeated = True
                if self.blueprints[i].id < b.id:
                    at = i + 1
            if not repeated:
                self.blueprints.insert(at, b.copy())

    def filter(self, pattern: String) -> BlueprintLibrary:
        """Keep the blueprints whose id or a tag matches, `Filter`.

        Args:
            pattern: A shell wildcard, such as `vehicle.*`.

        Returns:
            A new library.
        """
        var out = List[ActorBlueprint]()
        for b in self.blueprints:
            if b.match_tags(pattern):
                out.append(b.copy())
        return BlueprintLibrary(out^)

    def filter_by_attribute(
        self, name: String, value: String
    ) -> BlueprintLibrary:
        """Keep the blueprints that offer an attribute value,
        `FilterByAttribute`.

        Args:
            name: The attribute's id.
            value: The value.

        Returns:
            The blueprints that have the attribute and list the value
            among its recommended values, or, with none listed, hold it.
        """
        var out = List[ActorBlueprint]()
        for b in self.blueprints:
            var i = b._index(name)
            if i < 0:
                continue
            ref a = b.attributes[i]
            var offered = a.value == value
            if len(a.recommended_values) > 0:
                offered = False
                # The list is not empty, checked above.
                for v in a.recommended_values:  # pragma: no branch
                    if v == value:
                        offered = True
            if offered:
                out.append(b.copy())
        return BlueprintLibrary(out^)

    def find(self, id: String) -> Optional[ActorBlueprint]:
        """Return a blueprint by id, `Find`.

        Args:
            id: The id.

        Returns:
            A copy of the blueprint, or None.
        """
        for b in self.blueprints:
            if b.id == id:
                return b.copy()
        return None

    def at(self, id: String) raises -> ActorBlueprint:
        """Return a blueprint by id, `at`.

        Args:
            id: The id.

        Returns:
            A copy of the blueprint.

        Raises:
            Error: If there is no such blueprint.
        """
        var found = self.find(id)
        if not Bool(found):
            raise Error("blueprint '" + id + "' not found")
        return found.value().copy()

    def at(self, position: Int) raises -> ActorBlueprint:
        """Return a blueprint by position, `at`.

        Args:
            position: The index, from zero.

        Returns:
            A copy of the blueprint.

        Raises:
            Error: If the index is out of range.
        """
        if position < 0 or position >= len(self.blueprints):
            raise Error("index out of range")
        return self.blueprints[position].copy()

    def size(self) -> Int:
        """Return how many blueprints the library has.

        Returns:
            The count.
        """
        return len(self.blueprints)

    def ids(self) -> List[String]:
        """Return every blueprint's id, in order.

        Returns:
            The ids.
        """
        var out = List[String]()
        for b in self.blueprints:
            out.append(b.id)
        return out^


# --- the definitions ---------------------------------------------------------


def _join(parts: List[String], separator: String) -> String:
    var out = String()
    # An id has three parts or two.
    for i in range(len(parts)):  # pragma: no branch
        if i > 0:
            out += separator
        out += parts[i]
    return out^


def _definition(var parts: List[String]) raises -> ActorBlueprint:
    """`FillIdAndTags`: the id and tags, a role name and a ROS name."""
    var id = _join(parts, ".").lower()
    var attributes = List[ActorAttribute]()
    attributes.append(_variation("role_name", ATTRIBUTE_STRING, "default"))
    attributes.append(_variation("ros_name", ATTRIBUTE_STRING, id))
    return ActorBlueprint(id, _join(parts, ",").lower(), attributes^)


def _set_role_names(mut blueprint: ActorBlueprint, var names: List[String]):
    """`AddRecommendedValuesForActorRoleName`."""
    # Every definition starts with its role name, and the value CARLA's
    # client sees is the first recommended one.
    blueprint.attributes[0].value = names[0]
    blueprint.attributes[0].recommended_values = names^


def _sensor_role_names(mut blueprint: ActorBlueprint):
    _set_role_names(
        blueprint,
        [
            "front",
            "back",
            "left",
            "right",
            "front_left",
            "front_right",
            "back_left",
            "back_right",
        ],
    )


def _add(
    mut blueprint: ActorBlueprint,
    id: String,
    type: ActorAttributeType,
    value: String,
) raises:
    blueprint.attributes.append(_variation(id, type, value))


def _add_sensor_tick(mut blueprint: ActorBlueprint) raises:
    """`AddVariationsForSensor`."""
    _add(blueprint, "sensor_tick", ATTRIBUTE_FLOAT, "0.0")


def make_generic_definition(
    category: String, type: String, id: String
) raises -> ActorBlueprint:
    """Return a bare definition, `MakeGenericDefinition`.

    Args:
        category: The first part of the id, such as "static".
        type: The second part.
        id: The last part.

    Returns:
        A blueprint with a role name and a ROS name.

    Raises:
        Error: Never for text; the attribute check is passed on.
    """
    return _definition([category, type, id])


def make_generic_sensor_definition(
    type: String, id: String
) raises -> ActorBlueprint:
    """Return a sensor with no settings, `MakeGenericSensorDefinition`.

    Args:
        type: Such as "other".
        id: Such as "collision".

    Returns:
        `sensor.<type>.<id>` with the sensor role names.

    Raises:
        Error: Never for text; the attribute check is passed on.
    """
    var out = _definition(["sensor", type, id])
    _sensor_role_names(out)
    return out^


def _add_lens(mut out: ActorBlueprint) raises:
    _add(out, "lens_circle_falloff", ATTRIBUTE_FLOAT, "5.0")
    _add(out, "lens_circle_multiplier", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "lens_k", ATTRIBUTE_FLOAT, "-1.0")
    _add(out, "lens_kcube", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "lens_x_size", ATTRIBUTE_FLOAT, "0.08")
    _add(out, "lens_y_size", ATTRIBUTE_FLOAT, "0.08")


def _add_image(mut out: ActorBlueprint) raises:
    _add(out, "image_size_x", ATTRIBUTE_INT, "800")
    _add(out, "image_size_y", ATTRIBUTE_INT, "600")
    _add(out, "fov", ATTRIBUTE_FLOAT, "90.0")


def make_camera_definition(
    id: String, post_process: Bool = False
) raises -> ActorBlueprint:
    """Return a camera, `MakeCameraDefinition`.

    Args:
        id: Such as "rgb" or "depth".
        post_process: Whether its post-process effects can be set, as for
            the RGB and DVS cameras.

    Returns:
        `sensor.camera.<id>`: the image size, the field of view, the lens
        and the ray-tracing switch, and with `post_process` the effects
        switch and profile.

    Raises:
        Error: Never for text; the attribute check is passed on.
    """
    var out = _definition(["sensor", "camera", id])
    _sensor_role_names(out)
    _add_sensor_tick(out)
    _add_image(out)
    _add_lens(out)
    _add(out, "use_ray_tracing", ATTRIBUTE_BOOL, "true")
    if post_process:
        _add(out, "enable_postprocess_effects", ATTRIBUTE_BOOL, "true")
        _add(out, "post_process_profile", ATTRIBUTE_STRING, "Default")
    return out^


def make_normals_camera_definition() raises -> ActorBlueprint:
    """Return the normals camera, `MakeNormalsCameraDefinition`.

    Returns:
        `sensor.camera.normals`, with a camera's image and lens settings.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    return make_camera_definition("normals")


def make_dvs_camera_definition() raises -> ActorBlueprint:
    """Return the event camera, from CARLA's `DVSCamera.cpp`.

    Returns:
        `sensor.camera.dvs`: an RGB camera's settings and the event
        thresholds.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = make_camera_definition("dvs", True)
    _add(out, "positive_threshold", ATTRIBUTE_FLOAT, "0.3")
    _add(out, "negative_threshold", ATTRIBUTE_FLOAT, "0.3")
    _add(out, "sigma_positive_threshold", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "sigma_negative_threshold", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "refractory_period_ns", ATTRIBUTE_INT, "0")
    _add(out, "use_log", ATTRIBUTE_BOOL, "True")
    _add(out, "log_eps", ATTRIBUTE_FLOAT, "0.001")
    return out^


def make_wide_angle_lens_camera_definition(
    id: String, post_process: Bool = False
) raises -> ActorBlueprint:
    """Return a fisheye camera, `MakeWideAngleLensCameraDefinition`.

    The Kannala-Brandt coefficients are CARLA's defaults, printed to six
    decimals as CARLA prints them.

    Args:
        id: Such as "rgb"; the blueprint is `sensor.camera.<id>_fisheye`.
        post_process: Whether its exposure, bloom, blur, film and color
            settings can be set.

    Returns:
        The blueprint.

    Raises:
        Error: Never for text; the attribute check is passed on.
    """
    var out = _definition(["sensor", "camera", id + "_fisheye"])
    _sensor_role_names(out)
    _add_sensor_tick(out)
    _add(out, "camera_model", ATTRIBUTE_STRING, "perspective")
    _add(out, "k0", ATTRIBUTE_FLOAT, "0.083092")
    _add(out, "k1", ATTRIBUTE_FLOAT, "0.011121")
    _add(out, "k2", ATTRIBUTE_FLOAT, "0.008587")
    _add(out, "k3", ATTRIBUTE_FLOAT, "0.000854")
    _add(out, "image_size_x", ATTRIBUTE_INT, "800")
    _add(out, "image_size_y", ATTRIBUTE_INT, "600")
    _add(out, "fov", ATTRIBUTE_FLOAT, "90.0")
    _add(out, "focal_length", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "equirectangular", ATTRIBUTE_BOOL, "false")
    _add(out, "fov_mask", ATTRIBUTE_BOOL, "false")
    _add(out, "fov_fade_size", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "longitude_offset", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "perspective", ATTRIBUTE_BOOL, "false")
    _add_lens(out)
    if post_process:
        out.attributes.append(
            ActorAttribute(
                "exposure_mode", ATTRIBUTE_STRING, ["histogram", "manual"], True
            )
        )
        var ids: List[String] = [
            "exposure_compensation",
            "shutter_speed",
            "iso",
            "fstop",
            "enable_postprocess_effects",
            "gamma",
            "motion_blur_intensity",
            "motion_blur_max_distortion",
            "lens_flare_intensity",
            "bloom_intensity",
            "motion_blur_min_object_screen_size",
            "exposure_min_bright",
            "exposure_max_bright",
            "exposure_speed_up",
            "exposure_speed_down",
            "calibration_constant",
            "focal_distance",
            "min_fstop",
            "blade_count",
            "blur_amount",
            "blur_radius",
            "slope",
            "toe",
            "shoulder",
            "black_clip",
            "white_clip",
            "temp",
            "tint",
            "chromatic_aberration_intensity",
            "chromatic_aberration_offset",
        ]
        var values: List[String] = [
            "0.0",
            "200.0",
            "100.0",
            "1.4",
            "true",
            "2.2",
            "0.45",
            "0.35",
            "0.1",
            "0.675",
            "0.1",
            "10.0",
            "12.0",
            "3.0",
            "1.0",
            "16.0",
            "1000.0",
            "1.2",
            "5",
            "1.0",
            "0.0",
            "0.88",
            "0.55",
            "0.26",
            "0.0",
            "0.04",
            "6500.0",
            "0.0",
            "0.0",
            "0.0",
        ]
        # The list is a constant and not empty.
        for i in range(len(ids)):  # pragma: no branch
            var type = ATTRIBUTE_FLOAT
            if ids[i] == "enable_postprocess_effects":
                type = ATTRIBUTE_BOOL
            elif ids[i] == "blade_count":
                type = ATTRIBUTE_INT
            _add(out, ids[i], type, values[i])
    return out^


def _add_floats(mut out: ActorBlueprint, ids: List[String]) raises:
    # Each list passed here is a constant and not empty.
    for id in ids:  # pragma: no branch
        _add(out, id, ATTRIBUTE_FLOAT, "0.0")


def make_imu_definition() raises -> ActorBlueprint:
    """Return the inertial sensor, `MakeIMUDefinition`.

    Returns:
        `sensor.other.imu`: a noise seed and the noise deviations and
        gyroscope biases, all zero.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = _definition(["sensor", "other", "imu"])
    _add_sensor_tick(out)
    _add(out, "noise_seed", ATTRIBUTE_INT, "0")
    _add_floats(
        out,
        [
            "noise_accel_stddev_x",
            "noise_accel_stddev_y",
            "noise_accel_stddev_z",
            "noise_gyro_stddev_x",
            "noise_gyro_stddev_y",
            "noise_gyro_stddev_z",
            "noise_gyro_bias_x",
            "noise_gyro_bias_y",
            "noise_gyro_bias_z",
        ],
    )
    return out^


def make_radar_definition() raises -> ActorBlueprint:
    """Return the radar, `MakeRadarDefinition`.

    Returns:
        `sensor.other.radar`: 30 by 30 degrees, 100 m, 1500 points a
        second.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = _definition(["sensor", "other", "radar"])
    _add_sensor_tick(out)
    _add(out, "horizontal_fov", ATTRIBUTE_FLOAT, "30")
    _add(out, "vertical_fov", ATTRIBUTE_FLOAT, "30")
    _add(out, "range", ATTRIBUTE_FLOAT, "100")
    _add(out, "points_per_second", ATTRIBUTE_INT, "1500")
    _add(out, "noise_seed", ATTRIBUTE_INT, "0")
    return out^


def make_lidar_definition(id: String) raises -> ActorBlueprint:
    """Return a LiDAR, `MakeLidarDefinition`.

    Args:
        id: "ray_cast", "ray_cast_semantic" or "hss_lidar".

    Returns:
        `sensor.lidar.<id>` with CARLA's defaults for that kind.

    Raises:
        Error: If the id is none of the three.
    """
    var ray_cast = id == "ray_cast"
    var semantic = id == "ray_cast_semantic"
    var hss = id == "hss_lidar"
    if not (ray_cast or semantic or hss):
        raise Error("LiDAR id is not valid: " + id)
    var out = _definition(["sensor", "lidar", id])
    _sensor_role_names(out)
    _add_sensor_tick(out)
    _add(out, "channels", ATTRIBUTE_INT, "128" if hss else "64")
    _add(out, "range", ATTRIBUTE_FLOAT, "200" if hss else "50.0")
    if not hss:
        _add(out, "points_per_second", ATTRIBUTE_INT, "600000")
    _add(out, "rotation_frequency", ATTRIBUTE_FLOAT, "20" if hss else "60.0")
    _add(out, "upper_fov", ATTRIBUTE_FLOAT, "12.9" if hss else "10.0")
    _add(out, "lower_fov", ATTRIBUTE_FLOAT, "-12.5" if hss else "-30.0")
    if semantic:
        _add(out, "horizontal_fov", ATTRIBUTE_FLOAT, "360.0")
        return out^
    _add(out, "atmosphere_attenuation_rate", ATTRIBUTE_FLOAT, "0.004")
    _add(out, "noise_seed", ATTRIBUTE_INT, "0")
    _add(out, "dropoff_general_rate", ATTRIBUTE_FLOAT, "0.45")
    _add(out, "dropoff_intensity_limit", ATTRIBUTE_FLOAT, "0.8")
    _add(out, "dropoff_zero_intensity", ATTRIBUTE_FLOAT, "0.4")
    _add(out, "noise_stddev", ATTRIBUTE_FLOAT, "0.0")
    _add(out, "horizontal_fov", ATTRIBUTE_FLOAT, "120.0" if hss else "360.0")
    if hss:
        _add(out, "horizontal_resolution", ATTRIBUTE_FLOAT, "0.1")
    return out^


def _add_noise(mut out: ActorBlueprint) raises:
    _add_floats(
        out,
        [
            "noise_lat_stddev",
            "noise_lat_bias",
            "noise_lon_stddev",
            "noise_lon_bias",
            "noise_alt_stddev",
            "noise_alt_bias",
        ],
    )


def make_gnss_definition() raises -> ActorBlueprint:
    """Return the GNSS receiver, `MakeGnssDefinition`.

    Returns:
        `sensor.other.gnss`: a noise seed, and a deviation and a bias for
        the latitude, the longitude and the altitude, all zero.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = _definition(["sensor", "other", "gnss"])
    _add_sensor_tick(out)
    _add(out, "noise_seed", ATTRIBUTE_INT, "0")
    _add_noise(out)
    return out^


def make_obstacle_definition() raises -> ActorBlueprint:
    """Return the obstacle detector, `MakeObstacleDetectorDefinitions`.

    Returns:
        `sensor.other.obstacle`: 5 m ahead, a 0.5 m radius, every body.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = make_generic_sensor_definition("other", "obstacle")
    _add_sensor_tick(out)
    _add(out, "distance", ATTRIBUTE_FLOAT, "5.0")
    _add(out, "hit_radius", ATTRIBUTE_FLOAT, "0.5")
    _add(out, "only_dynamics", ATTRIBUTE_BOOL, "false")
    _add(out, "debug_linetrace", ATTRIBUTE_BOOL, "false")
    return out^


def _add_v2x(mut out: ActorBlueprint) raises:
    _add(out, "channel_id", ATTRIBUTE_STRING, "Default")
    _add(out, "noise_seed", ATTRIBUTE_INT, "0")
    _add(out, "transmit_power", ATTRIBUTE_FLOAT, "21.5")
    _add(out, "receiver_sensitivity", ATTRIBUTE_FLOAT, "-99.0")
    _add(out, "frequency_ghz", ATTRIBUTE_FLOAT, "5.9")
    _add(out, "combined_antenna_gain", ATTRIBUTE_FLOAT, "10.0")
    out.attributes.append(
        ActorAttribute(
            "scenario", ATTRIBUTE_STRING, ["highway", "rural", "urban"], True
        )
    )
    out.attributes.append(
        ActorAttribute(
            "path_loss_model", ATTRIBUTE_STRING, ["winner", "geometric"], True
        )
    )
    _add(out, "path_loss_exponent", ATTRIBUTE_FLOAT, "2.7")
    _add(out, "d_ref", ATTRIBUTE_FLOAT, "1.0")
    _add(out, "filter_distance", ATTRIBUTE_FLOAT, "500.0")
    _add(out, "use_etsi_fading", ATTRIBUTE_BOOL, "true")
    _add(out, "custom_fading_stddev", ATTRIBUTE_FLOAT, "0.0")


def make_v2x_definition() raises -> ActorBlueprint:
    """Return the cooperative-awareness sender, `MakeV2XDefinition`.

    Returns:
        `sensor.other.v2x`: the radio channel, the path-loss and fading
        settings, the message timing and the noise of the data it sends.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = _definition(["sensor", "other", "v2x"])
    _add_sensor_tick(out)
    _add_v2x(out)
    _add(out, "gen_cam_min", ATTRIBUTE_FLOAT, "0.1")
    _add(out, "gen_cam_max", ATTRIBUTE_FLOAT, "1.0")
    _add(out, "fixed_rate", ATTRIBUTE_BOOL, "false")
    _add_noise(out)
    _add_floats(
        out,
        [
            "noise_head_stddev",
            "noise_head_bias",
            "noise_accel_stddev_x",
            "noise_accel_stddev_y",
            "noise_accel_stddev_z",
            "noise_yawrate_stddev",
            "noise_yawrate_bias",
            "noise_vel_stddev_x",
        ],
    )
    return out^


def make_custom_v2x_definition() raises -> ActorBlueprint:
    """Return the custom-message sender, `MakeCustomV2XDefinition`.

    Returns:
        `sensor.other.v2x_custom`: the radio settings only.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = _definition(["sensor", "other", "v2x_custom"])
    _add_sensor_tick(out)
    _add_v2x(out)
    return out^


# --- vehicles, walkers and props ------------------------------------------


@fieldwise_init
struct VehicleParameters(Copyable, Movable):
    """A vehicle model's catalog entry, CARLA's vehicle parameters."""

    var make: String
    var model: String
    # "car", "truck", "van", "bus", "motorcycle" or "bicycle".
    var base_type: String
    # "emergency", "taxi", "electric" or empty.
    var special_type: String
    var object_type: String
    var number_of_wheels: Int
    var generation: Int
    var has_dynamic_doors: Bool
    var has_lights: Bool
    var recommended_colors: List[Color]
    var supported_drivers: List[Int]


def _color_text(c: Color) -> String:
    return String(Int(c.r)) + "," + String(Int(c.g)) + "," + String(Int(c.b))


def _bool_text(b: Bool) -> String:
    return "true" if b else "false"


def make_vehicle_definition(p: VehicleParameters) raises -> ActorBlueprint:
    """Return a vehicle, `MakeVehicleDefinition`.

    Args:
        p: The model.

    Returns:
        `vehicle.<make>.<model>`: the colors and drivers when the model has
        any, sticky control, the terrain and ROS switches, then its fixed
        attributes.

    Raises:
        Error: If a fixed value does not read as its type.
    """
    var out = _definition(["vehicle", p.make, p.model])
    _set_role_names(out, ["autopilot", "scenario", "ego_vehicle"])
    if len(p.recommended_colors) > 0:
        var colors = List[String]()
        # The list is not empty, checked above.
        for c in p.recommended_colors:  # pragma: no branch
            colors.append(_color_text(c))
        out.attributes.append(
            ActorAttribute("color", ATTRIBUTE_RGB_COLOR, colors^)
        )
    if len(p.supported_drivers) > 0:
        var drivers = List[String]()
        # The list is not empty, checked above.
        for d in p.supported_drivers:  # pragma: no branch
            drivers.append(String(d))
        out.attributes.append(
            ActorAttribute("driver_id", ATTRIBUTE_INT, drivers^, True)
        )
    _add(out, "sticky_control", ATTRIBUTE_BOOL, "true")
    _add(out, "terramechanics", ATTRIBUTE_BOOL, "false")
    _add(out, "ros2_ackermann_control", ATTRIBUTE_BOOL, "false")
    out.attributes.append(
        ActorAttribute.fixed("object_type", ATTRIBUTE_STRING, p.object_type)
    )
    out.attributes.append(
        ActorAttribute.fixed("base_type", ATTRIBUTE_STRING, p.base_type)
    )
    out.attributes.append(
        ActorAttribute.fixed("special_type", ATTRIBUTE_STRING, p.special_type)
    )
    out.attributes.append(
        ActorAttribute.fixed(
            "number_of_wheels", ATTRIBUTE_INT, String(p.number_of_wheels)
        )
    )
    out.attributes.append(
        ActorAttribute.fixed("generation", ATTRIBUTE_INT, String(p.generation))
    )
    out.attributes.append(
        ActorAttribute.fixed(
            "has_dynamic_doors", ATTRIBUTE_BOOL, _bool_text(p.has_dynamic_doors)
        )
    )
    out.attributes.append(
        ActorAttribute.fixed(
            "has_lights", ATTRIBUTE_BOOL, _bool_text(p.has_lights)
        )
    )
    return out^


@fieldwise_init
struct PedestrianGender(Equatable, ImplicitlyCopyable, Writable):
    """A pedestrian's gender, CARLA's pedestrian gender."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a gender.

        Returns:
            Whether the value is from 0 to 2.
        """
        return self.value >= 0 and self.value <= 2


comptime GENDER_OTHER = PedestrianGender(0)
comptime GENDER_FEMALE = PedestrianGender(1)
comptime GENDER_MALE = PedestrianGender(2)


@fieldwise_init
struct PedestrianAge(Equatable, ImplicitlyCopyable, Writable):
    """A pedestrian's age group, CARLA's pedestrian age."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names an age group.

        Returns:
            Whether the value is from 0 to 3.
        """
        return self.value >= 0 and self.value <= 3


comptime AGE_CHILD = PedestrianAge(0)
comptime AGE_TEENAGER = PedestrianAge(1)
comptime AGE_ADULT = PedestrianAge(2)
comptime AGE_ELDERLY = PedestrianAge(3)


@fieldwise_init
struct PedestrianParameters(Copyable, Movable):
    """A pedestrian model's catalog entry, CARLA's pedestrian parameters."""

    # Such as "0015".
    var id: String
    var gender: PedestrianGender
    var age: PedestrianAge
    var generation: Int
    # The recommended speeds, in m/s: still, walking, running.
    var speeds: List[Float32]


def make_pedestrian_definition(
    p: PedestrianParameters,
) raises -> ActorBlueprint:
    """Return a pedestrian, `MakePedestrianDefinition`.

    Args:
        p: The model.

    Returns:
        `walker.pedestrian.<id>`: the gender, generation and age, the
        speeds when there are any, and `is_invincible`.

    Raises:
        Error: If the gender or the age is not valid.
    """
    if not (p.gender.is_valid() and p.age.is_valid()):
        raise Error("Pedestrian gender or age is not valid")
    var out = _definition(["walker", "pedestrian", p.id])
    _set_role_names(out, ["pedestrian"])
    var gender: List[String] = ["other", "female", "male"]
    var age: List[String] = ["child", "teenager", "adult", "elderly"]
    if len(p.speeds) > 0:
        var speeds = List[String]()
        # The list is not empty, checked above.
        for s in p.speeds:  # pragma: no branch
            speeds.append(String(s))
        out.attributes.append(ActorAttribute("speed", ATTRIBUTE_FLOAT, speeds^))
    _add(out, "is_invincible", ATTRIBUTE_BOOL, "true")
    out.attributes.append(
        ActorAttribute.fixed("gender", ATTRIBUTE_STRING, gender[p.gender.value])
    )
    out.attributes.append(
        ActorAttribute.fixed("generation", ATTRIBUTE_INT, String(p.generation))
    )
    out.attributes.append(
        ActorAttribute.fixed("age", ATTRIBUTE_STRING, age[p.age.value])
    )
    return out^


def make_trigger_definition(id: String) raises -> ActorBlueprint:
    """Return a trigger box, `MakeTriggerDefinition`.

    Args:
        id: Such as "friction".

    Returns:
        `static.trigger.<id>`: a friction of 3.5 and a 1 m half size.

    Raises:
        Error: Never for text; the attribute check is passed on.
    """
    var out = _definition(["static", "trigger", id])
    _add(out, "friction", ATTRIBUTE_FLOAT, "3.5f")
    _add(out, "extent_x", ATTRIBUTE_FLOAT, "1.0f")
    _add(out, "extent_y", ATTRIBUTE_FLOAT, "1.0f")
    _add(out, "extent_z", ATTRIBUTE_FLOAT, "1.0f")
    return out^


def make_static_mesh_definition() raises -> ActorBlueprint:
    """Return the generic prop, from CARLA's `StaticMeshFactory.cpp`.

    Returns:
        `static.prop.mesh`: a mesh path, a mass and a scale.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = _definition(["static", "prop", "mesh"])
    _add(out, "mesh_path", ATTRIBUTE_STRING, "")
    _add(out, "mass", ATTRIBUTE_FLOAT, "")
    _add(out, "scale", ATTRIBUTE_FLOAT, "1.0f")
    return out^


# --- the catalog --------------------------------------------------------------


def catalog_colors() -> List[Color]:
    """Return the colors this port offers every vehicle.

    CARLA's models carry their own colors as assets. These are this
    port's choice: white, black, silver, red and blue.

    Returns:
        The colors, the first being the one a vehicle starts with.
    """
    return [
        Color(255, 255, 255),
        Color(20, 20, 20),
        Color(170, 170, 170),
        Color(170, 20, 20),
        Color(20, 50, 140),
    ]


def _vehicle(
    make: String,
    model: String,
    base_type: String,
    special_type: String,
    generation: Int,
    lights: Bool,
    doors: Bool,
) -> VehicleParameters:
    return VehicleParameters(
        make,
        model,
        base_type,
        special_type,
        "",
        4,
        generation,
        doors,
        lights,
        catalog_colors(),
        List[Int](),
    )


def vehicle_catalog() -> List[VehicleParameters]:
    """Return the vehicles of CARLA's vehicle catalog.

    The make, model, base type, special type, generation, lights and
    doors are the catalog's. Every model has four wheels and the colors
    of `catalog_colors`.

    Returns:
        The models, in the catalog's order.
    """
    return [
        _vehicle("dodge", "charger", "car", "", 2, True, True),
        _vehicle("dodgecop", "charger", "car", "emergency", 2, True, True),
        _vehicle("taxi", "ford", "car", "taxi", 2, True, True),
        _vehicle("lincoln", "mkz", "car", "", 2, True, True),
        _vehicle("mini", "cooper", "car", "", 2, True, True),
        _vehicle("nissan", "patrol", "car", "", 2, True, True),
        _vehicle("carlacola", "actors", "truck", "", 1, False, False),
        _vehicle("firetruck", "actors", "truck", "emergency", 2, True, True),
        _vehicle("ambulance", "ford", "van", "emergency", 2, True, True),
        _vehicle("sprinter", "mercedes", "van", "", 2, True, True),
        _vehicle("fuso", "mitsubishi", "bus", "", 2, True, False),
        _vehicle("miningtruck", "miningtruck", "truck", "", 2, False, False),
    ]


def pedestrian_catalog() -> List[PedestrianParameters]:
    """Return the pedestrians of CARLA's pedestrian catalog.

    The ids 0015 to 0047 are adults and 0048 to 0051 children, as the
    catalog groups them. The gender "other", the generation 2 and the
    speeds 0, 1.4 and 2.8 m/s are this port's choice.

    Returns:
        The models, by id.
    """
    var out = List[PedestrianParameters]()
    for n in range(15, 52):  # pragma: no branch
        var id = String(n)
        while id.byte_length() < 4:
            id = "0" + id
        out.append(
            PedestrianParameters(
                id,
                GENDER_OTHER,
                AGE_CHILD if n >= 48 else AGE_ADULT,
                2,
                [0.0, 1.4, 2.8],
            )
        )
    return out^


def sensor_definitions() raises -> List[ActorBlueprint]:
    """Return every sensor blueprint.

    Returns:
        The cameras and their fisheye forms, the three LiDARs, the radar,
        GNSS, IMU, collision, lane-invasion and obstacle sensors, and the
        two V2X senders.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var out = List[ActorBlueprint]()
    out.append(make_camera_definition("rgb", True))
    out.append(make_camera_definition("depth"))
    out.append(make_camera_definition("semantic_segmentation"))
    out.append(make_camera_definition("instance_segmentation"))
    out.append(make_camera_definition("optical_flow"))
    out.append(make_normals_camera_definition())
    out.append(make_dvs_camera_definition())
    out.append(make_wide_angle_lens_camera_definition("rgb", True))
    out.append(make_wide_angle_lens_camera_definition("depth"))
    out.append(make_wide_angle_lens_camera_definition("semantic_segmentation"))
    out.append(make_wide_angle_lens_camera_definition("instance_segmentation"))
    for id in [
        "ray_cast",
        "ray_cast_semantic",
        "hss_lidar",
    ]:  # pragma: no branch
        out.append(make_lidar_definition(id))
    out.append(make_radar_definition())
    out.append(make_gnss_definition())
    out.append(make_imu_definition())
    out.append(make_generic_sensor_definition("other", "collision"))
    out.append(make_generic_sensor_definition("other", "lane_invasion"))
    out.append(make_obstacle_definition())
    out.append(make_v2x_definition())
    out.append(make_custom_v2x_definition())
    return out^


def default_blueprint_library() raises -> BlueprintLibrary:
    """Return the library a world starts with.

    Returns:
        The sensors, the catalog's vehicles and pedestrians,
        `controller.ai.walker`, `static.trigger.friction`,
        `static.prop.mesh` and `util.actor.empty`, sorted by id, with
        their `uid` counted from one.

    Raises:
        Error: Never; the attribute check is passed on.
    """
    var all = sensor_definitions()
    # The catalog is a constant and not empty.
    for v in vehicle_catalog():  # pragma: no branch
        all.append(make_vehicle_definition(v))
    # The catalog is a constant and not empty.
    for p in pedestrian_catalog():  # pragma: no branch
        all.append(make_pedestrian_definition(p))
    all.append(make_generic_definition("controller", "ai", "walker"))
    all.append(make_trigger_definition("friction"))
    all.append(make_static_mesh_definition())
    all.append(make_generic_definition("util", "actor", "empty"))
    var library = BlueprintLibrary(all^)
    # The library is not empty.
    for i in range(len(library.blueprints)):  # pragma: no branch
        library.blueprints[i].uid = i + 1
    return library^
