# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose CARLA vehicle material factors before any image is encoded.

    carla_gltf_material REQUEST.json

REQUEST.json holds `name`, optional `mat` and `props` text, and `pngs`,
the texture stems that exist. The program prints the factor, blend,
texture, and report decisions. It does not read or write image files.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)


@fieldwise_init
struct _Num(Copyable, Movable):
    """One JSON number, an int when `integer` is true."""

    var value: Float64
    var integer: Bool


@fieldwise_init
struct _Plan(Copyable, Movable):
    """The decisions `rebuild` makes besides opening images."""

    var color: List[_Num]
    var metallic: _Num
    var roughness: _Num
    var blend: Bool
    var alpha_mode: String
    var cutoff: Bool
    var double_sided: Bool
    var extras: String
    var parent: String
    var textures: List[String]
    var report: List[String]


def plan_material(request_text: String) raises -> String:
    """Return the material decisions for one UModel material.

    Args:
        request_text: JSON with `name`, `mat`, `props`, and `pngs`. `mat`
            and `props` are the file text, or null when the file is absent.
            `pngs` lists texture stems.

    Returns:
        JSON for the factors, optional alpha and extras, texture steps,
        and the report triple.

    Raises:
        Error: If the request is missing a required field.
    """
    var doc = PyJson.parse(request_text)
    var name = doc.text(doc.at(doc.root, "name"))
    var mat = _optional_text(doc, "mat")
    var props = _optional_text(doc, "props")
    var pngs = List[String]()
    var listed = doc.at(doc.root, "pngs")
    for index in range(doc.length(listed)):
        pngs.append(doc.text(doc.item(listed, index)))
    var decision = _decide(name, mat, props, pngs)
    return _encode(decision)


def _optional_text(doc: PyJson, key: String) raises -> String:
    """Return a string field, or empty when it is null or absent."""
    var node = doc.find(doc.root, key)
    if node == MISSING or doc.kind(node) == PY_NONE:
        return ""
    return doc.text(node)


def _decide(
    name: String, mat: String, props: String, pngs: List[String]
) raises -> _Plan:
    """Apply the reviewed material rules."""
    var chosen = _by_name(name)
    var color = chosen[0].copy()
    var metallic = chosen[1].copy()
    var roughness = chosen[2].copy()
    var blend = chosen[3]
    var parent = String("")
    var masked = False
    var paint = False
    if props.byte_length() > 0:
        var parsed = _read_props(props)
        parent = parsed[0]
        blend = blend or parsed[3]
        masked = parsed[4]
        paint = (
            _has(parent, "M_CarExterior_Master")
            or _has(parent, "M_CarPaint")
            or _has(parent, "CarPaint")
        )
        var vectors = parsed[1].copy()
        var scalars = parsed[2].copy()
        var tint = _vector(vectors, "Base Color")
        if tint.byte_length() == 0:
            tint = _vector(vectors, "BaseColor")
        if tint.byte_length() == 0:
            tint = _vector(vectors, "Color")
        if tint.byte_length() == 0:
            tint = _vector(vectors, "Tint")
        if tint.byte_length() == 0:
            tint = _vector(vectors, "Paint Color")
        if tint.byte_length() > 0:
            color = _rgba(tint)
        if paint:
            metallic = _float("0.5")
            roughness = _float("0.3")
        var rough = _scalar(scalars, "Roughness")
        if rough.byte_length() == 0:
            rough = _scalar(scalars, "roughness")
        if rough.byte_length() > 0:
            roughness = _clamp(rough)
        var metal = _scalar(scalars, "Metallic")
        if metal.byte_length() == 0:
            metal = _scalar(scalars, "Metalness")
        if metal.byte_length() == 0:
            metal = _scalar(scalars, "metallic")
        if metal.byte_length() > 0:
            metallic = _clamp(metal)
    var glass = _has(_lower(name), "glass") or _has(_lower(parent), "glass")
    if glass:
        blend = True
        color = _glass_color()
        metallic = _float("0.0")
        roughness = _float("0.05")
    var textures = List[String]()
    var alpha_mode = String("")
    var cutoff = False
    var double_sided = False
    if mat.byte_length() > 0 and not paint and not glass:
        var entries = _read_mat(mat)
        var diffuse = _field(entries, "Diffuse")
        if diffuse.byte_length() == 0:
            diffuse = _other(entries, False)
        if diffuse.byte_length() > 0 and _listed(pngs, diffuse):
            textures.append("color " + diffuse)
            var kept = color[3].copy()
            color = _white(kept)
        var normal = _field(entries, "Normal")
        if (
            normal.byte_length() > 0
            and _listed(pngs, normal)
            and not _has(_lower(normal), "flat")
        ):
            textures.append("normal " + normal)
        if masked:
            var stem = diffuse
            if (
                stem.byte_length() == 0
                or _has(_lower(stem), "alpha")
                or _has(_lower(stem), "mask")
            ):
                var named = _other(entries, True)
                if named.byte_length() > 0:
                    stem = named
            var cut = _field(entries, "Opacity")
            if cut.byte_length() == 0:
                cut = diffuse
            if _listed(pngs, stem) and _listed(pngs, cut):
                textures.append("masked " + stem + "\n" + cut)
                color = _ones()
                alpha_mode = "MASK"
                cutoff = True
                double_sided = True
        var packed = _orm(entries)
        if packed.byte_length() > 0 and _listed(pngs, packed):
            textures.append("orm " + packed)
            metallic = _float("1.0")
            roughness = _float("1.0")
    var extras = String("")
    var lamps = _has(_lower(name), "light") and not glass
    if paint or _has(_lower(name), "bodywork"):
        extras = "paint"
    elif lamps:
        extras = "lamps"
        blend = False
        color[3] = _float("1.0")
    if blend:
        alpha_mode = "BLEND"
        if color[3].value > parse_float("0.4"):
            color[3] = _float("0.4")
    var report = _report_keys(textures)
    return _Plan(
        color^,
        metallic^,
        roughness^,
        blend,
        alpha_mode,
        cutoff,
        double_sided,
        extras,
        _tail(parent),
        textures^,
        report^,
    )


def _by_name(name: String) raises -> Tuple[List[_Num], _Num, _Num, Bool]:
    """Return the name-only factors."""
    var low = _lower(name)
    if _has(low, "glass") or _has(low, "window"):
        return (_glass_color(), _float("0.0"), _float("0.05"), True)
    if _has(low, "rubber") or _has(low, "tire") or _has(low, "tyre"):
        return (
            _row("0.03", "0.03", "0.03", True),
            _float("0.0"),
            _float("0.9"),
            False,
        )
    if _has(low, "chrome") or _has(low, "polished"):
        return (
            _row("0.9", "0.9", "0.9", True),
            _float("1.0"),
            _float("0.15"),
            False,
        )
    if _has(low, "alumin") or _has(low, "metal"):
        return (
            _row("0.6", "0.6", "0.62", True),
            _float("1.0"),
            _float("0.35"),
            False,
        )
    if _has(low, "black"):
        return (
            _row("0.02", "0.02", "0.02", True),
            _float("0.0"),
            _float("0.6"),
            False,
        )
    if _has(low, "grey") or _has(low, "gray"):
        return (
            _row("0.25", "0.25", "0.25", True),
            _float("0.0"),
            _float("0.6"),
            False,
        )
    if _has(low, "light"):
        return (
            _row("0.9", "0.9", "0.85", True),
            _float("0.0"),
            _float("0.2"),
            False,
        )
    return (
        _row("0.5", "0.5", "0.5", True),
        _float("0.0"),
        _float("0.6"),
        False,
    )


def _glass_color() raises -> List[_Num]:
    """Return the glass base color."""
    return _row("0.08", "0.1", "0.12", False)


def _row(
    red: String, green: String, blue: String, whole: Bool
) raises -> List[_Num]:
    """Return one base color. `whole` makes the alpha an int 1."""
    var color = List[_Num]()
    color.append(_float(red))
    color.append(_float(green))
    color.append(_float(blue))
    if whole:
        color.append(_Num(Float64(1), True))
    else:
        color.append(_float("0.35"))
    return color^


def _white(alpha: _Num) -> List[_Num]:
    """Return `[1, 1, 1, alpha]`."""
    var color = List[_Num]()
    color.append(_Num(Float64(1), True))
    color.append(_Num(Float64(1), True))
    color.append(_Num(Float64(1), True))
    color.append(alpha.copy())
    return color^


def _ones() -> List[_Num]:
    """Return four integer ones."""
    var color = List[_Num]()
    for _ in range(4):
        color.append(_Num(Float64(1), True))
    return color^


def _float(text: String) raises -> _Num:
    """Return a decimal as a JSON float."""
    return _Num(parse_float(text), False)


def _clamp(text: String) raises -> _Num:
    """Return `text` clamped to 0 through 1."""
    var value = parse_float(text)
    if value < 0:
        value = 0
    if value > 1:
        value = 1
    return _Num(value, False)


def _rgba(text: String) raises -> List[_Num]:
    """Return R, G, B and a float 1 from a stored vector."""
    var parts = _split(text, " ")
    var color = List[_Num]()
    color.append(_float(parts[0]))
    color.append(_float(parts[1]))
    color.append(_float(parts[2]))
    color.append(_float("1.0"))
    return color^


def _read_mat(text: String) -> List[String]:
    """Return mat keys and values, with others under an empty key."""
    var rows = List[String]()
    var others = String("")
    var lines = _lines(text)
    for index in range(len(lines)):
        var line = _strip(lines[index])
        var at = _find(line, "=")
        if at < 0:
            continue
        var key = String(line[byte=0:at])
        var value = String(line[byte = at + 1 :])
        if _starts(key, "Other"):
            if others.byte_length() > 0:
                others += "\n"
            others += value
        else:
            rows.append(key + "\n" + value)
    rows.append("\n" + others)
    return rows^


def _field(entries: List[String], key: String) -> String:
    """Return one mat value, or empty when the key is absent."""
    for index in range(len(entries)):
        var row = entries[index]
        var at = _find(row, "\n")
        if String(row[byte=0:at]) == key:
            return String(row[byte = at + 1 :])
    return ""


def _others(entries: List[String]) -> List[String]:
    """Return the Other values in file order."""
    var last = entries[len(entries) - 1]
    var body = String(last[byte=1:])
    return _lines(body)


def _other(entries: List[String], mask: Bool) -> String:
    """Return the first Other value whose name selects a color."""
    var rows = _others(entries)
    for index in range(len(rows)):
        if rows[index].byte_length() == 0:
            continue
        var low = _lower(rows[index])
        var selected = _has(low, "basecolor")
        if mask:
            selected = selected or _has(low, "front") or _has(low, "color")
        else:
            selected = selected or _has(low, "diffuse") or _has(low, "albedo")
        if selected:
            return rows[index]
    return ""


def _orm(entries: List[String]) -> String:
    """Return the first ORM stem, including a Specular value."""
    var rows = _others(entries)
    var specular = _field(entries, "Specular")
    rows.append(specular)
    for index in range(len(rows)):
        if _ends(_lower(rows[index]), "_orm"):
            return rows[index]
    return ""


def _read_props(
    text: String,
) raises -> Tuple[String, List[String], List[String], Bool, Bool]:
    """Return the parent, vectors, scalars, and blend flags."""
    var parent = String("")
    var lines = _lines(text)
    for index in range(len(lines)):
        var line = _strip(lines[index])
        if not _starts(line, "Parent = "):
            continue
        var rest = String(line[byte=9:])
        var quote = _find(rest, "'")
        if quote < 0:
            continue
        var word = String(rest[byte=0:quote])
        if word.byte_length() == 0 or not _word(word):
            continue
        var tail = String(rest[byte = quote + 1 :])
        var end = _find(tail, "'")
        if end < 0:
            continue
        parent = String(tail[byte=0:end])
        break
    var vectors = List[String]()
    var scalars = List[String]()
    var at = 0
    var raw = text
    while at < raw.byte_length():
        var found = _find_from(raw, "Name=", at)
        if found < 0:
            break
        var name_at = found + 5
        var brace = _find_from(raw, " }", name_at)
        if brace < 0:
            break
        var name = String(raw[byte=name_at:brace])
        var cursor = brace + 2
        cursor = _skip(raw, cursor)
        if _starts_at(raw, cursor, "ParameterValue = {"):
            var rgba = _vector_body(raw, cursor + 19)
            if rgba.byte_length() > 0:
                vectors.append(name + "\n" + rgba)
                at = cursor + 19
                continue
        if _starts_at(raw, cursor, "ParameterValue = "):
            var number = _scalar_body(raw, cursor + 17)
            if number.byte_length() > 0:
                scalars.append(name + "\n" + number)
                at = cursor + 17
                continue
        at = found + 5
    return (
        parent,
        vectors^,
        scalars^,
        _has(text, "BlendMode = BLEND_Translucent"),
        _has(text, "BlendMode = BLEND_Masked"),
    )


def _vector(rows: List[String], key: String) -> String:
    """Return `R G B A` for a named vector, or empty."""
    for index in range(len(rows)):
        var at = _find(rows[index], "\n")
        if String(rows[index][byte=0:at]) == key:
            return String(rows[index][byte = at + 1 :])
    return ""


def _scalar(rows: List[String], key: String) -> String:
    """Return one scalar text, or empty."""
    return _vector(rows, key)


def _vector_body(text: String, at: Int) -> String:
    """Return R G B A when the vector pattern matches."""
    if not _starts_at(text, at, "R="):
        return ""
    var red = _number(text, at + 2)
    if red.byte_length() == 0 or not _starts_at(
        text, at + 2 + red.byte_length(), ", G="
    ):
        return ""
    var green_at = at + 2 + red.byte_length() + 4
    var green = _number(text, green_at)
    if green.byte_length() == 0 or not _starts_at(
        text, green_at + green.byte_length(), ", B="
    ):
        return ""
    var blue_at = green_at + green.byte_length() + 4
    var blue = _number(text, blue_at)
    if blue.byte_length() == 0 or not _starts_at(
        text, blue_at + blue.byte_length(), ", A="
    ):
        return ""
    var alpha_at = blue_at + blue.byte_length() + 4
    var alpha = _number(text, alpha_at)
    if alpha.byte_length() == 0 or not _starts_at(
        text, alpha_at + alpha.byte_length(), " }"
    ):
        return ""
    return red + " " + green + " " + blue + " " + alpha


def _scalar_body(text: String, at: Int) -> String:
    """Return a scalar when whitespace follows it."""
    var number = _number(text, at)
    if number.byte_length() == 0:
        return ""
    var next = at + number.byte_length()
    if next >= text.byte_length():
        return number
    var byte = text.as_bytes()[next]
    if byte == 32 or byte == 9 or byte == 10 or byte == 13:
        return number
    return ""


def _number(text: String, at: Int) -> String:
    """Return one numeric token, or empty."""
    var raw = text.as_bytes()
    var end = at
    while end < len(raw):
        var byte = raw[end]
        var ok = (
            byte == 45
            or byte == 46
            or byte == 101
            or (byte >= 48 and byte <= 57)
        )
        if not ok:
            break
        end += 1
    if end == at:
        return ""
    return String(text[byte=at:end])


def _report_keys(textures: List[String]) -> List[String]:
    """Return the report's texture names in the Python sort order."""
    var pbr = List[String]()
    var material = List[String]()
    for index in range(len(textures)):
        var step = textures[index]
        if _starts(step, "color ") or _starts(step, "masked "):
            _add(pbr, "baseColorTexture")
        elif _starts(step, "normal "):
            _add(material, "normalTexture")
        elif _starts(step, "orm "):
            _add(pbr, "metallicRoughnessTexture")
            _add(material, "occlusionTexture")
    _sort(pbr)
    _sort(material)
    for index in range(len(material)):
        pbr.append(material[index])
    return pbr^


def _encode(plan: _Plan) raises -> String:
    """Return the decision JSON."""
    var doc = PyJson()
    var root = doc.new_dict()
    doc.root = root
    var color = doc.new_list()
    for index in range(4):
        doc.append(color, _node(doc, plan.color[index]))
    doc.set(root, "baseColorFactor", color)
    doc.set(root, "metallicFactor", _node(doc, plan.metallic))
    doc.set(root, "roughnessFactor", _node(doc, plan.roughness))
    if plan.alpha_mode.byte_length() > 0:
        doc.set(root, "alphaMode", doc.new_str(plan.alpha_mode))
    if plan.cutoff:
        doc.set(root, "alphaCutoff", doc.new_float(parse_float("0.3333")))
    if plan.double_sided:
        doc.set(root, "doubleSided", doc.new_bool(True))
    if plan.extras.byte_length() > 0:
        var extras = doc.new_dict()
        doc.set(extras, "carla", doc.new_str(plan.extras))
        doc.set(root, "extras", extras)
    var steps = doc.new_list()
    for index in range(len(plan.textures)):
        doc.append(steps, _step(doc, plan.textures[index]))
    doc.set(root, "textures", steps)
    var report = doc.new_list()
    doc.append(report, doc.new_str(plan.parent))
    var keys = doc.new_list()
    for index in range(len(plan.report)):
        doc.append(keys, doc.new_str(plan.report[index]))
    doc.append(report, keys)
    doc.set(root, "report", report)
    return _dumps(doc)


def _step(mut doc: PyJson, text: String) raises -> Int:
    """Return one texture step object."""
    var step = doc.new_dict()
    if _starts(text, "color "):
        doc.set(step, "kind", doc.new_str("color"))
        doc.set(step, "stem", doc.new_str(String(text[byte=6:])))
    elif _starts(text, "normal "):
        doc.set(step, "kind", doc.new_str("normal"))
        doc.set(step, "stem", doc.new_str(String(text[byte=7:])))
    elif _starts(text, "orm "):
        doc.set(step, "kind", doc.new_str("orm"))
        doc.set(step, "stem", doc.new_str(String(text[byte=4:])))
    else:
        var body = String(text[byte=7:])
        var at = _find(body, "\n")
        doc.set(step, "kind", doc.new_str("masked"))
        doc.set(step, "color", doc.new_str(String(body[byte=0:at])))
        doc.set(step, "mask", doc.new_str(String(body[byte = at + 1 :])))
    return step


def _node(mut doc: PyJson, number: _Num) raises -> Int:
    """Return a JSON int or float."""
    if number.integer:
        return doc.new_int(Int(number.value))
    return doc.new_float(number.value)


def _tail(text: String) -> String:
    """Return the text after the last slash."""
    var at = -1
    var raw = text.as_bytes()
    for index in range(len(raw)):
        if raw[index] == 47:
            at = index
    if at < 0:
        return text
    return String(text[byte = at + 1 :])


def _listed(pngs: List[String], stem: String) -> Bool:
    """Return whether `stem` is a known texture."""
    if stem.byte_length() == 0:
        return False
    for index in range(len(pngs)):
        if pngs[index] == stem:
            return True
    return False


def _add(mut keys: List[String], key: String):
    """Append `key` once."""
    for index in range(len(keys)):
        if keys[index] == key:
            return
    keys.append(key)


def _sort(mut keys: List[String]):
    """Sort ASCII strings."""
    for index in range(1, len(keys)):
        var value = keys[index]
        var place = index
        while place > 0 and keys[place - 1] > value:
            keys[place] = keys[place - 1]
            place -= 1
        keys[place] = value


def _lower(text: String) -> String:
    """Return `text` in ASCII lowercase."""
    var out = String()
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte >= 65 and byte <= 90:
            byte += 32
        out += chr(Int(byte))
    return out


def _has(text: String, needle: String) -> Bool:
    """Return whether `needle` occurs in `text`."""
    return _find(text, needle) >= 0


def _starts(text: String, prefix: String) -> Bool:
    """Return whether `text` begins with `prefix`."""
    return _starts_at(text, 0, prefix)


def _starts_at(text: String, at: Int, prefix: String) -> Bool:
    """Return whether `prefix` occurs at `at`."""
    var raw = text.as_bytes()
    var head = prefix.as_bytes()
    if at < 0 or at + len(head) > len(raw):
        return False
    for index in range(len(head)):
        if raw[at + index] != head[index]:
            return False
    return True


def _ends(text: String, suffix: String) -> Bool:
    """Return whether `text` ends with `suffix`."""
    var raw = text.as_bytes()
    var tail = suffix.as_bytes()
    if len(raw) < len(tail):
        return False
    return _starts_at(text, len(raw) - len(tail), suffix)


def _word(text: String) -> Bool:
    """Return whether `text` is a Python `\\w+` word."""
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        var ok = (
            (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or byte == 95
        )
        if not ok:
            return False
    return True


def _find(text: String, needle: String) -> Int:
    """Return the first index of `needle`, or -1."""
    return _find_from(text, needle, 0)


def _find_from(text: String, needle: String, start: Int) -> Int:
    """Return the next index of `needle` at or after `start`, or -1."""
    var raw = text.as_bytes()
    var head = needle.as_bytes()
    if len(head) == 0:
        return start
    var last = len(raw) - len(head)
    var index = start
    while index <= last:
        var same = True
        for offset in range(len(head)):
            if raw[index + offset] != head[offset]:
                same = False
                break
        if same:
            return index
        index += 1
    return -1


def _lines(text: String) -> List[String]:
    """Split `text` at newline characters."""
    var rows = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw)):
        if raw[index] == 10:
            rows.append(_strip(String(text[byte=start:index])))
            start = index + 1
    rows.append(_strip(String(text[byte=start:])))
    return rows^


def _split(text: String, separator: String) -> List[String]:
    """Split `text` on `separator`."""
    var rows = List[String]()
    var start = 0
    while True:
        var at = _find_from(text, separator, start)
        if at < 0:
            rows.append(String(text[byte=start:]))
            return rows^
        rows.append(String(text[byte=start:at]))
        start = at + separator.byte_length()


def _strip(text: String) -> String:
    """Remove ASCII spaces and carriage returns from both ends."""
    var raw = text.as_bytes()
    var first = 0
    var last = len(raw)
    while first < last:
        var byte = raw[first]
        if byte != 32 and byte != 9 and byte != 13:
            break
        first += 1
    while last > first:
        var byte = raw[last - 1]
        if byte != 32 and byte != 9 and byte != 13:
            break
        last -= 1
    return String(text[byte=first:last])


def _skip(text: String, at: Int) -> Int:
    """Skip ASCII whitespace."""
    var raw = text.as_bytes()
    var index = at
    while index < len(raw):
        var byte = raw[index]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            break
        index += 1
    return index


def _dumps(doc: PyJson) raises -> String:
    """Return JSON with Python's default separators and key order."""
    var out = List[UInt8]()
    _emit(doc, doc.root, out)
    return String(unsafe_from_utf8=Span(out))


def _emit(doc: PyJson, node: Int, mut out: List[UInt8]) raises:
    """Append one JSON value."""
    var kind = doc.kind(node)
    if kind == PY_DICT:
        out.append(0x7B)
        for index in range(doc.length(node)):
            if index > 0:
                _ascii(out, ", ")
            _quote(out, doc.key(node, index))
            _ascii(out, ": ")
            _emit(doc, doc.value(node, index), out)
        out.append(0x7D)
    elif kind == PY_LIST:
        out.append(0x5B)
        for index in range(doc.length(node)):
            if index > 0:
                _ascii(out, ", ")
            _emit(doc, doc.item(node, index), out)
        out.append(0x5D)
    elif kind == PY_STR:
        _quote(out, doc.text(node))
    elif kind == PY_BOOL:
        _ascii(out, "true" if doc.flag(node) else "false")
    elif kind == PY_NONE:
        _ascii(out, "null")
    else:
        _ascii(out, doc.text(node))


def _quote(mut out: List[UInt8], text: String):
    """Append a JSON string."""
    out.append(0x22)
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 0x22 or byte == 0x5C:
            out.append(0x5C)
            out.append(byte)
        elif byte < 0x20:
            _ascii(out, "\\u00")
            var hex = "0123456789abcdef"
            out.append(hex.as_bytes()[Int(byte >> 4)])
            out.append(hex.as_bytes()[Int(byte & 15)])
        else:
            out.append(byte)
    out.append(0x22)


def _ascii(mut out: List[UInt8], text: String):
    """Append raw ASCII."""
    var raw = text.as_bytes()
    for index in range(len(raw)):
        out.append(raw[index])


def main() raises:
    """Print the material decisions for the request file."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_gltf_material REQUEST.json", file=stderr)
        exit(2)
    try:
        print(plan_material(Path(arguments[1]).read_text()))
    except error:
        print("carla_gltf_material:", error, file=stderr)
        exit(1)
