# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The wiki link check in `make docs-check` (#687).

The numbered cases are the independent review's 33-case packet on #692.
Each runs in its own folder, and its expected problems are exhaustive.
"""

from std.os import makedirs
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from test_scratch import TestScratch, temporary_path
from tools.doc_lint import (
    Fence,
    anchors,
    check_links,
    percent_decode,
    slug,
)


def _case(
    name: String,
    source: String,
    expected: List[String],
    targets: List[String] = [],
    readme: Bool = False,
) raises:
    """Check `source` in a fresh folder against `targets`, given as
    alternating page names and texts. `expected` holds `line: problem`."""
    var root = temporary_path(name)
    var wiki = root + "/docs/wiki"
    makedirs(wiki, exist_ok=True)
    for k in range(0, len(targets), 2):
        Path(wiki + "/" + targets[k] + ".md").write_text(targets[k + 1])
    var path = root + "/README.md" if readme else wiki + "/Source.md"
    Path(path).write_text(source)
    var found = check_links([path], wiki)
    var message = name + ": " + String(", ").join(found)
    assert_equal(len(found), len(expected), message)
    for k in range(len(found)):
        assert_equal(found[k], path + ":" + expected[k], message)


def _missing(line: Int, page: String) -> String:
    return String(line) + ': no wiki page "' + page + '"'


def test_review_cases_01_to_10() raises:
    var target: List[String] = ["Target", "# Section\n"]
    _case(
        "01",
        (
            "````markdown\n```\n[in"
            " code](CodeOnlyMissing)\n````\n[real](RealMissing)\n"
        ),
        [_missing(5, "RealMissing")],
    )
    _case("02", "# x\n# x\n# x-1\n[valid](#x-1-1)\n", [])
    _case("03", "# x-1\n# x\n# x\n[valid](#x-2)\n", [])
    _case("04", "[valid](Target#%73ection)\n", [], target)
    _case("05", "[bad](%4dissing)\n", [_missing(1, "Missing")])
    _case(
        "06",
        "[bad](https://github.com/SethKitchen/ThreeMojo/wiki/%4dissing)\n",
        [_missing(1, "Missing")],
        readme=True,
    )
    _case("07", '[bad](Missing "A title")\n', [_missing(1, "Missing")])
    _case(
        "08",
        '[bad](Target#gone "A title")\n',
        ["1: no heading for Target#gone"],
        target,
    )
    _case("09", "`code\n[x](CodeOnlyMissing)\n`\n", [])
    _case(
        "10",
        (
            "![alt](image.png)\n[site](https://example.org/Missing)\n"
            "[mail](mailto:a@example.org)\n"
        ),
        [],
    )


def test_review_cases_11_to_21() raises:
    _case("11", "![alt](Badge)\n", [])
    _case(
        "12",
        "[ok](Target#section)\n[bad](Missing)\n[bad](Target#gone)\n",
        [_missing(2, "Missing"), "3: no heading for Target#gone"],
        ["Target", "# Section\n"],
    )
    _case(
        "13",
        "[outer [inner](Missing)](Known)\n",
        [_missing(1, "Missing")],
        ["Known", "# Known\n"],
    )
    _case(
        "14",
        "`code\n| [hidden](Missing)\nend`\n[real](RealMissing)\n",
        [_missing(4, "RealMissing")],
    )
    _case("15", "# \\_name\\_\n[valid](#_name_)\n", [])
    _case("16", "# _name\n[valid](#_name)\n", [])
    _case("17", "# `_name_`\n[valid](#_name_)\n", [])
    _case(
        "18",
        "`unmatched\n***\n[real](RealMissing) `\n",
        [_missing(3, "RealMissing")],
    )
    _case(
        "19", "Text <!--> [real](RealMissing)\n", [_missing(1, "RealMissing")]
    )
    _case("20", "[file](image%2Epng)\n", [])
    _case(
        "21",
        "| First | Second |\n| --- | --- |\n| `open | [real](Missing) ` |\n",
        [_missing(3, "Missing")],
    )


def test_review_container_cases_22_to_27() raises:
    _case(
        "22",
        (
            "[before](BeforeMissing)\n> ```md\n> [hidden](CodeOnlyMissing)\n"
            "> ```\n[after](AfterMissing)\n"
        ),
        [_missing(1, "BeforeMissing"), _missing(5, "AfterMissing")],
    )
    _case(
        "23",
        "> ```\n> [hidden](CodeOnlyMissing)\n[real](RealMissing)\n",
        [_missing(3, "RealMissing")],
    )
    _case(
        "24",
        (
            "> > ~~~~md\n> > ~~~\n> > [hidden](CodeOnlyMissing)\n> > ~~~~~\n"
            "> [real](RealMissing)\n"
        ),
        [_missing(5, "RealMissing")],
    )
    _case(
        "25",
        "- ```md\n  [hidden](CodeOnlyMissing)\n  ```\n- [real](RealMissing)\n",
        [_missing(4, "RealMissing")],
    )
    _case(
        "26",
        (
            "- Item\n\n  ```md\n  [hidden](CodeOnlyMissing)\n  ```\n"
            "  [inside](InsideMissing)\n\n[outside](OutsideMissing)\n"
        ),
        [_missing(6, "InsideMissing"), _missing(8, "OutsideMissing")],
    )
    _case(
        "27",
        (
            "10. ```md\n    [hidden](CodeOnlyMissing)\n    ```\n"
            "11. [real](RealMissing)\n"
        ),
        [_missing(4, "RealMissing")],
    )


def test_review_container_cases_28_to_33() raises:
    _case(
        "28",
        "- ```md\n  [hidden](CodeOnlyMissing)\n- [real](RealMissing)\n",
        [_missing(3, "RealMissing")],
    )
    _case(
        "29",
        (
            "- > ```md\n  > [hidden](CodeOnlyMissing)\n  > ```\n"
            "  [inside](InsideMissing)\n\n[outside](OutsideMissing)\n"
        ),
        [_missing(4, "InsideMissing"), _missing(6, "OutsideMissing")],
    )
    _case(
        "30",
        (
            "> - ```md\n>   [hidden](CodeOnlyMissing)\n>   ```\n"
            "> - [inside](InsideMissing)\n[outside](OutsideMissing)\n"
        ),
        [_missing(4, "InsideMissing"), _missing(5, "OutsideMissing")],
    )
    _case(
        "31",
        (
            "- Parent\n  - ```md\n    [hidden](CodeOnlyMissing)\n    ```\n"
            "  - [inside](InsideMissing)\n- [outside](OutsideMissing)\n"
        ),
        [_missing(5, "InsideMissing"), _missing(6, "OutsideMissing")],
    )
    _case(
        "32",
        (
            "> ```md\n> ``` trailing\n> [hidden](CodeOnlyMissing)\n> ```\n"
            "[real](RealMissing)\n"
        ),
        [_missing(5, "RealMissing")],
    )
    _case(
        "33",
        (
            "> ```\n> [hidden](CodeOnlyMissing)\n> ```\n\n- ~~~\n"
            "  [hidden](AlsoCodeOnlyMissing)\n  ~~~\n"
        ),
        [],
    )


def test_review_cases_34_to_40() raises:
    # The second packet: references, inline HTML, escapes, raw HTML.
    _case("34", "# A &amp; B\n[valid](#a--b)\n", [])
    _case("35", "# <em>Title</em>\n[valid](#title)\n", [])
    _case("36", "[bad](M&#105;ssing)\n", [_missing(1, "Missing")])
    _case("37", "[bad](Missing\\_Page)\n", [_missing(1, "Missing_Page")])
    _case(
        "38",
        "<pre>\n[hidden](CodeOnlyMissing)\n</pre>\n[real](RealMissing)\n",
        [_missing(4, "RealMissing")],
    )
    _case(
        "39",
        "<pre>\n\n[hidden](CodeOnlyMissing)\n</pre>\n[real](RealMissing)\n",
        [_missing(5, "RealMissing")],
    )
    _case("40", "[valid](Target#se&#99;tion)\n", [], ["Target", "# Section\n"])
    # Named references outside any short list, an unknown name and a
    # reference without its semicolon, which both stay text.
    _case(
        "42",
        (
            "# &Aacute;rbol\n# &notaname; X\n# &amp B\n"
            "[a](#%C3%A1rbol) [b](#notaname-x) [c](#amp-b)\n"
            "[bad](Missing&lowbar;Page)\n"
        ),
        [_missing(5, "Missing_Page")],
    )
    # github-slugger drops U+00AB and U+00A0, written as a reference or
    # as the character.
    _case("43", "# A&laquo;B\n[ok](#ab)\n# A«B\n[ok](#ab-1)\n", [])
    var nbsp = chr(0xA0)
    _case(
        "44",
        "# A&nbsp;B\n[ok](#ab)\n# A" + nbsp + "B\n[ok](#ab-1)\n",
        [],
    )
    # Letters, combining marks, digits and connectors stay.
    var mark = chr(0x301)
    _case(
        "45",
        "# Árbol e" + mark + " x² ‿ y\n[ok](#árbol-e" + mark + "-x-‿-y)\n",
        [],
    )
    # A hexadecimal reference, an unknown name and a one-line raw block.
    _case(
        "41",
        (
            "# X &#x41; &bogus; Y\n[ok](#x-a-bogus-y)\n\n"
            "<script>[a](Nope)</script>\n[real](RealMissing)\n"
        ),
        [_missing(5, "RealMissing")],
    )


def test_wiki_pages_readme_and_html_blocks() raises:
    var pages: List[String] = [
        "Model-files",
        "# Model files\n\n## glTF\n\n## glTF\n\n### `GltfModel` reads it\n",
    ]
    _case(
        "good",
        (
            "# Geometry\n\nSee [one](Model-files#gltf),"
            " [two](Model-files#gltf-1),"
            " [three](Model-files#gltfmodel-reads-it), [up](#geometry) and"
            " [a file](../../tools/x.py).\n"
        ),
        [],
        pages,
    )
    _case(
        "readme",
        (
            "# Readme\n\n<details>\n<summary>[skip](Html)</summary>\n\n- [x]"
            " [ok](https://github.com/SethKitchen/ThreeMojo/wiki/Model-files)\n-"
            " [bad](https://github.com/SethKitchen/ThreeMojo/wiki/Nope)\n-"
            " [file](LICENSE) and [top](#readme) and [gone](#gone)\n<!--"
            " [comment](Nope)\n[still](Nope) -->\n"
        ),
        [_missing(7, "Nope"), "8: no heading for #gone"],
        pages,
        readme=True,
    )
    _case(
        "setext",
        (
            "Title here\n===\n\nSub\n---\n\n   "
            " [indented](Nope)\n\n[a](#title-here) [b](#sub)\n"
        ),
        [],
    )
    _case(
        "heading-link",
        "## See [the page](Nope)\n\n[a](#see-the-page)\n",
        [_missing(1, "Nope")],
    )


def test_fence_rules() raises:
    var fence = Fence()
    # An info string with a backtick is not a fence.
    assert_false(fence.is_code("``` a`b"))
    assert_true(fence.is_code("~~~~ text"))
    # Another character, a shorter run or trailing text does not close.
    assert_true(fence.is_code("```"))
    assert_true(fence.is_code("~~~"))
    assert_true(fence.is_code("~~~~ more"))
    assert_true(fence.is_code("~~~~~  "))
    assert_false(fence.is_code("prose"))
    assert_false(fence.is_code("``"))


def test_repeated_headings_take_the_first_free_suffix() raises:
    var first = anchors("# x-1\n\n# x\n\n# x\n")
    assert_true("x-2" in first)
    assert_equal(len(first), 3)
    var second = anchors("# x\n\n# x\n\n# x-1\n")
    assert_true("x-1-1" in second)
    assert_equal(len(second), 3)


def test_slugs_follow_github() raises:
    assert_equal(slug("`GltfModel` reads it"), "gltfmodel-reads-it")
    assert_equal(slug("Read [the guide](Guide) now"), "read-the-guide-now")
    assert_equal(slug("A — B: C++ and snake_case"), "a--b-c-and-snake_case")
    assert_equal(slug("_name_ and __init__"), "name-and-init")
    assert_equal(slug("Diátaxis"), "diátaxis")
    var found = anchors("## C#\n\n## Closed ##\n\n#NotAHeading\n")
    assert_true("c" in found)
    assert_true("closed" in found)
    assert_equal(len(found), 2)
    var deep = anchors("    # code\n\n####### seven\n\n###### six\n")
    assert_equal(len(deep), 1)
    assert_true("six" in deep)


def test_percent_decoding() raises:
    assert_equal(percent_decode("%4dissing%2Fx"), "Missing/x")
    assert_equal(percent_decode("100%zz%2"), "100%zz%2")
    # Bytes that are not UTF-8 leave the text unchanged.
    assert_equal(percent_decode("%C3"), "%C3")
    assert_equal(percent_decode("di%C3%A1taxis"), "diátaxis")


def main() raises:
    with TestScratch():
        TestSuite.discover_tests[__functions_in_module()]().run()
