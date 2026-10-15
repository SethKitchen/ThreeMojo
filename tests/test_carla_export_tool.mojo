# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CARLA export tools: zips, manifest families and Poly Haven entries.

`assets/carla/tools/test_export_manifests.py` is ported here: a family of
packages replaces its entries and clears only the bindings to removed
entries. The zip and index goldens are the bytes and text that
`assets/carla/tools/export/zip_packages.py` wrote for the same inputs. The
Poly Haven tool reads a stub API through a stub `curl`, so no test opens a
network connection.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._carla_tool_files import (
    get_text,
    put,
    put_bytes,
    remove_tree,
    scratch,
    stub_program,
)
from tools._carla_assets import (
    Transport,
    default_manifest,
    entries_of,
    load_manifest,
    manifest_text,
    quote_json,
    save_manifest,
    sha256_bytes,
)
from tools._carla_files import read_file
from tools._carla_manifests import (
    capitalize,
    title_of,
    update_towns,
    update_vehicles,
)
from tools._carla_zip import (
    DosTime,
    ZipMember,
    python_zip,
    read_directory,
    read_member,
)
from tools._md5 import Md5, md5_hex
from tools._python_json import MISSING, PyJson
from tools.carla_export_polyhaven_entries import ASSETS, write_entries
from tools.carla_export_zip_packages import zip_packages


def q(text: String) -> String:
    """Return a str as JSON text."""
    return quote_json(text)


# --- MD5 and zips -------------------------------------------------------------------


def test_md5_matches_rfc_1321() raises:
    assert_equal(md5_hex("".as_bytes()), "d41d8cd98f00b204e9800998ecf8427e")
    assert_equal(md5_hex("abc".as_bytes()), "900150983cd24fb0d6963f7d28e17f72")
    assert_equal(
        md5_hex("message digest".as_bytes()),
        "f96b697d7cb7938d525a2f31aaf161d0",
    )
    var data = List[UInt8]()
    for index in range(100000):
        data.append(UInt8((index * 7919) % 251))
    assert_equal(md5_hex(Span(data)), "5b199f6801aabe1639729401eee6d93c")
    var parts = Md5()
    parts.update(Span(data)[:63])
    parts.update(Span(data)[63:64])
    parts.update(Span(data)[64:1000])
    parts.update(Span(data)[1000:])
    assert_equal(parts^.hexdigest(), "5b199f6801aabe1639729401eee6d93c")


def _members() -> List[ZipMember]:
    """Return the golden archive's members."""
    var block = List[UInt8]()
    for _ in range(3):
        for index in range(256):
            block.append(UInt8(index))
    var out = List[ZipMember]()
    out.append(ZipMember("a.txt", List[UInt8]("hello hello hello".as_bytes())))
    out.append(ZipMember("dir/é.bin", block^))
    out.append(ZipMember("empty", List[UInt8]()))
    return out^


def test_zips_are_the_bytes_python_zipfile_writes() raises:
    var deflated = python_zip(_members(), DosTime(2025, 9, 16, 0, 0, 0), True)
    assert_equal(len(deflated), 580)
    assert_equal(
        sha256_bytes(Span(deflated)),
        "62cb475120a68fd3a6207cd5a242490e2c6710b52ef95731357e2b03d75eb525",
    )
    var stored = python_zip(_members(), DosTime(2024, 1, 2, 3, 4, 6), False)
    assert_equal(len(stored), 1075)
    assert_equal(
        sha256_bytes(Span(stored)),
        "7900ed034546482c8b75e5337499ee53b67189007f4fb95a1a9ffd569d1a4659",
    )


def test_zips_read_back_as_zipfile_reads_them() raises:
    for deflated in [False, True]:
        var data = python_zip(
            _members(), DosTime(2025, 9, 16, 0, 0, 0), deflated
        )
        var items = read_directory(Span(data))
        assert_equal(len(items), 3)
        assert_equal(items[1].name, "dir/\u00e9.bin")
        var members = _members()
        for index in range(3):
            assert_true(
                read_member(Span(data), items[index]) == members[index].data
            )
    # A name without flag bit 11 is code page 437.
    var raw = python_zip(
        [ZipMember("aX", List[UInt8]())], DosTime(2025, 9, 16, 0, 0, 0), False
    )
    for index in range(len(raw) - 1):
        if raw[index] == 0x61 and raw[index + 1] == 0x58:
            raw[index + 1] = 0x80
    var named = read_directory(Span(raw))
    assert_equal(named[0].name, "aÇ")
    assert_equal(len(read_member(Span(raw), named[0])), 0)
    var data = python_zip(
        [ZipMember("ab", List[UInt8]("stored bytes".as_bytes()))],
        DosTime(2025, 9, 16, 0, 0, 0),
        False,
    )
    data[30 + 2 + 3] ^= 0xFF
    var items = read_directory(Span(data))
    try:
        _ = read_member(Span(data), items[0])
        assert_true(False, "a damaged member was read")
    except error:
        assert_equal(
            String(error), "zipfile.BadZipFile: Bad CRC-32 for file 'ab'"
        )
    try:
        _ = read_directory("not a zip at all".as_bytes())
        assert_true(False, "a file that is no archive was read")
    except error:
        assert_equal(
            String(error), "zipfile.BadZipFile: File is not a zip file"
        )


def test_zip_packages_writes_python_s_zips_index_and_summary() raises:
    var root = scratch()
    var packages = root + "/packages"
    var png = String()
    for _ in range(100):
        png += "\x89PNG"
    var block = List[UInt8]()
    for index in range(200):
        block.append(UInt8(index))
    for vehicle_id in ["vehicle.b.x", "vehicle.a.y"]:
        var folder = packages + "/" + vehicle_id
        put(folder + "/" + vehicle_id + ".gltf", String('{"asset": 1}') * 40)
        var picture = List[UInt8]()
        for _ in range(100):
            picture.extend([0x89, 0x50, 0x4E, 0x47])
        put_bytes(folder + "/tex/c.png", picture)
        put_bytes(folder + "/b.bin", block)
    put(packages + "/note.txt", "x")
    var summary = zip_packages(root, "packages", "index.json", root)
    assert_equal(summary, "2 zips, 0.0 MB, largest 0.0 MB\n")
    assert_equal(
        get_text(root + "/upload/index.json"),
        (
            '{\n "vehicle.a.y": {\n  "zip": "vehicle.a.y.zip",\n  "sha256":'
            ' "cc4177f3bee42c13c21053f961c78f2297e750501fcfe166f39cba4a88baa83c",\n'
            '  "bytes": 545,\n  "members": [\n   "b.bin",\n  '
            ' "vehicle.a.y.gltf",\n   "tex/c.png"\n  ]\n },\n "vehicle.b.x":'
            ' {\n  "zip": "vehicle.b.x.zip",\n  "sha256":'
            ' "b77ea502c3618516eba3e91409c76ccbd014bfd9996d67c41c2dae1411ba865d",\n'
            '  "bytes": 545,\n  "members": [\n   "b.bin",\n  '
            ' "vehicle.b.x.gltf",\n   "tex/c.png"\n  ]\n }\n}'
        ),
    )
    assert_equal(
        sha256_bytes(Span(read_file(root + "/upload/vehicle.a.y.zip"))),
        "cc4177f3bee42c13c21053f961c78f2297e750501fcfe166f39cba4a88baa83c",
    )
    remove_tree(root)


def test_zip_packages_without_packages_writes_an_empty_index_and_fails() raises:
    var root = scratch()
    put(root + "/packages/note.txt", "x")
    try:
        _ = zip_packages(root, "packages", "index.json", root)
        assert_true(False, "an empty index has no largest zip")
    except error:
        assert_equal(
            String(error), "ValueError: max() iterable argument is empty"
        )
    assert_equal(get_text(root + "/upload/index.json"), "{}")
    try:
        _ = zip_packages(root, "missing", "index.json", root)
        assert_true(False, "a missing folder is an error")
    except error:
        assert_true(String(error).startswith("FileNotFoundError: [Errno 2]"))
    remove_tree(root)


# --- Manifest families -------------------------------------------------------------------


def test_titles_spell_makes_and_models() raises:
    assert_equal(title_of("vehicle.audi.a2"), "Audi A2")
    assert_equal(title_of("vehicle.tesla.model3"), "Tesla Model 3")
    assert_equal(title_of("vehicle.ford.crown_xl_ab"), "Ford Crown XL AB")
    assert_equal(title_of("vehicle.nissan.patrol_2021"), "Nissan Patrol 2021")
    assert_equal(capitalize("hELLO"), "Hello")
    try:
        _ = title_of("vehicle.x")
        assert_true(False, "two parts are too few")
    except error:
        assert_equal(
            String(error),
            "ValueError: not enough values to unpack (expected 3, got 2)",
        )


def _carla_entry(identifier: String, folder: String, model: String) -> String:
    """Return a CARLA entry with one pinned archive, as JSON text."""
    return (
        '{"id": '
        + q(
            "carla."
            + identifier if not identifier.startswith("carla.") else identifier
        )
        + ', "kind": "'
        + ("town" if identifier.find("town") >= 0 else "model")
        + '", "title": "T", "license": "CC-BY-4.0", "author": "CARLA Team'
        ' (Computer Vision Center)", "source":'
        ' "https://github.com/carla-simulator/carla/releases/tag/0.9.16",'
        ' "provenance": "CARLA 0.9.16 fixture", "changes": "c",'
        + (' "forward": "+x",' if identifier.find("town") < 0 else "")
        + ' "files": [{"role": "archive", "url": "https://example.org/'
        + identifier
        + '.zip", "sha256": "'
        + String("a") * 64
        + '", "path": "'
        + folder
        + ".zip"
        + '", "extract": [{"role": "model", "member": '
        + q(model)
        + ', "path": '
        + q(folder + "/" + model)
        + "}]}]}"
    )


def _replace_family(towns: Bool) raises:
    """Run the Python test's family replacement for vehicles or towns."""
    var ids: List[String]
    var keys: List[String]
    var prefix: String
    if towns:
        ids = ["carla.town.town01", "carla.town.town02"]
        keys = ["town.Town01", "town.Town02"]
        prefix = "town."
    else:
        ids = ["vehicle.audi.a2", "vehicle.tesla.model3"]
        keys = ids.copy()
        prefix = "vehicle."
    var unrelated = (
        '{"id": "unrelated", "kind": "model", "forward": "+x", "license":'
        ' "CC0-1.0", "author": "Test", "source": "https://example.org/model",'
        ' "provenance": "Fixture only.", "files": [{"role": "model", "path":'
        ' "unrelated.glb", "url": null, "sha256": "'
        + String("a") * 64
        + '"}]}'
    )
    for retain in [1, 0]:
        var root = scratch()
        var entries = List[String]()
        var packages = List[String]()
        var entry_ids = List[String]()
        for index in range(2):
            var identifier = ids[index]
            var model: String
            var folder: String
            var members: String
            if towns:
                folder = "carla/towns/" + identifier
                model = identifier + ".glb"
                members = (
                    q(model) + ", " + q("Town0" + String(index + 1) + ".xodr")
                )
            else:
                folder = "carla/vehicles/" + identifier
                model = identifier + ".gltf"
                members = q(model)
            entries.append(_carla_entry(identifier, folder, model))
            entry_ids.append(
                identifier if towns else String("carla.") + identifier
            )
            packages.append(
                q(identifier)
                + ': {"zip": '
                + q(identifier + ".zip")
                + ', "sha256": "'
                + String("a") * 64
                + '", "members": ['
                + members
                + "]}"
            )
        var bindings = (
            "{"
            + q(keys[0])
            + ": "
            + q(entry_ids[0])
            + ", "
            + q(keys[1])
            + ": "
            + q(entry_ids[1])
            + ", "
            + q(prefix + "alias_kept")
            + ": "
            + q(entry_ids[0])
            + ", "
            + q(prefix + "alias_removed")
            + ": "
            + q(entry_ids[1])
            + ', "prop.unrelated": "unrelated"}'
        )
        var original = PyJson.parse(
            '{"format": 1, "entries": ['
            + ", ".join(entries)
            + ", "
            + unrelated
            + '], "bindings": '
            + bindings
            + "}"
        )
        var path = root + "/manifest.json"
        save_manifest(original, original.root, path)
        var index_text = String("{")
        if retain:
            index_text += packages[0]
        put(root + "/index.json", index_text + "}")
        if towns:
            _ = update_towns(path, root + "/index.json", "")
        else:
            _ = update_vehicles(path, root + "/index.json", "")
        var result = load_manifest(path)
        var kept = List[String]()
        for entry in entries_of(result, result.root):
            kept.append(result.text(result.get(entry, "id")))
        assert_equal(len(kept), 1 + retain)
        assert_equal(kept[0], "unrelated")
        if retain:
            assert_equal(kept[1], entry_ids[0])
            var entry = entries_of(result, result.root)[1]
            var file = result.item(result.get(entry, "files"), 0)
            assert_equal(
                result.text(result.get(file, "url")),
                "https://example.org/" + ids[0] + ".zip",
            )
        var after = result.get(result.root, "bindings")
        var before = original.get(original.root, "bindings")
        for position in range(original.length(before)):
            var key = original.key(before, position)
            var value = original.text(original.value(before, position))
            var now = result.get(after, key)
            var present = False
            for name in kept:
                if name == value:
                    present = True
            if present:
                assert_equal(result.text(now), value, key)
            else:
                assert_true(result.is_none(now), key)
        remove_tree(root)


def test_vehicle_removal_clears_only_bindings_to_removed_entries() raises:
    _replace_family(False)


def test_town_removal_clears_only_bindings_to_removed_entries() raises:
    _replace_family(True)


def test_vehicles_keep_their_url_take_a_new_one_or_wait_for_hosting() raises:
    var root = scratch()
    var path = root + "/manifest.json"
    var real = load_manifest(default_manifest())
    var tesla_sum = String()
    for entry in entries_of(real, real.root):
        if real.text(real.get(entry, "id")) == "carla.vehicle.tesla.model3":
            var file = real.item(real.get(entry, "files"), 0)
            tesla_sum = real.text(real.get(file, "sha256"))
    save_manifest(real, real.root, path)
    put(
        root + "/index.json",
        '{"vehicle.tesla.model3": {"zip": "vehicle.tesla.model3.zip",'
        ' "sha256": "'
        + tesla_sum
        + '", "members": ["vehicle.tesla.model3.gltf"]},'
        ' "vehicle.new.thing_xl":'
        ' {"zip": "vehicle.new.thing_xl.zip", "sha256": "'
        + String("c") * 64
        + '", "members": ["vehicle.new.thing_xl.gltf", "t.png"]},'
        ' "vehicle.audi.a2": {"zip": "vehicle.audi.a2.zip", "sha256": "'
        + String("b") * 64
        + '", "members": ["vehicle.audi.a2.gltf"]}}',
    )
    put(
        root + "/urls.json",
        '{"vehicle.audi.a2.zip": "https://drive.google.com/file/d/X/view"}',
    )
    var summary = update_vehicles(
        path, root + "/index.json", root + "/urls.json"
    )
    var result = load_manifest(path)
    var bindings = result.get(result.root, "bindings")
    assert_equal(
        summary,
        "3 vehicles written, 2 with a URL, "
        + String(result.length(bindings))
        + " bindings\n",
    )
    var urls = Dict[String, String]()
    var titles = Dict[String, String]()
    for entry in entries_of(result, result.root):
        var entry_id = result.text(result.get(entry, "id"))
        var file = result.item(result.get(entry, "files"), 0)
        var url = result.get(file, "url")
        urls[entry_id] = "null" if result.is_none(url) else result.text(url)
        titles[entry_id] = (
            result.text(result.get(entry, "title")) if result.get(
                entry, "title"
            )
            != MISSING else String()
        )
    assert_equal(
        urls["carla.vehicle.audi.a2"], "https://drive.google.com/file/d/X/view"
    )
    assert_true(urls["carla.vehicle.tesla.model3"].startswith("https://"))
    assert_equal(urls["carla.vehicle.new.thing_xl"], "null")
    assert_equal(titles["carla.vehicle.new.thing_xl"], "New Thing XL (CARLA)")
    assert_false("carla.vehicle.mini.cooper_s" in urls)
    # The other keys keep their order; the vehicles follow, sorted, then
    # the wildcard and the walkers.
    var order = List[String]()
    for position in range(result.length(bindings)):
        order.append(result.key(bindings, position))
    var wildcard = -1
    for position in range(len(order)):
        if order[position] == "vehicle.*":
            wildcard = position
    assert_true(wildcard > 0)
    for position in range(wildcard + 1, len(order)):
        assert_true(order[position].startswith("walker."))
    assert_true(result.is_none(result.get(bindings, "vehicle.mini.cooper_s")))
    assert_equal(
        result.text(result.get(bindings, "vehicle.new.thing_xl")),
        "carla.vehicle.new.thing_xl",
    )
    remove_tree(root)


def test_a_town_package_needs_its_opendrive_map() raises:
    var root = scratch()
    var path = root + "/manifest.json"
    var real = load_manifest(default_manifest())
    save_manifest(real, real.root, path)
    put(
        root + "/towns.json",
        '{"carla.town.x": {"zip": "z", "sha256": "'
        + String("a") * 64
        + '", "members": ["carla.town.x.glb"]}}',
    )
    try:
        _ = update_towns(path, root + "/towns.json", "")
        assert_true(False, "a town without a map was written")
    except error:
        assert_equal(
            String(error), "SystemExit: a town package has no OpenDRIVE map"
        )
    assert_equal(get_text(path), manifest_text(real, real.root))
    remove_tree(root)


# --- Poly Haven ------------------------------------------------------------------------------


def _api_curl(folder: String) raises -> Transport:
    """Return a `curl` that answers each URL from a file in `folder`.

    A URL's file is its text after `://`, with each `/` as `_`. A URL
    without a file answers 404.
    """
    var program = folder + "/bin/curl"
    stub_program(
        program,
        "while [ $# -gt 0 ]; do\n"
        + '  case "$1" in\n'
        + "    --dump-header) h=$2; shift;;\n"
        + "    --output) o=$2; shift;;\n"
        + "    --url) u=$2; shift;;\n"
        + "  esac\n"
        + "  shift\n"
        + "done\n"
        + "key=$(printf '%s' \"${u#*://}\" | tr '/' '_')\n"
        + "if [ -f '"
        + folder
        + '\'/"$key" ]; then\n'
        + "  printf 'HTTP/1.1 200 OK\\r\\nContent-Type:"
        + ' application/octet-stream\\r\\n\\r\\n\' > "$h"\n'
        + "  cp '"
        + folder
        + '\'/"$key" "$o"\n'
        + "else\n"
        + "  printf 'HTTP/1.1 404 Not Found\\r\\n\\r\\n' > \"$h\"\n"
        + "fi\n"
        + "exit 0\n",
    )
    return Transport(program, 0.0)


def _serve(folder: String, name: String, text: String) raises -> String:
    """Serve a file at `https://dl.test/<name>`; return its `url`/`md5`
    JSON."""
    put(folder + "/dl.test_" + name, text)
    return (
        '{"url": "https://dl.test/'
        + name
        + '", "md5": "'
        + md5_hex(text.as_bytes())
        + '"}'
    )


def _api(folder: String, bad: String = "") raises:
    """Write the stub API's answers for every asset."""
    for asset in materialize[ASSETS]():
        var asset_id = asset[0]
        var kind = asset[1]
        put(
            folder + "/api.test_info_" + asset_id,
            '{"name": '
            + q(asset_id + " é")
            + ', "authors": {"Rob": "All", "Dimitrios": "Photo"},'
            + ' "dimensions": [2500, 1000]}',
        )
        var files: String
        if kind == "texture_set":
            files = (
                '{"Diffuse": {"2k": {"jpg": '
                + _serve(folder, asset_id + "_diff.jpg", asset_id + " diffuse")
                + '}}, "nor_gl": {"2k": {"jpg": '
                + _serve(folder, asset_id + "_nor.jpg", asset_id + " normal")
                + '}}, "Displacement": {"2k": {"png": '
                + _serve(folder, asset_id + "_disp.png", asset_id + " height")
                + "}}}"
            )
        elif kind == "hdri":
            files = (
                '{"hdri": {"2k": {"hdr": '
                + _serve(folder, asset_id + ".hdr", asset_id + " sky")
                + "}}}"
            )
        else:
            var gltf = _serve(folder, asset_id + ".gltf", asset_id + " model")
            files = (
                '{"gltf": {"2k": {"gltf": '
                + String(gltf[byte = : gltf.byte_length() - 1])
                + ', "include": {"textures/z.jpg": '
                + _serve(folder, asset_id + "_z.jpg", "zz")
                + ', "b.bin": '
                + _serve(folder, asset_id + "_b.bin", "bin")
                + "}}}}}"
            )
        if asset_id == bad:
            files = files.replace('"md5": "', '"md5": "0')
        put(folder + "/api.test_files_" + asset_id, files)


def test_poly_haven_entries_are_read_fetched_checked_and_pinned() raises:
    var root = scratch()
    var path = root + "/manifest.json"
    var real = load_manifest(default_manifest())
    save_manifest(real, real.root, path)
    _api(root + "/web")
    var out = String()
    write_entries(
        path,
        root + "/cache",
        "2k",
        "2026-10-15",
        "https://api.test",
        _api_curl(root + "/web"),
        out,
    )
    assert_true(out.startswith("pinned    asphalt_02/asphalt_02_diff.jpg\n"))
    assert_true(
        out.endswith("10 Poly Haven entries written; dropped []\n"), out
    )
    var result = load_manifest(path)
    var entries = entries_of(result, result.root)
    var first = entries[0]
    assert_equal(result.text(result.get(first, "id")), "asphalt_02")
    assert_equal(result.text(result.get(first, "title")), "asphalt_02 é")
    assert_equal(result.text(result.get(first, "author")), "Rob, Dimitrios")
    assert_equal(result.text(result.get(first, "tile_meters")), "2.5")
    assert_true(
        result.text(result.get(first, "provenance")).find("read on 2026-10-15;")
        >= 0
    )
    var file = result.item(result.get(first, "files"), 0)
    assert_equal(
        result.text(result.get(file, "sha256")),
        sha256_bytes("asphalt_02 diffuse".as_bytes()),
    )
    var model = entries[8]
    assert_equal(result.text(result.get(model, "forward")), "+z")
    var support = result.item(result.get(model, "files"), 1)
    assert_equal(
        result.text(result.get(support, "path")), "island_tree_01/b.bin"
    )
    assert_equal(get_text(root + "/cache/island_tree_01/b.bin"), "bin")
    remove_tree(root)


def test_poly_haven_refuses_a_file_whose_md5_differs() raises:
    var root = scratch()
    var path = root + "/manifest.json"
    var real = load_manifest(default_manifest())
    save_manifest(real, real.root, path)
    var before = get_text(path)
    _api(root + "/web", "concrete_pavement")
    var out = String()
    try:
        write_entries(
            path,
            root + "/cache",
            "2k",
            "2026-10-15",
            "https://api.test",
            _api_curl(root + "/web"),
            out,
        )
        assert_true(False, "a file that differs from its MD5 was pinned")
    except error:
        var text = String(error)
        assert_true(text.startswith("FetchError: https://dl.test/"), text)
        assert_true(text.find(" is not the API's 0") >= 0, text)
    assert_equal(get_text(path), before)
    remove_tree(root)


def test_poly_haven_stops_at_an_http_error() raises:
    var root = scratch()
    var path = root + "/manifest.json"
    var real = load_manifest(default_manifest())
    save_manifest(real, real.root, path)
    put(root + "/web/.keep", "")
    var out = String()
    try:
        write_entries(
            path,
            root + "/cache",
            "2k",
            "2026-10-15",
            "https://api.test",
            _api_curl(root + "/web"),
            out,
        )
        assert_true(False, "a missing API answer was accepted")
    except error:
        assert_equal(
            String(error), "urllib.error.HTTPError: HTTP Error 404: Not Found"
        )
    assert_equal(out, "")
    remove_tree(root)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
