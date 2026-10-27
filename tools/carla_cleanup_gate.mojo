# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the reviewed cleanup migration record.

    carla_cleanup_gate --migration PATH [--previous PATH]
    carla_cleanup_gate --bytes PATH --sha HEX
    carla_cleanup_gate --sha-of PATH
    carla_cleanup_gate --sha-texts PATH
    carla_cleanup_gate --token-sha PATH
    carla_cleanup_gate --tokens DIR
    carla_cleanup_gate --words PATH --kind trig|geometry --label PATH
    carla_cleanup_gate --premises DIR
    carla_cleanup_gate --declaration PATH --name NAME [--owner NAME]
    carla_cleanup_gate --bounds PATH --name NAME [--owner NAME]
    carla_cleanup_gate --significant-json DIR
    carla_cleanup_gate --names DIR
    carla_cleanup_gate --moves PATH
    carla_cleanup_gate --statements PATH
    carla_cleanup_gate --starts PATH
    carla_cleanup_gate --routing PATH --constants PATH
    carla_cleanup_gate --ideal PATH --name NAME
    carla_cleanup_gate --stored-half PATH
    carla_cleanup_gate --project-sum2 PATH
    carla_cleanup_gate --commute-legacy PATH
    carla_cleanup_gate --binding PATH
    carla_cleanup_gate --imports PATH
    carla_cleanup_gate --heading PATH
    carla_cleanup_gate --syntax PATH
    carla_cleanup_gate --slice PATH --name NAME
    carla_cleanup_gate --fragment DIR
    carla_cleanup_gate --normalize PATH
    carla_cleanup_gate --table PATH --count N
    carla_cleanup_gate --moment-source PATH
    carla_cleanup_gate --moment-payload PATH
    carla_cleanup_gate --verify-table DIR
    carla_cleanup_gate --block DIR
    carla_cleanup_gate --strip-try PATH
    carla_cleanup_gate --pin-rows PATH
    carla_cleanup_gate --decimal PATH
    carla_cleanup_gate --literals PATH --name NAME --kind array --size N
    carla_cleanup_gate --literals PATH --name NAME --kind scalar

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent previous file checks only the migration record.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import heading_sources
from tests._python_tokens import (
    declaration_place,
    ideal_function_source,
    constant_literals_json,
    check_stored_half,
    binding_shadow_payload,
    direct_imports_payload,
    commute_legacy_source,
    project_sum2_source,
    function_slice,
    moment_payload_json,
    moment_source,
    moment_words_json,
    verify_moment_table,
    normalized_block,
    selected_block,
    pin_transition_rows,
    strip_try_only_routing,
    replace_token_fragment,
    python_syntax_json,
    declaration_text,
    stored_float_array,
    stored_scalar,
    significant_json,
    stored_word_sha256,
    module_routing_json,
    module_statements_json,
    top_level_starts_json,
    token_names,
    token_sha256,
    token_words,
    without_move_sigils,
)
from tools._python_json import MISSING, PY_DICT, PY_INT, PY_LIST, PY_STR, PyJson
from tools._sha256 import sha256_hex
from tools._spiral_moment_words import decimal_word


comptime _MIGRATION_SHA256 = (
    "01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9"
)
comptime _TRIG_WORD = (
    "f2337e89e88234a7a275e1be6398d672abd05210e5b37098e2e3bd39212c3807"
)
comptime _GEOMETRY_WORD = (
    "fb42552072a0166ca3ca94016b39ba98a6645e4091751e4b5b67e199139e96f0"
)


def _fail(message: String) raises:
    """Raise one reviewed-cleanup failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("reviewed cleanup source contract: " + message)


def _named(group: Int, index: Int) -> String:
    """Return one reviewed path.

    Args:
        group: 0 for successors, 1 for premise dependencies.
        index: The path position in that group.

    Returns:
        The repository path.
    """
    if group == 0:
        if index == 0:
            return "extensions/carla/curve_rounded_line.mojo"
        if index == 1:
            return "extensions/carla/curve_rounded_arc.mojo"
        return "extensions/carla/junction_bounds.mojo"
    if index == 0:
        return "extensions/carla/road_info.mojo"
    return "extensions/carla/curve_trig.mojo"


def _keys_match(doc: PyJson, node: Int, group: Int, count: Int) -> Bool:
    """Return whether an object has exactly one reviewed key set.

    Args:
        doc: The record.
        node: The object, or `MISSING`.
        group: Which reviewed path table to use.
        count: The number of reviewed paths.

    Returns:
        True when the keys are exactly that set.
    """
    if (
        node == MISSING
        or doc.kind(node) != PY_DICT
        or doc.length(node) != count
    ):
        return False
    var index = 0
    while index < count:
        if doc.get(node, _named(group, index)) == MISSING:
            return False
        index += 1
    return True


def _require_record(doc: PyJson) raises:
    """Require schema 1, the successor set, and the premise set.

    Args:
        doc: The migration record.

    Raises:
        Error: The schema or a path set changed.
    """
    var schema = doc.get(doc.root, "schema")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
    ):
        _fail("unsupported migration schema")
    if not _keys_match(doc, doc.get(doc.root, "sources"), 0, 3):
        _fail("wrong successor set")
    if not _keys_match(doc, doc.get(doc.root, "premise_dependencies"), 1, 2):
        _fail("wrong premise dependency set")


def _require_previous(doc: PyJson, previous: Span[UInt8, _]) raises:
    """Require the winner-sign migration digest.

    Args:
        doc: The migration record.
        previous: The historical winner-sign migration bytes.

    Raises:
        Error: The digest changed.
    """
    var field = doc.get(doc.root, "prior_winner_sign_migration_sha256")
    if (
        field == MISSING
        or doc.kind(field) != PY_STR
        or doc.text(field) != sha256_hex(previous)
    ):
        _fail("historical winner/sign record changed")


def cleanup_record(
    migration: Span[UInt8, _],
    previous: Span[UInt8, _],
    check_previous: Bool,
) raises:
    """Require the reviewed cleanup record.

    Args:
        migration: The successor record bytes.
        previous: The winner-sign migration. Used only when `check_previous` is true.
        check_previous: Whether to check the winner-sign digest.

    Raises:
        Error: The record or the winner-sign digest changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    _require_record(doc)
    if not check_previous:
        return
    _require_previous(doc, previous)


def cleanup_sha(payload: Span[UInt8, _]) -> String:
    """Return the SHA-256 hex digest of stored-word bytes.

    Args:
        payload: The canonical stored-word JSON.

    Returns:
        The lowercase hex digest.
    """
    return sha256_hex(payload)


def sha256_texts_json(payload: String) raises -> String:
    """Return the SHA-256 digest of each text.

    Args:
        payload: A JSON list of source texts.

    Returns:
        A JSON list of lowercase hex digests, in the same order.

    Raises:
        Error: The payload is not a list of strings.
    """
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var out = PyJson()
    var rows = out.new_list()
    var index = 0
    while index < count:
        var text = doc.text(doc.item(doc.root, index))
        out.append(rows, out.new_str(sha256_hex(text.as_bytes())))
        index += 1
    out.root = rows
    return out.dumps()


def cleanup_digest(payload: Span[UInt8, _], expected: String) raises:
    """Require the guard-pin successor digest.

    Args:
        payload: The reconstructed guard-pin bytes.
        expected: The required SHA-256 hex digest.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(payload) != expected:
        _fail("unreviewed dependency pin successor: sum2-guard-pins.json")


def _check_stored(source: String, name: String, size: Int) raises:
    """Require one stored declaration before its word digest is compared.

    Args:
        source: The module text.
        name: The constant name.
        size: The array length, or 0 for one scalar.

    Raises:
        Error: The declaration is missing, repeated, or not one decimal.
    """
    try:
        if size == 0:
            var value = stored_scalar(source, name)
            var rendered = String(value)
            if rendered.byte_length() < 0:
                _fail("unsupported complete stored-word scalar: " + name)
        else:
            var values = stored_float_array(source, name, size)
            if len(values) != size:
                _fail(
                    "unsupported complete constant-array declaration: " + name
                )
    except error:
        var message = String(error)
        if message.startswith("reviewed cleanup source contract:"):
            raise error
        if (
            message.startswith("missing or ambiguous")
            or message == "Missing or ambiguous selector constant"
        ):
            _fail("missing or ambiguous stored-word declaration: " + name)
        if size == 0:
            _fail("unsupported complete stored-word scalar: " + name)
        _fail("unsupported complete constant-array declaration: " + name)


def cleanup_words(source: String, kind: String, label: String) raises:
    """Require the trig or geometry stored-word digest.

    Args:
        source: The module text.
        kind: `trig` or `geometry`.
        label: The module path named in a mismatch.

    Raises:
        Error: The words changed, or a stored declaration cannot be read.
    """
    var arrays = List[String]()
    var sizes = List[Int]()
    var scalars = List[String]()
    var expected = String("")
    if kind == "trig":
        _check_stored(source, "_COS_COEFFICIENTS", 11)
        _check_stored(source, "_HALF_PI_HIGH", 0)
        _check_stored(source, "_HALF_PI_LOW", 0)
        _check_stored(source, "_INV_HALF_PI", 0)
        _check_stored(source, "_PHASE_LIMIT", 0)
        _check_stored(source, "_SIN_COEFFICIENTS", 11)
        arrays.append("_COS_COEFFICIENTS")
        arrays.append("_SIN_COEFFICIENTS")
        sizes.append(11)
        sizes.append(11)
        scalars.append("_PHASE_LIMIT")
        scalars.append("_INV_HALF_PI")
        scalars.append("_HALF_PI_HIGH")
        scalars.append("_HALF_PI_LOW")
        expected = _TRIG_WORD
    elif kind == "geometry":
        _check_stored(source, "_GL_NODES", 5)
        _check_stored(source, "_GL_WEIGHTS", 5)
        arrays.append("_GL_NODES")
        arrays.append("_GL_WEIGHTS")
        sizes.append(5)
        sizes.append(5)
        expected = _GEOMETRY_WORD
    else:
        _fail("unreviewed stored-word kind")
    var digest = stored_word_sha256(source, arrays, sizes, scalars)
    if digest != expected:
        _fail("unchanged premise dependency changed: " + label)


def significant_documents(directory: String) raises:
    """Print the significant-token JSON for each numbered source.

    Args:
        directory: A directory with `count` and `N.text` files.

    Raises:
        Error: A source cannot be tokenized, or the directory cannot be read.
    """
    var count = Int(Path(directory + "/count").read_text())
    var doc = PyJson()
    var rows = doc.new_list()
    var index = 0
    while index < count:
        var text = Path(directory + "/" + String(index) + ".text").read_text()
        doc.append(rows, doc.new_str(significant_json(text)))
        index += 1
    doc.root = rows
    print(doc.dumps())


def name_documents(directory: String) raises:
    """Print the NAME tokens for each numbered source.

    Args:
        directory: A directory with `count` and `N.text` files.

    Raises:
        Error: A source cannot be tokenized, or the directory cannot be read.
    """
    var count = Int(Path(directory + "/count").read_text())
    var doc = PyJson()
    var rows = doc.new_list()
    var index = 0
    while index < count:
        var names = token_names(
            Path(directory + "/" + String(index) + ".text").read_text()
        )
        var row = doc.new_list()
        var name_index = 0
        while name_index < len(names):
            doc.append(row, doc.new_str(names[name_index]))
            name_index += 1
        doc.append(rows, row)
        index += 1
    doc.root = rows
    print(doc.dumps())


def cleanup_premises(directory: String) raises:
    """Require each premise fragment once, in order.

    Args:
        directory: A directory with `labels.json` and `N.mojo` sources.

    Raises:
        Error: A fragment is missing, repeated, or out of order.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("unreviewed premise order")
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var row = doc.item(doc.root, index)
        var label = doc.text(doc.at(row, "label"))
        var source = Path(directory + "/" + String(index) + ".mojo").read_text()
        var actual = token_words(source)
        var fragments = doc.at(row, "fragments")
        if doc.kind(fragments) != PY_LIST:
            _fail(label)
        var previous = -1
        var fragment_index = 0
        var fragment_count = doc.length(fragments)
        while fragment_index < fragment_count:
            var expected = token_words(
                doc.text(doc.item(fragments, fragment_index))
            )
            var limit = len(actual) - len(expected) + 1
            var hits = 0
            var found = -1
            var start = 0
            while start < limit:
                var same = True
                var offset = 0
                while offset < len(expected):
                    if actual[start + offset] != expected[offset]:
                        same = False
                        offset = len(expected)
                    else:
                        offset += 1
                if same:
                    hits += 1
                    if hits == 1:
                        found = start
                start += 1
            if hits != 1 or found <= previous:
                _fail(label)
            previous = found
            fragment_index += 1
        index += 1


def cleanup_tokens(directory: String) raises:
    """Require each successor text to have its recorded token digest.

    Args:
        directory: A directory with `labels.json` and `N.text` files.

    Raises:
        Error: A token digest changed, or the directory cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("unreviewed complete successor")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var label = doc.text(doc.at(row, "label"))
        var expected = doc.text(doc.at(row, "token"))
        var text = Path(directory + "/" + String(index) + ".text").read_text()
        if token_sha256(text) != expected:
            _fail(label)
        index += 1


def _u64_hex(word: UInt64) -> String:
    """Return one binary64 word as `0x` and sixteen uppercase hex digits.

    Args:
        word: The encoding.

    Returns:
        The fixed-width spelling.
    """
    var out = String("0x")
    var shift = 60
    while shift >= 0:
        var nibble = Int((word >> UInt64(shift)) & 0xF)
        if nibble < 10:
            out += chr(48 + nibble)
        else:
            out += chr(55 + nibble)
        shift -= 4
    return out


def decimal_words_json(payload: String) raises -> String:
    """Round each decimal literal to its nearest binary64 word.

    Args:
        payload: A JSON list of decimal literal spellings.

    Returns:
        A JSON list of `0x` words. Each word has 16 hexadecimal digits.
        `-0.0` keeps its sign.

    Raises:
        Error: A literal is not a finite decimal number.
    """
    var doc = PyJson.parse(payload)
    var count = doc.length(doc.root)
    var out = PyJson()
    var rows = out.new_list()
    var index = 0
    while index < count:
        var token = doc.text(doc.item(doc.root, index))
        out.append(rows, out.new_str(_u64_hex(decimal_word(token))))
        index += 1
    out.root = rows
    return out.dumps()


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_cleanup_gate --migration PATH [--previous PATH] |"
            " --bytes PATH --sha HEX | --sha-of PATH | --sha-texts PATH |"
            " --token-sha PATH | --tokens DIR | --words PATH --kind"
            " trig|geometry --label PATH | --premises DIR | --declaration PATH"
            " --name NAME [--owner NAME] | --bounds PATH --name NAME [--owner"
            " NAME] | --significant-json DIR | --names DIR | --moves PATH |"
            " --statements PATH | --starts PATH | --routing PATH --constants"
            " PATH | --ideal PATH --name NAME | --stored-half PATH |"
            " --project-sum2 PATH | --commute-legacy PATH | --binding PATH |"
            " --imports PATH | --heading PATH |"
            " --syntax PATH |"
            " --slice PATH --name NAME | --fragment DIR | --normalize PATH |"
            " --table PATH --count N | --moment-source PATH | --moment-payload"
            " PATH | --verify-table DIR | --block DIR | --strip-try PATH |"
            " --pin-rows PATH | --decimal PATH | --literals PATH --name NAME"
            " --kind array --size N | --literals PATH --name NAME --kind scalar"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the reviewed cleanup record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var previous = String("")
    var payload = String("")
    var digest = String("")
    var sha_of = String("")
    var sha_texts = String("")
    var token_sha = String("")
    var tokens = String("")
    var words = String("")
    var kind = String("")
    var label = String("")
    var premises = String("")
    var declaration = String("")
    var bounds = String("")
    var decl_name = String("")
    var owners = List[String]()
    var significant = String("")
    var names = String("")
    var moves = String("")
    var statements = String("")
    var starts = String("")
    var routing = String("")
    var constants = String("")
    var ideal = String("")
    var stored_half = String("")
    var project_sum2 = String("")
    var commute_legacy = String("")
    var binding = String("")
    var imports = String("")
    var heading = String("")
    var syntax = String("")
    var slice_path = String("")
    var fragment = String("")
    var normalize = String("")
    var table = String("")
    var table_count = String("")
    var moment_source_path = String("")
    var moment_payload = String("")
    var verify_table = String("")
    var block = String("")
    var strip_try = String("")
    var pin_rows = String("")
    var decimal = String("")
    var literals = String("")
    var literal_size = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--previous"
            or word == "--bytes"
            or word == "--sha"
            or word == "--sha-of"
            or word == "--sha-texts"
            or word == "--token-sha"
            or word == "--tokens"
            or word == "--words"
            or word == "--kind"
            or word == "--label"
            or word == "--premises"
            or word == "--declaration"
            or word == "--bounds"
            or word == "--name"
            or word == "--owner"
            or word == "--significant-json"
            or word == "--names"
            or word == "--moves"
            or word == "--statements"
            or word == "--starts"
            or word == "--routing"
            or word == "--constants"
            or word == "--ideal"
            or word == "--stored-half"
            or word == "--project-sum2"
            or word == "--commute-legacy"
            or word == "--binding"
            or word == "--imports"
            or word == "--heading"
            or word == "--syntax"
            or word == "--slice"
            or word == "--fragment"
            or word == "--normalize"
            or word == "--table"
            or word == "--count"
            or word == "--moment-source"
            or word == "--moment-payload"
            or word == "--verify-table"
            or word == "--block"
            or word == "--strip-try"
            or word == "--pin-rows"
            or word == "--decimal"
            or word == "--literals"
            or word == "--size"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--previous":
                previous = value
            elif word == "--bytes":
                payload = value
            elif word == "--sha":
                digest = value
            elif word == "--sha-of":
                sha_of = value
            elif word == "--sha-texts":
                sha_texts = value
            elif word == "--token-sha":
                token_sha = value
            elif word == "--tokens":
                tokens = value
            elif word == "--words":
                words = value
            elif word == "--kind":
                kind = value
            elif word == "--label":
                label = value
            elif word == "--premises":
                premises = value
            elif word == "--declaration":
                declaration = value
            elif word == "--bounds":
                bounds = value
            elif word == "--name":
                decl_name = value
            elif word == "--owner":
                owners.append(value)
            elif word == "--significant-json":
                significant = value
            elif word == "--names":
                names = value
            elif word == "--moves":
                moves = value
            elif word == "--statements":
                statements = value
            elif word == "--starts":
                starts = value
            elif word == "--routing":
                routing = value
            elif word == "--constants":
                constants = value
            elif word == "--ideal":
                ideal = value
            elif word == "--stored-half":
                stored_half = value
            elif word == "--project-sum2":
                project_sum2 = value
            elif word == "--commute-legacy":
                commute_legacy = value
            elif word == "--binding":
                binding = value
            elif word == "--imports":
                imports = value
            elif word == "--heading":
                heading = value
            elif word == "--syntax":
                syntax = value
            elif word == "--slice":
                slice_path = value
            elif word == "--fragment":
                fragment = value
            elif word == "--normalize":
                normalize = value
            elif word == "--table":
                table = value
            elif word == "--count":
                table_count = value
            elif word == "--moment-source":
                moment_source_path = value
            elif word == "--moment-payload":
                moment_payload = value
            elif word == "--verify-table":
                verify_table = value
            elif word == "--block":
                block = value
            elif word == "--strip-try":
                strip_try = value
            elif word == "--pin-rows":
                pin_rows = value
            elif word == "--decimal":
                decimal = value
            elif word == "--literals":
                literals = value
            elif word == "--size":
                literal_size = value
            else:
                _usage()
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if payload.byte_length() > 0:
        modes += 1
    if sha_of.byte_length() > 0:
        modes += 1
    if sha_texts.byte_length() > 0:
        modes += 1
    if token_sha.byte_length() > 0:
        modes += 1
    if tokens.byte_length() > 0:
        modes += 1
    if (
        words.byte_length() > 0
        or label.byte_length() > 0
        or kind == "trig"
        or kind == "geometry"
    ):
        modes += 1
    if (
        literals.byte_length() > 0
        or literal_size.byte_length() > 0
        or kind == "array"
        or kind == "scalar"
    ):
        modes += 1
    if premises.byte_length() > 0:
        modes += 1
    if declaration.byte_length() > 0:
        modes += 1
    if bounds.byte_length() > 0:
        modes += 1
    if (
        declaration.byte_length() == 0
        and bounds.byte_length() == 0
        and ideal.byte_length() == 0
        and slice_path.byte_length() == 0
        and literals.byte_length() == 0
        and (decl_name.byte_length() > 0 or len(owners) > 0)
    ):
        modes += 1
    if ideal.byte_length() > 0:
        modes += 1
    if stored_half.byte_length() > 0:
        modes += 1
    if project_sum2.byte_length() > 0:
        modes += 1
    if commute_legacy.byte_length() > 0:
        modes += 1
    if binding.byte_length() > 0:
        modes += 1
    if imports.byte_length() > 0:
        modes += 1
    if heading.byte_length() > 0:
        modes += 1
    if syntax.byte_length() > 0:
        modes += 1
    if slice_path.byte_length() > 0:
        modes += 1
    if fragment.byte_length() > 0:
        modes += 1
    if normalize.byte_length() > 0:
        modes += 1
    if table.byte_length() > 0 or table_count.byte_length() > 0:
        modes += 1
    if moment_source_path.byte_length() > 0:
        modes += 1
    if moment_payload.byte_length() > 0:
        modes += 1
    if verify_table.byte_length() > 0:
        modes += 1
    if block.byte_length() > 0:
        modes += 1
    if strip_try.byte_length() > 0:
        modes += 1
    if pin_rows.byte_length() > 0:
        modes += 1
    if decimal.byte_length() > 0:
        modes += 1
    if significant.byte_length() > 0:
        modes += 1
    if names.byte_length() > 0:
        modes += 1
    if moves.byte_length() > 0:
        modes += 1
    if statements.byte_length() > 0:
        modes += 1
    if starts.byte_length() > 0:
        modes += 1
    if routing.byte_length() > 0 or constants.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if previous.byte_length() > 0 and migration.byte_length() == 0:
        _usage()
    if payload.byte_length() > 0 and digest.byte_length() == 0:
        _usage()
    if words.byte_length() > 0 and (
        label.byte_length() == 0 or (kind != "trig" and kind != "geometry")
    ):
        _usage()
    if (
        words.byte_length() == 0
        and literals.byte_length() == 0
        and (kind.byte_length() > 0 or label.byte_length() > 0)
    ):
        _usage()
    if (
        declaration.byte_length() == 0
        and bounds.byte_length() == 0
        and ideal.byte_length() == 0
        and slice_path.byte_length() == 0
        and literals.byte_length() == 0
        and (decl_name.byte_length() > 0 or len(owners) > 0)
    ):
        _usage()
    if (
        declaration.byte_length() > 0
        or bounds.byte_length() > 0
        or ideal.byte_length() > 0
        or slice_path.byte_length() > 0
        or literals.byte_length() > 0
    ) and decl_name.byte_length() == 0:
        _usage()
    try:
        if (routing.byte_length() == 0) != (constants.byte_length() == 0):
            _usage()
        if routing.byte_length() > 0:
            print(
                module_routing_json(
                    Path(routing).read_text(), Path(constants).read_text()
                ),
                end="",
            )
            return
        if literals.byte_length() > 0:
            if kind == "array":
                var size = 0
                try:
                    size = Int(literal_size)
                except error:
                    _ = String(error)
                    _usage()
                if size < 0 or literal_size.byte_length() == 0:
                    _usage()
                print(
                    constant_literals_json(
                        Path(literals).read_text(), decl_name, kind, size
                    ),
                    end="",
                )
            elif kind == "scalar" and literal_size.byte_length() == 0:
                print(
                    constant_literals_json(
                        Path(literals).read_text(), decl_name, kind, 0
                    ),
                    end="",
                )
            else:
                _usage()
            return
        if pin_rows.byte_length() > 0:
            print(pin_transition_rows(Path(pin_rows).read_text()), end="")
            return
        if decimal.byte_length() > 0:
            print(decimal_words_json(Path(decimal).read_text()), end="")
            return
        if strip_try.byte_length() > 0:
            print(
                strip_try_only_routing(Path(strip_try).read_text()),
                end="",
            )
            return
        if block.byte_length() > 0:
            print(
                selected_block(
                    Path(block + "/source.text").read_text(),
                    Path(block + "/begin.text").read_text(),
                    Path(block + "/end.text").read_text(),
                ),
                end="",
            )
            return
        if moment_source_path.byte_length() > 0:
            print(
                moment_source(Path(moment_source_path).read_text()),
                end="",
            )
            return
        if moment_payload.byte_length() > 0:
            print(
                moment_payload_json(Path(moment_payload).read_text()),
                end="",
            )
            return
        if verify_table.byte_length() > 0:
            print(
                verify_moment_table(
                    Path(verify_table + "/table.text").read_text(),
                    Path(verify_table + "/words.json").read_text(),
                ),
                end="",
            )
            return
        if table.byte_length() > 0 or table_count.byte_length() > 0:
            if table.byte_length() == 0 or table_count.byte_length() == 0:
                _usage()
            var count = 0
            try:
                count = Int(table_count)
            except error:
                _ = String(error)
                _usage()
            if count < 0:
                _usage()
            print(
                moment_words_json(Path(table).read_text(), count),
                end="",
            )
            return
        if normalize.byte_length() > 0:
            print(normalized_block(Path(normalize).read_text()), end="")
            return
        if fragment.byte_length() > 0:
            print(
                replace_token_fragment(
                    Path(fragment + "/source.text").read_text(),
                    Path(fragment + "/before.text").read_text(),
                    Path(fragment + "/after.text").read_text(),
                ),
                end="",
            )
            return
        if slice_path.byte_length() > 0:
            print(
                function_slice(Path(slice_path).read_text(), decl_name),
                end="",
            )
            return
        if syntax.byte_length() > 0:
            print(python_syntax_json(Path(syntax).read_text()), end="")
            return
        if ideal.byte_length() > 0:
            print(
                ideal_function_source(Path(ideal).read_text(), decl_name),
                end="",
            )
            return
        if stored_half.byte_length() > 0:
            check_stored_half(Path(stored_half).read_text())
            return
        if project_sum2.byte_length() > 0:
            print(project_sum2_source(Path(project_sum2).read_text()), end="")
            return
        if commute_legacy.byte_length() > 0:
            print(
                commute_legacy_source(Path(commute_legacy).read_text()),
                end="",
            )
            return
        if binding.byte_length() > 0:
            binding_shadow_payload(Path(binding).read_text())
            return
        if imports.byte_length() > 0:
            print(direct_imports_payload(Path(imports).read_text()), end="")
            return
        if heading.byte_length() > 0:
            heading_sources(Path(heading).read_text())
            return
        if starts.byte_length() > 0:
            print(top_level_starts_json(Path(starts).read_text()), end="")
            return
        if statements.byte_length() > 0:
            print(module_statements_json(Path(statements).read_text()), end="")
            return
        if moves.byte_length() > 0:
            print(without_move_sigils(Path(moves).read_text()), end="")
            return
        if names.byte_length() > 0:
            name_documents(names)
            return
        if significant.byte_length() > 0:
            significant_documents(significant)
            return
        if bounds.byte_length() > 0:
            var place = declaration_place(
                Path(bounds).read_text(), decl_name, owners
            )
            print(String(place.first) + " " + String(place.last))
            print(place.text, end="")
            return
        if declaration.byte_length() > 0:
            print(
                declaration_text(
                    Path(declaration).read_text(), decl_name, owners
                ),
                end="",
            )
            return
        if premises.byte_length() > 0:
            cleanup_premises(premises)
            return
        if words.byte_length() > 0:
            cleanup_words(Path(words).read_text(), kind, label)
            return
        if tokens.byte_length() > 0:
            cleanup_tokens(tokens)
            return
        if token_sha.byte_length() > 0:
            print(token_sha256(Path(token_sha).read_text()), end="")
            return
        if sha_of.byte_length() > 0:
            print(cleanup_sha(Path(sha_of).read_bytes()))
            return
        if sha_texts.byte_length() > 0:
            print(sha256_texts_json(Path(sha_texts).read_text()), end="")
            return
        if payload.byte_length() > 0:
            cleanup_digest(Path(payload).read_bytes(), digest)
        elif previous.byte_length() == 0:
            cleanup_record(
                Path(migration).read_bytes(), String("").as_bytes(), False
            )
        else:
            cleanup_record(
                Path(migration).read_bytes(), Path(previous).read_bytes(), True
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
