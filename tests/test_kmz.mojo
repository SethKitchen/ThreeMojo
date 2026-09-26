# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.kmz`: `assets/kmz/model.kmz`, which
`assets/kmz/make_kmz.mjs` zips with three.js 0.180's fflate, read as
three.js's `KMZLoader` finds its model and its images.

The model is read by `load_collada`, which `tests/test_collada.mojo`
tests. So these tests compare what the archive gives with what the model
and its image give when they are read from the disk.
"""

from core.assets import Assets
from core.buffer_geometry import POSITION, UV
from core.object3d import NO_PARENT
from core.scene import Scene
from loaders.collada import ColladaModel, load_collada
from loaders.kmz import kml_model_path, parse_kmz, read_kmz
from loaders.zip import ZIP_STORED, ZipEntry, zip_archive
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _entry(name: String, text: String) -> ZipEntry:
    """Return a stored file of text.

    Args:
        name: Its name.
        text: Its text.

    Returns:
        The entry.
    """
    return ZipEntry(name, ZIP_STORED, List[UInt8](text.as_bytes()))


def _same(
    got: ColladaModel,
    got_assets: Assets,
    want: ColladaModel,
    want_assets: Assets,
) raises:
    """Assert two reads built the same triangle with the same texture.

    Args:
        got: The archive's model.
        got_assets: Its assets.
        want: The model read from the disk.
        want_assets: Its assets.
    """
    assert_equal(len(got.geometries), len(want.geometries))
    for name in [POSITION, UV]:
        var a = (
            got_assets.geometries.get(got.geometries[0])
            .attribute_view(String(name))
            .packed()
        )
        var b = (
            want_assets.geometries.get(want.geometries[0])
            .attribute_view(String(name))
            .packed()
        )
        assert_equal(len(a), len(b))
        for at in range(len(a)):
            assert_equal(a[at], b[at])
    assert_equal(len(got.textures), 1)
    ref image = got_assets.textures.get(got.textures[0])
    ref brick = want_assets.textures.get(want.textures[0])
    assert_equal(image.width, brick.width)
    assert_equal(len(image.pixels), len(brick.pixels))
    for at in range(len(image.pixels)):
        assert_equal(image.pixels[at], brick.pixels[at])
    assert_equal(got.node_names[0], "tri")


def test_the_model_doc_kml_names_is_read_with_its_image() raises:
    var scene = Scene()
    var assets = Assets()
    var model = read_kmz("assets/kmz/model.kmz", scene, assets)
    var disk_scene = Scene()
    var disk_assets = Assets()
    var disk = load_collada(
        Path("assets/kmz/tri.dae").read_text(),
        "assets/",
        disk_scene,
        disk_assets,
    )
    _same(model, assets, disk, disk_assets)


def test_with_no_doc_kml_the_first_dae_is_read() raises:
    var dae = Path("assets/kmz/tri.dae").read_text()
    var brick = Path("assets/brick.png").read_bytes()
    # The first file named `.DAE`, in any case, and the last of its name.
    var archive = zip_archive(
        [
            _entry("readme.txt", "not a model"),
            _entry("Tri.DAE", "not XML either"),
            ZipEntry("textures/brick.png", ZIP_STORED, brick.copy()),
            _entry("Tri.DAE", dae),
            _entry("other.dae", "never read"),
        ]
    )
    var scene = Scene()
    var assets = Assets()
    var model = parse_kmz(archive, scene, assets)
    var disk_scene = Scene()
    var disk_assets = Assets()
    var disk = load_collada(dae, "assets/", disk_scene, disk_assets)
    _same(model, assets, disk, disk_assets)


def test_an_image_not_in_the_archive_is_read_from_the_directory() raises:
    var dae = Path("assets/kmz/tri.dae").read_text()
    var archive = zip_archive([_entry("m.dae", dae)])
    var scene = Scene()
    var assets = Assets()
    var model = parse_kmz(archive, scene, assets, "assets/")
    assert_equal(len(model.textures), 1)


def test_a_kml_names_its_model_as_three_js_selects_it() raises:
    # A prefix does not matter; an `href` outside the chain is passed.
    var kml = (
        "<k:kml xmlns:k='x'><k:href>no</k:href><Placemark><Link>"
        + "<href>no</href></Link><Model><Link><href> a.dae</href>"
        + "</Link></Model></Placemark></k:kml>"
    )
    assert_equal(kml_model_path(kml).value(), " a.dae")
    var outside = "<kml><Model><Link><href>x</href></Link></Model></kml>"
    assert_true(not kml_model_path(outside))


def test_nothing_to_read_gives_an_empty_node() raises:
    for archive in [
        zip_archive([_entry("doc.kml", "<kml/>"), _entry("a.dae", "x")]),
        zip_archive([_entry("a.txt", "x"), _entry("notes", "x")]),
        zip_archive([]),
    ]:
        var scene = Scene()
        var assets = Assets()
        var model = parse_kmz(archive, scene, assets)
        assert_equal(len(model.geometries), 0)
        assert_equal(len(scene.meshes), 0)
        assert_true(scene.node(model.root).parent == NO_PARENT)


def test_what_three_js_would_throw_on_is_refused() raises:
    var scene = Scene()
    var assets = Assets()
    var missing = (
        "<kml><Placemark><Model><Link><href>gone.dae</href></Link></Model>"
        + "</Placemark></kml>"
    )
    with assert_raises(contains="gone.dae, which is not here"):
        _ = parse_kmz(zip_archive([_entry("doc.kml", missing)]), scene, assets)
    var bad = ZipEntry("doc.kml", ZIP_STORED, [0xFF, 0xFE])
    with assert_raises(contains="doc.kml is not UTF-8"):
        _ = parse_kmz(zip_archive([bad^]), scene, assets)
    with assert_raises():
        _ = parse_kmz(zip_archive([_entry("doc.kml", "<kml")]), scene, assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
