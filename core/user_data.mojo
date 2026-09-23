# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a caller keeps on a node, three.js's `Object3D.userData`.

three.js's `userData` is a plain object that `toJSON` writes and
`ObjectLoader` reads back, so what goes in it has to be JSON. Here it is
exactly that: a map from a string key to one JSON value, kept in the order
the keys were first set, as a JavaScript object keeps them.

**Each value is kept as its JSON text.** A value can hold an array or an
object, which holds values in turn, and Mojo has no good spelling for a
struct that holds a `List` of itself -- see `loaders.json`. So a value is
stored as text, written the one way this module writes it, and read back
with `loaders.json` when a caller asks for its parts. `set_json` takes any
one JSON value and rewrites it that way, so two values that mean the same
thing are stored as the same text.

**Numbers are written as `JSON.stringify` writes them where that is
cheap.** A whole number below two to the fifty-three is written without a
point or an exponent. Any other number is written as Mojo writes a
`Float64`, which reads back to the same `Float64` but can differ in form:
`1e-07` where JavaScript writes `1e-7`. Both are JSON. A number that is
not finite is refused, as JSON has no text for one.

**Keys that look like array indices keep their place.** A JavaScript object
lists such keys first, in numeric order. This keeps every key where it was
first set.
"""

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    JsonKind,
    parse_json,
    quote_json,
)
from std.math import isfinite

# The largest number every whole `Float64` below it is exactly, two to the
# fifty-three. Whole numbers below it are written as integers.
comptime _EXACT = Float64(9007199254740992.0)


def json_number_text(value: Float64) raises -> String:
    """Return a number as JSON text, as `JSON.stringify` writes a whole one.

    Args:
        value: The number.

    Returns:
        A whole number below two to the fifty-three without a point, and
        any other number as Mojo writes it. Negative zero is `0`.

    Raises:
        Error: If the number is not finite.
    """
    if not isfinite(value):
        raise Error("User data: a number must be finite: " + String(value))
    if abs(value) < _EXACT and Float64(Int(value)) == value:
        return String(Int(value))
    return String(value)


def json_value_text(document: JsonDocument, node: Int) raises -> String:
    """Return one value of a parsed document as JSON text, as this module
    stores it.

    Objects keep their first order of keys, and a key named twice keeps its
    last value, as `JSON.parse` does.

    Args:
        document: The document.
        node: The value's index in it.

    Returns:
        The text.

    Raises:
        Error: If the index names no node.
    """
    var kind = document.kind(node)
    if kind == OBJECT:
        var out = String("{")
        var written = List[String]()
        for at in range(document.length(node)):
            var key = document.key(node, at)
            if key in written:
                continue
            if len(written) > 0:
                out += ","
            written.append(key)
            out += quote_json(key)
            out += ":"
            out += json_value_text(document, document.get(node, key))
        return out + "}"
    if kind == ARRAY:
        var out = String("[")
        for at in range(document.length(node)):
            if at > 0:
                out += ","
            out += json_value_text(document, document.at(node, at))
        return out + "]"
    if kind == STRING:
        return quote_json(document.string(node))
    if kind == NUMBER:
        return json_number_text(document.number(node))
    if kind == BOOLEAN:
        return "true" if document.boolean(node) else "false"
    return "null"


struct UserData(Copyable, Movable):
    """A map from a string key to a JSON value, in the order the keys were
    first set."""

    var _keys: List[String]
    # Each key's value, as JSON text written by `json_value_text`.
    var _values: List[String]

    def __init__(out self):
        """Create an empty map, as three.js's `userData = {}`."""
        self._keys = List[String]()
        self._values = List[String]()

    def __init__(out self, *, copy: Self):
        """Copy another map, every value included, as three.js's `copy`
        does with `JSON.parse(JSON.stringify(userData))`."""
        self._keys = copy._keys.copy()
        self._values = copy._values.copy()

    def count(self) -> Int:
        """Return how many keys the map holds."""
        return len(self._keys)

    def key(self, index: Int) raises -> String:
        """Return a key by position.

        Args:
            index: Which key, in the order the keys were first set.

        Returns:
            The key.

        Raises:
            Error: If no key has that position.
        """
        if index < 0 or index >= len(self._keys):
            raise Error("User data: no key at position " + String(index))
        return self._keys[index]

    def _find(self, key: String) -> Int:
        """Return a key's position, or -1."""
        for index in range(len(self._keys)):
            if self._keys[index] == key:
                return index
        return -1

    def has(self, key: String) -> Bool:
        """Return True if the map holds a key.

        Args:
            key: The key.

        Returns:
            Whether it is there.
        """
        return self._find(key) >= 0

    def json(self, key: String) raises -> String:
        """Return a key's value as JSON text.

        Args:
            key: The key.

        Returns:
            The text.

        Raises:
            Error: If the map does not hold the key.
        """
        var index = self._find(key)
        if index < 0:
            raise Error("User data: no key " + quote_json(key))
        return self._values[index]

    def kind(self, key: String) raises -> JsonKind:
        """Return what a key's value is.

        Args:
            key: The key.

        Returns:
            Its JSON kind.

        Raises:
            Error: If the map does not hold the key.
        """
        return parse_json(self.json(key)).kind(0)

    def number(self, key: String) raises -> Float64:
        """Return a key's value as a number.

        Args:
            key: The key.

        Returns:
            The number.

        Raises:
            Error: If the map does not hold the key, or the value is not a
                number.
        """
        return parse_json(self.json(key)).number(0)

    def string(self, key: String) raises -> String:
        """Return a key's value as a string.

        Args:
            key: The key.

        Returns:
            The string, its escapes resolved.

        Raises:
            Error: If the map does not hold the key, or the value is not a
                string.
        """
        return parse_json(self.json(key)).string(0)

    def boolean(self, key: String) raises -> Bool:
        """Return a key's value as a truth.

        Args:
            key: The key.

        Returns:
            The truth.

        Raises:
            Error: If the map does not hold the key, or the value is not
                `true` or `false`.
        """
        return parse_json(self.json(key)).boolean(0)

    def _put(mut self, key: String, text: String):
        """Set a key to a value's text: in its place when it is there, at
        the end when it is not."""
        var index = self._find(key)
        if index < 0:
            self._keys.append(key)
            self._values.append(text)
        else:
            self._values[index] = text

    def set_json(mut self, key: String, text: String) raises:
        """Set a key to any one JSON value, given as text.

        Args:
            key: The key.
            text: One JSON value: an object, an array, a string, a number,
                `true`, `false` or `null`.

        Raises:
            Error: If the text is not one JSON value. The map is left as
                it was.
        """
        var document = parse_json(text)
        self._put(key, json_value_text(document, 0))

    def set_number(mut self, key: String, value: Float64) raises:
        """Set a key to a number.

        Args:
            key: The key.
            value: The number.

        Raises:
            Error: If the number is not finite. The map is left as it was.
        """
        self._put(key, json_number_text(value))

    def set_string(mut self, key: String, value: String):
        """Set a key to a string.

        Args:
            key: The key.
            value: The string.
        """
        self._put(key, quote_json(value))

    def set_boolean(mut self, key: String, value: Bool):
        """Set a key to `true` or `false`.

        Args:
            key: The key.
            value: The truth.
        """
        self._put(key, "true" if value else "false")

    def set_null(mut self, key: String):
        """Set a key to `null`.

        Args:
            key: The key.
        """
        self._put(key, "null")

    def remove(mut self, key: String) -> Bool:
        """Remove a key, three.js's `delete userData[key]`.

        Args:
            key: The key.

        Returns:
            True if the key was there.
        """
        var index = self._find(key)
        if index < 0:
            return False
        _ = self._keys.pop(index)
        _ = self._values.pop(index)
        return True

    def to_json(self) -> String:
        """Return the whole map as one JSON object.

        Returns:
            The object's text, its keys in order.
        """
        var out = String("{")
        for index in range(len(self._keys)):
            if index > 0:
                out += ","
            out += quote_json(self._keys[index])
            out += ":"
            out += self._values[index]
        return out + "}"


def user_data_of(document: JsonDocument, node: Int) raises -> UserData:
    """Return the user data an object of a parsed document holds.

    Args:
        document: The document.
        node: The object's index.

    Returns:
        Its keys and values, in its order. A key named twice keeps its
        last value, as `JSON.parse` does.

    Raises:
        Error: If the node is not an object.
    """
    if document.kind(node) != OBJECT:
        raise Error("User data must be a JSON object")
    var data = UserData()
    for at in range(document.length(node)):
        var key = document.key(node, at)
        data._put(key, json_value_text(document, document.get(node, key)))
    return data^
