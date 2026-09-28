# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""USDA text layers, from three.js r186's
`examples/jsm/loaders/usd/USDAParser.js`.

`parse_usda_layer` reads USDA text into a `UsdLayer`, as three.js's
`parseData` reads it into `{ specsByPath }`. It works in three steps, as
three.js does.

**The text.** `preprocess_usda` is three.js's `_preprocess`. It drops
`/* */` comments and `#` comments outside strings, keeps the `#usda`
line, puts a triple-quoted string on one line with `\\n` for each line
break, and joins an array that runs over several lines into one line.
Each line is trimmed.

**The tree.** `usda_tree` is three.js's `parseText`. It reads a line at a
time into a tree of named texts and groups. A line with `=` sets its left
side to its right side, or opens a group when the right side ends with
`{`. When the right side ends with `(`, the group that opens holds the
value's metadata, beside the value. A line such as `1.5: (1, 2, 3)` sets
a time sample. A line that ends with `{` or `(` opens a group named by
the last line that named nothing, and `}` and `)` close.

**The layer.** Each `def` key is a prim at its path, with its type. Its
attributes are the keys with a type and a name, such as `float3
xformOp:scale`; a `rel` key is a relationship. `prepend references`,
`payload`, `variants` and `xformOpOrder` are the prim's fields.
`attribute_value` reads a value by its type as three.js's
`_parseAttributeValue` does: an array as JSON after `(` and `)` become
`[` and `]`, and a vector, a matrix and a number with `parseFloat`.

**Where three.js's quirks are kept.** A line with `:` and no `=` is not a
name. A key such as `custom float x` is an attribute of type `custom`
named `float x`. A time sample's value keeps the comma after it, so
`(1, 2, 3),` reads as four numbers, the last NaN. A variant set's
contents are not prims, and a `variants` selection is kept but has no
effect in the composer, as in three.js.

**What is refused.** A write into a string or into nothing, which throws
in three.js's strict mode; a group where three.js calls `replace` on a
string; a string where three.js reorders a quaternion array; and a
quaternion array whose length is not a multiple of four, which three.js
pads with `undefined`.
"""

from loaders.js_number import js_parse_float
from loaders.js_text import is_js_space, js_string, js_trim, js_units
from loaders.json import (
    ARRAY,
    BOOLEAN,
    JsonDocument,
    NULL,
    NUMBER,
    STRING,
    parse_json,
)
from loaders.three_mf import js_key_order
from loaders.usd_specs import (
    SPEC_ATTRIBUTE,
    SPEC_PRIM,
    SPEC_RELATIONSHIP,
    USD_ARRAY,
    USD_NULL,
    USD_NUMBERS,
    USD_OBJECT,
    USD_SAMPLES,
    USD_STRING,
    USD_STRINGS,
    USD_UNDEFINED,
    UsdLayer,
    UsdSpec,
    UsdValue,
    usd_boolean,
    usd_number,
    usd_numbers,
    usd_string,
    usd_strings,
)
from std.math import nan

# What a stack entry or the target is when it is not a group: a string,
# which a strict-mode write throws on, or nothing.
comptime _PRIMITIVE = -2
comptime _UNDEFINED = -1
# `String( object )`.
comptime _OBJECT_TEXT = "[object Object]"


def _is_space(byte: UInt8) -> Bool:
    """Return True for an ASCII byte that JavaScript's `\\s` matches.

    Args:
        byte: The byte.

    Returns:
        Whether it is a space, a tab, a line feed, a vertical tab, a form
        feed or a carriage return.
    """
    return byte == 0x20 or (byte >= 0x09 and byte <= 0x0D)


def _is_word(byte: UInt8) -> Bool:
    """Return True for a byte that JavaScript's `\\w` matches.

    Args:
        byte: The byte.

    Returns:
        Whether it is a letter, a digit or `_`.
    """
    return (
        (byte >= 0x30 and byte <= 0x39)
        or (byte >= 0x41 and byte <= 0x5A)
        or (byte >= 0x61 and byte <= 0x7A)
        or byte == 0x5F
    )


def _trim(text: String) -> String:
    """Return JavaScript's `text.trim()`.

    Args:
        text: The text.

    Returns:
        The text less white space at both ends, Unicode white space too.
    """
    var bytes = text.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end and _is_space(bytes[start]):
        start += 1
    while end > start and _is_space(bytes[end - 1]):
        end -= 1
    var ascii = (start == end) or (
        bytes[start] < 0x80 and bytes[end - 1] < 0x80
    )
    if ascii:
        return String(text[byte=start:end])
    var units = js_trim(js_units(text))
    return js_string(units, 0, len(units))


def _trim_end(text: String) -> String:
    """Return JavaScript's `text.trimEnd()`.

    Args:
        text: The text.

    Returns:
        The text less white space at its end.
    """
    var units = js_units(text)
    var end = len(units)
    while end > 0 and is_js_space(units[end - 1]):
        end -= 1
    return js_string(units, 0, end)


def _run(bytes: Span[UInt8, _], start: Int, space: Bool) -> Int:
    """Return how long a run of white space, or of word characters, is.

    Args:
        bytes: The text.
        start: Where the run starts.
        space: True for white space, False for word characters.

    Returns:
        The run's length.
    """
    var end = start
    while end < len(bytes) and (
        _is_space(bytes[end]) if space else _is_word(bytes[end])
    ):
        end += 1
    return end - start


def _quoted_tail(text: String, start: Int) -> Optional[String]:
    """Match `"?([^"]+)"?$` at a place, as a regular expression does.

    Args:
        text: The text.
        start: Where the match starts.

    Returns:
        The group, or nothing when the tail does not match.
    """
    var bytes = text.as_bytes()
    var n = len(bytes)
    for skip in [1, 0]:  # pragma: no branch
        if skip == 1 and (start >= n or bytes[start] != 0x22):
            continue
        var first = start + skip
        var last = first
        while last < n and bytes[last] != 0x22:
            last += 1
        if last == first:
            continue
        # A shorter run leaves a character that is not a quote, which
        # neither the last `"?` nor `$` can take.
        if last == n or (last + 1 == n):
            return String(text[byte=first:last])
    return None


def def_match(key: String) -> Optional[Tuple[String, String]]:
    """Match three.js's `DEF_MATCH_REGEX`, `^def\\s+(?:(\\w+)\\s+)?"?([^"]+)"?$`.

    Args:
        key: A key of the tree.

    Returns:
        The prim's type, empty when there is none, and its name; or
        nothing when the key is not a `def`.
    """
    var bytes = key.as_bytes()
    if not key.startswith("def"):
        return None
    var spaces = _run(bytes, 3, True)
    var taken = spaces
    while taken > 0:
        var at = 3 + taken
        var word = _run(bytes, at, False)
        if word > 0:
            var gap = _run(bytes, at + word, True)
            while gap > 0:
                var name = _quoted_tail(key, at + word + gap)
                if Bool(name):
                    return (String(key[byte = at : at + word]), name.value())
                gap -= 1
        var bare = _quoted_tail(key, at)
        if Bool(bare):
            return (String(""), bare.value())
        taken -= 1
    return None


def attribute_match(key: String) -> Optional[Tuple[String, String]]:
    """Match three.js's `ATTR_MATCH_REGEX`,
    `^(?:uniform\\s+)?(\\w+(?:\\[\\])?)\\s+(.+)$`.

    Args:
        key: A key of the tree.

    Returns:
        The value's type and the attribute's name, or nothing.
    """
    var bytes = key.as_bytes()
    var starts = List[Int]()
    if key.startswith("uniform"):
        var spaces = _run(bytes, 7, True)
        if spaces > 0:
            starts.append(7 + spaces)
    starts.append(0)
    for start in starts:  # pragma: no branch
        var word = _run(bytes, start, False)
        if word == 0:
            continue
        var end = start + word
        var ends = List[Int]()
        if String(key[byte = end : min(end + 2, len(bytes))]) == "[]":
            ends.append(end + 2)
        ends.append(end)
        for type_end in ends:  # pragma: no branch
            var gap = _run(bytes, type_end, True)
            while gap > 0:
                if type_end + gap < len(bytes):
                    return (
                        String(key[byte=start:type_end]),
                        String(key[byte = type_end + gap :]),
                    )
                gap -= 1
    return None


def _variant_match(key: String) -> Optional[String]:
    """Match three.js's `VARIANT_STRING_REGEX`, `^string\\s+(\\w+)$`.

    Args:
        key: A key of the `variants` group.

    Returns:
        The variant set's name, or nothing.
    """
    var bytes = key.as_bytes()
    if not key.startswith("string"):
        return None
    var spaces = _run(bytes, 6, True)
    var word = _run(bytes, 6 + spaces, False)
    if spaces == 0 or word == 0 or 6 + spaces + word != len(bytes):
        return None
    return String(key[byte = 6 + spaces :])


def _is_frame(key: String) -> Bool:
    """Match `^[\\d.]+$`.

    Args:
        key: The text before a `:`.

    Returns:
        Whether it is digits and points only, and not empty.
    """
    var bytes = key.as_bytes()
    for byte in bytes:
        if not ((byte >= 0x30 and byte <= 0x39) or byte == 0x2E):
            return False
    return len(bytes) > 0


def _strip_block_comments(text: String) -> String:
    """Drop each `/* */` comment, three.js's `_stripBlockComments`. An
    unclosed one runs to the end.

    Args:
        text: The text.

    Returns:
        The text less its block comments.
    """
    var bytes = text.as_bytes()
    var n = len(bytes)
    var out = List[UInt8](capacity=n)
    var i = 0
    while i < n:
        if bytes[i] == 0x2F and i + 1 < n and bytes[i + 1] == 0x2A:
            var j = i + 2
            while j < n:
                if bytes[j] == 0x2A and j + 1 < n and bytes[j + 1] == 0x2F:
                    j += 2
                    break
                j += 1
            i = j
        else:
            out.append(bytes[i])
            i += 1
    return String(unsafe_from_utf8=out)


def _is_triple(bytes: Span[UInt8, _], at: Int, quote: UInt8) -> Bool:
    """Return True when three quotes of one kind start at a place.

    Args:
        bytes: The text.
        at: The place. Three bytes must follow it.
        quote: `'` or `"`.

    Returns:
        Whether they are three of that quote.
    """
    return (
        bytes[at] == quote and bytes[at + 1] == quote and bytes[at + 2] == quote
    )


def _collapse_triple_quotes(text: String) -> String:
    """Put each triple-quoted string on one line, three.js's
    `_collapseTripleQuotedStrings`: a line feed becomes `\\n`, and a
    carriage return is dropped.

    Args:
        text: The text.

    Returns:
        The text with its long strings on one line.
    """
    var bytes = text.as_bytes()
    var n = len(bytes)
    var out = List[UInt8](capacity=n)
    var i = 0
    while i < n:
        var quote = UInt8(0)
        if i + 2 < n:
            if _is_triple(bytes, i, 0x27):
                quote = 0x27
            elif _is_triple(bytes, i, 0x22):
                quote = 0x22
        if quote == 0:
            out.append(bytes[i])
            i += 1
            continue
        for _ in range(3):  # pragma: no branch
            out.append(quote)
        i += 3
        while i < n:
            if i + 2 < n and _is_triple(bytes, i, quote):
                for _ in range(3):  # pragma: no branch
                    out.append(quote)
                i += 3
                break
            if bytes[i] == 0x0A:
                out.append(0x5C)
                out.append(0x6E)
            elif bytes[i] != 0x0D:
                out.append(bytes[i])
            i += 1
    return String(unsafe_from_utf8=out)


def _outside_strings(line: String, target: UInt8) -> Int:
    """Find a byte outside quotes, as three.js's `_stripInlineComment`
    and `_findAssignmentOperator` scan: a backslash escapes the next
    character, and `"` and `'` open strings.

    Args:
        line: The line.
        target: `#` or `=`.

    Returns:
        Where the first one outside a string is, or -1.
    """
    var bytes = line.as_bytes()
    var inside = UInt8(0)
    var escaped = False
    for i in range(len(bytes)):
        var byte = bytes[i]
        if escaped:
            escaped = False
            continue
        if byte == 0x5C:
            escaped = True
            continue
        if inside == 0 and (byte == 0x22 or byte == 0x27):
            inside = byte
        elif inside != 0 and byte == inside:
            inside = 0
        elif inside == 0 and byte == target:
            return i
    return -1


def _strip_inline_comment(line: String) -> String:
    """Drop a `#` comment outside strings, three.js's
    `_stripInlineComment`. The `#usda` line is kept.

    Args:
        line: The line.

    Returns:
        The line less its comment, less white space at its end when it
        had a comment.
    """
    if _trim(line).startswith("#usda"):
        return line
    var at = _outside_strings(line, 0x23)
    if at < 0:
        return line
    return _trim_end(String(line[byte=:at]))


def find_assignment(line: String) -> Int:
    """Find the first `=` outside quotes, three.js's
    `_findAssignmentOperator`.

    Args:
        line: The line.

    Returns:
        Where it is, or -1.
    """
    return _outside_strings(line, 0x3D)


def _count(text: String, byte: UInt8) -> Int:
    """Count a byte in a text.

    Args:
        text: The text.
        byte: The byte.

    Returns:
        How many times it is there.
    """
    var n = 0
    for b in text.as_bytes():
        if b == byte:
            n += 1
    return n


def preprocess_usda(text: String) -> String:
    """Clean USDA text for the tree, three.js's `_preprocess`.

    Args:
        text: The text.

    Returns:
        The lines, each trimmed, with no comments, each long string on
        one line, and each array that ran over several lines on one line.
        An array still open at the end is dropped, as in three.js.
    """
    var cleaned = _collapse_triple_quotes(_strip_block_comments(text))
    var out = List[String]()
    var multiline = False
    var brackets = 0
    var parentheses = 0
    var joined = String()
    for raw in cleaned.split("\n"):  # pragma: no branch
        var trimmed = _trim(_strip_inline_comment(String(raw)))
        if multiline:
            joined += " " + trimmed
            for byte in trimmed.as_bytes():
                if byte == 0x5B:
                    brackets += 1
                elif byte == 0x5D:
                    brackets -= 1
                elif byte == 0x28 and brackets > 0:
                    parentheses += 1
                elif byte == 0x29 and brackets > 0:
                    parentheses -= 1
            if brackets == 0 and parentheses == 0:
                out.append(joined)
                joined = String()
                multiline = False
            continue
        var equals = find_assignment(trimmed)
        if equals >= 0:
            var rhs = _trim(String(trimmed[byte = equals + 1 :]))
            var opened = _count(rhs, 0x5B)
            var closed = _count(rhs, 0x5D)
            if opened > closed:
                multiline = True
                brackets = opened - closed
                parentheses = 0
                joined = trimmed
                continue
        out.append(trimmed)
    return String("\n").join(out)


struct _Group(Copyable, Movable):
    """One group of the tree: its keys in the order first set, each key's
    text or group, and the metadata group of each key that has one."""

    var keys: List[String]
    var texts: List[String]
    # The group a key holds, or -1 when it holds text.
    var kids: List[Int]
    var index: Dict[String, Int]
    var meta_keys: List[String]
    var meta_kids: List[Int]

    def __init__(out self):
        """Start with no keys."""
        self.keys = List[String]()
        self.texts = List[String]()
        self.kids = List[Int]()
        self.index = Dict[String, Int]()
        self.meta_keys = List[String]()
        self.meta_kids = List[Int]()


struct UsdaTree(Copyable, Movable):
    """What three.js's `parseText` makes: groups of named texts and
    groups, the root at zero."""

    var groups: List[_Group]

    def __init__(out self):
        """Start with the root group."""
        self.groups = [_Group()]

    def add(mut self) -> Int:
        """Add an empty group.

        Returns:
            Its index.
        """
        self.groups.append(_Group())
        return len(self.groups) - 1

    def slot(self, group: Int, key: String) -> Int:
        """Return where a key is in a group.

        Args:
            group: The group.
            key: The key.

        Returns:
            Its place, or -1.
        """
        var found = self.groups[group].index.get(key)
        return found.value() if found else -1

    def set(mut self, group: Int, key: String, text: String, kid: Int):
        """Set a key, keeping its place when it is there, as JavaScript
        does.

        Args:
            group: The group.
            key: The key.
            text: The text, when `kid` is -1.
            kid: The group it holds, or -1 for text.
        """
        var at = self.slot(group, key)
        if at < 0:
            self.groups[group].index[key] = len(self.groups[group].keys)
            self.groups[group].keys.append(key)
            self.groups[group].texts.append(text)
            self.groups[group].kids.append(kid)
        else:
            self.groups[group].texts[at] = text
            self.groups[group].kids[at] = kid

    def text(self, group: Int, key: String) -> Optional[String]:
        """Return a key's text.

        Args:
            group: The group.
            key: The key.

        Returns:
            The text, or nothing when the key is missing or holds a group.
        """
        var at = self.slot(group, key)
        if at < 0 or self.groups[group].kids[at] >= 0:
            return None
        return self.groups[group].texts[at]

    def kid(self, group: Int, key: String) -> Int:
        """Return the group a key holds.

        Args:
            group: The group.
            key: The key.

        Returns:
            The group, or -1 when the key is missing or holds text.
        """
        var at = self.slot(group, key)
        if at < 0:
            return -1
        return self.groups[group].kids[at]

    def set_meta(mut self, group: Int, key: String, meta: Int):
        """Set a key's metadata group, three.js's
        `target[ VALUE_METADATA ][ key ] = meta`.

        Args:
            group: The group that holds the key.
            key: The key.
            meta: The metadata group.
        """
        for k in range(len(self.groups[group].meta_keys)):
            if self.groups[group].meta_keys[k] == key:
                self.groups[group].meta_kids[k] = meta
                return
        self.groups[group].meta_keys.append(key)
        self.groups[group].meta_kids.append(meta)

    def meta(self, group: Int, key: String) -> Int:
        """Return a key's metadata group.

        Args:
            group: The group that holds the key.
            key: The key.

        Returns:
            The metadata group, or -1.
        """
        for k in range(len(self.groups[group].meta_keys)):
            if self.groups[group].meta_keys[k] == key:
                return self.groups[group].meta_kids[k]
        return -1

    def order(self, group: Int) -> List[Int]:
        """Return a group's places in JavaScript's key order.

        Args:
            group: The group.

        Returns:
            The places.
        """
        var out = List[Int]()
        for key in js_key_order(self.groups[group].keys):
            out.append(self.slot(group, key))
        return out^


def _write(target: Int) raises:
    """Refuse a write into what is not a group.

    Args:
        target: The target.

    Raises:
        Error: If it is a string or nothing, as three.js throws in strict
            mode.
    """
    if target < 0:
        raise Error("USDA: a line writes into a string or into nothing")


def usda_tree(text: String) raises -> UsdaTree:
    """Read USDA text into a tree, three.js's `parseText`.

    Args:
        text: The text, before `preprocess_usda`.

    Returns:
        The tree.

    Raises:
        Error: If a line writes into a string or into nothing.
    """
    var tree = UsdaTree()
    var named: Optional[String] = None
    var target = 0
    var stack: List[Int] = [0]
    for raw in preprocess_usda(text).split("\n"):  # pragma: no branch
        var line = String(raw)
        if line.find("=") >= 0:
            var equals = find_assignment(line)
            if equals < 0:
                named = _trim(line)
                continue
            var lhs = _trim(String(line[byte=:equals]))
            var rhs = _trim(String(line[byte = equals + 1 :]))
            _write(target)
            if rhs.endswith("{"):
                var group = tree.add()
                stack.append(group)
                tree.set(target, lhs, "", group)
                target = group
            elif rhs.endswith("("):
                var value = _trim(String(rhs[byte = : rhs.byte_length() - 1]))
                tree.set(target, lhs, value, -1)
                var meta = tree.add()
                tree.set_meta(target, lhs, meta)
                stack.append(meta)
                target = meta
            else:
                tree.set(target, lhs, rhs, -1)
        elif line.find(":") >= 0:
            # A time sample, such as `1.5: (1, 2, 3)`. Any other line with
            # a `:` and no `=` is dropped.
            var colon = line.find(":")
            var key = _trim(String(line[byte=:colon]))
            if _is_frame(key):
                _write(target)
                tree.set(
                    target, key, _trim(String(line[byte = colon + 1 :])), -1
                )
        elif line.endswith("{"):
            var head = _trim(String(line[byte = : line.byte_length() - 1]))
            if head != "":
                named = head
            var key = named.or_else("null")
            _write(target)
            var at = tree.slot(target, key)
            var group: Int
            if at >= 0 and tree.groups[target].kids[at] >= 0:
                group = tree.groups[target].kids[at]
            elif at >= 0 and tree.groups[target].texts[at] != "":
                # `target[ string ] || {}` is the string, which the next
                # write throws on.
                group = _PRIMITIVE
            else:
                group = tree.add()
            stack.append(group)
            if group >= 0:
                tree.set(target, key, "", group)
            target = group
        elif line.endswith("}"):
            # `pop` of an empty stack gives `undefined` and changes nothing.
            if len(stack) > 0:
                _ = stack.pop()
            if len(stack) == 0:
                continue
            target = stack[len(stack) - 1]
        elif line.endswith("("):
            var meta = tree.add()
            stack.append(meta)
            var head = _trim(String(line[byte = : line.find("(")]))
            if head != "":
                named = head
            _write(target)
            tree.set(target, named.or_else("null"), "", meta)
            target = meta
        elif line.endswith(")"):
            if len(stack) > 0:
                _ = stack.pop()
            target = stack[len(stack) - 1] if len(stack) > 0 else _UNDEFINED
        elif _trim(line) != "":
            named = _trim(line)
    return tree^


def parse_string(text: String) -> String:
    """Return a quoted string's text, three.js's `_parseString`.

    The quotes at both ends are dropped, when they match. Then `\\n`,
    `\\t` and `\\r` become their characters, and a backslash before any
    other character becomes that character.

    Args:
        text: The text.

    Returns:
        The string.
    """
    var bytes = text.as_bytes()
    var n = len(bytes)
    var start = 0
    var end = n
    var quoted = n > 0 and (
        (bytes[0] == 0x22 and bytes[n - 1] == 0x22)
        or (bytes[0] == 0x27 and bytes[n - 1] == 0x27)
    )
    if quoted:
        start = 1
        end = max(n - 1, 1)
    var out = List[UInt8](capacity=n)
    var i = start
    while i < end:
        if bytes[i] == 0x5C and i + 1 < end:
            var next = bytes[i + 1]
            if next == 0x6E:
                out.append(0x0A)
            elif next == 0x74:
                out.append(0x09)
            elif next == 0x72:
                out.append(0x0D)
            else:
                out.append(next)
            i += 2
        else:
            out.append(bytes[i])
            i += 1
    return String(unsafe_from_utf8=out)


def _float_list(text: String) -> List[Float64]:
    """Return three.js's vector read: the text less parentheses, cut at
    each comma, each part read with `parseFloat`.

    Args:
        text: The value.

    Returns:
        The numbers, NaN where a part is not one.
    """
    var out = List[Float64]()
    for part in (
        text.replace("(", "").replace(")", "").split(",")
    ):  # pragma: no branch
        out.append(js_parse_float(_trim(String(part))))
    return out^


struct _Reader(Movable):
    """The counterpart of three.js's `USDAParser.parseData` as it reads one text.
    """

    var tree: UsdaTree
    var layer: UsdLayer

    def __init__(out self, var tree: UsdaTree):
        """Start reading a tree.

        Args:
            tree: The tree.
        """
        self.tree = tree^
        self.layer = UsdLayer()

    def raw(self, group: Int, slot: Int) -> String:
        """Return `String( data[ key ] )` of a key.

        Args:
            group: The group.
            slot: The key's place.

        Returns:
            Its text, or `[object Object]` for a group.
        """
        if self.tree.groups[group].kids[slot] >= 0:
            return _OBJECT_TEXT
        return self.tree.groups[group].texts[slot]

    def text_of(self, group: Int, slot: Int, what: String) raises -> String:
        """Return a key's text where three.js calls `replace` on it.

        Args:
            group: The group.
            slot: The key's place.
            what: The key, for the message.

        Returns:
            The text.

        Raises:
            Error: If the key holds a group, which has no `replace`.
        """
        if self.tree.groups[group].kids[slot] >= 0:
            raise Error("USDA: " + what + " is a group, not a value")
        return self.tree.groups[group].texts[slot]

    def json(mut self, doc: JsonDocument, node: Int) raises -> Int:
        """Keep a JSON value as a layer value.

        Args:
            doc: The document.
            node: The value.

        Returns:
            Its place in the layer.

        Raises:
            Error: If the document refuses a read.
        """
        var kind = doc.kind(node)
        if kind == NUMBER:
            return self.layer.add(usd_number(doc.number(node)))
        if kind == STRING:
            return self.layer.add(usd_string(doc.string(node)))
        if kind == BOOLEAN:
            return self.layer.add(usd_boolean(doc.boolean(node)))
        if kind == NULL:
            return self.layer.add(UsdValue(USD_NULL))
        if kind == ARRAY:
            var items = List[Int]()
            for k in range(doc.length(node)):
                items.append(doc.at(node, k))
            return self.json_array(doc, items)
        var keys = List[String]()
        for k in range(doc.length(node)):
            keys.append(doc.key(node, k))
        var out = UsdValue(USD_OBJECT)
        for key in js_key_order(keys):
            out.strings.append(key)
            out.items.append(self.json(doc, doc.get(node, key)))
        return self.layer.add(out^)

    def json_array(mut self, doc: JsonDocument, items: List[Int]) raises -> Int:
        """Keep a JSON array as a layer value: numbers or strings when
        every element is one, and each element's value otherwise.

        Args:
            doc: The document.
            items: The elements.

        Returns:
            Its place in the layer.

        Raises:
            Error: If the document refuses a read.
        """
        var numbers = 0
        var strings = 0
        for item in items:
            var kind = doc.kind(item)
            if kind == NUMBER:
                numbers += 1
            elif kind == STRING:
                strings += 1
        # An empty list reads as numbers, so the loops after this one run.
        if strings == 0 and numbers == len(items):
            var out = List[Float64]()
            for item in items:
                out.append(doc.number(item))
            return self.layer.add(usd_numbers(out^))
        if numbers == 0 and strings == len(items):
            var out = List[String]()
            for item in items:  # pragma: no branch
                out.append(doc.string(item))
            return self.layer.add(usd_strings(out^))
        var out = UsdValue(USD_ARRAY)
        for item in items:  # pragma: no branch
            out.items.append(self.json(doc, item))
        return self.layer.add(out^)

    def array(mut self, text: String) raises -> Int:
        """Read an array value, three.js's `[]` case of
        `_parseAttributeValue`, before a quaternion's reorder.

        Args:
            text: The trimmed value.

        Returns:
            Its place in the layer.

        Raises:
            Error: If the document refuses a read.
        """
        var cleaned = text.replace("(", "[").replace(")", "]")
        if cleaned.endswith(","):
            var head = String(cleaned[byte = : cleaned.byte_length() - 1])
            cleaned = head
        var parsed: JsonDocument
        try:
            parsed = parse_json(cleaned)
        except:
            return self.loose_array(text)
        var root = parsed.root()
        if doc_is_array(parsed, root):
            var first_is_array = parsed.length(root) > 0 and doc_is_array(
                parsed, parsed.at(root, 0)
            )
            if first_is_array:
                # `parsed.flat()`: each element that is an array is spread.
                var items = List[Int]()
                for k in range(parsed.length(root)):  # pragma: no branch
                    var item = parsed.at(root, k)
                    if doc_is_array(parsed, item):
                        for j in range(parsed.length(item)):
                            items.append(parsed.at(item, j))
                    else:
                        items.append(item)
                return self.json_array(parsed, items)
        return self.json(parsed, root)

    def loose_array(mut self, text: String) raises -> Int:
        """Read an array that is not JSON, three.js's fallback: the text
        less brackets, cut at each comma, a part that `parseFloat` reads
        a number, and any other part a string less its quotes.

        Args:
            text: The trimmed value.

        Returns:
            Its place in the layer.

        Raises:
            Error: If the layer refuses a value.
        """
        var parts = text.replace("[", "").replace("]", "").split(",")
        var numbers = List[Float64]()
        var strings = List[String]()
        var is_number = List[Bool]()
        for raw in parts:  # pragma: no branch
            var part = _trim(String(raw))
            var number = js_parse_float(part)
            is_number.append(number == number)
            if number == number:
                numbers.append(number)
            else:
                strings.append(part.replace('"', ""))
        if len(strings) == 0:
            return self.layer.add(usd_numbers(numbers^))
        if len(numbers) == 0:
            return self.layer.add(usd_strings(strings^))
        var out = UsdValue(USD_ARRAY)
        var n = 0
        var s = 0
        for k in range(len(is_number)):  # pragma: no branch
            if is_number[k]:
                out.items.append(self.layer.add(usd_number(numbers[n])))
                n += 1
            else:
                out.items.append(self.layer.add(usd_string(strings[s])))
                s += 1
        return self.layer.add(out^)

    def reorder_quaternions(mut self, id: Int) raises:
        """Turn each `(w, x, y, z)` of an array into `(x, y, z, w)`, as
        three.js does to a `quat` array.

        Args:
            id: The array's place.

        Raises:
            Error: If the value is a string, which three.js cannot write
                into, or an array whose length is not a multiple of four.
        """
        var kind = self.layer.kind(id)
        if kind == USD_STRING:
            raise Error("USDA: a quaternion array that is a string")
        var count = self.layer.length(id)
        if count < 0:
            return
        if count % 4 != 0:
            raise Error("USDA: a quaternion array not a multiple of four long")
        for i in range(0, count, 4):
            if kind == USD_NUMBERS:
                ref n = self.layer.values[id].numbers
                var w = n[i]
                n[i] = n[i + 1]
                n[i + 1] = n[i + 2]
                n[i + 2] = n[i + 3]
                n[i + 3] = w
            elif kind == USD_STRINGS:
                ref s = self.layer.values[id].strings
                var w = s[i]
                s[i] = s[i + 1]
                s[i + 1] = s[i + 2]
                s[i + 2] = s[i + 3]
                s[i + 3] = w
            else:
                ref t = self.layer.values[id].items
                var w = t[i]
                t[i] = t[i + 1]
                t[i + 1] = t[i + 2]
                t[i + 2] = t[i + 3]
                t[i + 3] = w

    def attribute_value(
        mut self, value_type: String, raw: String
    ) raises -> Int:
        """Read a value by its type, three.js's `_parseAttributeValue`.

        Args:
            value_type: The type, such as `float3` or `token[]`.
            raw: `String( value )`.

        Returns:
            Its place in the layer.

        Raises:
            Error: For a quaternion array three.js cannot reorder.
        """
        var text = _trim(raw)
        if value_type.endswith("[]"):
            var id = self.array(text)
            if value_type.startswith("quat"):
                self.reorder_quaternions(id)
            return id
        var vector = (
            value_type.find("3") >= 0
            or value_type.find("2") >= 0
            or value_type.find("4") >= 0
        )
        if vector or value_type.find("matrix") >= 0:
            return self.layer.add(usd_numbers(_float_list(text)))
        if value_type.startswith("quat"):
            var parts = _float_list(text)
            if len(parts) >= 4:
                return self.layer.add(
                    usd_numbers([parts[1], parts[2], parts[3], parts[0]])
                )
            # `values[ 1 ]` and on past the list are `undefined`.
            var out = UsdValue(USD_ARRAY)
            for k in [1, 2, 3, 0]:  # pragma: no branch
                if k < len(parts):
                    out.items.append(self.layer.add(usd_number(parts[k])))
                else:
                    out.items.append(self.layer.add(UsdValue(USD_UNDEFINED)))
            return self.layer.add(out^)
        if (
            value_type == "float"
            or value_type == "double"
            or value_type == "int"
        ):
            return self.layer.add(usd_number(js_parse_float(text)))
        if value_type == "asset":
            return self.layer.add(
                usd_string(text.replace("@", "").replace('"', ""))
            )
        return self.layer.add(usd_string(parse_string(text)))

    def header(mut self) raises -> UsdSpec:
        """Read the root's fields from the `#usda 1.0` metadata.

        Returns:
            The root's spec.

        Raises:
            Error: If `upAxis` or `defaultPrim` is a group.
        """
        var out = UsdSpec(SPEC_PRIM)
        var header = self.tree.kid(0, "#usda 1.0")
        if header < 0:
            return out^
        for name in ["upAxis", "defaultPrim"]:  # pragma: no branch
            var at = self.tree.slot(header, name)
            if at < 0:
                continue
            var is_group = self.tree.groups[header].kids[at] >= 0
            if not is_group and self.tree.groups[header].texts[at] == "":
                continue
            var text = self.text_of(header, at, name)
            out.set(name, self.layer.add(usd_string(text.replace('"', ""))))
        for name in [  # pragma: no branch
            "metersPerUnit",
            "framesPerSecond",
            "timeCodesPerSecond",
        ]:
            var at = self.tree.slot(header, name)
            if at >= 0:
                var number = js_parse_float(_trim(self.raw(header, at)))
                out.set(name, self.layer.add(usd_number(number)))
        return out^

    def walk(mut self, group: Int, parent: String) raises:
        """Add the prims of a group and all under them, three.js's
        `walkTree`.

        Args:
            group: The group.
            parent: The path of the prim it belongs to.

        Raises:
            Error: For anything `extract` refuses.
        """
        var children = List[String]()
        for slot in self.tree.order(group):
            var key = self.tree.groups[group].keys[slot]
            if key == "#usda 1.0" or key == "variants":
                continue
            var found = def_match(key)
            if not found:
                continue
            var name = found.value()[1]
            var path = "/" + name if parent == "/" else parent + "/" + name
            children.append(name)
            var fields = UsdSpec(SPEC_PRIM)
            fields.set("typeName", self.layer.add(usd_string(found.value()[0])))
            var kid = self.tree.groups[group].kids[slot]
            if kid >= 0:
                self.extract(kid, path, fields)
            _ = self.layer.put(path, fields^)
            if kid >= 0:
                self.walk(kid, path)
        # The parent's spec is put before its prims are walked.
        if len(children) > 0:
            var id = self.layer.add(usd_strings(children^))
            self.layer.specs[self.layer.spec(parent)].set("primChildren", id)

    def extract(mut self, group: Int, path: String, mut fields: UsdSpec) raises:
        """Read a prim's fields, attributes and relationships, three.js's
        `_extractPrimData`.

        Args:
            group: The prim's group.
            path: The prim's path.
            fields: The prim's fields.

        Raises:
            Error: For a group where three.js calls `replace`, and a
                quaternion array three.js cannot reorder.
        """
        for slot in self.tree.order(group):
            var key = self.tree.groups[group].keys[slot]
            var kid = self.tree.groups[group].kids[slot]
            if key.startswith("def "):
                continue
            if key == "prepend references":
                var reference = UsdValue(USD_ARRAY)
                reference.items.append(self.held(group, slot))
                fields.set("references", self.layer.add(reference^))
                continue
            if key == "payload":
                fields.set("payload", self.held(group, slot))
                continue
            if key == "variants":
                self.variants(kid, fields)
                continue
            if key.startswith("rel "):
                self.relationship(group, slot, path)
                continue
            if key.find("xformOpOrder") >= 0:
                var text = self.text_of(group, slot, key)
                var ops = List[String]()
                for part in (
                    text.replace("[", "").replace("]", "").split(",")
                ):  # pragma: no branch
                    ops.append(_trim(String(part)).replace('"', ""))
                fields.set("xformOpOrder", self.layer.add(usd_strings(ops^)))
                continue
            var found = attribute_match(key)
            if not found:
                continue
            var value_type = found.value()[0]
            var name = found.value()[1]
            if name.endswith(".connect"):
                self.connection(
                    path + "." + String(name[byte = : name.byte_length() - 8]),
                    value_type,
                    self.raw(group, slot),
                )
            elif name.endswith(".timeSamples") and kid >= 0:
                self.time_samples(
                    kid,
                    path + "." + String(name[byte = : name.byte_length() - 12]),
                    value_type,
                )
            else:
                var value = self.attribute_value(
                    value_type, self.raw(group, slot)
                )
                var type_id = self.layer.add(usd_string(value_type))
                var attribute = path + "." + name
                var at = self.layer.spec(attribute)
                if at >= 0:
                    self.layer.specs[at].set("default", value)
                    self.layer.specs[at].set("typeName", type_id)
                else:
                    var spec = UsdSpec(SPEC_ATTRIBUTE)
                    spec.set("default", value)
                    spec.set("typeName", type_id)
                    _ = self.layer.put(attribute, spec^)

    def held(mut self, group: Int, slot: Int) raises -> Int:
        """Keep a key's value as it is: its text, or an object for a
        group.

        Args:
            group: The group.
            slot: The key's place.

        Returns:
            Its place in the layer.

        Raises:
            Error: If the layer refuses a value.
        """
        if self.tree.groups[group].kids[slot] >= 0:
            return self.layer.add(UsdValue(USD_OBJECT))
        return self.layer.add(usd_string(self.tree.groups[group].texts[slot]))

    def variants(mut self, group: Int, mut fields: UsdSpec) raises:
        """Read a prim's `variants` selections.

        Args:
            group: The `variants` group, or -1 for a text.
            fields: The prim's fields.

        Raises:
            Error: If a selection is a group.
        """
        if group < 0:
            return
        var out = UsdValue(USD_OBJECT)
        for slot in self.tree.order(group):
            var key = self.tree.groups[group].keys[slot]
            var set_name = _variant_match(key)
            if not set_name:
                continue
            var chosen = self.text_of(group, slot, key).replace('"', "")
            var id = self.layer.add(usd_string(chosen))
            var at = -1
            for k in range(len(out.strings)):
                if out.strings[k] == set_name.value():
                    at = k
            if at >= 0:
                out.items[at] = id
            else:
                out.strings.append(set_name.value())
                out.items.append(id)
        if len(out.strings) > 0:
            fields.set("variantSelection", self.layer.add(out^))

    def relationship(mut self, group: Int, slot: Int, path: String) raises:
        """Read a `rel` key into a relationship spec.

        Args:
            group: The prim's group.
            slot: The key's place.
            path: The prim's path.

        Raises:
            Error: If the key holds a group.
        """
        var key = self.tree.groups[group].keys[slot]
        var target = (
            self.text_of(group, slot, key).replace("<", "").replace(">", "")
        )
        var spec = UsdSpec(SPEC_RELATIONSHIP)
        spec.set("targetPaths", self.layer.add(usd_strings([target])))
        var meta = self.tree.meta(group, key)
        if meta >= 0:
            var at = self.tree.slot(meta, "bindMaterialAs")
            if at >= 0:
                var text = parse_string(_trim(self.raw(meta, at)))
                spec.set("bindMaterialAs", self.layer.add(usd_string(text)))
        _ = self.layer.put(path + "." + String(key[byte=4:]), spec^)

    def connection(
        mut self, attribute: String, value_type: String, raw: String
    ) raises:
        """Read a `.connect` key into its attribute's `connectionPaths`.

        Args:
            attribute: The attribute's path.
            value_type: The value's type.
            raw: The key's text.

        Raises:
            Error: If the layer refuses a value.
        """
        var target = _trim(raw)
        if target.startswith("<"):
            var rest = String(target[byte=1:])
            target = rest
        if target.endswith(">"):
            var head = String(target[byte = : target.byte_length() - 1])
            target = head
        var at = self.layer.spec(attribute)
        if at < 0:
            var spec = UsdSpec(SPEC_ATTRIBUTE)
            spec.set("typeName", self.layer.add(usd_string(value_type)))
            at = self.layer.put(attribute, spec^)
        var id = self.layer.add(usd_strings([target]))
        self.layer.specs[at].set("connectionPaths", id)

    def time_samples(
        mut self, group: Int, attribute: String, value_type: String
    ) raises:
        """Read a `.timeSamples` group into its attribute's samples, sorted
        by time.

        Args:
            group: The samples' group.
            attribute: The attribute's path.
            value_type: The value's type.

        Raises:
            Error: For a quaternion array three.js cannot reorder.
        """
        var times = List[Float64]()
        var values = List[Int]()
        for slot in self.tree.order(group):
            var frame = js_parse_float(self.tree.groups[group].keys[slot])
            if frame != frame:
                continue
            var value = self.attribute_value(value_type, self.raw(group, slot))
            # A stable insertion, as JavaScript's sort is stable.
            var at = len(times)
            while at > 0 and times[at - 1] > frame:
                at -= 1
            times.insert(at, frame)
            values.insert(at, value)
        var samples = UsdValue(USD_SAMPLES)
        samples.numbers = times^
        samples.items = values^
        var spec = UsdSpec(SPEC_ATTRIBUTE)
        spec.set("timeSamples", self.layer.add(samples^))
        spec.set("typeName", self.layer.add(usd_string(value_type)))
        _ = self.layer.put(attribute, spec^)

    def infer_element_sizes(mut self) raises:
        """Set the `elementSize` of a mesh's joint indices and weights
        from the count of points, three.js's `_inferSkelElementSize`.

        Raises:
            Error: If the layer refuses a value.
        """
        # The layer holds the root at least.
        for k in range(len(self.layer.paths)):  # pragma: no branch
            if self.layer.specs[k].spec_type != SPEC_PRIM:
                continue
            # The root has no `typeName`; every other prim has a string.
            var type_name = self.layer.specs[k].field("typeName")
            var is_mesh = (
                self.layer.is_string(type_name)
                and self.layer.text(type_name) == "Mesh"
            )
            if not is_mesh:
                continue
            var path = self.layer.paths[k]
            var points = self.layer.field(path + ".points", "default")
            if not self.layer.truthy(points):
                continue
            var count = self.layer.length(points)
            var vertices = (
                Float64(count) / 3 if count >= 0 else nan[DType.float64]()
            )
            if vertices == 0:
                continue
            for name in [  # pragma: no branch
                ".primvars:skel:jointIndices",
                ".primvars:skel:jointWeights",
            ]:
                self.infer_element_size(path + name, vertices)

    def infer_element_size(mut self, path: String, vertices: Float64) raises:
        """Set one attribute's `elementSize`, three.js's
        `_inferElementSize`.

        Args:
            path: The attribute's path.
            vertices: The mesh's count of points, NaN when it has none.

        Raises:
            Error: If the layer refuses a value.
        """
        var at = self.layer.spec(path)
        if at < 0:
            return
        # three.js keeps an `elementSize` that is there, which USDA text
        # never writes.
        var value = self.layer.specs[at].field("default")
        if not self.layer.truthy(value):
            return
        var count = Float64(self.layer.length(value))
        if count > 0 and count % vertices == 0:
            var id = self.layer.add(usd_number(count / vertices))
            self.layer.specs[at].set("elementSize", id)


def doc_is_array(doc: JsonDocument, node: Int) raises -> Bool:
    """Return `Array.isArray` of a JSON value.

    Args:
        doc: The document.
        node: The value.

    Returns:
        Whether it is an array.

    Raises:
        Error: If the node is not in the document.
    """
    return doc.kind(node) == ARRAY


def parse_usda_layer(text: String) raises -> UsdLayer:
    """Read USDA text into a layer, three.js's `USDAParser.parseData`.

    The root, `/`, comes first, with `upAxis`, `defaultPrim`,
    `metersPerUnit`, `framesPerSecond` and `timeCodesPerSecond` from the
    header. Then each prim follows its attributes and relationships, and
    comes before the prims under it.

    Args:
        text: The text.

    Returns:
        The layer.

    Raises:
        Error: For anything the module docstring lists.
    """
    var reader = _Reader(usda_tree(text))
    var root = reader.header()
    _ = reader.layer.put("/", root^)
    reader.walk(0, "/")
    reader.infer_element_sizes()
    var layer = UsdLayer()
    swap(layer, reader.layer)
    return layer^
