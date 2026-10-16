# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CARLA asset manifest and its fetch tool, on file:// fixtures.

These are the tests of `assets/carla/tools/test_carla_assets.py`, ported to
`tools/carla_assets.mojo`. Every expected sum is computed here from the
fixture's own bytes. A download that would leave the machine runs a stub
`curl` that logs each run, so a test can show that no URL was opened. A
race that the Python tests made with `unittest.mock` is made here by
`StageHooks`, at the same moment of staging.
"""

from std.os.path import exists, isdir, islink
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._carla_tool_files import (
    get_text,
    hard_link,
    make_fifo,
    names,
    put,
    put_bytes,
    read_link,
    remove_dir,
    remove_tree,
    rename,
    runs,
    scratch,
    stub_curl,
    symlink,
    tree,
    unlink,
)
from tools._carla_assets import (
    Transport,
    binding_kind,
    cached,
    carla_release,
    check_manifest,
    credits,
    default_manifest,
    direct_url,
    entries_of,
    fetch,
    fetch_file,
    is_sum,
    load_manifest,
    manifest_text,
    quote_json,
    sha256_bytes,
    verify,
)
from tools._carla_files import (
    path_exists,
    read_file,
    write_all,
    write_file,
)
from tools._carla_zip import DosTime, ZipMember, python_zip
from tools._python_json import MISSING, PY_STR, PyJson
from tools.carla_assets import (
    NoHooks,
    Outcome,
    StageHooks,
    parse_arguments,
    run,
    stage_archive,
    stage_render,
)


# --- Fixtures -----------------------------------------------------------------------


def q(text: String) -> String:
    """Return a str as JSON text."""
    return quote_json(text)


def sum_of(text: String) -> String:
    """Return the SHA-256 of a text's bytes."""
    return sha256_bytes(text.as_bytes())


def texture(
    url: String,
    digest: String,
    entry_id: String = "asphalt",
    path: String = "asphalt/color.jpg",
) -> String:
    """Return a texture set entry as JSON text; `url` and `digest` are JSON
    values, such as `null`."""
    return (
        '{"id": '
        + q(entry_id)
        + ', "kind": "texture_set", "license": "CC0-1.0", "author": "A.'
        ' Scanner", "source": "https://example.org/asphalt", "provenance": "A'
        ' test fixture.", "tile_meters": 4, "files": [{"role": "albedo",'
        ' "url": '
        + url
        + ', "sha256": '
        + digest
        + ', "path": '
        + q(path)
        + "}]}"
    )


def manifest_of(entries: List[String], bindings: String = "{}") -> String:
    """Return a manifest as JSON text."""
    return (
        '{"format": 1, "entries": ['
        + ", ".join(entries)
        + '], "bindings": '
        + bindings
        + "}"
    )


def check_text(text: String) raises:
    """Check a manifest given as JSON text."""
    var doc = PyJson.parse(text)
    check_manifest(doc, doc.root)


def refused(text: String) raises -> Bool:
    """Return whether the manifest is refused with a `ManifestError`."""
    try:
        check_text(text)
    except error:
        return String(error).startswith("ManifestError: ")
    return False


def zip_of(names_: List[String], datas: List[String]) raises -> List[UInt8]:
    """Return a stored archive, as `zipfile.ZipFile(..., 'w')` writes one."""
    var members = List[ZipMember]()
    for index in range(len(names_)):
        members.append(
            ZipMember(names_[index], List[UInt8](datas[index].as_bytes()))
        )
    return python_zip(members, DosTime(2024, 1, 2, 3, 4, 6), False)


def offline_transport(folder: String) raises -> Transport:
    """Return a transport whose `curl` logs each run and fails."""
    return Transport(
        stub_curl(folder, "", "", "", 7, "curl: (7) network access", 99), 0.0
    )


def cli(arguments: List[String], transport: Transport) raises -> Outcome:
    """Run the command line without hooks."""
    var hooks = NoHooks()
    return run(arguments, transport, hooks)


def read_text(path: String) raises -> String:
    """Return a file's text."""
    return get_text(path)


struct Fixture(Movable):
    """A temporary folder with source files, a cache and a stub `curl`."""

    var root: String
    var source: String
    var cache: String
    var net: String

    def __init__(out self) raises:
        self.root = scratch()
        self.source = self.root + "/source"
        self.cache = self.root + "/cache"
        self.net = self.root + "/net"
        put(self.source + "/.keep", "")
        unlink_quiet(self.source + "/.keep")

    def file(self, name: String, data: String) raises -> String:
        """Write a source file and return its file:// URL as JSON text."""
        put(self.source + "/" + name, data)
        return q("file://" + self.source + "/" + name)

    def file_bytes(self, name: String, data: List[UInt8]) raises -> String:
        """Write a binary source file and return its URL as JSON text."""
        put_bytes(self.source + "/" + name, data)
        return q("file://" + self.source + "/" + name)

    def close(self) raises:
        remove_tree(self.root)


def unlink_quiet(path: String):
    """Remove a file and ignore an error."""
    try:
        unlink(path)
    except:
        pass


# --- The manifest's rules -------------------------------------------------------------


def test_repository_manifest_keeps_the_rules() raises:
    var doc = load_manifest(default_manifest())
    var bindings = doc.get(doc.root, "bindings")
    for key in [
        "surface.road",
        "surface.sidewalk",
        "surface.curb",
        "surface.wall",
        "ground.grass",
        "ground.paving",
        "sky.clear",
        "vehicle.*",
        "walker.*",
    ]:
        assert_true(doc.find(bindings, key) != MISSING, key)


def test_a_good_manifest_passes() raises:
    check_text(
        manifest_of(
            [texture(q("https://example.org/a.jpg"), "null")],
            '{"surface.road": "asphalt", "vehicle.*": null}',
        )
    )


def _variant(
    path: List[String], value: String, remove: Bool = False
) raises -> String:
    """Return the good texture manifest with one member changed."""
    var doc = PyJson.parse(
        manifest_of([texture(q("https://example.org/a.jpg"), "null")])
    )
    var node = doc.item(doc.get(doc.root, "entries"), 0)
    for index in range(len(path) - 1):
        var key = path[index]
        if key == "0":
            node = doc.item(node, 0)
        else:
            node = doc.get(node, key)
    var last = path[len(path) - 1]
    if remove:
        doc.remove(node, last)
    else:
        var other = PyJson.parse(value)
        doc.set(node, last, doc.adopt(other, other.root))
    return manifest_text(doc, doc.root)


def test_each_broken_rule_is_refused() raises:
    var cases = List[String]()
    cases.append(_variant(["kind"], '"sound"'))
    cases.append(_variant(["license"], '"GPL-3.0"'))
    cases.append(_variant(["author"], '" "'))
    cases.append(_variant(["provenance"], "", True))
    cases.append(_variant(["colour"], '"red"'))
    cases.append(_variant(["tile_meters"], "0"))
    cases.append(_variant(["tile_meters"], "true"))
    cases.append(_variant(["files"], "[]"))
    cases.append(_variant(["files", "0", "role"], '"hdri"'))
    cases.append(_variant(["files", "0", "role"], '"normal"'))
    cases.append(_variant(["files", "0", "path"], '"../escape.jpg"'))
    cases.append(_variant(["files", "0", "path"], '"/abs.jpg"'))
    cases.append(_variant(["files", "0", "url"], '"http://example.org/a.jpg"'))
    cases.append(_variant(["files", "0", "sha256"], '"ABC"'))
    cases.append(_variant(["files", "0", "url"], "null"))
    cases.append(_variant(["files", "0", "url"], "7"))
    cases.append('{"format": 2, "entries": []}')
    var good = texture(q("https://example.org/a.jpg"), "null")
    cases.append(manifest_of([good, good]))
    cases.append(manifest_of([good], '{"surface.road": "nothing"}'))
    cases.append(manifest_of([good], '{"sky.clear": "asphalt"}'))
    var model = (
        '{"id": "car", "kind": "model", "license": "CC-BY-4.0", "author": "B",'
        ' "source": "https://example.org/car", "provenance": "p", "files":'
        ' [{"role": "MODEL", "url": "https://example.org/car.glb", "sha256":'
        ' null, "path": "car.glb"}]'
    )
    cases.append(manifest_of([model.replace("MODEL", "model") + "}"]))
    cases.append(
        manifest_of(
            [
                model.replace("MODEL", "support")
                .replace('"car"', '"town"')
                .replace('"model"', '"town"')
                + "}"
            ]
        )
    )
    cases.append(
        manifest_of(
            [model.replace("MODEL", "model") + ', "forward": "+x"}'],
            '{"town.Town02": "car"}',
        )
    )
    cases.append(
        manifest_of(
            [
                good.replace(
                    (
                        '"role": "albedo", "url": "https://example.org/a.jpg",'
                        ' "sha256": null, "path": "asphalt/color.jpg"'
                    ),
                    (
                        '"role": "archive", "url": "https://example.org/a.zip",'
                        ' "sha256": null, "path": "a.zip", "extract": []'
                    ),
                )
            ]
        )
    )
    for text in cases:
        assert_true(refused(text), text)


def test_tile_sizes_must_remain_positive_finite_float32() raises:
    for value in [
        "NaN",
        "Infinity",
        "-Infinity",
        "1e100",
        "1e-100",
        "0",
        "-1",
        "true",
        '"2"',
        # Past the largest double: `float(int)` overflows. JSON cannot hold
        # the 10,001 digits of the Python test's 10**10000.
        "1" + String("0") * 400,
    ]:
        var text = _variant(["tile_meters"], value)
        with assert_raises(contains="Float32 tile_meters"):
            check_text(text)
    for value in ["1", "0.25", "1e-40", "3.4028234663852886e38"]:
        check_text(_variant(["tile_meters"], value))


def test_manifest_format_is_numeric_not_boolean() raises:
    for value in ["true", "false"]:
        assert_true(refused('{"format": ' + value + ', "entries": []}'))
    check_text('{"format": 1.0, "entries": []}')


def test_a_town_passes() raises:
    check_text(
        manifest_of(
            [
                '{"id": "town02", "kind": "town", "license": "CC-BY-4.0",'
                ' "author": "B", "source": "https://example.org/town",'
                ' "provenance": "p", "files": [{"role": "model", "url":'
                ' "https://example.org/t.gltf", "sha256": null, "path":'
                ' "t.gltf"}]}'
            ],
            '{"town.Town02": "town02"}',
        )
    )


def test_every_repository_carla_entry_keeps_attribution_and_integrity() raises:
    # Issue #309: each converted CARLA archive keeps its exact sum, its
    # upstream release, its changes, the CARLA Team credit and the
    # CC BY 4.0 link, whatever host serves it.
    var doc = load_manifest(default_manifest())
    var entries = entries_of(doc, doc.root)
    var attribution = credits(doc, entries, False)
    var carla = 0
    var models = 0
    var towns = 0
    for entry in entries:
        var entry_id = doc.text(doc.get(entry, "id"))
        if not entry_id.startswith("carla."):
            continue
        carla += 1
        var kind = doc.text(doc.get(entry, "kind"))
        models += 1 if kind == "model" else 0
        towns += 1 if kind == "town" else 0
        assert_equal(doc.text(doc.get(entry, "license")), "CC-BY-4.0")
        assert_equal(
            doc.text(doc.get(entry, "author")),
            "CARLA Team (Computer Vision Center)",
        )
        var source = doc.text(doc.get(entry, "source"))
        var release = carla_release(source)
        assert_true(Bool(release), entry_id)
        assert_true(
            doc.text(doc.get(entry, "provenance")).find(
                "CARLA " + release.value()
            )
            >= 0
        )
        var changes = doc.text(doc.get(entry, "changes"))
        assert_true(String(changes.strip()).byte_length() > 0)
        var files = doc.get(entry, "files")
        var archives = 0
        for index in range(doc.length(files)):
            var item = doc.item(files, index)
            if doc.text(doc.get(item, "role")) == "archive":
                archives += 1
                assert_true(is_sum(doc, doc.get(item, "sha256")))
        assert_equal(archives, 1)
        var line = (
            '"'
            + doc.text(doc.get(entry, "title"))
            + '" by CARLA Team (Computer Vision Center), '
            + source
            + ", CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)."
            + " Changes: "
            + changes
        )
        assert_true(attribution.find(line) >= 0, entry_id)
    assert_equal(carla, 47)
    assert_equal(models, 41)
    assert_equal(towns, 6)


def _audi() raises -> String:
    """Return the repository's `carla.vehicle.audi.a2` entry as JSON."""
    var doc = load_manifest(default_manifest())
    for entry in entries_of(doc, doc.root):
        if doc.text(doc.get(entry, "id")) == "carla.vehicle.audi.a2":
            return manifest_text(doc, entry)
    raise Error("no audi")


def _audi_with(
    key: String, value: String, remove: Bool = False
) raises -> String:
    """Return a manifest of the audi entry with one member changed."""
    var doc = PyJson.parse(manifest_of([_audi()]))
    var entry = doc.item(doc.get(doc.root, "entries"), 0)
    if key == "sha256":
        var item = doc.item(doc.get(entry, "files"), 0)
        doc.set(item, "sha256", doc.new_none())
    elif remove:
        doc.remove(entry, key)
    else:
        var other = PyJson.parse(value)
        doc.set(entry, key, doc.adopt(other, other.root))
    return manifest_text(doc, doc.root)


def test_a_carla_entry_that_loses_credit_release_changes_or_sum_is_refused() raises:
    check_text(manifest_of([_audi()]))
    var page = "https://github.com/carla-simulator/carla/releases/tag/"
    var cases: List[String] = [
        _audi_with("license", '"CC0-1.0"'),
        _audi_with("author", '"Someone Else"'),
        _audi_with("source", '"https://carla.org/"'),
        _audi_with("source", q(page + "latest")),
        _audi_with("provenance", '"A CARLA vehicle."'),
        _audi_with("source", q(page + "0.9.15")),
        _audi_with("changes", "", True),
        _audi_with("changes", '" "'),
        _audi_with("changes", "7"),
        _audi_with("sha256", ""),
    ]
    for text in cases:
        assert_true(refused(text))


def test_carla_provenance_matches_a_complete_release_name() raises:
    var page = "https://github.com/carla-simulator/carla/releases/tag/"
    with assert_raises(contains="provenance must name CARLA 0.9.1"):
        check_text(_audi_with("source", q(page + "0.9.1")))
    for provenance in [
        "CARLA 0.9.160",
        "CARLA 0.9.16.1",
        "CARLA 0.9.16.rc1",
        "CARLA 0.9.16rc1",
        "CARLA 0.9.16-rc1",
        "CARLA 0.9.16+build.1",
        "NOTCARLA 0.9.16",
        "CARLA 0.9.16_extra",
    ]:
        assert_true(
            refused(_audi_with("provenance", q(provenance))), provenance
        )
    for provenance in [
        "CARLA 0.9.16",
        "CARLA 0.9.16's own vehicle",
        "CARLA 0.9.16. Converted assets.",
        "(CARLA 0.9.16), converted.",
    ]:
        check_text(_audi_with("provenance", q(provenance)))


def test_a_file_not_hosted_yet_passes_with_its_sum() raises:
    check_text(manifest_of([texture("null", q(sum_of("scan")))]))


def test_a_drive_share_link_becomes_its_download() raises:
    var download = "https://drive.usercontent.google.com/download?export=download&confirm=t&id="
    assert_equal(
        direct_url("https://drive.google.com/file/d/1aB-c_9/view?usp=sharing"),
        download + "1aB-c_9",
    )
    assert_equal(
        direct_url("https://drive.google.com/open?id=1aB-c_9"),
        download + "1aB-c_9",
    )
    assert_equal(
        direct_url("https://drive.google.com/uc?export=download&id=XY"),
        download + "XY",
    )
    assert_equal(
        direct_url("https://example.org/a.zip"), "https://example.org/a.zip"
    )


def test_binding_kinds() raises:
    assert_equal(binding_kind("surface.road"), "texture_set")
    assert_equal(binding_kind("facade.brick"), "texture_set")
    assert_equal(binding_kind("sky.overcast"), "hdri")
    assert_equal(binding_kind("vehicle.tesla.model3"), "model")
    assert_equal(binding_kind("town.Town02"), "town")


# --- Fetch --------------------------------------------------------------------------------


def _fetch(
    mut doc: PyJson,
    fixture: Fixture,
    ids: List[String] = List[String](),
    pin: Bool = False,
    offline: Bool = False,
) raises -> List[String]:
    """Fetch and return each `entry path status` line."""
    var lines = List[String]()
    for line in fetch(
        doc,
        doc.root,
        fixture.cache,
        ids,
        pin,
        offline,
        offline_transport(fixture.net),
    ):
        lines.append(line.entry_id + " " + line.path + " " + line.status)
    return lines^


def _verify(
    doc: PyJson, fixture: Fixture, ids: List[String] = List[String]()
) raises -> List[String]:
    """Verify and return each `path status` line."""
    var lines = List[String]()
    for line in verify(doc, doc.root, fixture.cache, ids):
        lines.append(line.path + " " + line.status)
    return lines^


comptime DATA = "photoscanned asphalt"


def test_fetch_verifies_then_keeps() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var doc = PyJson.parse(manifest_of([texture(url, q(sum_of(DATA)))]))
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg fetched")
    assert_equal(read_text(fixture.cache + "/asphalt/color.jpg"), DATA)
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg kept")
    assert_equal(_verify(doc, fixture)[0], "asphalt/color.jpg ok")
    assert_true(cached(doc, entries_of(doc, doc.root)[0], fixture.cache))
    assert_equal(runs(fixture.net), 0)
    fixture.close()


def test_a_wrong_sum_leaves_nothing() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var doc = PyJson.parse(
        manifest_of([texture(url, q(sum_of("something else")))])
    )
    with assert_raises(contains="FetchError"):
        _ = _fetch(doc, fixture)
    assert_equal(len(names(fixture.cache + "/asphalt")), 0)
    assert_false(cached(doc, entries_of(doc, doc.root)[0], fixture.cache))
    fixture.close()


def test_a_verified_file_is_never_overwritten() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var doc = PyJson.parse(manifest_of([texture(url, q(sum_of(DATA)))]))
    _ = _fetch(doc, fixture)
    # The source changes; the manifest now expects the new bytes.
    put(fixture.source + "/asphalt.jpg", "new bytes")
    var item = doc.item(doc.get(entries_of(doc, doc.root)[0], "files"), 0)
    doc.set(item, "sha256", doc.new_str(sum_of("new bytes")))
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg mismatch")
    assert_equal(read_text(fixture.cache + "/asphalt/color.jpg"), DATA)
    assert_equal(_verify(doc, fixture)[0], "asphalt/color.jpg mismatch")
    fixture.close()


def test_unpinned_needs_pin() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var doc = PyJson.parse(manifest_of([texture(url, "null")]))
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg unpinned")
    assert_false(exists(fixture.cache + "/asphalt/color.jpg"))
    assert_equal(
        _fetch(doc, fixture, pin=True)[0], "asphalt asphalt/color.jpg pinned"
    )
    var item = doc.item(doc.get(entries_of(doc, doc.root)[0], "files"), 0)
    assert_equal(doc.text(doc.get(item, "sha256")), sum_of(DATA))
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg kept")
    fixture.close()


def test_a_cached_unpinned_file_is_pinned_from_disk() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var doc = PyJson.parse(manifest_of([texture(url, "null")]))
    put(fixture.cache + "/asphalt/color.jpg", "placed by hand")
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg unpinned")
    assert_equal(_verify(doc, fixture)[0], "asphalt/color.jpg unpinned")
    assert_equal(
        _fetch(doc, fixture, pin=True)[0], "asphalt asphalt/color.jpg pinned"
    )
    var item = doc.item(doc.get(entries_of(doc, doc.root)[0], "files"), 0)
    assert_equal(doc.text(doc.get(item, "sha256")), sum_of("placed by hand"))
    fixture.close()


def test_missing_source_and_unknown_id() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var gone = url.replace('.jpg"', '.jpg.gone"')
    var doc = PyJson.parse(manifest_of([texture(gone, q(sum_of(DATA)))]))
    with assert_raises(contains="No such file or directory"):
        _ = _fetch(doc, fixture)
    assert_equal(_verify(doc, fixture)[0], "asphalt/color.jpg missing")
    with assert_raises(contains="ManifestError: no entry 'nothing'"):
        _ = _fetch(doc, fixture, ["nothing"])
    fixture.close()


def test_a_file_not_hosted_yet_is_placed_by_hand() raises:
    var fixture = Fixture()
    var doc = PyJson.parse(manifest_of([texture("null", q(sum_of(DATA)))]))
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg unhosted")
    assert_equal(_verify(doc, fixture)[0], "asphalt/color.jpg missing")
    put(fixture.cache + "/asphalt/color.jpg", DATA)
    assert_equal(_fetch(doc, fixture)[0], "asphalt asphalt/color.jpg kept")
    fixture.close()


def test_a_web_page_in_place_of_the_file_is_refused() raises:
    var fixture = Fixture()
    var url = fixture.file("sign-in.html", "<html>Sign in</html>")
    var doc = PyJson.parse(manifest_of([texture(url, "null")]))
    with assert_raises(contains="the host sent a web page"):
        _ = _fetch(doc, fixture, pin=True)
    assert_equal(len(names(fixture.cache + "/asphalt")), 0)
    # The first bytes are enough, whatever the name says.
    var renamed = fixture.file("sign-in.bin", "  \n<!DOCTYPE HTML><p>x")
    doc = PyJson.parse(manifest_of([texture(renamed, "null")]))
    with assert_raises(contains="the host sent a web page"):
        _ = _fetch(doc, fixture, pin=True)
    fixture.close()


def test_only_named_entries_are_fetched() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var doc = PyJson.parse(
        manifest_of(
            [
                texture(url, q(sum_of(DATA))),
                texture(url, q(sum_of(DATA)), "other", "other/color.jpg"),
            ]
        )
    )
    var report = _fetch(doc, fixture, ["other"])
    assert_equal(len(report), 1)
    assert_equal(report[0], "other other/color.jpg fetched")
    assert_false(exists(fixture.cache + "/asphalt/color.jpg"))
    fixture.close()


def _archive_entry(url: String, digest: String, members: String) -> String:
    """Return a texture entry whose one file is an archive."""
    return texture(url, "null").replace(
        '{"role": "albedo", "url": '
        + url
        + ', "sha256": null, "path": "asphalt/color.jpg"}',
        '{"role": "archive", "url": '
        + url
        + ', "sha256": '
        + digest
        + ', "path": "scan.zip", "extract": ['
        + members
        + "]}",
    )


def test_an_archive_is_verified_then_extracted() raises:
    var fixture = Fixture()
    var data = zip_of(
        ["Scan_Color.jpg", "Scan_NormalGL.jpg"],
        ["color texels", "normal texels"],
    )
    var url = fixture.file_bytes("scan.zip", data)
    var members = (
        '{"role": "albedo", "member": "Scan_Color.jpg", "path":'
        ' "scan/color.jpg"}, {"role": "normal", "member":'
        ' "Scan_NormalGL.jpg", "path": "scan/normal.jpg"}'
    )
    var doc = PyJson.parse(
        manifest_of([_archive_entry(url, q(sha256_bytes(Span(data))), members)])
    )
    check_manifest(doc, doc.root)
    var entry = entries_of(doc, doc.root)[0]
    assert_equal(_fetch(doc, fixture)[0], "asphalt scan.zip fetched")
    assert_equal(read_text(fixture.cache + "/scan/color.jpg"), "color texels")
    assert_true(cached(doc, entry, fixture.cache))
    # A member removed by hand comes back from the kept archive.
    unlink(fixture.cache + "/scan/normal.jpg")
    assert_false(cached(doc, entry, fixture.cache))
    assert_equal(_fetch(doc, fixture)[0], "asphalt scan.zip kept")
    assert_equal(read_text(fixture.cache + "/scan/normal.jpg"), "normal texels")
    var extract = doc.get(doc.item(doc.get(entry, "files"), 0), "extract")
    doc.set(doc.item(extract, 1), "member", doc.new_str("Missing.jpg"))
    unlink(fixture.cache + "/scan/normal.jpg")
    with assert_raises(contains="the archive has no member 'Missing.jpg'"):
        _ = _fetch(doc, fixture)
    fixture.close()


def test_corrupt_extracted_member_is_reported_and_never_overwritten() raises:
    var fixture = Fixture()
    var data = zip_of(["color.jpg"], ["original pixels"])
    var url = fixture.file_bytes("checked.zip", data)
    var doc = PyJson.parse(
        manifest_of(
            [
                _archive_entry(
                    url,
                    q(sha256_bytes(Span(data))),
                    (
                        '{"role": "albedo", "member": "color.jpg", "path":'
                        ' "scan/color.jpg"}'
                    ),
                )
            ]
        )
    )
    _ = _fetch(doc, fixture)
    var extracted = fixture.cache + "/scan/color.jpg"
    assert_equal(_verify(doc, fixture)[1], "scan/color.jpg ok")
    put(extracted, "corrupted pixels")
    assert_equal(_verify(doc, fixture)[1], "scan/color.jpg mismatch")
    with assert_raises(contains="extracted member differs"):
        _ = _fetch(doc, fixture)
    assert_equal(read_text(extracted), "corrupted pixels")
    unlink(extracted)
    assert_equal(_verify(doc, fixture)[1], "scan/color.jpg missing")
    _ = _fetch(doc, fixture)
    assert_equal(read_text(extracted), "original pixels")
    fixture.close()


def test_command_line_pins_into_the_manifest() raises:
    var fixture = Fixture()
    var url = fixture.file("asphalt.jpg", DATA)
    var path = fixture.root + "/manifest.json"
    put(path, manifest_of([texture(url, "null")]))
    var common: List[String] = ["--manifest", path, "--cache", fixture.cache]
    var transport = offline_transport(fixture.net)
    var out = String()
    for command in ["check", "fetch", "fetch --pin", "verify", "status"]:
        var arguments = common.copy()
        for word in command.split(" "):
            arguments.append(String(word))
        var outcome = cli(arguments, transport)
        assert_equal(outcome.status, 0, command)
        out += outcome.out
    assert_true(out.find("pinned") >= 0)
    assert_true(out.find("cached") >= 0)
    var saved = load_manifest(path)
    var item = saved.item(
        saved.get(entries_of(saved, saved.root)[0], "files"), 0
    )
    assert_equal(saved.text(saved.get(item, "sha256")), sum_of(DATA))
    put(fixture.cache + "/asphalt/color.jpg", "tampered")
    var verify_args = common.copy()
    verify_args.append("verify")
    assert_equal(cli(verify_args, transport).status, 1)
    var fetch_args = common.copy()
    fetch_args.append("fetch")
    assert_equal(cli(fetch_args, transport).status, 1)
    fixture.close()


# --- Recovery --------------------------------------------------------------------------


struct Recovery(Movable):
    """A pinned archive at an https URL, and a cache to recover it into."""

    var fixture: Fixture
    var data: List[UInt8]
    var archive: String
    var extracted: String

    def __init__(out self) raises:
        self.fixture = Fixture()
        self.data = zip_of(["color.jpg"], ["original pixels"])
        self.archive = self.fixture.cache + "/scan.zip"
        self.extracted = self.fixture.cache + "/scan/color.jpg"

    def manifest(self, digest: Bool = True) -> String:
        """Return the manifest text."""
        return manifest_of(
            [
                _archive_entry(
                    q("https://example.org/scan.zip"),
                    q(sha256_bytes(Span(self.data))) if digest else "null",
                    (
                        '{"role": "albedo", "member": "color.jpg", "path":'
                        ' "scan/color.jpg"}'
                    ),
                )
            ]
        )

    def place(self) raises:
        """Put the pinned archive in the cache."""
        put_bytes(self.archive, self.data)

    def cli(
        self, words: List[String], text: String, transport: Transport
    ) raises -> Outcome:
        """Run the command line on a manifest file that must not change."""
        var path = self.fixture.root + "/manifest.json"
        put(path, text)
        var arguments: List[String] = [
            "--manifest",
            path,
            "--cache",
            self.fixture.cache,
        ]
        arguments.extend(words.copy())
        var outcome = cli_run(arguments, transport)
        assert_equal(read_text(path), text)
        return outcome^


def cli_run(arguments: List[String], transport: Transport) raises -> Outcome:
    """Run the command line without hooks."""
    var hooks = NoHooks()
    return run(arguments, transport, hooks)


def test_offline_extracts_then_repairs_only_missing_members_without_urls() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    var text = setup.manifest()
    setup.place()
    assert_equal(
        setup.cli(["fetch", "asphalt", "--offline"], text, net).status, 0
    )
    assert_equal(read_text(setup.extracted), "original pixels")
    assert_equal(
        setup.cli(["verify", "asphalt", "--strict"], text, net).status, 0
    )
    unlink(setup.extracted)
    assert_equal(
        setup.cli(["verify", "--strict", "asphalt"], text, net).status, 1
    )
    assert_equal(
        setup.cli(["fetch", "--offline", "asphalt"], text, net).status, 0
    )
    assert_equal(read_text(setup.extracted), "original pixels")
    assert_equal(
        setup.cli(["verify", "asphalt", "--strict"], text, net).status, 0
    )
    assert_equal(runs(setup.fixture.net), 0)
    assert_true(read_file(setup.archive) == setup.data)
    setup.fixture.close()


def test_offline_missing_archives_fail_without_creating_cache_or_opening_urls() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    for url in ["https://example.org/scan.zip", "null", "SOURCE"]:
        var text = setup.manifest()
        var replaced = q(
            "file://" + setup.fixture.source
        ) if url == "SOURCE" else (q(url) if url != "null" else String("null"))
        text = text.replace(q("https://example.org/scan.zip"), replaced)
        var outcome = setup.cli(["fetch", "--offline"], text, net)
        assert_equal(outcome.status, 1)
        assert_true(outcome.out.find("missing") >= 0)
        assert_false(exists(setup.fixture.cache))
    assert_equal(runs(setup.fixture.net), 0)
    setup.fixture.close()


def test_offline_corrupt_archive_is_unchanged_and_never_extracted() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    put(setup.archive, "corrupt archive")
    var outcome = setup.cli(["fetch", "--offline"], setup.manifest(), net)
    assert_equal(outcome.status, 1)
    assert_true(outcome.out.find("mismatch") >= 0)
    assert_equal(read_text(setup.archive), "corrupt archive")
    assert_false(exists(setup.extracted))
    assert_equal(runs(setup.fixture.net), 0)
    setup.fixture.close()


def test_offline_pinned_nonarchive_checks_bytes_without_opening_urls() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    var data = "plain texture pixels"
    var text = manifest_of(
        [texture(q("https://example.org/color.jpg"), q(sum_of(data)))]
    )
    var target = setup.fixture.cache + "/asphalt/color.jpg"
    assert_equal(setup.cli(["fetch", "--offline"], text, net).status, 1)
    put(target, data)
    var outcome = setup.cli(["fetch", "--offline"], text, net)
    assert_equal(outcome.status, 0)
    assert_true(outcome.out.find("kept") >= 0)
    assert_equal(setup.cli(["verify", "--strict"], text, net).status, 0)
    put(target, "corrupt texture pixels")
    outcome = setup.cli(["fetch", "--offline"], text, net)
    assert_equal(outcome.status, 1)
    assert_true(outcome.out.find("mismatch") >= 0)
    assert_equal(setup.cli(["verify", "--strict"], text, net).status, 1)
    assert_equal(runs(setup.fixture.net), 0)
    assert_equal(read_text(target), "corrupt texture pixels")
    setup.fixture.close()


def test_offline_corrupt_member_is_unchanged_and_fails_verification() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    setup.place()
    var doc = PyJson.parse(setup.manifest())
    _ = fetch(
        doc, doc.root, setup.fixture.cache, List[String](), False, True, net
    )
    put(setup.extracted, "corrupt pixels")
    with assert_raises(contains="extracted member differs"):
        _ = fetch(
            doc, doc.root, setup.fixture.cache, List[String](), False, True, net
        )
    assert_equal(
        setup.cli(["verify", "--strict"], setup.manifest(), net).status, 1
    )
    assert_equal(runs(setup.fixture.net), 0)
    assert_equal(read_text(setup.extracted), "corrupt pixels")
    setup.fixture.close()


def test_offline_unpinned_files_are_never_trusted() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    var text = setup.manifest(False)
    for present in [False, True]:
        if present:
            setup.place()
        var outcome = setup.cli(["fetch", "--offline"], text, net)
        assert_equal(outcome.status, 1)
        assert_true(outcome.out.find("unpinned") >= 0)
        assert_equal(setup.cli(["verify", "--strict"], text, net).status, 1)
        assert_equal(setup.cli(["verify"], text, net).status, 0)
        assert_false(exists(setup.extracted))
    assert_equal(runs(setup.fixture.net), 0)
    setup.fixture.close()


def test_offline_cannot_pin_through_api_or_cli() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    var doc = PyJson.parse(setup.manifest(False))
    with assert_raises(contains="cannot pin"):
        _ = fetch(
            doc, doc.root, setup.fixture.cache, List[String](), True, True, net
        )
    var item = doc.item(doc.get(entries_of(doc, doc.root)[0], "files"), 0)
    with assert_raises(contains="cannot pin"):
        _ = fetch_file(doc, item, setup.fixture.cache, True, True, net)
    var outcome = setup.cli(
        ["fetch", "--offline", "--pin"], setup.manifest(False), net
    )
    assert_equal(outcome.status, 2)
    assert_true(
        outcome.err.find("argument --pin: not allowed with argument --offline")
        >= 0
    )
    assert_true(doc.is_none(doc.get(item, "sha256")))
    assert_false(exists(setup.fixture.cache))
    setup.fixture.close()


def test_strict_verification_is_opt_in_and_selection_excludes_other_missing_files() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    var text = manifest_of(
        [
            _archive_entry(
                q("https://example.org/scan.zip"),
                q(sha256_bytes(Span(setup.data))),
                (
                    '{"role": "albedo", "member": "color.jpg", "path":'
                    ' "scan/color.jpg"}'
                ),
            ),
            texture("null", q(sum_of("other")), "other", "other.jpg"),
        ]
    )
    var doc = PyJson.parse(text)
    check_manifest(doc, doc.root)
    assert_equal(setup.cli(["verify"], text, net).status, 0)
    assert_equal(setup.cli(["verify", "--strict"], text, net).status, 1)
    setup.place()
    assert_equal(
        setup.cli(["fetch", "--offline", "asphalt"], text, net).status, 0
    )
    assert_equal(
        setup.cli(["verify", "--strict", "asphalt"], text, net).status, 0
    )
    assert_equal(setup.cli(["verify", "--strict"], text, net).status, 1)
    assert_equal(setup.cli(["fetch", "--offline"], text, net).status, 1)
    var lines = _verify(doc, setup.fixture, ["asphalt"])
    assert_equal(len(lines), 2)
    assert_equal(lines[0], "scan.zip ok")
    assert_equal(lines[1], "scan/color.jpg ok")
    setup.fixture.close()


def test_unknown_selection_is_rejected_before_any_cache_work() raises:
    var setup = Recovery()
    var net = offline_transport(setup.fixture.net)
    put(setup.archive, "not the archive")
    var doc = PyJson.parse(setup.manifest())
    with assert_raises(contains="no entry"):
        _ = fetch(
            doc,
            doc.root,
            setup.fixture.cache,
            ["asphalt", "unknown"],
            False,
            True,
            net,
        )
    with assert_raises(contains="no entry"):
        _ = verify(doc, doc.root, setup.fixture.cache, ["asphalt", "unknown"])
    # No file was hashed or extracted: the corrupt archive was not seen.
    assert_false(exists(setup.extracted))
    setup.fixture.close()


def _download(setup: Recovery, transport: Transport) raises -> List[String]:
    """Fetch the recovery manifest through a stub host."""
    var doc = PyJson.parse(setup.manifest())
    var lines = List[String]()
    for line in fetch(
        doc,
        doc.root,
        setup.fixture.cache,
        List[String](),
        False,
        False,
        transport,
    ):
        lines.append(line.status)
    assert_equal(
        manifest_text(doc, doc.root),
        manifest_text(
            PyJson.parse(setup.manifest()), PyJson.parse(setup.manifest()).root
        ),
    )
    return lines^


def test_permission_quota_and_missing_http_responses_leave_no_download() raises:
    for pair in [
        ("403", "Forbidden"),
        ("429", "Too Many Requests"),
        ("404", "Not Found"),
    ]:
        var setup = Recovery()
        var stub = stub_curl(
            setup.fixture.net,
            "HTTP/1.1 " + pair[0] + " " + pair[1],
            "text/html",
            "<html>no</html>",
        )
        with assert_raises(contains="HTTP Error " + pair[0] + ": " + pair[1]):
            _ = _download(setup, Transport(stub, 0.0))
        assert_equal(runs(setup.fixture.net), 1)
        assert_equal(len(names(setup.fixture.cache)), 0)
        setup.fixture.close()


def test_html_permission_and_quota_pages_are_refused_even_if_mislabeled() raises:
    for content_type in ["text/html", "application/octet-stream"]:
        for body in [
            "<html>Sign in for permission</html>",
            "<html>Download quota exceeded</html>",
        ]:
            var setup = Recovery()
            var stub = stub_curl(
                setup.fixture.net, "HTTP/1.1 200 OK", content_type, body
            )
            with assert_raises(contains="FetchError"):
                _ = _download(setup, Transport(stub, 0.0))
            assert_equal(len(names(setup.fixture.cache)), 0)
            setup.fixture.close()


def test_drive_interstitial_pages_are_named_as_web_pages_even_if_mislabeled() raises:
    # Drive sends a page, not the file, for a file it does not share, for a
    # used-up download quota and for its virus-scan confirmation.
    for body in [
        "<!DOCTYPE html><html><title>Google Drive - Virus scan warning</title>",
        "\n  <html><body>Google Drive - Quota exceeded</body></html>",
        "<HTML><title>Sign in - Google Accounts</title>",
    ]:
        var setup = Recovery()
        var stub = stub_curl(
            setup.fixture.net,
            "HTTP/1.1 200 OK",
            "application/octet-stream",
            body,
        )
        try:
            _ = _download(setup, Transport(stub, 0.0))
            assert_true(False, "a web page was accepted")
        except error:
            var text = String(error)
            assert_true(text.find("web page") >= 0 and text.find("quota") >= 0)
        assert_equal(len(names(setup.fixture.cache)), 0)
        setup.fixture.close()


def test_a_proxy_that_refuses_the_tunnel_is_not_tried_again() raises:
    for code in ["403", "407"]:
        var setup = Recovery()
        var stub = stub_curl(
            setup.fixture.net,
            "",
            "",
            "",
            56,
            "curl: (56) CONNECT tunnel failed, response " + code,
            99,
        )
        with assert_raises(contains="CONNECT tunnel failed, response " + code):
            _ = _download(setup, Transport(stub, 100.0))
        assert_equal(runs(setup.fixture.net), 1)
        assert_equal(len(names(setup.fixture.cache)), 0)
        setup.fixture.close()


def test_a_dropped_connection_is_tried_again_then_verified() raises:
    var setup = Recovery()
    var stub = stub_curl(
        setup.fixture.net,
        "HTTP/1.1 200 OK",
        "application/zip",
        "",
        56,
        "curl: (56) Recv failure: Connection reset by peer",
        1,
        setup.data.copy(),
    )
    var lines = _download(setup, Transport(stub, 0.0))
    assert_equal(lines[0], "fetched")
    assert_equal(runs(setup.fixture.net), 2)
    assert_equal(read_text(setup.extracted), "original pixels")
    setup.fixture.close()


def test_synthetic_clean_cache_download_verifies_before_extracting() raises:
    var setup = Recovery()
    var stub = stub_curl(
        setup.fixture.net,
        "HTTP/1.1 200 OK",
        "application/zip",
        "",
        data=setup.data.copy(),
    )
    assert_equal(_download(setup, Transport(stub, 0.0))[0], "fetched")
    assert_equal(runs(setup.fixture.net), 1)
    assert_true(read_file(setup.archive) == setup.data)
    assert_equal(read_text(setup.extracted), "original pixels")
    var net = offline_transport(setup.fixture.root + "/other")
    assert_equal(
        setup.cli(["verify", "--strict"], setup.manifest(), net).status, 0
    )
    setup.fixture.close()


# --- Staging renders -----------------------------------------------------------------


comptime RENDER = "\x89PNG\r\n\x1a\n exact fixture bytes"
comptime OTHER = "animation bytes"


struct Stage(Movable):
    """A custom manifest, two renders, and the new directory to stage."""

    var fixture: Fixture
    var output: String
    var manifest_path: String
    var manifest_bytes: String
    var render: String
    var other: String

    def __init__(out self) raises:
        self.fixture = Fixture()
        self.output = self.fixture.root + "/distribution"
        self.manifest_path = self.fixture.root + "/custom-manifest.json"
        var free = texture(q("https://example.org/asphalt.jpg"), "null")
        var scanned = (
            texture("null", q(sum_of("archive")), "brick", "brick.jpg")
            .replace('"CC0-1.0"', '"CC-BY-4.0"')
            .replace('"A. Scanner"', '"Custom Author"')
            .replace(
                '"tile_meters": 4',
                (
                    '"tile_meters": 4, "title": "Custom Brick", "changes":'
                    ' "Converted for this historical render."'
                ),
            )
        )
        self.manifest_bytes = " \r\n" + manifest_of([free, scanned]) + "\r\n\t"
        put(self.manifest_path, self.manifest_bytes)
        self.render = self.fixture.source + "/render.png"
        put(self.render, RENDER)
        self.other = self.fixture.source + "/other.apng"
        put(self.other, OTHER)

    def run[
        H: StageHooks
    ](
        self, mut hooks: H, renders: List[String] = List[String]()
    ) raises -> Outcome:
        """Run `stage-render` and return what it printed."""
        var arguments: List[String] = [
            "--manifest",
            self.manifest_path,
            "--cache",
            self.fixture.cache,
            "stage-render",
            "--output",
            self.output,
        ]
        if len(renders) == 0:
            arguments.append(self.render)
        else:
            arguments.extend(renders.copy())
        return run(arguments, offline_transport(self.fixture.net), hooks)

    def plain(self, renders: List[String] = List[String]()) raises -> Outcome:
        """Run `stage-render` without hooks."""
        var hooks = NoHooks()
        return self.run(hooks, renders)

    def attribution(self) raises -> String:
        """Return the credits of the custom manifest."""
        var doc = PyJson.parse(self.manifest_bytes)
        return credits(doc, entries_of(doc, doc.root), True)


def test_exact_copies_custom_manifest_and_credits_leave_sources_and_cache_unchanged() raises:
    var setup = Stage()
    put(setup.fixture.cache + "/sentinel.zip", "pinned archive untouched")
    put(setup.fixture.source + "/render.credits.md", "do not copy this sidecar")
    var before = tree(setup.fixture.root)
    var outcome = setup.plain([setup.render, setup.other])
    assert_equal(outcome.status, 0)
    assert_equal(outcome.err, "")
    var staged = names(setup.output)
    assert_equal(len(staged), 4)
    assert_equal(read_text(setup.output + "/render.png"), RENDER)
    assert_equal(read_text(setup.output + "/other.apng"), OTHER)
    assert_equal(
        read_text(setup.output + "/manifest.json"), setup.manifest_bytes
    )
    var attribution = read_text(setup.output + "/ATTRIBUTION.md")
    assert_equal(attribution, setup.attribution())
    for text in [
        "Custom Brick",
        "Custom Author",
        "Converted for this historical render.",
        "CC0 entries",
    ]:
        assert_true(attribution.find(text) >= 0, text)
    assert_false(attribution.find("CARLA Team") >= 0)
    var after = List[String]()
    for line in tree(setup.fixture.root):
        if not line.startswith("distribution/") and not line.startswith("net/"):
            after.append(line)
    assert_equal(len(after), len(before))
    for index in range(len(before)):
        assert_equal(after[index], before[index])
    assert_false(exists(setup.fixture.source + "/manifest.json"))
    setup.fixture.close()


def test_default_manifest_is_supported() raises:
    var setup = Stage()
    var hooks = NoHooks()
    var outcome = run(
        ["stage-render", "--output", setup.output, setup.render],
        offline_transport(setup.fixture.net),
        hooks,
    )
    assert_equal(outcome.status, 0)
    assert_true(
        read_file(setup.output + "/manifest.json")
        == read_file("assets/carla/manifest.json")
    )
    assert_true(
        read_file(setup.output + "/ATTRIBUTION.md")
        == read_file("assets/carla/ATTRIBUTION.md")
    )
    setup.fixture.close()


def test_no_cache_network_or_process_is_needed() raises:
    var setup = Stage()
    assert_equal(setup.plain().status, 0)
    assert_false(exists(setup.fixture.cache))
    assert_equal(runs(setup.fixture.net), 0)
    setup.fixture.close()


def test_bad_render_inputs_fail_before_creating_any_output() raises:
    var setup = Stage()
    var source = setup.fixture.source
    symlink(setup.render, source + "/linked.png")
    symlink(source + "/missing.png", source + "/dangling.png")
    make_fifo(source + "/pipe.png")
    for bad in [
        source + "/missing.png",
        source,
        source + "/linked.png",
        source + "/dangling.png",
        source + "/pipe.png",
    ]:
        var outcome = setup.plain([setup.render, bad])
        assert_equal(outcome.status, 1, bad)
        assert_true(outcome.err.startswith("stage-render: "))
        assert_false(exists(setup.output))
    setup.fixture.close()


def test_duplicate_files_basename_collisions_and_reserved_names_are_refused() raises:
    var setup = Stage()
    var elsewhere = setup.fixture.root + "/elsewhere"
    put(elsewhere + "/RENDER.PNG", "case collision")
    put(elsewhere + "/render.png", "other bytes")
    hard_link(setup.render, elsewhere + "/hardlink.png")
    for duplicate in [
        setup.render,
        elsewhere + "/hardlink.png",
        elsewhere + "/render.png",
        elsewhere + "/RENDER.PNG",
    ]:
        assert_equal(setup.plain([setup.render, duplicate]).status, 1)
        assert_false(exists(setup.output))
    for name in [
        "manifest.json",
        "MANIFEST.JSON",
        "ATTRIBUTION.md",
        "attribution.MD",
    ]:
        put(elsewhere + "/" + name, "reserved")
        var outcome = setup.plain([elsewhere + "/" + name])
        assert_equal(outcome.status, 1)
        assert_true(
            outcome.err.find("duplicate or reserved output basename") >= 0
        )
        assert_false(exists(setup.output))
    setup.fixture.close()


def test_invalid_manifest_inputs_fail_before_creating_output() raises:
    var setup = Stage()
    for data in ["{broken", "\xff", "{}", '{"format": 1, "entries": false}']:
        put(setup.manifest_path, data)
        assert_equal(setup.plain().status, 1)
        assert_false(exists(setup.output))
    unlink(setup.manifest_path)
    assert_equal(setup.plain().status, 1)
    put(setup.manifest_path + "/x", "")
    unlink(setup.manifest_path + "/x")
    assert_equal(setup.plain().status, 1)
    remove_dir(setup.manifest_path)
    for target in [setup.render, setup.fixture.source + "/missing.json"]:
        symlink(target, setup.manifest_path)
        assert_equal(setup.plain().status, 1)
        unlink(setup.manifest_path)
    assert_false(exists(setup.output))
    setup.fixture.close()


def test_cli_requires_output_and_at_least_one_render() raises:
    var setup = Stage()
    var lines = List[List[String]]()
    lines.append(["stage-render"])
    lines.append(["stage-render", "--output", setup.output])
    lines.append(["stage-render", setup.render])
    for arguments in lines:
        assert_equal(parse_arguments(arguments).status, 2)
    var hooks = NoHooks()
    with assert_raises(contains="at least one render file is required"):
        stage_render(setup.manifest_path, setup.output, List[String](), hooks)
    assert_false(exists(setup.output))
    setup.fixture.close()


def test_existing_destinations_are_untouched_including_empty_and_dangling() raises:
    var setup = Stage()
    put(setup.output, "existing file")
    assert_equal(setup.plain().status, 1)
    assert_equal(read_text(setup.output), "existing file")
    unlink(setup.output)
    put(setup.output + "/user.txt", "user content")
    assert_equal(setup.plain().status, 1)
    assert_equal(read_text(setup.output + "/user.txt"), "user content")
    unlink(setup.output + "/user.txt")
    assert_equal(setup.plain().status, 1)
    assert_equal(len(names(setup.output)), 0)
    remove_dir(setup.output)
    for target in [setup.fixture.source, setup.fixture.root + "/missing"]:
        symlink(target, setup.output)
        assert_equal(setup.plain().status, 1)
        assert_true(islink(setup.output))
        assert_equal(read_link(setup.output), target)
        unlink(setup.output)
    setup.fixture.close()


def test_output_parent_must_exist() raises:
    var setup = Stage()
    setup.output = setup.output + "/nested"
    var outcome = setup.plain()
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("No such file or directory") >= 0)
    assert_false(exists(setup.fixture.root + "/distribution"))
    setup.fixture.close()


struct Racer(StageHooks):
    """Hooks that act as a racing process at one named moment."""

    var mode: String
    """What to do."""
    var output: String
    """The output directory."""
    var other: String
    """Another input."""
    var moved: String
    """Where a replaced directory goes."""
    var name: String
    """The file or folder whose moment it is."""
    var data: String
    """Bytes a hook writes, or what replaces a folder."""
    var child: String
    """The output folder a child test replaces."""
    var count: Int
    """How many times a folder was replaced."""
    var copies: Int
    """How many copies began."""

    def __init__(
        out self,
        mode: String,
        output: String = "",
        other: String = "",
        moved: String = "",
        name: String = "",
        data: String = "",
        child: String = "",
    ):
        """Make the hooks.

        Args:
            mode: What to do.
            output: The output directory.
            other: Another input.
            moved: Where a replaced directory goes.
            name: The file or folder whose moment it is.
            data: Bytes a hook writes, or what replaces a folder.
            child: The output folder a child test replaces.
        """
        self.mode = mode
        self.output = output
        self.other = other
        self.moved = moved
        self.name = name
        self.data = data
        self.child = child
        self.count = 0
        self.copies = 0

    def _replace(mut self, path: String) raises:
        """Move a directory away and put the user's replacement there."""
        rename(path, self.moved)
        if self.data == "directory":
            put(path + "/user.txt", "user replacement")
        elif self.data == "symlink":
            symlink(self.other, path)
        self.count += 1

    def before_mkdir(mut self, output: String) raises:
        """Create the destination after the check that it is absent.

        Args:
            output: The output directory.

        Raises:
            Error: Never.
        """
        if self.mode == "race-directory":
            put(output + "/user.txt", "racing directory")
        elif self.mode == "race-file":
            put(output, "racing file")
        elif self.mode == "race-symlink":
            symlink(self.other, output)

    def after_mkdir(mut self, output: String) raises:
        """Replace the new directory.

        Args:
            output: The output directory.

        Raises:
            Error: Never.
        """
        if self.mode == "replace-after-mkdir":
            rename(output, self.moved)
            put(output + "/user.txt", "racing user directory")

    def before_source_open(mut self, path: String) raises:
        """Replace an input after its check.

        Args:
            path: The input.

        Raises:
            Error: Never.
        """
        if path != self.name:
            return
        if self.mode == "input-symlink":
            unlink(path)
            symlink(self.other, path)
        elif self.mode == "input-file":
            rename(path, self.moved)
            put(path, "replacement input")

    def before_write(mut self, name: String) raises:
        """Act before an output file is created.

        Args:
            name: The file's name.

        Raises:
            Error: The injected failure.
        """
        if self.mode == "insert-file" and name == self.name:
            put(self.output + "/" + name, "racing user file")
        elif self.mode == "insert-symlink" and name == self.name:
            symlink(self.other, self.output + "/" + name)
        elif self.mode == "fail-create" and name == self.name:
            raise Error("OSError: injected output creation failure")
        elif self.mode == "user-added" and name == "manifest.json":
            put(self.output + "/user.txt", "user addition")
            raise Error("OSError: injected later failure")
        elif self.mode == "user-replaced" and name == "manifest.json":
            unlink(self.output + "/" + self.name)
            put(self.output + "/" + self.name, "user replacement")
            raise Error("OSError: injected later failure")
        elif self.mode == "user-symlink" and name == "manifest.json":
            unlink(self.output + "/" + self.name)
            symlink(self.other, self.output + "/" + self.name)
            raise Error("OSError: injected later failure")
        elif self.mode == "change-archive" and name == self.name:
            var data = read_file(self.other)
            data[0] = 0x58
            data[1] = 0x58
            write_file(self.other, Span(data))
        elif self.mode == "child-before" and name == self.name:
            self._replace(self.output + "/" + self.child)

    def before_copy(mut self, name: String, fd: Int) raises:
        """Fail a copy after part of it.

        Args:
            name: The file's name.
            fd: The open output file.

        Raises:
            Error: The injected failure.
        """
        self.copies += 1
        if self.mode == "fail-copy" and self.copies == Int(self.data):
            write_all(fd, "partial output".as_bytes())
            raise Error("OSError: injected copy failure")
        if self.mode == "fail-write":
            var data = read_file(self.other)
            write_all(fd, Span(data)[:3])
            raise Error("OSError: injected write failure")
        if self.mode == "replace-after-mkdir":
            raise Error("OSError: copy failed")

    def after_write(mut self, name: String) raises:
        """Act after an output file is written.

        Args:
            name: The file's name.

        Raises:
            Error: Never.
        """
        if self.mode == "replace-output" and name == self.name:
            rename(self.output, self.moved)
            put(self.output + "/user.txt", "user directory")
        elif self.mode == "child-after" and name == self.name:
            self._replace(self.output + "/" + self.child)

    def after_child_mkdir(mut self, relative: String) raises:
        """Replace a new folder with a link.

        Args:
            relative: The folder, relative to the output.

        Raises:
            Error: Never.
        """
        if self.mode == "racing-folder":
            remove_dir(self.output + "/" + relative)
            symlink(self.other, self.output + "/" + relative)

    def before_child_open(mut self, relative: String) raises:
        """Replace a new folder after its check.

        Args:
            relative: The folder, relative to the output.

        Raises:
            Error: Never.
        """
        if self.mode == "child-open" and relative == self.name:
            rename(self.output + "/" + relative, self.moved)
            put(self.output + "/" + relative + "/user.txt", "user replacement")


def test_destination_created_after_preflight_is_not_reused_or_removed() raises:
    var setup = Stage()
    for kind in ["directory", "file", "symlink"]:
        var hooks = Racer("race-" + kind, other=setup.fixture.root + "/absent")
        var outcome = setup.run(hooks)
        assert_equal(outcome.status, 1, kind)
        assert_true(outcome.err.find("File exists") >= 0, outcome.err)
        if kind == "directory":
            assert_equal(
                read_text(setup.output + "/user.txt"), "racing directory"
            )
            assert_equal(len(names(setup.output)), 1)
            remove_tree(setup.output)
        elif kind == "file":
            assert_equal(read_text(setup.output), "racing file")
            unlink(setup.output)
        else:
            assert_true(islink(setup.output))
            unlink(setup.output)
    setup.fixture.close()


def test_output_file_created_during_copy_is_never_overwritten() raises:
    var setup = Stage()
    for kind in ["file", "symlink"]:
        setup.output = setup.fixture.root + "/racing-output-" + kind
        var hooks = Racer(
            "insert-" + kind, setup.output, setup.other, name="render.png"
        )
        var outcome = setup.run(hooks)
        assert_equal(outcome.status, 1)
        assert_true(outcome.err.find("staging incomplete") >= 0)
        var target = setup.output + "/render.png"
        if kind == "file":
            assert_equal(read_text(target), "racing user file")
        else:
            assert_true(islink(target))
            assert_equal(read_link(target), setup.other)
            assert_equal(read_text(setup.other), OTHER)
        assert_equal(len(names(setup.output)), 1)
    setup.fixture.close()


def test_copy_failures_retain_partial_outputs_with_explicit_status() raises:
    var setup = Stage()
    var partials: List[String] = [
        "render.png",
        "other.apng",
        "manifest.json",
        "ATTRIBUTION.md",
    ]
    for fail_at in range(1, 5):
        setup.output = setup.fixture.root + "/failed-copy-" + String(fail_at)
        var hooks = Racer("fail-copy", data=String(fail_at))
        var outcome = setup.run(hooks, [setup.render, setup.other])
        assert_equal(outcome.status, 1)
        assert_true(outcome.err.find("injected copy failure") >= 0)
        assert_true(outcome.err.find("staging incomplete") >= 0)
        assert_true(outcome.err.find(setup.output) >= 0)
        assert_equal(len(names(setup.output)), fail_at)
        assert_equal(
            read_text(setup.output + "/" + partials[fail_at - 1]),
            "partial output",
        )
        if fail_at <= 2:
            assert_false(exists(setup.output + "/manifest.json"))
            assert_false(exists(setup.output + "/ATTRIBUTION.md"))
    assert_equal(read_text(setup.manifest_path), setup.manifest_bytes)
    assert_equal(read_text(setup.render), RENDER)
    setup.fixture.close()


def test_direct_writer_failure_retains_partial_bytes_and_returns_failure() raises:
    var setup = Stage()
    var hooks = Racer("fail-write", other=setup.render)
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("injected write failure") >= 0)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    var written = read_file(setup.output + "/render.png")
    var source = read_file(setup.render)
    assert_equal(len(written), 3)
    for index in range(3):
        assert_equal(written[index], source[index])
    assert_false(exists(setup.output + "/manifest.json"))
    assert_false(exists(setup.output + "/ATTRIBUTION.md"))
    setup.fixture.close()


def test_file_creation_failure_retains_prior_outputs_and_reports_incomplete() raises:
    var setup = Stage()
    var hooks = Racer("fail-create", name="ATTRIBUTION.md")
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("injected output creation failure") >= 0)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    assert_equal(read_text(setup.output + "/render.png"), RENDER)
    assert_equal(
        read_text(setup.output + "/manifest.json"), setup.manifest_bytes
    )
    assert_false(exists(setup.output + "/ATTRIBUTION.md"))
    setup.fixture.close()


def test_failure_preserves_user_added_or_replaced_files() raises:
    var setup = Stage()
    for replacement in ["added", "replaced", "symlink"]:
        setup.output = setup.fixture.root + "/failure-" + replacement
        var hooks = Racer(
            "user-" + replacement, setup.output, setup.other, name="render.png"
        )
        var outcome = setup.run(hooks)
        assert_equal(outcome.status, 1)
        assert_true(outcome.err.find("staging incomplete") >= 0)
        assert_equal(
            len(names(setup.output)), 2 if replacement == "added" else 1
        )
        if replacement == "symlink":
            assert_equal(read_link(setup.output + "/render.png"), setup.other)
        elif replacement == "added":
            assert_equal(read_text(setup.output + "/user.txt"), "user addition")
        else:
            assert_equal(
                read_text(setup.output + "/render.png"), "user replacement"
            )
    setup.fixture.close()


def test_replaced_output_directory_is_left_untouched() raises:
    var setup = Stage()
    var moved = setup.fixture.root + "/moved-distribution"
    var hooks = Racer(
        "replace-output", setup.output, moved=moved, name="render.png"
    )
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("output changed while staging it") >= 0)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    assert_equal(read_text(setup.output + "/user.txt"), "user directory")
    var kept = names(moved)
    assert_equal(len(kept), 3)
    assert_equal(kept[0], "ATTRIBUTION.md")
    assert_equal(kept[1], "manifest.json")
    assert_equal(kept[2], "render.png")
    setup.fixture.close()


def test_failure_never_attempts_destructive_cleanup() raises:
    var setup = Stage()
    var hooks = Racer("fail-copy", data="1")
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("injected copy failure") >= 0)
    assert_true(outcome.err.find("retained output at " + setup.output) >= 0)
    assert_true(exists(setup.output + "/render.png"))
    setup.fixture.close()


def test_directory_replaced_immediately_after_mkdir_survives_failure() raises:
    var setup = Stage()
    var moved = setup.fixture.root + "/original-directory"
    var hooks = Racer("replace-after-mkdir", moved=moved)
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    assert_equal(read_text(setup.output + "/user.txt"), "racing user directory")
    assert_true(isdir(moved))
    setup.fixture.close()


def test_input_replaced_by_symlink_during_open_is_refused() raises:
    var setup = Stage()
    var hooks = Racer("input-symlink", other=setup.other, name=setup.render)
    assert_equal(setup.run(hooks).status, 1)
    assert_false(exists(setup.output))
    assert_equal(read_text(setup.other), OTHER)
    setup.fixture.close()


def test_input_replaced_by_regular_file_during_open_is_refused() raises:
    var setup = Stage()
    var moved = setup.fixture.source + "/original-render.png"
    var hooks = Racer("input-file", moved=moved, name=setup.render)
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("input changed while opening it") >= 0)
    assert_false(exists(setup.output))
    assert_equal(read_text(moved), RENDER)
    assert_equal(read_text(setup.render), "replacement input")
    setup.fixture.close()


def test_credits_stdout_flags_and_output_still_create_no_sidecars() raises:
    var setup = Stage()
    var before = tree(setup.fixture.root)
    var doc = PyJson.parse(setup.manifest_bytes)
    for everything in [False, True]:
        var arguments: List[String] = [
            "--manifest",
            setup.manifest_path,
            "credits",
        ]
        if everything:
            arguments.append("--all")
        var outcome = cli(arguments, offline_transport(setup.fixture.net))
        assert_equal(outcome.status, 0)
        assert_equal(
            outcome.out, credits(doc, entries_of(doc, doc.root), everything)
        )
    var destination = setup.fixture.root + "/custom-credits.md"
    var outcome = cli(
        ["--manifest", setup.manifest_path, "credits", "--output", destination],
        offline_transport(setup.fixture.net),
    )
    assert_equal(outcome.status, 0)
    assert_equal(
        read_text(destination), credits(doc, entries_of(doc, doc.root), False)
    )
    var after = 0
    for line in tree(setup.fixture.root):
        if not line.startswith("net/"):
            after += 1
    assert_equal(after, len(before) + 1)
    setup.fixture.close()


# --- Staging archives ---------------------------------------------------------------------


struct Archives(Movable):
    """A real CARLA entry and a CC0 entry, each with a pinned archive."""

    var fixture: Fixture
    var output: String
    var manifest_path: String
    var manifest_bytes: String
    var doc: PyJson
    var car: List[UInt8]
    var wheel: List[UInt8]
    var scan: List[UInt8]
    var car_path: String

    def __init__(out self) raises:
        self.fixture = Fixture()
        self.output = self.fixture.root + "/package"
        self.manifest_path = self.fixture.root + "/custom-manifest.json"
        self.manifest_bytes = String()
        var audi = PyJson.parse(_audi())
        var item = audi.item(audi.get(audi.root, "files"), 0)
        var extract = audi.get(item, "extract")
        var member_names = List[String]()
        var member_data = List[String]()
        for index in range(audi.length(extract)):
            var member = audi.item(extract, index)
            member_names.append(audi.text(audi.get(member, "member")))
            member_data.append(audi.text(audi.get(member, "path")))
        self.car = zip_of(member_names, member_data)
        self.wheel = zip_of(["wheel.gltf"], ['{"wheel": 1}'])
        self.scan = zip_of(["Scan_Color.jpg"], ["color texels"])
        self.car_path = audi.text(audi.get(item, "path"))
        audi.set(item, "sha256", audi.new_str(sha256_bytes(Span(self.car))))
        audi.set(item, "url", audi.new_none())
        var free = _archive_entry(
            "null",
            q(sha256_bytes(Span(self.scan))),
            (
                '{"role": "albedo", "member": "Scan_Color.jpg", "path":'
                ' "scan/color.jpg"}'
            ),
        ).replace('"asphalt"', '"scan"')
        var other = texture(
            q("https://example.org/other.jpg"), "null", "other", "other.jpg"
        ).replace(
            '"tile_meters": 4', '"tile_meters": 4, "title": "Unselected Entry"'
        )
        self.doc = PyJson.parse(
            manifest_of([manifest_text(audi, audi.root), free, other])
        )
        put_bytes(self.fixture.cache + "/" + self.car_path, self.car)
        put_bytes(self.fixture.cache + "/scan.zip", self.scan)
        self.write()

    def write(mut self) raises:
        """Write the manifest file from `doc`."""
        self.manifest_bytes = manifest_text(self.doc, self.doc.root) + "\r\n"
        put(self.manifest_path, self.manifest_bytes)

    def entry(self, index: Int) raises -> Int:
        """Return an entry of `doc`."""
        return self.doc.item(self.doc.get(self.doc.root, "entries"), index)

    def file(self, index: Int) raises -> Int:
        """Return an entry's first file."""
        return self.doc.item(self.doc.get(self.entry(index), "files"), 0)

    def run[
        H: StageHooks
    ](self, mut hooks: H, ids: List[String] = List[String]()) raises -> Outcome:
        """Run `stage-archive`, by default for the CARLA and scan entries."""
        var arguments: List[String] = [
            "--manifest",
            self.manifest_path,
            "--cache",
            self.fixture.cache,
            "stage-archive",
            "--output",
            self.output,
        ]
        if len(ids) == 0:
            arguments.append("carla.vehicle.audi.a2")
            arguments.append("scan")
        else:
            arguments.extend(ids.copy())
        return run(arguments, offline_transport(self.fixture.net), hooks)

    def plain(self, ids: List[String] = List[String]()) raises -> Outcome:
        """Run `stage-archive` without hooks."""
        var hooks = NoHooks()
        return self.run(hooks, ids)


def test_exact_pinned_archives_manifest_and_selected_credits() raises:
    var setup = Archives()
    var outcome = setup.plain()
    assert_equal(outcome.status, 0)
    assert_equal(outcome.err, "")
    assert_true(read_file(setup.output + "/" + setup.car_path) == setup.car)
    assert_true(read_file(setup.output + "/scan.zip") == setup.scan)
    assert_equal(
        read_text(setup.output + "/manifest.json"), setup.manifest_bytes
    )
    assert_equal(len(tree(setup.output)), 4)
    var attribution = read_text(setup.output + "/ATTRIBUTION.md")
    assert_equal(
        attribution, credits(setup.doc, [setup.entry(0), setup.entry(1)], True)
    )
    for text in [
        "CARLA Team (Computer Vision Center)",
        "Audi A2 (CARLA)",
        "https://creativecommons.org/licenses/by/4.0/",
        "https://github.com/carla-simulator/carla/releases/tag/0.9.16",
        '"scan" by A. Scanner',
    ]:
        assert_true(attribution.find(text) >= 0, text)
    assert_false(attribution.find("Unselected Entry") >= 0)
    setup.fixture.close()


def test_package_is_a_cache_root_for_offline_recovery() raises:
    var setup = Archives()
    assert_equal(setup.plain().status, 0)
    var common: List[String] = [
        "--manifest",
        setup.output + "/manifest.json",
        "--cache",
        setup.output,
    ]
    var fetching = common.copy()
    fetching.extend(["fetch", "--offline", "carla.vehicle.audi.a2", "scan"])
    assert_equal(cli(fetching, offline_transport(setup.fixture.net)).status, 0)
    var verifying = common.copy()
    verifying.extend(["verify", "--strict", "carla.vehicle.audi.a2", "scan"])
    var checked = cli(verifying, offline_transport(setup.fixture.net))
    assert_equal(checked.status, 0)
    assert_false(checked.out.find("mismatch") >= 0)
    assert_equal(read_text(setup.output + "/scan/color.jpg"), "color texels")
    assert_equal(runs(setup.fixture.net), 0)
    setup.fixture.close()


def test_shared_folders_hold_several_archives() raises:
    var setup = Archives()
    var files = setup.doc.get(setup.entry(0), "files")
    var wheel = PyJson.parse(
        '{"role": "archive", "url": null, "sha256": '
        + q(sha256_bytes(Span(setup.wheel)))
        + ', "path": "carla/vehicles/wheel.zip", "extract": [{"role":'
        ' "support", "member": "wheel.gltf", "path": "carla/wheel.gltf"}]}'
    )
    setup.doc.append(files, setup.doc.adopt(wheel, wheel.root))
    setup.write()
    put_bytes(setup.fixture.cache + "/carla/vehicles/wheel.zip", setup.wheel)
    assert_equal(setup.plain(["carla.vehicle.audi.a2"]).status, 0)
    assert_equal(len(tree(setup.output)), 4)
    assert_true(
        read_file(setup.output + "/carla/vehicles/wheel.zip") == setup.wheel
    )
    setup.fixture.close()


def test_different_missing_unpinned_or_linked_archives_create_no_output() raises:
    var setup = Archives()
    var archive = setup.fixture.cache + "/scan.zip"
    put_bytes(archive, zip_of(["Scan_Color.jpg"], ["rebuilt texels"]))
    var outcome = setup.plain()
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("does not match the pinned") >= 0)
    assert_false(exists(setup.output))
    unlink(archive)
    assert_equal(setup.plain().status, 1)
    assert_false(exists(setup.output))
    symlink(setup.fixture.cache + "/" + setup.car_path, archive)
    assert_equal(setup.plain().status, 1)
    assert_false(exists(setup.output))
    unlink(archive)
    put_bytes(archive, setup.scan)
    setup.doc.set(setup.file(1), "sha256", setup.doc.new_none())
    setup.doc.set(
        setup.file(1), "url", setup.doc.new_str("https://example.org/scan.zip")
    )
    setup.write()
    outcome = setup.plain()
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("no pinned sha256") >= 0)
    assert_false(exists(setup.output))
    setup.fixture.close()


def test_bad_selections_and_manifests_create_no_output() raises:
    var setup = Archives()
    var selections = List[List[String]]()
    selections.append(["missing.entry"])
    selections.append(["scan", "scan"])
    selections.append(["other"])
    for ids in selections:
        var outcome = setup.plain(ids)
        assert_equal(outcome.status, 1)
        assert_true(outcome.err.byte_length() > 0)
        assert_false(exists(setup.output))
    var hooks = NoHooks()
    with assert_raises(contains="at least one entry id is required"):
        stage_archive(
            setup.manifest_path,
            setup.fixture.cache,
            setup.output,
            List[String](),
            hooks,
        )
    for data in ["{broken", "\xff", "{}"]:
        put(setup.manifest_path, data)
        assert_equal(setup.plain().status, 1)
    assert_false(exists(setup.output))
    var lines = List[List[String]]()
    lines.append(["stage-archive"])
    lines.append(["stage-archive", "--output", setup.output])
    lines.append(["stage-archive", "scan"])
    for arguments in lines:
        assert_equal(parse_arguments(arguments).status, 2)
    setup.fixture.close()


def test_reserved_and_case_insensitive_path_clashes_are_refused() raises:
    for pair in [
        ("MANIFEST.JSON", ""),
        ("attribution.md", ""),
        ("Carla/a.zip", "carla/b.zip"),
        ("a.zip", "A.ZIP/b.zip"),
        ("a/b.zip", "A/B.ZIP"),
    ]:
        var setup = Archives()
        var first = String(pair[0])
        var second = String(pair[1])
        put_bytes(setup.fixture.cache + "/" + first, setup.scan)
        var free = PyJson.parse(manifest_text(setup.doc, setup.entry(1)))
        var free_file = free.item(free.get(free.root, "files"), 0)
        free.set(free_file, "path", free.new_str(first))
        var entries: List[String] = [manifest_text(free, free.root)]
        var ids: List[String] = ["scan"]
        if second:
            # The clash is refused from the manifest alone. A second cached
            # file cannot exist beside the first on a case-insensitive disk.
            free.set(free.root, "id", free.new_str("second"))
            free.set(free_file, "path", free.new_str(second))
            var member = free.item(free.get(free_file, "extract"), 0)
            free.set(member, "path", free.new_str("second/color.jpg"))
            entries.append(manifest_text(free, free.root))
            ids.append("second")
        setup.doc = PyJson.parse(manifest_of(entries))
        setup.write()
        var outcome = setup.plain(ids)
        assert_equal(outcome.status, 1, first)
        assert_true(outcome.err.find("clashes") >= 0, outcome.err)
        assert_false(exists(setup.output))
        setup.fixture.close()


def test_existing_destinations_and_missing_parents_are_refused() raises:
    var setup = Archives()
    put(setup.output + "/user.txt", "user content")
    assert_equal(setup.plain().status, 1)
    var kept = tree(setup.output)
    assert_equal(len(kept), 1)
    assert_equal(kept[0], "user.txt=user content")
    setup.output = setup.fixture.root + "/dangling"
    symlink(setup.fixture.root + "/absent", setup.output)
    assert_equal(setup.plain().status, 1)
    assert_true(islink(setup.output))
    setup.output = setup.fixture.root + "/absent/nested"
    assert_equal(setup.plain().status, 1)
    assert_false(exists(setup.fixture.root + "/absent"))
    setup.fixture.close()


def test_archive_changed_after_preflight_is_reported_and_retained() raises:
    var setup = Archives()
    var hooks = Racer(
        "change-archive",
        other=setup.fixture.cache + "/scan.zip",
        name="scan.zip",
    )
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("changed from the pinned") >= 0)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    assert_true(outcome.err.find(setup.output) >= 0)
    assert_equal(len(tree(setup.output)), 2)
    assert_false(exists(setup.output + "/manifest.json"))
    setup.fixture.close()


def test_late_failures_retain_partial_output_and_never_overwrite() raises:
    var setup = Archives()
    var hooks = Racer("fail-create", name="ATTRIBUTION.md")
    var outcome = setup.run(hooks)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    assert_equal(
        read_text(setup.output + "/manifest.json"), setup.manifest_bytes
    )
    assert_true(read_file(setup.output + "/scan.zip") == setup.scan)
    assert_false(exists(setup.output + "/ATTRIBUTION.md"))
    setup.output = setup.fixture.root + "/racing"
    var racing = Racer("racing-folder", setup.output, setup.fixture.source)
    outcome = setup.run(racing)
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    assert_equal(len(names(setup.fixture.source)), 0)
    assert_true(islink(setup.output + "/carla"))
    setup.fixture.close()


def test_replaced_child_directories_fail_without_deleting_replacements() raises:
    var setup = Archives()
    var cut = setup.car_path.rfind("/")
    var archive_name = String(setup.car_path[byte = cut + 1 :])
    for child in ["carla", "carla/vehicles"]:
        for moment in ["before archive", "after archive", "after metadata"]:
            for replacement in ["directory", "symlink", "absent"]:
                var label = (
                    String(child).replace("/", "-")
                    + "-"
                    + String(moment).replace(" ", "-")
                    + "-"
                    + replacement
                )
                setup.output = setup.fixture.root + "/package-" + label
                var moved = setup.fixture.root + "/moved-" + label
                var mode = String("child-after")
                if moment == "before archive":
                    mode = "child-before"
                var name = archive_name
                if moment == "after metadata":
                    name = "ATTRIBUTION.md"
                var hooks = Racer(
                    mode,
                    setup.output,
                    setup.fixture.source,
                    moved,
                    name,
                    replacement,
                    child,
                )
                var outcome = setup.run(hooks, ["carla.vehicle.audi.a2"])
                assert_equal(hooks.count, 1, label)
                assert_equal(outcome.status, 1, label)
                assert_true(outcome.err.find("staging incomplete") >= 0, label)
                assert_true(outcome.err.find(setup.output) >= 0)
                assert_true(isdir(moved))
                var target = setup.output + "/" + child
                if replacement == "directory":
                    var kept = tree(target)
                    assert_equal(len(kept), 1)
                    assert_equal(kept[0], "user.txt=user replacement")
                elif replacement == "symlink":
                    assert_true(islink(target))
                    assert_equal(len(names(setup.fixture.source)), 0)
                else:
                    assert_false(exists(target))
    setup.fixture.close()


def test_child_replaced_between_stat_and_open_is_refused() raises:
    var setup = Archives()
    var moved = setup.fixture.root + "/original-vehicles"
    var hooks = Racer(
        "child-open", setup.output, moved=moved, name="carla/vehicles"
    )
    var outcome = setup.run(hooks, ["carla.vehicle.audi.a2"])
    assert_equal(outcome.status, 1)
    assert_true(outcome.err.find("output changed while opening it") >= 0)
    assert_true(outcome.err.find("staging incomplete") >= 0)
    var kept = tree(setup.output + "/carla/vehicles")
    assert_equal(len(kept), 1)
    assert_equal(kept[0], "user.txt=user replacement")
    assert_equal(len(names(moved)), 0)
    setup.fixture.close()


# --- Credits ------------------------------------------------------------------------------


def test_committed_attribution_matches_every_manifest_entry() raises:
    var doc = load_manifest(default_manifest())
    var entries = entries_of(doc, doc.root)
    var expected = credits(doc, entries, True)
    assert_equal(read_text("assets/carla/ATTRIBUTION.md"), expected)
    var required = 0
    for entry in entries:
        if doc.text(doc.get(entry, "license")) != "CC-BY-4.0":
            continue
        required += 1
        for key in ["title", "author", "source", "changes"]:
            assert_true(expected.find(doc.text(doc.get(entry, key))) >= 0)
    assert_equal(required, 47)
    assert_true(
        expected.find("https://creativecommons.org/licenses/by/4.0/") >= 0
    )


def test_cc_by_entries_are_credited() raises:
    var free = texture(q("https://example.org/a.jpg"), "null")
    var scanned = (
        texture(
            q("https://example.org/b.jpg"), "null", "bricks", "bricks/color.jpg"
        )
        .replace('"CC0-1.0"', '"CC-BY-4.0"')
        .replace('"A. Scanner"', '"C. Mason"')
        .replace(
            '"https://example.org/asphalt"', '"https://example.org/bricks"'
        )
        .replace(
            '"tile_meters": 4',
            (
                '"tile_meters": 4, "title": "Old Bricks", "changes": "Resized'
                ' to 2048 texels."'
            ),
        )
    )
    var doc = PyJson.parse(manifest_of([free, scanned]))
    var entries = entries_of(doc, doc.root)
    var text = credits(doc, entries, False)
    assert_true(
        text.find(
            '- "Old Bricks" by C. Mason, https://example.org/bricks, CC BY 4.0'
            " (https://creativecommons.org/licenses/by/4.0/). Changes: Resized"
            " to 2048 texels."
        )
        >= 0
    )
    assert_false(text.find("asphalt") >= 0)
    assert_true(
        credits(doc, entries, True).find('"asphalt" by A. Scanner') >= 0
    )
    var only = PyJson.parse(manifest_of([free]))
    assert_true(
        credits(only, entries_of(only, only.root), False).find("No CC BY entry")
        >= 0
    )


def test_credits_command_writes_a_file() raises:
    var folder = scratch()
    var output = folder + "/credits.md"
    var outcome = cli(
        ["credits", "--all", "--output", output],
        offline_transport(folder + "/net"),
    )
    assert_equal(outcome.status, 0)
    assert_true(read_text(output).startswith("## Credits"))
    remove_tree(folder)


# --- The command line ---------------------------------------------------------------------


def test_command_line_texts_match_argparse() raises:
    var empty = parse_arguments(List[String]())
    assert_equal(empty.status, 2)
    assert_equal(
        empty.message,
        (
            "usage: carla_assets [-h] [--manifest MANIFEST] [--cache CACHE]\n"
            "                   "
            " {check,status,fetch,verify,credits,stage-render,stage-archive}\n"
            "                    ...\n"
            "carla_assets: error: the following arguments are required:"
            " command\n"
        ),
    )
    var bogus = parse_arguments(["bogus"])
    assert_true(
        bogus.message.endswith(
            "argument command: invalid choice: 'bogus' (choose from check,"
            " status, fetch, verify, credits, stage-render, stage-archive)\n"
        )
    )
    var extra = parse_arguments(["check", "--manifest", "x"])
    assert_true(
        extra.message.endswith("unrecognized arguments: --manifest x\n")
    )
    var help = parse_arguments(["fetch", "-h"])
    assert_equal(help.status, 0)
    assert_equal(
        help.message,
        (
            "usage: carla_assets fetch [-h] [--pin | --offline] [ids"
            " ...]\n\npositional arguments:\n  ids\n\noptions:\n  -h, --help "
            " show this help message and exit\n  --pin       trust the first"
            " download of a file with no sum, and record its\n             "
            " sum\n  --offline   verify and extract cached files only; fail if"
            " missing or\n              unpinned\n"
        ),
    )
    var mixed = parse_arguments(["verify", "a", "--strict", "b"])
    assert_true(mixed.message.endswith("unrecognized arguments: b\n"))
    var parsed = parse_arguments(
        ["--man=m.json", "--c", "c", "fetch", "--o", "x", "y"]
    )
    assert_equal(parsed.status, 0)
    assert_equal(parsed.values["manifest"], "m.json")
    assert_equal(parsed.values["cache"], "c")
    assert_true(parsed.flag("offline"))
    assert_equal(len(parsed.items), 2)


def test_check_reports_entries_and_bindings() raises:
    var folder = scratch()
    var path = folder + "/m.json"
    put(
        path,
        manifest_of(
            [texture(q("https://example.org/a.jpg"), "null")],
            '{"surface.road": "asphalt", "x": null}',
        ),
    )
    var outcome = cli(["--manifest", path, "check"], offline_transport(folder))
    assert_equal(outcome.status, 0)
    assert_equal(
        outcome.out, path + ": 1 entries, 2 bindings, all rules kept\n"
    )
    put(path, "{broken")
    outcome = cli(["--manifest", path, "check"], offline_transport(folder))
    assert_equal(outcome.status, 1)
    assert_equal(
        outcome.err,
        (
            "json.decoder.JSONDecodeError: Expecting property name enclosed in"
            " double quotes: line 1 column 2 (char 1)\n"
        ),
    )
    remove_tree(folder)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
