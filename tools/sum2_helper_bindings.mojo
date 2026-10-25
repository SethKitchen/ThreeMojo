# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed Sum2 helper bindings.

Each consumer imports the reviewed helpers directly. A wildcard, an alias,
a declaration, an assignment, a parameter, or an exception binding that
replaces one of those helpers is refused.
"""

from tests._python_tokens import _tokenize


comptime _NAME = 1
comptime _NEWLINE = 4
comptime _OP = 55


def _fail(message: String) raises:
    """Raise a Sum2 binding error.

    Args:
        message: The failure text.

    Raises:
        Error: A reviewed helper binding changed.
    """
    raise Error(message)


def _load(source: String, mut kinds: List[Int], mut texts: List[String]) raises:
    """Tokenize `source`.

    Args:
        source: Module source.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source cannot be tokenized.
    """
    _tokenize(source, kinds, texts)


def _join(names: List[String]) -> String:
    """Join import names in source order.

    Args:
        names: The imported names.

    Returns:
        The names separated by commas.
    """
    var out = String("")
    var index = 0
    while index < len(names):
        if index > 0:
            out += ","
        out += names[index]
        index += 1
    return out


def _imports(
    kinds: List[Int],
    texts: List[String],
    mut modules: List[String],
    mut names: List[String],
    mut aliases: List[String],
    mut from_import: List[Int],
) raises:
    """Record every import statement.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        modules: One module path per import, appended by this call.
        names: Comma-joined names per import, appended by this call.
        aliases: Comma-joined aliases per import, appended by this call.
        from_import: 1 for `from` imports and 0 for plain imports.

    Raises:
        Error: An import cannot be read.
    """
    var index = 0
    while index < len(kinds):
        if kinds[index] == _NAME and texts[index] == "from":
            index += 1
            var module = String("")
            while index < len(kinds) and texts[index] != "import":
                module += texts[index]
                index += 1
            if index >= len(kinds):
                _fail("Sum2 direct helper import changed: unreadable")
            index += 1
            var got_names = List[String]()
            var got_aliases = List[String]()
            if index < len(kinds) and texts[index] == "(":
                index += 1
            while index < len(kinds):
                if texts[index] == ")" or kinds[index] == _NEWLINE:
                    break
                if texts[index] == ",":
                    index += 1
                    continue
                var name = texts[index]
                index += 1
                var alias = String("")
                if index < len(kinds) and texts[index] == "as":
                    index += 1
                    if index >= len(kinds):
                        _fail("Sum2 direct helper import changed: unreadable")
                    alias = texts[index]
                    index += 1
                got_names.append(name)
                got_aliases.append(alias)
            if index < len(kinds) and texts[index] == ")":
                index += 1
            modules.append(module)
            names.append(_join(got_names))
            aliases.append(_join(got_aliases))
            from_import.append(1)
            continue
        if kinds[index] == _NAME and texts[index] == "import":
            index += 1
            var module = String("")
            while (
                index < len(kinds)
                and texts[index] != "as"
                and kinds[index] != _NEWLINE
                and texts[index] != ","
            ):
                module += texts[index]
                index += 1
            var alias = String("")
            if index < len(kinds) and texts[index] == "as":
                index += 1
                alias = texts[index]
                index += 1
            var bound = alias
            if bound == "":
                var dot = module.find(".")
                if dot < 0:
                    bound = module
                else:
                    bound = String(module[byte=0:dot])
            modules.append(module)
            names.append(bound)
            aliases.append(alias)
            from_import.append(0)
            continue
        index += 1


def _one_from(
    modules: List[String],
    names: List[String],
    aliases: List[String],
    from_import: List[Int],
    module: String,
    expected: String,
    label: String,
) raises:
    """Require one direct import of `expected` from `module`.

    Args:
        modules: The import modules.
        names: The comma-joined names.
        aliases: The comma-joined aliases.
        from_import: 1 when the statement is a `from` import.
        module: The required module path.
        expected: The required names, comma-joined.
        label: The consumer name in the failure text.

    Raises:
        Error: The import is missing, repeated, aliased, or reordered.
    """
    var found = 0
    var index = 0
    while index < len(modules):
        if from_import[index] == 1 and modules[index] == module:
            found += 1
            if names[index] != expected or not _blank_aliases_text(
                aliases[index]
            ):
                _fail("Sum2 direct helper import changed: " + label)
        index += 1
    if found != 1:
        _fail("Sum2 direct helper import changed: " + label)


def _blank_aliases_text(aliases: String) -> Bool:
    """Return whether a joined alias list is empty.

    Args:
        aliases: Comma-joined aliases.

    Returns:
        True when every alias slot is empty.
    """
    if aliases == "":
        return True
    var index = 0
    while index < aliases.byte_length():
        if String(aliases[byte = index : index + 1]) != ",":
            return False
        index += 1
    return True


def _binds(names: String, aliases: String, helper: String) -> Bool:
    """Return whether one import binds `helper`.

    Args:
        names: Comma-joined names.
        aliases: Comma-joined aliases.
        helper: The reviewed helper.

    Returns:
        True when a name or an alias is `helper`.
    """
    var name_at = 0
    var alias_at = 0
    while name_at <= names.byte_length():
        var name_end = names.find(",", name_at)
        if name_end < 0:
            name_end = names.byte_length()
        var alias_end = aliases.find(",", alias_at)
        if alias_end < 0:
            alias_end = aliases.byte_length()
        var name = String(names[byte=name_at:name_end])
        var alias = String("")
        if aliases != "":
            alias = String(aliases[byte=alias_at:alias_end])
        var bound = name
        if alias != "":
            bound = alias
        if name == "*" or bound == helper or name == helper:
            return True
        if name_end == names.byte_length():
            return False
        name_at = name_end + 1
        if aliases != "":
            alias_at = alias_end + 1
    return False


def _shadows(
    kinds: List[Int],
    texts: List[String],
    modules: List[String],
    names: List[String],
    aliases: List[String],
    from_import: List[Int],
    helper: String,
    allowed_module: String,
    allow_definition: Bool,
) raises:
    """Reject a binding that could replace `helper`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        modules: The import modules.
        names: The comma-joined names.
        aliases: The comma-joined aliases.
        from_import: 1 when the statement is a `from` import.
        helper: The reviewed helper.
        allowed_module: The one module that may import `helper`.
        allow_definition: True when one function definition is the helper.

    Raises:
        Error: A wildcard, alias, declaration, assignment, parameter, or
        exception binding shadows the helper.
    """
    var index = 0
    while index < len(modules):
        if _binds(names[index], aliases[index], helper):
            if names[index].find("*") >= 0:
                _fail("wildcard import can shadow reviewed helper: " + helper)
            if from_import[index] == 0:
                _fail("reviewed helper module alias shadows: " + helper)
            if modules[index] != allowed_module:
                _fail("reviewed helper import alias shadows: " + helper)
        index += 1
    var definitions = 0
    index = 0
    while index + 1 < len(kinds):
        if (
            kinds[index] == _NAME
            and (texts[index] == "def" or texts[index] == "struct")
            and texts[index + 1] == helper
        ):
            definitions += 1
        index += 1
    if allow_definition:
        if definitions != 1:
            _fail("reviewed helper declaration shadows: " + helper)
    elif definitions != 0:
        _fail("reviewed helper declaration shadows: " + helper)
    index = 0
    while index + 1 < len(kinds):
        if (
            texts[index] == helper
            and kinds[index + 1] == _OP
            and (
                texts[index + 1] == "="
                or texts[index + 1] == "+="
                or texts[index + 1] == "-="
            )
        ):
            _fail("reviewed helper assignment shadows: " + helper)
        if texts[index] == "for" and texts[index + 1] == helper:
            _fail("reviewed helper assignment shadows: " + helper)
        if texts[index] == "except":
            var cursor = index + 1
            while (
                cursor + 1 < len(kinds)
                and texts[cursor] != "as"
                and kinds[cursor] != _NEWLINE
            ):
                cursor += 1
            if (
                cursor + 1 < len(kinds)
                and texts[cursor] == "as"
                and texts[cursor + 1] == helper
            ):
                _fail("reviewed helper exception binding shadows: " + helper)
        if texts[index] == "def" and index + 1 < len(kinds):
            var cursor = index + 2
            if cursor < len(kinds) and texts[cursor] == "[":
                var brackets = 1
                cursor += 1
                while cursor < len(kinds) and brackets > 0:
                    if texts[cursor] == "[":
                        brackets += 1
                    elif texts[cursor] == "]":
                        brackets -= 1
                    cursor += 1
            if cursor < len(kinds) and texts[cursor] == "(":
                cursor += 1
                var parens = 1
                while cursor < len(kinds) and parens > 0:
                    if texts[cursor] == "(":
                        parens += 1
                    elif texts[cursor] == ")":
                        parens -= 1
                    elif texts[cursor] == helper and parens == 1:
                        var previous = texts[cursor - 1]
                        if (
                            previous == "("
                            or previous == ","
                            or previous == "mut"
                            or previous == "var"
                        ):
                            _fail(
                                "reviewed helper parameter shadows: " + helper
                            )
                    cursor += 1
        index += 1


def _half_import(
    modules: List[String],
    names: List[String],
    aliases: List[String],
    from_import: List[Int],
) raises:
    """Require one direct `_stored_half` import.

    Args:
        modules: The import modules.
        names: The comma-joined names.
        aliases: The comma-joined aliases.
        from_import: 1 when the statement is a `from` import.

    Raises:
        Error: The stored-half import changed.
    """
    var found = 0
    var index = 0
    while index < len(modules):
        if from_import[index] == 1 and _binds(
            names[index], aliases[index], "_stored_half"
        ):
            found += 1
            if modules[
                index
            ] != "extensions.carla.curve_interval" or not _half_direct(
                names[index], aliases[index]
            ):
                _fail("stored-half direct import changed")
        index += 1
    if found != 1:
        _fail("stored-half direct import changed")


def _half_direct(names: String, aliases: String) -> Bool:
    """Return whether `_stored_half` is imported under its own name.

    Args:
        names: Comma-joined names.
        aliases: Comma-joined aliases.

    Returns:
        True when the helper has no alias.
    """
    var name_at = 0
    var alias_at = 0
    while name_at <= names.byte_length():
        var name_end = names.find(",", name_at)
        if name_end < 0:
            name_end = names.byte_length()
        var alias_end = aliases.byte_length()
        if aliases != "":
            alias_end = aliases.find(",", alias_at)
            if alias_end < 0:
                alias_end = aliases.byte_length()
        var name = String(names[byte=name_at:name_end])
        var alias = String("")
        if aliases != "":
            alias = String(aliases[byte=alias_at:alias_end])
        if name == "_stored_half" or alias == "_stored_half":
            return name == "_stored_half" and alias == ""
        if name_end == names.byte_length():
            return False
        name_at = name_end + 1
        if aliases != "":
            alias_at = alias_end + 1
    return False


def _check_consumer(
    source: String, module: String, expected: String, label: String
) raises:
    """Require one consumer's Sum2 import and reject shadows.

    Args:
        source: The consumer module.
        module: The required Sum2 module path.
        expected: The required helper names, comma-joined.
        label: The consumer name in the failure text.

    Raises:
        Error: The import changed or a helper is shadowed.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    var modules = List[String]()
    var names = List[String]()
    var aliases = List[String]()
    var from_import = List[Int]()
    _load(source, kinds, texts)
    _imports(kinds, texts, modules, names, aliases, from_import)
    _one_from(modules, names, aliases, from_import, module, expected, label)
    var index = 0
    while index <= expected.byte_length():
        var end = expected.find(",", index)
        if end < 0:
            end = expected.byte_length()
        var helper = String(expected[byte=index:end])
        _shadows(
            kinds,
            texts,
            modules,
            names,
            aliases,
            from_import,
            helper,
            module,
            False,
        )
        if end == expected.byte_length():
            break
        index = end + 1


def sum2_helper_bindings(
    lane: String, bounds: String, roundoff: String, interval: String
) raises:
    """Require the reviewed Sum2 and stored-half bindings.

    Args:
        lane: The `lane_geometry` module.
        bounds: The `curve_bounds` module.
        roundoff: The `spiral_roundoff_proof` module.
        interval: The `curve_interval` module.

    Raises:
        Error: An import changed, or a reviewed helper is shadowed.
    """
    _check_consumer(
        lane,
        "extensions.carla.curve_sum2",
        "_sum2_update,_require_sum2_environment",
        "lane_geometry",
    )
    _check_consumer(
        bounds,
        "extensions.carla.curve_sum2",
        "_sum2_error_checked,_sum2_supported_environment",
        "curve_bounds",
    )
    _check_consumer(
        roundoff,
        "extensions.carla.curve_sum2",
        "_sum2_error",
        "spiral_roundoff_proof",
    )
    var kinds = List[Int]()
    var texts = List[String]()
    var modules = List[String]()
    var names = List[String]()
    var aliases = List[String]()
    var from_import = List[Int]()
    _load(bounds, kinds, texts)
    _imports(kinds, texts, modules, names, aliases, from_import)
    _half_import(modules, names, aliases, from_import)
    _shadows(
        kinds,
        texts,
        modules,
        names,
        aliases,
        from_import,
        "_stored_half",
        "extensions.carla.curve_interval",
        False,
    )
    kinds.clear()
    texts.clear()
    modules.clear()
    names.clear()
    aliases.clear()
    from_import.clear()
    _load(interval, kinds, texts)
    _imports(kinds, texts, modules, names, aliases, from_import)
    _shadows(
        kinds,
        texts,
        modules,
        names,
        aliases,
        from_import,
        "_stored_half",
        "extensions.carla.curve_interval",
        True,
    )
