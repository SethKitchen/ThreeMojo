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


# The WHATWG named character references that end in a semicolon, the ones
# CommonMark recognizes: one `name` per line, then its code points in hex.
# Generated from Python's `html.entities.html5`:
#   python3 -c "from html.entities import html5; print('\n'.join(
#     k[:-1] + ' ' + ' '.join('%X' % ord(c) for c in v)
#     for k, v in sorted(html5.items()) if k.endswith(';')))"
comptime _ENTITIES = """
AElig C6
AMP 26
Aacute C1
Abreve 102
Acirc C2
Acy 410
Afr 1D504
Agrave C0
Alpha 391
Amacr 100
And 2A53
Aogon 104
Aopf 1D538
ApplyFunction 2061
Aring C5
Ascr 1D49C
Assign 2254
Atilde C3
Auml C4
Backslash 2216
Barv 2AE7
Barwed 2306
Bcy 411
Because 2235
Bernoullis 212C
Beta 392
Bfr 1D505
Bopf 1D539
Breve 2D8
Bscr 212C
Bumpeq 224E
CHcy 427
COPY A9
Cacute 106
Cap 22D2
CapitalDifferentialD 2145
Cayleys 212D
Ccaron 10C
Ccedil C7
Ccirc 108
Cconint 2230
Cdot 10A
Cedilla B8
CenterDot B7
Cfr 212D
Chi 3A7
CircleDot 2299
CircleMinus 2296
CirclePlus 2295
CircleTimes 2297
ClockwiseContourIntegral 2232
CloseCurlyDoubleQuote 201D
CloseCurlyQuote 2019
Colon 2237
Colone 2A74
Congruent 2261
Conint 222F
ContourIntegral 222E
Copf 2102
Coproduct 2210
CounterClockwiseContourIntegral 2233
Cross 2A2F
Cscr 1D49E
Cup 22D3
CupCap 224D
DD 2145
DDotrahd 2911
DJcy 402
DScy 405
DZcy 40F
Dagger 2021
Darr 21A1
Dashv 2AE4
Dcaron 10E
Dcy 414
Del 2207
Delta 394
Dfr 1D507
DiacriticalAcute B4
DiacriticalDot 2D9
DiacriticalDoubleAcute 2DD
DiacriticalGrave 60
DiacriticalTilde 2DC
Diamond 22C4
DifferentialD 2146
Dopf 1D53B
Dot A8
DotDot 20DC
DotEqual 2250
DoubleContourIntegral 222F
DoubleDot A8
DoubleDownArrow 21D3
DoubleLeftArrow 21D0
DoubleLeftRightArrow 21D4
DoubleLeftTee 2AE4
DoubleLongLeftArrow 27F8
DoubleLongLeftRightArrow 27FA
DoubleLongRightArrow 27F9
DoubleRightArrow 21D2
DoubleRightTee 22A8
DoubleUpArrow 21D1
DoubleUpDownArrow 21D5
DoubleVerticalBar 2225
DownArrow 2193
DownArrowBar 2913
DownArrowUpArrow 21F5
DownBreve 311
DownLeftRightVector 2950
DownLeftTeeVector 295E
DownLeftVector 21BD
DownLeftVectorBar 2956
DownRightTeeVector 295F
DownRightVector 21C1
DownRightVectorBar 2957
DownTee 22A4
DownTeeArrow 21A7
Downarrow 21D3
Dscr 1D49F
Dstrok 110
ENG 14A
ETH D0
Eacute C9
Ecaron 11A
Ecirc CA
Ecy 42D
Edot 116
Efr 1D508
Egrave C8
Element 2208
Emacr 112
EmptySmallSquare 25FB
EmptyVerySmallSquare 25AB
Eogon 118
Eopf 1D53C
Epsilon 395
Equal 2A75
EqualTilde 2242
Equilibrium 21CC
Escr 2130
Esim 2A73
Eta 397
Euml CB
Exists 2203
ExponentialE 2147
Fcy 424
Ffr 1D509
FilledSmallSquare 25FC
FilledVerySmallSquare 25AA
Fopf 1D53D
ForAll 2200
Fouriertrf 2131
Fscr 2131
GJcy 403
GT 3E
Gamma 393
Gammad 3DC
Gbreve 11E
Gcedil 122
Gcirc 11C
Gcy 413
Gdot 120
Gfr 1D50A
Gg 22D9
Gopf 1D53E
GreaterEqual 2265
GreaterEqualLess 22DB
GreaterFullEqual 2267
GreaterGreater 2AA2
GreaterLess 2277
GreaterSlantEqual 2A7E
GreaterTilde 2273
Gscr 1D4A2
Gt 226B
HARDcy 42A
Hacek 2C7
Hat 5E
Hcirc 124
Hfr 210C
HilbertSpace 210B
Hopf 210D
HorizontalLine 2500
Hscr 210B
Hstrok 126
HumpDownHump 224E
HumpEqual 224F
IEcy 415
IJlig 132
IOcy 401
Iacute CD
Icirc CE
Icy 418
Idot 130
Ifr 2111
Igrave CC
Im 2111
Imacr 12A
ImaginaryI 2148
Implies 21D2
Int 222C
Integral 222B
Intersection 22C2
InvisibleComma 2063
InvisibleTimes 2062
Iogon 12E
Iopf 1D540
Iota 399
Iscr 2110
Itilde 128
Iukcy 406
Iuml CF
Jcirc 134
Jcy 419
Jfr 1D50D
Jopf 1D541
Jscr 1D4A5
Jsercy 408
Jukcy 404
KHcy 425
KJcy 40C
Kappa 39A
Kcedil 136
Kcy 41A
Kfr 1D50E
Kopf 1D542
Kscr 1D4A6
LJcy 409
LT 3C
Lacute 139
Lambda 39B
Lang 27EA
Laplacetrf 2112
Larr 219E
Lcaron 13D
Lcedil 13B
Lcy 41B
LeftAngleBracket 27E8
LeftArrow 2190
LeftArrowBar 21E4
LeftArrowRightArrow 21C6
LeftCeiling 2308
LeftDoubleBracket 27E6
LeftDownTeeVector 2961
LeftDownVector 21C3
LeftDownVectorBar 2959
LeftFloor 230A
LeftRightArrow 2194
LeftRightVector 294E
LeftTee 22A3
LeftTeeArrow 21A4
LeftTeeVector 295A
LeftTriangle 22B2
LeftTriangleBar 29CF
LeftTriangleEqual 22B4
LeftUpDownVector 2951
LeftUpTeeVector 2960
LeftUpVector 21BF
LeftUpVectorBar 2958
LeftVector 21BC
LeftVectorBar 2952
Leftarrow 21D0
Leftrightarrow 21D4
LessEqualGreater 22DA
LessFullEqual 2266
LessGreater 2276
LessLess 2AA1
LessSlantEqual 2A7D
LessTilde 2272
Lfr 1D50F
Ll 22D8
Lleftarrow 21DA
Lmidot 13F
LongLeftArrow 27F5
LongLeftRightArrow 27F7
LongRightArrow 27F6
Longleftarrow 27F8
Longleftrightarrow 27FA
Longrightarrow 27F9
Lopf 1D543
LowerLeftArrow 2199
LowerRightArrow 2198
Lscr 2112
Lsh 21B0
Lstrok 141
Lt 226A
Map 2905
Mcy 41C
MediumSpace 205F
Mellintrf 2133
Mfr 1D510
MinusPlus 2213
Mopf 1D544
Mscr 2133
Mu 39C
NJcy 40A
Nacute 143
Ncaron 147
Ncedil 145
Ncy 41D
NegativeMediumSpace 200B
NegativeThickSpace 200B
NegativeThinSpace 200B
NegativeVeryThinSpace 200B
NestedGreaterGreater 226B
NestedLessLess 226A
NewLine A
Nfr 1D511
NoBreak 2060
NonBreakingSpace A0
Nopf 2115
Not 2AEC
NotCongruent 2262
NotCupCap 226D
NotDoubleVerticalBar 2226
NotElement 2209
NotEqual 2260
NotEqualTilde 2242 338
NotExists 2204
NotGreater 226F
NotGreaterEqual 2271
NotGreaterFullEqual 2267 338
NotGreaterGreater 226B 338
NotGreaterLess 2279
NotGreaterSlantEqual 2A7E 338
NotGreaterTilde 2275
NotHumpDownHump 224E 338
NotHumpEqual 224F 338
NotLeftTriangle 22EA
NotLeftTriangleBar 29CF 338
NotLeftTriangleEqual 22EC
NotLess 226E
NotLessEqual 2270
NotLessGreater 2278
NotLessLess 226A 338
NotLessSlantEqual 2A7D 338
NotLessTilde 2274
NotNestedGreaterGreater 2AA2 338
NotNestedLessLess 2AA1 338
NotPrecedes 2280
NotPrecedesEqual 2AAF 338
NotPrecedesSlantEqual 22E0
NotReverseElement 220C
NotRightTriangle 22EB
NotRightTriangleBar 29D0 338
NotRightTriangleEqual 22ED
NotSquareSubset 228F 338
NotSquareSubsetEqual 22E2
NotSquareSuperset 2290 338
NotSquareSupersetEqual 22E3
NotSubset 2282 20D2
NotSubsetEqual 2288
NotSucceeds 2281
NotSucceedsEqual 2AB0 338
NotSucceedsSlantEqual 22E1
NotSucceedsTilde 227F 338
NotSuperset 2283 20D2
NotSupersetEqual 2289
NotTilde 2241
NotTildeEqual 2244
NotTildeFullEqual 2247
NotTildeTilde 2249
NotVerticalBar 2224
Nscr 1D4A9
Ntilde D1
Nu 39D
OElig 152
Oacute D3
Ocirc D4
Ocy 41E
Odblac 150
Ofr 1D512
Ograve D2
Omacr 14C
Omega 3A9
Omicron 39F
Oopf 1D546
OpenCurlyDoubleQuote 201C
OpenCurlyQuote 2018
Or 2A54
Oscr 1D4AA
Oslash D8
Otilde D5
Otimes 2A37
Ouml D6
OverBar 203E
OverBrace 23DE
OverBracket 23B4
OverParenthesis 23DC
PartialD 2202
Pcy 41F
Pfr 1D513
Phi 3A6
Pi 3A0
PlusMinus B1
Poincareplane 210C
Popf 2119
Pr 2ABB
Precedes 227A
PrecedesEqual 2AAF
PrecedesSlantEqual 227C
PrecedesTilde 227E
Prime 2033
Product 220F
Proportion 2237
Proportional 221D
Pscr 1D4AB
Psi 3A8
QUOT 22
Qfr 1D514
Qopf 211A
Qscr 1D4AC
RBarr 2910
REG AE
Racute 154
Rang 27EB
Rarr 21A0
Rarrtl 2916
Rcaron 158
Rcedil 156
Rcy 420
Re 211C
ReverseElement 220B
ReverseEquilibrium 21CB
ReverseUpEquilibrium 296F
Rfr 211C
Rho 3A1
RightAngleBracket 27E9
RightArrow 2192
RightArrowBar 21E5
RightArrowLeftArrow 21C4
RightCeiling 2309
RightDoubleBracket 27E7
RightDownTeeVector 295D
RightDownVector 21C2
RightDownVectorBar 2955
RightFloor 230B
RightTee 22A2
RightTeeArrow 21A6
RightTeeVector 295B
RightTriangle 22B3
RightTriangleBar 29D0
RightTriangleEqual 22B5
RightUpDownVector 294F
RightUpTeeVector 295C
RightUpVector 21BE
RightUpVectorBar 2954
RightVector 21C0
RightVectorBar 2953
Rightarrow 21D2
Ropf 211D
RoundImplies 2970
Rrightarrow 21DB
Rscr 211B
Rsh 21B1
RuleDelayed 29F4
SHCHcy 429
SHcy 428
SOFTcy 42C
Sacute 15A
Sc 2ABC
Scaron 160
Scedil 15E
Scirc 15C
Scy 421
Sfr 1D516
ShortDownArrow 2193
ShortLeftArrow 2190
ShortRightArrow 2192
ShortUpArrow 2191
Sigma 3A3
SmallCircle 2218
Sopf 1D54A
Sqrt 221A
Square 25A1
SquareIntersection 2293
SquareSubset 228F
SquareSubsetEqual 2291
SquareSuperset 2290
SquareSupersetEqual 2292
SquareUnion 2294
Sscr 1D4AE
Star 22C6
Sub 22D0
Subset 22D0
SubsetEqual 2286
Succeeds 227B
SucceedsEqual 2AB0
SucceedsSlantEqual 227D
SucceedsTilde 227F
SuchThat 220B
Sum 2211
Sup 22D1
Superset 2283
SupersetEqual 2287
Supset 22D1
THORN DE
TRADE 2122
TSHcy 40B
TScy 426
Tab 9
Tau 3A4
Tcaron 164
Tcedil 162
Tcy 422
Tfr 1D517
Therefore 2234
Theta 398
ThickSpace 205F 200A
ThinSpace 2009
Tilde 223C
TildeEqual 2243
TildeFullEqual 2245
TildeTilde 2248
Topf 1D54B
TripleDot 20DB
Tscr 1D4AF
Tstrok 166
Uacute DA
Uarr 219F
Uarrocir 2949
Ubrcy 40E
Ubreve 16C
Ucirc DB
Ucy 423
Udblac 170
Ufr 1D518
Ugrave D9
Umacr 16A
UnderBar 5F
UnderBrace 23DF
UnderBracket 23B5
UnderParenthesis 23DD
Union 22C3
UnionPlus 228E
Uogon 172
Uopf 1D54C
UpArrow 2191
UpArrowBar 2912
UpArrowDownArrow 21C5
UpDownArrow 2195
UpEquilibrium 296E
UpTee 22A5
UpTeeArrow 21A5
Uparrow 21D1
Updownarrow 21D5
UpperLeftArrow 2196
UpperRightArrow 2197
Upsi 3D2
Upsilon 3A5
Uring 16E
Uscr 1D4B0
Utilde 168
Uuml DC
VDash 22AB
Vbar 2AEB
Vcy 412
Vdash 22A9
Vdashl 2AE6
Vee 22C1
Verbar 2016
Vert 2016
VerticalBar 2223
VerticalLine 7C
VerticalSeparator 2758
VerticalTilde 2240
VeryThinSpace 200A
Vfr 1D519
Vopf 1D54D
Vscr 1D4B1
Vvdash 22AA
Wcirc 174
Wedge 22C0
Wfr 1D51A
Wopf 1D54E
Wscr 1D4B2
Xfr 1D51B
Xi 39E
Xopf 1D54F
Xscr 1D4B3
YAcy 42F
YIcy 407
YUcy 42E
Yacute DD
Ycirc 176
Ycy 42B
Yfr 1D51C
Yopf 1D550
Yscr 1D4B4
Yuml 178
ZHcy 416
Zacute 179
Zcaron 17D
Zcy 417
Zdot 17B
ZeroWidthSpace 200B
Zeta 396
Zfr 2128
Zopf 2124
Zscr 1D4B5
aacute E1
abreve 103
ac 223E
acE 223E 333
acd 223F
acirc E2
acute B4
acy 430
aelig E6
af 2061
afr 1D51E
agrave E0
alefsym 2135
aleph 2135
alpha 3B1
amacr 101
amalg 2A3F
amp 26
and 2227
andand 2A55
andd 2A5C
andslope 2A58
andv 2A5A
ang 2220
ange 29A4
angle 2220
angmsd 2221
angmsdaa 29A8
angmsdab 29A9
angmsdac 29AA
angmsdad 29AB
angmsdae 29AC
angmsdaf 29AD
angmsdag 29AE
angmsdah 29AF
angrt 221F
angrtvb 22BE
angrtvbd 299D
angsph 2222
angst C5
angzarr 237C
aogon 105
aopf 1D552
ap 2248
apE 2A70
apacir 2A6F
ape 224A
apid 224B
apos 27
approx 2248
approxeq 224A
aring E5
ascr 1D4B6
ast 2A
asymp 2248
asympeq 224D
atilde E3
auml E4
awconint 2233
awint 2A11
bNot 2AED
backcong 224C
backepsilon 3F6
backprime 2035
backsim 223D
backsimeq 22CD
barvee 22BD
barwed 2305
barwedge 2305
bbrk 23B5
bbrktbrk 23B6
bcong 224C
bcy 431
bdquo 201E
becaus 2235
because 2235
bemptyv 29B0
bepsi 3F6
bernou 212C
beta 3B2
beth 2136
between 226C
bfr 1D51F
bigcap 22C2
bigcirc 25EF
bigcup 22C3
bigodot 2A00
bigoplus 2A01
bigotimes 2A02
bigsqcup 2A06
bigstar 2605
bigtriangledown 25BD
bigtriangleup 25B3
biguplus 2A04
bigvee 22C1
bigwedge 22C0
bkarow 290D
blacklozenge 29EB
blacksquare 25AA
blacktriangle 25B4
blacktriangledown 25BE
blacktriangleleft 25C2
blacktriangleright 25B8
blank 2423
blk12 2592
blk14 2591
blk34 2593
block 2588
bne 3D 20E5
bnequiv 2261 20E5
bnot 2310
bopf 1D553
bot 22A5
bottom 22A5
bowtie 22C8
boxDL 2557
boxDR 2554
boxDl 2556
boxDr 2553
boxH 2550
boxHD 2566
boxHU 2569
boxHd 2564
boxHu 2567
boxUL 255D
boxUR 255A
boxUl 255C
boxUr 2559
boxV 2551
boxVH 256C
boxVL 2563
boxVR 2560
boxVh 256B
boxVl 2562
boxVr 255F
boxbox 29C9
boxdL 2555
boxdR 2552
boxdl 2510
boxdr 250C
boxh 2500
boxhD 2565
boxhU 2568
boxhd 252C
boxhu 2534
boxminus 229F
boxplus 229E
boxtimes 22A0
boxuL 255B
boxuR 2558
boxul 2518
boxur 2514
boxv 2502
boxvH 256A
boxvL 2561
boxvR 255E
boxvh 253C
boxvl 2524
boxvr 251C
bprime 2035
breve 2D8
brvbar A6
bscr 1D4B7
bsemi 204F
bsim 223D
bsime 22CD
bsol 5C
bsolb 29C5
bsolhsub 27C8
bull 2022
bullet 2022
bump 224E
bumpE 2AAE
bumpe 224F
bumpeq 224F
cacute 107
cap 2229
capand 2A44
capbrcup 2A49
capcap 2A4B
capcup 2A47
capdot 2A40
caps 2229 FE00
caret 2041
caron 2C7
ccaps 2A4D
ccaron 10D
ccedil E7
ccirc 109
ccups 2A4C
ccupssm 2A50
cdot 10B
cedil B8
cemptyv 29B2
cent A2
centerdot B7
cfr 1D520
chcy 447
check 2713
checkmark 2713
chi 3C7
cir 25CB
cirE 29C3
circ 2C6
circeq 2257
circlearrowleft 21BA
circlearrowright 21BB
circledR AE
circledS 24C8
circledast 229B
circledcirc 229A
circleddash 229D
cire 2257
cirfnint 2A10
cirmid 2AEF
cirscir 29C2
clubs 2663
clubsuit 2663
colon 3A
colone 2254
coloneq 2254
comma 2C
commat 40
comp 2201
compfn 2218
complement 2201
complexes 2102
cong 2245
congdot 2A6D
conint 222E
copf 1D554
coprod 2210
copy A9
copysr 2117
crarr 21B5
cross 2717
cscr 1D4B8
csub 2ACF
csube 2AD1
csup 2AD0
csupe 2AD2
ctdot 22EF
cudarrl 2938
cudarrr 2935
cuepr 22DE
cuesc 22DF
cularr 21B6
cularrp 293D
cup 222A
cupbrcap 2A48
cupcap 2A46
cupcup 2A4A
cupdot 228D
cupor 2A45
cups 222A FE00
curarr 21B7
curarrm 293C
curlyeqprec 22DE
curlyeqsucc 22DF
curlyvee 22CE
curlywedge 22CF
curren A4
curvearrowleft 21B6
curvearrowright 21B7
cuvee 22CE
cuwed 22CF
cwconint 2232
cwint 2231
cylcty 232D
dArr 21D3
dHar 2965
dagger 2020
daleth 2138
darr 2193
dash 2010
dashv 22A3
dbkarow 290F
dblac 2DD
dcaron 10F
dcy 434
dd 2146
ddagger 2021
ddarr 21CA
ddotseq 2A77
deg B0
delta 3B4
demptyv 29B1
dfisht 297F
dfr 1D521
dharl 21C3
dharr 21C2
diam 22C4
diamond 22C4
diamondsuit 2666
diams 2666
die A8
digamma 3DD
disin 22F2
div F7
divide F7
divideontimes 22C7
divonx 22C7
djcy 452
dlcorn 231E
dlcrop 230D
dollar 24
dopf 1D555
dot 2D9
doteq 2250
doteqdot 2251
dotminus 2238
dotplus 2214
dotsquare 22A1
doublebarwedge 2306
downarrow 2193
downdownarrows 21CA
downharpoonleft 21C3
downharpoonright 21C2
drbkarow 2910
drcorn 231F
drcrop 230C
dscr 1D4B9
dscy 455
dsol 29F6
dstrok 111
dtdot 22F1
dtri 25BF
dtrif 25BE
duarr 21F5
duhar 296F
dwangle 29A6
dzcy 45F
dzigrarr 27FF
eDDot 2A77
eDot 2251
eacute E9
easter 2A6E
ecaron 11B
ecir 2256
ecirc EA
ecolon 2255
ecy 44D
edot 117
ee 2147
efDot 2252
efr 1D522
eg 2A9A
egrave E8
egs 2A96
egsdot 2A98
el 2A99
elinters 23E7
ell 2113
els 2A95
elsdot 2A97
emacr 113
empty 2205
emptyset 2205
emptyv 2205
emsp13 2004
emsp14 2005
emsp 2003
eng 14B
ensp 2002
eogon 119
eopf 1D556
epar 22D5
eparsl 29E3
eplus 2A71
epsi 3B5
epsilon 3B5
epsiv 3F5
eqcirc 2256
eqcolon 2255
eqsim 2242
eqslantgtr 2A96
eqslantless 2A95
equals 3D
equest 225F
equiv 2261
equivDD 2A78
eqvparsl 29E5
erDot 2253
erarr 2971
escr 212F
esdot 2250
esim 2242
eta 3B7
eth F0
euml EB
euro 20AC
excl 21
exist 2203
expectation 2130
exponentiale 2147
fallingdotseq 2252
fcy 444
female 2640
ffilig FB03
fflig FB00
ffllig FB04
ffr 1D523
filig FB01
fjlig 66 6A
flat 266D
fllig FB02
fltns 25B1
fnof 192
fopf 1D557
forall 2200
fork 22D4
forkv 2AD9
fpartint 2A0D
frac12 BD
frac13 2153
frac14 BC
frac15 2155
frac16 2159
frac18 215B
frac23 2154
frac25 2156
frac34 BE
frac35 2157
frac38 215C
frac45 2158
frac56 215A
frac58 215D
frac78 215E
frasl 2044
frown 2322
fscr 1D4BB
gE 2267
gEl 2A8C
gacute 1F5
gamma 3B3
gammad 3DD
gap 2A86
gbreve 11F
gcirc 11D
gcy 433
gdot 121
ge 2265
gel 22DB
geq 2265
geqq 2267
geqslant 2A7E
ges 2A7E
gescc 2AA9
gesdot 2A80
gesdoto 2A82
gesdotol 2A84
gesl 22DB FE00
gesles 2A94
gfr 1D524
gg 226B
ggg 22D9
gimel 2137
gjcy 453
gl 2277
glE 2A92
gla 2AA5
glj 2AA4
gnE 2269
gnap 2A8A
gnapprox 2A8A
gne 2A88
gneq 2A88
gneqq 2269
gnsim 22E7
gopf 1D558
grave 60
gscr 210A
gsim 2273
gsime 2A8E
gsiml 2A90
gt 3E
gtcc 2AA7
gtcir 2A7A
gtdot 22D7
gtlPar 2995
gtquest 2A7C
gtrapprox 2A86
gtrarr 2978
gtrdot 22D7
gtreqless 22DB
gtreqqless 2A8C
gtrless 2277
gtrsim 2273
gvertneqq 2269 FE00
gvnE 2269 FE00
hArr 21D4
hairsp 200A
half BD
hamilt 210B
hardcy 44A
harr 2194
harrcir 2948
harrw 21AD
hbar 210F
hcirc 125
hearts 2665
heartsuit 2665
hellip 2026
hercon 22B9
hfr 1D525
hksearow 2925
hkswarow 2926
hoarr 21FF
homtht 223B
hookleftarrow 21A9
hookrightarrow 21AA
hopf 1D559
horbar 2015
hscr 1D4BD
hslash 210F
hstrok 127
hybull 2043
hyphen 2010
iacute ED
ic 2063
icirc EE
icy 438
iecy 435
iexcl A1
iff 21D4
ifr 1D526
igrave EC
ii 2148
iiiint 2A0C
iiint 222D
iinfin 29DC
iiota 2129
ijlig 133
imacr 12B
image 2111
imagline 2110
imagpart 2111
imath 131
imof 22B7
imped 1B5
in 2208
incare 2105
infin 221E
infintie 29DD
inodot 131
int 222B
intcal 22BA
integers 2124
intercal 22BA
intlarhk 2A17
intprod 2A3C
iocy 451
iogon 12F
iopf 1D55A
iota 3B9
iprod 2A3C
iquest BF
iscr 1D4BE
isin 2208
isinE 22F9
isindot 22F5
isins 22F4
isinsv 22F3
isinv 2208
it 2062
itilde 129
iukcy 456
iuml EF
jcirc 135
jcy 439
jfr 1D527
jmath 237
jopf 1D55B
jscr 1D4BF
jsercy 458
jukcy 454
kappa 3BA
kappav 3F0
kcedil 137
kcy 43A
kfr 1D528
kgreen 138
khcy 445
kjcy 45C
kopf 1D55C
kscr 1D4C0
lAarr 21DA
lArr 21D0
lAtail 291B
lBarr 290E
lE 2266
lEg 2A8B
lHar 2962
lacute 13A
laemptyv 29B4
lagran 2112
lambda 3BB
lang 27E8
langd 2991
langle 27E8
lap 2A85
laquo AB
larr 2190
larrb 21E4
larrbfs 291F
larrfs 291D
larrhk 21A9
larrlp 21AB
larrpl 2939
larrsim 2973
larrtl 21A2
lat 2AAB
latail 2919
late 2AAD
lates 2AAD FE00
lbarr 290C
lbbrk 2772
lbrace 7B
lbrack 5B
lbrke 298B
lbrksld 298F
lbrkslu 298D
lcaron 13E
lcedil 13C
lceil 2308
lcub 7B
lcy 43B
ldca 2936
ldquo 201C
ldquor 201E
ldrdhar 2967
ldrushar 294B
ldsh 21B2
le 2264
leftarrow 2190
leftarrowtail 21A2
leftharpoondown 21BD
leftharpoonup 21BC
leftleftarrows 21C7
leftrightarrow 2194
leftrightarrows 21C6
leftrightharpoons 21CB
leftrightsquigarrow 21AD
leftthreetimes 22CB
leg 22DA
leq 2264
leqq 2266
leqslant 2A7D
les 2A7D
lescc 2AA8
lesdot 2A7F
lesdoto 2A81
lesdotor 2A83
lesg 22DA FE00
lesges 2A93
lessapprox 2A85
lessdot 22D6
lesseqgtr 22DA
lesseqqgtr 2A8B
lessgtr 2276
lesssim 2272
lfisht 297C
lfloor 230A
lfr 1D529
lg 2276
lgE 2A91
lhard 21BD
lharu 21BC
lharul 296A
lhblk 2584
ljcy 459
ll 226A
llarr 21C7
llcorner 231E
llhard 296B
lltri 25FA
lmidot 140
lmoust 23B0
lmoustache 23B0
lnE 2268
lnap 2A89
lnapprox 2A89
lne 2A87
lneq 2A87
lneqq 2268
lnsim 22E6
loang 27EC
loarr 21FD
lobrk 27E6
longleftarrow 27F5
longleftrightarrow 27F7
longmapsto 27FC
longrightarrow 27F6
looparrowleft 21AB
looparrowright 21AC
lopar 2985
lopf 1D55D
loplus 2A2D
lotimes 2A34
lowast 2217
lowbar 5F
loz 25CA
lozenge 25CA
lozf 29EB
lpar 28
lparlt 2993
lrarr 21C6
lrcorner 231F
lrhar 21CB
lrhard 296D
lrm 200E
lrtri 22BF
lsaquo 2039
lscr 1D4C1
lsh 21B0
lsim 2272
lsime 2A8D
lsimg 2A8F
lsqb 5B
lsquo 2018
lsquor 201A
lstrok 142
lt 3C
ltcc 2AA6
ltcir 2A79
ltdot 22D6
lthree 22CB
ltimes 22C9
ltlarr 2976
ltquest 2A7B
ltrPar 2996
ltri 25C3
ltrie 22B4
ltrif 25C2
lurdshar 294A
luruhar 2966
lvertneqq 2268 FE00
lvnE 2268 FE00
mDDot 223A
macr AF
male 2642
malt 2720
maltese 2720
map 21A6
mapsto 21A6
mapstodown 21A7
mapstoleft 21A4
mapstoup 21A5
marker 25AE
mcomma 2A29
mcy 43C
mdash 2014
measuredangle 2221
mfr 1D52A
mho 2127
micro B5
mid 2223
midast 2A
midcir 2AF0
middot B7
minus 2212
minusb 229F
minusd 2238
minusdu 2A2A
mlcp 2ADB
mldr 2026
mnplus 2213
models 22A7
mopf 1D55E
mp 2213
mscr 1D4C2
mstpos 223E
mu 3BC
multimap 22B8
mumap 22B8
nGg 22D9 338
nGt 226B 20D2
nGtv 226B 338
nLeftarrow 21CD
nLeftrightarrow 21CE
nLl 22D8 338
nLt 226A 20D2
nLtv 226A 338
nRightarrow 21CF
nVDash 22AF
nVdash 22AE
nabla 2207
nacute 144
nang 2220 20D2
nap 2249
napE 2A70 338
napid 224B 338
napos 149
napprox 2249
natur 266E
natural 266E
naturals 2115
nbsp A0
nbump 224E 338
nbumpe 224F 338
ncap 2A43
ncaron 148
ncedil 146
ncong 2247
ncongdot 2A6D 338
ncup 2A42
ncy 43D
ndash 2013
ne 2260
neArr 21D7
nearhk 2924
nearr 2197
nearrow 2197
nedot 2250 338
nequiv 2262
nesear 2928
nesim 2242 338
nexist 2204
nexists 2204
nfr 1D52B
ngE 2267 338
nge 2271
ngeq 2271
ngeqq 2267 338
ngeqslant 2A7E 338
nges 2A7E 338
ngsim 2275
ngt 226F
ngtr 226F
nhArr 21CE
nharr 21AE
nhpar 2AF2
ni 220B
nis 22FC
nisd 22FA
niv 220B
njcy 45A
nlArr 21CD
nlE 2266 338
nlarr 219A
nldr 2025
nle 2270
nleftarrow 219A
nleftrightarrow 21AE
nleq 2270
nleqq 2266 338
nleqslant 2A7D 338
nles 2A7D 338
nless 226E
nlsim 2274
nlt 226E
nltri 22EA
nltrie 22EC
nmid 2224
nopf 1D55F
not AC
notin 2209
notinE 22F9 338
notindot 22F5 338
notinva 2209
notinvb 22F7
notinvc 22F6
notni 220C
notniva 220C
notnivb 22FE
notnivc 22FD
npar 2226
nparallel 2226
nparsl 2AFD 20E5
npart 2202 338
npolint 2A14
npr 2280
nprcue 22E0
npre 2AAF 338
nprec 2280
npreceq 2AAF 338
nrArr 21CF
nrarr 219B
nrarrc 2933 338
nrarrw 219D 338
nrightarrow 219B
nrtri 22EB
nrtrie 22ED
nsc 2281
nsccue 22E1
nsce 2AB0 338
nscr 1D4C3
nshortmid 2224
nshortparallel 2226
nsim 2241
nsime 2244
nsimeq 2244
nsmid 2224
nspar 2226
nsqsube 22E2
nsqsupe 22E3
nsub 2284
nsubE 2AC5 338
nsube 2288
nsubset 2282 20D2
nsubseteq 2288
nsubseteqq 2AC5 338
nsucc 2281
nsucceq 2AB0 338
nsup 2285
nsupE 2AC6 338
nsupe 2289
nsupset 2283 20D2
nsupseteq 2289
nsupseteqq 2AC6 338
ntgl 2279
ntilde F1
ntlg 2278
ntriangleleft 22EA
ntrianglelefteq 22EC
ntriangleright 22EB
ntrianglerighteq 22ED
nu 3BD
num 23
numero 2116
numsp 2007
nvDash 22AD
nvHarr 2904
nvap 224D 20D2
nvdash 22AC
nvge 2265 20D2
nvgt 3E 20D2
nvinfin 29DE
nvlArr 2902
nvle 2264 20D2
nvlt 3C 20D2
nvltrie 22B4 20D2
nvrArr 2903
nvrtrie 22B5 20D2
nvsim 223C 20D2
nwArr 21D6
nwarhk 2923
nwarr 2196
nwarrow 2196
nwnear 2927
oS 24C8
oacute F3
oast 229B
ocir 229A
ocirc F4
ocy 43E
odash 229D
odblac 151
odiv 2A38
odot 2299
odsold 29BC
oelig 153
ofcir 29BF
ofr 1D52C
ogon 2DB
ograve F2
ogt 29C1
ohbar 29B5
ohm 3A9
oint 222E
olarr 21BA
olcir 29BE
olcross 29BB
oline 203E
olt 29C0
omacr 14D
omega 3C9
omicron 3BF
omid 29B6
ominus 2296
oopf 1D560
opar 29B7
operp 29B9
oplus 2295
or 2228
orarr 21BB
ord 2A5D
order 2134
orderof 2134
ordf AA
ordm BA
origof 22B6
oror 2A56
orslope 2A57
orv 2A5B
oscr 2134
oslash F8
osol 2298
otilde F5
otimes 2297
otimesas 2A36
ouml F6
ovbar 233D
par 2225
para B6
parallel 2225
parsim 2AF3
parsl 2AFD
part 2202
pcy 43F
percnt 25
period 2E
permil 2030
perp 22A5
pertenk 2031
pfr 1D52D
phi 3C6
phiv 3D5
phmmat 2133
phone 260E
pi 3C0
pitchfork 22D4
piv 3D6
planck 210F
planckh 210E
plankv 210F
plus 2B
plusacir 2A23
plusb 229E
pluscir 2A22
plusdo 2214
plusdu 2A25
pluse 2A72
plusmn B1
plussim 2A26
plustwo 2A27
pm B1
pointint 2A15
popf 1D561
pound A3
pr 227A
prE 2AB3
prap 2AB7
prcue 227C
pre 2AAF
prec 227A
precapprox 2AB7
preccurlyeq 227C
preceq 2AAF
precnapprox 2AB9
precneqq 2AB5
precnsim 22E8
precsim 227E
prime 2032
primes 2119
prnE 2AB5
prnap 2AB9
prnsim 22E8
prod 220F
profalar 232E
profline 2312
profsurf 2313
prop 221D
propto 221D
prsim 227E
prurel 22B0
pscr 1D4C5
psi 3C8
puncsp 2008
qfr 1D52E
qint 2A0C
qopf 1D562
qprime 2057
qscr 1D4C6
quaternions 210D
quatint 2A16
quest 3F
questeq 225F
quot 22
rAarr 21DB
rArr 21D2
rAtail 291C
rBarr 290F
rHar 2964
race 223D 331
racute 155
radic 221A
raemptyv 29B3
rang 27E9
rangd 2992
range 29A5
rangle 27E9
raquo BB
rarr 2192
rarrap 2975
rarrb 21E5
rarrbfs 2920
rarrc 2933
rarrfs 291E
rarrhk 21AA
rarrlp 21AC
rarrpl 2945
rarrsim 2974
rarrtl 21A3
rarrw 219D
ratail 291A
ratio 2236
rationals 211A
rbarr 290D
rbbrk 2773
rbrace 7D
rbrack 5D
rbrke 298C
rbrksld 298E
rbrkslu 2990
rcaron 159
rcedil 157
rceil 2309
rcub 7D
rcy 440
rdca 2937
rdldhar 2969
rdquo 201D
rdquor 201D
rdsh 21B3
real 211C
realine 211B
realpart 211C
reals 211D
rect 25AD
reg AE
rfisht 297D
rfloor 230B
rfr 1D52F
rhard 21C1
rharu 21C0
rharul 296C
rho 3C1
rhov 3F1
rightarrow 2192
rightarrowtail 21A3
rightharpoondown 21C1
rightharpoonup 21C0
rightleftarrows 21C4
rightleftharpoons 21CC
rightrightarrows 21C9
rightsquigarrow 219D
rightthreetimes 22CC
ring 2DA
risingdotseq 2253
rlarr 21C4
rlhar 21CC
rlm 200F
rmoust 23B1
rmoustache 23B1
rnmid 2AEE
roang 27ED
roarr 21FE
robrk 27E7
ropar 2986
ropf 1D563
roplus 2A2E
rotimes 2A35
rpar 29
rpargt 2994
rppolint 2A12
rrarr 21C9
rsaquo 203A
rscr 1D4C7
rsh 21B1
rsqb 5D
rsquo 2019
rsquor 2019
rthree 22CC
rtimes 22CA
rtri 25B9
rtrie 22B5
rtrif 25B8
rtriltri 29CE
ruluhar 2968
rx 211E
sacute 15B
sbquo 201A
sc 227B
scE 2AB4
scap 2AB8
scaron 161
sccue 227D
sce 2AB0
scedil 15F
scirc 15D
scnE 2AB6
scnap 2ABA
scnsim 22E9
scpolint 2A13
scsim 227F
scy 441
sdot 22C5
sdotb 22A1
sdote 2A66
seArr 21D8
searhk 2925
searr 2198
searrow 2198
sect A7
semi 3B
seswar 2929
setminus 2216
setmn 2216
sext 2736
sfr 1D530
sfrown 2322
sharp 266F
shchcy 449
shcy 448
shortmid 2223
shortparallel 2225
shy AD
sigma 3C3
sigmaf 3C2
sigmav 3C2
sim 223C
simdot 2A6A
sime 2243
simeq 2243
simg 2A9E
simgE 2AA0
siml 2A9D
simlE 2A9F
simne 2246
simplus 2A24
simrarr 2972
slarr 2190
smallsetminus 2216
smashp 2A33
smeparsl 29E4
smid 2223
smile 2323
smt 2AAA
smte 2AAC
smtes 2AAC FE00
softcy 44C
sol 2F
solb 29C4
solbar 233F
sopf 1D564
spades 2660
spadesuit 2660
spar 2225
sqcap 2293
sqcaps 2293 FE00
sqcup 2294
sqcups 2294 FE00
sqsub 228F
sqsube 2291
sqsubset 228F
sqsubseteq 2291
sqsup 2290
sqsupe 2292
sqsupset 2290
sqsupseteq 2292
squ 25A1
square 25A1
squarf 25AA
squf 25AA
srarr 2192
sscr 1D4C8
ssetmn 2216
ssmile 2323
sstarf 22C6
star 2606
starf 2605
straightepsilon 3F5
straightphi 3D5
strns AF
sub 2282
subE 2AC5
subdot 2ABD
sube 2286
subedot 2AC3
submult 2AC1
subnE 2ACB
subne 228A
subplus 2ABF
subrarr 2979
subset 2282
subseteq 2286
subseteqq 2AC5
subsetneq 228A
subsetneqq 2ACB
subsim 2AC7
subsub 2AD5
subsup 2AD3
succ 227B
succapprox 2AB8
succcurlyeq 227D
succeq 2AB0
succnapprox 2ABA
succneqq 2AB6
succnsim 22E9
succsim 227F
sum 2211
sung 266A
sup1 B9
sup2 B2
sup3 B3
sup 2283
supE 2AC6
supdot 2ABE
supdsub 2AD8
supe 2287
supedot 2AC4
suphsol 27C9
suphsub 2AD7
suplarr 297B
supmult 2AC2
supnE 2ACC
supne 228B
supplus 2AC0
supset 2283
supseteq 2287
supseteqq 2AC6
supsetneq 228B
supsetneqq 2ACC
supsim 2AC8
supsub 2AD4
supsup 2AD6
swArr 21D9
swarhk 2926
swarr 2199
swarrow 2199
swnwar 292A
szlig DF
target 2316
tau 3C4
tbrk 23B4
tcaron 165
tcedil 163
tcy 442
tdot 20DB
telrec 2315
tfr 1D531
there4 2234
therefore 2234
theta 3B8
thetasym 3D1
thetav 3D1
thickapprox 2248
thicksim 223C
thinsp 2009
thkap 2248
thksim 223C
thorn FE
tilde 2DC
times D7
timesb 22A0
timesbar 2A31
timesd 2A30
tint 222D
toea 2928
top 22A4
topbot 2336
topcir 2AF1
topf 1D565
topfork 2ADA
tosa 2929
tprime 2034
trade 2122
triangle 25B5
triangledown 25BF
triangleleft 25C3
trianglelefteq 22B4
triangleq 225C
triangleright 25B9
trianglerighteq 22B5
tridot 25EC
trie 225C
triminus 2A3A
triplus 2A39
trisb 29CD
tritime 2A3B
trpezium 23E2
tscr 1D4C9
tscy 446
tshcy 45B
tstrok 167
twixt 226C
twoheadleftarrow 219E
twoheadrightarrow 21A0
uArr 21D1
uHar 2963
uacute FA
uarr 2191
ubrcy 45E
ubreve 16D
ucirc FB
ucy 443
udarr 21C5
udblac 171
udhar 296E
ufisht 297E
ufr 1D532
ugrave F9
uharl 21BF
uharr 21BE
uhblk 2580
ulcorn 231C
ulcorner 231C
ulcrop 230F
ultri 25F8
umacr 16B
uml A8
uogon 173
uopf 1D566
uparrow 2191
updownarrow 2195
upharpoonleft 21BF
upharpoonright 21BE
uplus 228E
upsi 3C5
upsih 3D2
upsilon 3C5
upuparrows 21C8
urcorn 231D
urcorner 231D
urcrop 230E
uring 16F
urtri 25F9
uscr 1D4CA
utdot 22F0
utilde 169
utri 25B5
utrif 25B4
uuarr 21C8
uuml FC
uwangle 29A7
vArr 21D5
vBar 2AE8
vBarv 2AE9
vDash 22A8
vangrt 299C
varepsilon 3F5
varkappa 3F0
varnothing 2205
varphi 3D5
varpi 3D6
varpropto 221D
varr 2195
varrho 3F1
varsigma 3C2
varsubsetneq 228A FE00
varsubsetneqq 2ACB FE00
varsupsetneq 228B FE00
varsupsetneqq 2ACC FE00
vartheta 3D1
vartriangleleft 22B2
vartriangleright 22B3
vcy 432
vdash 22A2
vee 2228
veebar 22BB
veeeq 225A
vellip 22EE
verbar 7C
vert 7C
vfr 1D533
vltri 22B2
vnsub 2282 20D2
vnsup 2283 20D2
vopf 1D567
vprop 221D
vrtri 22B3
vscr 1D4CB
vsubnE 2ACB FE00
vsubne 228A FE00
vsupnE 2ACC FE00
vsupne 228B FE00
vzigzag 299A
wcirc 175
wedbar 2A5F
wedge 2227
wedgeq 2259
weierp 2118
wfr 1D534
wopf 1D568
wp 2118
wr 2240
wreath 2240
wscr 1D4CC
xcap 22C2
xcirc 25EF
xcup 22C3
xdtri 25BD
xfr 1D535
xhArr 27FA
xharr 27F7
xi 3BE
xlArr 27F8
xlarr 27F5
xmap 27FC
xnis 22FB
xodot 2A00
xopf 1D569
xoplus 2A01
xotime 2A02
xrArr 27F9
xrarr 27F6
xscr 1D4CD
xsqcup 2A06
xuplus 2A04
xutri 25B3
xvee 22C1
xwedge 22C0
yacute FD
yacy 44F
ycirc 177
ycy 44B
yen A5
yfr 1D536
yicy 457
yopf 1D56A
yscr 1D4CE
yucy 44E
yuml FF
zacute 17A
zcaron 17E
zcy 437
zdot 17C
zeetrf 2128
zeta 3B6
zfr 1D537
zhcy 436
zigrarr 21DD
zopf 1D56B
zscr 1D4CF
zwj 200D
zwnj 200C
"""


def _named_entity(name: String, mut out: List[UInt8]) -> Bool:
    """Append a named character reference's UTF-8, or return False.

    A name that HTML does not define stays literal text, as in CommonMark.
    """
    var table = String(_ENTITIES)
    var at = table.find("\n" + name + " ")
    if at < 0:
        return False
    var bytes = table.as_bytes()
    var i = at + len(name.as_bytes()) + 2
    var code = 0
    while i < len(bytes) and bytes[i] != _NEWLINE:
        if bytes[i] == _SPACE:
            _utf8(code, out)
            code = 0
        else:
            code = code * 16 + _hex(bytes[i])
        i += 1
    _utf8(code, out)
    return True


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
    if not _named_entity(_text_of(bytes, start, i), out):
        return 0
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
