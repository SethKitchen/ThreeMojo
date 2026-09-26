# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The chunks of a LightWave object read into a tree, from three.js
`examples/jsm/loaders/lwo/IFFParser.js`, `LWO2Parser.js` and
`LWO3Parser.js`.

`parse_lwo_tree` is three.js's `IFFParser.parse`. three.js reads the file
into JavaScript objects whose shape depends on what the file holds, and a
chunk writes into whichever object is current. `LwoTree` holds the same
objects: each is a list of keys and values, and a value is a number, a
string, a list of either, an object or a list of objects. The reader
follows three.js's state: the current form, its parent and where it ends,
the current layer, node and surface. So a chunk lands where three.js puts
it, even when that is not where the format means it to go.

**Where three.js's reading is kept.** An LWO2 chunk whose four-byte
length runs past the file is read again with a two-byte length, as three.js
reads the sub-chunks of a surface. The chunks three.js skips are skipped by
their length, with no pad byte. A points chunk is read three floats at a
time while fewer than its length's quarter have been read, so a length that
is not a multiple of twelve reads past it. A double is read as a 64-bit
integer. An unknown chunk is kept as text under its tag. Object keys are
walked in JavaScript's order: array indices first, from smallest.

**What is refused.** What three.js throws on: a file with no `FORM` of
`LWO2` or `LWO3`, a read past the end, an empty `TAGS` chunk, surface tags
before any polygons, and a chunk that writes into a form, a node or a
surface that is not there. And polygons before any points, which three.js
reads as a mesh with no positions.
"""

from loaders.js_text import js_units
from loaders.three_mf import js_key_order
from std.memory import bitcast

# What a value in the tree is.
comptime _UNDEFINED = 0
comptime _NUMBER = 1
comptime _STRING = 2
comptime _NUMBERS = 3
comptime _STRINGS = 4
comptime _OBJECT = 5
comptime _OBJECTS = 6


struct LwoValue(Copyable, Movable):
    """A value of three.js's parsed tree: `undefined`, a number, a string,
    an array of numbers or strings, an object or an array of objects."""

    var kind: Int
    var number: Float64
    var text: String
    var numbers: List[Float64]
    var strings: List[String]
    # An object's index in `LwoTree.objects`.
    var object: Int
    var objects: List[Int]

    def __init__(out self):
        """Make `undefined`."""
        self.kind = _UNDEFINED
        self.number = 0
        self.text = String()
        self.numbers = List[Float64]()
        self.strings = List[String]()
        self.object = -1
        self.objects = List[Int]()

    def is_undefined(self) -> Bool:
        """Return True for `undefined`.

        Returns:
            Whether it is.
        """
        return self.kind == _UNDEFINED

    def is_number(self) -> Bool:
        """Return True for a number.

        Returns:
            Whether it is.
        """
        return self.kind == _NUMBER

    def is_string(self) -> Bool:
        """Return True for a string.

        Returns:
            Whether it is.
        """
        return self.kind == _STRING

    def is_numbers(self) -> Bool:
        """Return True for an array of numbers.

        Returns:
            Whether it is.
        """
        return self.kind == _NUMBERS

    def is_strings(self) -> Bool:
        """Return True for an array of strings.

        Returns:
            Whether it is.
        """
        return self.kind == _STRINGS

    def is_object(self) -> Bool:
        """Return True for an object.

        Returns:
            Whether it is.
        """
        return self.kind == _OBJECT

    def is_objects(self) -> Bool:
        """Return True for an array of objects.

        Returns:
            Whether it is.
        """
        return self.kind == _OBJECTS

    def truthy(self) -> Bool:
        """Return JavaScript's truth of the value: a number other than zero
        and NaN, a string that is not empty, and any object or array.

        Returns:
            Whether it is true.
        """
        if self.kind == _UNDEFINED:
            return False
        if self.kind == _NUMBER:
            return self.number == self.number and self.number != 0
        if self.kind == _STRING:
            return self.text.byte_length() > 0
        return True


def _number(v: Float64) -> LwoValue:
    var out = LwoValue()
    out.kind = _NUMBER
    out.number = v
    return out^


def _string(var s: String) -> LwoValue:
    var out = LwoValue()
    out.kind = _STRING
    out.text = s^
    return out^


def _numbers(var v: List[Float64]) -> LwoValue:
    var out = LwoValue()
    out.kind = _NUMBERS
    out.numbers = v^
    return out^


def _strings(var v: List[String]) -> LwoValue:
    var out = LwoValue()
    out.kind = _STRINGS
    out.strings = v^
    return out^


def _object(index: Int) -> LwoValue:
    var out = LwoValue()
    out.kind = _OBJECT
    out.object = index
    return out^


def _objects(var v: List[Int]) -> LwoValue:
    var out = LwoValue()
    out.kind = _OBJECTS
    out.objects = v^
    return out^


struct LwoObject(Copyable, Movable):
    """A JavaScript object of the tree: its keys, in the order they were
    added, and their values."""

    var keys: List[String]
    var values: List[LwoValue]

    def __init__(out self):
        """Make an empty object."""
        self.keys = List[String]()
        self.values = List[LwoValue]()


struct LwoTree(Movable):
    """Everything `parse_lwo_tree` read: three.js's `_lwoTree`.

    Object 0 is the tree itself, with `materials`, `layers`, `tags` and
    `textures`.
    """

    var objects: List[LwoObject]
    # `LWO2` or `LWO3`.
    var format: String

    def __init__(out self):
        """Start a tree of one empty object."""
        self.objects = List[LwoObject]()
        self.objects.append(LwoObject())
        self.format = String()

    def add(mut self) -> Int:
        """Add an empty object.

        Returns:
            Its index.
        """
        self.objects.append(LwoObject())
        return len(self.objects) - 1

    def find(self, object: Int, key: String) -> Int:
        """Return where a key is in an object, or -1.

        Args:
            object: The object.
            key: The key.

        Returns:
            The key's place.
        """
        ref o = self.objects[object]
        for k in range(len(o.keys)):
            if o.keys[k] == key:
                return k
        return -1

    def get(self, object: Int, key: String) -> LwoValue:
        """Return a key's value, or `undefined`.

        Args:
            object: The object.
            key: The key.

        Returns:
            A copy of the value.
        """
        var at = self.find(object, key)
        if at < 0:
            return LwoValue()
        return self.objects[object].values[at].copy()

    def set(mut self, object: Int, key: String, var value: LwoValue):
        """Set a key, keeping its place if it is there.

        Args:
            object: The object.
            key: The key.
            value: The value.
        """
        var at = self.find(object, key)
        if at < 0:
            self.objects[object].keys.append(key)
            self.objects[object].values.append(value^)
        else:
            self.objects[object].values[at] = value^

    def child(self, object: Int, key: String) -> Int:
        """Return the object a key holds, or -1.

        Args:
            object: The object.
            key: The key.

        Returns:
            The object's index.
        """
        var value = self.get(object, key)
        return value.object if value.is_object() else -1

    def walk(self, object: Int) -> List[String]:
        """Return an object's keys in the order `for ... in` walks them.

        Args:
            object: The object.

        Returns:
            The keys.
        """
        return js_key_order(self.objects[object].keys)


def _decode(bytes: List[UInt8], start: Int, end: Int) -> String:
    """Return bytes as `TextDecoder` reads them: UTF-8, a byte that does
    not fit read as U+FFFD."""
    var out = String()
    var at = start
    while at < end:
        var b = Int(bytes[at])
        var need = 0
        var point = b
        if b >= 0xF0 and b < 0xF5:
            need = 3
            point = b & 7
        elif b >= 0xE0 and b < 0xF0:
            need = 2
            point = b & 15
        elif b >= 0xC2 and b < 0xE0:
            need = 1
            point = b & 31
        elif b >= 0x80:
            out += chr(0xFFFD)
            at += 1
            continue
        var ok = at + need < end
        for k in range(1, need + 1):
            if ok:
                var c = Int(bytes[at + k])
                ok = c >= 0x80 and c < 0xC0
                point = (point << 6) | (c & 63)
        if ok and need > 0:
            ok = not (
                (need == 2 and point < 0x800)
                or (need == 3 and (point < 0x10000 or point > 0x10FFFF))
                or (point >= 0xD800 and point < 0xE000)
            )
        if not ok:
            out += chr(0xFFFD)
            at += 1
            continue
        out += chr(point)
        at += need + 1
    return out^


def string_offset(text: String) -> Int:
    """Return three.js's `stringOffset`: the string's length in UTF-16
    units, one for its end, and a pad to even.

    Args:
        text: The string.

    Returns:
        The bytes three.js takes it to fill.
    """
    var n = len(js_units(text)) + 1
    return n + n % 2


struct _Reader:
    """three.js's `DataViewReader`: big-endian values from the bytes."""

    var bytes: List[UInt8]
    var offset: Int

    def __init__(out self, var bytes: List[UInt8]):
        self.bytes = bytes^
        self.offset = 0

    def need(self, size: Int) raises:
        if self.offset + size > len(self.bytes):
            raise Error(
                "LWO: a value runs past the end, at byte " + String(self.offset)
            )

    def set_offset(mut self, offset: Int):
        # three.js logs and keeps its place for an offset past the end. No
        # offset here is before the start.
        if offset < len(self.bytes):
            self.offset = offset

    def at_end(self) -> Bool:
        return self.offset >= len(self.bytes)

    def skip(mut self, length: Int):
        self.offset += length

    def u8(mut self) raises -> Int:
        self.need(1)
        var v = Int(self.bytes[self.offset])
        self.offset += 1
        return v

    def u16(mut self) raises -> Int:
        self.need(2)
        var v = (Int(self.bytes[self.offset]) << 8) | Int(
            self.bytes[self.offset + 1]
        )
        self.offset += 2
        return v

    def u32(mut self) raises -> Int:
        self.need(4)
        var v = 0
        for k in range(4):  # pragma: no branch
            v = (v << 8) | Int(self.bytes[self.offset + k])
        self.offset += 4
        return v

    def i32(mut self) raises -> Int:
        var v = self.u32()
        return v - (1 << 32) if v >= (1 << 31) else v

    def u64(mut self) raises -> Float64:
        var low = self.u32()
        var high = self.u32()
        return Float64(high) * 4294967296.0 + Float64(low)

    def f32(mut self) raises -> Float64:
        return Float64(bitcast[DType.float32](UInt32(self.u32())))

    def f64(mut self) raises -> Float64:
        var high = UInt64(self.u32())
        var low = UInt64(self.u32())
        return bitcast[DType.float64]((high << 32) | low)

    def f32s(mut self, count: Int) raises -> List[Float64]:
        var out = List[Float64]()
        for _ in range(count):  # pragma: no branch
            out.append(self.f32())
        return out^

    def vx(mut self) raises -> Int:
        """three.js's `getVariableLengthIndex`."""
        var first = self.u8()
        if first == 255:
            var a = self.u8()
            var b = self.u8()
            var c = self.u8()
            return a * 65536 + b * 256 + c
        return first * 256 + self.u8()

    def tag(mut self) raises -> String:
        """three.js's `getIDTag`: four bytes as text."""
        self.need(4)
        var out = _decode(self.bytes, self.offset, self.offset + 4)
        self.offset += 4
        return out^

    def text(mut self, size: Int) raises -> String:
        """three.js's `getString( size )` for a size that is not zero."""
        self.need(size)
        var out = _decode(self.bytes, self.offset, self.offset + size)
        self.offset += size
        return out^

    def string(mut self) raises -> String:
        """three.js's `getString()`: to the next zero byte, the reader moved
        past it and a pad to even."""
        var end = self.offset
        while end < len(self.bytes) and self.bytes[end] != 0:
            end += 1
        if end >= len(self.bytes):
            raise Error("LWO: a string runs past the end")
        var out = _decode(self.bytes, self.offset, end)
        var length = end - self.offset + 1
        length += length % 2
        self.offset += length
        return out^


# The chunks both parsers skip by their length.
comptime _SKIPPED: List[String] = [
    "ICON",
    "VMPA",
    "BBOX",
    "NORM",
    "PRE ",
    "POST",
    "KEY ",
    "SPAN",
    "TIME",
    "CLRS",
    "CLRA",
    "FILT",
    "DITH",
    "CONT",
    "BRIT",
    "SATR",
    "HUE ",
    "GAMM",
    "NEGA",
    "IFLT",
    "PFLT",
    "PROJ",
    "AXIS",
    "AAST",
    "PIXB",
    "STCK",
    "VALU",
    "PNAM",
    "INAM",
    "GRST",
    "GREN",
    "GRPT",
    "FKEY",
    "IKEY",
    "CSYS",
    "OPAQ",
    "CMAP",
    "NLOC",
    "NZOM",
    "NVER",
    "NSRV",
    "NCRD",
    "NMOD",
    "NSEL",
    "NPRW",
    "NPLA",
    "VERS",
    "ENUM",
    "TAG ",
    "CGMD",
    "CGTY",
    "CGST",
    "CGEN",
    "CGTS",
    "CGTE",
    "OSMP",
    "OMDE",
    "OUTR",
    "FLAG",
    "TRNL",
    "SHRP",
    "RFOP",
    "RSAN",
    "TROP",
    "RBLR",
    "TBLR",
    "CLRH",
    "CLRF",
    "ADTR",
    "GLOW",
    "LINE",
    "ALPH",
    "VCOL",
    "ENAB",
]
# The chunks only the LWO2 parser skips.
comptime _SKIPPED_LWO2: List[String] = [
    "AUVO",
    "PROC",
    "FUNC",
    "NVSK",
    "WRPW",
    "WRPH",
    "NODS",
    "OPAC",
    "GVAL",
    "TMAP",
]
# Image node settings kept as an integer when four bytes long.
comptime _NODE_INTEGERS: List[String] = [
    "IPIX",
    "IMIP",
    "IMOD",
    "AMOD",
    "IINV",
    "INCR",
    "IAXS",
    "IFOT",
    "ITIM",
    "IWRL",
    "IUTI",
    "IINX",
    "IINY",
    "IINZ",
    "IREF",
]
# Forms three.js skips by their length.
comptime _SKIPPED_FORMS: List[String] = [
    "ISEQ",
    "ANIM",
    "STCC",
    "VPVL",
    "VPRM",
    "NROT",
    "WRPW",
    "WRPH",
    "FUNC",
    "FALL",
    "OPAC",
    "GRAD",
    "ENVS",
    "VMOP",
    "VMBG",
    "OMAX",
    "STEX",
    "CKBG",
    "CKEY",
    "VMLA",
    "VMLB",
]
# Forms whose chunks three.js reads as if they were not in a form.
comptime _OPEN_FORMS: List[String] = [
    "META",
    "NNDS",
    "NODS",
    "NDTA",
    "ADAT",
    "AOVS",
    "BLOK",
    "IBGC",
    "IOPC",
    "IIMG",
    "TXTR",
]
# Image node attributes: a form three.js reads a value out of.
comptime _NODE_ATTRIBUTES: List[String] = [
    "IFAL",
    "ISCL",
    "IPOS",
    "IROT",
    "IBMP",
    "IUTD",
    "IVTD",
]


def _is(tag: String, names: List[String]) -> Bool:
    for name in names:  # pragma: no branch
        if tag == name:
            return True
    return False


struct _Parser:
    """three.js's `IFFParser` and its block parsers, with their state."""

    var r: _Reader
    var tree: LwoTree
    var materials: Int
    var current_layer: Int
    # -1 is `undefined`.
    var current_form: Int
    var parent_form: Int
    var form_end: Int
    var has_form_end: Bool
    var current_node: Int
    var current_surface: Int
    var points: List[Float64]
    var has_points: Bool

    def __init__(out self, var bytes: List[UInt8]):
        self.r = _Reader(bytes^)
        self.tree = LwoTree()
        self.materials = self.tree.add()
        self.tree.set(0, "materials", _object(self.materials))
        self.tree.set(0, "layers", _objects(List[Int]()))
        self.tree.set(0, "tags", _strings(List[String]()))
        self.tree.set(0, "textures", _objects(List[Int]()))
        self.current_layer = 0
        self.current_form = 0
        self.parent_form = -1
        self.form_end = 0
        self.has_form_end = False
        self.current_node = -1
        self.current_surface = -1
        self.points = List[Float64]()
        self.has_points = False

    def take(deinit self) -> LwoTree:
        return self.tree^

    # --- where a chunk writes ----------------------------------------------

    def form(self) raises -> Int:
        if self.current_form < 0:
            raise Error("LWO: a chunk writes into a form that is not there")
        return self.current_form

    def node(self) raises -> Int:
        if self.current_node < 0:
            raise Error("LWO: a chunk writes into a node that is not there")
        return self.current_node

    def surface(self) raises -> Int:
        if self.current_surface < 0:
            raise Error("LWO: a chunk writes into a surface that is not there")
        return self.current_surface

    def surface_attributes(self) raises -> Int:
        return self.tree.child(self.surface(), "attributes")

    def end_form(mut self, length: Int):
        self.form_end = self.r.offset + length
        self.has_form_end = True

    def push_object(mut self, object: Int, key: String, child: Int):
        var value = self.tree.get(object, key)
        var list = value.objects.copy() if value.is_objects() else List[Int]()
        list.append(child)
        self.tree.set(object, key, _objects(list^))

    def push_string(mut self, object: Int, key: String, var text: String):
        var value = self.tree.get(object, key)
        var list = value.strings.copy() if value.is_strings() else List[
            String
        ]()
        list.append(text^)
        self.tree.set(object, key, _strings(list^))

    # --- the top ------------------------------------------------------------

    def parse(mut self) raises:
        var top = self.r.tag()
        if top != "FORM":
            raise Error("LWO: the file does not start with a FORM")
        _ = self.r.u32()
        var kind = self.r.tag()
        if kind != "LWO2" and kind != "LWO3":
            raise Error("LWO: the file is neither LWO2 nor LWO3")
        self.tree.format = kind
        var lwo3 = kind == "LWO3"
        # Each block moves the reader past its tag and its length, at least,
        # so the loop ends.
        while not self.r.at_end():
            self.block(lwo3)

    def block(mut self, lwo3: Bool) raises:
        """three.js's `parseBlock`, of `LWO2Parser` or `LWO3Parser`."""
        var id = self.r.tag()
        var length = self.r.u32()
        if not lwo3 and length > len(self.r.bytes) - self.r.offset:
            self.r.offset -= 4
            length = self.r.u16()
        if id == "FORM":
            self.parse_form(length, lwo3)
        elif _is(id, materialize[_SKIPPED]()) or (
            not lwo3 and _is(id, materialize[_SKIPPED_LWO2]())
        ):
            self.r.skip(length)
        elif not lwo3 and id == "SURF":
            self.surface_lwo2(length)
        elif not lwo3 and id == "CLIP":
            self.clip_lwo2(length)
        elif _is(id, materialize[_NODE_INTEGERS]()):
            if length == 4:
                var v = self.r.i32()
                self.tree.set(self.node(), id, _number(Float64(v)))
            else:
                self.r.skip(length)
        elif id == "OTAG":
            self.object_tag()
        elif id == "LAYR":
            self.layer(length)
        elif id == "PNTS":
            self.read_points(length)
        elif id == "VMAP":
            self.vertex_mapping(length, False)
        elif not lwo3 and (id == "AUVU" or id == "AUVN"):
            self.r.skip(length - 1)
            _ = self.r.vx()
        elif id == "POLS":
            self.polygons(length)
        elif id == "TAGS":
            self.tag_strings(length)
        elif id == "PTAG":
            self.polygon_tags(length)
        elif id == "VMAD":
            self.vertex_mapping(length, True)
        elif id == "DESC":
            var text = self.r.string()
            self.tree.set(self.form(), "description", _string(text^))
        elif id == "TEXT" or id == "CMNT" or id == "NCOM":
            var text = self.r.string()
            self.tree.set(self.form(), "comment", _string(text^))
        elif id == "NAME":
            var text = self.r.string()
            self.tree.set(self.form(), "channelName", _string(text^))
        elif id == "WRAP":
            var wrap = self.tree.add()
            var w = self.r.u16()
            var h = self.r.u16()
            self.tree.set(wrap, "w", _number(Float64(w)))
            self.tree.set(wrap, "h", _number(Float64(h)))
            self.tree.set(self.form(), "wrap", _object(wrap))
        elif id == "IMAG":
            var index = self.r.vx()
            self.tree.set(self.form(), "imageIndex", _number(Float64(index)))
        elif id == "OREF":
            var text = self.r.string()
            self.tree.set(self.form(), "referenceObject", _string(text^))
        elif id == "ROID":
            var v = self.r.u32()
            self.tree.set(self.form(), "referenceObjectID", _number(Float64(v)))
        elif id == "SSHN":
            var text = self.r.string()
            self.tree.set(self.surface(), "surfaceShaderName", _string(text^))
        elif id == "AOVN":
            var text = self.r.string()
            self.tree.set(
                self.surface(), "surfaceCustomAOVName", _string(text^)
            )
        elif id == "NSTA":
            var v = self.r.u16()
            self.tree.set(self.form(), "disabled", _number(Float64(v)))
        elif id == "NRNM":
            var text = self.r.string()
            self.tree.set(self.form(), "realName", _string(text^))
        elif id == "NNME":
            var text = self.r.string()
            var form = self.form()
            self.tree.set(form, "refName", _string(text.copy()))
            var nodes = self.tree.child(self.surface(), "nodes")
            self.tree.set(nodes, text, _object(form))
        elif id == "INME":
            self.push_string(self.form(), "nodeName", self.r.string())
        elif id == "IINN":
            self.push_string(self.form(), "inputNodeName", self.r.string())
        elif id == "IINM":
            self.push_string(self.form(), "inputName", self.r.string())
        elif id == "IONM":
            self.push_string(self.form(), "inputOutputName", self.r.string())
        elif id == "FNAM":
            var text = self.r.string()
            self.tree.set(self.form(), "fileName", _string(text^))
        elif id == "CHAN":
            if length == 4:
                var text = self.r.tag()
                self.tree.set(self.form(), "textureChannel", _string(text^))
            else:
                self.r.skip(length)
        elif id == "SMAN":
            var angle = self.r.f32()
            self.tree.set(
                self.surface_attributes(),
                "smooth",
                _number(0.0 if angle < 0 else 1.0),
            )
        elif (
            id == "COLR"
            or id == "LUMI"
            or id == "SPEC"
            or id == "DIFF"
            or id == "REFL"
            or id == "GLOS"
        ):
            self.surface_value(id)
        elif id == "TRAN" or id == "BUMP" or id == "RIND":
            var v = self.r.f32()
            self.r.skip(2)
            var key = "opacity" if id == "TRAN" else (
                "bumpStrength" if id == "BUMP" else "refractiveIndex"
            )
            self.tree.set(self.surface_attributes(), key, _number(v))
        elif id == "SIDE":
            var v = self.r.u16()
            self.tree.set(
                self.surface_attributes(), "side", _number(Float64(v))
            )
        elif id == "RIMG" or id == "TIMG":
            var v = self.r.vx()
            var key = "reflectionMap" if id == "RIMG" else "refractionMap"
            self.tree.set(self.surface_attributes(), key, _number(Float64(v)))
        elif id == "IMAP":
            if lwo3:
                var v = self.r.u32()
                self.tree.set(
                    self.surface_attributes(),
                    "imageMapIndex",
                    _number(Float64(v)),
                )
            else:
                self.r.skip(2)
        elif id == "IUVI":
            var value = LwoValue()
            if length != 0:
                value = _string(self.r.text(length))
            self.tree.set(self.node(), "UVChannel", value^)
        elif id == "IUTL" or id == "IVTL":
            var v = self.r.u32()
            var key = (
                "widthWrappingMode" if id == "IUTL" else "heightWrappingMode"
            )
            self.tree.set(self.node(), key, _number(Float64(v)))
        elif not lwo3 and id == "BLOK":
            pass
        else:
            # three.js's `parseUnknownCHUNK`: the bytes kept as text.
            var value = LwoValue()
            if length != 0:
                value = _string(self.r.text(length))
            self.tree.set(self.form(), id, value^)
        if self.has_form_end and self.r.offset >= self.form_end:
            self.current_form = self.parent_form

    def surface_value(mut self, id: String) raises:
        """A surface value of LWO2's: a color or a float, and an envelope."""
        var key: String
        if id == "COLR":
            key = "Color"
        elif id == "LUMI":
            key = "Luminosity"
        elif id == "SPEC":
            key = "Specular"
        elif id == "DIFF":
            key = "Diffuse"
        elif id == "REFL":
            key = "Reflection"
        else:
            key = "Glossiness"
        var entry = self.tree.add()
        if id == "COLR":
            self.tree.set(entry, "value", _numbers(self.r.f32s(3)))
        else:
            self.tree.set(entry, "value", _number(self.r.f32()))
        self.r.skip(2)
        self.tree.set(self.surface_attributes(), key, _object(entry))

    # --- forms --------------------------------------------------------------

    def parse_form(mut self, length: Int, lwo3: Bool) raises:
        """three.js's `parseForm`."""
        var kind = self.r.tag()
        if _is(kind, materialize[_SKIPPED_FORMS]()):
            self.r.skip(length - 4)
        elif _is(kind, materialize[_OPEN_FORMS]()):
            pass
        elif _is(kind, materialize[_NODE_ATTRIBUTES]()):
            self.node_attribute(kind)
        elif kind == "ENVL":
            self.r.skip(length - 4)
        elif kind == "CLIP":
            if lwo3:
                self.clip(length)
            else:
                self.parse_form(length, lwo3)
        elif kind == "STIL":
            self.r.skip(8)
            var text = self.r.string()
            self.tree.set(self.form(), "fileName", _string(text^))
        elif kind == "XREF":
            self.r.skip(8)
            var reference = self.tree.add()
            var index = self.r.u32()
            self.tree.set(reference, "index", _number(Float64(index)))
            self.tree.set(reference, "refName", _string(self.r.string()))
            self.tree.set(self.form(), "referenceTexture", _object(reference))
        elif kind == "IMST":
            self.r.skip(8)
            var level = self.r.f32()
            self.tree.set(self.form(), "mipMapLevel", _number(level))
        elif kind == "SURF":
            self.surface_form(length)
        elif kind == "VALU":
            self.value_form()
        elif kind == "NTAG":
            self.sub_node(length)
        elif kind == "ATTR" or kind == "SATR":
            self.setup_form("attributes", length)
        elif kind == "NCON":
            self.end_form(length)
            self.parent_form = self.current_form
            self.current_form = self.tree.child(self.surface(), "connections")
        elif kind == "SSHA":
            self.parent_form = self.current_form
            self.current_form = self.surface()
            self.setup_form("surfaceShader", length)
        elif kind == "SSHD":
            self.setup_form("surfaceShaderData", length)
        elif kind == "ENTR":
            self.entry_form(length)
        elif kind == "IMAP":
            self.image_map(length)
        elif kind == "TAMP":
            var end = self.r.offset + length - 4
            self.r.skip(8)
            var v = self.r.f32()
            self.tree.set(self.form(), "amplitude", _number(v))
            self.r.set_offset(end)
        elif kind == "TMAP":
            self.setup_form("textureMap", length)
        elif kind == "CNTR" or kind == "SIZE" or kind == "ROTA":
            var end = self.r.offset + length - 4
            self.r.skip(8)
            var xyz = self.tree.add()
            self.tree.set(xyz, "x", _number(self.r.f32()))
            self.tree.set(xyz, "y", _number(self.r.f32()))
            self.tree.set(xyz, "z", _number(self.r.f32()))
            var key = "center" if kind == "CNTR" else (
                "scale" if kind == "SIZE" else "rotation"
            )
            self.tree.set(self.form(), key, _object(xyz))
            self.r.set_offset(end)
        else:
            self.r.skip(length - 4)

    def setup_form(mut self, key: String, length: Int) raises:
        """three.js's `setupForm`: a child object of the current form."""
        if self.current_form < 0:
            self.current_form = self.current_node
        self.end_form(length)
        self.parent_form = self.current_form
        var form = self.form()
        var found = self.tree.get(form, key)
        if found.is_undefined():
            var child = self.tree.add()
            self.tree.set(form, key, _object(child))
            self.current_form = child
        elif found.is_object():
            self.current_form = found.object
        else:
            raise Error("LWO: a form's key " + key + " is not an object")

    def surface_form(mut self, length: Int) raises:
        """three.js's `parseSurfaceForm`, of LWO3."""
        self.r.skip(8)
        var name = self.r.string()
        var surface = self.new_surface(name)
        self.tree.set(surface, "inputName", _string(name.copy()))
        self.tree.set(surface, "source", _string(self.r.string()))
        self.end_form(length)

    def surface_lwo2(mut self, length: Int) raises:
        """three.js's `parseSurfaceLwo2`."""
        var name = self.r.string()
        var surface = self.new_surface(name)
        self.tree.set(surface, "source", _string(self.r.string()))
        self.end_form(length)

    def new_surface(mut self, name: String) -> Int:
        var surface = self.tree.add()
        var attributes = self.tree.add()
        var connections = self.tree.add()
        var nodes = self.tree.add()
        self.tree.set(surface, "attributes", _object(attributes))
        self.tree.set(surface, "connections", _object(connections))
        self.tree.set(surface, "name", _string(name.copy()))
        self.tree.set(surface, "nodes", _object(nodes))
        self.tree.set(self.materials, name, _object(surface))
        self.current_surface = surface
        self.parent_form = self.materials
        self.current_form = surface
        return surface

    def sub_node(mut self, length: Int) raises:
        """three.js's `parseSubNode`."""
        self.r.skip(8)
        var node = self.tree.add()
        self.tree.set(node, "name", _string(self.r.string()))
        self.current_form = node
        self.current_node = node
        self.end_form(length)

    def entry_form(mut self, length: Int) raises:
        """three.js's `parseEntryForm`."""
        self.r.skip(8)
        var name = self.r.string()
        # A node's attributes are only ever an object, or not there.
        self.current_form = self.tree.child(self.node(), "attributes")
        self.setup_form(name, length)

    def value_form(mut self) raises:
        """three.js's `parseValueForm`: a double is read as a 64-bit
        integer, as three.js reads it."""
        self.r.skip(8)
        var kind = self.r.string()
        if kind == "double":
            var v = self.r.u64()
            self.tree.set(self.form(), "value", _number(v))
        elif kind == "int":
            var v = self.r.u32()
            self.tree.set(self.form(), "value", _number(Float64(v)))
        elif kind == "vparam":
            self.r.skip(24)
            var v = self.r.f64()
            self.tree.set(self.form(), "value", _number(v))
        elif kind == "vparam3":
            self.r.skip(24)
            var v = List[Float64]()
            for _ in range(3):  # pragma: no branch
                v.append(self.r.f64())
            self.tree.set(self.form(), "value", _numbers(v^))

    def image_map(mut self, length: Int) raises:
        """three.js's `parseImageMap`: a map added to the form's `maps`."""
        self.end_form(length)
        self.parent_form = self.current_form
        var form = self.form()
        var map = self.tree.add()
        self.push_object(form, "maps", map)
        self.current_form = map
        self.r.skip(10)

    def node_attribute(mut self, kind: String) raises:
        """three.js's `parseTextureNodeAttribute`."""
        self.r.skip(48)
        var node = self.node()
        if kind == "ISCL" or kind == "IPOS" or kind == "IROT" or kind == "IFAL":
            var key = "scale" if kind == "ISCL" else (
                "position" if kind
                == "IPOS" else ("rotation" if kind == "IROT" else "falloff")
            )
            self.tree.set(node, key, _numbers(self.r.f32s(3)))
        else:
            var key = "amplitude" if kind == "IBMP" else (
                "uTiles" if kind == "IUTD" else "vTiles"
            )
            self.tree.set(node, key, _number(self.r.f32()))
        self.r.skip(2)

    def clip(mut self, length: Int) raises:
        """three.js's `parseClip`, of LWO3."""
        var tag = self.r.tag()
        if tag == "FORM":
            self.r.skip(16)
            var text = self.r.string()
            self.tree.set(self.node(), "fileName", _string(text^))
            return
        self.r.set_offset(self.r.offset - 4)
        self.end_form(length)
        self.parent_form = self.current_form
        self.r.skip(8)
        var texture = self.tree.add()
        self.tree.set(texture, "index", _number(Float64(self.r.u32())))
        self.push_object(0, "textures", texture)
        self.current_form = texture

    def clip_lwo2(mut self, length: Int) raises:
        """three.js's `parseClipLwo2`."""
        var texture = self.tree.add()
        self.tree.set(texture, "index", _number(Float64(self.r.u32())))
        self.tree.set(texture, "fileName", _string(String()))
        while True:
            var tag = self.r.tag()
            var n = self.r.u16()
            if tag == "STIL":
                self.tree.set(texture, "fileName", _string(self.r.string()))
                break
            if n >= length:
                break
        self.push_object(0, "textures", texture)
        self.current_form = texture

    # --- geometry -----------------------------------------------------------

    def object_tag(mut self) raises:
        """three.js's `parseObjectTag`."""
        var tags = self.tree.child(0, "objectTags")
        if tags < 0:
            tags = self.tree.add()
            self.tree.set(0, "objectTags", _object(tags))
        var tag = self.r.tag()
        var entry = self.tree.add()
        self.tree.set(entry, "tagString", _string(self.r.string()))
        self.tree.set(tags, tag, _object(entry))

    def layer(mut self, length: Int) raises:
        """three.js's `parseLayer`: the pivot's x is negated."""
        var number = self.r.u16()
        var flags = self.r.u16()
        var pivot = self.r.f32s(3)
        var layer = self.tree.add()
        self.tree.set(layer, "number", _number(Float64(number)))
        self.tree.set(layer, "flags", _number(Float64(flags)))
        self.tree.set(layer, "pivot", _numbers([-pivot[0], pivot[1], pivot[2]]))
        var name = self.r.string()
        var parsed = 16 + string_offset(name)
        self.tree.set(layer, "name", _string(name^))
        self.push_object(0, "layers", layer)
        self.current_layer = layer
        var parent = Float64(-1)
        if parsed < length:
            parent = Float64(self.r.u16())
        self.tree.set(layer, "parent", _number(parent))

    def read_points(mut self, length: Int) raises:
        """three.js's `parsePoints`: x negated, three at a time while fewer
        than the length's quarter are read."""
        self.points = List[Float64]()
        self.has_points = True
        var i = 0
        while Float64(i) < Float64(length) / 4:
            var x = self.r.f32()
            var y = self.r.f32()
            var z = self.r.f32()
            self.points.append(-x)
            self.points.append(y)
            self.points.append(z)
            i += 3

    def vertex_mapping(mut self, length: Int, discontinuous: Bool) raises:
        """three.js's `parseVertexMapping`."""
        var final = self.r.offset + length
        var channel = self.r.string()
        if self.r.offset == final:
            self.tree.set(self.form(), "UVChannel", _string(channel^))
            return
        self.r.set_offset(self.r.offset - string_offset(channel))
        var kind = self.r.tag()
        _ = self.r.u16()
        var name = self.r.string()
        var remaining = length - 6 - string_offset(name)
        if kind == "TXUV":
            self.uv_mapping(name, final, discontinuous)
        elif kind == "MORF" or kind == "SPOT":
            self.morph_targets(name, final, kind)
        else:
            self.r.skip(remaining)

    def layer_map(mut self, key: String) -> Int:
        var map = self.tree.child(self.current_layer, key)
        if map < 0:
            map = self.tree.add()
            self.tree.set(self.current_layer, key, _object(map))
        return map

    def uv_mapping(
        mut self, name: String, final: Int, discontinuous: Bool
    ) raises:
        """three.js's `parseUVMapping`."""
        var indices = List[Float64]()
        var polygons = List[Float64]()
        var uvs = List[Float64]()
        while self.r.offset < final:
            indices.append(Float64(self.r.vx()))
            if discontinuous:
                polygons.append(Float64(self.r.vx()))
            uvs.append(self.r.f32())
            uvs.append(self.r.f32())
        var entry = self.tree.add()
        self.tree.set(entry, "uvIndices", _numbers(indices^))
        if discontinuous:
            self.tree.set(entry, "polyIndices", _numbers(polygons^))
        self.tree.set(entry, "uvs", _numbers(uvs^))
        var map = self.layer_map("discontinuousUVs" if discontinuous else "uvs")
        self.tree.set(map, name, _object(entry))

    def morph_targets(mut self, name: String, final: Int, kind: String) raises:
        """three.js's `parseMorphTargets`: z negated."""
        var indices = List[Float64]()
        var points = List[Float64]()
        while self.r.offset < final:
            indices.append(Float64(self.r.vx()))
            var x = self.r.f32()
            var y = self.r.f32()
            var z = self.r.f32()
            points.append(x)
            points.append(y)
            points.append(-z)
        var entry = self.tree.add()
        self.tree.set(entry, "indices", _numbers(indices^))
        self.tree.set(entry, "points", _numbers(points^))
        self.tree.set(
            entry,
            "type",
            _string(String("relative") if kind == "MORF" else "absolute"),
        )
        var map = self.layer_map("morphTargets")
        self.tree.set(map, name, _object(entry))

    def polygons(mut self, length: Int) raises:
        """three.js's `parsePolygonList`."""
        var final = self.r.offset + length
        var kind = self.r.tag()
        var indices = List[Float64]()
        var dimensions = List[Float64]()
        while self.r.offset < final:
            var count = self.r.u16() & 1023
            dimensions.append(Float64(count))
            for _ in range(count):
                indices.append(Float64(self.r.vx()))
        if not self.has_points:
            raise Error("LWO: polygons come before any points")
        if len(dimensions) > 0 and dimensions[0] == 1:
            kind = "points"
        elif len(dimensions) > 0 and dimensions[0] == 2:
            kind = "lines"
        var geometry = self.tree.add()
        self.tree.set(geometry, "type", _string(kind^))
        self.tree.set(geometry, "vertexIndices", _numbers(indices^))
        self.tree.set(geometry, "polygonDimensions", _numbers(dimensions^))
        self.tree.set(geometry, "points", _numbers(self.points.copy()))
        self.tree.set(self.current_layer, "geometry", _object(geometry))

    def tag_strings(mut self, length: Int) raises:
        """three.js's `parseTagStrings`: split at zero bytes, empty ones
        dropped."""
        if length == 0:
            # three.js splits `getString( 0 )`, which is `undefined`.
            raise Error("LWO: a TAGS chunk is empty")
        var text = self.r.text(length)
        var out = List[String]()
        var part = String()
        for c in text.codepoints():  # pragma: no branch
            if c.to_u32() == 0:
                if part.byte_length() > 0:
                    out.append(part)
                part = String()
            else:
                part += String(c)
        if part.byte_length() > 0:
            out.append(part)
        self.tree.set(0, "tags", _strings(out^))

    def polygon_tags(mut self, length: Int) raises:
        """three.js's `parsePolygonTagMapping`."""
        var final = self.r.offset + length
        var kind = self.r.tag()
        if kind != "SURF":
            self.r.skip(length - 4)
            return
        var geometry = self.tree.child(self.current_layer, "geometry")
        if geometry < 0:
            raise Error("LWO: surface tags come before any polygons")
        var indices = List[Float64]()
        while self.r.offset < final:
            indices.append(Float64(self.r.vx()))
            indices.append(Float64(self.r.u16()))
        self.tree.set(geometry, "materialIndices", _numbers(indices^))


def parse_lwo_tree(bytes: List[UInt8]) raises -> LwoTree:
    """Read a LightWave object's chunks, three.js's `IFFParser.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The tree three.js builds.

    Raises:
        Error: For anything the module docstring lists.
    """
    var parser = _Parser(bytes.copy())
    parser.parse()
    return parser^.take()
