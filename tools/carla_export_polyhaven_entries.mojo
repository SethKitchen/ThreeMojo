# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the manifest's Poly Haven entries from Poly Haven's own API.

For each asset in `ASSETS`, read its name, its authors, its scanned size
and its files from api.polyhaven.com, and write its entry: a texture
set's maps and its tile size (the scan's width), an HDRI's panorama, or
a model's glTF with every file the glTF names. Then download each file
into the cache, check it against the MD5 sum the API gives, and write
its SHA-256 sum into the manifest.

    sh tools/tool.sh .venv/bin/mojo carla_export_polyhaven_entries [--resolution 2k]

It replaces `assets/carla/tools/export/polyhaven_entries.py`, with the same
command line, entries, texts and exit statuses. `curl` reads the API and
downloads the files, as `tools/carla_assets.mojo` downloads them.
"""

from std.ffi import external_call
from std.math import isinf
from std.sys import argv, exit, stderr
from std.time import sleep

from tools._carla_assets import (
    ATTEMPTS,
    Transport,
    curl_get,
    default_cache,
    default_manifest,
    fetch_file,
    join_path,
    load_manifest,
    pad,
    path_text,
    save_manifest,
    subscript,
    type_name,
    value_repr,
    value_str,
)
from tools._carla_files import (
    exception_text,
    make_temporary,
    path_exists,
    read_file,
    remove_file,
)
from tools._carla_manifests import export_error_line, items_of
from tools._cli import parse_command_line
from tools._md5 import md5_hex
from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
    loads,
    py_equal,
    py_repr,
    sorted_order,
)
from tools._python_stats import format_fixed

comptime PROGRAM = "carla_export_polyhaven_entries"
"""The program name in usage and error texts."""
comptime API = "https://api.polyhaven.com"
"""Poly Haven's API."""
comptime USAGE = (
    "usage: carla_export_polyhaven_entries [-h] [--manifest MANIFEST]\n"
    "                                      [--cache CACHE]\n"
    "                                      [--resolution RESOLUTION]\n"
)
"""The usage text."""
comptime HELP = """
Write the manifest's Poly Haven entries from Poly Haven's own API.

For each asset in `ASSETS`, read its name, its authors, its scanned size
and its files from api.polyhaven.com, and write its entry: a texture
set's maps and its tile size (the scan's width), an HDRI's panorama, or
a model's glTF with every file the glTF names. Then download each file
into the cache, check it against the MD5 sum the API gives, and write
its SHA-256 sum into the manifest.

    sh tools/tool.sh .venv/bin/mojo carla_export_polyhaven_entries [--resolution 2k]

options:
  -h, --help            show this help message and exit
  --manifest MANIFEST
  --cache CACHE
  --resolution RESOLUTION
"""
"""The help after the usage."""

comptime ASSETS: List[Tuple[String, String, String]] = [
    ("asphalt_02", "texture_set", ""),
    ("concrete_pavement", "texture_set", ""),
    ("concrete_floor_02", "texture_set", ""),
    ("leafy_grass", "texture_set", ""),
    ("patterned_paving", "texture_set", ""),
    ("kloofendal_48d_partly_cloudy_puresky", "hdri", ""),
    ("kloofendal_overcast_puresky", "hdri", ""),
    ("belfast_sunset_puresky", "hdri", ""),
    ("island_tree_01", "model", "+z"),
    ("concrete_road_barrier", "model", "+x"),
]
"""Each asset id, its kind and a model's forward axis."""
comptime MAPS: List[Tuple[String, String, String]] = [
    ("albedo", "Diffuse", "jpg"),
    ("normal", "nor_gl", "jpg"),
    ("roughness", "Rough", "jpg"),
    ("ao", "AO", "jpg"),
    ("displacement", "Displacement", "png"),
]
"""The map roles, the API's names for them and their formats."""


def today() -> String:
    """Return `datetime.date.today().isoformat()`, in local time.

    Returns:
        The date, such as `2026-10-15`.
    """
    var seconds = List[Int](length=1, fill=0)
    _ = external_call["time", Int](
        OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(seconds.unsafe_ptr())
        )
    )
    var fields = List[Int32](length=16, fill=0)
    _ = external_call["localtime_r", OpaquePointer[MutAnyOrigin]](
        OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(seconds.unsafe_ptr())
        ),
        OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(fields.unsafe_ptr())
        ),
    )
    var year = Int(fields[5]) + 1900
    var month = Int(fields[4]) + 1
    var day = Int(fields[3])
    var text = String(year)
    while text.byte_length() < 4:
        text = "0" + text
    return (
        text
        + "-"
        + ("0" if month < 10 else "")
        + String(month)
        + "-"
        + ("0" if day < 10 else "")
        + String(day)
    )


def api_get(path: String, api: String, transport: Transport) raises -> PyJson:
    """Return the API's JSON answer for `path`, as the Python `get` does.

    An HTTP error is final. Another failure is tried again, up to
    `ATTEMPTS` times in all.

    Args:
        path: The API path, such as `/info/asphalt_02`.
        api: The API's root URL.
        transport: The `curl` program and the wait between tries.

    Returns:
        The answer.

    Raises:
        Error: `urllib.error.HTTPError` or `urllib.error.URLError` text, or
            a decoding error.
    """
    var url = api + path
    var body = make_temporary("/tmp", "polyhaven.", ".json")
    try:
        for attempt in range(ATTEMPTS):
            var answer = curl_get(url, body, transport)
            if answer.status != 0:
                if attempt + 1 == ATTEMPTS:
                    raise Error(
                        "urllib.error.URLError: <urlopen error "
                        + answer.problem
                        + ">"
                    )
                sleep(transport.backoff * Float64(attempt + 1))
                continue
            if answer.code < 200 or answer.code >= 300:
                raise Error(
                    "urllib.error.HTTPError: HTTP Error "
                    + String(answer.code)
                    + ": "
                    + answer.reason
                )
            var data = read_file(body)
            try:
                return loads(Span(data))
            except error:
                var text = String(error)
                if text.startswith("'utf-8' codec") or text.startswith("'utf-"):
                    raise Error("UnicodeDecodeError: " + text)
                raise Error("json.decoder.JSONDecodeError: " + text)
        raise Error("urllib.error.URLError: <urlopen error no answer>")
    finally:
        if path_exists(body):
            remove_file(body)


def _member(mut doc: PyJson, node: Int, key: String) raises -> Int:
    """Return `value[key]`, with Python's errors."""
    return subscript(doc, node, key)


def _basename(doc: PyJson, node: Int) raises -> String:
    """Return `os.path.basename(value)` for a str."""
    if doc.kind(node) != PY_STR:
        raise Error(
            "TypeError: expected str, bytes or os.PathLike object, not "
            + type_name(doc, node)
        )
    var text = doc.text(node)
    var cut = text.rfind("/")
    return String(text[byte = cut + 1 :]) if cut >= 0 else text


def authors(mut doc: PyJson, info: Int) raises -> String:
    """Return the credit line of an asset's authors.

    Args:
        doc: The document.
        info: The API's information about the asset.

    Returns:
        `", ".join(info["authors"])`.

    Raises:
        Error: Python's error text for authors that are not str.
    """
    var names = List[String]()
    var index = 0
    for author in items_of(doc, _member(doc, info, "authors")):
        if doc.kind(author) != PY_STR:
            raise Error(
                "TypeError: sequence item "
                + String(index)
                + ": expected str instance, "
                + type_name(doc, author)
                + " found"
            )
        names.append(doc.text(author))
        index += 1
    return ", ".join(names)


def _round3(value: Float64) raises -> Float64:
    """Return `round(value, 3)`."""
    return parse_float(format_fixed(value, 3))


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a number as `float` would, with Python's error for `/`."""
    var kind = doc.kind(node)
    if kind == PY_BOOL:
        return 1.0 if doc.flag(node) else 0.0
    if kind == PY_INT:
        var value = parse_float(doc.text(node))
        if isinf(value):
            raise Error("OverflowError: int too large to convert to float")
        return value
    if kind == PY_FLOAT:
        return doc.number(node)
    raise Error(
        "TypeError: unsupported operand type(s) for /: "
        + py_repr(type_name(doc, node))
        + " and 'float'"
    )


def _index0(doc: PyJson, node: Int) raises -> Int:
    """Return `value[0]`, with Python's errors."""
    var kind = doc.kind(node)
    if kind == PY_LIST:
        return doc.item(node, 0)
    if kind == PY_DICT:
        raise Error("KeyError: 0")
    raise Error(
        "TypeError: "
        + py_repr(type_name(doc, node))
        + " object is not subscriptable"
    )


struct Entry(Movable):
    """A new entry and the MD5 sum the API gives for each of its paths."""

    var node: Int
    """The entry, in the manifest's document."""
    var paths: List[String]
    """Each path with a sum."""
    var sums: List[Int]
    """The API's sum for each path, in the manifest's document."""

    def __init__(out self, node: Int):
        """Start an entry.

        Args:
            node: The entry.
        """
        self.node = node
        self.paths = List[String]()
        self.sums = List[Int]()

    def md5(self, path: String) -> Int:
        """Return the API's sum of a path; the last one given wins.

        Args:
            path: The path.

        Returns:
            The sum's value.
        """
        var found = MISSING
        for index in range(len(self.paths)):
            if self.paths[index] == path:
                found = self.sums[index]
        return found


def _add(
    mut doc: PyJson,
    mut entry: Entry,
    role: String,
    item: Int,
    path: String,
) raises:
    """Add one file to an entry and remember its MD5 sum."""
    var files = doc.get(entry.node, "files")
    var record = doc.new_dict()
    doc.set(record, "role", doc.new_str(role))
    doc.set(record, "url", _member(doc, item, "url"))
    doc.set(record, "sha256", doc.new_none())
    doc.set(record, "path", doc.new_str(path))
    doc.append(files, record)
    entry.paths.append(path)
    entry.sums.append(_member(doc, item, "md5"))


def entry_of(
    mut doc: PyJson,
    asset_id: String,
    kind: String,
    forward: String,
    resolution: String,
    day: String,
    api: String,
    transport: Transport,
) raises -> Entry:
    """Return an entry and the MD5 sum the API gives for each of its paths.

    Args:
        doc: The manifest's document; the entry is added to it.
        asset_id: The Poly Haven id.
        kind: `texture_set`, `hdri` or `model`.
        forward: A model's forward axis.
        resolution: The resolution to fetch, such as `2k`.
        day: The date the API is read, as ISO text.
        api: The API's root URL.
        transport: How the API is read.

    Returns:
        The entry.

    Raises:
        Error: Python's error text for an API answer without its keys, or
            an HTTP error.
    """
    var info_doc = api_get("/info/" + asset_id, api, transport)
    var info = doc.adopt(info_doc, info_doc.root)
    var files_doc = api_get("/files/" + asset_id, api, transport)
    var files = doc.adopt(files_doc, files_doc.root)
    var node = doc.new_dict()
    var entry = Entry(node)
    doc.set(node, "id", doc.new_str(asset_id))
    doc.set(node, "kind", doc.new_str(kind))
    doc.set(node, "title", _member(doc, info, "name"))
    doc.set(node, "license", doc.new_str("CC0-1.0"))
    doc.set(node, "author", doc.new_str(authors(doc, info)))
    doc.set(node, "source", doc.new_str("https://polyhaven.com/a/" + asset_id))
    doc.set(
        node,
        "provenance",
        doc.new_str(
            "Poly Haven, "
            + resolution
            + ". The name, the authors, the size and the files are from"
            " api.polyhaven.com, read on "
            + day
            + "; each file matched the MD5 sum the API gives before its"
            " SHA-256 sum was written here."
        ),
    )
    doc.set(node, "files", doc.new_list())
    if kind == "texture_set":
        var width = _number(doc, _index0(doc, _member(doc, info, "dimensions")))
        doc.set(node, "tile_meters", doc.new_float(_round3(width / 1000.0)))
        for map in materialize[MAPS]():
            if doc.kind(files) == PY_DICT and doc.get(files, map[1]) != MISSING:
                var item = _member(
                    doc,
                    _member(doc, _member(doc, files, map[1]), resolution),
                    map[2],
                )
                var path = (
                    asset_id + "/" + _basename(doc, _member(doc, item, "url"))
                )
                _add(doc, entry, map[0], item, path)
    elif kind == "hdri":
        var item = _member(
            doc, _member(doc, _member(doc, files, "hdri"), resolution), "hdr"
        )
        var path = asset_id + "/" + _basename(doc, _member(doc, item, "url"))
        _add(doc, entry, "hdri", item, path)
    else:
        doc.set(node, "forward", doc.new_str(forward))
        var gltf = _member(
            doc, _member(doc, _member(doc, files, "gltf"), resolution), "gltf"
        )
        var path = asset_id + "/" + _basename(doc, _member(doc, gltf, "url"))
        _add(doc, entry, "model", gltf, path)
        var include = _member(doc, gltf, "include")
        if doc.kind(include) != PY_DICT:
            raise Error(
                "AttributeError: "
                + py_repr(type_name(doc, include))
                + " object has no attribute 'items'"
            )
        var keys = List[String]()
        for index in range(doc.length(include)):
            keys.append(doc.key(include, index))
        for index in sorted_order(keys):
            _add(
                doc,
                entry,
                "support",
                doc.value(include, index),
                asset_id + "/" + keys[index],
            )
    return entry^


def md5_of(path: String) raises -> String:
    """Return a file's MD5 sum.

    Args:
        path: The file.

    Returns:
        The sum, as 32 lower-case hex digits.

    Raises:
        Error: An `OSError` if the file cannot be read.
    """
    return md5_hex(Span(read_file(path)))


def write_entries(
    manifest_path: String,
    cache: String,
    resolution: String,
    day: String,
    api: String,
    transport: Transport,
    mut out: String,
) raises:
    """Rewrite the Poly Haven entries, fetch them and pin them.

    Args:
        manifest_path: The manifest to rewrite.
        cache: The cache that receives the files.
        resolution: The resolution to fetch.
        day: The date the API is read.
        api: The API's root URL.
        transport: How the API is read and the files are downloaded.
        out: Receives each line the Python script printed.

    Raises:
        Error: Python's error text, such as `carla_assets.FetchError` for a
            file whose MD5 sum is not the API's.
    """
    var doc = load_manifest(manifest_path)
    var manifest = doc.root
    var fresh = List[Int]()
    var fresh_ids = List[String]()
    for asset in materialize[ASSETS]():
        var entry = entry_of(
            doc, asset[0], asset[1], asset[2], resolution, day, api, transport
        )
        var files = doc.get(entry.node, "files")
        for index in range(doc.length(files)):
            var item = doc.item(files, index)
            var status = fetch_file(
                doc, item, path_text(cache), True, False, transport
            )
            var path = doc.text(doc.get(item, "path"))
            var found = md5_of(join_path(path_text(cache), path))
            var expected = entry.md5(path)
            if not (
                doc.kind(expected) == PY_STR and doc.text(expected) == found
            ):
                raise Error(
                    "FetchError: "
                    + value_str(doc, doc.get(item, "url"))
                    + ": MD5 "
                    + found
                    + " is not the API's "
                    + value_str(doc, expected)
                )
            out += pad(status, 9) + " " + path + "\n"
        var replaced = False
        for index in range(len(fresh_ids)):
            if fresh_ids[index] == asset[0]:
                fresh[index] = entry.node
                replaced = True
        if not replaced:
            fresh.append(entry.node)
            fresh_ids.append(asset[0])
    # Replace the old Poly Haven entries, and put the new ones first.
    var entries = doc.get(manifest, "entries")
    var old = List[Int]()
    var old_ids = List[String]()
    var rest = List[Int]()
    for index in range(doc.length(entries)):
        var entry = doc.item(entries, index)
        if doc.text(doc.get(entry, "source")).startswith(
            "https://polyhaven.com/"
        ):
            old.append(entry)
            old_ids.append(doc.text(doc.get(entry, "id")))
    for index in range(doc.length(entries)):
        var entry = doc.item(entries, index)
        var equal = False
        for other in old:
            if py_equal(doc, entry, doc, other):
                equal = True
        if not equal:
            rest.append(entry)
    var replaced = doc.new_list()
    for node in fresh:
        doc.append(replaced, node)
    for node in rest:
        doc.append(replaced, node)
    doc.set(manifest, "entries", replaced)
    var gone = List[String]()
    for name in old_ids:
        var kept = False
        for fresh_id in fresh_ids:
            if fresh_id == name:
                kept = True
        var listed = False
        for seen in gone:
            if seen == name:
                listed = True
        if not kept and not listed:
            gone.append(name)
    var bindings = subscript(doc, manifest, "bindings")
    for index in range(doc.length(bindings)):
        var value = doc.value(bindings, index)
        if doc.kind(value) != PY_STR:
            continue
        for name in gone:
            if name == doc.text(value):
                doc.set(bindings, doc.key(bindings, index), doc.new_none())
                break
    save_manifest(doc, manifest, manifest_path)
    var dropped = String("[")
    var order = sorted_order(gone)
    for position in range(len(order)):
        if position > 0:
            dropped += ", "
        dropped += py_repr(gone[order[position]])
    dropped += "]"
    out += (
        String(len(fresh))
        + " Poly Haven entries written; dropped "
        + dropped
        + "\n"
    )


def main() raises:
    """Rewrite the manifest's Poly Haven entries.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var command = parse_command_line(
        arguments,
        PROGRAM,
        USAGE,
        HELP,
        List[String](),
        ["--manifest", "--cache", "--resolution"],
    )
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    var out = String()
    try:
        write_entries(
            command.value("--manifest", default_manifest()),
            command.value("--cache", default_cache()),
            command.value("--resolution", "2k"),
            today(),
            API,
            Transport(),
            out,
        )
    except error:
        print(out, end="")
        print(export_error_line(error), file=stderr)
        exit(1)
    print(out, end="")
