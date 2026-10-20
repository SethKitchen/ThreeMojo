# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The scanned-building manifest: its rules, its scene pages and credits.

`tools/building_scans.mojo` is the command line. The manifest,
`assets/building_scans/manifest.json`, has the shape of the CARLA asset
manifest, so `tools._carla_assets.fetch` and `verify` fetch and check its
files with the same rules: a file is written to the cache only after its
sum matches, a verified file is never overwritten, and an unpinned file is
fetched only with `--pin`.

An entry names one SuperSplat scene. Before its files are pinned, it has
no files. `resolve` then reads the scene page, `https://superspl.at/s?id=`
and the scene id, and finds the `contentUrl` that the page's viewer loads:
the scene's `meta.json`. The text names the SOG images, which lie beside
it. Each becomes a file of the entry, with its URL and no sum, so the
pinning fetch that follows downloads it and records its sum.

**The licenses.** Only CC BY 4.0 and CC0 1.0 are allowed. A scene under a
license that forbids changes or commercial use, such as CC BY-ND or CC
BY-NC, is refused, because ThreeMojo changes what it reads and has a
commercial license.

**What is refused in a page and a text.** A page with no `contentUrl`, or
one whose URL is not `https://` or `file://`. A file name with a folder
in it, so a downloaded text cannot write outside the entry's folder.
"""

from std.math import isfinite
from std.os.path import realpath

from loaders.json import NO_NODE, OBJECT, parse_json
from tools._carla_assets import (
    Transport,
    curl_get,
    download,
    entries_of,
    join_path,
    manifest_text,
    read_json_text,
)
from tools._carla_files import (
    make_dirs,
    make_temporary,
    path_exists,
    path_is_file,
    read_file,
    remove_file,
    write_text,
)
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
    py_repr,
)

comptime FORMAT = 1
"""The manifest format this tool reads."""
comptime SCENE_PAGE = "https://superspl.at/s?id="
"""The page of a SuperSplat scene, before its id."""
comptime CC_BY = "CC-BY-4.0"
"""The Creative Commons Attribution 4.0 license."""
comptime CC0 = "CC0-1.0"
"""The Creative Commons Zero 1.0 dedication."""
comptime LICENSES: List[String] = [CC_BY, CC0]
"""The licenses an entry may have."""
comptime LICENSE_URLS: List[String] = [
    "https://creativecommons.org/licenses/by/4.0/",
    "https://creativecommons.org/publicdomain/zero/1.0/",
]
"""The text of each license, in the same order."""
comptime KITS: List[String] = ["masonry", "stone", "concrete", "timber"]
"""The construction kits of `extensions.building.kits`."""
comptime USES: List[String] = [
    "office",
    "corridor",
    "core",
    "lobby",
    "retail",
    "living",
    "bedroom",
    "kitchen",
    "bathroom",
    "storage",
    "mechanical",
    "meeting",
]
"""The space uses of `extensions.building.kinds`."""
comptime AXES: List[String] = ["+x", "-x", "+y", "-y", "+z", "-z"]
"""The scan axes of `extensions.scan.frame`."""
comptime SCALES: List[String] = ["declared", "measured", "assumed"]
"""The scale sources of `extensions.scan.frame`."""
comptime ENTRY_KEYS: List[String] = [
    "id",
    "title",
    "author",
    "author_url",
    "license",
    "source",
    "scene",
    "provenance",
    "changes",
    "kit",
    "use",
    "frame",
    "files",
]
"""The keys every entry has."""
comptime ROLES: List[String] = ["meta", "image"]
"""What a file of an entry is."""


def default_manifest() raises -> String:
    """Return the repository's manifest.

    The tool runs from the repository root, as `tools/tool.sh` runs it.

    Returns:
        The absolute path of `assets/building_scans/manifest.json`.

    Raises:
        Error: If the working directory cannot be read.
    """
    return realpath(".") + "/assets/building_scans/manifest.json"


def default_cache() raises -> String:
    """Return the cache that git ignores.

    Returns:
        The absolute path of `.cache/building-scans`.

    Raises:
        Error: If the working directory cannot be read.
    """
    return realpath(".") + "/.cache/building-scans"


def _manifest_error(text: String) -> Error:
    """Return a `ManifestError`."""
    return Error("ManifestError: " + text)


def _fetch_error(text: String) -> Error:
    """Return a `FetchError`."""
    return Error("FetchError: " + text)


def _contains(items: List[String], text: String) -> Bool:
    """Return whether a list holds a text."""
    for item in items:
        if item == text:
            return True
    return False


def _text(doc: PyJson, node: Int, key: String, place: String) raises -> String:
    """Return a non-empty string under a key, or raise.

    Args:
        doc: The document.
        node: The object.
        key: The key.
        place: Where the object is, for the error.

    Returns:
        The text.

    Raises:
        Error: `ManifestError` text if the value is not a non-empty string.
    """
    var value = doc.get(node, key)
    if doc.kind(value) != PY_STR or doc.text(value) == "":
        raise _manifest_error(
            place + ": " + key + " must be a non-empty string"
        )
    return doc.text(value)


def _one_of(
    doc: PyJson, node: Int, key: String, allowed: List[String], place: String
) raises -> String:
    """Return a string under a key that is one of a list, or raise."""
    var text = _text(doc, node, key, place)
    if not _contains(allowed, text):
        raise _manifest_error(
            place
            + ": "
            + key
            + " "
            + py_repr(text)
            + " is not one of "
            + ", ".join(allowed)
        )
    return text


def is_file_name(name: String) -> Bool:
    """Return whether a name is one file, not a path.

    Args:
        name: The name.

    Returns:
        False for an empty name, `.`, `..`, or a name with `/` or `\\`.
    """
    if name == "" or name == "." or name == "..":
        return False
    return not ("/" in name or "\\" in name)


def is_sum(text: String) -> Bool:
    """Return whether a text is a SHA-256 sum: 64 lower-case hex digits.

    Args:
        text: The text.

    Returns:
        Whether it is one.
    """
    var bytes = text.as_bytes()
    if len(bytes) != 64:
        return False
    for byte in bytes:
        var digit = byte >= 0x30 and byte <= 0x39
        var letter = byte >= 0x61 and byte <= 0x66
        if not digit and not letter:
            return False
    return True


def _check_file(doc: PyJson, item: Int, entry_id: String, place: String) raises:
    """Refuse a file record that the fetch cannot use.

    Args:
        doc: The document.
        item: The file record.
        entry_id: Its entry's id.
        place: Where it is, for the error.

    Raises:
        Error: `ManifestError` text for a bad role, path, URL or sum. A
            file with a null URL and a null sum waits to be put in the
            cache by hand and pinned there.
    """
    _ = _one_of(doc, item, "role", materialize[ROLES](), place)
    var path = _text(doc, item, "path", place)
    var prefix = entry_id + "/"
    if not path.startswith(prefix) or not is_file_name(
        String(path[byte = prefix.byte_length() :])
    ):
        raise _manifest_error(
            place + ": path must be the entry id, a slash and a file name"
        )
    var url = doc.get(item, "url")
    if url == MISSING:
        raise _manifest_error(place + ": a file needs a url, or null")
    if not doc.is_none(url):
        var text = _text(doc, item, "url", place)
        if not text.startswith("https://") and not text.startswith("file://"):
            raise _manifest_error(place + ": a url must be https:// or file://")
    var sum = doc.get(item, "sha256")
    if sum == MISSING:
        raise _manifest_error(place + ": a file needs a sha256, or null")
    if not doc.is_none(sum) and not is_sum(_text(doc, item, "sha256", place)):
        raise _manifest_error(place + ": sha256 must be 64 hex digits")


def _positive(doc: PyJson, node: Int) -> Bool:
    """Return whether a value is a finite number above zero.

    Args:
        doc: The document.
        node: The value, or `MISSING`.

    Returns:
        True for an int above zero or a finite float above zero.
    """
    var kind = doc.kind(node)
    if kind == PY_INT:
        var digits = doc.text(node)
        return not digits.startswith("-") and digits != "0"
    if kind == PY_FLOAT:
        var value = doc.number(node)
        return value > 0 and isfinite(value)
    return False


def _check_frame(doc: PyJson, entry: Int, place: String) raises:
    """Refuse a frame that `extensions.scan.frame` would refuse.

    Args:
        doc: The document.
        entry: The entry.
        place: Where it is, for the error.

    Raises:
        Error: `ManifestError` text for a bad axis, unit or scale.
    """
    var frame = doc.get(entry, "frame")
    if doc.kind(frame) != PY_DICT:
        raise _manifest_error(place + ": frame must be an object")
    var up = _one_of(doc, frame, "up", materialize[AXES](), place + " frame")
    var north = _one_of(
        doc, frame, "north", materialize[AXES](), place + " frame"
    )
    if up.as_bytes()[1] == north.as_bytes()[1]:
        raise _manifest_error(place + " frame: up and north must differ")
    if not _positive(doc, doc.get(frame, "unit_m")):
        raise _manifest_error(
            place + " frame: unit_m must be a positive number"
        )
    _ = _one_of(doc, frame, "scale", materialize[SCALES](), place + " frame")


def check_scan_manifest(doc: PyJson, manifest: Int) raises:
    """Refuse a manifest that breaks the rules of the module docstring.

    Args:
        doc: The document.
        manifest: The manifest value.

    Raises:
        Error: `ManifestError` text for the first rule broken.
    """
    if doc.kind(manifest) != PY_DICT:
        raise _manifest_error("the manifest must be an object")
    var format = doc.get(manifest, "format")
    if doc.kind(format) != PY_INT or doc.text(format) != String(FORMAT):
        raise _manifest_error("format must be " + String(FORMAT))
    var entries = doc.get(manifest, "entries")
    if doc.kind(entries) != PY_LIST:
        raise _manifest_error("entries must be a list")
    var seen = List[String]()
    for index in range(doc.length(entries)):
        var entry = doc.item(entries, index)
        var place = "entry " + String(index)
        if doc.kind(entry) != PY_DICT:
            raise _manifest_error(place + " must be an object")
        for key in materialize[ENTRY_KEYS]():
            if doc.get(entry, key) == MISSING:
                raise _manifest_error(place + ": missing " + key)
        var entry_id = _text(doc, entry, "id", place)
        if not is_file_name(entry_id):
            raise _manifest_error(place + ": id must be one file name")
        if _contains(seen, entry_id):
            raise _manifest_error("duplicate id " + py_repr(entry_id))
        seen.append(entry_id)
        place = py_repr(entry_id)
        for key in ["title", "author", "provenance", "changes"]:
            _ = _text(doc, entry, key, place)
        for key in ["author_url", "source"]:
            if not _text(doc, entry, key, place).startswith("https://"):
                raise _manifest_error(place + ": " + key + " must be https://")
        _ = _one_of(doc, entry, "license", materialize[LICENSES](), place)
        _ = _one_of(doc, entry, "kit", materialize[KITS](), place)
        _ = _one_of(doc, entry, "use", materialize[USES](), place)
        if not is_file_name(_text(doc, entry, "scene", place)):
            raise _manifest_error(place + ": scene must be a scene id")
        _check_frame(doc, entry, place)
        var files = doc.get(entry, "files")
        if doc.kind(files) != PY_LIST:
            raise _manifest_error(place + ": files must be a list")
        var paths = List[String]()
        for at in range(doc.length(files)):
            var item = doc.item(files, at)
            var spot = place + " file " + String(at)
            if doc.kind(item) != PY_DICT:
                raise _manifest_error(spot + " must be an object")
            _check_file(doc, item, entry_id, spot)
            var path = doc.text(doc.get(item, "path"))
            if _contains(paths, path):
                raise _manifest_error(
                    spot + ": duplicate path " + py_repr(path)
                )
            paths.append(path)


def load_scan_manifest(path: String) raises -> PyJson:
    """Return the manifest at `path`, checked.

    Args:
        path: The manifest file.

    Returns:
        The document; its root is the manifest.

    Raises:
        Error: An `OSError`, a decoding error or a `ManifestError`.
    """
    var doc = read_json_text(read_file(path))
    check_scan_manifest(doc, doc.root)
    return doc^


def save_scan_manifest(doc: PyJson, manifest: Int, path: String) raises:
    """Check the manifest and write it back, two-space indented.

    Args:
        doc: The document.
        manifest: The manifest value.
        path: The file to write.

    Raises:
        Error: A `ManifestError`, or an `OSError` from the write.
    """
    check_scan_manifest(doc, manifest)
    write_text(path, manifest_text(doc, manifest))


def content_url(page: String) raises -> String:
    """Return the `contentUrl` that a scene page's viewer loads.

    The page sets it in a script, as `contentUrl = '...'` or as
    `"contentUrl":"..."`.

    Args:
        page: The page's text.

    Returns:
        The URL.

    Raises:
        Error: `FetchError` text if the page has none, it is not an
            `https://` or a `file://` URL, or it does not name a
            `meta.json`, as a streamed `lod-meta.json` scene does.
    """
    var at = page.find("contentUrl")
    if at < 0:
        raise _fetch_error("the scene page has no contentUrl")
    var bytes = page.as_bytes()
    var index = at + len("contentUrl".as_bytes())
    # Past the closing quote of a key, spaces, one `=` or `:`, and spaces.
    if index < len(bytes) and (bytes[index] == 0x22 or bytes[index] == 0x27):
        index += 1
    while index < len(bytes) and bytes[index] == 0x20:
        index += 1
    if index < len(bytes) and (bytes[index] == 0x3D or bytes[index] == 0x3A):
        index += 1
    while index < len(bytes) and bytes[index] == 0x20:
        index += 1
    if index >= len(bytes) or (bytes[index] != 0x27 and bytes[index] != 0x22):
        raise _fetch_error("the scene page's contentUrl is not a quoted text")
    var quote = bytes[index]
    var start = index + 1
    var end = start
    while end < len(bytes) and bytes[end] != quote:
        end += 1
    if end >= len(bytes):
        raise _fetch_error("the scene page's contentUrl is not a quoted text")
    var url = String(page[byte=start:end])
    if not url.startswith("https://") and not url.startswith("file://"):
        raise _fetch_error(
            "the scene page's contentUrl is not https:// or file://: " + url
        )
    var folder = url_folder(url)
    var name = String(url[byte = folder.byte_length() :])
    var cut = name.find("?")
    if cut >= 0:
        var head = String(name[byte=:cut])
        name = head^
    if name != "meta.json":
        raise _fetch_error(
            "the scene is "
            + name
            + ", not one SOG meta.json; download it with the Download"
            + " button of its page"
        )
    return url^


def url_folder(url: String) -> String:
    """Return a URL up to the last `/` of its path.

    Args:
        url: The URL.

    Returns:
        The folder, ending in `/`. A query and a fragment are dropped.
    """
    var end = url.byte_length()
    var query = url.find("?")
    if query >= 0:
        end = query
    var fragment = url.find("#")
    if fragment >= 0 and fragment < end:
        end = fragment
    var head = String(url[byte=:end])
    return String(head[byte = 0 : head.rfind("/") + 1])


def meta_names(text: String) raises -> List[String]:
    """Return the image names that a SOG `meta.json` text gives.

    Args:
        text: The text.

    Returns:
        The names of every section's `files`, in the order of the text,
        each once.

    Raises:
        Error: `FetchError` text if the text is not a JSON object, it names
            no file, or a name is not a file name.
    """
    var document = parse_json(text)
    var names = List[String]()
    var root = document.root()
    if document.kind(root) != OBJECT:
        raise _fetch_error("meta.json is not an object")
    for index in range(document.length(root)):
        var section = document.get(root, document.key(root, index))
        if document.kind(section) != OBJECT:
            continue
        var files = document.get(section, "files")
        if files == NO_NODE:
            continue
        for at in range(document.length(files)):
            var name = document.string(document.at(files, at))
            if not is_file_name(name):
                raise _fetch_error(
                    "meta.json names " + py_repr(name) + ", not a file name"
                )
            if not _contains(names, name):
                names.append(name)
    if len(names) == 0:
        raise _fetch_error("meta.json names no image")
    return names^


def page_text(
    url: String, cache: String, transport: Transport
) raises -> String:
    """Return a scene page's text.

    Args:
        url: The page.
        cache: The cache root, where the page is held while it downloads.
        transport: The `curl` program.

    Returns:
        The text, with bytes that are not UTF-8 replaced.

    Raises:
        Error: `FetchError` text if `curl` fails or the host answers with
            an HTTP error.
    """
    make_dirs(cache)
    var partial = make_temporary(cache, "page.", ".part")
    try:
        var answer = curl_get(url, partial, transport)
        if answer.status != 0:
            raise _fetch_error(url + ": " + answer.problem)
        if answer.code < 200 or answer.code >= 300:
            raise _fetch_error(
                url
                + ": HTTP Error "
                + String(answer.code)
                + ": "
                + answer.reason
            )
        return String(from_utf8_lossy=read_file(partial))
    finally:
        if path_exists(partial):
            remove_file(partial)


def _file_record(
    mut doc: PyJson, role: String, url: String, path: String
) -> Int:
    """Return a new file record with no sum."""
    var item = doc.new_dict()
    doc.set(item, "role", doc.new_str(role))
    doc.set(item, "url", doc.new_str(url))
    doc.set(item, "sha256", doc.new_none())
    doc.set(item, "path", doc.new_str(path))
    return item


def resolve(
    mut doc: PyJson, entry: Int, cache: String, transport: Transport
) raises -> Int:
    """Give an entry with no files the files of its scene; see the module
    docstring.

    Args:
        doc: The document; the new file records go into the entry.
        entry: The entry.
        cache: The cache root.
        transport: The `curl` program.

    Returns:
        How many files the entry got: zero when it already had some.

    Raises:
        Error: `FetchError` text if the page, the text or a name is
            refused, or a download fails.
    """
    var files = doc.get(entry, "files")
    if doc.length(files) > 0:
        return 0
    var entry_id = doc.text(doc.get(entry, "id"))
    var page = page_text(
        SCENE_PAGE + doc.text(doc.get(entry, "scene")), cache, transport
    )
    var meta_url = content_url(page)
    make_dirs(join_path(cache, entry_id))
    var partial = make_temporary(join_path(cache, entry_id), "meta.", ".part")
    var names: List[String]
    try:
        download(meta_url, partial, transport)
        names = meta_names(String(from_utf8_lossy=read_file(partial)))
    finally:
        if path_exists(partial):
            remove_file(partial)
    var folder = url_folder(meta_url)
    doc.append(
        files, _file_record(doc, "meta", meta_url, entry_id + "/meta.json")
    )
    for name in names:
        doc.append(
            files,
            _file_record(doc, "image", folder + name, entry_id + "/" + name),
        )
    return len(names) + 1


def scene_path(doc: PyJson, entry: Int, cache: String) raises -> String:
    """Return where an entry's `meta.json` is in the cache.

    Args:
        doc: The document.
        entry: The entry.
        cache: The cache root.

    Returns:
        The path, whether or not the file is there.

    Raises:
        Error: Never for a checked manifest.
    """
    return join_path(cache, doc.text(doc.get(entry, "id")) + "/meta.json")


def is_cached(doc: PyJson, entry: Int, cache: String) raises -> Bool:
    """Return whether every file of an entry is in the cache.

    Args:
        doc: The document.
        entry: The entry.
        cache: The cache root.

    Returns:
        False for an entry with no files.

    Raises:
        Error: Never for a checked manifest.
    """
    var files = doc.get(entry, "files")
    if doc.length(files) == 0:
        return False
    for index in range(doc.length(files)):
        var item = doc.item(files, index)
        if not path_is_file(join_path(cache, doc.text(doc.get(item, "path")))):
            return False
    return True


def credit_line(doc: PyJson, entry: Int) raises -> String:
    """Return one attribution line, as CC BY 4.0 asks for it.

    Args:
        doc: The document.
        entry: The entry.

    Returns:
        The title, the author with their page, the source, the license
        with its text, and the changes.

    Raises:
        Error: Never for a checked manifest.
    """
    var license = doc.text(doc.get(entry, "license"))
    var name = String("CC0 1.0")
    var link = materialize[LICENSE_URLS]()[1]
    if license == CC_BY:
        name = "CC BY 4.0"
        link = materialize[LICENSE_URLS]()[0]
    return (
        '- "'
        + doc.text(doc.get(entry, "title"))
        + '" by '
        + doc.text(doc.get(entry, "author"))
        + " ("
        + doc.text(doc.get(entry, "author_url"))
        + "), "
        + doc.text(doc.get(entry, "source"))
        + ", "
        + name
        + " ("
        + link
        + "). Changes: "
        + doc.text(doc.get(entry, "changes"))
    )


def credits(
    doc: PyJson, manifest: Int, cache: String, everything: Bool
) raises -> String:
    """Return the credits of the cached entries, or of every entry.

    Args:
        doc: The document.
        manifest: A checked manifest.
        cache: The cache root.
        everything: Credit every entry, cached or not.

    Returns:
        A Markdown section, or a line that says nothing is cached.

    Raises:
        Error: Never for a checked manifest.
    """
    var lines = List[String]()
    for entry in entries_of(doc, manifest):
        if everything or is_cached(doc, entry, cache):
            lines.append(credit_line(doc, entry))
    if len(lines) == 0:
        return "No scanned building is cached.\n"
    return (
        "## Credits\n\n"
        + "\n".join(lines)
        + "\n\nCredit the author, link the source and the license, and say"
        + " what you changed, when you share a scan or a render of it.\n"
    )
