# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The CARLA quantity inventory check reads public declarations exactly.

Each test writes a small `extensions/carla/` tree and an inventory.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
)

from tests._tree import Tree
from tools.check_carla_quantity_inventory import (
    INVENTORY,
    check,
    declarations,
    selected,
)

comptime HEADER = (
    "file\tsymbol\tmember\ttype\tkind\tline\tclassification\tunit_or_meaning"
    "\ttyped_boundary\traw_adapter\tvalidation\trationale\n"
)

comptime SOURCE = (
    '"""A module.\n\nstruct Hidden:\n    var x: Float64\n"""\n'
    + "comptime Length = Quantity[1]\n"
    + "struct Sensor:\n"
    + "    var range: Length\n"
    + "    var _secret: Float64\n"
    + "    var count: Int\n"
    + "    var table: Dict[\n"
    + "        String, Float32\n"
    + "    ]\n"
    + "    def __init__(out self, var range: Length, rate: Float64 = 1.0):\n"
    + "        pass\n"
    + "    def _private(self, x: Float64):\n"
    + "        pass\n"
    + "    def scale(\n"
    + "        self, factor: DType.float32, items: List[Tuple[Int, Float64]]\n"
    + "    ) -> Float64:\n"
    + "        return 1.0\n"
    + "struct _Raw:\n"
    + "    var value: Float64\n"
    + "    def get(self) -> Float64:\n"
    + "        return self.value\n"
    + "def free(value: Float64Plus, raw: _RawSI) -> Float64:\n"
    + "    return 1.0\n"
    + "def speed_value(x: Int) -> Int:\n"
    + "    var local: Float64 = 1\n"
    + "    return x\n"
)


def _tree() raises -> Tree:
    """Return a tree with one CARLA module and the quantity aliases."""
    var tree = Tree()
    tree.write(
        "units/length.mojo",
        "comptime Length = Quantity[Meter]\ncomptime Plain = Int\n",
    )
    tree.write(
        "extensions/physics/quantities.mojo",
        "comptime Force =  Quantity[Newton]\n",
    )
    tree.write("extensions/carla/v2x.mojo", SOURCE)
    return tree^


def _keys(tree: Tree) raises -> String:
    """Return each selected row as `symbol member type kind line`."""
    var lines = List[String]()
    for row in selected(tree.root):
        lines.append(
            row.symbol
            + " "
            + row.member
            + " "
            + row.type
            + " "
            + row.kind
            + " "
            + String(row.line)
        )
    return "\n".join(lines)


def test_selects_floats_quantities_and_named_integers() raises:
    var tree = _tree()
    assert_equal(
        _keys(tree),
        "Sensor range Length field 8\n"
        + "Sensor table Dict[ String, Float32 ] field 11\n"
        + "Sensor.__init__ range Length parameter 14\n"
        + "Sensor.__init__ rate Float64 parameter 14\n"
        + "Sensor.scale factor DType.float32 parameter 18\n"
        + "Sensor.scale items List[Tuple[Int, Float64]] parameter 18\n"
        + "Sensor.scale return Float64 return 18\n"
        + "speed_value return Int return 28",
    )
    # Every public declaration is read; the selection keeps the quantities.
    assert_equal(len(declarations(tree.root)), 10)
    tree.close()


def _inventory(
    tree: Tree, var skip: Int = -1, classification: String = "typed-boundary"
) raises:
    """Write an inventory of the selection, without row `skip`."""
    var text = String(HEADER)
    var index = 0
    for row in selected(tree.root):
        if index != skip:
            text += (
                row.file
                + "\t"
                + row.symbol
                + "\t"
                + row.member
                + "\t"
                + row.type
                + "\t"
                + row.kind
                + "\t"
                + String(row.line)
                + "\t"
                + classification
                + "\tm\tb\tr\tv\twhy\n"
            )
        index += 1
    tree.write(INVENTORY, text)


def test_a_complete_inventory_passes() raises:
    var tree = _tree()
    _inventory(tree)
    var outcome = check(tree.root, False)
    assert_equal(outcome[0], 0, outcome[1])
    assert_true(outcome[1].startswith("PASS: 8 current public"))
    tree.close()


def test_missing_stale_and_unreviewed_rows_fail() raises:
    var tree = _tree()
    _inventory(tree, 0, "guess")
    var text = (
        tree.read(INVENTORY)
        + "extensions/carla/v2x.mojo\tOld\tx\tFloat64\tfield\t1\ttyped-boundary\tm\tb\tr\tv\t\n"
    )
    tree.write(INVENTORY, text)
    var outcome = check(tree.root, False)
    assert_equal(outcome[0], 1)
    var lines = outcome[1].split("\n")
    assert_equal(
        String(lines[0]),
        (
            "Missing 1 declaration(s): ('extensions/carla/v2x.mojo', 'Sensor',"
            " 'range', 'Length', 'field')"
        ),
    )
    assert_equal(
        String(lines[1]),
        (
            "Stale 1 declaration(s): ('extensions/carla/v2x.mojo', 'Old', 'x',"
            " 'Float64', 'field')"
        ),
    )
    assert_true(
        outcome[1].find(
            "Unreviewed classification: ('extensions/carla/v2x.mojo', 'Sensor',"
            " 'table'"
        )
        >= 0
    )
    assert_true(
        outcome[1].find(
            "Missing rationale: ('extensions/carla/v2x.mojo', 'Old'"
        )
        >= 0
    )
    tree.close()


def test_refresh_lines_rewrites_only_the_line_numbers() raises:
    var tree = _tree()
    _inventory(tree)
    var expected = tree.read(INVENTORY)
    tree.write(
        INVENTORY,
        expected.replace("\t8\ttyped", "\t1\ttyped").replace(
            "\t28\ttyped", "\t2\ttyped"
        ),
    )
    var outcome = check(tree.root, True)
    assert_equal(outcome[0], 0, outcome[1])
    assert_equal(tree.read(INVENTORY), expected)
    tree.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
