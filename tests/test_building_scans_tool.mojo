# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The scanned-building manifest and its fetch tool, on file:// fixtures.

A scene's files are copies of `assets/sog/flat/`, served as `file://`
URLs. Its scene page is served by a stub `curl` that logs each run, so a
test can count the pages opened and show that a second fetch opens none.
Every expected sum is computed here from the fixture's own bytes.
"""

from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from extensions.scan.sog import read_sog
from test_scratch import TestScratch, temporary_path
from tests._carla_tool_files import get_text, put, put_bytes, runs, stub_curl
from tools._building_scans import (
    check_scan_manifest,
    content_url,
    credits,
    is_file_name,
    is_sum,
    load_scan_manifest,
    meta_names,
    resolve,
    url_folder,
)
from tools._carla_assets import (
    Transport,
    entries_of,
    read_json_text,
    sha256_bytes,
)
from tools.building_scans import Outcome, parse_arguments, run

comptime SOURCE = "assets/sog/flat/"
comptime NAMES: List[String] = [
    "meta.json",
    "means_l.webp",
    "means_u.webp",
    "scales.webp",
    "quats.webp",
    "sh0.webp",
]


def _entry(
    entry_id: String,
    license: String = "CC-BY-4.0",
    files: String = "[]",
    frame: String = '{"up": "-y", "north": "-z", "unit_m": 1, "scale": "declared"}',
) -> String:
    """Return one entry's JSON text."""
    return (
        '{"id": "'
        + entry_id
        + '", "title": "Flat room", "author": "a tester",'
        + ' "author_url": "https://example.test/tester", "license": "'
        + license
        + '", "source": "https://example.test/scene/abc123", "scene": "abc123",'
        + ' "provenance": "Made by make_sog.mjs.", "changes": "None.",'
        + ' "kit": "masonry", "use": "living", "frame": '
        + frame
        + ', "files": '
        + files
        + "}"
    )


def _manifest(entry: String) -> String:
    """Return a manifest with one entry."""
    return '{"format": 1, "about": "test", "entries": [' + entry + "]}"


struct _Site(Movable):
    """A scene served from a folder: its files, its page, a manifest and
    a cache."""

    var root: String
    var manifest: String
    var cache: String
    var net: String
    var transport: Transport

    def __init__(
        out self, name: String, status_line: String = "HTTP/1.1 200 OK"
    ) raises:
        self.root = temporary_path("scans_" + name + "/")
        self.manifest = self.root + "manifest.json"
        self.cache = self.root + "cache"
        self.net = self.root + "net"
        for file in materialize[NAMES]():
            put_bytes(
                self.root + "source/" + file, Path(SOURCE + file).read_bytes()
            )
        var page = (
            "<html><script>const contentUrl = 'file://"
            + self.root
            + "source/meta.json';</script></html>"
        )
        put(self.net + "/.keep", "")
        self.transport = Transport(
            stub_curl(self.net, status_line, "text/html", page), 0
        )
        put(self.manifest, _manifest(_entry("flat-room")))

    def run(self, var words: List[String]) -> Outcome:
        """Run the tool on this site's manifest and cache."""
        var all: List[String] = [
            "--manifest",
            self.manifest,
            "--cache",
            self.cache,
        ]
        all.extend(words^)
        return run(all, self.transport)


def _source_sum(name: String) raises -> String:
    """Return the sum of a fixture file."""
    var data = Path(SOURCE + name).read_bytes()
    return sha256_bytes(Span(data))


def test_the_repository_manifest_keeps_the_rules() raises:
    """Every entry is CC BY 4.0 or CC0, with a kit, a use and a frame."""
    var doc = load_scan_manifest("assets/building_scans/manifest.json")
    var entries = entries_of(doc, doc.root)
    assert_true(len(entries) >= 2)
    for entry in entries:
        var license = doc.text(doc.get(entry, "license"))
        assert_true(license == "CC-BY-4.0" or license == "CC0-1.0")
        assert_true(
            doc.text(doc.get(entry, "source")).startswith(
                "https://superspl.at/scene/"
            )
        )


def test_a_pinning_fetch_resolves_downloads_and_records() raises:
    """One page is opened; every file is fetched, pinned and readable."""
    var site = _Site("pin")
    var outcome = site.run(["fetch", "--pin"])
    assert_equal(outcome.status, 0)
    assert_equal(runs(site.net), 1)
    assert_true("pinned  flat-room/meta.json" in outcome.output)
    var doc = load_scan_manifest(site.manifest)
    var entry = entries_of(doc, doc.root)[0]
    var files = doc.get(entry, "files")
    assert_equal(doc.length(files), 6)
    for index in range(6):
        var item = doc.item(files, index)
        var name = materialize[NAMES]()[index]
        assert_equal(doc.text(doc.get(item, "path")), "flat-room/" + name)
        assert_equal(doc.text(doc.get(item, "sha256")), _source_sum(name))
    var cached = read_sog(site.cache + "/flat-room/meta.json")
    var original = read_sog(SOURCE + "meta.json")
    assert_true(cached.geometry.centers == original.geometry.centers)
    assert_true(cached.geometry.colors == original.geometry.colors)


def test_a_second_fetch_keeps_its_files_and_opens_nothing() raises:
    """Pinned and cached files are kept; offline and strict checks pass."""
    var site = _Site("again")
    _ = site.run(["fetch", "--pin"])
    var again = site.run(["fetch"])
    assert_equal(again.status, 0)
    assert_equal(again.output.count("kept  "), 6)
    assert_equal(runs(site.net), 1)
    assert_equal(site.run(["fetch", "--offline"]).status, 0)
    var verified = site.run(["verify", "--strict"])
    assert_equal(verified.status, 0)
    assert_equal(verified.output.count("ok  "), 6)


def test_a_changed_file_is_a_mismatch_and_is_left_alone() raises:
    """Verify and fetch both fail, and the file keeps its new bytes."""
    var site = _Site("changed")
    _ = site.run(["fetch", "--pin"])
    put(site.cache + "/flat-room/quats.webp", "not the image")
    var verified = site.run(["verify"])
    assert_equal(verified.status, 1)
    assert_true("mismatch  flat-room/quats.webp" in verified.output)
    assert_equal(site.run(["fetch"]).status, 1)
    assert_equal(
        get_text(site.cache + "/flat-room/quats.webp"), "not the image"
    )


def test_an_unresolved_scene_is_not_fetched_without_pin() raises:
    """No page is opened; offline and strict runs fail."""
    var site = _Site("unresolved")
    var fetched = site.run(["fetch"])
    assert_equal(fetched.status, 0)
    assert_true("unresolved  flat-room/" in fetched.output)
    assert_equal(runs(site.net), 0)
    assert_equal(site.run(["fetch", "--offline"]).status, 1)
    assert_equal(site.run(["verify"]).status, 0)
    assert_equal(site.run(["verify", "--strict"]).status, 1)
    assert_equal(get_text(site.manifest), _manifest(_entry("flat-room")))


def test_status_and_credits_follow_the_cache() raises:
    """Unresolved, cached and missing; credits only for what is cached."""
    var site = _Site("status")
    assert_true("unresolved" in site.run(["status"]).output)
    assert_true(
        "No scanned building is cached." in site.run(["credits"]).output
    )
    assert_true(
        '"Flat room" by a tester' in site.run(["credits", "--all"]).output
    )
    _ = site.run(["fetch", "--pin"])
    assert_true("flat-room  cached  " in site.run(["status"]).output)
    var credited = site.run(["credits"]).output
    assert_true(
        "CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)" in credited
    )
    _ = Path(site.cache + "/flat-room/sh0.webp").write_text("")
    from std.os import remove

    remove(site.cache + "/flat-room/sh0.webp")
    assert_true("flat-room  missing" in site.run(["status"]).output)
    assert_equal(site.run(["check"]).output, "manifest ok: 1 entries\n")


def test_a_cc0_scene_is_credited_as_cc0() raises:
    """The dedication's own name and link."""
    var doc = read_json_text(
        List[UInt8](_manifest(_entry("free", "CC0-1.0")).as_bytes())
    )
    check_scan_manifest(doc, doc.root)
    var text = credits(doc, doc.root, "/nonexistent", True)
    assert_true(
        "CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)" in text
    )


def test_a_failed_page_leaves_the_manifest_and_cache_alone() raises:
    """An HTTP error and a curl failure each end the fetch."""
    var site = _Site("http", "HTTP/1.1 404 Not Found")
    var outcome = site.run(["fetch", "--pin"])
    assert_equal(outcome.status, 1)
    assert_true("HTTP Error 404" in outcome.errors)
    assert_equal(get_text(site.manifest), _manifest(_entry("flat-room")))
    var broken = _Site("curl")
    broken.transport = Transport(
        stub_curl(broken.net, "", "", "", 7, "curl: (7) no route", 9), 0
    )
    var failed = broken.run(["fetch", "--pin"])
    assert_equal(failed.status, 1)
    assert_true("no route" in failed.errors)


def test_a_scene_page_must_name_its_content() raises:
    """Script and JSON spellings are read; anything else is refused."""
    assert_equal(
        content_url("x contentUrl = 'https://a.test/b/meta.json' y"),
        "https://a.test/b/meta.json",
    )
    assert_equal(
        content_url('{"contentUrl":"https://a.test/c/meta.json?sig=1"}'),
        "https://a.test/c/meta.json?sig=1",
    )
    assert_equal(
        content_url("{'contentUrl': 'file:///d/meta.json'}"),
        "file:///d/meta.json",
    )
    with assert_raises(contains="no contentUrl"):
        _ = content_url("<html></html>")
    with assert_raises(contains="is not a quoted text"):
        _ = content_url("contentUrl = window.url")
    with assert_raises(contains="is not a quoted text"):
        _ = content_url("contentUrl = 'https://a.test/never-closed")
    with assert_raises(contains="is not a quoted text"):
        _ = content_url("contentUrl")
    with assert_raises(contains="the scene is lod-meta.json, not one SOG"):
        _ = content_url("contentUrl = 'https://a.test/b/lod-meta.json?x=1'")
    with assert_raises(contains="is not https:// or file://"):
        _ = content_url("contentUrl = 'http://a.test/meta.json'")


def test_a_url_folder_drops_the_name_query_and_fragment() raises:
    """The images lie beside the text."""
    assert_equal(
        url_folder("https://a.test/b/meta.json?sig=1/2"), "https://a.test/b/"
    )
    assert_equal(
        url_folder("https://a.test/b/meta.json#top"), "https://a.test/b/"
    )
    assert_equal(url_folder("https://a.test/b/c?x#y"), "https://a.test/b/")
    assert_equal(url_folder("https://a.test/b/c#y?x"), "https://a.test/b/")


def test_a_text_names_its_images_once() raises:
    """Every section's files, each once; a folder or no file is refused."""
    var names = meta_names(Path(SOURCE + "meta.json").read_text())
    assert_equal(len(names), 5)
    assert_equal(names[0], "means_l.webp")
    assert_equal(
        len(meta_names(Path("assets/sog/sh3/meta.json").read_text())), 7
    )
    assert_equal(
        len(
            meta_names(
                '{"a": {"files": ["x.webp"]}, "b": {"files": ["x.webp"]},'
                ' "count": 3}'
            )
        ),
        1,
    )
    with assert_raises(contains="not a file name"):
        _ = meta_names('{"a": {"files": ["../x.webp"]}}')
    with assert_raises(contains="names no image"):
        _ = meta_names('{"a": {"codebook": []}}')
    with assert_raises(contains="is not an object"):
        _ = meta_names("[1, 2]")


def test_an_entry_with_files_is_not_resolved_again() raises:
    """`resolve` adds nothing to an entry that has files."""
    var files = (
        '[{"role": "meta", "url": "file:///x/meta.json", "sha256": null,'
        ' "path": "flat-room/meta.json"}]'
    )
    var doc = read_json_text(
        List[UInt8](_manifest(_entry("flat-room", files=files)).as_bytes())
    )
    check_scan_manifest(doc, doc.root)
    var entry = entries_of(doc, doc.root)[0]
    assert_equal(resolve(doc, entry, "/nonexistent", Transport("false", 0)), 0)


def _refused(text: String, contains: String) raises:
    """Assert a manifest text is refused with a message."""
    var doc = read_json_text(List[UInt8](text.as_bytes()))
    with assert_raises(contains=contains):
        check_scan_manifest(doc, doc.root)


def test_the_manifest_rules() raises:
    """Each rule of the module docstring refuses its own mistake."""
    var good = _entry("flat-room")
    _refused("[]", "the manifest must be an object")
    _refused('{"format": 2, "entries": []}', "format must be 1")
    _refused('{"format": 1.0, "entries": []}', "format must be 1")
    _refused('{"format": 1, "entries": {}}', "entries must be a list")
    _refused(_manifest("3"), "entry 0 must be an object")
    _refused(_manifest('{"id": "x"}'), "missing title")
    _refused(
        _manifest(good.replace('"id": "flat-room"', '"id": ""')),
        "id must be a non-empty string",
    )
    _refused(
        _manifest(good.replace('"id": "flat-room"', '"id": "a/b"')),
        "id must be one file name",
    )
    _refused(
        '{"format": 1, "entries": [' + good + ", " + good + "]}",
        "duplicate id 'flat-room'",
    )
    _refused(
        _manifest(good.replace('"title": "Flat room"', '"title": ""')),
        "title must be",
    )
    _refused(
        _manifest(
            good.replace(
                "https://example.test/tester", "http://example.test/tester"
            )
        ),
        "author_url must be https://",
    )
    _refused(
        _manifest(_entry("x", "CC-BY-NC-4.0")),
        "license 'CC-BY-NC-4.0' is not one of",
    )
    _refused(
        _manifest(_entry("x", "CC-BY-ND-4.0")),
        "license 'CC-BY-ND-4.0' is not one of",
    )
    _refused(
        _manifest(good.replace('"kit": "masonry"', '"kit": "adobe"')),
        "kit 'adobe'",
    )
    _refused(
        _manifest(good.replace('"use": "living"', '"use": "bunker"')),
        "use 'bunker'",
    )
    _refused(
        _manifest(good.replace('"scene": "abc123"', '"scene": "a/b"')),
        "scene must be a scene id",
    )
    _refused(_manifest(_entry("x", frame="3")), "frame must be an object")
    _refused(
        _manifest(
            _entry(
                "x",
                frame=(
                    '{"up": "y", "north": "-z", "unit_m": 1, "scale":'
                    ' "declared"}'
                ),
            )
        ),
        "frame: up 'y' is not one of",
    )
    _refused(
        _manifest(
            _entry(
                "x",
                frame=(
                    '{"up": "-y", "north": "+y", "unit_m": 1, "scale":'
                    ' "declared"}'
                ),
            )
        ),
        "up and north must differ",
    )
    for unit in ["0", "-1", '"1"', "0.0", "-2.5", "NaN", "Infinity"]:
        _refused(
            _manifest(
                _entry(
                    "x",
                    frame='{"up": "-y", "north": "-z", "unit_m": '
                    + unit
                    + ', "scale": "declared"}',
                )
            ),
            "unit_m must be a positive number",
        )
    _refused(
        _manifest(
            _entry(
                "x",
                frame=(
                    '{"up": "-y", "north": "-z", "unit_m": 0.5, "scale":'
                    ' "guessed"}'
                ),
            )
        ),
        "scale 'guessed'",
    )
    _refused(_manifest(_entry("x", files="{}")), "files must be a list")
    _refused(_manifest(_entry("x", files="[1]")), "file 0 must be an object")
    var file = (
        '{"role": "image", "url": "file:///a.webp", "sha256": null, "path":'
        ' "x/a.webp"}'
    )
    _refused(
        _manifest(
            _entry("x", files="[" + file.replace('"image"', '"mesh"') + "]")
        ),
        "role 'mesh'",
    )
    _refused(
        _manifest(
            _entry(
                "x", files="[" + file.replace('"x/a.webp"', '"y/a.webp"') + "]"
            )
        ),
        "path must be the entry id",
    )
    _refused(
        _manifest(
            _entry(
                "x",
                files="[" + file.replace('"x/a.webp"', '"x/b/a.webp"') + "]",
            )
        ),
        "path must be the entry id",
    )
    _refused(
        _manifest(
            _entry(
                "x",
                files="[" + file.replace('"url": "file:///a.webp", ', "") + "]",
            )
        ),
        "needs a url, or null",
    )
    _refused(
        _manifest(
            _entry(
                "x",
                files="["
                + file.replace("file:///a.webp", "http://a.test/a.webp")
                + "]",
            )
        ),
        "a url must be https:// or file://",
    )
    _refused(
        _manifest(
            _entry("x", files="[" + file.replace('"sha256": null, ', "") + "]")
        ),
        "needs a sha256, or null",
    )
    _refused(
        _manifest(_entry("x", files="[" + file.replace("null", '"abc"') + "]")),
        "sha256 must be 64 hex digits",
    )
    _refused(
        _manifest(_entry("x", files="[" + file + ", " + file + "]")),
        "duplicate path 'x/a.webp'",
    )
    var hosted = file.replace('"file:///a.webp"', "null").replace(
        'null, "path"', '"' + "0" * 64 + '", "path"'
    )
    var doc = read_json_text(
        List[UInt8](_manifest(_entry("x", files="[" + hosted + "]")).as_bytes())
    )
    check_scan_manifest(doc, doc.root)
    # A file put in the cache by hand has no URL, and no sum until pinned.
    var placed = file.replace('"file:///a.webp"', "null")
    doc = read_json_text(
        List[UInt8](_manifest(_entry("x", files="[" + placed + "]")).as_bytes())
    )
    check_scan_manifest(doc, doc.root)


def test_file_names_and_sums() raises:
    """A file name has no folder; a sum is 64 lower-case hex digits."""
    assert_true(is_file_name("meta.json"))
    for name in ["", ".", "..", "a/b", "a\\\\b"]:
        assert_false(is_file_name(name))
    assert_true(is_sum("0123456789abcdef" * 4))
    assert_false(is_sum("0123456789ABCDEF" * 4))
    assert_false(is_sum("0123456789abcdeg" * 4))
    assert_false(is_sum("abc"))


def test_a_file_put_in_the_cache_by_hand_is_pinned() raises:
    """With no URL, a fetch says unhosted; once the file is placed, a
    pinning fetch records its sum and a later fetch keeps it."""
    var site = _Site("hand")
    var record = (
        '[{"role": "meta", "url": null, "sha256": null, "path":'
        ' "flat-room/meta.json"}]'
    )
    put(site.manifest, _manifest(_entry("flat-room", files=record)))
    assert_true(
        "unhosted  flat-room/meta.json" in site.run(["fetch", "--pin"]).output
    )
    put_bytes(
        site.cache + "/flat-room/meta.json",
        Path(SOURCE + "meta.json").read_bytes(),
    )
    var pinned = site.run(["fetch", "--pin"])
    assert_equal(pinned.status, 0)
    assert_true("pinned  flat-room/meta.json" in pinned.output)
    var doc = load_scan_manifest(site.manifest)
    var item = doc.item(doc.get(entries_of(doc, doc.root)[0], "files"), 0)
    assert_equal(doc.text(doc.get(item, "sha256")), _source_sum("meta.json"))
    assert_true("kept  flat-room/meta.json" in site.run(["fetch"]).output)
    assert_equal(runs(site.net), 0)


def test_the_command_line() raises:
    """Commands, ids, options and every usage error."""
    var parsed = parse_arguments(["--cache", "c", "fetch", "a", "b", "--pin"])
    assert_equal(parsed.status, 0)
    assert_equal(parsed.command, "fetch")
    assert_equal(len(parsed.ids), 2)
    assert_equal(parsed.cache, "c")
    assert_true(parsed.has("--pin"))
    assert_false(parsed.has("--all"))
    assert_equal(parse_arguments(["--manifest", "m", "check"]).manifest, "m")
    assert_equal(parse_arguments(["-h"]).status, -1)
    assert_true("commands:" in run(["--help"], Transport()).output)
    var errors: List[String] = [
        "required: command",
        "invalid choice: 'go'",
        "unrecognized arguments: --fast",
        "argument --cache: expected one argument",
        "--pin and --offline cannot be used together",
    ]
    var lines: List[List[String]] = [
        List[String](),
        ["go"],
        ["check", "--fast"],
        ["check", "--cache"],
        ["fetch", "--pin", "--offline"],
    ]
    for index in range(len(errors)):
        var outcome = run(lines[index].copy(), Transport())
        assert_equal(outcome.status, 2)
        assert_true(errors[index] in outcome.errors)


def test_an_unknown_id_or_manifest_is_an_error() raises:
    """A missing entry and a missing manifest each end with status 1."""
    var site = _Site("unknown")
    var outcome = site.run(["fetch", "nope"])
    assert_equal(outcome.status, 1)
    assert_true("no entry 'nope'" in outcome.errors)
    var missing = run(
        ["--manifest", site.root + "none.json", "check"], Transport()
    )
    assert_equal(missing.status, 1)


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
