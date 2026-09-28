# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.usd_specs`: the layer's specs, and its values read
as JavaScript reads them."""

from loaders.usd_specs import (
    NO_VALUE,
    SPEC_ATTRIBUTE,
    SPEC_PRIM,
    SpecType,
    USD_ARRAY,
    USD_BOOLEAN,
    USD_NULL,
    USD_NUMBER,
    USD_NUMBERS,
    USD_OBJECT,
    USD_SAMPLES,
    USD_STRING,
    USD_STRINGS,
    USD_UNDEFINED,
    UsdKind,
    UsdLayer,
    UsdSpec,
    UsdValue,
    usd_boolean,
    usd_number,
    usd_numbers,
    usd_string,
    usd_strings,
)
from std.math import isnan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def _array(mut layer: UsdLayer, var items: List[Int]) raises -> Int:
    """Keep an array of other values."""
    var out = UsdValue(USD_ARRAY)
    out.items = items^
    return layer.add(out^)


def test_types_are_checked() raises:
    assert_true(SpecType(0).is_valid())
    assert_true(SpecType(11).is_valid())
    assert_false(SpecType(12).is_valid())
    assert_false(SpecType(-1).is_valid())
    assert_true(UsdKind(9).is_valid())
    assert_false(UsdKind(10).is_valid())
    assert_false(UsdKind(-1).is_valid())
    var layer = UsdLayer()
    with assert_raises(contains="no kind"):
        _ = layer.add(UsdValue(UsdKind(10)))


def test_specs() raises:
    var spec = UsdSpec(SPEC_PRIM)
    assert_equal(spec.field("a"), NO_VALUE)
    spec.set("a", 3)
    spec.set("b", 4)
    spec.set("a", 5)
    assert_equal(spec.field("a"), 5)
    assert_equal(spec.names[0], "a")
    var layer = UsdLayer()
    assert_equal(layer.spec("/x"), -1)
    assert_equal(layer.field("/x", "a"), NO_VALUE)
    assert_equal(layer.put("/x", spec^), 0)
    assert_equal(layer.put("/y", UsdSpec(SPEC_ATTRIBUTE)), 1)
    # Setting a path again keeps its place.
    assert_equal(layer.put("/x", UsdSpec(SPEC_ATTRIBUTE)), 0)
    assert_true(layer.specs[0].spec_type == SPEC_ATTRIBUTE)
    assert_equal(layer.field("/x", "a"), NO_VALUE)


def test_truthiness() raises:
    var layer = UsdLayer()
    assert_false(layer.truthy(NO_VALUE))
    assert_false(layer.defined(NO_VALUE))
    assert_false(layer.truthy(layer.add(UsdValue(USD_UNDEFINED))))
    assert_false(layer.truthy(layer.add(UsdValue(USD_NULL))))
    assert_true(layer.defined(layer.add(UsdValue(USD_NULL))))
    assert_true(layer.truthy(layer.add(usd_boolean(True))))
    assert_false(layer.truthy(layer.add(usd_boolean(False))))
    assert_false(layer.truthy(layer.add(usd_number(0))))
    assert_false(layer.truthy(layer.add(usd_number(Float64(0) / Float64(0)))))
    assert_true(layer.truthy(layer.add(usd_number(-2))))
    assert_false(layer.truthy(layer.add(usd_string(""))))
    assert_true(layer.truthy(layer.add(usd_string("a"))))
    assert_true(layer.truthy(layer.add(UsdValue(USD_NUMBERS))))


def test_kinds() raises:
    var layer = UsdLayer()
    var numbers = layer.add(usd_numbers([1, 2]))
    var strings = layer.add(usd_strings(["a"]))
    var array = _array(layer, List[Int]())
    var text = layer.add(usd_string("héllo"))
    var number = layer.add(usd_number(1.5))
    var object = layer.add(UsdValue(USD_OBJECT))
    for id in [numbers, strings, array]:
        assert_true(layer.is_array(id))
    assert_false(layer.is_array(text))
    assert_true(layer.is_string(text))
    assert_false(layer.is_string(number))
    assert_true(layer.is_number(number))
    assert_false(layer.is_number(text))
    assert_equal(layer.number(number), 1.5)
    assert_equal(layer.text(text), "héllo")
    assert_equal(layer.length(numbers), 2)
    assert_equal(layer.length(strings), 1)
    assert_equal(layer.length(array), 0)
    assert_equal(layer.length(text), 5)
    assert_equal(layer.length(object), -1)
    assert_true(layer.kind(NO_VALUE) == USD_UNDEFINED)


def test_numbers_as_javascript_reads_them() raises:
    var layer = UsdLayer()
    assert_equal(layer.to_number(layer.add(usd_number(2))), 2)
    assert_equal(layer.to_number(layer.add(usd_boolean(True))), 1)
    assert_equal(layer.to_number(layer.add(usd_string(" 7 "))), 7)
    assert_equal(layer.to_number(layer.add(UsdValue(USD_NULL))), 0)
    assert_true(isnan(layer.to_number(NO_VALUE)))
    assert_true(isnan(layer.to_number(layer.add(UsdValue(USD_OBJECT)))))
    assert_equal(layer.to_number(layer.add(UsdValue(USD_NUMBERS))), 0)
    assert_equal(layer.to_number(layer.add(usd_numbers([4]))), 4)
    assert_true(isnan(layer.to_number(layer.add(usd_numbers([4, 5])))))
    assert_equal(layer.to_number(layer.add(usd_strings(["6"]))), 6)
    # `[ x ]` reads as the text of `x` reads.
    var null = layer.add(UsdValue(USD_NULL))
    assert_equal(layer.to_number(_array(layer, [null])), 0)
    var undefined = layer.add(UsdValue(USD_UNDEFINED))
    assert_equal(layer.to_number(_array(layer, [undefined])), 0)
    var yes = layer.add(usd_boolean(True))
    assert_true(isnan(layer.to_number(_array(layer, [yes]))))
    var object = layer.add(UsdValue(USD_OBJECT))
    assert_true(isnan(layer.to_number(_array(layer, [object]))))
    var samples = layer.add(UsdValue(USD_SAMPLES))
    assert_true(isnan(layer.to_number(_array(layer, [samples]))))
    var eight = layer.add(usd_string("8"))
    assert_equal(layer.to_number(_array(layer, [eight])), 8)
    var nine = layer.add(usd_numbers([9]))
    assert_equal(layer.to_number(_array(layer, [nine])), 9)


def test_elements() raises:
    var layer = UsdLayer()
    var numbers = layer.add(usd_numbers([1, 2]))
    var strings = layer.add(usd_strings(["3", "x"]))
    var word = layer.add(usd_string("w"))
    var one = layer.add(usd_number(1))
    var array = _array(layer, [word, one])
    assert_equal(layer.element_number(numbers, 1), 2)
    assert_true(isnan(layer.element_number(numbers, 2)))
    assert_true(isnan(layer.element_number(numbers, -1)))
    assert_equal(layer.element_number(strings, 0), 3)
    assert_equal(layer.element_number(array, 1), 1)
    assert_equal(layer.element_string(strings, 1).value(), "x")
    assert_false(Bool(layer.element_string(strings, 2)))
    assert_false(Bool(layer.element_string(strings, -1)))
    assert_equal(layer.element_string(array, 0).value(), "w")
    assert_false(Bool(layer.element_string(array, 1)))
    assert_false(Bool(layer.element_string(numbers, 0)))
    var copied = layer.numbers(numbers)
    assert_equal(copied[1], 2)
    var read = layer.numbers(strings)
    assert_equal(read[0], 3)
    assert_true(isnan(read[1]))
    assert_equal(len(layer.numbers(layer.add(usd_strings(List[String]())))), 0)


def test_objects() raises:
    var layer = UsdLayer()
    var red = layer.add(usd_string("red"))
    var object = UsdValue(USD_OBJECT)
    object.strings = ["color", "size"]
    object.items = [red, NO_VALUE]
    var id = layer.add(object^)
    assert_equal(layer.object_value(id, "color"), red)
    assert_equal(layer.object_value(id, "shape"), NO_VALUE)
    assert_equal(layer.object_value(red, "color"), NO_VALUE)
    var empty = layer.add(UsdValue(USD_OBJECT))
    assert_equal(layer.object_value(empty, "color"), NO_VALUE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
