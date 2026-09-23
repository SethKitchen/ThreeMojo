# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.user_data`, three.js's `Object3D.userData`.

The expected texts are what `JSON.stringify` writes for the same values,
except where the module docstring says the form of a number differs.
"""

from core.user_data import (
    UserData,
    json_number_text,
    json_value_text,
    user_data_of,
)
from loaders.json import (
    ARRAY,
    BOOLEAN,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    parse_json,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_a_new_map_is_empty() raises:
    var data = UserData()
    assert_equal(data.count(), 0)
    assert_equal(data.to_json(), "{}")
    assert_false(data.has("a"))


def test_numbers_are_written_as_json_stringify_writes_whole_ones() raises:
    assert_equal(json_number_text(3), "3")
    assert_equal(json_number_text(-0.0), "0")
    assert_equal(json_number_text(-12), "-12")
    assert_equal(json_number_text(0.5), "0.5")
    assert_equal(json_number_text(9007199254740991.0), "9007199254740991")
    # At two to the fifty-three and past it, Mojo's own form.
    assert_equal(json_number_text(9007199254740992.0), "9007199254740992.0")
    assert_equal(json_number_text(1e300), "1e+300")
    with assert_raises(contains="finite"):
        _ = json_number_text(inf[DType.float64]())
    with assert_raises(contains="finite"):
        _ = json_number_text(nan[DType.float64]())


def test_every_kind_of_value_is_written_back_as_json() raises:
    var document = parse_json(
        '{"a": [1, 2.5, "x\\n"], "b": {"c": true, "d": false}, "e": null,'
        ' "f": [], "g": {}}'
    )
    assert_equal(
        json_value_text(document, 0),
        '{"a":[1,2.5,"x\\n"],"b":{"c":true,"d":false},"e":null,"f":[],"g":{}}',
    )


def test_a_key_named_twice_keeps_its_first_place_and_last_value() raises:
    # `JSON.parse('{"a":1,"b":2,"a":3}')` stringifies as `{"a":3,"b":2}`.
    var document = parse_json('{"a": 1, "b": 2, "a": 3}')
    assert_equal(json_value_text(document, 0), '{"a":3,"b":2}')
    assert_equal(user_data_of(document, 0).to_json(), '{"a":3,"b":2}')


def test_each_setter_and_reader() raises:
    var data = UserData()
    data.set_number("hp", 12.5)
    data.set_string("name", 'say "hi"')
    data.set_boolean("solid", True)
    data.set_null("owner")
    data.set_json("spawn", ' { "x" : 1 , "y" : [ 2 ] } ')
    assert_equal(data.count(), 5)
    assert_equal(data.key(0), "hp")
    assert_equal(data.key(4), "spawn")
    assert_equal(data.number("hp"), 12.5)
    assert_equal(data.string("name"), 'say "hi"')
    assert_true(data.boolean("solid"))
    assert_equal(data.kind("owner"), NULL)
    assert_equal(data.kind("spawn"), OBJECT)
    assert_equal(data.kind("hp"), NUMBER)
    assert_equal(data.kind("name"), STRING)
    assert_equal(data.kind("solid"), BOOLEAN)
    assert_equal(data.json("spawn"), '{"x":1,"y":[2]}')
    assert_equal(
        data.to_json(),
        '{"hp":12.5,"name":"say \\"hi\\"","solid":true,"owner":null,'
        + '"spawn":{"x":1,"y":[2]}}',
    )


def test_setting_a_key_again_keeps_its_place() raises:
    var data = UserData()
    data.set_number("a", 1)
    data.set_number("b", 2)
    data.set_json("a", "[3]")
    assert_equal(data.to_json(), '{"a":[3],"b":2}')
    assert_equal(data.kind("a"), ARRAY)


def test_a_key_is_removed() raises:
    var data = UserData()
    data.set_number("a", 1)
    data.set_number("b", 2)
    assert_true(data.remove("a"))
    assert_false(data.remove("a"))
    assert_equal(data.to_json(), '{"b":2}')


def test_a_copy_is_its_own() raises:
    var data = UserData()
    data.set_number("a", 1)
    var copy = UserData(copy=data)
    copy.set_number("a", 2)
    assert_equal(data.number("a"), 1)
    assert_equal(copy.number("a"), 2)


def test_what_is_not_there_or_not_json_is_refused() raises:
    var data = UserData()
    data.set_string("s", "text")
    with assert_raises(contains="no key"):
        _ = data.json("missing")
    with assert_raises(contains="no key at position"):
        _ = data.key(-1)
    with assert_raises(contains="no key at position"):
        _ = data.key(1)
    with assert_raises(contains="expected a number"):
        _ = data.number("s")
    with assert_raises():
        data.set_json("bad", "{nope}")
    with assert_raises(contains="finite"):
        data.set_number("bad", inf[DType.float64]())
    assert_false(data.has("bad"))
    with assert_raises(contains="JSON object"):
        _ = user_data_of(parse_json("[1]"), 0)
    assert_equal(user_data_of(parse_json("{}"), 0).count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
