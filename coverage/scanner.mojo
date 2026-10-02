# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Decides which lines of a Mojo source file are executable statements.

This is the whole difficulty of the coverage tool. A probe can only be inserted
before a line that is a statement inside a function body, so everything else
must be recognized and skipped: blank lines, comments, docstrings, decorators,
imports, struct field declarations, `def`/`struct`/`trait` headers, trait
method bodies, block-continuation
keywords like `else:`, and any line that is the tail of a multi-line statement.

Scanning is stateful and line-ordered: feed every line of the file to
`Scanner.is_executable` in sequence, including the ones you expect to skip.
"""


def indent_of(line: String) -> Int:
    """Return the number of leading spaces on `line`."""
    var count = 0
    for cp in line.codepoint_slices():
        if cp == " ":
            count += 1
        else:
            break
    return count


def _count_quotes(line: String) -> Int:
    """Return how many `\\\"\\\"\\\"` markers appear in `line`."""
    var count = 0
    var run = 0
    for cp in line.codepoint_slices():
        if cp == '"':
            run += 1
            if run == 3:
                count += 1
                run = 0
        else:
            run = 0
    return count


def _characters(text: String) -> List[String]:
    """Return the codepoints used by the source lexer."""
    var chars = List[String]()
    for cp in text.codepoint_slices():
        chars.append(String(cp))
    return chars^


def _quote_delimiter(chars: List[String], start: Int) -> String:
    """Return the one- or three-character delimiter at an opening quote."""
    var quote = chars[start]
    if start + 2 < len(chars):
        if chars[start + 1] == quote and chars[start + 2] == quote:
            return quote * 3
    return quote.copy()


def _literal_end(chars: List[String], start: Int, delimiter: String) -> Int:
    """Find a closing delimiter after `start`, which is inside a literal."""
    var width = 1 if delimiter == '"' or delimiter == "'" else 3
    var quote = String('"') if delimiter.startswith('"') else String("'")
    var index = start
    while index < len(chars):
        if chars[index] == "\\":
            index += 2
            continue
        if chars[index] == quote:
            if width == 1:
                return index + 1
            if index + 2 < len(chars):
                if chars[index + 1] == quote and chars[index + 2] == quote:
                    return index + 3
        index += 1
    return -1


def _quoted_end(chars: List[String], start: Int) -> Int:
    """Return the position after a quoted literal, or -1 if unfinished.

    Single and triple delimiters both preserve escaped quote characters.
    """
    var delimiter = _quote_delimiter(chars, start)
    var width = 1 if delimiter == '"' or delimiter == "'" else 3
    return _literal_end(chars, start + width, delimiter)


def _bracket_delta(line: String, mut literal: String) -> Int:
    """Scan one physical line, retaining an unfinished literal's delimiter.

    The scanner carries bracket and quote state instead of rescanning a long
    continuation. A trailing backslash escapes the physical newline, so the
    next line still starts at an unescaped character inside the literal.
    """
    var chars = _characters(line)
    var depth = 0
    var index = 0
    while index < len(chars):
        if literal != "":
            var end = _literal_end(chars, index, literal)
            if end < 0:
                return depth
            literal = String("")
            index = end
            continue
        var cp = chars[index]
        if cp == '"' or cp == "'":
            literal = _quote_delimiter(chars, index)
            index += 1 if literal == '"' or literal == "'" else 3
            continue
        if cp == "#":
            break
        if cp == "(" or cp == "[" or cp == "{":
            depth += 1
        elif cp == ")" or cp == "]" or cp == "}":
            depth -= 1
        index += 1
    return depth


@fieldwise_init
struct _Scope(ImplicitlyCopyable):
    """One open `def`, `struct` or `trait` block, and its header's indent."""

    var indent: Int
    var is_def: Bool
    # A `trait` block, or a `def` inside one. The scanner currently excludes
    # all trait bodies. Default implementations need separate recognition;
    # issue #540 tracks that inherited gap. Buffer tracking follows the same
    # exclusion until that scanner work is complete.
    var is_trait: Bool
    var number: Int
    var started: Bool


struct Scanner(Movable):
    """Line-ordered state machine over one Mojo source file."""

    var _in_docstring: Bool
    var _open_brackets: Int
    var _literal: String
    # Innermost block last. A statement is executable only when the innermost
    # enclosing block is a `def`; a nested `def` must not be mistaken for the
    # end of the function containing it, which a single indent value cannot
    # express.
    var _scopes: List[_Scope]
    var _next_scope: Int
    var entry_indent: Int
    var entry_number: Int

    def __init__(out self):
        """Start a scan at the top of a file."""
        self._in_docstring = False
        self._open_brackets = 0
        self._literal = String("")
        self._scopes = List[_Scope]()
        self._next_scope = 0
        self.entry_indent = -1
        self.entry_number = -1

    def _close_scopes_at_or_above(mut self, indent: Int):
        """Drop every open block whose header is indented at least `indent`."""
        while len(self._scopes) > 0:
            if self._scopes[len(self._scopes) - 1].indent < indent:
                break
            _ = self._scopes.pop()

    def in_continuation(self) -> Bool:
        """Return True if the next line continues an unclosed statement."""
        return self._open_brackets > 0 or self._literal != ""

    def in_docstring(self) -> Bool:
        """Return True if the scan is currently inside a multi-line docstring.

        The instrumenter needs this to avoid mistaking prose for declarations
        when deciding where the probe import may be placed.
        """
        return self._in_docstring

    def _inside_function_body(self) -> Bool:
        """Return True if the innermost open block is a `def`."""
        if len(self._scopes) == 0:
            return False
        return self._scopes[len(self._scopes) - 1].is_def

    def _inside_trait(self) -> Bool:
        """Return True if any open block is a `trait`."""
        for scope in range(len(self._scopes)):
            if self._scopes[scope].is_trait:
                return True
        return False

    def function_number(self) -> Int:
        """Return the current function's local-buffer suffix, or -1.

        Returns:
            The current function's number, or -1 outside a function.
        """
        if not self._inside_function_body():
            return -1
        return self._scopes[len(self._scopes) - 1].number

    def is_executable(mut self, line: String) -> Bool:
        """Return True if a probe belongs immediately before `line`.

        Must be called for every line of the file, in order.
        """
        self.entry_indent = -1
        self.entry_number = -1
        var stripped = String(line.strip())

        # A continuation of a multi-line statement is never probed on its own.
        if self.in_continuation():
            self._open_brackets += _bracket_delta(line, self._literal)
            return False

        if self._in_docstring:
            if _count_quotes(line) > 0:
                self._in_docstring = False
            return False

        if stripped == "" or stripped.startswith("#"):
            return False

        if stripped.startswith('"""'):
            # An odd number of markers leaves the docstring open.
            if _count_quotes(stripped) == 1:
                self._in_docstring = True
            return False

        var indent = indent_of(line)

        # Dedenting to a header's own column or further left closes it.
        self._close_scopes_at_or_above(indent)

        if self._inside_function_body() and not self._inside_trait():
            var slot = len(self._scopes) - 1
            if not self._scopes[slot].started:
                self._scopes[slot].started = True
                self.entry_indent = indent
                self.entry_number = self._scopes[slot].number

        # Bracket depth must be tracked for *every* statement line, not only
        # the ones that get a probe. A skipped line can still open a bracket
        # that runs onto the next line — `comptime assert (` reflowed by the
        # formatter, a multi-line `elif`, a decorator with arguments — and
        # missing that makes the continuation look like a fresh statement,
        # which then gets a probe inserted into the middle of an expression.
        self._open_brackets += _bracket_delta(line, self._literal)

        if stripped.startswith("@"):
            return False

        if stripped.startswith("struct "):
            # Struct scope holds field declarations, not statements.
            self._scopes.append(_Scope(indent, False, False, -1, False))
            return False

        if stripped.startswith("trait "):
            # Preserve the current trait-body exclusion. This also excludes
            # default implementations, the separate gap tracked in #540.
            self._scopes.append(_Scope(indent, False, True, -1, False))
            return False

        if stripped.startswith("def ") or stripped.startswith("async def "):
            # A `def` inherits its enclosing trait-ness: the body of a trait
            # method is a declaration however much it looks like a function.
            # An `async def` is a function body like any other; the renderer
            # has one per rasterizer band.
            self._scopes.append(
                _Scope(
                    indent, True, self._inside_trait(), self._next_scope, False
                )
            )
            self._next_scope += 1
            return False

        if stripped.startswith("from ") or stripped.startswith("import "):
            return False

        # `comptime` introduces a compile-time constant, not a runtime step.
        if stripped.startswith("comptime "):
            return False

        # A probe cannot be inserted before a clause that continues a block.
        if (
            stripped.startswith("else:")
            or stripped.startswith("elif ")
            or stripped.startswith("except")
            or stripped.startswith("finally")
        ):
            return False

        # Anything left outside a function body is a declaration, not a step,
        # and so is everything inside a trait.
        if self._inside_trait():
            return False
        return self._inside_function_body()
