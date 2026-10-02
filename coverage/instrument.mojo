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

from coverage.scanner import Scanner, indent_of, _characters, _quoted_end

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
    var chars = _characters(line)
    var depth = 0
    var index = 0
    var found = -1
    while index < len(chars):
        var cp = chars[index]
        if cp == '"' or cp == "'":
            var end = _quoted_end(chars, index)
            if end < 0:
                break
            index = end
            continue
        if cp == "#":
            while index < len(chars) and chars[index] != "\n":
                index += 1
            continue
        if cp == "(" or cp == "[" or cp == "{":
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
    var chars = _characters(line)
    var out = String("")
    var index = 0
    while index < len(chars):
        var cp = chars[index]
        if cp == '"' or cp == "'":
            var end = _quoted_end(chars, index)
            if end < 0:
                # Trailing whitespace still belongs to an unfinished literal.
                return out + _substring(line, index, len(chars))
            out += _substring(line, index, end)
            index = end
            continue
        if cp == "#":
            while index < len(chars) and chars[index] != "\n":
                index += 1
            continue
        out += cp
        index += 1
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


def _token_boundary(ch: String) -> Bool:
    """Return True for whitespace or a delimiter next to a logical keyword."""
    return ch in " \t\r\n()[]{}"


def _separator_at(chars: List[String], index: Int) raises -> String:
    """Return a top-level expression keyword with surrounding spaces.

    Token boundaries accept tabs and adjacent parentheses, but not identifiers
    such as `android` or `original`. The caller keeps quoted text opaque.
    """
    if index > 0 and not _token_boundary(chars[index - 1]):
        return String("")
    for word in [String("and"), String("or"), String("if")]:
        var end = index + _codepoint_count(word)
        if _word_at(chars, index, word):
            if end == len(chars) or _token_boundary(chars[end]):
                return " " + word + " "
    return String("")


def split_conditions(condition: String) raises -> List[String]:
    """Split `condition` into operands and the operators between them.

    Returns alternating entries: operand, operator, operand, ... Only
    top-level `and`, `or` and `if` keywords split. Calls, indexing
    and string literals stay intact.
    The wrapper visits complete parenthesized groups separately.

    Args:
        condition: The decision's condition text.

    Returns:
        Alternating operand and operator segments.

    Raises:
        Error: Never; present to match the helpers it calls.
    """
    var chars = _characters(condition)
    var parts = List[String]()
    var current = String("")
    var depth = 0
    var index = 0

    while index < len(chars):
        var ch = chars[index]
        if ch == '"' or ch == "'":
            var end = _quoted_end(chars, index)
            if end < 0:
                end = len(chars)
            current += _substring(condition, index, end)
            index = end
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
                index += consumed - 2
                continue
        current += ch
        index += 1

    parts.append(String(current.strip()))
    return parts^


def _is_group(condition: String) raises -> Bool:
    """Return True when one parenthesis pair encloses the entire expression.

    `(a or b) == c` is one comparison, not a Boolean group. Parentheses in
    calls, subscripts and quoted strings must not change that classification.
    """
    if not condition.startswith("("):
        return False
    var chars = _characters(condition)
    var depth = 0
    var index = 0
    while index < len(chars):
        var cp = chars[index]
        if cp == '"' or cp == "'":
            var end = _quoted_end(chars, index)
            if end < 0:
                return False
            index = end
            continue
        if cp == "(" or cp == "[" or cp == "{":
            depth += 1
        elif cp == ")" or cp == "]" or cp == "}":
            depth -= 1
            if depth == 0:
                return cp == ")" and index == len(chars) - 1
        index += 1
    return False


def _wrap_leaf(
    condition: String, id: String, mut count: Int, frame: String, stem: String
) -> String:
    """Wrap one opaque expression without changing its evaluation."""
    var result = (
        stem
        + "leaf("
        + condition
        + ", "
        + frame
        + ', "'
        + id
        + "."
        + String(count)
        + '", '
        + String(count)
        + ")"
    )
    count += 1
    return result^


def _wrap_leaves(
    condition: String, id: String, mut count: Int, frame: String, stem: String
) raises -> String:
    """Wrap Boolean leaves, retaining every logical operator and group.

    Only the decision's Boolean grammar is traversed. An atomic call, index,
    comparison or arithmetic expression stays intact, even if it contains a
    Boolean expression used as an argument or value. No leaf is duplicated.
    """
    var parts = split_conditions(condition)
    # Conditional expressions bind less tightly than Boolean operators.
    # Keep them opaque, including any leading `not`, rather than change which
    # arm runs or move a logical operator across the conditional expression.
    for index in range(1, len(parts), 2):
        if parts[index] == " if ":
            return _wrap_leaf(String(condition.strip()), id, count, frame, stem)
    if len(parts) > 1:
        var out = String("")
        for index in range(len(parts)):
            if index % 2 == 1:
                out += parts[index]
            else:
                out += _wrap_leaves(parts[index], id, count, frame, stem)
        return out^
    var text = parts[0].copy()
    if _is_group(text):
        var inner = _substring(text, 1, _codepoint_count(text) - 1)
        return "(" + _wrap_leaves(inner, id, count, frame, stem) + ")"
    var chars = _characters(text)
    if len(chars) > 3 and _word_at(chars, 0, String("not")):
        if _token_boundary(chars[3]):
            var inner = _substring(text, 3, len(chars))
            return "not " + _wrap_leaves(inner, id, count, frame, stem)
    return _wrap_leaf(text, id, count, frame, stem)


struct Wrapped(Movable):
    """A rewritten decision header and how many conditions it now reports."""

    var text: String
    var conditions: Int

    def __init__(out self, var text: String, conditions: Int):
        """Store the rewritten header text and its condition count."""
        self.text = text^
        self.conditions = conditions


def _wrap_condition(
    line: String,
    keyword: String,
    id: String,
    frame: String = "_cov_eval_state0",
    stem: String = "_cov_eval_",
    branch: String = "_cov_branch",
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
        frame: The private operand buffer in this function invocation.
        stem: An evaluation-helper prefix absent from the source.
        branch: A branch-helper alias absent from the source.

    Returns:
        The rewritten line, unchanged if it holds no usable condition.

    Raises:
        Error: If the complete UTF-8 evaluation record would exceed 512 bytes.
    """
    var colon = _statement_colon(line)
    if colon < 0:
        return Wrapped(String(line), 0)

    var indent = indent_of(line)
    var condition_start = indent + _codepoint_count(keyword)
    var condition = String(
        _strip_comment(_substring(line, condition_start, colon)).strip()
    )
    if condition == "":
        return Wrapped(String(line), 0)
    # `while True:` is a loop, not a decision: a literal condition has exactly
    # one outcome, so reporting the other as "never evaluated" is noise.
    if condition == "True" or condition == "False":
        return Wrapped(String(line), 0)

    var conditions = 0
    var rebuilt = _wrap_leaves(condition, id, conditions, frame, stem)
    # The decision already measures a single leaf, including a negated leaf.
    # Keep its original spelling, including redundant grouping and whitespace.
    if conditions == 1:
        rebuilt = condition.copy()
        conditions = 0

    # Everything from the colon onward is kept so trailing comments survive.
    var tail = _substring(line, colon, _codepoint_count(line))
    if conditions == 0:
        return Wrapped(
            " " * indent
            + keyword
            + branch
            + '("'
            + id
            + '", '
            + rebuilt
            + ")"
            + tail,
            0,
        )
    # A pipe guarantees indivisible writes only through POSIX PIPE_BUF's
    # portable minimum. Refuse unsupported widths instead of losing probes.
    if id.byte_length() + conditions + 14 > 512:
        raise Error(
            "Coverage evaluation exceeds the 512-byte atomic record limit: "
            + id
        )
    return Wrapped(
        " " * indent
        + keyword
        + stem
        + "begin("
        + frame
        + ", "
        + String(conditions)
        + ") and "
        + stem
        + "finish("
        + rebuilt
        + ", "
        + frame
        + ', "'
        + id
        + '")'
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
        or stripped.startswith("trait ")
        or stripped.startswith("@")
    )


def _close_loops(
    mut out: String, mut closers: List[_LoopCloser], indent: Int, branch: String
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
            + "_ = "
            + branch
            + '("'
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
    branch: String,
    loop_stem: String,
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
        branch: A branch-helper alias absent from the source.
        loop_stem: A loop-counter prefix absent from the source.
    """
    var flag = loop_stem + String(number)
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
    out += body_indent + "_ = " + branch + '("' + id + '", True)\n'
    closers.append(_LoopCloser(indent, id, flag))


def _fresh_name(var name: String, source: String) -> String:
    """Return a generated name or prefix absent from the entire source.

    Checking the full text also protects nested scopes, parameters, imported
    names, generic callbacks, and longer identifiers sharing the prefix.
    """
    while name in source:
        name += "_"
    return name^


def instrument(source: String, module: String) raises -> Instrumented:
    """Return `source` rewritten with line probes for the module named `module`.

    Args:
        source: The original file's full text.
        module: Name embedded in probe IDs, at most 480 UTF-8 bytes.

    Returns:
        The instrumented text, the executable line numbers, and the lines
        holding decisions whose outcomes are tracked.

    Raises:
        Error: If the module ID exceeds 480 UTF-8 bytes, or a complete
            evaluation record would exceed 512 bytes including its newline.
    """
    if module.byte_length() + 32 > 512:
        raise Error(
            "Coverage module ID exceeds the 512-byte atomic record limit"
        )
    var scanner = Scanner()
    var stem = _fresh_name(String("_cov_eval_"), source)
    var hit = _fresh_name(String("_cov_hit"), source)
    var branch = _fresh_name(String("_cov_branch"), source)
    var loop_stem = _fresh_name(String("_cov_loop_"), source)
    var declarations = List[String]()
    var used_frames = List[Int]()
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
    var pending_frame = -1
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
        if not import_emitted and not was_prose and not was_continuation:
            if _opens_top_level_block(line):
                out += (
                    "from coverage.runtime import hit as "
                    + hit
                    + ", branch as "
                    + branch
                    + ", begin as "
                    + stem
                    + "begin, leaf as "
                    + stem
                    + "leaf, finish as "
                    + stem
                    + "finish, buffer as "
                    + stem
                    + "buffer\n"
                )
                import_emitted = True

        if scanner.entry_indent >= 0:
            var declaration = (
                " " * scanner.entry_indent
                + "var "
                + stem
                + "state"
                + String(scanner.entry_number)
                + " = "
                + stem
                + "buffer()\n"
            )
            while len(declarations) <= scanner.entry_number:
                declarations.append(String(""))
            declarations[scanner.entry_number] = declaration.copy()
            out += declaration

        # Still accumulating a header split over several physical lines.
        if pending != "":
            pending_excluded = pending_excluded or PRAGMA_NO_BRANCH in line
            # A triple-quoted literal can contain newlines, comments and
            # indentation. Keep those bytes until the whole header is parsed.
            if (
                '"""' in pending
                or "'''" in pending
                or '"""' in line
                or "'''" in line
            ):
                pending += "\n" + line
            else:
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
                        branch,
                        loop_stem,
                    )
                else:
                    var id = module + ":" + String(pending_line)
                    var joined = _wrap_condition(
                        pending,
                        pending_keyword,
                        id,
                        stem + "state" + String(pending_frame),
                        stem,
                        branch,
                    )
                    if joined.text != pending:
                        branches.append(pending_line)
                        conditions.append(joined.conditions)
                        if joined.conditions > 0:
                            used_frames.append(pending_frame)
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
            _close_loops(out, closers, indent_of(line), branch)

        if executable:
            lines.append(number)
            out += " " * indent_of(line)
            out += hit + '("' + module + ":" + String(number) + '")\n'

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
                    out,
                    branches,
                    conditions,
                    closers,
                    line,
                    number,
                    module,
                    branch,
                    loop_stem,
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
                    pending_frame = scanner.function_number()
                    pending_is_loop = False
                    pending_excluded = False
                    continue
                var id = module + ":" + String(number)
                var wrapped = _wrap_condition(
                    line,
                    keyword,
                    id,
                    stem + "state" + String(scanner.function_number()),
                    stem,
                    branch,
                )
                if wrapped.text != line:
                    branches.append(number)
                    conditions.append(wrapped.conditions)
                    if wrapped.conditions > 0:
                        used_frames.append(scanner.function_number())
                    emitted = wrapped.text.copy()

        out += emitted + "\n"

    # An unterminated header is emitted verbatim rather than silently dropped.
    if pending != "":
        out += pending + "\n"

    # Loops running to the end of the file still need their trailing probe.
    _close_loops(out, closers, 0, branch)

    # Only compound decisions need a buffer. Unused declarations disappear.
    for frame in range(len(declarations)):
        var used = False
        for candidate in used_frames:
            if frame == candidate:
                used = True
        if not used and declarations[frame] != "":
            out = out.replace(declarations[frame], "")
    return Instrumented(out^, lines^, branches^, conditions^)
