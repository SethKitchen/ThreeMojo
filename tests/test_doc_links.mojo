# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The wiki link check in `make docs-check` (#687)."""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from test_scratch import TestScratch, temporary_path
from tools.doc_links import (
    Fence,
    anchors,
    check_links,
    code_spans,
    link_targets,
    percent_decode,
    slug,
)


def _wiki() raises -> String:
    var wiki = temporary_path("docs/wiki")
    makedirs(wiki, exist_ok=True)
    Path(wiki + "/Model-files.md").write_text(
        "# Model files\n\n## glTF\n\n## glTF\n\n### `GltfModel` reads it\n"
    )
    Path(wiki + "/Target.md").write_text("# Target\n\n## Section\n")
    return wiki


def _page(wiki: String, name: String, text: String) raises -> List[String]:
    var path = wiki + "/" + name
    Path(path).write_text(text)
    return [path]


def _check(wiki: String, name: String, text: String) raises -> List[String]:
    return check_links(_page(wiki, name, text), wiki)


def test_good_links_pass() raises:
    var wiki = _wiki()
    var found = _check(
        wiki,
        "Geometry.md",
        (
            "# Geometry\n\nSee the [loader](Model-files#gltf), the"
            " [second](Model-files#gltf-1), [the"
            " model](Model-files#gltfmodel-reads-it), [files](Model-files),"
            " [up](#geometry), [three.js](https://threejs.org/docs/) and [a"
            " file](../../tools/x.py).\n"
        ),
    )
    assert_equal(len(found), 0)


def test_missing_page_and_anchor_fail() raises:
    var wiki = _wiki()
    var path = wiki + "/Geometry.md"
    var found = _check(
        wiki,
        "Geometry.md",
        (
            "# Geometry\n\nThe [glTF loader](glTF) and [a"
            " part](Model-files#gltf-2) and [here](#nowhere).\n"
        ),
    )
    assert_equal(len(found), 3)
    assert_equal(found[0], path + ':3: no wiki page "glTF"')
    assert_equal(found[1], path + ":3: no heading for Model-files#gltf-2")
    assert_equal(found[2], path + ":3: no heading for #nowhere")


def test_code_is_not_read() raises:
    var wiki = _wiki()
    var found = _check(
        wiki,
        "Scene.md",
        (
            "# Scene\n\n`objects_by_property[order](3)` is code.\n\n"
            "```mojo\nvar b = make[DType.uint8](256)\n[x](Missing)\n```\n\n"
            "~~~\n[y](Missing)\n~~~\n"
        ),
    )
    assert_equal(len(found), 0)


def test_a_fence_closes_only_with_its_own_length() raises:
    # Review case 1: an inner three-backtick line does not close a
    # four-backtick fence, so only the link after the fence is read.
    var wiki = _wiki()
    var path = wiki + "/Fence.md"
    var found = _check(
        wiki,
        "Fence.md",
        (
            "# Fence\n\n````\n```\n[in code](CodeOnlyMissing)\n````\n\n"
            "[real](RealMissing)\n"
        ),
    )
    assert_equal(len(found), 1)
    assert_equal(found[0], path + ':8: no wiki page "RealMissing"')


def test_fence_rules() raises:
    var fence = Fence()
    # An info string with a backtick is not a fence.
    assert_false(fence.is_code("``` a`b"))
    assert_true(fence.is_code("  ~~~~ text"))
    # Another character, a shorter run or trailing text does not close.
    assert_true(fence.is_code("```"))
    assert_true(fence.is_code("~~~"))
    assert_true(fence.is_code("~~~~ more"))
    assert_true(fence.is_code("~~~~~  "))
    assert_false(fence.is_code("prose"))
    assert_false(fence.is_code("``"))


def test_repeated_headings_take_the_first_free_suffix() raises:
    # Review case 2, as github-slugger assigns the anchors.
    var first = anchors("# x-1\n\n# x\n\n# x\n")
    assert_true("x-1" in first)
    assert_true("x" in first)
    assert_true("x-2" in first)
    assert_equal(len(first), 3)
    var second = anchors("# x\n\n# x\n\n# x-1\n")
    assert_true("x-1-1" in second)
    assert_equal(len(second), 3)
    var wiki = _wiki()
    var found = _check(
        wiki,
        "Repeat.md",
        "# x-1\n\n# x\n\n# x\n\n[two](#x-2)\n",
    )
    assert_equal(len(found), 0)


def test_targets_are_decoded_and_lose_their_titles() raises:
    # Review cases 3 and 4.
    var wiki = _wiki()
    var path = wiki + "/Decode.md"
    var found = _check(
        wiki,
        "Decode.md",
        (
            '# Decode\n\n[encoded](%4dissing) and [titled](Missing "A'
            ' title") and [angle](<Missing>) and [ok](Target#%73ection).\n'
        ),
    )
    assert_equal(len(found), 3)
    for problem in found:
        assert_equal(problem, path + ':3: no wiki page "Missing"')


def test_readme_wiki_urls_are_checked() raises:
    var wiki = _wiki()
    var readme = temporary_path("README.md")
    Path(readme).write_text(
        "# Readme\n\n-"
        " [ok](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files#gltf)\n-"
        " [bad](https://github.com/SethKitchen/ThreeMojo/wiki/Nope)\n-"
        " [local](docs/wiki/Model-files.md), [file](LICENSE) and"
        " [top](#readme)\n"
    )
    var found = check_links([readme], wiki)
    assert_equal(len(found), 1)
    assert_equal(found[0], readme + ':4: no wiki page "Nope"')


def test_slugs_follow_github() raises:
    assert_equal(slug("`GltfModel` reads it"), "gltfmodel-reads-it")
    assert_equal(slug("Read [the guide](Guide) now"), "read-the-guide-now")
    assert_equal(slug("A — B: C++ and snake_case"), "a--b-c-and-snake_case")
    assert_equal(slug("Diátaxis"), "diátaxis")
    # A closing run of `#` needs a space before it.
    var found = anchors("## C#\n\n## Closed ##\n\n#NotAHeading\n")
    assert_true("c" in found)
    assert_true("closed" in found)
    assert_equal(len(found), 2)
    var deep = anchors("    # code\n\n####### seven\n\n###### six\n")
    assert_equal(len(deep), 1)
    assert_true("six" in deep)


def test_inline_code_and_link_targets() raises:
    assert_equal(code_spans("a `b` c ``d ` e`` f", False), "a  c  f")
    assert_equal(code_spans("a `b` c", True), "a b c")
    assert_equal(
        code_spans("an ``unclosed ` run", False), "an ``unclosed ` run"
    )
    var targets = link_targets('[a](One) [b](Two#x "t") [c](<Three>) [d](')
    assert_equal(len(targets), 4)
    assert_equal(targets[0], "One")
    assert_equal(targets[1], "Two#x")
    assert_equal(targets[2], "Three")
    assert_equal(targets[3], "")


def test_percent_decoding() raises:
    assert_equal(percent_decode("%4dissing%2Fx"), "Missing/x")
    assert_equal(percent_decode("100%zz%2"), "100%zz%2")
    # Bytes that are not UTF-8 leave the text unchanged.
    assert_equal(percent_decode("%C3"), "%C3")
    assert_equal(percent_decode("di%C3%A1taxis"), "diátaxis")


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
