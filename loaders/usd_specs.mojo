# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The layer that three.js r186's USD parsers give its `USDComposer`: the
`{ specsByPath }` object of `examples/jsm/loaders/usd/USDAParser.js` and
`USDCParser.js`.

A layer maps each path, such as `/Root/Mesh` or `/Root/Mesh.points`, to
a spec: its `SpecType` and its fields. A field holds a JavaScript value.
`UsdLayer` keeps every value in one list, and a field names its value by
its place there. So a value can hold other values, as a JavaScript array
or object does, without a type that holds itself.

The paths keep the order in which they were first set, as a JavaScript
object keeps its keys. Setting a path again keeps its place. The same is
true of the fields of a spec.

A value is one of the kinds `UsdKind` names. An array of numbers is
`USD_NUMBERS` and an array of strings is `USD_STRINGS`, which is what
nearly every array is. `USD_ARRAY` holds any other array, one value for
each element. `USD_SAMPLES` is the `{ times, values }` object that
`timeSamples` holds.

**The JavaScript reads.** The composer reads a value as three.js does:
`truthy` is JavaScript's truthiness, `length` is `.length`, and
`element_number` is `Number( value[ i ] )`, which is what a
`Float32Array` stores.
"""

from loaders.js_number import js_string_to_number
from loaders.js_text import js_units
from std.math import nan


@fieldwise_init
struct SpecType(Equatable, ImplicitlyCopyable, Writable):
    """What a path of a layer is, as a type rather than a bare int: the
    `SpecType` of three.js's parsers and OpenUSD's `SdfSpecType`.

    The value is the number a USDC file stores. `parse_usdc` refuses one
    that `is_valid` does not accept.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the twelve spec types, zero to eleven."""
        return self.value >= 0 and self.value <= 11


comptime SPEC_UNKNOWN = SpecType(0)
# A property that holds a value: `/Mesh.points`.
comptime SPEC_ATTRIBUTE = SpecType(1)
comptime SPEC_CONNECTION = SpecType(2)
comptime SPEC_EXPRESSION = SpecType(3)
comptime SPEC_MAPPER = SpecType(4)
comptime SPEC_MAPPER_ARG = SpecType(5)
# A prim: `/Root/Mesh`.
comptime SPEC_PRIM = SpecType(6)
# The layer's root, `/`, in a USDC file.
comptime SPEC_PSEUDO_ROOT = SpecType(7)
# A property that names other paths: `/Mesh.material:binding`.
comptime SPEC_RELATIONSHIP = SpecType(8)
comptime SPEC_RELATIONSHIP_TARGET = SpecType(9)
# One choice of a variant set: `/Toy/{color=red}`.
comptime SPEC_VARIANT = SpecType(10)
# A variant set: `/Toy/{color=}`.
comptime SPEC_VARIANT_SET = SpecType(11)


@fieldwise_init
struct UsdKind(Equatable, ImplicitlyCopyable, Writable):
    """Which JavaScript value a `UsdValue` is, as a type rather than a
    bare int.

    `UsdLayer.add` refuses a kind that `is_valid` does not accept.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the ten kinds, zero to nine."""
        return self.value >= 0 and self.value <= 9


# `undefined`.
comptime USD_UNDEFINED = UsdKind(0)
# `null`, which the USDC parser gives for a type it does not read.
comptime USD_NULL = UsdKind(1)
comptime USD_BOOLEAN = UsdKind(2)
comptime USD_NUMBER = UsdKind(3)
comptime USD_STRING = UsdKind(4)
# An array whose elements are all numbers, in `numbers`.
comptime USD_NUMBERS = UsdKind(5)
# An array whose elements are all strings, in `strings`.
comptime USD_STRINGS = UsdKind(6)
# Any other array: each element is the value `items` names.
comptime USD_ARRAY = UsdKind(7)
# An object: each key of `strings` holds the value `items` names.
comptime USD_OBJECT = UsdKind(8)
# The `{ times, values }` of `timeSamples`: the times in `numbers`, and
# the value at each time named by `items`.
comptime USD_SAMPLES = UsdKind(9)

# The place of a value that is not there: `undefined`.
comptime NO_VALUE = -1


struct UsdValue(Copyable, Movable):
    """One JavaScript value of a layer. Which fields mean something
    depends on `kind`; see `UsdKind`."""

    var kind: UsdKind
    # A number, or 1 and 0 for a boolean.
    var number: Float64
    var text: String
    var numbers: List[Float64]
    var strings: List[String]
    var items: List[Int]

    def __init__(out self, kind: UsdKind):
        """Make an empty value of a kind.

        Args:
            kind: The kind.
        """
        self.kind = kind
        self.number = 0
        self.text = String()
        self.numbers = List[Float64]()
        self.strings = List[String]()
        self.items = List[Int]()


def usd_number(value: Float64) -> UsdValue:
    """Return a number.

    Args:
        value: The number.

    Returns:
        The value.
    """
    var out = UsdValue(USD_NUMBER)
    out.number = value
    return out^


def usd_boolean(value: Bool) -> UsdValue:
    """Return a boolean.

    Args:
        value: The boolean.

    Returns:
        The value.
    """
    var out = UsdValue(USD_BOOLEAN)
    out.number = 1 if value else 0
    return out^


def usd_string(text: String) -> UsdValue:
    """Return a string.

    Args:
        text: The string.

    Returns:
        The value.
    """
    var out = UsdValue(USD_STRING)
    out.text = text
    return out^


def usd_numbers(var numbers: List[Float64]) -> UsdValue:
    """Return an array of numbers.

    Args:
        numbers: The numbers.

    Returns:
        The value.
    """
    var out = UsdValue(USD_NUMBERS)
    out.numbers = numbers^
    return out^


def usd_strings(var strings: List[String]) -> UsdValue:
    """Return an array of strings.

    Args:
        strings: The strings.

    Returns:
        The value.
    """
    var out = UsdValue(USD_STRINGS)
    out.strings = strings^
    return out^


struct UsdSpec(Copyable, Movable):
    """One path's spec: its type and its fields, each field's name with
    the place of its value, in the order first set."""

    var spec_type: SpecType
    var names: List[String]
    var values: List[Int]

    def __init__(out self, spec_type: SpecType):
        """Make a spec with no fields.

        Args:
            spec_type: The spec's type.
        """
        self.spec_type = spec_type
        self.names = List[String]()
        self.values = List[Int]()

    def slot(self, name: String) -> Int:
        """Return where a field is.

        Args:
            name: The field.

        Returns:
            Its place in `names`, or -1.
        """
        for k in range(len(self.names)):
            if self.names[k] == name:
                return k
        return -1

    def field(self, name: String) -> Int:
        """Return the place of a field's value.

        Args:
            name: The field.

        Returns:
            The place, or `NO_VALUE` when the spec has no such field.
        """
        var at = self.slot(name)
        return self.values[at] if at >= 0 else NO_VALUE

    def set(mut self, name: String, value: Int):
        """Set a field, keeping its place when it is there.

        Args:
            name: The field.
            value: The place of its value.
        """
        var at = self.slot(name)
        if at < 0:
            self.names.append(name)
            self.values.append(value)
        else:
            self.values[at] = value


struct UsdLayer(Copyable, Movable):
    """The counterpart of three.js's `{ specsByPath }`: each path's spec, in the order the
    paths were first set, and every value the specs hold."""

    var paths: List[String]
    var specs: List[UsdSpec]
    var values: List[UsdValue]
    var _index: Dict[String, Int]

    def __init__(out self):
        """Make a layer with no paths."""
        self.paths = List[String]()
        self.specs = List[UsdSpec]()
        self.values = List[UsdValue]()
        self._index = Dict[String, Int]()

    def add(mut self, var value: UsdValue) raises -> Int:
        """Keep a value.

        Args:
            value: The value.

        Returns:
            Its place.

        Raises:
            Error: If its kind is not valid.
        """
        if not value.kind.is_valid():
            raise Error("USD: a value of no kind: " + String(value.kind.value))
        self.values.append(value^)
        return len(self.values) - 1

    def spec(self, path: String) -> Int:
        """Return where a path's spec is.

        Args:
            path: The path.

        Returns:
            Its place in `specs`, or -1.
        """
        var found = self._index.get(path)
        return found.value() if found else -1

    def put(mut self, path: String, var spec: UsdSpec) -> Int:
        """Set a path's spec, keeping the path's place when it is there, as
        `specsByPath[ path ] = spec` does.

        Args:
            path: The path.
            spec: The spec.

        Returns:
            The spec's place.
        """
        var at = self.spec(path)
        if at >= 0:
            self.specs[at] = spec^
            return at
        self.paths.append(path)
        self.specs.append(spec^)
        self._index[path] = len(self.specs) - 1
        return len(self.specs) - 1

    def field(self, path: String, name: String) -> Int:
        """Return `specsByPath[ path ]?.fields[ name ]`.

        Args:
            path: The path.
            name: The field.

        Returns:
            The place of its value, or `NO_VALUE`.
        """
        var at = self.spec(path)
        if at < 0:
            return NO_VALUE
        return self.specs[at].field(name)

    def kind(self, id: Int) -> UsdKind:
        """Return a value's kind.

        Args:
            id: The value's place, or `NO_VALUE`.

        Returns:
            Its kind: `USD_UNDEFINED` for `NO_VALUE`.
        """
        if id < 0:
            return USD_UNDEFINED
        return self.values[id].kind

    def defined(self, id: Int) -> Bool:
        """Return `value !== undefined`.

        Args:
            id: The value's place, or `NO_VALUE`.

        Returns:
            Whether the value is there.
        """
        return self.kind(id) != USD_UNDEFINED

    def truthy(self, id: Int) -> Bool:
        """Return JavaScript's truthiness of a value.

        Args:
            id: The value's place, or `NO_VALUE`.

        Returns:
            False for `undefined`, `null`, `false`, zero, NaN and the empty
            string, and True for anything else, an empty array too.
        """
        var kind = self.kind(id)
        if kind == USD_UNDEFINED or kind == USD_NULL:
            return False
        if kind == USD_BOOLEAN or kind == USD_NUMBER:
            var n = self.values[id].number
            return n == n and n != 0
        if kind == USD_STRING:
            return self.values[id].text.byte_length() > 0
        return True

    def is_array(self, id: Int) -> Bool:
        """Return `Array.isArray( value )`.

        Args:
            id: The value's place.

        Returns:
            Whether it is an array.
        """
        var kind = self.kind(id)
        return kind == USD_NUMBERS or kind == USD_STRINGS or kind == USD_ARRAY

    def is_string(self, id: Int) -> Bool:
        """Return `typeof value === 'string'`.

        Args:
            id: The value's place.

        Returns:
            Whether it is a string.
        """
        return self.kind(id) == USD_STRING

    def is_number(self, id: Int) -> Bool:
        """Return `typeof value === 'number'`.

        Args:
            id: The value's place.

        Returns:
            Whether it is a number.
        """
        return self.kind(id) == USD_NUMBER

    def number(self, id: Int) -> Float64:
        """Return a number's value.

        Args:
            id: The value's place. It must be a number or a boolean.

        Returns:
            The number.
        """
        return self.values[id].number

    def text(self, id: Int) -> String:
        """Return a string's text.

        Args:
            id: The value's place. It must be a string.

        Returns:
            The text.
        """
        return self.values[id].text

    def length(self, id: Int) -> Int:
        """Return `value.length` for an array or a string.

        Args:
            id: The value's place.

        Returns:
            The count of elements, or of UTF-16 units for a string, or -1
            for a value that has no length.
        """
        var kind = self.kind(id)
        if kind == USD_NUMBERS:
            return len(self.values[id].numbers)
        if kind == USD_STRINGS:
            return len(self.values[id].strings)
        if kind == USD_ARRAY:
            return len(self.values[id].items)
        if kind == USD_STRING:
            return len(js_units(self.values[id].text))
        return -1

    def to_number(self, id: Int) -> Float64:
        """Return JavaScript's `Number( value )`.

        Args:
            id: The value's place, or `NO_VALUE`.

        Returns:
            The number: a string read as `Number` reads it, `null` zero,
            `undefined` NaN, a boolean one or zero, an array of no elements
            zero, an array of one element that element read as its text
            is, and NaN for anything else.
        """
        var kind = self.kind(id)
        if kind == USD_NUMBER or kind == USD_BOOLEAN:
            return self.values[id].number
        if kind == USD_STRING:
            return js_string_to_number(self.values[id].text)
        if kind == USD_NULL:
            return 0
        var count = self.length(id)
        if count == 0:
            return 0
        if count == 1:
            return self._single(id)
        return nan[DType.float64]()

    def _single(self, id: Int) -> Float64:
        """Return `Number( [ x ] )`: the number the text of `x` reads as.

        Args:
            id: An array of one element.

        Returns:
            The number.
        """
        var kind = self.kind(id)
        if kind == USD_NUMBERS:
            return self.values[id].numbers[0]
        if kind == USD_STRINGS:
            return js_string_to_number(self.values[id].strings[0])
        var item = self.values[id].items[0]
        var inner = self.kind(item)
        # `String( [ null ] )` and `String( [ undefined ] )` are empty.
        if inner == USD_NULL or inner == USD_UNDEFINED:
            return 0
        if inner == USD_BOOLEAN or inner == USD_OBJECT or inner == USD_SAMPLES:
            return nan[DType.float64]()
        return self.to_number(item)

    def element_number(self, id: Int, index: Int) -> Float64:
        """Return `Number( value[ index ] )`, what a `Float32Array` or an
        `Int32Array` is given.

        Args:
            id: An array's place.
            index: The element.

        Returns:
            The element as a number, and NaN past the end, where JavaScript
            reads `undefined`.
        """
        var kind = self.kind(id)
        if index < 0 or index >= self.length(id):
            return nan[DType.float64]()
        if kind == USD_NUMBERS:
            return self.values[id].numbers[index]
        if kind == USD_STRINGS:
            return js_string_to_number(self.values[id].strings[index])
        return self.to_number(self.values[id].items[index])

    def element_string(self, id: Int, index: Int) -> Optional[String]:
        """Return `value[ index ]` when it is a string.

        Args:
            id: An array's place.
            index: The element.

        Returns:
            The string, or nothing when the element is not a string.
        """
        var kind = self.kind(id)
        if index < 0 or index >= self.length(id):
            return None
        if kind == USD_STRINGS:
            return self.values[id].strings[index]
        if kind == USD_ARRAY:
            var item = self.values[id].items[index]
            if self.kind(item) == USD_STRING:
                return self.values[item].text
        return None

    def numbers(self, id: Int) -> List[Float64]:
        """Return each element of an array as a number.

        Args:
            id: An array's place.

        Returns:
            `Number( element )` of each element.
        """
        var kind = self.kind(id)
        if kind == USD_NUMBERS:
            return self.values[id].numbers.copy()
        var out = List[Float64]()
        for k in range(self.length(id)):
            out.append(self.element_number(id, k))
        return out^

    def object_value(self, id: Int, key: String) -> Int:
        """Return `object[ key ]` of an object.

        Args:
            id: An object's place.
            key: The key.

        Returns:
            The place of its value, or `NO_VALUE`.
        """
        if self.kind(id) != USD_OBJECT:
            return NO_VALUE
        ref value = self.values[id]
        for k in range(len(value.strings)):
            if value.strings[k] == key:
                return value.items[k]
        return NO_VALUE
