# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the exported CARLA vehicles and towns into the asset manifest.

`tools/carla_export_zip_packages.mojo` writes an index of the zipped
packages: each zip, its sum, its size and its members. These functions make
one manifest entry per package, with the zip as its archive, and bind each
blueprint id or town to its entry. They replace the entries of their family
and leave every other entry as it is. A binding to a removed entry becomes
null.

They do what `assets/carla/tools/export/manifest_vehicles.py` and
`manifest_towns.py` did, with the same entries, bindings, texts and errors.
An error that the asset manager raises keeps its Python module name,
`carla_assets.ManifestError`, as the Python scripts printed it.
"""

from tools._carla_assets import (
    CARLA_AUTHOR,
    load_manifest,
    read_json_text,
    save_manifest,
    subscript,
    truthy,
    type_name,
    value_str,
)
from tools._carla_files import exception_line, read_file
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
    code_points,
    py_equal,
    py_repr,
    sorted_order,
)

comptime PREFIX = "carla."
"""The prefix of a CARLA entry id."""
comptime TOWN_PREFIX = "carla.town."
"""The prefix of a CARLA town entry id."""
comptime SOURCE = "https://github.com/carla-simulator/carla/releases/tag/0.9.16"
"""The CARLA release page."""
comptime VEHICLE_PROVENANCE = (
    "CARLA 0.9.16's own vehicle, from the cooked Windows release "
    "(CARLA_0.9.16.zip). UE Viewer (umodel) build 1590 exported the "
    "blueprint's skeletal body and its static glass and lights to glTF; "
    "assets/carla/tools/export/ merged them and rebuilt the materials. "
    "The uncooked carla-content repository holds the same meshes, but "
    "UE Viewer cannot read uncooked meshes."
)
"""Where a vehicle came from."""
comptime VEHICLE_CHANGES = (
    "Exported from Unreal Engine 4.26 to glTF 2.0; the body and its "
    "attachments merged into one file; materials rebuilt as glTF PBR "
    "from their Unreal parameters; textures scaled to at most 1024 "
    "pixels."
)
"""What a vehicle's conversion changed."""
comptime TOWN_PROVENANCE = (
    "CARLA 0.9.16's own town, from the cooked Windows release "
    "(CARLA_0.9.16.zip). A running CARLA server, with UE4SS and "
    "assets/carla/tools/export/layout_dump/main.lua, wrote where the town "
    "places every static mesh; UE Viewer (umodel) build 1590 exported the "
    "meshes and their materials; assets/carla/tools/export/build_towns.py "
    "placed and merged them. The town's OpenDRIVE map is the release's own."
)
"""Where a town came from."""
comptime TOWN_CHANGES = (
    "Every static mesh placed as the town places it, in the renderer's "
    "frame; merged by 32 m tile, kind and material; a near and a far "
    "level of detail, trees far off drawn as impostors; meshes simplified "
    "to a triangle budget; materials rebuilt as glTF PBR; textures scaled "
    "to at most 512 pixels; textures that show another company's mark, a "
    "real person or institution, or poster art of unclear origin replaced "
    "by their average color."
)
"""What a town's conversion changed."""

comptime TITLES: List[Tuple[String, String]] = [
    ("vehicle.bh.crossbike", "BH Crossbike"),
    ("vehicle.bmw.grandtourer", "BMW Grand Tourer"),
    ("vehicle.carlamotors.carlacola", "CarlaCola Truck"),
    ("vehicle.carlamotors.european_hgv", "European HGV"),
    ("vehicle.carlamotors.firetruck", "Fire Truck"),
    ("vehicle.harley-davidson.low_rider", "Harley-Davidson Low Rider"),
    ("vehicle.mini.cooper_s", "Mini Cooper S"),
    ("vehicle.mini.cooper_s_2021", "Mini Cooper S 2021"),
    ("vehicle.lincoln.mkz_2017", "Lincoln MKZ 2017"),
    ("vehicle.lincoln.mkz_2020", "Lincoln MKZ 2020"),
    ("vehicle.mitsubishi.fusorosa", "Mitsubishi Fuso Rosa"),
    ("vehicle.tesla.model3", "Tesla Model 3"),
    ("vehicle.vespa.zx125", "Vespa ZX 125"),
    ("vehicle.volkswagen.t2", "Volkswagen T2"),
    ("vehicle.volkswagen.t2_2021", "Volkswagen T2 2021"),
    ("vehicle.yamaha.yzf", "Yamaha YZF"),
]
"""Names the blueprint id's make and model do not spell out."""

comptime ALIASES: List[Tuple[String, String]] = [
    ("vehicle.dodge.charger", "vehicle.dodge.charger_2020"),
    ("vehicle.dodgecop.charger", "vehicle.dodge.charger_police_2020"),
    ("vehicle.taxi.ford", "vehicle.ford.crown"),
    ("vehicle.lincoln.mkz", "vehicle.lincoln.mkz_2020"),
    ("vehicle.mini.cooper", "vehicle.mini.cooper_s_2021"),
    ("vehicle.sprinter.mercedes", "vehicle.mercedes.sprinter"),
    ("vehicle.carlacola.actors", "vehicle.carlamotors.carlacola"),
    ("vehicle.firetruck.actors", "vehicle.carlamotors.firetruck"),
    ("vehicle.ambulance.ford", "vehicle.ford.ambulance"),
    ("vehicle.fuso.mitsubishi", "vehicle.mitsubishi.fusorosa"),
]
"""Older and Unreal 5 blueprint ids, each bound to the 0.9.16 vehicle it
names."""


def export_error_line(error: Error) -> String:
    """Return the traceback's last line for an export tool's error.

    The asset manager's own errors keep the module they came from.

    Args:
        error: The error.

    Returns:
        The line, such as `carla_assets.ManifestError: ...`.
    """
    var line = exception_line(error)
    if line.startswith("ManifestError: ") or line.startswith("FetchError: "):
        return "carla_assets." + line
    return line^


def _upper_point(point: Int) -> Int:
    """Return a code point in upper case, for the scripts names use."""
    if point >= 0x61 and point <= 0x7A:
        return point - 0x20
    if point >= 0xE0 and point <= 0xFE and point != 0xF7:
        return point - 0x20
    return point


def _lower_point(point: Int) -> Int:
    """Return a code point in lower case, for the scripts names use."""
    if point >= 0x41 and point <= 0x5A:
        return point + 0x20
    if point >= 0xC0 and point <= 0xDE and point != 0xD7:
        return point + 0x20
    return point


def _text(points: List[Int]) -> String:
    """Return code points as text."""
    var out = String()
    for point in points:
        out += chr(point)
    return out^


def capitalize(text: String) -> String:
    """Return `str.capitalize()`: the first letter upper, the rest lower.

    Args:
        text: The str; ASCII and Latin-1 letters change case.

    Returns:
        The capitalized str.
    """
    var points = code_points(text, False)
    for index in range(len(points)):
        points[index] = _upper_point(
            points[index]
        ) if index == 0 else _lower_point(points[index])
    return _text(points)


def upper(text: String) -> String:
    """Return `str.upper()` for ASCII and Latin-1 letters.

    Args:
        text: The str.

    Returns:
        The str in upper case.
    """
    var points = code_points(text, False)
    for index in range(len(points)):
        points[index] = _upper_point(points[index])
    return _text(points)


def title_of(vehicle_id: String) raises -> String:
    """Return a vehicle's display name.

    Args:
        vehicle_id: The blueprint id, `vehicle.<make>.<model>`.

    Returns:
        The name from `TITLES`, or the make and the model's words, each
        capitalized, and a word of one or two letters in capitals.

    Raises:
        Error: Python's `ValueError` text for an id with fewer than three
            parts.
    """
    for pair in materialize[TITLES]():
        if pair[0] == vehicle_id:
            return pair[1]
    var parts = vehicle_id.split(".", 2)
    if len(parts) < 3:
        raise Error(
            "ValueError: not enough values to unpack (expected 3, got "
            + String(len(parts))
            + ")"
        )
    var words: List[String] = [capitalize(String(parts[1]))]
    for word in String(parts[2]).split("_"):
        var text = String(word)
        if len(code_points(text, False)) <= 2:
            words.append(upper(text))
        else:
            words.append(capitalize(text))
    return " ".join(words)


def items_of(mut doc: PyJson, node: Int) raises -> List[Int]:
    """Return what `for item in value` gives, each as a value of `doc`.

    Args:
        doc: The document; a str's characters and a dict's keys are added
            to it.
        node: The value.

    Returns:
        The items.

    Raises:
        Error: Python's `TypeError` text for a value that is not iterable.
    """
    var kind = doc.kind(node)
    var out = List[Int]()
    if kind == PY_LIST:
        for index in range(doc.length(node)):
            out.append(doc.item(node, index))
        return out^
    if kind == PY_DICT:
        var keys = List[String]()
        for index in range(doc.length(node)):
            keys.append(doc.key(node, index))
        for key in keys:
            out.append(doc.new_str(key))
        return out^
    if kind == PY_STR:
        var points = code_points(doc.text(node), False)
        for point in points:
            out.append(doc.new_str(chr(point)))
        return out^
    raise Error(
        "TypeError: "
        + py_repr(type_name(doc, node))
        + " object is not iterable"
    )


def _dict_get(doc: PyJson, node: Int, key: Int) raises -> Int:
    """Return `mapping.get(key)` for a dict read from JSON."""
    if doc.kind(node) != PY_DICT:
        raise Error(
            "AttributeError: "
            + py_repr(type_name(doc, node))
            + " object has no attribute 'get'"
        )
    var kind = doc.kind(key)
    if kind == PY_LIST or kind == PY_DICT:
        raise Error(
            "TypeError: unhashable type: " + py_repr(type_name(doc, key))
        )
    if kind != PY_STR:
        return MISSING
    return doc.get(node, doc.text(key))


def _items(doc: PyJson, node: Int) raises -> List[Tuple[String, Int]]:
    """Return `sorted(mapping.items())` for a dict read from JSON."""
    if doc.kind(node) != PY_DICT:
        raise Error(
            "AttributeError: "
            + py_repr(type_name(doc, node))
            + " object has no attribute 'items'"
        )
    var keys = List[String]()
    for index in range(doc.length(node)):
        keys.append(doc.key(node, index))
    var out = List[Tuple[String, Int]]()
    for index in sorted_order(keys):
        out.append((keys[index], doc.value(node, index)))
    return out^


struct Inputs(Movable):
    """The index and the URLs, read into the manifest's document."""

    var index: Int
    """The index value."""
    var urls: Int
    """The URL map, or an empty dict without `--urls`."""

    def __init__(out self, index: Int, urls: Int):
        """Hold the values.

        Args:
            index: The index value.
            urls: The URL map.
        """
        self.index = index
        self.urls = urls


def read_inputs(
    mut doc: PyJson, index_path: String, urls_path: String
) raises -> Inputs:
    """Read the index and the URL file into the manifest's document.

    Args:
        doc: The manifest's document.
        index_path: The index file.
        urls_path: The URL file, or empty for none.

    Returns:
        Their values in `doc`.

    Raises:
        Error: An `OSError` or a decoding error.
    """
    var index_doc = read_json_text(read_file(index_path))
    var index = doc.adopt(index_doc, index_doc.root)
    var urls = doc.new_dict()
    if urls_path.byte_length() > 0:
        var urls_doc = read_json_text(read_file(urls_path))
        urls = doc.adopt(urls_doc, urls_doc.root)
    return Inputs(index, urls)


def _archive_entry(
    mut doc: PyJson,
    entry_id: String,
    kind: String,
    title: String,
    provenance: String,
    changes: String,
    forward: Bool,
    folder: String,
    model_name: String,
    item: Int,
    url: Int,
) raises -> Int:
    """Return one CARLA entry whose one file is an archive."""
    var entry = doc.new_dict()
    doc.set(entry, "id", doc.new_str(entry_id))
    doc.set(entry, "kind", doc.new_str(kind))
    doc.set(entry, "title", doc.new_str(title))
    doc.set(entry, "license", doc.new_str("CC-BY-4.0"))
    doc.set(entry, "author", doc.new_str(CARLA_AUTHOR))
    doc.set(entry, "source", doc.new_str(SOURCE))
    doc.set(entry, "provenance", doc.new_str(provenance))
    doc.set(entry, "changes", doc.new_str(changes))
    if forward:
        doc.set(entry, "forward", doc.new_str("+x"))
    var archive = doc.new_dict()
    doc.set(archive, "role", doc.new_str("archive"))
    doc.set(archive, "url", url if url != MISSING else doc.new_none())
    doc.set(archive, "sha256", subscript(doc, item, "sha256"))
    doc.set(archive, "path", doc.new_str(folder + ".zip"))
    var extract = doc.new_list()
    for member in items_of(doc, subscript(doc, item, "members")):
        var record = doc.new_dict()
        var model = (
            doc.kind(member) == PY_STR and doc.text(member) == model_name
        )
        doc.set(record, "role", doc.new_str("model" if model else "support"))
        doc.set(record, "member", member)
        doc.set(
            record, "path", doc.new_str(folder + "/" + value_str(doc, member))
        )
        doc.append(extract, record)
    doc.set(archive, "extract", extract)
    var files = doc.new_list()
    doc.append(files, archive)
    doc.set(entry, "files", files)
    return entry


def vehicle_entry(
    mut doc: PyJson, vehicle_id: String, item: Int, url: Int
) raises -> Int:
    """Return the manifest entry of one vehicle.

    Args:
        doc: The document.
        vehicle_id: The blueprint id.
        item: The vehicle's index record: its sum and its members.
        url: The zip's URL, or `MISSING` for null.

    Returns:
        The entry.

    Raises:
        Error: Python's error text for a record without its keys.
    """
    var folder = "carla/vehicles/" + vehicle_id
    return _archive_entry(
        doc,
        PREFIX + vehicle_id,
        "model",
        title_of(vehicle_id) + " (CARLA)",
        VEHICLE_PROVENANCE,
        VEHICLE_CHANGES,
        True,
        folder,
        vehicle_id + ".gltf",
        item,
        url,
    )


def town_of(doc: PyJson, package: Int) raises -> String:
    """Return a package's town name, as CARLA spells it: `Town02`.

    Args:
        doc: The document.
        package: The package's index record.

    Returns:
        The name of its OpenDRIVE map, without `.xodr`.

    Raises:
        Error: `SystemExit: ` text when no member is a map, or Python's
            error text for a member that is not a str.
    """
    var members = subscript(doc, package, "members")
    var copy = doc.copy()
    for member in items_of(copy, members):
        if copy.kind(member) != PY_STR:
            raise Error(
                "AttributeError: "
                + py_repr(type_name(copy, member))
                + " object has no attribute 'endswith'"
            )
        var text = copy.text(member)
        if text.endswith(".xodr"):
            return String(text[byte = : text.byte_length() - 5])
    raise Error("SystemExit: a town package has no OpenDRIVE map")


def town_entry(
    mut doc: PyJson, package_id: String, item: Int, url: Int
) raises -> Int:
    """Return the manifest entry of one town.

    Args:
        doc: The document.
        package_id: The package id, `carla.town.<town>`.
        item: The package's index record.
        url: The zip's URL, or `MISSING` for null.

    Returns:
        The entry.

    Raises:
        Error: `SystemExit: ` text for a package without a map, or
            Python's error text for a record without its keys.
    """
    var title = town_of(doc, item) + " (CARLA)"
    return _archive_entry(
        doc,
        package_id,
        "town",
        title,
        TOWN_PROVENANCE,
        TOWN_CHANGES,
        False,
        "carla/towns/" + package_id,
        package_id + ".glb",
        item,
        url,
    )


def _carried_url(
    mut doc: PyJson, manifest: Int, entry_id: String, item: Int, urls: Int
) raises -> Int:
    """Return the URL of a new entry: from the URL file, or the old entry's
    when its sum is unchanged, or `MISSING`."""
    if doc.kind(urls) != PY_DICT:
        raise Error(
            "AttributeError: "
            + py_repr(type_name(doc, urls))
            + " object has no attribute 'get'"
        )
    var url = _dict_get(doc, urls, subscript(doc, item, "zip"))
    if url != MISSING and not doc.is_none(url):
        return url
    var entries = doc.get(manifest, "entries")
    var previous = MISSING
    for index in range(doc.length(entries)):
        var entry = doc.item(entries, index)
        if doc.text(doc.get(entry, "id")) == entry_id:
            previous = entry
    if previous == MISSING:
        return MISSING
    var file = doc.item(doc.get(previous, "files"), 0)
    if py_equal(
        doc, doc.get(file, "sha256"), doc, subscript(doc, item, "sha256")
    ):
        var old = doc.get(file, "url")
        return old if not doc.is_none(old) else MISSING
    return MISSING


def _clear_removed(
    mut doc: PyJson, manifest: Int, old_ids: List[String]
) raises:
    """Set to null each binding that names an entry no longer present."""
    var entries = doc.get(manifest, "entries")
    var present = List[String]()
    for index in range(doc.length(entries)):
        present.append(doc.text(doc.get(doc.item(entries, index), "id")))
    var bindings = doc.get(manifest, "bindings")
    for index in range(doc.length(bindings)):
        var value = doc.value(bindings, index)
        if doc.kind(value) != PY_STR:
            continue
        var name = doc.text(value)
        var removed = False
        for old in old_ids:
            if old == name:
                removed = True
        for kept in present:
            if kept == name:
                removed = False
        if removed:
            doc.set(bindings, doc.key(bindings, index), doc.new_none())


def _ids(doc: PyJson, manifest: Int) -> List[String]:
    """Return the ids of a checked manifest's entries."""
    var out = List[String]()
    var entries = doc.get(manifest, "entries")
    for index in range(doc.length(entries)):
        try:
            out.append(doc.text(doc.get(doc.item(entries, index), "id")))
        except:
            pass
    return out^


def _hosted(doc: PyJson, added: List[Int]) raises -> Int:
    """Return how many new entries have a URL."""
    var count = 0
    for entry in added:
        var file = doc.item(doc.get(entry, "files"), 0)
        if truthy(doc, doc.get(file, "url")):
            count += 1
    return count


def update_vehicles(
    manifest_path: String, index_path: String, urls_path: String
) raises -> String:
    """Replace the manifest's vehicles with the index's, as
    `manifest_vehicles.py` does.

    Args:
        manifest_path: The manifest to rewrite.
        index_path: The vehicles' index.
        urls_path: A file that maps a zip name to its URL, or empty.

    Returns:
        The summary line, with its newline.

    Raises:
        Error: Python's error text, such as an `OSError`, a decoding
            error or `ManifestError`.
    """
    var doc = load_manifest(manifest_path)
    var manifest = doc.root
    var inputs = read_inputs(doc, index_path, urls_path)
    var old_ids = _ids(doc, manifest)
    var entries = doc.get(manifest, "entries")
    var kept = doc.new_list()
    for index in range(doc.length(entries)):
        var entry = doc.item(entries, index)
        if not doc.text(doc.get(entry, "id")).startswith(PREFIX + "vehicle."):
            doc.append(kept, entry)
    var added = List[Int]()
    var records = _items(doc, inputs.index)
    for record in records:
        var url = _carried_url(
            doc, manifest, PREFIX + record[0], record[1], inputs.urls
        )
        added.append(vehicle_entry(doc, record[0], record[1], url))
    for entry in added:
        doc.append(kept, entry)
    doc.set(manifest, "entries", kept)
    if doc.get(manifest, "bindings") == MISSING:
        doc.set(manifest, "bindings", doc.new_dict())
    var bindings = doc.get(manifest, "bindings")
    var index_ids = List[String]()
    for position in range(doc.length(inputs.index)):
        index_ids.append(doc.key(inputs.index, position))
    for vehicle_id in index_ids:
        doc.set(bindings, vehicle_id, doc.new_str(PREFIX + vehicle_id))
    for pair in materialize[ALIASES]():
        for vehicle_id in index_ids:
            if vehicle_id == pair[1]:
                doc.set(bindings, pair[0], doc.new_str(PREFIX + pair[1]))
                break
    # The other keys keep their order; the vehicles follow, sorted, and
    # the vehicle wildcard comes after them.
    var keys = List[String]()
    for position in range(doc.length(bindings)):
        keys.append(doc.key(bindings, position))
    var vehicles = List[String]()
    for key in keys:
        if key.startswith("vehicle.") and key != "vehicle.*":
            vehicles.append(key)
    var order = List[String]()
    for key in keys:
        if not key.startswith("vehicle.") and not key.startswith("walker."):
            order.append(key)
    for position in sorted_order(vehicles):
        order.append(vehicles[position])
    order.append("vehicle.*")
    for key in keys:
        if key.startswith("walker."):
            order.append(key)
    var rebuilt = doc.new_dict()
    for key in order:
        var value = doc.get(bindings, key)
        doc.set(rebuilt, key, value if value != MISSING else doc.new_none())
    doc.set(manifest, "bindings", rebuilt)
    _clear_removed(doc, manifest, old_ids)
    save_manifest(doc, manifest, manifest_path)
    return (
        String(len(added))
        + " vehicles written, "
        + String(_hosted(doc, added))
        + " with a URL, "
        + String(doc.length(rebuilt))
        + " bindings\n"
    )


def update_towns(
    manifest_path: String, index_path: String, urls_path: String
) raises -> String:
    """Replace the manifest's towns with the index's, as
    `manifest_towns.py` does.

    Args:
        manifest_path: The manifest to rewrite.
        index_path: The towns' index.
        urls_path: A file that maps a zip name to its URL, or empty.

    Returns:
        The summary line, with its newline.

    Raises:
        Error: Python's error text, such as an `OSError`, a decoding
            error, `ManifestError` or `SystemExit` for a package without a
            map.
    """
    var doc = load_manifest(manifest_path)
    var manifest = doc.root
    var inputs = read_inputs(doc, index_path, urls_path)
    var old_ids = _ids(doc, manifest)
    var entries = doc.get(manifest, "entries")
    var kept = doc.new_list()
    for index in range(doc.length(entries)):
        var entry = doc.item(entries, index)
        if not doc.text(doc.get(entry, "id")).startswith(TOWN_PREFIX):
            doc.append(kept, entry)
    var added = List[Int]()
    if doc.get(manifest, "bindings") == MISSING:
        doc.set(manifest, "bindings", doc.new_dict())
    var bindings = doc.get(manifest, "bindings")
    var records = _items(doc, inputs.index)
    for record in records:
        var url = _carried_url(doc, manifest, record[0], record[1], inputs.urls)
        added.append(town_entry(doc, record[0], record[1], url))
        doc.set(
            bindings, "town." + town_of(doc, record[1]), doc.new_str(record[0])
        )
    for entry in added:
        doc.append(kept, entry)
    doc.set(manifest, "entries", kept)
    _clear_removed(doc, manifest, old_ids)
    save_manifest(doc, manifest, manifest_path)
    return (
        String(len(added))
        + " towns written, "
        + String(_hosted(doc, added))
        + " with a URL\n"
    )
