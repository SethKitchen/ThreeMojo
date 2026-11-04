# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mouse in the village: a drag looks, and a click strikes."""

from controls.input import (
    InputEvent,
    InputKind,
    PointerButton,
    KEY_DOWN,
    MIDDLE,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    SECONDARY,
)
from extensions.village.character import no_input
from extensions.village.mouse import DRAG, MOUSE_TURN, MouseLook
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def _at(kind: InputKind, x: Int, y: Int, button: PointerButton) -> InputEvent:
    return InputEvent(kind, button=button, x=x, y=y)


def test_a_drag_looks_and_a_click_strikes() raises:
    var mouse = MouseLook()
    # A move with no button held does nothing.
    mouse.event(_at(POINTER_MOVE, 50, 50, PRIMARY))
    var still = no_input()
    mouse.apply(still)
    assert_equal(still.look_right, 0)
    # A drag turns the look, as far as the stick leans, and is no click.
    mouse.event(_at(POINTER_DOWN, 10, 10, SECONDARY))
    mouse.event(_at(POINTER_MOVE, 20, 4, SECONDARY))
    var looked = no_input()
    mouse.apply(looked)
    assert_almost_equal(looked.look_right, 10 * MOUSE_TURN, atol=1e-6)
    assert_almost_equal(looked.look_up, 6 * MOUSE_TURN, atol=1e-6)
    mouse.event(_at(POINTER_MOVE, 200, 4, SECONDARY))
    var far = no_input()
    mouse.apply(far)
    assert_equal(far.look_right, 1)
    mouse.event(_at(POINTER_UP, 200, 4, SECONDARY))
    var after = no_input()
    mouse.apply(after)
    assert_false(after.heavy)
    # A click of the primary button is a light attack, of the secondary a
    # heavy one, and of the middle nothing.
    mouse.event(_at(POINTER_DOWN, 5, 5, PRIMARY))
    mouse.event(_at(POINTER_MOVE, 6, 5, PRIMARY))
    mouse.event(_at(POINTER_UP, 6, 5, PRIMARY))
    var light = no_input()
    mouse.apply(light)
    assert_true(light.light)
    assert_false(light.heavy)
    mouse.event(_at(POINTER_DOWN, 5, 5, SECONDARY))
    mouse.event(_at(POINTER_UP, 5, 5, SECONDARY))
    var heavy = no_input()
    mouse.apply(heavy)
    assert_true(heavy.heavy)
    mouse.event(_at(POINTER_DOWN, 5, 5, MIDDLE))
    mouse.event(_at(POINTER_UP, 5, 5, MIDDLE))
    var middle = no_input()
    mouse.apply(middle)
    assert_false(middle.light or middle.heavy)
    # A release with no press, and a key, do nothing.
    mouse.event(_at(POINTER_UP, 5, 5, PRIMARY))
    mouse.event(InputEvent(KEY_DOWN))
    var none = no_input()
    mouse.apply(none)
    assert_false(none.light)
    _ = DRAG


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
