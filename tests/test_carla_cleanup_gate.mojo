# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""A changed reviewed cleanup record fails the gate."""

from std.testing import TestSuite, assert_equal, assert_raises

from std.os import makedirs
from std.pathlib import Path
from tests._python_expr import (
    expression_dump,
    function_dump,
    plain_function_dump,
    statement_dump,
)
from tests._python_tokens import (
    declaration_place,
    declaration_text,
    constant_literals_json,
    function_slice,
    try_only_refusal,
    moment_source,
    moment_words_json,
    normalized_block,
    selected_block,
    pin_transition_rows,
    strip_try_only_routing,
    replace_token_fragment,
    ideal_function_source,
    python_syntax_json,
    significant_json,
    module_routing_json,
    module_statements_json,
    token_names,
    token_sha256,
    top_level_starts_json,
    _direct_imports_json,
    without_move_sigils,
)
from tools.carla_cleanup_gate import (
    decimal_words_json,
    cleanup_digest,
    cleanup_record,
    cleanup_sha,
    sha256_texts_json,
    cleanup_premises,
    cleanup_tokens,
    cleanup_words,
)


def test_a_changed_record_is_refused() raises:
    """Bytes that are not the reviewed record fail closed."""
    with assert_raises(
        contains="reviewed cleanup source contract: unreviewed migration record"
    ):
        cleanup_record(String("").as_bytes(), String("").as_bytes(), False)


def test_a_changed_guard_pin_is_refused() raises:
    """Bytes that are not the recorded guard pin fail closed."""
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unreviewed dependency pin"
            " successor: sum2-guard-pins.json"
        )
    ):
        cleanup_digest(String("nope").as_bytes(), "00")


def test_a_changed_successor_token_is_refused() raises:
    """A text that does not have the recorded token digest fails closed."""
    var directory = "/tmp/cleanup-token-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"label":"unreviewed complete successor: module.mojo","token":"00"}]'
    )
    Path(directory + "/0.text").write_text("def changed():\n    pass\n")
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unreviewed complete successor:"
            " module.mojo"
        )
    ):
        cleanup_tokens(directory)


def test_a_missing_stored_word_is_refused() raises:
    """A geometry module without its stored arrays fails closed."""
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: missing or ambiguous"
            " stored-word declaration: _GL_NODES"
        )
    ):
        cleanup_words(
            "def empty():\n    pass\n",
            "geometry",
            "extensions/carla/geometry.mojo",
        )


def test_a_changed_stored_word_is_refused() raises:
    """Geometry arrays of zeros are not the reviewed words."""
    var source = String(
        "comptime _GL_NODES: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0, 0.0]\n"
        + "comptime _GL_WEIGHTS: Array[Float64, 5] = [0.0, 0.0, 0.0, 0.0,"
        " 0.0]\n"
    )
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: unchanged premise dependency"
            " changed: extensions/carla/geometry.mojo"
        )
    ):
        cleanup_words(source, "geometry", "extensions/carla/geometry.mojo")


def test_a_nested_def_is_not_a_top_level_start() raises:
    """Only a top-level def or import line is recorded."""
    var source = String(
        "def first():\n"
        + "    def nested():\n"
        + "        return 1\n"
        + "from a import b\n"
    )
    assert_equal(top_level_starts_json(source), "[[1,0],[4,0]]")


def test_an_ideal_generic_parameter_list_is_removed() raises:
    """`var` and the `derivatives: Bool` list are removed."""
    var source = String(
        "def _stored_half[\n"
        + "    derivatives: Bool\n"
        + "](value: Int) -> Int:\n"
        + "    var result = value\n"
        + "    return result\n"
    )
    var plain = ideal_function_source(source, "_stored_half")
    if plain.find("var ") >= 0 or plain.find("derivatives") >= 0:
        raise Error(plain)
    if plain.find("def _stored_half") < 0 or plain.find("return result") < 0:
        raise Error(plain)


def test_a_top_level_function_slice_stops_at_the_next_def() raises:
    """The slice starts at `def` and stops before the next top-level marker."""
    var source = String(
        "@hidden\n"
        + "def first(value: Int):\n"
        + "    return value\n"
        + "\n"
        + "def second[T: Int]():\n"
        + "    return 1\n"
        + "@later\n"
        + "def third():\n"
        + "    return 2\n"
    )
    assert_equal(
        function_slice(source, "first"),
        "def first(value: Int):\n    return value\n\n",
    )
    assert_equal(
        function_slice(source, "second"),
        "def second[T: Int]():\n    return 1\n",
    )
    assert_equal(
        function_slice(source, "third"),
        "def third():\n    return 2\n",
    )
    with assert_raises(contains="missing or ambiguous function: first"):
        _ = function_slice(source + "def first():\n    return 0\n", "first")
    with assert_raises(contains="missing or ambiguous function: absent"):
        _ = function_slice(source, "absent")


def test_the_moment_source_keeps_the_canonical_header() raises:
    """2816 zero words become the generated table layout."""
    var words = String("[")
    var index = 0
    while index < 2816:
        if index > 0:
            words += ","
        words += '"0x0000000000000000"'
        index += 1
    words += "]"
    var text = moment_source(words)
    if not text.startswith("# Copyright (c) 2026 Seth Kitchen, PE\n"):
        raise Error("header changed")
    if text.find("    # Count 1\n    # cosine\n") < 0:
        raise Error("first count changed")
    if text.find("    # Count 64\n    # cosine\n") < 0:
        raise Error("last count changed")
    if not text.endswith("]\n"):
        raise Error("closer changed")
    with assert_raises(contains="malformed moment source word"):
        _ = moment_source('["0x1"]')


def test_a_moment_table_keeps_its_hex_words() raises:
    """Comments do not change the stored words, and a short word fails."""
    var source = String(
        "# header\n"
        + "comptime _SPIRAL_MOMENT_WORDS: Array[UInt64, 2] = [\n"
        + "    # Count 1\n"
        + "    UInt64(0x0000000000000001), UInt64(0x000000000000000A),\n"
        + "]\n"
    )
    assert_equal(
        moment_words_json(source, 2),
        '["0x0000000000000001","0x000000000000000A"]',
    )
    with assert_raises(contains="malformed coefficient word or extra source"):
        _ = moment_words_json(
            source.replace("0x0000000000000001", "0x000000000000001"), 2
        )
    with assert_raises(contains="wrong table declaration shape"):
        _ = moment_words_json(
            source.replace("Array[UInt64, 2]", "Array[UInt64, 1]"), 2
        )


def test_a_repeated_pin_pointer_is_marked() raises:
    """The second use of one pointer is a duplicate and has no value."""
    var payload = String(
        '{"pins":{"groups":{"g":{"a":"AFTER"}}},"transitions":['
        + '{"pointer":["groups","g","a"],"before":"BEFORE","after":"AFTER"},'
        + '{"pointer":["groups","g","a"],"before":"BEFORE","after":"AFTER"}]}'
    )
    assert_equal(
        pin_transition_rows(payload),
        '[{"actual":"AFTER","duplicate":false,"expected":"AFTER"},'
        + '{"actual":"","duplicate":true,"expected":"AFTER"}]',
    )


def test_the_try_only_parameter_is_removed() raises:
    """One default-false parameter is deleted from the proof declaration."""
    var routing = String(
        '[[["NAME","def"],["NAME","_lane_jet_model_proof"],'
        + '["NAME","require_reuse"],["OP",":"],["NAME","Bool"],'
        + '["OP","="],["NAME","False"],["OP",","],["OP",")"]]]'
    )
    assert_equal(
        strip_try_only_routing(routing),
        '[[["NAME","def"],["NAME","_lane_jet_model_proof"],["OP",")"]]]',
    )
    with assert_raises(contains="missing try-only routing declaration"):
        _ = strip_try_only_routing('[[["NAME","def"],["NAME","other"]]]')
    with assert_raises(contains="try-only routing parameter changed"):
        _ = strip_try_only_routing(
            '[[["NAME","def"],["NAME","_lane_jet_model_proof"],["OP",")"]]]'
        )


def test_a_source_block_stops_at_the_next_marker() raises:
    """A docstring copy of a marker is not a top-level boundary."""
    var source = String(
        '"""\n'
        + "def decoy():\n"
        + '"""\n'
        + "def first():\n"
        + "    return 1\n"
        + "\n"
        + "def second():\n"
        + "    return 2\n"
    )
    assert_equal(
        selected_block(source, "def first():", "def second():"),
        "def first():\n    return 1\n",
    )
    with assert_raises(
        contains="source-block boundary is not an actual top-level token"
    ):
        _ = selected_block(source, "def decoy():", "def second():")
    with assert_raises(contains="unbound decorator before source-block start"):
        _ = selected_block(
            (
                "@no_inline\ndef first():\n    return 1\n\ndef second():\n   "
                " return 2\n"
            ),
            "def first():",
            "def second():",
        )


def test_a_source_block_drops_comments_and_blank_lines() raises:
    """Indentation stays, and a comment or a blank line does not."""
    assert_equal(
        normalized_block("    a  # c\n\n  \n    b\n"),
        "    a\n    b\n",
    )
    assert_equal(normalized_block("   \n# only\n"), "\n")


def test_a_constant_array_literal_list_is_exact() raises:
    """One signed decimal array keeps its source spelling."""
    var source = String(
        '"""comptime _GL_NODES: Array[Float64, 2] = [9.0, 9.0]"""\n'
        + "comptime _GL_NODES: Array[Float64, 2] = [1.0, -2.5]\n"
    )
    assert_equal(
        constant_literals_json(source, "_GL_NODES", "array", 2),
        '["1.0","-2.5"]',
    )
    with assert_raises(contains="unsupported constant literal: _GL_NODES"):
        _ = constant_literals_json(
            "comptime _GL_NODES: Array[Float64, 1] = [1 .0]\n",
            "_GL_NODES",
            "array",
            1,
        )
    with assert_raises(contains="missing or ambiguous scalar: _PHASE_LIMIT"):
        _ = constant_literals_json(
            "comptime _PHASE_LIMIT = Float64(1.0)\n"
            + "comptime _PHASE_LIMIT = Float64(2.0)\n",
            "_PHASE_LIMIT",
            "scalar",
            0,
        )


def test_one_executable_fragment_is_replaced() raises:
    """A comment does not hide the executable assignment."""
    var source = String(
        "def f():\n"
        + "    # terms += center_work\n"
        + "    terms += center_work\n"
        + "    return terms\n"
    )
    assert_equal(
        replace_token_fragment(source, "terms += center_work", "terms += 0"),
        "def f():\n"
        + "    # terms += center_work\n"
        + "    terms += 0\n"
        + "    return terms\n",
    )
    with assert_raises(
        contains="missing or ambiguous executable mutation fragment: terms += 0"
    ):
        _ = replace_token_fragment(source, "terms += 0", "terms += 1")


def test_a_generic_declaration_becomes_python_source() raises:
    """`struct` becomes `class`, and the parameter list is metadata."""
    var source = String(
        "struct Box[T: Int]:\n"
        + "    def value[\n"
        + "        derivatives: Bool,\n"
        + "    ]() -> Int:\n"
        + "        var number = 1\n"
        + "        return number\n"
    )
    var document = python_syntax_json(source)
    if document.find('"class"') < 0 or document.find('"struct"') >= 0:
        raise Error(document)
    if document.find("derivatives") < 0 or document.find("var ") >= 0:
        raise Error(document)
    if document.find("def value") < 0 or document.find("return number") < 0:
        raise Error(document)


def test_a_repeated_generic_name_is_refused() raises:
    """Two generic declarations with the same name fail closed."""
    with assert_raises(contains="ambiguous generic declaration"):
        _ = python_syntax_json(
            "def value[T: Int]():\n    return 1\n\n"
            + "def value[U: Int]():\n    return 2\n"
        )


def test_a_stored_word_routing_masks_the_right_hand_side() raises:
    """A named comptime declaration keeps only the tokens through equals."""
    var source = "comptime _GL_NODES: Array[Float64, 5] = [0.0]\n"
    assert_equal(
        module_routing_json(source, '["_GL_NODES"]'),
        '[[["NAME","comptime"],["NAME","_GL_NODES"],["OP",":"],'
        + '["NAME","Array"],["OP","["],["NAME","Float64"],["OP",","],'
        + '["NUMBER","5"],["OP","]"],["OP","="],["STORED_WORDS","_GL_NODES"]]]',
    )


def test_a_module_docstring_is_not_a_top_level_statement() raises:
    """The opening module string is omitted from the statement list."""
    var source = String('"""Module."""\n' + "def first():\n" + "    return 1\n")
    assert_equal(
        module_statements_json(source),
        '[[["NAME","def"],["NAME","first"],["OP","("],["OP",")"],["OP",":"]]]',
    )


def test_argument_move_sigils_are_removed() raises:
    """A postfix move sigil before a comma or parenthesis is removed."""
    var source = "def f(road^, section^):\n    return road\n"
    var plain = without_move_sigils(source)
    if plain.find("^") >= 0:
        raise Error(plain)
    var names = token_names(plain)
    var saw_road = False
    var saw_section = False
    for name in names:
        if name == "road":
            saw_road = True
        if name == "section":
            saw_section = True
    if not saw_road or not saw_section:
        raise Error("argument name missing")


def test_a_comment_does_not_change_significant_tokens() raises:
    """A comment is not part of the significant token list."""
    var source = "def first():\n    return 1\n"
    if significant_json(source) != significant_json(source + "# note\n"):
        raise Error("comment changed the significant tokens")
    if significant_json(source) == significant_json(
        "def first():\n    return 2\n"
    ):
        raise Error("changed body kept the significant tokens")


def test_a_struct_method_keeps_its_declaration() raises:
    """A module function and a struct method keep the Python declaration text.
    """
    var source = String(
        "def first():\n    return 1\n\nstruct Owner:\n    def second():\n"
        + "        return 2\n"
    )
    var none = List[String]()
    var place = declaration_place(source, "first", none)
    assert_equal(place.text, "def first():\n    return 1\n\n")
    if place.first != 0 or place.last != 3:
        raise Error("first declaration span changed")
    assert_equal(
        declaration_text(source, "first", List[String]()),
        "def first():\n    return 1\n\n",
    )
    var owner = List[String]()
    owner.append("Owner")
    assert_equal(
        declaration_text(source, "second", owner),
        "def second():\n    return 2\n",
    )
    var wrong = List[String]()
    with assert_raises(contains="guard caller owner/scope changed: second"):
        _ = declaration_text(source, "second", wrong)


def test_a_repeated_premise_fragment_is_refused() raises:
    """A premise fragment that occurs twice fails closed."""
    var directory = "/tmp/cleanup-premises-test"
    makedirs(directory, exist_ok=True)
    Path(directory + "/labels.json").write_text(
        '[{"label":"ordered finite domain premise","fragments":'
        + '["_rounded_operand(low)"]}]'
    )
    Path(directory + "/0.mojo").write_text(
        "def bounds():\n"
        + "    _rounded_operand(low)\n"
        + "    _rounded_operand(low)\n"
    )
    with assert_raises(
        contains=(
            "reviewed cleanup source contract: ordered finite domain premise"
        )
    ):
        cleanup_premises(directory)


def test_a_decimal_literal_rounds_to_binary64() raises:
    """Signed zero, one tenth, and an exact fraction keep their words."""
    assert_equal(
        decimal_words_json(
            '["0.0","-0.0","0.1","-0.1","1/2","-1/3","2/4","-0/1"]'
        ),
        (
            '["0x0000000000000000","0x8000000000000000",'
            + '"0x3FB999999999999A","0xBFB999999999999A",'
            + '"0x3FE0000000000000","0xBFD5555555555555",'
            + '"0x3FE0000000000000","0x8000000000000000"]'
        ),
    )


def test_the_token_digest_matches_cpython() raises:
    """The kept-token digest matches CPython 3.12 for one function."""
    assert_equal(
        token_sha256("def first():\n    return 1\n"),
        "28885cd8303bb65249ae7f3f82d218953cc86334e26246f61262bd8c61fe613a",
    )


def test_text_digests_match_sha256() raises:
    """Each text digest matches SHA-256 of its UTF-8 bytes."""
    assert_equal(
        sha256_texts_json('["abc",""]'),
        '["ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"]',
    )


def test_a_function_dump_matches_cpython() raises:
    """One function dump matches CPython, including the generic mark."""
    var source = (
        "def f(geometry: RoadGeometry, d: _JetExpression[derivatives]) ->"
        " Tuple[Int, Int]:\n"
    )
    source += "    x = 1\n    while x < 2:\n        x += 1\n    return (x, d)\n"
    assert_equal(
        function_dump(source),
        '["FunctionDef",[["name","f"],["args",["arguments",[["posonlyargs",[]],["args",[["arg",[["arg","geometry"],["annotation",["Name",[["id","RoadGeometry"],["ctx",["Load",[]]]]]]]],["arg",[["arg","d"],["annotation",["Subscript",[["value",["Name",[["id","_JetExpression"],["ctx",["Load",[]]]]]],["slice",["Name",[["id","derivatives"],["ctx",["Load",[]]]]]],["ctx",["Load",[]]]]]]]]]],["kwonlyargs",[]],["kw_defaults",[]],["defaults",[]]]]],["body",[["Assign",[["targets",[["Name",[["id","x"],["ctx",["Store",[]]]]]]],["value",["Constant",[["value",1]]]]]],["While",[["test",["Compare",[["left",["Name",[["id","x"],["ctx",["Load",[]]]]]],["ops",[["Lt",[]]]],["comparators",[["Constant",[["value",2]]]]]]]],["body",[["AugAssign",[["target",["Name",[["id","x"],["ctx",["Store",[]]]]]],["op",["Add",[]]],["value",["Constant",[["value",1]]]]]]]],["orelse",[]]]],["Return",[["value",["Tuple",[["elts",[["Name",[["id","x"],["ctx",["Load",[]]]]],["Name",[["id","d"],["ctx",["Load",[]]]]]]],["ctx",["Load",[]]]]]]]]]],["decorator_list",[]],["returns",["Subscript",[["value",["Name",[["id","Tuple"],["ctx",["Load",[]]]]]],["slice",["Tuple",[["elts",[["Name",[["id","Int"],["ctx",["Load",[]]]]],["Name",[["id","Int"],["ctx",["Load",[]]]]]]],["ctx",["Load",[]]]]]],["ctx",["Load",[]]]]]],["mojo_type_parameters",[["NAME","derivatives"],["OP",":"],["NAME","Bool"]]]]]',
    )


def test_an_if_and_for_dump_matches_cpython() raises:
    """If, for, and a decorator dump match CPython."""
    assert_equal(
        plain_function_dump(
            "def f():\n    if a < 1 or not b:\n        return None\n"
        ),
        '["FunctionDef",[["name","f"],["args",["arguments",[["posonlyargs",[]],["args",[]],["kwonlyargs",[]],["kw_defaults",[]],["defaults",[]]]]],["body",[["If",[["test",["BoolOp",[["op",["Or",[]]],["values",[["Compare",[["left",["Name",[["id","a"],["ctx",["Load",[]]]]]],["ops",[["Lt",[]]]],["comparators",[["Constant",[["value",1]]]]]]],["UnaryOp",[["op",["Not",[]]],["operand",["Name",[["id","b"],["ctx",["Load",[]]]]]]]]]]]]],["body",[["Return",[["value",["Constant",[]]]]]]],["orelse",[]]]]]],["decorator_list",[]]]]',
    )
    assert_equal(
        plain_function_dump(
            "@no_inline\ndef f():\n    for piece in range(pieces):\n        x ="
            " piece\n"
        ),
        '["FunctionDef",[["name","f"],["args",["arguments",[["posonlyargs",[]],["args",[]],["kwonlyargs",[]],["kw_defaults",[]],["defaults",[]]]]],["body",[["For",[["target",["Name",[["id","piece"],["ctx",["Store",[]]]]]],["iter",["Call",[["func",["Name",[["id","range"],["ctx",["Load",[]]]]]],["args",[["Name",[["id","pieces"],["ctx",["Load",[]]]]]]],["keywords",[]]]]],["body",[["Assign",[["targets",[["Name",[["id","x"],["ctx",["Store",[]]]]]]],["value",["Name",[["id","piece"],["ctx",["Load",[]]]]]]]]]],["orelse",[]]]]]],["decorator_list",[["Name",[["id","no_inline"],["ctx",["Load",[]]]]]]]]]',
    )


def test_an_if_expression_and_annotation_match_cpython() raises:
    """An if-expression and an annotation dump match CPython."""
    assert_equal(
        plain_function_dump(
            "def f():\n    fixed = 26 if goal else 20\n    point_domain:"
            " Tuple[Int, Int]\n    x: Int = 1\n"
        ),
        '["FunctionDef",[["name","f"],["args",["arguments",[["posonlyargs",[]],["args",[]],["kwonlyargs",[]],["kw_defaults",[]],["defaults",[]]]]],["body",[["Assign",[["targets",[["Name",[["id","fixed"],["ctx",["Store",[]]]]]]],["value",["IfExp",[["test",["Name",[["id","goal"],["ctx",["Load",[]]]]]],["body",["Constant",[["value",26]]]],["orelse",["Constant",[["value",20]]]]]]]]],["AnnAssign",[["target",["Name",[["id","point_domain"],["ctx",["Store",[]]]]]],["annotation",["Subscript",[["value",["Name",[["id","Tuple"],["ctx",["Load",[]]]]]],["slice",["Tuple",[["elts",[["Name",[["id","Int"],["ctx",["Load",[]]]]],["Name",[["id","Int"],["ctx",["Load",[]]]]]]],["ctx",["Load",[]]]]]],["ctx",["Load",[]]]]]],["simple",1]]],["AnnAssign",[["target",["Name",[["id","x"],["ctx",["Store",[]]]]]],["annotation",["Name",[["id","Int"],["ctx",["Load",[]]]]]],["value",["Constant",[["value",1]]]],["simple",1]]]]],["decorator_list",[]]]]',
    )


def test_the_try_only_refusal_matches_the_reviewed_shape() raises:
    """The lane proof keeps one reviewed try-only refusal."""
    var source = String(
        "def _lane_jet_model_proof[capture: Bool](\n"
        + "    ideal_translation: Bool = False,\n"
        + "    require_reuse: Bool = False,\n"
        + ") -> Int:\n"
        + "    if reused:\n"
        + "        point = reused.value()\n"
        + "    elif require_reuse:\n"
        + "        return _unknown_point()\n"
        + "    else:\n"
        + "        point = 1\n"
        + "    return point\n"
    )
    try_only_refusal(source)
    with assert_raises(contains="try-only parameter changed"):
        try_only_refusal(
            source.replace("require_reuse: Bool = False", "reuse: Bool = False")
        )
    with assert_raises(
        contains="try-only default must preserve historical callers"
    ):
        try_only_refusal(
            source.replace(
                "require_reuse: Bool = False", "require_reuse: Bool = True"
            )
        )
    with assert_raises(
        contains="try-only refusal missing from reuse/fallback edge"
    ):
        try_only_refusal(
            source.replace(
                "    elif require_reuse:\n        return _unknown_point()\n", ""
            )
        )
    with assert_raises(contains="try-only refusal changed"):
        try_only_refusal(
            source.replace("return _unknown_point()", "return other()")
        )
    with assert_raises(contains="try-only flag has an unreviewed use"):
        try_only_refusal(source.replace("point = 1", "point = require_reuse"))


def test_a_statement_dump_matches_cpython() raises:
    """One expression statement dump matches CPython's normalized AST."""
    assert_equal(
        statement_dump("_require_sum2_environment()"),
        '["Expr",[["value",["Call",[["func",["Name",[["id","_require_sum2_environment"],["ctx",["Load",[]]]]]],["args",[]],["keywords",[]]]]]]]',
    )


def test_an_expression_dump_matches_cpython() raises:
    """One expression dump matches CPython's normalized AST."""
    assert_equal(
        expression_dump("_stored_half(rate)"),
        '["Call",[["func",["Name",[["id","_stored_half"],["ctx",["Load",[]]]]]],["args",[["Name",[["id","rate"],["ctx",["Load",[]]]]]]],["keywords",[]]]]',
    )
    assert_equal(expression_dump("False"), '["Constant",[["value",false]]]')
    assert_equal(expression_dump("0.0"), '["Constant",[["value",0.0]]]')
    assert_equal(
        expression_dump("1.0 + nodes[0]"),
        '["BinOp",[["left",["Constant",[["value",1.0]]]],["op",["Add",[]]],["right",["Subscript",[["value",["Name",[["id","nodes"],["ctx",["Load",[]]]]]],["slice",["Constant",[["value",0]]]],["ctx",["Load",[]]]]]]]]',
    )


def test_top_level_imports_keep_source_order() raises:
    """Top-level from-imports keep order and omit a nested import."""
    var source = String("from a.b import c, d as e\n")
    source += "def hidden():\n    from nested.mod import z\n"
    source += "from a.b import (\n    f,\n    g as h,\n)\n"
    source += "from .relative import item\n"
    assert_equal(
        _direct_imports_json(source),
        '[{"module":"a.b","names":[["c",""],["d","e"]]},{"module":"a.b","names":[["f",""],["g","h"]]},{"module":"relative","names":[["item",""]]}]',
    )


def test_the_stored_word_digest_matches_sha256() raises:
    """The stored-word digest is SHA-256 of the given bytes."""
    var digest = cleanup_sha(String("abc").as_bytes())
    if (
        digest
        != "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    ):
        raise Error(digest)


def main() raises:
    """Run the reviewed cleanup gate tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
