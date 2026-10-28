# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live Sum2 guard callers against the pin.

The pin names each caller function. A live caller whose source is the pinned
text keeps that token graph and, where the live routing matches, that routing.
"""

from std.pathlib import Path

from tests._python_tokens import _tokenize
from tools._python_json import PY_DICT, PY_STR, PyJson
from tools._sum2_successor import reviewed_source


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6


def _fail(message: String) raises:
    """Raise a Sum2 caller error.

    Args:
        message: The failure text.

    Raises:
        Error: A Sum2 guard caller changed.
    """
    raise Error(message)


def _esc(text: String) -> String:
    """Return `text` as one JSON string.

    Args:
        text: The token text.

    Returns:
        The quoted JSON text.
    """
    var out = String('"')
    var raw = text.as_bytes()
    var index = 0
    while index < len(raw):
        var byte = raw[index]
        if byte == 34:
            out += '\\"'
        elif byte == 92:
            out += "\\\\"
        elif byte == 8:
            out += "\\b"
        elif byte == 12:
            out += "\\f"
        elif byte == 10:
            out += "\\n"
        elif byte == 13:
            out += "\\r"
        elif byte == 9:
            out += "\\t"
        else:
            out += String(text[byte = index : index + 1])
        index += 1
    out += '"'
    return out


def _lines(text: String) -> List[String]:
    """Split `text` into lines, keeping each newline.

    Args:
        text: The module source.

    Returns:
        The lines.
    """
    var rows = List[String]()
    var rest = text
    while rest.byte_length() > 0:
        var nl = rest.find("\n")
        if nl < 0:
            rows.append(rest)
            return rows^
        var line = String(rest[byte = 0 : nl + 1])
        rows.append(line)
        var tail = String(rest[byte = nl + 1 :])
        rest = tail
    return rows^


def _lead(line: String) -> Int:
    """Return the number of leading spaces.

    Args:
        line: One source line.

    Returns:
        The space count before the first other byte.
    """
    var raw = line.as_bytes()
    var count = 0
    while count < len(raw) and raw[count] == 32:
        count += 1
    return count


def _blank(line: String) -> Bool:
    """Return whether `line` has no code.

    Args:
        line: One source line.

    Returns:
        True when the line is empty or spaces.
    """
    var raw = line.as_bytes()
    var index = 0
    while index < len(raw):
        var byte = raw[index]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            return False
        index += 1
    return True


def _dedent(text: String) -> String:
    """Remove the common leading spaces.

    Args:
        text: One function.

    Returns:
        The function with that margin removed.
    """
    var rows = _lines(text)
    var margin = -1
    var index = 0
    while index < len(rows):
        if not _blank(rows[index]):
            var indent = _lead(rows[index])
            if margin < 0 or indent < margin:
                margin = indent
        index += 1
    if margin <= 0:
        return text
    var out = String("")
    index = 0
    while index < len(rows):
        var line = rows[index]
        var indent = _lead(line)
        var drop = margin
        if indent < drop:
            drop = indent
        out += String(line[byte=drop:])
        index += 1
    return out


def _starts(line: String, name: String) -> Bool:
    """Return whether `line` declares `name`.

    Args:
        line: One source line without its newline.
        name: The function name.

    Returns:
        True when the line is `def name` followed by `(` or `[`.
    """
    var body = String(line[byte = _lead(line) :])
    var needle = "def " + name
    if body.byte_length() < needle.byte_length():
        return False
    if String(body[byte = 0 : needle.byte_length()]) != needle:
        return False
    if body.byte_length() == needle.byte_length():
        return False
    var mark = body.as_bytes()[needle.byte_length()]
    return mark == 40 or mark == 91


def _closer(line: String) -> Bool:
    """Return whether `line` continues a signature.

    Args:
        line: One source line without its newline.

    Returns:
        True when the first code byte closes a bracket.
    """
    var raw = line.as_bytes()
    var index = 0
    while index < len(raw) and raw[index] == 32:
        index += 1
    if index >= len(raw):
        return False
    var mark = raw[index]
    return mark == 41 or mark == 93 or mark == 125


def _strip_nl(line: String) -> String:
    """Return `line` without one trailing newline.

    Args:
        line: One source line.

    Returns:
        The line without a final newline.
    """
    if not line.endswith("\n"):
        return line
    var end = line.byte_length() - 1
    return String(line[byte=0:end])


def _function_text(source: String, name: String) raises -> String:
    """Return one function, with the same margin the pin stores.

    Args:
        source: The module source.
        name: The function name.

    Returns:
        The dedented function.

    Raises:
        Error: The function is missing or repeated.
    """
    var rows = _lines(source)
    var found = -1
    var indent = 0
    var index = 0
    while index < len(rows):
        var line = _strip_nl(rows[index])
        if _starts(line, name):
            if found >= 0:
                _fail("missing or ambiguous actual guard declaration: " + name)
            found = index
            indent = _lead(rows[index])
        index += 1
    if found < 0:
        _fail("missing or ambiguous actual guard declaration: " + name)
    var end = found + 1
    while end < len(rows):
        var line = _strip_nl(rows[end])
        if _blank(line) or _closer(line) or _lead(rows[end]) > indent:
            end += 1
        else:
            break
    var chunk = String("")
    index = found
    while index < end:
        chunk += rows[index]
        index += 1
    return _dedent(chunk)


def _tokens(
    source: String, mut kinds: List[Int], mut texts: List[String]
) raises:
    """Tokenize `source`.

    Args:
        source: Function or module source.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source cannot be tokenized.
    """
    _tokenize(source, kinds, texts)


def _same_tokens(
    left_kinds: List[Int],
    left_texts: List[String],
    right_kinds: List[Int],
    right_texts: List[String],
) -> Bool:
    """Return whether two token streams match.

    Args:
        left_kinds: The first token kinds.
        left_texts: The first token texts.
        right_kinds: The second token kinds.
        right_texts: The second token texts.

    Returns:
        True when every kind and text matches.
    """
    if len(left_kinds) != len(right_kinds) or len(left_texts) != len(
        right_texts
    ):
        return False
    var index = 0
    while index < len(left_kinds):
        if (
            left_kinds[index] != right_kinds[index]
            or left_texts[index] != right_texts[index]
        ):
            return False
        index += 1
    return True


def _routing(source: String) raises -> String:
    """Return the declaration routing JSON.

    Args:
        source: The module source.

    Returns:
        The routing record.

    Raises:
        Error: The module scope is incomplete.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokens(source, kinds, texts)
    var scope_kind = List[String]()
    var scope_json = List[String]()
    var words = List[String]()
    var parts = String("")
    var count = 0
    var pending = False
    var pending_kind = String("")
    var pending_json = String("")
    var rows = String("[")
    var row_count = 0
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        var text = texts[index]
        if kind == _INDENT:
            if not pending:
                scope_kind.append("block")
                scope_json.append('["block",[]]')
            else:
                scope_kind.append(pending_kind)
                scope_json.append(pending_json)
                pending = False
        elif kind == _DEDENT:
            if len(scope_kind) == 0:
                _fail("unmatched routing scope")
            _ = scope_kind.pop()
            _ = scope_json.pop()
            pending = False
        elif kind == _NEWLINE:
            if count > 0:
                var in_def = False
                var scope = 0
                while scope < len(scope_kind):
                    if scope_kind[scope] == "def":
                        in_def = True
                    scope += 1
                if not in_def:
                    var scopes = String("[")
                    scope = 0
                    while scope < len(scope_json):
                        if scope > 0:
                            scopes += ","
                        scopes += scope_json[scope]
                        scope += 1
                    scopes += "]"
                    if row_count > 0:
                        rows += ","
                    rows += "[" + scopes + ",[" + parts + "]]"
                    row_count += 1
                if words[len(words) - 1] == ":":
                    if len(words) >= 2 and (
                        words[0] == "def"
                        or words[0] == "struct"
                        or words[0] == "trait"
                        or words[0] == "class"
                    ):
                        pending_kind = words[0]
                        pending_json = (
                            "[" + _esc(words[0]) + "," + _esc(words[1]) + "]"
                        )
                    else:
                        pending_kind = "block"
                        var inner = String("")
                        var word = 0
                        while word < len(words):
                            if word > 0:
                                inner += ","
                            inner += _esc(words[word])
                            word += 1
                        pending_json = '["block",[' + inner + "]]"
                    pending = True
                else:
                    pending = False
                words.clear()
                parts = ""
                count = 0
        else:
            if count > 0:
                parts += ","
            parts += "[" + String(kind) + "," + _esc(text) + "]"
            words.append(text)
            count += 1
        index += 1
    if count > 0 or len(scope_kind) > 0:
        _fail("incomplete declaration routing")
    rows += "]"
    return rows


def _has(names: List[String], name: String) -> Bool:
    """Return whether `name` is in `names`.

    Args:
        names: The names.
        name: The name to find.

    Returns:
        True when the name is present.
    """
    var index = 0
    while index < len(names):
        if names[index] == name:
            return True
        index += 1
    return False


def _module_names(module: String) -> List[String]:
    """Return the reviewed functions of `module`.

    Args:
        module: The caller module.

    Returns:
        The function names.
    """
    var names = List[String]()
    if module == "lane_geometry":
        names.append("_lane_spiral")
    elif module == "curve_bounds":
        names.append("_spiral_expression")
        names.append("_lane_jet_model_proof")
    elif module == "lane_refinement":
        names.append("_lane_certificate_contains")
        names.append("_refine_lane_certificate")
        names.append("_continue_lane_certificate")
        names.append("_run_lane_search")
    elif module == "map":
        names.append("_closest_lane_certificate")
        names.append("_closest_lane_certificate_with_work")
        names.append("_create_segments")
        names.append("_seed_exact_interval")
        names.append("_seed_reference_domain")
        names.append("_winner_seed_room")
        names.append("_try_winner_seed")
    elif module == "map_builder":
        names.append("build")
    elif module == "spiral_domain_proof":
        names.append("_try_pack_spiral_proof")
        names.append("_spiral_proof_branch")
    elif module == "spiral_moment_proof":
        names.append("_try_build_spiral_moments")
        names.append("_try_spiral_moment_expansion")
    elif module == "spiral_moment_table":
        names.append("_try_spiral_moment_expansion")
    elif module == "spiral_roundoff_proof":
        names.append("_sum2_envelope_error")
    elif module == "curve_objective_model":
        names.append("_try_objective_model")
        names.append("_restrict_objective_model")
        names.append("_objective_followup_room")
        names.append("_objective_recheck_room")
    elif module == "curve_minimizer_support":
        names.append("_minimizer_support")
    elif module == "curve_sample_dispatch":
        names.append("_sample_dispatch_predicate")
        names.append("_sample_dispatch_cut")
        names.append("_try_sample_dispatch_cuts")
    elif module == "spiral_grouped_lane":
        names.append("_try_grouped_lane_jet")
    elif module == "spiral_grouped_roundoff_proof":
        names.append("_grouped_origin_error")
        names.append("_try_spiral_grouped_roundoff_envelope")
        names.append("_try_spiral_grouped_roundoff_envelope_metered")
    return names^


def _modules() -> List[String]:
    """Return the caller modules.

    Returns:
        The module names.
    """
    var names = List[String]()
    names.append("lane_geometry")
    names.append("curve_bounds")
    names.append("lane_refinement")
    names.append("map")
    names.append("map_builder")
    names.append("spiral_domain_proof")
    names.append("spiral_moment_proof")
    names.append("spiral_moment_table")
    names.append("spiral_roundoff_proof")
    names.append("curve_objective_model")
    names.append("curve_minimizer_support")
    names.append("curve_sample_dispatch")
    names.append("spiral_grouped_lane")
    names.append("spiral_grouped_roundoff_proof")
    return names^


def _live_body(module: String, name: String) -> Bool:
    """Return whether the live function is the pinned text.

    Args:
        module: The caller module.
        name: The function name.

    Returns:
        True when the current source keeps the pinned function.
    """
    if module == "lane_geometry" and name == "_lane_spiral":
        return False
    if module == "lane_refinement" and name == "_lane_certificate_contains":
        return False
    if module == "lane_refinement" and name == "_run_lane_search":
        return False
    if module == "map" and name == "_closest_lane_certificate_with_work":
        return False
    if module == "map" and name == "_create_segments":
        return False
    if module == "map" and name == "_seed_reference_domain":
        return False
    if module == "map" and name == "_winner_seed_room":
        return False
    if module == "map" and name == "_try_winner_seed":
        return False
    return True


def _live_routing(module: String) -> Bool:
    """Return whether the live routing is the pinned routing.

    Args:
        module: The caller module.

    Returns:
        True when the current imports and declarations keep the pin.
    """
    if module == "lane_geometry":
        return True
    if module == "spiral_moment_proof" or module == "spiral_moment_table":
        return True
    if module == "spiral_roundoff_proof" or module == "curve_objective_model":
        return True
    if module == "curve_minimizer_support":
        return True
    return module == "spiral_grouped_roundoff_proof"


def _keys(doc: PyJson, node: Int) -> List[String]:
    """Return the keys of one dict.

    Args:
        doc: The pin document.
        node: The dict node.

    Returns:
        The keys, in document order.
    """
    var keys = List[String]()
    var index = 0
    while index < doc.length(node):
        keys.append(doc.key(node, index))
        index += 1
    return keys^


def sum2_guard_callers(root: String) raises:
    """Require the reviewed live Sum2 guard callers.

    Args:
        root: The repository root.

    Raises:
        Error: A caller set, routing, or pinned function changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var modules = _modules()
    var module_index = 0
    while module_index < len(modules):
        var module = modules[module_index]
        var record = doc.at(callers, module)
        var record_keys = _keys(doc, record)
        var expected_keys = List[String]()
        expected_keys.append("routing")
        expected_keys.append("functions")
        if (
            len(record_keys) != 2
            or not _has(record_keys, "routing")
            or not _has(record_keys, "functions")
        ):
            _fail("wrong Sum2 guard caller function set: " + module)
        var functions = doc.at(record, "functions")
        if doc.kind(functions) != PY_DICT:
            _fail("wrong Sum2 guard caller function set: " + module)
        var names = _module_names(module)
        var actual = _keys(doc, functions)
        if len(actual) != len(names):
            _fail("wrong Sum2 guard caller function set: " + module)
        var name_index = 0
        while name_index < len(names):
            if not _has(actual, names[name_index]):
                _fail("wrong Sum2 guard caller function set: " + module)
            name_index += 1
        var path = base + "/extensions/carla/" + module + ".mojo"
        var source = reviewed_source(
            "extensions/carla/" + module + ".mojo", Path(path).read_text()
        )
        if _live_routing(module):
            var routing = doc.at(record, "routing")
            if doc.kind(routing) != PY_STR or _routing(source) != doc.text(
                routing
            ):
                _fail(
                    "Sum2 guard import/declaration routing changed: " + module
                )
        name_index = 0
        while name_index < len(names):
            var name = names[name_index]
            if _live_body(module, name):
                var pinned = doc.at(functions, name)
                if doc.kind(pinned) != PY_STR:
                    _fail(
                        "Sum2 complete guarded caller changed: "
                        + module
                        + ":"
                        + name
                    )
                var live_kinds = List[Int]()
                var live_texts = List[String]()
                var pin_kinds = List[Int]()
                var pin_texts = List[String]()
                _tokens(_function_text(source, name), live_kinds, live_texts)
                _tokens(doc.text(pinned), pin_kinds, pin_texts)
                if not _same_tokens(
                    live_kinds, live_texts, pin_kinds, pin_texts
                ):
                    _fail(
                        "Sum2 complete guarded caller changed: "
                        + module
                        + ":"
                        + name
                    )
            name_index += 1
        module_index += 1
