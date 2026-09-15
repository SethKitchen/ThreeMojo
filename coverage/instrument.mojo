# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rewrites Mojo sources into instrumented copies that report what they run.

A statement gets a `_cov_hit("<module>:<line>")` call inserted on the line
above it, at matching indentation. The mapping back to the original file is the
line number embedded in the probe id, so the instrumented copy is disposable
and only ever lives under `coverage/build/`.
"""

from coverage.scanner import Scanner, indent_of

comptime PROBE_IMPORT = (
    "from coverage.runtime import hit as _cov_hit, branch as _cov_branch"
)

# Decisions whose condition is wrapped so both outcomes become observable.
comptime BRANCH_KEYWORDS = ["if ", "elif ", "while "]

# A `for` loop has no condition to wrap. Its two outcomes are "the body ran"
# and "the sequence was empty", so a counter is bumped inside the body and
# read once the loop has finished.
#
# It is an Int counter and not a Bool flag for a reason that cost a day to
# find: a Bool assigned the constant `True` inside a loop and read after it
# sends the Mojo compiler's dataflow analysis superlinear on nested loops.
# An instrumented sphere took minutes to *compile*; `+= 1` on an Int is not a
# constant assignment, and the same file builds in two seconds.
comptime LOOP_KEYWORD = "for "

# Opt-out for a decision whose second outcome is unreachable rather than
# untested — a loop over a length an invariant already proves is non-zero, say.
# Unlike silently dropping a decision, this is visible in the source and shows
# up in review, which is why it is spelled out per line.
comptime PRAGMA_NO_BRANCH = "# pragma: no branch"


@fieldwise_init
struct _LoopCloser(Copyable, Movable):
    """A `for` loop awaiting the probe that runs after its body."""

    var indent: Int
    var id: String
    var flag: String


struct Instrumented(Movable):
    """An instrumented source file and the original lines it can report on."""

    var text: String
    var lines: List[Int]
    var branches: List[Int]
    # Parallel to `branches`: how many individual conditions that decision was
    # split into, or 0 when it is a single condition or a loop.
    var conditions: List[Int]

    def __init__(
        out self,
        var text: String,
        var lines: List[Int],
        var branches: List[Int],
        var conditions: List[Int],
    ):
        """Store the rewritten text with its executable and decision lines."""
        self.text = text^
        self.lines = lines^
        self.branches = branches^
        self.conditions = conditions^


def _substring(line: String, start: Int, end: Int) -> String:
    """Return the codepoints of `line` in the half-open range [start, end).

    Mojo has no string slicing, so the range is accumulated by hand.
    """
    var out = String("")
    var index = 0
    for cp in line.codepoint_slices():
        if index >= start and index < end:
            out += String(cp)
        index += 1
    return out^


def _codepoint_count(line: String) -> Int:
    """Return the number of codepoints in `line`."""
    var count = 0
    for _ in line.codepoint_slices():
        count += 1
    return count


def _statement_colon(line: String) -> Int:
    """Return the index of the colon ending a block header, or -1 if absent.

    Colons inside brackets (type annotations, dict literals), inside string
    literals, or after a `#` comment do not end the header.
    """
    var depth = 0
    var quote = String("")
    var index = 0
    var found = -1
    for cp in line.codepoint_slices():
        if quote != "":
            if cp == quote:
                quote = String("")
        elif cp == '"' or cp == "'":
            quote = String(cp)
        elif cp == "#":
            break
        elif cp == "(" or cp == "[" or cp == "{":
            depth += 1
        elif cp == ")" or cp == "]" or cp == "}":
            depth -= 1
        elif cp == ":" and depth == 0:
            found = index
        index += 1
    return found


def _strip_comment(line: String) -> String:
    """Return `line` with any trailing `#` comment removed.

    Joining the physical lines of a multi-line header would otherwise push the
    code after a comment onto the same line, commenting it out.
    """
    var out = String("")
    var quote = String("")
    for cp in line.codepoint_slices():
        if quote != "":
            if cp == quote:
                quote = String("")
        elif cp == '"' or cp == "'":
            quote = String(cp)
        elif cp == "#":
            break
        out += String(cp)
    return String(out.rstrip())


def _branch_keyword(stripped: String) -> String:
    """Return the decision keyword `stripped` begins with, or an empty string.
    """
    comptime for keyword in BRANCH_KEYWORDS:
        if stripped.startswith(keyword):
            return String(keyword)
    return String("")


def _word_at(chars: List[String], start: Int, word: String) raises -> Bool:
    """Return True if `word` appears in `chars` beginning at `start`."""
    var offset = 0
    for cp in word.codepoint_slices():
        if start + offset >= len(chars) or chars[start + offset] != cp:
            return False
        offset += 1
    return True


def _separator_at(chars: List[String], index: Int) raises -> String:
    """Return the boolean operator starting at `index`, or an empty string.

    Matches ` and ` / ` or ` with their surrounding spaces so that identifiers
    such as `android` or `original` are never split.
    """
    if _word_at(chars, index, String(" and ")):
        return String(" and ")
    if _word_at(chars, index, String(" or ")):
        return String(" or ")
    return String("")


def split_conditions(condition: String) raises -> List[String]:
    """Split `condition` into operands and the operators between them.

    Returns alternating entries: operand, operator, operand, ... Only
    top-level operators split, so brackets and string literals stay intact and
    `not (a and b)` remains a single condition.

    Args:
        condition: The decision's condition text.

    Returns:
        Alternating operand and operator segments.

    Raises:
        Error: Never; present to match the helpers it calls.
    """
    var chars = List[String]()
    for cp in condition.codepoint_slices():
        chars.append(String(cp))

    var parts = List[String]()
    var current = String("")
    var depth = 0
    var quote = String("")
    var index = 0

    while index < len(chars):
        var ch = chars[index]
        if quote != "":
            if ch == quote:
                quote = String("")
            current += ch
            index += 1
            continue
        if ch == '"' or ch == "'":
            quote = ch
            current += ch
            index += 1
            continue
        if ch == "(" or ch == "[" or ch == "{":
            depth += 1
        elif ch == ")" or ch == "]" or ch == "}":
            depth -= 1
        elif depth == 0:
            var separator = _separator_at(chars, index)
            if separator != "":
                parts.append(String(current.strip()))
                parts.append(separator)
                current = String("")
                var consumed = 0
                for _ in separator.codepoint_slices():
                    consumed += 1
                index += consumed
                continue
        current += ch
        index += 1

    parts.append(String(current.strip()))
    return parts^


struct Wrapped(Movable):
    """A rewritten decision header and how many conditions it now reports."""

    var text: String
    var conditions: Int

    def __init__(out self, var text: String, conditions: Int):
        """Store the rewritten header text and its condition count."""
        self.text = text^
        self.conditions = conditions


def _wrap_condition(
    line: String, keyword: String, id: String
) raises -> Wrapped:
    """Return `line` with its decision and each condition wrapped for probing.

    The whole decision is wrapped for decision coverage, and when it is a
    compound of `and`/`or` operands each operand is wrapped too, giving
    condition coverage. Wrapping only the leaves preserves both operator
    precedence and short-circuit evaluation.

    Args:
        line: The physical or joined logical header line.
        keyword: The decision keyword the line begins with.
        id: Probe id for the decision; conditions get `id.0`, `id.1`, ...

    Returns:
        The rewritten line, unchanged if it holds no usable condition.

    Raises:
        Error: Never; present to match the helpers it calls.
    """
    var colon = _statement_colon(line)
    if colon < 0:
        return Wrapped(String(line), 0)

    var indent = indent_of(line)
    var condition_start = indent + _codepoint_count(keyword)
    var condition = String(_substring(line, condition_start, colon).strip())
    if condition == "":
        return Wrapped(String(line), 0)
    # `while True:` is a loop, not a decision: a literal condition has exactly
    # one outcome, so reporting the other as "never evaluated" is noise.
    if condition == "True" or condition == "False":
        return Wrapped(String(line), 0)

    var parts = split_conditions(condition)
    var rebuilt = String("")
    var conditions = 0
    # A single operand needs no inner probe; the decision's own probe says
    # everything there is to say about it.
    var split = len(parts) > 1
    var index = 0
    while index < len(parts):
        if index % 2 == 1:
            rebuilt += parts[index]
        elif split:
            rebuilt += (
                '_cov_branch("'
                + id
                + "."
                + String(conditions)
                + '", '
                + parts[index]
                + ")"
            )
            conditions += 1
        else:
            rebuilt += parts[index]
        index += 1

    # Everything from the colon onward is kept so trailing comments survive.
    var tail = _substring(line, colon, _codepoint_count(line))
    return Wrapped(
        " " * indent
        + keyword
        + '_cov_branch("'
        + id
        + '", '
        + rebuilt
        + ")"
        + tail,
        conditions,
    )


def _opens_top_level_block(line: String) -> Bool:
    """Return True if `line` starts a top-level definition or decorator."""
    if indent_of(line) != 0:
        return False
    var stripped = String(line.strip())
    return (
        stripped.startswith("def ")
        or stripped.startswith("async def ")
        or stripped.startswith("struct ")
        or stripped.startswith("@")
    )


def _close_loops(
    mut out: String, mut closers: List[_LoopCloser], indent: Int
) raises:
    """Emit the trailing probe for every loop whose body has just ended.

    Reading the flag after the loop is what makes the empty-sequence outcome
    observable; nothing inside the body could report it.
    """
    while len(closers) > 0:
        var last = closers[len(closers) - 1].copy()
        if last.indent < indent:
            break
        _ = closers.pop()
        out += (
            " " * last.indent
            + '_ = _cov_branch("'
            + last.id
            + '", '
            + last.flag
            + " > 0)\n"
        )


def _emit_loop(
    mut out: String,
    mut branches: List[Int],
    mut conditions: List[Int],
    mut closers: List[_LoopCloser],
    header: String,
    number: Int,
    module: String,
):
    """Emit a `for` loop's counter, its header, and the probe on entry.

    Used for a header that fit on one line and for one joined from several,
    so the two cannot drift apart. The closer that reads the counter after
    the loop is queued for `_close_loops` to emit when the body ends.

    Args:
        out: Destination text.
        branches: Decision lines, appended to.
        conditions: Condition counts, appended to in step with `branches`.
        closers: Loops awaiting their trailing probe.
        header: The complete `for ...:` line, already comment-stripped if it
            was joined from several physical lines.
        number: The source line the header started on.
        module: Probe id prefix.
    """
    var flag = "_cov_loop_" + String(number)
    var id = module + ":" + String(number)
    branches.append(number)
    conditions.append(0)
    var indent = indent_of(header)
    out += " " * indent + "var " + flag + " = 0\n"
    out += header + "\n"
    # Bumped on entry, so a body that returns still reports the sequence was
    # non-empty.
    var body_indent = " " * (indent + 4)
    out += body_indent + flag + " += 1\n"
    out += body_indent + '_ = _cov_branch("' + id + '", True)\n'
    closers.append(_LoopCloser(indent, id, flag))


def instrument(source: String, module: String) raises -> Instrumented:
    """Return `source` rewritten with line probes for the module named `module`.

    Args:
        source: The original file's full text.
        module: Short name embedded in probe ids, e.g. "render/rasterizer".

    Returns:
        The instrumented text, the executable line numbers, and the lines
        holding decisions whose outcomes are tracked.

    Raises:
        Error: Never; present to match the scanner's raising signature.
    """
    var scanner = Scanner()
    var out = String("")
    var lines = List[Int]()
    var branches = List[Int]()
    var conditions = List[Int]()
    var number = 0
    var import_emitted = False

    # A decision header whose colon lies on a later line is accumulated here
    # until it is complete, then emitted as one logical line. Without this the
    # decision would be dropped from the manifest entirely, quietly shrinking
    # the denominator instead of showing up as a gap.
    var pending = String("")
    var pending_line = 0
    var pending_keyword = String("")
    # A `for` header can span lines too, and a pragma may sit on any of them,
    # so both are tracked for the whole logical header rather than its first
    # physical line. Getting that wrong emitted a loop prologue into the
    # middle of a `range(` argument list.
    var pending_is_loop = False
    var pending_excluded = False
    var closers = List[_LoopCloser]()

    for raw in source.splitlines():
        var line = String(raw)
        number += 1

        # Ask before scanning: the line closing a docstring reports False
        # afterwards, and prose must never be read as a declaration.
        var was_prose = scanner.in_docstring()
        var was_continuation = scanner.in_continuation()
        var executable = scanner.is_executable(line)

        # The import cannot precede a module docstring, which must stay the
        # file's first expression, so it goes just above the first definition.
        if not import_emitted and not was_prose:
            if _opens_top_level_block(line):
                out += PROBE_IMPORT + "\n"
                import_emitted = True

        # Still accumulating a header split over several physical lines.
        if pending != "":
            pending_excluded = pending_excluded or PRAGMA_NO_BRANCH in line
            pending += " " + _strip_comment(String(line.strip()))
            if _statement_colon(pending) >= 0:
                if pending_excluded:
                    out += pending + "\n"
                elif pending_is_loop:
                    _emit_loop(
                        out,
                        branches,
                        conditions,
                        closers,
                        pending,
                        pending_line,
                        module,
                    )
                else:
                    var id = module + ":" + String(pending_line)
                    var joined = _wrap_condition(pending, pending_keyword, id)
                    if joined.text != pending:
                        branches.append(pending_line)
                        conditions.append(joined.conditions)
                    out += joined.text + "\n"
                pending = String("")
            continue

        # A significant line at or left of a loop's own column ends its body.
        var significant = (
            not was_prose
            and not was_continuation
            and String(line.strip()) != ""
            and not String(line.strip()).startswith("#")
        )
        if significant:
            _close_loops(out, closers, indent_of(line))

        if executable:
            lines.append(number)
            out += " " * indent_of(line)
            out += '_cov_hit("' + module + ":" + String(number) + '")\n'

        var excluded = PRAGMA_NO_BRANCH in line

        if significant and String(line.strip()).startswith(LOOP_KEYWORD):
            if _statement_colon(line) < 0:
                # The header continues on the next line; decide about the
                # pragma once all of it has been seen.
                pending = _strip_comment(line)
                pending_line = number
                pending_is_loop = True
                pending_excluded = excluded
                continue
            if not excluded:
                _emit_loop(
                    out, branches, conditions, closers, line, number, module
                )
                continue

        # `elif` never takes a line probe but is still a decision, so branch
        # detection is deliberately independent of `executable`.
        var emitted = String(line)
        if not was_prose and not was_continuation and not excluded:
            var keyword = _branch_keyword(String(line.strip()))
            if keyword != "":
                if _statement_colon(line) < 0:
                    # The condition continues on the next line.
                    pending = _strip_comment(line)
                    pending_line = number
                    pending_keyword = keyword^
                    pending_is_loop = False
                    pending_excluded = False
                    continue
                var id = module + ":" + String(number)
                var wrapped = _wrap_condition(line, keyword, id)
                if wrapped.text != line:
                    branches.append(number)
                    conditions.append(wrapped.conditions)
                    emitted = wrapped.text.copy()

        out += emitted + "\n"

    # An unterminated header is emitted verbatim rather than silently dropped.
    if pending != "":
        out += pending + "\n"

    # Loops running to the end of the file still need their trailing probe.
    _close_loops(out, closers, 0)

    return Instrumented(out^, lines^, branches^, conditions^)
