# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check that wiki links name pages and headings that exist.

`tools/doc_lint.mojo` runs this check, so `make docs-check` reports each
broken wiki link in `README.md`, `CONTRIBUTING.md` and `docs/wiki/`.

A wiki page links another as `[text](Page)` or `[text](Page#anchor)`, and
any file can link `https://github.com/SethKitchen/ThreeMojo/wiki/Page`. A
same-page link is `[text](#anchor)`. Each named page must be a file in the
wiki folder, and each anchor must be a heading's anchor on that page.

Anchors follow GitHub: lower case, punctuation removed except `-` and `_`,
and each space changed to `-`. A repeated anchor gets the first free
`-1`, `-2` suffix, as github-slugger assigns it. Targets and anchors are
percent-decoded, and a link title after the target is ignored.

Fenced and inline code is not read. A fence closes only with its own
character, at least as many times as it opened. Links with a scheme, a
path or a file extension are not wiki links and are not checked.
"""

from std.os import listdir
from std.pathlib import Path

comptime WIKI = "docs/wiki"
"""The folder that holds the wiki pages."""
comptime WIKI_URL = "https://github.com/SethKitchen/ThreeMojo/wiki/"
"""The prefix of an absolute link to a wiki page."""

comptime _TICK = UInt8(96)
comptime _TILDE = UInt8(126)
comptime _HASH = UInt8(35)


struct Fence(Movable):
    """Track fenced code blocks the way CommonMark opens and closes them."""

    var marker: UInt8
    """The fence character, or 0 outside fenced code."""
    var length: Int
    """How many fence characters opened the block."""

    def __init__(out self):
        """Start outside fenced code."""
        self.marker = 0
        self.length = 0

    def is_code(mut self, line: String) -> Bool:
        """Return True if `line` opens, closes or lies inside fenced code.

        Args:
            line: One line of Markdown, without its newline.

        Returns:
            True when the line is a fence or code, and False for prose.
        """
        var bytes = line.as_bytes()
        var start = 0
        while start < len(bytes) and _is_space(bytes[start]):
            start += 1
        var run = 0
        var marker = UInt8(0)
        if start < len(bytes) and (
            bytes[start] == _TICK or bytes[start] == _TILDE
        ):
            marker = bytes[start]
            while start + run < len(bytes) and bytes[start + run] == marker:
                run += 1
        if self.marker == 0:
            if run < 3:
                return False
            if marker == _TICK:
                # A backtick fence's info string has no backtick.
                for i in range(start + run, len(bytes)):
                    if bytes[i] == _TICK:
                        return False
            self.marker = marker
            self.length = run
            return True
        if marker == self.marker and run >= self.length:
            var rest = start + run
            while rest < len(bytes) and _is_space(bytes[rest]):
                rest += 1
            if rest == len(bytes):
                self.marker = 0
        return True


def _is_space(byte: UInt8) -> Bool:
    return byte == 32 or byte == 9 or byte == 13


def _text(bytes: List[UInt8]) raises -> String:
    return String(from_utf8=Span(bytes))


def _run(bytes: Span[UInt8, _], at: Int) -> Int:
    var end = at
    while end < len(bytes) and bytes[end] == bytes[at]:
        end += 1
    return end - at


def code_spans(line: String, keep: Bool) raises -> String:
    """Remove each inline code span from `line`, or keep only its text.

    A span opens with a run of backticks and closes with the next run of
    the same length. An unclosed run is literal text.

    Args:
        line: One line of Markdown.
        keep: True to keep each span's text without its backticks.

    Returns:
        The line with its code spans removed or unwrapped.

    Raises:
        Error: If the line is not valid UTF-8.
    """
    var bytes = line.as_bytes()
    var out = List[UInt8]()
    var i = 0
    while i < len(bytes):
        if bytes[i] != _TICK:
            out.append(bytes[i])
            i += 1
            continue
        var run = _run(bytes, i)
        var close = -1
        var j = i + run
        while j < len(bytes):
            if bytes[j] != _TICK:
                j += 1
                continue
            var other = _run(bytes, j)
            if other == run:
                close = j
                break
            j += other
        if close < 0:
            for _ in range(run):
                out.append(_TICK)
        elif keep:
            for k in range(i + run, close):
                out.append(bytes[k])
        i = i + run if close < 0 else close + run
    return _text(out)


def _hex(byte: UInt8) -> Int:
    if byte >= 48 and byte <= 57:
        return Int(byte) - 48
    if byte >= 65 and byte <= 70:
        return Int(byte) - 55
    if byte >= 97 and byte <= 102:
        return Int(byte) - 87
    return -1


def percent_decode(text: String) -> String:
    """Return `text` with each `%XX` escape replaced by its byte.

    Args:
        text: A link target or anchor.

    Returns:
        The decoded text, or `text` itself if the bytes are not UTF-8.
    """
    var bytes = text.as_bytes()
    var out = List[UInt8]()
    var i = 0
    while i < len(bytes):
        if bytes[i] == 37 and i + 2 < len(bytes):
            var high = _hex(bytes[i + 1])
            var low = _hex(bytes[i + 2])
            if high >= 0 and low >= 0:
                out.append(UInt8(high * 16 + low))
                i += 3
                continue
        out.append(bytes[i])
        i += 1
    try:
        return _text(out)
    except:
        return text


def _drops(ch: String) -> Bool:
    """Return True if a slug drops the character `ch`."""
    var bytes = ch.as_bytes()
    if len(bytes) > 1:
        # Only common Unicode punctuation; letters stay, as on GitHub.
        for mark in ["—", "–", "‘", "’", "“", "”", "…", "·", "×", "→", "←"]:
            if ch == mark:
                return True
        return False
    var byte = bytes[0]
    var digit = byte >= 48 and byte <= 57
    var letter = byte >= 97 and byte <= 122
    return not (digit or letter or byte == 45 or byte == 95 or byte == 32)


def slug(heading: String) raises -> String:
    """Return GitHub's anchor for a heading's text.

    Args:
        heading: The heading text without its `#` markers.

    Returns:
        The anchor before any repeat suffix.

    Raises:
        Error: If the heading is not valid UTF-8.
    """
    var text = code_spans(heading, True)
    var out = String("")
    var in_target = False
    var previous = String("")
    for cp in String(String(text.strip()).lower()).codepoint_slices():
        var ch = String(cp)
        # A link keeps its text; its target is not part of the anchor.
        if in_target:
            in_target = ch != ")"
        elif ch == "(" and previous == "]":
            in_target = True
        elif ch == " ":
            out += "-"
        elif not _drops(ch):
            out += ch
        previous = ch
    return out^


def _heading(line: String) raises -> Tuple[Bool, String]:
    """Return whether `line` is an ATX heading, and its text."""
    var bytes = line.as_bytes()
    var start = 0
    while start < len(bytes) and start < 4 and bytes[start] == 32:
        start += 1
    var level = 0
    while start + level < len(bytes) and bytes[start + level] == _HASH:
        level += 1
    var after = start + level
    if (
        start > 3
        or level == 0
        or level > 6
        or (after < len(bytes) and not _is_space(bytes[after]))
    ):
        return (False, String(""))
    var end = len(bytes)
    while end > after and _is_space(bytes[end - 1]):
        end -= 1
    # A closing run of `#` needs a space before it, or no text at all.
    var close = end
    while close > after and bytes[close - 1] == _HASH:
        close -= 1
    if close == after or _is_space(bytes[close - 1]):
        end = close
    var content = List[UInt8]()
    for i in range(after, end):
        content.append(bytes[i])
    return (True, String(_text(content).strip()))


def anchors(text: String) raises -> Dict[String, Int]:
    """Return the heading anchors on a page, with their repeat suffixes.

    github-slugger gives each heading its slug, or the slug with the first
    free `-1`, `-2` suffix. So `x-1, x, x` gives `x-1, x, x-2`, and
    `x, x, x-1` gives `x, x-1, x-1-1`.

    Args:
        text: The page's Markdown.

    Returns:
        Each anchor on the page as a key.

    Raises:
        Error: If the page is not valid UTF-8.
    """
    var seen = Dict[String, Int]()
    var fence = Fence()
    for raw in text.split("\n"):
        var line = String(raw)
        if fence.is_code(line):
            continue
        var heading = _heading(line)
        if not heading[0]:
            continue
        var base = slug(heading[1])
        var result = base
        while result in seen:
            seen[base] = seen[base] + 1
            result = base + "-" + String(seen[base])
        seen[result] = 0
    return seen^


def link_targets(line: String) raises -> List[String]:
    """Return the target of each inline link in `line`, without its title.

    Args:
        line: One line of prose with its code spans removed.

    Returns:
        Each target in order. A `<...>` target loses its angle brackets.

    Raises:
        Error: If the line is not valid UTF-8.
    """
    var bytes = line.as_bytes()
    var targets = List[String]()
    var i = 0
    while i + 1 < len(bytes):
        if bytes[i] != 93 or bytes[i + 1] != 40:
            i += 1
            continue
        var start = i + 2
        var angle = start < len(bytes) and bytes[start] == 60
        if angle:
            start += 1
        var end = start
        while end < len(bytes):
            if angle:
                if bytes[end] == 62:
                    break
            elif bytes[end] == 41 or _is_space(bytes[end]):
                break
            end += 1
        var target = List[UInt8]()
        for k in range(start, end):
            target.append(bytes[k])
        targets.append(_text(target))
        i = end
    return targets^


def _is_page(name: String) -> Bool:
    var bytes = name.as_bytes()
    if len(bytes) == 0:
        return False
    for i in range(len(bytes)):
        var byte = bytes[i]
        var alnum = (
            (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
        )
        if not (alnum or (i > 0 and (byte == 45 or byte == 95))):
            return False
    return True


def _folder(path: String) -> String:
    var clean = path.removeprefix("./")
    var cut = clean.rfind("/")
    return String(clean[byte=:cut]) if cut >= 0 else String("")


def check_links(
    paths: List[String], wiki: String = WIKI
) raises -> List[String]:
    """Return one problem line for each broken wiki link in `paths`.

    Args:
        paths: The Markdown files to check.
        wiki: The folder that holds the wiki pages.

    Returns:
        One `path:line: problem` line per broken link, empty if all resolve.

    Raises:
        Error: If a file cannot be read or is not valid UTF-8.
    """
    var folder = String(wiki.removeprefix("./").removesuffix("/"))
    var pages = Dict[String, String]()
    for name in listdir(Path(folder)):
        if name.endswith(".md"):
            pages[String(name.removesuffix(".md"))] = folder + "/" + name
    var cache = Dict[String, Dict[String, Int]]()
    var problems = List[String]()
    for path in paths:
        var text = Path(path).read_text()
        var own = anchors(text)
        var in_wiki = _folder(path) == folder
        var fence = Fence()
        var number = 0
        for raw in text.split("\n"):
            number += 1
            var line = String(raw)
            if fence.is_code(line):
                continue
            for found in link_targets(code_spans(line, False)):
                var target = found
                if target.startswith(WIKI_URL):
                    var rest = String(found.removeprefix(WIKI_URL))
                    target = rest^
                elif not in_wiki and not target.startswith("#"):
                    continue
                var cut = target.find("#")
                var page = percent_decode(
                    String(target[byte=:cut]) if cut >= 0 else target
                )
                var anchor = percent_decode(
                    String(target[byte = cut + 1 :]) if cut >= 0 else String("")
                )
                var at = path + ":" + String(number) + ": "
                if page == "":
                    if anchor != "" and anchor not in own:
                        problems.append(at + "no heading for #" + anchor)
                    continue
                if not _is_page(page):
                    continue
                if page not in pages:
                    problems.append(at + 'no wiki page "' + page + '"')
                    continue
                if anchor == "":
                    continue
                if page not in cache:
                    cache[page] = anchors(Path(pages[page]).read_text())
                if anchor not in cache[page]:
                    problems.append(
                        at + "no heading for " + page + "#" + anchor
                    )
    return problems^
