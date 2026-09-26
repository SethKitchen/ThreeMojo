# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""USD scenes, from three.js `examples/jsm/loaders/USDLoader.js` and its
`usd/USDAParser.js`.

`parse_usda` reads USDA text, as three.js's `parse` reads a string.
`parse_usd` reads a file's bytes, as three.js's `parse` reads a buffer: a
USDC crate gives an empty node, as three.js's crate reader does, and any
other file is a USDZ archive. `read_usd` reads a file as three.js's
`load` does, so a `.usda` file is refused as a ZIP; `read_usda` reads
one as text.

**The text.** `usda_tree` is three.js's `parseText`. It reads a line at a
time into a tree of named values and groups. A line with `=` sets its
left side to its right side, or opens a group when the right side ends
with `{`. A line that ends with `{` opens a group named by the last line
that named nothing. A line that ends with `(` opens metadata, and `}` and
`)` close. Keys keep JavaScript's order.

**The scene.** Each `def Xform` is a node, named by its quoted word, under
the `def Xform` or `def Scope` it is in. It is a mesh when a `def Mesh`
is anywhere inside it, or in the layer its `prepend references` names:
three.js takes the first one it finds, so a parent wears its first
child's mesh too. The mesh's faces of three and four corners are cut
into triangles with no index. It has `points`, `normals` and `st`
texture coordinates when they are there, and flat normals when there are
none. Its material is a physical material from a `UsdPreviewSurface`,
with the maps three.js reads. `material:binding` names its material by
the second part of its path, as three.js reads it. A
`matrix4d xformOp:transform` places the node.

**Where three.js's quirks are kept.** A face's corners start at its
index times its count of corners, as three.js reads them, so faces of
mixed counts read the wrong corners. A corner past the list reads NaN. A
map whose image is not in the archive is still a map: this port makes it
one black texel, as a texture with no image draws, and names it in
`missing_textures`. A texture's `rotation` is read in radians.

**What is refused.** What three.js throws on: a value it reads as JSON
that is not JSON, a line that writes into a string or into nothing, a
reference with no `@`, a texture input whose path names no shader, and a
shader with no file. And where this port holds less than three.js: an
array value that is not an array; a color outside zero to one; a wrap
three.js does not know, which it leaves `undefined`; points that are not
three numbers each; a transform that is not sixteen finite numbers; and
text that is not UTF-8.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.js_number import js_parse_float, js_string_to_number
from loaders.js_text import js_trim, js_units, js_string
from loaders.json import (
    ARRAY,
    BOOLEAN,
    JsonDocument,
    NULL,
    NUMBER,
    STRING,
    parse_json,
)
from loaders.model_nodes import decompose_onto, texture_from_bytes
from loaders.three_mf import js_key_order
from loaders.zip import ZipEntry, unzip
from materials.material import Material, MaterialId, physical_material
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB, ColorSpace, linear_to_srgb
from render.texture import (
    CLAMP,
    COVERAGE,
    IGNORED,
    MIRROR,
    NEAREST,
    REPEAT,
    Texture,
    Wrap,
)
from render.texture_store import NO_TEXTURE, TextureId
from std.math import isfinite, isnan, nan
from std.pathlib import Path
from units.si import RADIAN, Angle

# What a stack entry or the target is when it is not a group: a string,
# which a strict-mode write throws on, or nothing.
comptime _PRIMITIVE = -2
comptime _UNDEFINED = -1


struct _Node(Copyable, Movable):
    """One group of the tree: its keys in the order first set, and each
    key's text or group."""

    var keys: List[String]
    var texts: List[String]
    # The group a key holds, or -1 when it holds text.
    var kids: List[Int]

    def __init__(out self):
        """Start with no keys."""
        self.keys = List[String]()
        self.texts = List[String]()
        self.kids = List[Int]()


struct UsdaTree(Copyable, Movable):
    """What three.js's `parseText` makes: groups of named texts and
    groups, the root at zero."""

    var nodes: List[_Node]

    def __init__(out self):
        """Start with the root group."""
        self.nodes = [_Node()]

    def add(mut self) -> Int:
        """Add an empty group.

        Returns:
            Its index.
        """
        self.nodes.append(_Node())
        return len(self.nodes) - 1

    def slot(self, node: Int, key: String) -> Int:
        """Return where a key is in a group.

        Args:
            node: The group.
            key: The key.

        Returns:
            Its place, or -1.
        """
        ref keys = self.nodes[node].keys
        for k in range(len(keys)):
            if keys[k] == key:
                return k
        return -1

    def has(self, node: Int, key: String) -> Bool:
        """Return JavaScript's `key in node`.

        Args:
            node: The group.
            key: The key.

        Returns:
            Whether the group has the key.
        """
        return self.slot(node, key) >= 0

    def set(mut self, node: Int, key: String, text: String, kid: Int):
        """Set a key, keeping its place when it is there, as JavaScript
        does.

        Args:
            node: The group.
            key: The key.
            text: The text, when `kid` is -1.
            kid: The group it holds, or -1 for text.
        """
        var at = self.slot(node, key)
        if at < 0:
            self.nodes[node].keys.append(key)
            self.nodes[node].texts.append(text)
            self.nodes[node].kids.append(kid)
        else:
            self.nodes[node].texts[at] = text
            self.nodes[node].kids[at] = kid

    def text(self, node: Int, key: String) -> Optional[String]:
        """Return a key's text.

        Args:
            node: The group.
            key: The key.

        Returns:
            The text, or none when the key is missing or holds a group.
        """
        var at = self.slot(node, key)
        if at < 0 or self.nodes[node].kids[at] >= 0:
            return None
        return self.nodes[node].texts[at]

    def kid(self, node: Int, key: String) -> Int:
        """Return the group a key holds.

        Args:
            node: The group.
            key: The key.

        Returns:
            The group, or -1 when the key is missing or holds text.
        """
        var at = self.slot(node, key)
        if at < 0:
            return -1
        return self.nodes[node].kids[at]

    def order(self, node: Int) -> List[Int]:
        """Return a group's places in JavaScript's key order.

        Args:
            node: The group.

        Returns:
            The places.
        """
        var out = List[Int]()
        for key in js_key_order(self.nodes[node].keys):
            out.append(self.slot(node, key))
        return out^


def _trimmed(text: String) -> String:
    """Return JavaScript's `text.trim()`.

    Args:
        text: The text.

    Returns:
        The text less white space at both ends.
    """
    var units = js_trim(js_units(text))
    return js_string(units, 0, len(units))


def _write(target: Int) raises:
    """Refuse a write into what is not a group.

    Args:
        target: The target.

    Raises:
        Error: If it is a string or nothing, as three.js throws in strict
            mode.
    """
    if target < 0:
        raise Error("USD: a line writes into a string or into nothing")


def usda_tree(text: String) raises -> UsdaTree:
    """Read USDA text into a tree, three.js's `parseText`.

    Args:
        text: The text.

    Returns:
        The tree.

    Raises:
        Error: If a line writes into a string or into nothing.
    """
    var tree = UsdaTree()
    var named: Optional[String] = None
    var target = 0
    var stack: List[Int] = [0]
    for raw in text.split("\n"):  # pragma: no branch
        var line = String(raw)
        var equals = line.find("=")
        if equals >= 0:
            # `line.split( '=' )[ 1 ]` ends at a second `=`.
            var after = String(line[byte = equals + 1 :])
            var next = after.find("=")
            var rest = String(after[byte=:next]) if next >= 0 else after
            var lhs = _trimmed(String(line[byte=:equals]))
            var rhs = _trimmed(rest)
            _write(target)
            if rhs.endswith("{"):
                var group = tree.add()
                stack.append(group)
                tree.set(target, lhs, "", group)
                target = group
            elif rhs.endswith("("):
                tree.set(
                    target, lhs, String(rhs[byte = : rhs.byte_length() - 1]), -1
                )
                var meta = tree.add()
                stack.append(meta)
                target = meta
            else:
                tree.set(target, lhs, rhs, -1)
        elif line.endswith("{"):
            var key = named.or_else("null")
            _write(target)
            var at = tree.slot(target, key)
            var group: Int
            if at >= 0 and tree.nodes[target].kids[at] >= 0:
                group = tree.nodes[target].kids[at]
            elif at >= 0 and tree.nodes[target].texts[at] != "":
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
            var head = _trimmed(String(line[byte = : line.find("(")]))
            if head != "":
                named = head
            _write(target)
            tree.set(target, named.or_else("null"), "", meta)
            target = meta
        elif line.endswith(")"):
            if len(stack) > 0:
                _ = stack.pop()
            target = stack[len(stack) - 1] if len(stack) > 0 else _UNDEFINED
        else:
            named = _trimmed(line)
    return tree^


@fieldwise_init
struct UsdObject(Copyable, Movable):
    """A node `parse_usda` added: a mesh, or a node with nothing to draw,
    as three.js adds a `Mesh` or an `Object3D`."""

    var node: NodeId
    var is_mesh: Bool
    # The mesh's geometry and material; unset for a node.
    var geometry: GeometryId
    var material: MaterialId


struct UsdModel(Movable):
    """What `parse_usda` added: the root, three.js's `Group`, and each
    object under it, in the order added."""

    var root: NodeId
    var objects: List[UsdObject]
    # Each texture a material read, in the order read.
    var textures: List[TextureId]
    # The file of each map whose image is not in the archive.
    var missing_textures: List[String]

    def __init__(out self, root: NodeId):
        """Start with a root and nothing under it.

        Args:
            root: The root node.
        """
        self.root = root
        self.objects = List[UsdObject]()
        self.textures = List[TextureId]()
        self.missing_textures = List[String]()


struct _Layer(Copyable, Movable):
    """One file of a USDZ archive as three.js's `parseAssets` holds it."""

    var name: String
    # 0 for a PNG, 1 for a text layer, 2 for a crate.
    var kind: Int
    var bytes: List[UInt8]
    var tree: UsdaTree

    def __init__(
        out self,
        name: String,
        kind: Int,
        var bytes: List[UInt8],
        var tree: UsdaTree,
    ):
        """Hold a file.

        Args:
            name: Its name in the archive.
            kind: 0 for a PNG, 1 for a text layer, 2 for a crate.
            bytes: Its bytes.
            tree: Its tree, for a text layer.
        """
        self.name = name
        self.kind = kind
        self.bytes = bytes^
        self.tree = tree^


def _numbers(doc: JsonDocument, what: String) raises -> List[Float64]:
    """Return a JSON array's elements as a `Float32Array` converts them.

    Args:
        doc: The parsed value.
        what: The value's name, for the message.

    Returns:
        Each element as JavaScript's `Number` reads it.

    Raises:
        Error: If the value is not an array.
    """
    var root = doc.root()
    if doc.kind(root) != ARRAY:
        raise Error("USD: " + what + " is not an array")
    var out = List[Float64]()
    for k in range(doc.length(root)):
        out.append(_to_number(doc, doc.at(root, k)))
    return out^


def _to_number(doc: JsonDocument, node: Int) raises -> Float64:
    """Return JavaScript's `Number( value )` of a JSON value.

    Args:
        doc: The document.
        node: The value.

    Returns:
        The number: a string read as `Number` reads it, `null` and false
        zero, true one, an array of one number that number, and NaN for
        any other array or object.
    """
    var kind = doc.kind(node)
    if kind == NUMBER:
        return doc.number(node)
    if kind == STRING:
        return js_string_to_number(doc.string(node))
    if kind == BOOLEAN:
        return 1 if doc.boolean(node) else 0
    if kind == NULL:
        return 0
    if kind == ARRAY and doc.length(node) == 0:
        return 0
    if kind == ARRAY and doc.length(node) == 1:
        return _to_number(doc, doc.at(node, 0))
    return nan[DType.float64]()


def _no_parentheses(text: String) -> String:
    """Return `text.replace( /[()]*/g, '' )`.

    Args:
        text: The text.

    Returns:
        The text with no parentheses.
    """
    return text.replace("(", "").replace(")", "")


def _corner(raw: List[Float64], at: Int) -> Float64:
    """Return a corner, NaN past the list, as `undefined` reads.

    Args:
        raw: The corners.
        at: Which.

    Returns:
        The corner.
    """
    return raw[at] if at < len(raw) else nan[DType.float64]()


def _triangles(raw: List[Float64], counts: List[Float64]) -> List[Float64]:
    """Return three.js's `toTriangleIndices`: faces of three and four
    corners as triangles, each face's corners from its index times its
    count.

    Args:
        raw: The corners.
        counts: Each face's count of corners.

    Returns:
        The triangles' corners, NaN past the list.
    """
    var out = List[Float64]()
    for i in range(len(counts)):
        var count = counts[i]
        if count != 3 and count != 4:
            continue
        var stride = i * Int(count)
        out.append(_corner(raw, stride))
        out.append(_corner(raw, stride + 1))
        out.append(_corner(raw, stride + 2))
        if count == 4:
            out.append(_corner(raw, stride))
            out.append(_corner(raw, stride + 2))
            out.append(_corner(raw, stride + 3))
    return out^


def _flat(
    values: List[Float64], size: Int, indices: List[Float64]
) -> List[Float64]:
    """Return three.js's `toFlatBufferAttribute`: each index's item, as a
    `Float32Array`.

    Args:
        values: The items end to end.
        size: Numbers an item.
        indices: Which item each vertex takes. One that names no item
            reads NaN.

    Returns:
        The items, end to end.
    """
    var out = List[Float64](capacity=len(indices) * size)
    for index in indices:
        for j in range(size):  # pragma: no branch
            var at = index * Float64(size) + Float64(j)
            # NaN compares false, so an `undefined` index reads NaN.
            var inside = at >= 0 and at < Float64(len(values))
            if inside and at == Float64(Int(at)):
                out.append(Float64(Float32(values[Int(at)])))
            else:
                out.append(nan[DType.float64]())
    return out^


# What a `_Value` is.
comptime _MISSING = 0
comptime _TEXT = 1
comptime _GROUP = 2
# An object that is not a group of the text: a crate layer's `Group`,
# which holds no `def` keys.
comptime _OPAQUE = 3


@fieldwise_init
struct _Value(Copyable, Movable):
    """A JavaScript value the loader reads: missing, a string, a group of
    one of the trees, or another object."""

    var kind: Int
    var text: String
    # Which tree, and which group of it, for a group.
    var tree: Int
    var node: Int

    def truthy(self) -> Bool:
        """Return JavaScript's truthiness: an empty string and `undefined`
        are false.

        Returns:
            Whether the value is truthy.
        """
        if self.kind == _MISSING:
            return False
        if self.kind == _TEXT:
            return self.text != ""
        return True


def _missing() -> _Value:
    """Return `undefined`.

    Returns:
        The value.
    """
    return _Value(_MISSING, "", -1, -1)


def _strip_path(reference: String) -> String:
    """Return a reference less `</` at its start and `>` at its end, as
    three.js's two `replace` calls cut it.

    Args:
        reference: The reference.

    Returns:
        The path.
    """
    var start = 2 if reference.startswith("</") else 0
    var end = reference.byte_length()
    if end > start and reference.endswith(">"):
        end -= 1
    return String(reference[byte=start:end])


def _is_word(byte: UInt8) -> Bool:
    """Return True for a character `\\w` matches.

    Args:
        byte: The byte.

    Returns:
        Whether it is a letter, a digit or `_`.
    """
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def _word_before_output(text: String, any_separator: Bool) -> Optional[String]:
    """Return the word three.js's `/(\\w+)\\.output/` or `/(\\w+).output/`
    captures.

    Args:
        text: The text.
        any_separator: True for `.` as any character, False for a literal
            point.

    Returns:
        The captured word, or none when the pattern does not match.
    """
    var b = text.as_bytes()
    var n = len(b)
    var start = 0
    while start < n:
        # Each word is tried from its first character: a word that fails
        # from there fails from any later one.
        if not _is_word(b[start]):
            start += 1
            continue
        var run = start
        while run < n and _is_word(b[run]):
            run += 1
        # Greedy: the longest word first, then shorter ones.
        var end = run
        while end > start:
            var separator = end < n and (
                b[end]
                == 46 if not any_separator else (b[end] != 10 and b[end] != 13)
            )
            var tail = String(text[byte = min(end + 1, n) : min(end + 7, n)])
            if separator and tail == "output":
                return String(text[byte=start:end])
            end -= 1
        start = run
    return None


def _xform_name(key: String) -> String:
    """Return the word three.js's `/def Xform "(\\w+)"/` captures, or an
    empty name.

    Args:
        key: The key.

    Returns:
        The name.
    """
    var b = key.as_bytes()
    var at = key.find('def Xform "')
    while at >= 0:
        var start = at + 11
        var end = start
        while end < len(b) and _is_word(b[end]):
            end += 1
        if end > start and end < len(b) and b[end] == 34:
            return String(key[byte=start:end])
        var next = String(key[byte = at + 1 :]).find('def Xform "')
        at = at + 1 + next if next >= 0 else -1
    return ""


def _linear_color(text: String, what: String) raises -> Color:
    """Return a `color3f` as three.js's `color.fromArray` reads it: linear
    numbers, here encoded to sRGB bytes.

    Args:
        text: The value, `(r, g, b)`.
        what: The input, for the message.

    Returns:
        The color as authored.

    Raises:
        Error: If it is not JSON, or a channel is not a number from zero
            to one, which a `Color` here cannot hold.
    """
    var numbers = _numbers(parse_json("[" + _no_parentheses(text) + "]"), what)
    var channels = List[UInt8]()
    for k in range(3):  # pragma: no branch
        var value = numbers[k] if k < len(numbers) else nan[DType.float64]()
        if not (value >= 0 and value <= 1):
            raise Error(
                "USD: " + what + " must be three numbers from zero to one"
            )
        var encoded = linear_to_srgb(Float32(value))
        channels.append(UInt8(Int(encoded * 255 + 0.5)))
    return Color(channels[0], channels[1], channels[2])


def _wrap(token: _Value) raises -> Wrap:
    """Return the wrap a `token inputs:wrapS` or `wrapT` names.

    Args:
        token: The value.

    Raises:
        Error: If it names none of `"clamp"`, `"mirror"` and `"repeat"`,
            which three.js leaves `undefined`.

    Returns:
        The wrap.
    """
    if token.kind == _TEXT and token.text == '"clamp"':
        return CLAMP
    if token.kind == _TEXT and token.text == '"mirror"':
        return MIRROR
    if token.kind == _TEXT and token.text == '"repeat"':
        return REPEAT
    raise Error("USD: a texture wrap three.js does not know")


struct _Builder(Movable):
    """Builds three.js's group from the trees."""

    # The stage's tree first, then each text layer's.
    var trees: List[UsdaTree]
    var layers: List[_Layer]
    var model: UsdModel

    def __init__(
        out self, var stage: UsdaTree, var layers: List[_Layer], root: NodeId
    ):
        """Hold the stage, the archive's layers and the root.

        Args:
            stage: The stage's tree.
            layers: The archive's layers.
            root: The root node.
        """
        self.trees = [stage^]
        for layer in layers:
            self.trees.append(layer.tree.copy())
        self.layers = layers^
        self.model = UsdModel(root)

    def result(deinit self) -> UsdModel:
        """Give up the model.

        Returns:
            What was added.
        """
        return self.model^

    def value(self, tree: Int, node: Int, slot: Int) -> _Value:
        """Return the value at a place of a group.

        Args:
            tree: The tree.
            node: The group.
            slot: The place.

        Returns:
            The value.
        """
        ref group = self.trees[tree].nodes[node]
        if group.kids[slot] >= 0:
            return _Value(_GROUP, "", tree, group.kids[slot])
        return _Value(_TEXT, group.texts[slot], tree, -1)

    def get(self, of: _Value, key: String) -> _Value:
        """Return `of[ key ]` of a group.

        Args:
            of: The group.
            key: The key.

        Returns:
            The value, or `undefined`.
        """
        var slot = self.trees[of.tree].slot(of.node, key)
        if slot < 0:
            return _missing()
        return self.value(of.tree, of.node, slot)

    def has(self, of: _Value, key: String) raises -> Bool:
        """Return JavaScript's `key in of`.

        Args:
            of: The value.
            key: The key.

        Returns:
            Whether a group has the key.

        Raises:
            Error: If the value is not an object, as `in` throws.
        """
        if of.kind == _GROUP:
            return self.trees[of.tree].has(of.node, key)
        if of.kind == _OPAQUE:
            return False
        raise Error("USD: `in` reads a key of what is not an object")

    def text(self, of: _Value, key: String, what: String) raises -> String:
        """Return a group's text, as three.js's string calls read it.

        Args:
            of: The group.
            key: The key, which is there.
            what: The value, for the message.

        Returns:
            The text.

        Raises:
            Error: If the key holds a group, which has no string methods.
        """
        var got = self.get(of, key)
        if got.kind != _TEXT:
            raise Error("USD: " + what + " is a group, not a string")
        return got.text

    def asset(self, path: String) -> _Value:
        """Return `assets[ path ]`: a PNG's URL, a layer's tree, or a
        crate's group.

        Args:
            path: The file's name in the archive.

        Returns:
            The value, or `undefined`.
        """
        var found = _missing()
        for k in range(len(self.layers)):
            if self.layers[k].name == path:
                var kind = self.layers[k].kind
                if kind == 0:
                    found = _Value(_TEXT, "blob:" + path, -1, -1)
                elif kind == 1:
                    found = _Value(_GROUP, "", k + 1, 0)
                else:
                    found = _Value(_OPAQUE, "", -1, -1)
        return found^

    def find_geometry(
        self, data: _Value, id: Optional[String]
    ) raises -> _Value:
        """Return three.js's `findGeometry`: the named mesh, or the first
        `def Mesh` inside.

        Args:
            data: Where to look.
            id: The mesh's name, or none.

        Returns:
            The mesh's value, or `undefined`.

        Raises:
            Error: If a name is looked for in a string.
        """
        if not data.truthy():
            return _missing()
        if Bool(id):
            var name = 'def Mesh "' + id.value() + '"'
            if self.has(data, name):
                return self.get(data, name)
        if data.kind != _GROUP:
            # A string's keys are its indices; an opaque object has no
            # `def` keys.
            return _missing()
        for slot in self.trees[data.tree].order(data.node):
            var key = self.trees[data.tree].nodes[data.node].keys[slot]
            var object = self.value(data.tree, data.node, slot)
            if key.startswith("def Mesh"):
                return object^
            if object.kind == _GROUP:
                var found = self.find_geometry(object, None)
                if found.truthy():
                    return found^
        return _missing()

    def find_mesh_geometry(self, data: _Value) raises -> _Value:
        """Return three.js's `findMeshGeometry`: the referenced layer's
        mesh, or the first inside.

        Args:
            data: The `def Xform`'s value.

        Returns:
            The mesh's value, or `undefined`.

        Raises:
            Error: If the reference is not a string with a path and a
                name between `@`s.
        """
        if not data.truthy():
            return _missing()
        if self.has(data, "prepend references"):
            var reference = self.text(data, "prepend references", "a reference")
            var parts = reference.split("@")
            if len(parts) < 3:
                raise Error("USD: a reference with no @path@ and name")
            var whole = String(parts[1])
            # `replace( /^.\//, '' )`: any first character, then `/`.
            var cut = whole.byte_length() >= 2 and whole.as_bytes()[1] == 47
            var path = String(whole[byte=2:]) if cut else whole
            var id = _strip_path(String(parts[2]))
            return self.find_geometry(self.asset(path), id)
        return self.find_geometry(data, None)

    def json_numbers(
        self, data: _Value, key: String, parentheses: Bool
    ) raises -> List[Float64]:
        """Return a value three.js reads with `JSON.parse`.

        Args:
            data: The mesh.
            key: The key, which is there.
            parentheses: Whether to drop `(` and `)` first.

        Returns:
            The numbers.

        Raises:
            Error: If the value is a group or not a JSON array.
        """
        var text = self.text(data, key, key)
        if parentheses:
            text = _no_parentheses(text)
        return _numbers(parse_json(text), key)

    def build_geometry(
        mut self, data: _Value
    ) raises -> Optional[BufferGeometry]:
        """Return three.js's `buildGeometry`.

        Args:
            data: The mesh's value.

        Returns:
            The geometry, with no index, or none for no mesh.

        Raises:
            Error: For a value three.js cannot read, and points that are
                not three numbers each.
        """
        if not data.truthy():
            return None
        var geometry = BufferGeometry()
        var indices: Optional[List[Float64]] = None
        var counts: Optional[List[Float64]] = None
        var uvs: Optional[List[Float64]] = None
        var positions_length = -1
        if self.has(data, "int[] faceVertexIndices"):
            indices = self.json_numbers(data, "int[] faceVertexIndices", False)
        if self.has(data, "int[] faceVertexCounts"):
            counts = self.json_numbers(data, "int[] faceVertexCounts", False)
            if not Bool(indices):
                # three.js reads `null[ stride ]` for the first face of
                # three or four corners.
                for count in counts.value():
                    if count == 3 or count == 4:
                        raise Error(
                            "USD: faceVertexCounts with no faceVertexIndices"
                        )
                indices = List[Float64]()
            else:
                indices = _triangles(indices.value(), counts.value())
        if self.has(data, "point3f[] points"):
            var positions = self.json_numbers(data, "point3f[] points", True)
            positions_length = len(positions)
            var values = positions^
            if Bool(indices):
                values = _flat(values, 3, indices.value())
            geometry.set_attribute(String(POSITION), _attribute(values, 3))
        if self.has(data, "float2[] primvars:st"):
            var st = self.get(data, "float2[] primvars:st")
            self.trees_set(data, "texCoord2f[] primvars:st", st)
        if self.has(data, "texCoord2f[] primvars:st"):
            uvs = self.json_numbers(data, "texCoord2f[] primvars:st", True)
            var values = uvs.value().copy()
            if Bool(indices):
                values = _flat(values, 2, indices.value())
            geometry.set_attribute(String(UV), _attribute(values, 2))
        if self.has(data, "int[] primvars:st:indices") and Bool(uvs):
            var own = self.json_numbers(
                data, "int[] primvars:st:indices", False
            )
            if not Bool(counts):
                raise Error("USD: st indices with no faceVertexCounts")
            var corners = _triangles(own, counts.value())
            geometry.set_attribute(
                String(UV), _attribute(_flat(uvs.value(), 2, corners), 2)
            )
        if self.has(data, "normal3f[] normals"):
            var normals = self.json_numbers(data, "normal3f[] normals", True)
            var values: List[Float64]
            if len(normals) == positions_length:
                values = normals.copy()
                if Bool(indices):
                    values = _flat(values, 3, indices.value())
            else:
                # Normals of their own, a corner each.
                if len(normals) % 3 != 0:
                    raise Error("USD: normals that are not three numbers each")
                if not Bool(counts):
                    raise Error("USD: normals with no faceVertexCounts")
                var own = List[Float64]()
                for k in range(len(normals) // 3):
                    own.append(Float64(k))
                values = _flat(normals, 3, _triangles(own, counts.value()))
            geometry.set_attribute(String(NORMAL), _attribute(values, 3))
        elif geometry.has_attribute(String(POSITION)):
            geometry.compute_vertex_normals()
        return geometry^

    def trees_set(mut self, data: _Value, key: String, value: _Value):
        """Set a key of a group to a value, as three.js copies `st`.

        Args:
            data: The group.
            key: The key.
            value: The value.
        """
        if value.kind == _GROUP:
            self.trees[data.tree].set(data.node, key, "", value.node)
        else:
            self.trees[data.tree].set(data.node, key, value.text, -1)

    def find_material(self, data: _Value, id: String) -> _Value:
        """Return three.js's `findMaterial`: the first key that starts
        with `def Material` and the id.

        Args:
            data: Where to look.
            id: What follows `def Material`, or empty.

        Returns:
            The material's value, or `undefined`.
        """
        # `data` is a group: the stage's root, a `def Xform`'s group, or
        # a group inside one.
        for slot in self.trees[data.tree].order(data.node):
            var key = self.trees[data.tree].nodes[data.node].keys[slot]
            var object = self.value(data.tree, data.node, slot)
            if key.startswith("def Material" + id):
                return object^
            if object.kind == _GROUP:
                var found = self.find_material(object, id)
                if found.truthy():
                    return found^
        return _missing()

    def find_texture(self, id: String) -> _Value:
        """Return three.js's `findTexture` from the stage's root.

        Args:
            id: The shader's name.

        Returns:
            The shader's value, or `undefined`.
        """
        return self.find_shader(_Value(_GROUP, "", 0, 0), id)

    def find_shader(self, data: _Value, id: String) -> _Value:
        """Return the first key that starts with `def Shader "id"`.

        Args:
            data: Where to look.
            id: The shader's name.

        Returns:
            The shader's value, or `undefined`.
        """
        for slot in self.trees[data.tree].order(data.node):
            var key = self.trees[data.tree].nodes[data.node].keys[slot]
            var object = self.value(data.tree, data.node, slot)
            if key.startswith('def Shader "' + id + '"'):
                return object^
            if object.kind == _GROUP:
                var found = self.find_shader(object, id)
                if found.truthy():
                    return found^
        return _missing()

    def build_texture(
        mut self,
        connection: String,
        material: _Value,
        transform: String,
        space: ColorSpace,
        mut assets: Assets,
    ) raises -> TextureId:
        """Return three.js's `buildTexture` of the shader a connection
        names, with the material's `Transform2d` shader's placement.

        Args:
            connection: The input's `.connect` path.
            material: The material's value.
            transform: The `Transform2d` shader's name.
            space: `SRGB` for a color map, `LINEAR` for a data map.
            assets: Where the texture goes.

        Returns:
            The texture.

        Raises:
            Error: If the path names no shader, the shader has no file, or
                a wrap or a placement cannot be read.
        """
        var name = _word_before_output(connection, True)
        if not Bool(name):
            raise Error("USD: a texture input names no shader: " + connection)
        var sampler = self.find_texture(name.value())
        if not self.has(sampler, "asset inputs:file"):
            raise Error(
                "USD: the texture shader " + name.value() + " has no file"
            )
        var path = _trimmed(
            self.text(sampler, "asset inputs:file", "a file").replace("@", "")
        )
        var alpha = COVERAGE if space == SRGB else IGNORED
        var texture: Texture
        # `assets[ path ]` is an image only for a PNG of the archive.
        var png = -1
        for k in range(len(self.layers)):
            if self.layers[k].name == path and self.layers[k].kind == 0:
                png = k
        if png >= 0:
            texture = texture_from_bytes(
                self.layers[png].bytes, space, CLAMP, alpha
            )
        else:
            # three.js keeps a texture whose image never loads, which
            # draws black.
            texture = Texture(
                1, 1, [0, 0, 0, 255], CLAMP, NEAREST, space, False, alpha
            )
            self.model.missing_textures.append(path)
        texture.wrap_s = CLAMP
        texture.wrap_t = CLAMP
        if self.has(sampler, "token inputs:wrapS"):
            texture.wrap_s = _wrap(self.get(sampler, "token inputs:wrapS"))
        if self.has(sampler, "token inputs:wrapT"):
            texture.wrap_t = _wrap(self.get(sampler, "token inputs:wrapT"))
        var place = self.get(material, 'def Shader "' + transform + '"')
        if place.kind == _GROUP:
            var rotation = self.get(place, "float inputs:rotation")
            if rotation.truthy():
                texture.rotation = Angle(
                    Float32(
                        js_parse_float(
                            self.text(
                                place, "float inputs:rotation", "a rotation"
                            )
                        )
                    ),
                    RADIAN,
                )
            var scale = self.get(place, "float2 inputs:scale")
            if scale.truthy():
                texture.repeat = self.pair(place, "float2 inputs:scale")
            var translation = self.get(place, "float2 inputs:translation")
            if translation.truthy():
                texture.offset = self.pair(place, "float2 inputs:translation")
        var id = assets.textures.add(texture^)
        self.model.textures.append(id)
        return id

    def pair(self, of: _Value, key: String) raises -> Vector2:
        """Return a `float2` as `Vector2.fromArray` reads it.

        Args:
            of: The shader.
            key: The input.

        Returns:
            The pair, NaN where a number is missing.

        Raises:
            Error: If it is not JSON.
        """
        var numbers = _numbers(
            parse_json("[" + _no_parentheses(self.text(of, key, key)) + "]"),
            key,
        )
        var x = numbers[0] if len(numbers) > 0 else nan[DType.float64]()
        var y = numbers[1] if len(numbers) > 1 else nan[DType.float64]()
        return Vector2(Float32(x), Float32(y))

    def build_material(
        mut self, data: _Value, mut assets: Assets
    ) raises -> Material:
        """Return three.js's `buildMaterial`: a physical material from a
        `UsdPreviewSurface`.

        Args:
            data: The material's value, or `undefined`.
            assets: Where the textures go.

        Returns:
            The material.

        Raises:
            Error: For an input three.js cannot read, and a color outside
                zero to one.
        """
        var material = physical_material(Color(255, 255, 255))
        if data.kind != _GROUP:
            return material^
        var connection = self.get(data, "token outputs:surface.connect")
        if not connection.truthy() or connection.kind != _TEXT:
            return material^
        var surface_name = _word_before_output(connection.text, False)
        if not Bool(surface_name):
            return material^
        var surface = self.get(
            data, 'def Shader "' + surface_name.value() + '"'
        )
        if surface.kind == _MISSING:
            return material^
        if self.has(surface, "color3f inputs:diffuseColor.connect"):
            material.map = self.build_texture(
                self.text(
                    surface, "color3f inputs:diffuseColor.connect", "a path"
                ),
                data,
                "Transform2d_diffuse",
                SRGB,
                assets,
            )
        elif self.has(surface, "color3f inputs:diffuseColor"):
            material.color = _linear_color(
                self.text(
                    surface, "color3f inputs:diffuseColor", "diffuseColor"
                ),
                "diffuseColor",
            )
        if self.has(surface, "color3f inputs:emissiveColor.connect"):
            material.emissive_map = self.build_texture(
                self.text(
                    surface, "color3f inputs:emissiveColor.connect", "a path"
                ),
                data,
                "Transform2d_emissive",
                SRGB,
                assets,
            )
            material.emissive = Color(255, 255, 255)
        elif self.has(surface, "color3f inputs:emissiveColor"):
            material.emissive = _linear_color(
                self.text(
                    surface, "color3f inputs:emissiveColor", "emissiveColor"
                ),
                "emissiveColor",
            )
        if self.has(surface, "normal3f inputs:normal.connect"):
            material.normal_map = self.build_texture(
                self.text(surface, "normal3f inputs:normal.connect", "a path"),
                data,
                "Transform2d_normal",
                LINEAR,
                assets,
            )
        if self.has(surface, "float inputs:roughness.connect"):
            material.roughness = 1
            material.roughness_map = self.build_texture(
                self.text(surface, "float inputs:roughness.connect", "a path"),
                data,
                "Transform2d_roughness",
                LINEAR,
                assets,
            )
        elif self.has(surface, "float inputs:roughness"):
            material.roughness = self.float(surface, "float inputs:roughness")
        if self.has(surface, "float inputs:metallic.connect"):
            material.metalness = 1
            material.metalness_map = self.build_texture(
                self.text(surface, "float inputs:metallic.connect", "a path"),
                data,
                "Transform2d_metallic",
                LINEAR,
                assets,
            )
        elif self.has(surface, "float inputs:metallic"):
            material.metalness = self.float(surface, "float inputs:metallic")
        if self.has(surface, "float inputs:clearcoat.connect"):
            material.clearcoat = 1
            material.clearcoat_map = self.build_texture(
                self.text(surface, "float inputs:clearcoat.connect", "a path"),
                data,
                "Transform2d_clearcoat",
                LINEAR,
                assets,
            )
        elif self.has(surface, "float inputs:clearcoat"):
            material.clearcoat = self.float(surface, "float inputs:clearcoat")
        if self.has(surface, "float inputs:clearcoatRoughness.connect"):
            material.clearcoat_roughness = 1
            material.clearcoat_roughness_map = self.build_texture(
                self.text(
                    surface, "float inputs:clearcoatRoughness.connect", "a path"
                ),
                data,
                "Transform2d_clearcoatRoughness",
                LINEAR,
                assets,
            )
        elif self.has(surface, "float inputs:clearcoatRoughness"):
            material.clearcoat_roughness = self.float(
                surface, "float inputs:clearcoatRoughness"
            )
        if self.has(surface, "float inputs:ior"):
            material.ior = self.float(surface, "float inputs:ior")
        if self.has(surface, "float inputs:occlusion.connect"):
            material.ao_map = self.build_texture(
                self.text(surface, "float inputs:occlusion.connect", "a path"),
                data,
                "Transform2d_occlusion",
                LINEAR,
                assets,
            )
        return material^

    def float(self, of: _Value, key: String) raises -> Float32:
        """Return a `float` input, read with `parseFloat`.

        Args:
            of: The shader.
            key: The input.

        Returns:
            The number.

        Raises:
            Error: If it is a group.
        """
        return Float32(js_parse_float(self.text(of, key, key)))

    def find_mesh_material(self, data: _Value) raises -> _Value:
        """Return three.js's `findMeshMaterial`: the bound material, found
        by the second part of its path, or the first one inside.

        Args:
            data: The `def Xform`'s value.

        Returns:
            The material's value, or `undefined`.

        Raises:
            Error: If the binding is a group.
        """
        if not data.truthy():
            return _missing()
        if self.has(data, "rel material:binding"):
            var id = _strip_path(
                self.text(data, "rel material:binding", "a material binding")
            )
            var parts = id.split("/")
            var second = String(parts[1]) if len(parts) > 1 else "undefined"
            return self.find_material(
                _Value(_GROUP, "", 0, 0), ' "' + second + '"'
            )
        return self.find_material(data, "")

    def build_object(
        mut self,
        data: _Value,
        name: String,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises -> NodeId:
        """Add three.js's `buildObject`: a mesh or a node, placed by its
        transform.

        Args:
            data: The `def Xform`'s value.
            name: Its name.
            parent: The node it goes under.
            scene: The scene.
            assets: Where the geometry, the material and the textures go.

        Returns:
            The node.

        Raises:
            Error: For a mesh, a material or a transform that cannot be
                read.
        """
        var geometry = self.build_geometry(self.find_mesh_geometry(data))
        var material = self.build_material(
            self.find_mesh_material(data), assets
        )
        var node = Object3D()
        node.name = name
        if self.has(data, "matrix4d xformOp:transform"):
            var numbers = _numbers(
                parse_json(
                    "["
                    + _no_parentheses(
                        self.text(
                            data, "matrix4d xformOp:transform", "a transform"
                        )
                    )
                    + "]"
                ),
                "a transform",
            )
            if len(numbers) < 16:
                raise Error("USD: a transform of fewer than sixteen numbers")
            var matrix = Matrix4()
            for k in range(16):  # pragma: no branch
                matrix.elements[k] = Float32(numbers[k])
            decompose_onto(node, matrix, "USD")
        var at = scene.attach(node, parent)
        if Bool(geometry):
            var geometry_id = assets.geometries.add(geometry.value().clone())
            var material_id = assets.materials.add(material^)
            scene.add_mesh(Mesh(geometry_id, material_id, at))
            self.model.objects.append(
                UsdObject(at, True, geometry_id, material_id)
            )
        else:
            self.model.objects.append(
                UsdObject(at, False, GeometryId(0), MaterialId(0))
            )
        return at

    def build_hierarchy(
        mut self,
        data: _Value,
        parent: NodeId,
        mut scene: Scene,
        mut assets: Assets,
    ) raises:
        """Add three.js's `buildHierarchy`: each `def Xform` under a group
        and each `def Scope` it holds.

        Args:
            data: The group.
            parent: The node the objects go under.
            scene: The scene.
            assets: Where the geometries, materials and textures go.

        Raises:
            Error: For anything `build_object` refuses.
        """
        if data.kind != _GROUP:
            return
        for slot in self.trees[data.tree].order(data.node):
            var key = self.trees[data.tree].nodes[data.node].keys[slot]
            var object = self.value(data.tree, data.node, slot)
            if key.startswith("def Scope"):
                self.build_hierarchy(object, parent, scene, assets)
            elif key.startswith("def Xform"):
                var node = self.build_object(
                    object, _xform_name(key), parent, scene, assets
                )
                self.build_hierarchy(object, node, scene, assets)


def _attribute(values: List[Float64], size: Int) raises -> BufferAttribute:
    """Return an attribute of numbers as a `Float32Array` holds them.

    Args:
        values: The numbers.
        size: Numbers a vertex.

    Returns:
        The attribute.

    Raises:
        Error: If the numbers are not whole vertices.
    """
    if len(values) % size != 0:
        raise Error("USD: an attribute that is not whole vertices")
    var floats = List[Float32](capacity=len(values))
    for value in values:
        floats.append(Float32(value))
    return BufferAttribute(floats^, size)


def _build(
    var stage: UsdaTree,
    var layers: List[_Layer],
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId,
) raises -> UsdModel:
    """Add three.js's `buildGroup`.

    Args:
        stage: The stage's tree.
        layers: The archive's layers.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under.

    Returns:
        What was added.

    Raises:
        Error: For anything the builder refuses.
    """
    var root = scene.attach(Object3D(), parent)
    var builder = _Builder(stage^, layers^, root)
    builder.build_hierarchy(_Value(_GROUP, "", 0, 0), root, scene, assets)
    return builder^.result()


def parse_usda(
    text: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> UsdModel:
    """Read USDA text into a scene, three.js's `USDLoader.parse` of a
    string.

    Args:
        text: The text.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.

    Returns:
        What was added. A texture has no image, as there is no archive.

    Raises:
        Error: For anything the module docstring lists.
    """
    return _build(usda_tree(text), List[_Layer](), scene, assets, parent)


def _is_crate(bytes: Span[UInt8, _]) -> Bool:
    """Return three.js's `isCrateFile`: the bytes start with `PXR-USDC`.

    Args:
        bytes: The file.

    Returns:
        Whether it is a crate.
    """
    return len(bytes) >= 8 and String(unsafe_from_utf8=bytes[:8]) == "PXR-USDC"


def _text(bytes: Span[UInt8, _], name: String) raises -> String:
    """Return a file as fflate's `strFromU8` decodes it: a byte order mark
    dropped.

    Args:
        bytes: The file.
        name: Its name, for the message.

    Returns:
        The text.

    Raises:
        Error: If the bytes are not UTF-8.
    """
    var start = 0
    var marked = (
        len(bytes) >= 3
        and bytes[0] == 0xEF
        and bytes[1] == 0xBB
        and bytes[2] == 0xBF
    )
    if marked:
        start = 3
    try:
        return String(from_utf8=bytes[start:])
    except:
        raise Error("USD: " + name + " is not UTF-8 text")


def parse_usd(
    bytes: List[UInt8],
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> UsdModel:
    """Read a USD file's bytes into a scene, three.js's `USDLoader.parse`
    of a buffer.

    Args:
        bytes: The file: a USDC crate or a USDZ archive.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.

    Returns:
        What was added: nothing under the root for a crate.

    Raises:
        Error: If the archive cannot be unzipped, its first file is not a
            USD layer, and for anything `parse_usda` refuses.
    """
    if _is_crate(bytes):
        return _build(UsdaTree(), List[_Layer](), scene, assets, parent)
    var entries = unzip(bytes)
    var names = List[String]()
    for entry in entries:
        if entry.name not in names:
            names.append(entry.name)
    var layers = List[_Layer]()
    for name in js_key_order(names):
        # fflate keeps the last file of a name.
        var data = List[UInt8]()
        for entry in entries:  # pragma: no branch
            if entry.name == name:
                data = entry.data.copy()
        if name.endswith("png"):
            layers.append(_Layer(name, 0, data^, UsdaTree()))
        elif (
            name.endswith("usd")
            or name.endswith("usda")
            or name.endswith("usdc")
        ):
            if _is_crate(data):
                layers.append(_Layer(name, 2, data^, UsdaTree()))
            else:
                var tree = usda_tree(_text(data, name))
                layers.append(_Layer(name, 1, data^, tree^))
    var order = js_key_order(names)
    if len(order) == 0:
        raise Error("USD: the archive is empty")
    var first = order[0]
    var layer = (
        first.endswith("usda")
        or first.endswith("usdc")
        or first.endswith("usd")
    )
    if not layer:
        raise Error("USD: the archive's first file is not a USD layer")
    var main = List[UInt8]()
    for entry in entries:  # pragma: no branch
        if entry.name == first:
            main = entry.data.copy()
    return _build(usda_tree(_text(main, first)), layers^, scene, assets, parent)


def read_usd(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> UsdModel:
    """Read a USD file as three.js's `USDLoader.load` does: as bytes.

    Args:
        path: The file.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.

    Returns:
        What `parse_usd` gives.

    Raises:
        Error: If the file cannot be read, and for anything `parse_usd`
            refuses. A `.usda` file is refused as a ZIP, as three.js's
            `load` refuses it.
    """
    return parse_usd(Path(path).read_bytes(), scene, assets, parent)


def read_usda(
    path: String,
    mut scene: Scene,
    mut assets: Assets,
    parent: NodeId = NO_PARENT,
) raises -> UsdModel:
    """Read a USDA file as text, as three.js's `parse` reads a string.

    Args:
        path: The file.
        scene: The scene.
        assets: Where the geometries, materials and textures go.
        parent: The node the group goes under, or `NO_PARENT`.

    Returns:
        What `parse_usda` gives.

    Raises:
        Error: If the file cannot be read, and for anything `parse_usda`
            refuses.
    """
    return parse_usda(Path(path).read_text(), scene, assets, parent)
