# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check Markdown documentation against the house writing rules.

    mojo run -I . tools/doc_lint.mojo README.md docs/wiki/*.md

The rules come from ASD-STE100, Simplified Technical English:

- A sentence has at most `MAX_WORDS` words.
- A paragraph has at most `MAX_SENTENCES` sentences.
- The words "should", "may" and "might" do not appear. Use "must" for a
  requirement and "can" for a possibility.
- The spelling is American English: "color", "meter", "center", "gray".

Code blocks, tables, headings, badges and HTML comments are not checked.
Inline code and link targets do not count as words. The tool also checks
that each wiki link names a page and a heading that exist. It prints one
line per problem and exits with an error when there is at least one.
"""

from std.os import listdir
from std.pathlib import Path
from std.sys import argv

comptime MAX_WORDS = 25
comptime MAX_SENTENCES = 6


def _clean(line: String) -> String:
    """Return `line` with inline code, link targets and emphasis removed."""
    var out = String("")
    var in_code = False
    var in_target = False
    var after_bracket = False
    for cp in line.codepoint_slices():
        var ch = String(cp)
        if in_code:
            if ch == "`":
                in_code = False
                out += "code"
            continue
        if in_target:
            if ch == ")":
                in_target = False
            continue
        if ch == "`":
            in_code = True
            after_bracket = False
            continue
        if ch == "(" and after_bracket:
            in_target = True
            after_bracket = False
            continue
        after_bracket = ch == "]"
        if ch == "[" or ch == "]" or ch == "*" or ch == "!":
            continue
        out += ch
    return out^


def _sentences(text: String) -> List[String]:
    """Split `text` into sentences at a full stop, question or exclamation
    mark that is followed by a space or the end of the text."""
    var chars = List[String]()
    for cp in text.codepoint_slices():
        chars.append(String(cp))
    var sentences = List[String]()
    var current = String("")
    for index in range(len(chars)):
        var ch = chars[index]
        current += ch
        if ch == "." or ch == "?" or ch == "!":
            var at_end = index + 1 == len(chars)
            if at_end or chars[index + 1] == " ":
                sentences.append(current)
                current = String("")
    if String(current.strip()) != "":
        sentences.append(current)
    return sentences^


def _word_count(sentence: String) -> Int:
    """Return how many whitespace-separated words `sentence` holds."""
    var count = 0
    for token in sentence.split(" "):
        if String(token) != "":
            count += 1
    return count


def _is_list_item(stripped: String) -> Bool:
    """Return True if `stripped` starts a Markdown list item."""
    if stripped.startswith("- ") or stripped.startswith("* "):
        return True
    if stripped.startswith("- [") or stripped.startswith("* ["):
        return True
    var digits = 0
    for cp in stripped.codepoint_slices():
        var ch = String(cp)
        if ch >= "0" and ch <= "9":
            digits += 1
            continue
        return digits > 0 and ch == "."
    return False


def _british() -> List[String]:
    """Return British spellings that the documentation must not use.

    Stems, so that a plural or a past tense is caught too. Each is chosen so
    that no American word contains it, except a name the checker removes
    first, such as "greyhound".
    """
    return [
        "colour",
        "metre",
        "centre",
        "centred",
        "grey",
        "recognise",
        "recognising",
        "behaviour",
        "artefact",
        "travelled",
        "travelling",
        "neighbour",
        "honour",
        "favour",
        "analyse",
        "analysing",
        "maths",
        "judgement",
        "licence",
        "practise",
        "catalogue",
        "whilst",
        "amongst",
        "learnt",
        "orientated",
        "anticlockwise",
        "cancelled",
        "labelled",
        "modelling",
        "optimise",
        "optimising",
        "optimisation",
        "normalise",
        "normalising",
        "normalisation",
        "initialise",
        "initialising",
        "initialisation",
        "minimise",
        "minimising",
        "maximise",
        "maximising",
        "organise",
        "organising",
        "organisation",
        "summarise",
        "summarising",
        "prioritise",
        "prioritising",
        "emphasise",
        "emphasising",
        "characterise",
        "characterising",
        "characterisation",
        "utilise",
        "utilising",
        "utilisation",
        "specialise",
        "specialising",
        "specialisation",
        "standardise",
        "standardising",
        "visualise",
        "visualising",
        "visualisation",
        "serialise",
        "serialising",
        "serialisation",
        "synchronise",
        "synchronising",
        "synchronisation",
        "customise",
        "customising",
        "finalise",
        "finalising",
        "categorise",
        "categorising",
    ]


def _american() -> List[String]:
    """Return the American spelling for each entry of `_british`."""
    return [
        "color",
        "meter",
        "center",
        "centered",
        "gray",
        "recognize",
        "recognizing",
        "behavior",
        "artifact",
        "traveled",
        "traveling",
        "neighbor",
        "honor",
        "favor",
        "analyze",
        "analyzing",
        "math",
        "judgment",
        "license",
        "practice",
        "catalog",
        "while",
        "among",
        "learned",
        "oriented",
        "counterclockwise",
        "canceled",
        "labeled",
        "modeling",
        "optimize",
        "optimizing",
        "optimization",
        "normalize",
        "normalizing",
        "normalization",
        "initialize",
        "initializing",
        "initialization",
        "minimize",
        "minimizing",
        "maximize",
        "maximizing",
        "organize",
        "organizing",
        "organization",
        "summarize",
        "summarizing",
        "prioritize",
        "prioritizing",
        "emphasize",
        "emphasizing",
        "characterize",
        "characterizing",
        "characterization",
        "utilize",
        "utilizing",
        "utilization",
        "specialize",
        "specializing",
        "specialization",
        "standardize",
        "standardizing",
        "visualize",
        "visualizing",
        "visualization",
        "serialize",
        "serializing",
        "serialization",
        "synchronize",
        "synchronizing",
        "synchronization",
        "customize",
        "customizing",
        "finalize",
        "finalizing",
        "categorize",
        "categorizing",
    ]


def _check_paragraph(
    path: String, first_line: Int, text: String, is_item: Bool
) -> List[String]:
    """Return the problems found in one paragraph or list item."""
    var problems = List[String]()
    var place = path + ":" + String(first_line) + ": "
    var sentences = _sentences(text)
    if not is_item and len(sentences) > MAX_SENTENCES:
        problems.append(
            place
            + String(len(sentences))
            + " sentences in one paragraph (limit "
            + String(MAX_SENTENCES)
            + ")"
        )
    for sentence in sentences:
        var words = _word_count(sentence)
        if words > MAX_WORDS:
            problems.append(
                place
                + String(words)
                + " words in one sentence (limit "
                + String(MAX_WORDS)
                + "): "
                + String(sentence.strip())
            )
    var lowered = " " + text.lower() + " "
    for word in ["should", "may", "might"]:
        if lowered.find(" " + word + " ") >= 0:
            problems.append(
                place
                + "'"
                + word
                + "' is not Simplified Technical English; use 'must' or 'can'"
            )
    var british = _british()
    var american = _american()
    # An American word that holds a British stem, such as the breed name
    # "greyhound", is not a British spelling.
    var plain = lowered
    for word in ["greyhound"]:
        plain = plain.replace(word, " ")
    for index in range(len(british)):
        if plain.find(british[index]) >= 0:
            problems.append(
                place
                + "'"
                + british[index]
                + "' is British English; write '"
                + american[index]
                + "'"
            )
    return problems^


# --- Wiki links ----------------------------------------------------------------
#
# The link check reads Markdown as GitHub does, for the parts that decide
# whether text is a link: block quotes, list items, fenced and indented
# code, HTML blocks, ATX and setext headings, thematic breaks, tables and
# paragraphs. Inline code spans, escapes, raw HTML, autolinks, images and
# nested links are resolved over a whole paragraph or table cell.

comptime WIKI = "docs/wiki"
"""The folder that holds the wiki pages."""
comptime WIKI_URL = "https://github.com/SethKitchen/ThreeMojo/wiki/"
"""The prefix of an absolute link to a wiki page."""

comptime _TICK = UInt8(96)
comptime _TILDE = UInt8(126)
comptime _HASH = UInt8(35)
comptime _SPACE = UInt8(32)
comptime _NEWLINE = UInt8(10)
comptime _QUOTE = 1
comptime _ITEM = 2
comptime _HTML_RAW = 1
comptime _HTML_COMMENT = 2
comptime _HTML_BLOCK = 6
comptime _HTML_TAG = 7


@fieldwise_init
struct Link(Copyable, Movable):
    """An inline link's destination and the line where its text ends."""

    var target: String
    """The destination, without a title or angle brackets."""
    var line: Int
    """The 1-based line number."""


def _text_of(bytes: Span[UInt8, _], start: Int, end: Int) raises -> String:
    var out = List[UInt8]()
    for i in range(start, end):
        out.append(bytes[i])
    return String(from_utf8=Span(out))


def _spaces(bytes: Span[UInt8, _], at: Int) -> Int:
    var end = at
    while end < len(bytes) and bytes[end] == _SPACE:
        end += 1
    return end - at


def _blank(bytes: Span[UInt8, _], at: Int) -> Bool:
    return at + _spaces(bytes, at) >= len(bytes)


def _run(bytes: Span[UInt8, _], at: Int) -> Int:
    var end = at
    while end < len(bytes) and bytes[end] == bytes[at]:
        end += 1
    return end - at


def _is_punctuation(byte: UInt8) -> Bool:
    return (
        (byte >= 33 and byte <= 47)
        or (byte >= 58 and byte <= 64)
        or (byte >= 91 and byte <= 96)
        or (byte >= 123 and byte <= 126)
    )


def _is_alpha(byte: UInt8) -> Bool:
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)


def _has(bytes: Span[UInt8, _], at: Int, text: String) -> Bool:
    """Return True if `text` occurs in `bytes` at or after `at`."""
    var want = text.as_bytes()
    var start = at
    while start + len(want) <= len(bytes):
        var same = True
        for k in range(len(want)):
            if bytes[start + k] != want[k]:
                same = False
                break
        if same:
            return True
        start += 1
    return False


def _starts(bytes: Span[UInt8, _], at: Int, text: String) -> Bool:
    var want = text.as_bytes()
    if at + len(want) > len(bytes):
        return False
    for k in range(len(want)):
        if bytes[at + k] != want[k]:
            return False
    return True


def _fence_open(bytes: Span[UInt8, _], at: Int) -> Tuple[UInt8, Int]:
    """Return a fence's character and length, or a length of 0."""
    var indent = _spaces(bytes, at)
    var start = at + indent
    if indent > 3 or start >= len(bytes):
        return (UInt8(0), 0)
    var marker = bytes[start]
    if marker != _TICK and marker != _TILDE:
        return (UInt8(0), 0)
    var run = _run(bytes, start)
    if run < 3:
        return (UInt8(0), 0)
    if marker == _TICK:
        # A backtick fence's info string has no backtick.
        for i in range(start + run, len(bytes)):
            if bytes[i] == _TICK:
                return (UInt8(0), 0)
    return (marker, run)


def _fence_closes(
    bytes: Span[UInt8, _], at: Int, marker: UInt8, length: Int
) -> Bool:
    """Return True if the line closes a fence: the same character, at least
    as long as the opener, and nothing after it."""
    var indent = _spaces(bytes, at)
    var start = at + indent
    if indent > 3 or start >= len(bytes) or bytes[start] != marker:
        return False
    var run = _run(bytes, start)
    return run >= length and _blank(bytes, start + run)


struct Fence(Movable):
    """Track top-level fenced code the way CommonMark opens and closes it."""

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
            line: One line of Markdown with its indentation removed.

        Returns:
            True when the line is a fence or code, and False for prose.
        """
        var bytes = line.as_bytes()
        if self.length > 0:
            if _fence_closes(bytes, 0, self.marker, self.length):
                self.length = 0
            return True
        var fence = _fence_open(bytes, 0)
        if fence[1] == 0:
            return False
        self.marker = fence[0]
        self.length = fence[1]
        return True


def _quote(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return where a block quote's content starts, or -1."""
    var indent = _spaces(bytes, at)
    var start = at + indent
    if indent > 3 or start >= len(bytes) or bytes[start] != 62:
        return -1
    start += 1
    if start < len(bytes) and bytes[start] == _SPACE:
        start += 1
    return start


def _thematic(bytes: Span[UInt8, _], at: Int) -> Bool:
    var indent = _spaces(bytes, at)
    var start = at + indent
    if indent > 3 or start >= len(bytes):
        return False
    var mark = bytes[start]
    if mark != 45 and mark != 42 and mark != 95:
        return False
    var count = 0
    for i in range(start, len(bytes)):
        if bytes[i] == mark:
            count += 1
        elif bytes[i] != _SPACE:
            return False
    return count >= 3


def _setext(bytes: Span[UInt8, _], at: Int) -> Bool:
    var indent = _spaces(bytes, at)
    var start = at + indent
    if indent > 3 or start >= len(bytes):
        return False
    var mark = bytes[start]
    if mark != 61 and mark != 45:
        return False
    return _blank(bytes, start + _run(bytes, start))


def _list_marker(bytes: Span[UInt8, _], at: Int) -> Tuple[Int, Int, Bool]:
    """Return a list item's content width, its ordered number (-1 for a
    bullet), and whether it is empty. The width is 0 for no item."""
    var indent = _spaces(bytes, at)
    var start = at + indent
    if indent > 3 or start >= len(bytes):
        return (0, -1, False)
    var end = start
    var number = -1
    var mark = bytes[start]
    if mark == 45 or mark == 43 or mark == 42:
        end = start + 1
    else:
        number = 0
        while (
            end < len(bytes)
            and end - start < 9
            and bytes[end] >= 48
            and bytes[end] <= 57
        ):
            number = number * 10 + Int(bytes[end]) - 48
            end += 1
        if (
            end == start
            or end >= len(bytes)
            or (bytes[end] != 46 and bytes[end] != 41)
        ):
            return (0, -1, False)
        end += 1
    if end < len(bytes) and bytes[end] != _SPACE:
        return (0, -1, False)
    var after = _spaces(bytes, end)
    if end + after >= len(bytes):
        # An empty item's content starts one column after its marker.
        return (end - at + 1, number, True)
    if after > 4:
        after = 1
    return (end - at + after, number, False)


def _atx(bytes: Span[UInt8, _], at: Int) -> Tuple[Bool, Int, Int]:
    """Return whether the line is an ATX heading, and its text's bounds."""
    var indent = _spaces(bytes, at)
    var start = at + indent
    var level = 0
    while start + level < len(bytes) and bytes[start + level] == _HASH:
        level += 1
    var after = start + level
    if (
        indent > 3
        or level == 0
        or level > 6
        or (after < len(bytes) and bytes[after] != _SPACE)
    ):
        return (False, 0, 0)
    var end = len(bytes)
    while end > after and bytes[end - 1] == _SPACE:
        end -= 1
    # A closing run of `#` needs a space before it, or no text at all.
    var close = end
    while close > after and bytes[close - 1] == _HASH:
        close -= 1
    if close == after or bytes[close - 1] == _SPACE:
        end = close
    while end > after and bytes[end - 1] == _SPACE:
        end -= 1
    after += _spaces(bytes, after)
    return (True, after, max(after, end))


def _html_start(bytes: Span[UInt8, _], at: Int) raises -> Int:
    """Return the kind of HTML block that the line starts, or 0."""
    var indent = _spaces(bytes, at)
    var start = at + indent
    if indent > 3 or start >= len(bytes) or bytes[start] != 60:
        return 0
    if _starts(bytes, start, "<!--"):
        return _HTML_COMMENT
    var lower = String(_text_of(bytes, start, len(bytes)).lower())
    var low = lower.as_bytes()
    for raw in ["<pre", "<script", "<style", "<textarea"]:
        if _starts(low, 0, raw):
            var after = len(raw.as_bytes())
            if after >= len(low) or low[after] == _SPACE or low[after] == 62:
                return _HTML_RAW
    var name = start + 1
    if name < len(bytes) and bytes[name] == 47:
        name += 1
    var end = name
    while end < len(bytes) and (
        _is_alpha(bytes[end]) or (bytes[end] >= 48 and bytes[end] <= 57)
    ):
        end += 1
    if end == name:
        return 0
    var tag = String(_text_of(bytes, name, end).lower())
    var stop = end >= len(bytes) or bytes[end] == _SPACE or bytes[end] == 62
    stop = stop or _starts(bytes, end, "/>")
    for block in [
        "address",
        "article",
        "aside",
        "blockquote",
        "body",
        "center",
        "details",
        "dialog",
        "dd",
        "div",
        "dl",
        "dt",
        "fieldset",
        "figcaption",
        "figure",
        "footer",
        "form",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "head",
        "header",
        "hr",
        "html",
        "li",
        "main",
        "nav",
        "ol",
        "p",
        "section",
        "summary",
        "table",
        "tbody",
        "td",
        "tfoot",
        "th",
        "thead",
        "tr",
        "ul",
    ]:
        if tag == block and stop:
            return _HTML_BLOCK
    # Any other complete tag alone on its line.
    var last = len(bytes)
    while last > start and bytes[last - 1] == _SPACE:
        last -= 1
    if bytes[last - 1] != 62:
        return 0
    for i in range(start + 1, last - 1):
        if bytes[i] == 60 or bytes[i] == 62:
            return 0
    return _HTML_TAG


def _raw_closes(bytes: Span[UInt8, _], at: Int) raises -> Bool:
    """Return True if the line holds a raw-text block's closing tag."""
    var lower = String(_text_of(bytes, at, len(bytes)).lower())
    var low = lower.as_bytes()
    for close in ["</pre>", "</script>", "</style>", "</textarea>"]:
        if _has(low, 0, close):
            return True
    return False


def _utf8(code: Int, mut out: List[UInt8]):
    """Append a code point as UTF-8; an invalid one becomes U+FFFD."""
    var c = code
    if c <= 0 or c > 0x10FFFF or (c >= 0xD800 and c <= 0xDFFF):
        c = 0xFFFD
    if c < 0x80:
        out.append(UInt8(c))
    elif c < 0x800:
        out.append(UInt8(0xC0 | (c >> 6)))
        out.append(UInt8(0x80 | (c & 0x3F)))
    elif c < 0x10000:
        out.append(UInt8(0xE0 | (c >> 12)))
        out.append(UInt8(0x80 | ((c >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (c & 0x3F)))
    else:
        out.append(UInt8(0xF0 | (c >> 18)))
        out.append(UInt8(0x80 | ((c >> 12) & 0x3F)))
        out.append(UInt8(0x80 | ((c >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (c & 0x3F)))


def _named_entity(name: String) -> Int:
    """Return the code point of a named character reference, or -1.

    This is the common subset of HTML's table. An unknown name stays
    literal text, as CommonMark leaves it.
    """
    var names: List[String] = [
        "amp",
        "lt",
        "gt",
        "quot",
        "apos",
        "nbsp",
        "copy",
        "reg",
        "trade",
        "mdash",
        "ndash",
        "hellip",
        "lsquo",
        "rsquo",
        "ldquo",
        "rdquo",
        "times",
        "divide",
        "middot",
        "deg",
        "plusmn",
        "micro",
        "larr",
        "rarr",
        "uarr",
        "darr",
        "harr",
        "le",
        "ge",
        "ne",
        "asymp",
        "minus",
        "laquo",
        "raquo",
        "sect",
        "para",
        "bull",
        "euro",
        "pound",
        "yen",
        "cent",
        "frac12",
        "frac14",
        "frac34",
        "sup2",
        "sup3",
        "alpha",
        "beta",
        "gamma",
        "delta",
        "pi",
        "sigma",
        "theta",
        "lambda",
        "mu",
        "omega",
        "infin",
        "radic",
        "sum",
        "prod",
        "check",
        "cross",
    ]
    var codes: List[Int] = [
        38,
        60,
        62,
        34,
        39,
        160,
        169,
        174,
        8482,
        8212,
        8211,
        8230,
        8216,
        8217,
        8220,
        8221,
        215,
        247,
        183,
        176,
        177,
        181,
        8592,
        8594,
        8593,
        8595,
        8596,
        8804,
        8805,
        8800,
        8776,
        8722,
        171,
        187,
        167,
        182,
        8226,
        8364,
        163,
        165,
        162,
        189,
        188,
        190,
        178,
        179,
        945,
        946,
        947,
        948,
        960,
        963,
        952,
        955,
        956,
        969,
        8734,
        8730,
        8721,
        8719,
        10003,
        10007,
    ]
    for k in range(len(names)):
        if names[k] == name:
            return codes[k]
    return -1


def _entity(
    bytes: Span[UInt8, _], at: Int, end: Int, mut out: List[UInt8]
) raises -> Int:
    """Decode a character reference at `at` into `out`.

    Returns how many bytes it used, or 0 if there is no valid reference.
    """
    if at + 2 >= end or bytes[at] != 38:
        return 0
    var i = at + 1
    if bytes[i] == 35:
        i += 1
        var hex = i < end and (bytes[i] == 120 or bytes[i] == 88)
        if hex:
            i += 1
        var start = i
        var code = 0
        while i < end and i - start < (6 if hex else 7):
            var digit = _hex(bytes[i])
            if not hex and (bytes[i] < 48 or bytes[i] > 57):
                digit = -1
            if digit < 0:
                break
            code = code * (16 if hex else 10) + digit
            i += 1
        if i == start or i >= end or bytes[i] != 59:
            return 0
        _utf8(code, out)
        return i + 1 - at
    var start = i
    while (
        i < end
        and i - start < 32
        and (_is_alpha(bytes[i]) or (bytes[i] >= 48 and bytes[i] <= 57))
    ):
        i += 1
    if i == start or i >= end or bytes[i] != 59:
        return 0
    var code = _named_entity(_text_of(bytes, start, i))
    if code < 0:
        return 0
    _utf8(code, out)
    return i + 1 - at


def _unescape(text: String) raises -> String:
    """Return a link destination with its escapes and references decoded."""
    var bytes = text.as_bytes()
    var out = List[UInt8]()
    var i = 0
    while i < len(bytes):
        if (
            bytes[i] == 92
            and i + 1 < len(bytes)
            and _is_punctuation(bytes[i + 1])
        ):
            out.append(bytes[i + 1])
            i += 2
            continue
        var used = _entity(bytes, i, len(bytes), out)
        if used > 0:
            i += used
            continue
        out.append(bytes[i])
        i += 1
    return String(from_utf8=Span(out))


def _cells(bytes: Span[UInt8, _], at: Int) -> List[Tuple[Int, Int]]:
    """Return the bounds of each cell in a table row."""
    var cells = List[Tuple[Int, Int]]()
    var start = at + _spaces(bytes, at)
    var end = len(bytes)
    while end > start and bytes[end - 1] == _SPACE:
        end -= 1
    if start < end and bytes[start] == 124:
        start += 1
    if end > start and bytes[end - 1] == 124 and bytes[end - 2] != 92:
        end -= 1
    var cell = start
    var i = start
    while i < end:
        if bytes[i] == 92:
            i += 2
            continue
        if bytes[i] == 124:
            cells.append((cell, i))
            cell = i + 1
        i += 1
    cells.append((cell, end))
    return cells^


def _delimiter_row(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the cell count of a table delimiter row, or 0."""
    if not _has(bytes, at, "|") and not _has(bytes, at, "-"):
        return 0
    var cells = _cells(bytes, at)
    for cell in cells:
        var start = cell[0] + _spaces(bytes, cell[0])
        var end = cell[1]
        while end > start and bytes[end - 1] == _SPACE:
            end -= 1
        if start < end and bytes[start] == 58:
            start += 1
        if end > start and bytes[end - 1] == 58:
            end -= 1
        if start == end:
            return 0
        for i in range(start, end):
            if bytes[i] != 45:
                return 0
    var piped = _has(bytes, at, "|")
    return len(cells) if piped or len(cells) > 1 else 0


def _destination(bytes: Span[UInt8, _], at: Int) -> Tuple[Int, Int, Int]:
    """Read an inline link's `(destination "title")` at `at`.

    Returns the destination's bounds and the index after `)`, or -1.
    """
    var none = (0, 0, -1)
    if at >= len(bytes) or bytes[at] != 40:
        return none
    var i = at + 1
    while i < len(bytes) and (bytes[i] == _SPACE or bytes[i] == _NEWLINE):
        i += 1
    var start = i
    var end = i
    if i < len(bytes) and bytes[i] == 60:
        start = i + 1
        end = start
        while end < len(bytes) and bytes[end] != 62:
            if bytes[end] == _NEWLINE or bytes[end] == 60:
                return none
            end += 1
        if end >= len(bytes):
            return none
        i = end + 1
    else:
        var depth = 0
        while end < len(bytes):
            var byte = bytes[end]
            if byte <= 32:
                break
            if byte == 92 and end + 1 < len(bytes):
                end += 2
                continue
            if byte == 40:
                depth += 1
            elif byte == 41:
                if depth == 0:
                    break
                depth -= 1
            end += 1
        i = end
    var gap = i
    while i < len(bytes) and (bytes[i] == _SPACE or bytes[i] == _NEWLINE):
        i += 1
    if (
        i < len(bytes)
        and i > gap
        and (bytes[i] == 34 or bytes[i] == 39 or bytes[i] == 40)
    ):
        var close = UInt8(41) if bytes[i] == 40 else bytes[i]
        i += 1
        while i < len(bytes) and bytes[i] != close:
            i += 2 if bytes[i] == 92 else 1
        if i >= len(bytes):
            return none
        i += 1
        while i < len(bytes) and (bytes[i] == _SPACE or bytes[i] == _NEWLINE):
            i += 1
    if i >= len(bytes) or bytes[i] != 41:
        return none
    return (start, end, i + 1)


def _code_end(bytes: Span[UInt8, _], at: Int, end: Int) -> Int:
    """Return the index after the code span that opens at `at`, or -1."""
    var run = _run(bytes, at)
    var j = at + run
    while j < end:
        if bytes[j] != _TICK:
            j += 1
            continue
        var other = 0
        while j + other < end and bytes[j + other] == _TICK:
            other += 1
        if other == run:
            return j + run
        j += other
    return -1


def _html_end(bytes: Span[UInt8, _], at: Int, end: Int) -> Int:
    """Return the index after inline raw HTML or an autolink, or -1."""
    if _starts(bytes, at, "<!--"):
        # A comment cannot start with `>` or `->`.
        if _starts(bytes, at + 4, ">") or _starts(bytes, at + 4, "->"):
            return -1
        var i = at + 4
        while i + 3 <= end:
            if _starts(bytes, i, "-->"):
                return i + 3
            i += 1
        return -1
    var i = at + 1
    if i < end and bytes[i] == 47:
        i += 1
    if i >= end or not _is_alpha(bytes[i]):
        return -1
    while i < end and bytes[i] != 62:
        if bytes[i] == 60:
            return -1
        i += 1
    return i + 1 if i < end else -1


def _links(
    text: String, lines: List[Int], offsets: List[Int], mut out: List[Link]
) raises:
    """Append each inline link in a paragraph or table cell.

    Args:
        text: The paragraph's lines joined by newlines.
        lines: The source line number of each joined line.
        offsets: Where each joined line starts in `text`.
        out: Receives each link, in order.

    Raises:
        Error: If the text is not valid UTF-8.
    """
    var bytes = text.as_bytes()
    var end = len(bytes)
    # Open brackets: position, image, active.
    var openers = List[Tuple[Int, Bool, Bool]]()
    var i = 0
    while i < end:
        var byte = bytes[i]
        if byte == 92 and i + 1 < end and _is_punctuation(bytes[i + 1]):
            i += 2
            continue
        if byte == _TICK:
            var after = _code_end(bytes, i, end)
            i = after if after >= 0 else i + _run(bytes, i)
            continue
        if byte == 60:
            var after = _html_end(bytes, i, end)
            i = after if after >= 0 else i + 1
            continue
        if byte == 33 and i + 1 < end and bytes[i + 1] == 91:
            openers.append((i + 1, True, True))
            i += 2
            continue
        if byte == 91:
            openers.append((i, False, True))
            i += 1
            continue
        if byte != 93 or len(openers) == 0:
            i += 1
            continue
        var opener = openers.pop()
        if not opener[2]:
            i += 1
            continue
        var found = _destination(bytes, i + 1)
        if found[2] < 0:
            i += 1
            continue
        if not opener[1]:
            var line = 0
            while line + 1 < len(offsets) and offsets[line + 1] <= i:
                line += 1
            var target = _unescape(_text_of(bytes, found[0], found[1]))
            out.append(Link(target^, lines[line]))
            # A link cannot contain another link.
            for k in range(len(openers)):
                if not openers[k][1]:
                    openers[k] = (openers[k][0], False, False)
        i = found[2]


def _rendered(heading: String) raises -> String:
    """Return a heading's text as GitHub renders it, for its anchor.

    Escapes become their character, code spans keep their text, a link
    keeps its text, and matched `_` emphasis is removed.
    """
    var bytes = heading.as_bytes()
    var chars = List[UInt8]()
    # Whether each kept byte is a literal that emphasis cannot use.
    var literal = List[Bool]()
    var i = 0
    while i < len(bytes):
        var byte = bytes[i]
        if byte == 92 and i + 1 < len(bytes) and _is_punctuation(bytes[i + 1]):
            chars.append(bytes[i + 1])
            literal.append(True)
            i += 2
            continue
        if byte == 38:
            var used = _entity(bytes, i, len(bytes), chars)
            if used > 0:
                while len(literal) < len(chars):
                    literal.append(True)
                i += used
                continue
        if byte == 60:
            var after = _html_end(bytes, i, len(bytes))
            if after >= 0:
                i = after
                continue
        if byte == _TICK:
            var after = _code_end(bytes, i, len(bytes))
            if after >= 0:
                var run = _run(bytes, i)
                for k in range(i + run, after - run):
                    chars.append(bytes[k])
                    literal.append(True)
                i = after
                continue
            for _ in range(_run(bytes, i)):
                chars.append(_TICK)
                literal.append(True)
            i += _run(bytes, i)
            continue
        if byte == 93:
            var found = _destination(bytes, i + 1)
            if found[2] >= 0:
                i = found[2]
                continue
        chars.append(byte)
        literal.append(False)
        i += 1
    # Pair `_` delimiter runs by CommonMark's flanking rules.
    var keep = List[Bool](length=len(chars), fill=True)
    var openers = List[Tuple[Int, Int]]()
    var k = 0
    while k < len(chars):
        if chars[k] != 95 or literal[k]:
            k += 1
            continue
        var run = 0
        while (
            k + run < len(chars)
            and chars[k + run] == 95
            and not literal[k + run]
        ):
            run += 1
        var before = chars[k - 1] if k > 0 else _SPACE
        var after = chars[k + run] if k + run < len(chars) else _SPACE
        var space_before = before == _SPACE or before == _NEWLINE
        var space_after = after == _SPACE or after == _NEWLINE
        var left = not space_after and (
            not _is_punctuation(after)
            or space_before
            or _is_punctuation(before)
        )
        var right = not space_before and (
            not _is_punctuation(before) or space_after or _is_punctuation(after)
        )
        var opens = left and (not right or _is_punctuation(before))
        var closes = right and (not left or _is_punctuation(after))
        if closes and len(openers) > 0:
            var opener = openers.pop()
            var used = min(opener[1], run)
            for m in range(used):
                keep[opener[0] + opener[1] - 1 - m] = False
                keep[k + m] = False
        elif opens:
            openers.append((k, run))
        k += run
    var out = List[UInt8]()
    for m in range(len(chars)):
        if keep[m]:
            out.append(chars[m])
    return String(from_utf8=Span(out))


def _drops(ch: String) -> Bool:
    """Return True if an anchor drops the character `ch`."""
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
    """Return GitHub's anchor for a heading's Markdown text.

    Args:
        heading: The heading text without its `#` markers.

    Returns:
        The anchor before any repeat suffix.

    Raises:
        Error: If the heading is not valid UTF-8.
    """
    var out = String("")
    var text = _rendered(heading)
    for cp in String(String(text.strip()).lower()).codepoint_slices():
        var ch = String(cp)
        if ch == " ":
            out += "-"
        elif not _drops(ch):
            out += ch
    return out^


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
        return String(from_utf8=Span(out))
    except:
        return text


def _hex(byte: UInt8) -> Int:
    if byte >= 48 and byte <= 57:
        return Int(byte) - 48
    if byte >= 65 and byte <= 70:
        return Int(byte) - 55
    if byte >= 97 and byte <= 102:
        return Int(byte) - 87
    return -1


struct Document(Movable):
    """The anchors and inline links of one Markdown file."""

    var anchors: Dict[String, Int]
    """Each heading anchor, as github-slugger assigns it."""
    var links: List[Link]
    """Each inline link outside code, in order."""
    var _kinds: List[Int]
    var _indents: List[Int]
    var _fence: Tuple[UInt8, Int, Int]
    var _html: Tuple[Int, Int]
    var _paragraph: List[String]
    var _lines: List[Int]
    var _table: Bool

    def __init__(out self, text: String) raises:
        """Read the blocks, headings and links of a Markdown file.

        Args:
            text: The file's Markdown.

        Raises:
            Error: If the text is not valid UTF-8.
        """
        self.anchors = Dict[String, Int]()
        self.links = List[Link]()
        self._kinds = List[Int]()
        self._indents = List[Int]()
        self._fence = (UInt8(0), 0, 0)
        self._html = (0, 0)
        self._paragraph = List[String]()
        self._lines = List[Int]()
        self._table = False
        var number = 0
        for raw in text.split("\n"):
            number += 1
            self._line(String(String(raw).replace("\t", "    ")), number)
        self._flush()

    def _anchor(mut self, heading: String) raises:
        # github-slugger: the slug, or the first free `-N` suffix.
        var base = slug(heading)
        var result = base
        while result in self.anchors:
            self.anchors[base] = self.anchors[base] + 1
            result = base + "-" + String(self.anchors[base])
        self.anchors[result] = 0

    def _inline(mut self, text: String, line: Int) raises:
        _links(text, [line], [0], self.links)

    def _flush(mut self) raises:
        if len(self._paragraph) > 0:
            var joined = String("")
            var offsets = List[Int]()
            for k in range(len(self._paragraph)):
                if k > 0:
                    joined += "\n"
                offsets.append(len(joined.as_bytes()))
                joined += self._paragraph[k]
            _links(joined, self._lines, offsets, self.links)
            self._paragraph = List[String]()
            self._lines = List[Int]()
        self._table = False

    def _row(mut self, line: String, number: Int) raises:
        # Each table cell is inline content of its own.
        var bytes = line.as_bytes()
        for cell in _cells(bytes, 0):
            self._inline(_text_of(bytes, cell[0], cell[1]), number)

    def _close(mut self, depth: Int):
        while len(self._kinds) > depth:
            _ = self._kinds.pop()
            _ = self._indents.pop()

    def _line(mut self, text: String, number: Int) raises:
        var bytes = text.as_bytes()
        if len(bytes) > 0 and bytes[len(bytes) - 1] == 13:
            self._line(_text_of(bytes, 0, len(bytes) - 1), number)
            return
        var at = 0
        var matched = 0
        while matched < len(self._kinds):
            if self._kinds[matched] == _QUOTE:
                var after = _quote(bytes, at)
                if after < 0:
                    break
                at = after
            elif not _blank(bytes, at):
                if _spaces(bytes, at) < self._indents[matched]:
                    break
                at += self._indents[matched]
            matched += 1
        # Fenced code and HTML blocks end with their container.
        if self._fence[1] > 0:
            if matched >= self._fence[2]:
                if _fence_closes(bytes, at, self._fence[0], self._fence[1]):
                    self._fence = (UInt8(0), 0, 0)
                return
            self._fence = (UInt8(0), 0, 0)
        if self._html[0] != 0:
            if matched >= self._html[1]:
                if self._html[0] == _HTML_RAW:
                    if _raw_closes(bytes, at):
                        self._html = (0, 0)
                elif self._html[0] == _HTML_COMMENT:
                    if _has(bytes, at, "-->"):
                        self._html = (0, 0)
                elif _blank(bytes, at):
                    self._html = (0, 0)
                return
            self._html = (0, 0)
        var all = matched == len(self._kinds)
        if not all:
            # A lazy line continues an open paragraph.
            var starts = (
                _blank(bytes, at)
                or _quote(bytes, at) >= 0
                or _list_marker(bytes, at)[0] > 0
                or _fence_open(bytes, at)[1] > 0
                or _atx(bytes, at)[0]
                or _thematic(bytes, at)
                or _html_start(bytes, at) != 0
            )
            if len(self._paragraph) > 0 and not self._table and not starts:
                self._paragraph.append(
                    _text_of(bytes, at + _spaces(bytes, at), len(bytes))
                )
                self._lines.append(number)
                return
            self._flush()
            self._close(matched)
        # New containers.
        while True:
            if _thematic(bytes, at):
                break
            var after = _quote(bytes, at)
            if after >= 0:
                self._flush()
                self._kinds.append(_QUOTE)
                self._indents.append(0)
                at = after
                continue
            var item = _list_marker(bytes, at)
            # Only a nonempty item, and an ordered one from 1, interrupts
            # a paragraph.
            var interrupts = (
                len(self._paragraph) == 0
                or not all
                or (not item[2] and item[1] <= 1)
            )
            if item[0] > 0 and interrupts:
                self._flush()
                self._kinds.append(_ITEM)
                self._indents.append(item[0])
                at = min(at + item[0], len(bytes))
                all = True
                continue
            break
        if _blank(bytes, at):
            self._flush()
            return
        var fence = _fence_open(bytes, at)
        if fence[1] > 0:
            self._flush()
            self._fence = (fence[0], fence[1], len(self._kinds))
            return
        var atx = _atx(bytes, at)
        if atx[0]:
            self._flush()
            var heading = _text_of(bytes, atx[1], atx[2])
            self._anchor(heading)
            self._inline(heading, number)
            return
        if len(self._paragraph) > 0 and not self._table and _setext(bytes, at):
            var heading = String(" ").join(self._paragraph)
            self._anchor(heading)
            self._flush()
            return
        if _thematic(bytes, at):
            self._flush()
            return
        var html = _html_start(bytes, at)
        if html != 0 and (html != _HTML_TAG or len(self._paragraph) == 0):
            self._flush()
            var closed = (
                html == _HTML_COMMENT and _has(bytes, at + 4, "-->")
            ) or (html == _HTML_RAW and _raw_closes(bytes, at))
            if not closed:
                self._html = (html, len(self._kinds))
            return
        if len(self._paragraph) == 0 and _spaces(bytes, at) >= 4:
            # Indented code.
            return
        if self._table:
            self._row(_text_of(bytes, at, len(bytes)), number)
            return
        if len(self._paragraph) == 1:
            var columns = _delimiter_row(bytes, at)
            var header = self._paragraph[0]
            if columns > 0 and columns == len(_cells(header.as_bytes(), 0)):
                var line = self._lines[0]
                self._paragraph = List[String]()
                self._lines = List[Int]()
                self._row(header, line)
                self._table = True
                return
        self._paragraph.append(
            _text_of(bytes, at + _spaces(bytes, at), len(bytes))
        )
        self._lines.append(number)


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
    return Document(text).anchors.copy()


def _is_page(name: String) -> Bool:
    var bytes = name.as_bytes()
    if len(bytes) == 0:
        return False
    for i in range(len(bytes)):
        var byte = bytes[i]
        var alnum = _is_alpha(byte) or (byte >= 48 and byte <= 57)
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

    A wiki page's `[text](Page#anchor)` and `[text](#anchor)` links are
    checked, and so is any file's link to the GitHub wiki URL. Targets and
    anchors are percent-decoded. Links with a scheme, a path or a file
    extension are not wiki links.

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
        var document = Document(Path(path).read_text())
        var in_wiki = _folder(path) == folder
        for link in document.links:
            var target = link.target
            if target.startswith(WIKI_URL):
                var rest = String(link.target.removeprefix(WIKI_URL))
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
            var at = path + ":" + String(link.line) + ": "
            if page == "":
                if anchor != "" and anchor not in document.anchors:
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
                problems.append(at + "no heading for " + page + "#" + anchor)
    return problems^


def check_file(path: String) raises -> List[String]:
    """Return every problem in the Markdown file at `path`.

    Args:
        path: The file to check.

    Returns:
        One line per problem, empty if the file passes.

    Raises:
        Error: If the file cannot be read.
    """
    var problems = List[String]()
    var text = Path(path).read_text()
    var fence = Fence()
    var in_comment = False
    var paragraph = String("")
    var paragraph_line = 0
    var paragraph_is_item = False
    var number = 0
    for raw in text.split("\n"):
        number += 1
        var stripped = String(String(raw).strip())
        if in_comment:
            if stripped.find("-->") >= 0:
                in_comment = False
            continue
        if stripped.startswith("<!--"):
            if stripped.find("-->") < 0:
                in_comment = True
            continue
        if fence.is_code(stripped):
            continue
        var skip = (
            stripped == ""
            or stripped.startswith("#")
            or stripped.startswith("|")
            or stripped.startswith("[!")
            or stripped.startswith("---")
            or stripped.startswith("<")
        )
        var is_item = _is_list_item(stripped)
        if skip or is_item:
            if paragraph != "":
                problems.extend(
                    _check_paragraph(
                        path, paragraph_line, paragraph, paragraph_is_item
                    )
                )
                paragraph = String("")
            if skip:
                continue
        if paragraph == "":
            paragraph_line = number
            paragraph_is_item = is_item
            paragraph = _clean(stripped)
        else:
            paragraph += " " + _clean(stripped)
    if paragraph != "":
        problems.extend(
            _check_paragraph(path, paragraph_line, paragraph, paragraph_is_item)
        )
    return problems^


def main() raises:
    var args = argv()
    if len(args) < 2:
        raise Error("usage: doc_lint <file.md>...")
    var problems = 0
    var paths = List[String]()
    for index in range(1, len(args)):
        paths.append(String(args[index]))
        var found = check_file(paths[index - 1])
        for problem in found:
            print(problem)
        problems += len(found)
    var links = check_links(paths)
    for problem in links:
        print(problem)
    problems += len(links)
    if problems > 0:
        raise Error(String(problems) + " documentation problems found")
    print("Documentation follows the rules:", len(args) - 1, "files.")
