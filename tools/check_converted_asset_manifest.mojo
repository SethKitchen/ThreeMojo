# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check converted assets; optionally fetch and reproduce production sources.

    mojo run -I . tools/check_converted_asset_manifest.mojo
    mojo run -I . tools/check_converted_asset_manifest.mojo --source-cache DIR
    mojo run -I . tools/check_converted_asset_manifest.mojo --source-cache DIR --fetch-sources

Run it from the repository root. The default check is offline and small: it
checks every pinned hash and regenerates three synthetic fixtures.
Production verification requires an explicit `--source-cache`. Downloads
also require `--fetch-sources`, and use `curl`. Accepted outputs and
existing cache files are never replaced.

The cache holds each source file at `DIR/<source id>/<revision>/<path>`.
Each file must match its pinned size, SHA-256 and git blob SHA-1.
"""

from std.collections import Set
from std.ffi import c_int, external_call
from std.os import listdir, makedirs, remove, rmdir
from std.os.path import exists, isdir, islink, realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    JsonNode,
    parse_json,
    quote_json,
)
from tools._json_tools import (
    equal,
    equals_text,
    equals_texts,
    json_tokens,
    truthy,
)
from tools._process import run_program
from tools._python_float import parse_float, python_repr
from tools._sha1 import git_blob_sha1
from tools._sha256 import sha256_hex
import tools.hair_style as hair_style
import tools.ict_face_model as ict_face_model

comptime MANIFEST = "assets/converted-asset-manifest.json"
"""The manifest, relative to the repository root."""
comptime MALFORMED = "Malformed converted asset manifest"
"""The error for a manifest of the wrong shape."""
comptime HAIR_CONVERTER = "tools/hair_style.mojo"
"""The converter of the two hairstyles."""
comptime FACE_CONVERTER = "tools/ict_face_model.mojo"
"""The converter of the face model."""
comptime SOURCE_LIMIT = 16 * 1024 * 1024
"""The largest source file the manifest can pin, in bytes."""
comptime FETCH_COMMAND: List[String] = [
    "curl",
    "--fail",
    "--silent",
    "--show-error",
    "--location",
    "--connect-timeout",
    "60",
    "--output",
]
"""The download command; the output file and the URL follow it."""


# --- the registries ------------------------------------------------------------


def production_paths() -> List[String]:
    """Return the production outputs the manifest must list.

    Returns:
        The face and the two hairstyles, by path.
    """
    return [
        "assets/face/ict_face.bin",
        "assets/hair/layered.bin",
        "assets/hair/mohawk.bin",
    ]


def production_binding(path: String) raises -> Tuple[String, String, String]:
    """Return a production output's converter, source and source input.

    Args:
        path: A production output's path.

    Returns:
        The converter, the source id and the input within the source.

    Raises:
        Error: `MALFORMED` for an unknown path.
    """
    if path == "assets/face/ict_face.bin":
        return (String(FACE_CONVERTER), String("ict"), String("FaceXModel"))
    if path == "assets/hair/layered.bin":
        return (
            String(HAIR_CONVERTER),
            String("sintel"),
            String("static/models/SintelHairOriginal-sintel_hair.16points.tfx"),
        )
    if path == "assets/hair/mohawk.bin":
        return (
            String(HAIR_CONVERTER),
            String("ratboy"),
            String("bin/Objects/HairAsset/Ratboy/Ratboy_mohawk.tfx"),
        )
    raise Error(MALFORMED)


def source_names() -> List[String]:
    """Return the source ids, in the manifest's order.

    Returns:
        The ids of the three source repositories.
    """
    return ["ict", "sintel", "ratboy"]


def repository(name: String) raises -> String:
    """Return the repository a source id names.

    Args:
        name: A source id.

    Returns:
        The repository's URL.

    Raises:
        Error: `MALFORMED` for an unknown id.
    """
    if name == "ict":
        return "https://github.com/USC-ICT/ICT-FaceKit"
    if name == "sintel":
        return "https://github.com/Scthe/frostbitten-hair-webgpu"
    if name == "ratboy":
        return "https://github.com/GPUOpen-Effects/TressFX"
    raise Error(MALFORMED)


def source_evidence(name: String) raises -> List[Tuple[String, String]]:
    """Return the license and context files a source must pin, in order.

    Args:
        name: A source id.

    Returns:
        Each file's path and role.

    Raises:
        Error: `MALFORMED` for an unknown id.
    """
    if name == "ict":
        return [
            (String("LICENSE"), String("license")),
            (String("README.md"), String("context")),
        ]
    if name == "sintel":
        return [(String("README.md"), String("context"))]
    if name == "ratboy":
        return [
            (String("license.txt"), String("license")),
            (String("README.md"), String("context")),
        ]
    raise Error(MALFORMED)


def sintel_license_urls() -> List[String]:
    """Return the evidence of Sintel's license beyond its repository.

    Returns:
        The URLs.
    """
    return [
        "https://blendswap.com/blend/2847",
        "https://durian.blender.org/about/",
        "https://creativecommons.org/licenses/by/3.0/",
    ]


def synthetic_names() -> List[String]:
    """Return the synthetic fixtures the manifest must list.

    Returns:
        Their names.
    """
    return ["small-face", "small-layered", "small-mohawk"]


def synthetic_binding(name: String) raises -> Tuple[String, String]:
    """Return a synthetic fixture's format and source.

    Args:
        name: A synthetic fixture's name.

    Returns:
        The format and the source path.

    Raises:
        Error: `MALFORMED` for an unknown name.
    """
    if name == "small-face":
        return (String("ICTF"), String("assets/converted-fixtures/face"))
    if name == "small-layered":
        return (
            String("THRS"),
            String("assets/converted-fixtures/layered.tfx.hex"),
        )
    if name == "small-mohawk":
        return (
            String("THRS"),
            String("assets/converted-fixtures/mohawk.tfx.hex"),
        )
    raise Error(MALFORMED)


def required_files() -> List[String]:
    """Return the files whose hashes the manifest must record.

    Returns:
        The production outputs, their converters and the synthetic inputs.
    """
    var files = production_paths()
    files.append(FACE_CONVERTER)
    files.append(HAIR_CONVERTER)
    for name in [
        "generic_neutral_mesh.obj",
        "identity000.obj",
        "jawOpen.obj",
        "still.obj",
    ]:
        files.append("assets/converted-fixtures/face/" + name)
    files.append("assets/converted-fixtures/layered.tfx.hex")
    files.append("assets/converted-fixtures/mohawk.tfx.hex")
    return files^


# --- JSON with Python's meanings -------------------------------------------------


def load_json(text: String) raises -> JsonDocument:
    """Read JSON text, with each number exactly as Python's `json` reads it.

    `loaders.json` rounds some decimals to a neighbor of the nearest
    double. Here every number is read again with `parse_float`, and keeps
    its text, so an integer stays apart from a float.

    Args:
        text: The JSON text.

    Returns:
        The document. A number node's `text` is its literal.

    Raises:
        Error: If the text is not JSON.
    """
    var document = parse_json(text)
    var numbers = List[String]()
    for token in json_tokens(text)[0]:
        var first = token.as_bytes()[0]
        if first == 45 or (first >= 48 and first <= 57):
            numbers.append(token)
    var k = 0
    for i in range(len(document.nodes)):
        if document.nodes[i].kind == NUMBER:
            document.nodes[i].number = parse_float(numbers[k])
            document.nodes[i].text = numbers[k]
            k += 1
    return document^


def dump_json(document: JsonDocument, node: Int) raises -> String:
    """Return a value as compact JSON text, each number as it was read.

    Args:
        document: The document.
        node: A node.

    Returns:
        The JSON text.

    Raises:
        Error: If `node` is not a node of `document`.
    """
    var kind = document.kind(node)
    if kind == OBJECT:
        var text = String("{")
        for i in range(document.length(node)):
            if i > 0:
                text += ", "
            var key = document.key(node, i)
            text += quote_json(key) + ": "
            text += dump_json(document, document.nodes[node].children[i])
        return text + "}"
    if kind == ARRAY:
        var text = String("[")
        for i in range(document.length(node)):
            if i > 0:
                text += ", "
            text += dump_json(document, document.at(node, i))
        return text + "]"
    if kind == STRING:
        return quote_json(document.string(node))
    if kind == NUMBER:
        var literal = document.nodes[node].text
        if literal.byte_length() > 0:
            return literal
        return python_repr(document.number(node))
    if kind == BOOLEAN:
        return "true" if document.boolean(node) else "false"
    return "null"


def _member(document: JsonDocument, node: Int, key: String) raises -> Int:
    """Return `node[key]`, or raise `MALFORMED` where Python raises
    `TypeError` or `KeyError`."""
    if document.kind(node) != OBJECT or not document.has(node, key):
        raise Error(MALFORMED)
    return document.get(node, key)


def _items(document: JsonDocument, node: Int) raises -> List[Int]:
    """Return the items a loop over `node` subscripts, or raise `MALFORMED`.

    An array gives its items. An empty object or string gives none. Any
    other value gives items that cannot be subscripted, or none at all.
    """
    var kind = document.kind(node)
    if kind == ARRAY:
        var found = List[Int]()
        for i in range(document.length(node)):
            found.append(document.at(node, i))
        return found^
    if (kind == OBJECT and document.length(node) == 0) or (
        kind == STRING and document.string(node).byte_length() == 0
    ):
        return List[Int]()
    raise Error(MALFORMED)


def _keys(document: JsonDocument, node: Int) raises -> List[String]:
    """Return an object's keys, or raise `MALFORMED` for `.items()` of any
    other value."""
    if document.kind(node) != OBJECT:
        raise Error(MALFORMED)
    var found = List[String]()
    for i in range(document.length(node)):
        found.append(document.key(node, i))
    return found^


def _hashable(document: JsonDocument, node: Int) raises -> String:
    """Return the set member a value is: a string's text, or a mark no
    string has. A container is unhashable: `MALFORMED`."""
    var kind = document.kind(node)
    if kind == STRING:
        return "s" + document.string(node)
    if kind == ARRAY or kind == OBJECT:
        raise Error(MALFORMED)
    return "n" + dump_json(document, node)


def _set(document: JsonDocument, node: Int) raises -> Set[String]:
    """Return `set(value)` as marks: an object's keys, an array's items or
    a string's characters."""
    var kind = document.kind(node)
    var found = Set[String]()
    if kind == OBJECT:
        for key in _keys(document, node):
            found.add("s" + key)
    elif kind == ARRAY:
        for i in range(document.length(node)):
            found.add(_hashable(document, document.at(node, i)))
    elif kind == STRING:
        for byte in document.string(node).as_bytes():
            found.add("s" + chr(Int(byte)))
    else:
        raise Error(MALFORMED)
    return found^


def _marks(names: List[String]) -> Set[String]:
    """Return a set of strings as marks."""
    var found = Set[String]()
    for name in names:
        found.add("s" + name)
    return found^


def _same(a: Set[String], b: Set[String]) -> Bool:
    """Return True when two sets are equal."""
    if len(a) != len(b):
        return False
    for item in a:
        if item not in b:
            return False
    return True


def _text(document: JsonDocument, node: Int) raises -> String:
    """Return a string, or raise `MALFORMED` where Python would join or
    subscript some other value."""
    if document.kind(node) != STRING:
        raise Error(MALFORMED)
    return document.string(node)


def _is_int(document: JsonDocument, node: Int) raises -> Bool:
    """Return True for a number Python's `json` reads as an `int`."""
    if document.kind(node) != NUMBER:
        return False
    var literal = document.nodes[node].text
    for byte in literal.as_bytes():
        if byte == 46 or byte == 101 or byte == 69:
            return False
    return True


def _positive(document: JsonDocument, node: Int) raises -> Bool:
    """Return True for a positive `int`, not a Boolean or a float."""
    return _is_int(document, node) and document.number(node) > 0


def _equals_number(
    document: JsonDocument, node: Int, value: Float64
) raises -> Bool:
    """Return `node == value` as Python compares a decoded value."""
    var kind = document.kind(node)
    if kind == NUMBER:
        return document.number(node) == value
    if kind == BOOLEAN:
        return (1.0 if document.boolean(node) else 0.0) == value
    return False


def _hex(document: JsonDocument, node: Int, length: Int) raises -> Bool:
    """Return True for a string of exactly `length` lowercase hex digits."""
    if document.kind(node) != STRING:
        return False
    var text = document.string(node)
    if text.byte_length() != length:
        return False
    for byte in text.as_bytes():
        if not ((byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 102)):
            return False
    return True


def _whole(document: JsonDocument, node: Int) raises -> Int:
    """Return an `int` or a Boolean as Python uses it as a count, or raise
    `MALFORMED`."""
    if document.kind(node) == BOOLEAN:
        return 1 if document.boolean(node) else 0
    if not _is_int(document, node):
        raise Error(MALFORMED)
    return Int(document.number(node))


def _require(condition: Bool, message: String) raises:
    """Raise `message` unless `condition` holds."""
    if not condition:
        raise Error(message)


def check_path(value: String) raises -> String:
    """Return a manifest path that is relative, normal and inside its root.

    Args:
        value: The path.

    Returns:
        The path.

    Raises:
        Error: For an empty, absolute or non-normal path, a backslash, or
            a `..` part.
    """
    var valid = value.byte_length() > 0 and not ("\\" in value)
    if valid:
        valid = not value.startswith("/")
        for part in value.split("/"):
            if part.byte_length() == 0 or part == "." or part == "..":
                valid = False
    _require(valid, "Invalid manifest path")
    return value


def _path_member(document: JsonDocument, node: Int) raises -> String:
    """Return a value checked as a manifest path."""
    var value = String()
    var valid = document.kind(node) == STRING
    if valid:
        value = document.string(node)
    _require(valid, "Invalid manifest path")
    return check_path(value)


def digest(path: String) raises -> String:
    """Return the SHA-256 of a local file.

    Args:
        path: The file.

    Returns:
        64 lowercase hex digits.

    Raises:
        Error: If the file cannot be read.
    """
    return sha256_hex(Span(Path(path).read_bytes()))


def _file_size(path: String) raises -> Int:
    """Return a file's size in bytes."""
    return len(Path(path).read_bytes())


def _join(base: String, relative: String) -> String:
    """Join paths as `pathlib` does: an absolute part replaces the base."""
    if relative.startswith("/"):
        return relative
    if base.byte_length() == 0 or base.endswith("/"):
        return base + relative
    return base + "/" + relative


def _parameters_text(source_id: String) -> String:
    """Return the complete recipe a production entry must record, as JSON."""
    if source_id == "ict":
        return (
            '{"identities": 60, "skin_end": 11248, "coarse_target": 6000,'
            + ' "to_meters": '
            + _repr(ict_face_model.TO_METERS)
            + ', "still_meters": '
            + _repr(ict_face_model.STILL)
            + "}"
        )
    var style = "layered" if source_id == "sintel" else "mohawk"
    var text = (
        '{"style": "'
        + style
        + '", "points": '
        + String(hair_style.POINTS)
        + ', "summation": "left-to-right-binary64"'
    )
    if style == "mohawk":
        text += ', "mohawk_from_degrees": ' + _repr(hair_style.MOHAWK_FROM)
        text += ', "mohawk_to_degrees": ' + _repr(hair_style.MOHAWK_TO)
        text += ', "scalp_from_degrees": ' + _repr(hair_style.SCALP_FROM)
        text += ', "scalp_to_degrees": ' + _repr(hair_style.SCALP_TO)
        text += ', "mohawk_head": ' + _repr(hair_style.MOHAWK_HEAD)
        text += ', "mohawk_narrow": ' + _repr(hair_style.MOHAWK_NARROW)
        text += ', "mohawk_reach": ' + _repr(hair_style.MOHAWK_REACH)
        text += (
            ', "human_radii": ['
            + _repr(hair_style.HUMAN_ACROSS)
            + ", "
            + _repr(hair_style.HUMAN_UP)
            + ", "
            + _repr(hair_style.HUMAN_ALONG)
            + "]"
        )
    return text + "}"


def _repr(value: Float64) -> String:
    """Return `repr` of a float constant."""
    try:
        return python_repr(value)
    except:
        return String(value)


# --- validation ------------------------------------------------------------------


def validate(data: JsonDocument, root: String) raises:
    """Validate the manifest structure, source bindings and recorded local
    bytes.

    Args:
        data: The manifest.
        root: The repository root.

    Raises:
        Error: The first problem found. A manifest of the wrong shape gives
            `MALFORMED`.
    """
    var top = data.root()
    _require(
        _equals_number(data, _member(data, top, "schema_version"), 2),
        "Unsupported converted asset manifest schema",
    )
    _require(
        equals_text(
            data,
            _member(data, top, "status"),
            "production-regeneration-verified",
        ),
        "Unverified production status",
    )
    var production = List[Int]()
    for e in _items(data, _member(data, top, "production_assets")):
        production.append(_member(data, e, "path"))
    var synthetic = List[Int]()
    for e in _items(data, _member(data, top, "synthetic_regeneration")):
        synthetic.append(_member(data, e, "name"))
    var registered = len(production) == 3
    if registered:
        var found = Set[String]()
        for node in production:
            found.add(_hashable(data, node))
        registered = _same(found, _marks(production_paths()))
    _require(
        registered,
        "The production asset registry must contain all three assets",
    )
    registered = len(synthetic) == 3
    if registered:
        var found = Set[String]()
        for node in synthetic:
            found.add(_hashable(data, node))
        registered = _same(found, _marks(synthetic_names()))
    _require(
        registered, "The synthetic registry must contain all three fixtures"
    )
    var files = _member(data, top, "files")
    var recorded = _set(data, files)
    var complete = True
    for path in required_files():
        if ("s" + path) not in recorded:
            complete = False
    _require(
        complete,
        "All production, converter and synthetic inputs need recorded hashes",
    )
    for path in _keys(data, files):
        _ = check_path(path)
        var expected = data.get(files, path)
        _require(_hex(data, expected, 64), "Invalid local SHA-256")
        _require(
            digest(_join(root, path)) == data.string(expected),
            "Converted asset manifest hash mismatch: " + path,
        )
    var sources = _member(data, top, "sources")
    _require(
        _same(_set(data, sources), _marks(source_names())),
        "Invalid source registry",
    )
    for name in _keys(data, sources):
        var source = data.get(sources, name)
        _require(
            equals_text(
                data, _member(data, source, "repository"), repository(name)
            ),
            "Source repository binding mismatch",
        )
        _require(
            _hex(data, _member(data, source, "revision"), 40),
            "Source revision must be an immutable commit",
        )
        var listed = _member(data, source, "files")
        _require(truthy(data, listed), "Missing source files")
        var entries = _items(data, listed)
        var paths = Set[String]()
        for entry in entries:
            paths.add(_path_member(data, _member(data, entry, "path")))
            var size = _member(data, entry, "size_bytes")
            _require(
                _positive(data, size)
                and data.number(size) <= Float64(SOURCE_LIMIT),
                "Invalid source size",
            )
            _require(
                _hex(data, _member(data, entry, "sha256"), 64)
                and _hex(data, _member(data, entry, "git_blob_sha1"), 40),
                "Invalid source checksum",
            )
            var role = _member(data, entry, "role")
            _require(
                equals_text(data, role, "input")
                or equals_text(data, role, "license")
                or equals_text(data, role, "context"),
                "Invalid source role",
            )
        _require(len(paths) == len(entries), "Duplicate source file")
        # The license and context files, by path, the last role winning.
        var evidence_paths = List[String]()
        var evidence_roles = List[Int]()
        var inputs = Set[String]()
        for entry in entries:
            var role = data.get(entry, "role")
            var path = data.string(data.get(entry, "path"))
            if equals_text(data, role, "input"):
                inputs.add(path)
                continue
            var at = -1
            for i in range(len(evidence_paths)):
                if evidence_paths[i] == path:
                    at = i
            if at < 0:
                evidence_paths.append(path)
                evidence_roles.append(role)
            else:
                evidence_roles[at] = role
        var wanted = source_evidence(name)
        var matched = len(wanted) == len(evidence_paths)
        for pair in wanted:
            var at = -1
            for i in range(len(evidence_paths)):
                if evidence_paths[i] == pair[0]:
                    at = i
            if at < 0 or not equals_text(data, evidence_roles[at], pair[1]):
                matched = False
        _require(matched, "Missing source license/context evidence")
        if name == "ict":
            var valid = len(inputs) == 118 and (
                "FaceXModel/generic_neutral_mesh.obj" in inputs
            )
            for i in range(60):
                var label = String(i)
                while label.byte_length() < 3:
                    label = "0" + label
                if ("FaceXModel/identity" + label + ".obj") not in inputs:
                    valid = False
            for path in inputs:
                if not (
                    path.startswith("FaceXModel/")
                    and path.count("/") == 1
                    and path.endswith(".obj")
                ):
                    valid = False
            _require(valid, "Invalid ICT input set")
            var expressions = True
            for path in inputs:
                if (
                    path == "FaceXModel/generic_neutral_mesh.obj"
                    or _is_identity(path)
                ):
                    continue
                var file = String(path[byte = path.rfind("/") + 1 :])
                if file.startswith("identity") or file.startswith("generic"):
                    expressions = False
            _require(expressions, "Invalid ICT expression set")
        else:
            var output = (
                "assets/hair/"
                + ("layered" if name == "sintel" else "mohawk")
                + ".bin"
            )
            var expected = production_binding(output)[2]
            _require(
                len(inputs) == 1 and expected in inputs,
                "Hair input binding mismatch",
            )
    for entry in _items(data, _member(data, top, "production_assets")):
        var path = _text(data, data.get(entry, "path"))
        var binding = production_binding(path)
        _require(
            equals_text(data, _member(data, entry, "converter"), binding[0]),
            "Production converter binding mismatch",
        )
        var source = _member(data, entry, "source")
        var bound = (
            data.kind(source) == OBJECT
            and data.length(source) == 2
            and data.has(source, "id")
            and data.has(source, "input")
            and equals_text(data, data.get(source, "id"), binding[1])
            and equals_text(data, data.get(source, "input"), binding[2])
        )
        _require(bound, "Production source binding mismatch")
        var expected = load_json(_parameters_text(binding[1]))
        _require(
            equal(
                data,
                _member(data, entry, "parameters"),
                expected,
                expected.root(),
            ),
            "Production parameter mismatch",
        )
        var version = (
            ict_face_model.VERSION if binding[1]
            == "ict" else hair_style.VERSION
        )
        _require(
            _equals_number(
                data, _member(data, entry, "format_version"), Float64(version)
            ),
            "Production format version mismatch",
        )
        var verified = _member(data, entry, "regeneration_verified")
        _require(
            data.kind(verified) == BOOLEAN and data.boolean(verified),
            "Unverified production regeneration",
        )
        var size = _member(data, entry, "output_size_bytes")
        var sized = _positive(data, size)
        if sized:
            sized = Float64(_file_size(_join(root, path))) == data.number(size)
        _require(sized, "Production output size mismatch")
        var license = _member(data, entry, "license")
        _require(
            equals_text(
                data,
                _member(data, license, "spdx"),
                "CC-BY-3.0" if binding[1] == "sintel" else "MIT",
            ),
            "Production license mismatch",
        )
        var pinned = _member(data, sources, binding[1])
        var source_files = List[String]()
        for pair in source_evidence(binding[1]):
            source_files.append(pair[0])
        var urls = List[String]()
        for file in source_files:
            urls.append(
                _text(data, _member(data, pinned, "repository"))
                + "/blob/"
                + _text(data, _member(data, pinned, "revision"))
                + "/"
                + file
            )
        if binding[1] == "sintel":
            urls.extend(sintel_license_urls())
        var evidenced = equals_texts(
            data, _member(data, license, "source_files"), source_files
        )
        if evidenced:
            evidenced = equals_texts(
                data, _member(data, license, "evidence_urls"), urls
            )
        if evidenced:
            evidenced = equals_text(
                data, _member(data, license, "notice"), "THIRD-PARTY-NOTICES.md"
            )
        _require(evidenced, "Missing license evidence")
    for entry in _items(data, _member(data, top, "synthetic_regeneration")):
        var binding = synthetic_binding(_text(data, data.get(entry, "name")))
        var format = _member(data, entry, "format")
        var source = _member(data, entry, "source")
        _require(
            equals_text(data, format, binding[0])
            and equals_text(data, source, binding[1]),
            "Synthetic format or source binding mismatch",
        )
        _require(
            _hex(data, _member(data, entry, "output_sha256"), 64)
            and _positive(data, _member(data, entry, "output_size_bytes")),
            "Invalid synthetic output pin",
        )


def _is_identity(path: String) -> Bool:
    """Return True for `FaceXModel/identityNNN.obj` with NNN below 60."""
    for i in range(60):
        var label = String(i)
        while label.byte_length() < 3:
            label = "0" + label
        if path == "FaceXModel/identity" + label + ".obj":
            return True
    return False


# --- sources ---------------------------------------------------------------------


def from_hex(text: String) raises -> List[UInt8]:
    """Return bytes from hex digits, as `bytes.fromhex` reads them.

    Args:
        text: Pairs of hex digits, with whitespace allowed between pairs.

    Returns:
        The bytes.

    Raises:
        Error: For any other character, or a pair cut by whitespace.
    """
    var out = List[UInt8]()
    var bytes = text.as_bytes()
    var i = 0
    while i < len(bytes):
        var byte = bytes[i]
        if byte == 32 or (byte >= 9 and byte <= 13):
            i += 1
            continue
        if i + 1 >= len(bytes):
            raise Error(
                "non-hexadecimal number found in fromhex() arg at position "
                + String(i + 1)
            )
        var high = _nibble(bytes[i], i)
        var low = _nibble(bytes[i + 1], i + 1)
        out.append(UInt8(high * 16 + low))
        i += 2
    return out^


def _nibble(byte: UInt8, at: Int) raises -> Int:
    """Return one hex digit's value."""
    if byte >= 48 and byte <= 57:
        return Int(byte) - 48
    if byte >= 97 and byte <= 102:
        return Int(byte) - 87
    if byte >= 65 and byte <= 70:
        return Int(byte) - 55
    raise Error(
        "non-hexadecimal number found in fromhex() arg at position "
        + String(at)
    )


def check_source_bytes(
    content: List[UInt8], data: JsonDocument, entry: Int
) raises:
    """Refuse changed, truncated or wrong-revision source bytes.

    Args:
        content: The bytes read, at most one past the pinned size.
        data: The manifest.
        entry: The source file's entry.

    Raises:
        Error: If the size, the SHA-256 or the git blob SHA-1 differs.
    """
    var path = _text(data, _member(data, entry, "path"))
    var size = _member(data, entry, "size_bytes")
    var matched = _equals_number(data, size, Float64(len(content)))
    if matched:
        matched = equals_text(
            data, _member(data, entry, "sha256"), sha256_hex(Span(content))
        )
    if matched:
        matched = equals_text(
            data,
            _member(data, entry, "git_blob_sha1"),
            git_blob_sha1(Span(content)),
        )
    _require(matched, "Source checksum or size mismatch: " + path)


def _absolute(path: String) raises -> String:
    """Return a path from the root of the file system."""
    if path.startswith("/"):
        return path
    return realpath(".") + "/" + path


def resolve(path: String) raises -> String:
    """Return a path with each existing symbolic link followed, as
    `Path.resolve()` does; missing parts are kept as written.

    Args:
        path: The path.

    Returns:
        The absolute, resolved path.

    Raises:
        Error: If the working directory cannot be read.
    """
    var resolved = String("")
    for part in _absolute(path).split("/"):
        if part.byte_length() == 0 or part == ".":
            continue
        if part == "..":
            var slash = resolved.rfind("/")
            var parent = String(resolved[byte = : max(slash, 0)])
            resolved = parent
            continue
        var candidate = resolved + "/" + part
        if exists(candidate):
            resolved = realpath(candidate)
        else:
            resolved = candidate
    if resolved.byte_length() == 0:
        return "/"
    return resolved


def _inside(path: String, base: String) -> Bool:
    """Return True when a resolved path is `base` or lies under it."""
    return path == base or path.startswith(
        base if base.endswith("/") else base + "/"
    )


def _read_at_most(path: String, limit: Int) raises -> List[UInt8]:
    """Return at most `limit` bytes from the start of a file."""
    var data = Path(path).read_bytes()
    if len(data) > limit:
        data.resize(limit, 0)
    return data^


def remove_tree(path: String) raises:
    """Remove a directory and everything in it; a link is removed, not
    followed.

    Args:
        path: The directory.

    Raises:
        Error: If something cannot be removed.
    """
    for name in listdir(path):
        var child = path + "/" + name
        if isdir(child) and not islink(child):
            remove_tree(child)
        else:
            remove(child)
    rmdir(path)


def _parent(path: String) -> String:
    """Return the directory part of a path."""
    var slash = path.rfind("/")
    if slash <= 0:
        return "/" if slash == 0 else "."
    return String(path[byte=:slash])


def _download(
    url: String, limit: Int, command: List[String]
) raises -> List[UInt8]:
    """Return at most `limit` bytes of a URL, or raise the command's error."""
    var scratch = mkdtemp(prefix="converted-asset-fetch-")
    try:
        var output = scratch + "/download"
        var arguments = command.copy()
        arguments.append(output)
        arguments.append(url)
        var result = run_program(arguments, 600)
        if result.status != 0 or not exists(output):
            raise Error("Cannot download " + url + ": " + result.output)
        return _read_at_most(output, limit)
    finally:
        remove_tree(scratch)


def _create_exclusive(path: String, content: List[UInt8]) raises:
    """Create a file that does not exist yet; never replace one that does.

    The bytes go to a temporary file beside it, which is then hard-linked
    to the name: a link never replaces an existing name.
    """
    var temporary = (
        _parent(path)
        + "/.partial-"
        + String(external_call["getpid", c_int]())
        + "-"
        + path[byte = path.rfind("/") + 1 :]
    )
    Path(temporary).write_bytes(Span(content))
    var source = temporary
    var target = path
    _ = external_call["link", c_int](
        source.as_c_string_span().ptr(), target.as_c_string_span().ptr()
    )
    remove(temporary)


def materialize_sources(
    data: JsonDocument,
    cache: String,
    destination: String,
    fetch: Bool = False,
    fetch_command: List[String] = materialize[FETCH_COMMAND](),
) raises:
    """Check the explicit cache and stage exactly the pinned inputs.

    Fetch only missing files when requested. Never repair altered cache
    files. Each staged file is the same byte string that passed both
    checksum checks.

    Args:
        data: The manifest, or at least its `sources`.
        cache: The cache directory.
        destination: Where the inputs are staged, by source id.
        fetch: True to download missing files into the cache.
        fetch_command: The download command; the output file and the URL
            are added to it.

    Raises:
        Error: For a path that escapes the cache, a missing file without
            `fetch`, a failed download, or bytes that do not match their
            pins.
    """
    var sources = _member(data, data.root(), "sources")
    var cache_root = resolve(cache)
    for name in _keys(data, sources):
        var source = data.get(sources, name)
        var base = _join(
            _join(cache, name), _text(data, _member(data, source, "revision"))
        )
        for entry in _items(data, _member(data, source, "files")):
            var relative = _text(data, _member(data, entry, "path"))
            var path = _join(base, relative)
            _require(
                _inside(resolve(path), cache_root), "Source path escapes cache"
            )
            var size = _whole(data, _member(data, entry, "size_bytes"))
            if not exists(path):
                _require(
                    fetch,
                    "Missing pinned source: "
                    + path
                    + "; use --fetch-sources with this explicit cache to"
                    + " download it",
                )
                var repository = _text(
                    data, _member(data, source, "repository")
                )
                var marker = repository.find("github.com/")
                if marker < 0:
                    raise Error("list index out of range")
                var url = (
                    "https://raw.githubusercontent.com/"
                    + String(
                        repository[byte = marker + 11 :].split("github.com/")[0]
                    )
                    + "/"
                    + _text(data, _member(data, source, "revision"))
                    + "/"
                    + relative
                )
                var content = _download(url, size + 1, fetch_command)
                check_source_bytes(content, data, entry)
                makedirs(_parent(path), exist_ok=True)
                # Exclusive creation never replaces an existing cache file.
                _create_exclusive(path, content)
            var content = _read_at_most(path, size + 1)
            check_source_bytes(content, data, entry)
            if equals_text(data, data.get(entry, "role"), "input"):
                var staged = _join(_join(destination, name), relative)
                makedirs(_parent(staged), exist_ok=True)
                Path(staged).write_bytes(Span(content))


def _convert_face(
    data: JsonDocument, parameters: Int, source: String, target: String
) raises:
    """Run the face converter with a manifest entry's parameters."""
    var identities = ict_face_model.IDENTITIES
    var skin_end = ict_face_model.SKIN_END
    var coarse_target = ict_face_model.COARSE_TRIANGLES
    for key in _keys(data, parameters):
        var value = _whole(data, data.get(parameters, key))
        if key == "identities":
            identities = value
        elif key == "skin_end":
            skin_end = value
        elif key == "coarse_target":
            coarse_target = value
        else:
            raise Error(MALFORMED)
    _ = ict_face_model.convert(
        source, target, identities, skin_end, coarse_target
    )


def _style(data: JsonDocument, parameters: Int) raises -> String:
    """Return a hair entry's style; a style that is not text is no style."""
    var style = _member(data, parameters, "style")
    if data.kind(style) != STRING:
        return String()
    return data.string(style)


def regenerate_production(
    data: JsonDocument, sources: String, destination: String
) raises:
    """Reproduce all production files in scratch and compare accepted
    hashes.

    Args:
        data: The manifest.
        sources: The staged inputs, by source id.
        destination: The scratch directory for the outputs.

    Raises:
        Error: If a conversion fails or an output differs from its pin.
    """
    var top = data.root()
    for entry in _items(data, _member(data, top, "production_assets")):
        var bound = _member(data, entry, "source")
        var source_id = _text(data, _member(data, bound, "id"))
        var source = _join(
            _join(sources, source_id),
            _text(data, _member(data, bound, "input")),
        )
        var path = _text(data, _member(data, entry, "path"))
        var target = _join(
            destination, String(path[byte = path.rfind("/") + 1 :])
        )
        var parameters = _member(data, entry, "parameters")
        if source_id == "ict":
            _ = ict_face_model.convert(
                source,
                target,
                _whole(data, _member(data, parameters, "identities")),
                _whole(data, _member(data, parameters, "skin_end")),
                _whole(data, _member(data, parameters, "coarse_target")),
            )
        else:
            _ = hair_style.convert(_style(data, parameters), source, target)
        var size = _member(data, entry, "output_size_bytes")
        var matched = _equals_number(data, size, Float64(_file_size(target)))
        if matched:
            matched = equals_text(
                data,
                _member(data, _member(data, top, "files"), path),
                digest(target),
            )
        _require(matched, "Production regeneration mismatch: " + path)


def verify(
    root: String = ".",
    manifest: String = "",
    require_source_pins: Bool = False,
    source_cache: String = "",
    fetch_sources: Bool = False,
    fetch_command: List[String] = materialize[FETCH_COMMAND](),
) raises:
    """Check pins and synthetic outputs; reproduce production only with a
    cache.

    The compatibility `require_source_pins` option checks metadata, which
    is also checked by default. It does not imply that the production
    sources were available or converted today.

    Args:
        root: The repository root.
        manifest: The manifest, or empty for the repository's.
        require_source_pins: Accepted for compatibility.
        source_cache: The source cache, or empty to skip production.
        fetch_sources: True to download missing sources into the cache.
        fetch_command: The download command.

    Raises:
        Error: The first problem found.
    """
    _ = require_source_pins
    _require(
        not fetch_sources or source_cache.byte_length() > 0,
        "--fetch-sources requires an explicit --source-cache",
    )
    var path = manifest if manifest.byte_length() > 0 else _join(root, MANIFEST)
    var data = load_json(Path(path).read_text())
    validate(data, root)
    var folder = mkdtemp(prefix="converted-asset-check-")
    try:
        var top = data.root()
        for entry in _items(data, _member(data, top, "synthetic_regeneration")):
            var target = folder + "/out.bin"
            var source = _join(
                root, _text(data, _member(data, entry, "source"))
            )
            var parameters = _member(data, entry, "parameters")
            if equals_text(data, _member(data, entry, "format"), "ICTF"):
                _convert_face(data, parameters, source, target)
            else:
                var decoded = folder + "/source.tfx"
                Path(decoded).write_bytes(
                    Span(from_hex(Path(source).read_text()))
                )
                _require(
                    equals_text(
                        data,
                        _member(data, entry, "decoded_input_sha256"),
                        digest(decoded),
                    ),
                    "Decoded synthetic source hash mismatch",
                )
                _ = hair_style.convert(
                    _style(data, parameters), decoded, target
                )
            var matched = equals_text(
                data, _member(data, entry, "output_sha256"), digest(target)
            )
            if matched:
                matched = _equals_number(
                    data,
                    _member(data, entry, "output_size_bytes"),
                    Float64(_file_size(target)),
                )
            _require(
                matched,
                "Synthetic regeneration mismatch: "
                + _text(data, _member(data, entry, "name")),
            )
        if source_cache.byte_length() > 0:
            materialize_sources(
                data,
                source_cache,
                folder + "/sources",
                fetch_sources,
                fetch_command,
            )
            regenerate_production(data, folder + "/sources", folder)
    finally:
        remove_tree(folder)


comptime USAGE = (
    "usage: check_converted_asset_manifest.mojo [--require-source-pins]"
    " [--source-cache SOURCE_CACHE] [--fetch-sources]"
)
"""The command line."""


def run(
    arguments: List[String], root: String = "."
) -> Tuple[Int, String, String]:
    """Run the check as the command line does.

    Args:
        arguments: The program name and its options.
        root: The repository root.

    Returns:
        The exit status, the standard output and the standard error.
    """
    var pins = False
    var fetch = False
    var cache = String()
    var index = 1
    while index < len(arguments):
        var argument = arguments[index]
        if argument == "--require-source-pins":
            pins = True
        elif argument == "--fetch-sources":
            fetch = True
        elif argument == "--source-cache":
            if index + 1 >= len(arguments):
                return (
                    2,
                    String(),
                    String(USAGE)
                    + "\nerror: argument --source-cache: expected one"
                    + " argument\n",
                )
            index += 1
            cache = arguments[index]
        elif argument.startswith("--source-cache="):
            cache = String(argument[byte=15:])
        else:
            return (
                2,
                String(),
                String(USAGE)
                + "\nerror: unrecognized arguments: "
                + argument
                + "\n",
            )
        index += 1
    try:
        verify(root, "", pins, cache, fetch)
    except error:
        return (1, String(), String(error) + "\n")
    var out = String(
        "Verified local hashes, complete source pins, and three synthetic"
        " outputs.\n"
    )
    if cache.byte_length() == 0:
        out += (
            "Production reproduction was not run; pass --source-cache to"
            " check it.\n"
        )
    else:
        out += (
            "Verified all pinned source bytes and reproduced all three"
            " production outputs exactly.\n"
        )
    return (0, out^, String())


def main():
    """Run an offline check or explicit production reproduction."""
    var arguments = List[String]()
    for argument in argv():
        arguments.append(String(argument))
    var outcome = run(arguments)
    print(outcome[1], end="")
    print(outcome[2], end="", file=stderr)
    exit(outcome[0])
