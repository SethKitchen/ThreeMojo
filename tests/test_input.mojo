# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `controls.input`: the event types and the terminal decoder."""

from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    ESCAPE,
    InputDecoder,
    InputEvent,
    InputKind,
    KEY_DOWN,
    Key,
    MIDDLE,
    NO_BUTTON,
    NO_KEY,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    RESIZE,
    SECONDARY,
    WHEEL,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true


def _decode(mut decoder: InputDecoder, text: String) -> List[InputEvent]:
    """Feed a decoder the bytes of `text`.

    Args:
        decoder: The decoder.
        text: The bytes.

    Returns:
        The events.
    """
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    return decoder.feed(bytes)


def _one(text: String) raises -> InputEvent:
    """Decode `text` with a new decoder and return its only event.

    Args:
        text: The bytes.

    Returns:
        The event.

    Raises:
        Error: If there is not exactly one.
    """
    var decoder = InputDecoder()
    var events = _decode(decoder, text)
    assert_equal(len(events), 1)
    return events[0]


def test_the_types_know_their_values() raises:
    assert_true(KEY_DOWN.is_valid())
    assert_true(WHEEL.is_valid())
    assert_false(InputKind(-1).is_valid())
    assert_false(InputKind(7).is_valid())
    assert_true(NO_BUTTON.is_valid())
    assert_true(SECONDARY.is_valid())
    assert_false(PointerButton(-2).is_valid())
    assert_false(PointerButton(3).is_valid())
    assert_true(Key(65).is_valid())
    assert_true(Key(127).is_valid())
    assert_true(ARROW_UP.is_valid())
    assert_true(ARROW_RIGHT.is_valid())
    assert_true(NO_KEY.is_valid())
    assert_false(Key(-2).is_valid())
    assert_false(Key(128).is_valid())
    assert_false(Key(300).is_valid())


def test_a_byte_is_its_key() raises:
    var event = _one("q")
    assert_true(event.kind == KEY_DOWN)
    assert_true(event.key == Key(113))
    assert_true(event.button == NO_BUTTON)
    assert_true(_one("\x03").key == Key(3))


def test_a_byte_past_ascii_is_dropped() raises:
    var decoder = InputDecoder()
    var events = _decode(decoder, "é")
    assert_equal(len(events), 0)
    assert_equal(len(decoder.pending), 0)


def test_an_escape_alone_is_the_escape_key() raises:
    assert_true(_one("\x1b").key == ESCAPE)
    # An escape before anything but a bracket is the key, then that key.
    var decoder = InputDecoder()
    var events = _decode(decoder, "\x1bx")
    assert_equal(len(events), 2)
    assert_true(events[0].key == ESCAPE)
    assert_true(events[1].key == Key(120))


def test_the_arrows() raises:
    assert_true(_one("\x1b[A").key == ARROW_UP)
    assert_true(_one("\x1b[B").key == ARROW_DOWN)
    assert_true(_one("\x1b[C").key == ARROW_RIGHT)
    assert_true(_one("\x1b[D").key == ARROW_LEFT)
    var plain = _one("\x1b[A")
    assert_false(plain.shift or plain.alt or plain.ctrl)


def test_an_arrow_carries_its_modifiers() raises:
    var shifted = _one("\x1b[1;2A")
    assert_true(shifted.shift)
    assert_false(shifted.alt)
    assert_false(shifted.ctrl)
    var alt = _one("\x1b[1;3B")
    assert_true(alt.alt)
    var ctrl = _one("\x1b[1;5C")
    assert_true(ctrl.ctrl)
    assert_false(ctrl.shift)
    # Parameters that are not numbers carry no modifiers.
    var odd = _one("\x1b[?D")
    assert_true(odd.key == ARROW_LEFT)
    assert_false(odd.shift)


def test_a_sequence_it_does_not_know_is_dropped() raises:
    var decoder = InputDecoder()
    # Function key F5, a bare `M`, and a mouse report of the wrong shape.
    var events = _decode(decoder, "\x1b[15~\x1b[M\x1b[<1;2x\x1b[<0;1Mq")
    assert_equal(len(events), 1)
    assert_true(events[0].key == Key(113))
    assert_equal(len(decoder.pending), 0)


def test_a_press_a_drag_and_a_release() raises:
    var press = _one("\x1b[<0;10;5M")
    assert_true(press.kind == POINTER_DOWN)
    assert_true(press.button == PRIMARY)
    assert_equal(press.x, 9)
    assert_equal(press.y, 4)
    var drag = _one("\x1b[<34;11;5M")
    assert_true(drag.kind == POINTER_MOVE)
    assert_true(drag.button == SECONDARY)
    var hover = _one("\x1b[<35;1;1M")
    assert_true(hover.kind == POINTER_MOVE)
    assert_true(hover.button == NO_BUTTON)
    var release = _one("\x1b[<1;11;5m")
    assert_true(release.kind == POINTER_UP)
    assert_true(release.button == MIDDLE)


def test_a_mouse_report_carries_its_modifiers() raises:
    var event = _one("\x1b[<28;1;1M")
    assert_true(event.shift)
    assert_true(event.alt)
    assert_true(event.ctrl)
    assert_true(event.button == PRIMARY)
    var bare = _one("\x1b[<0;1;1M")
    assert_false(bare.shift or bare.alt or bare.ctrl)


def test_a_wheel_notch() raises:
    var away = _one("\x1b[<64;3;3M")
    assert_true(away.kind == WHEEL)
    assert_equal(away.wheel, -1)
    var toward = _one("\x1b[<65;3;3M")
    assert_equal(toward.wheel, 1)
    assert_equal(toward.x, 2)


def test_a_split_sequence_waits_for_the_rest() raises:
    var decoder = InputDecoder()
    assert_equal(len(_decode(decoder, "\x1b[")), 0)
    assert_equal(len(decoder.pending), 2)
    assert_equal(len(_decode(decoder, "<0;4")), 0)
    var events = _decode(decoder, ";7Ma")
    assert_equal(len(events), 2)
    assert_true(events[0].kind == POINTER_DOWN)
    assert_equal(events[0].x, 3)
    assert_true(events[1].key == Key(97))
    assert_equal(len(decoder.pending), 0)
    # Nothing new decodes nothing.
    assert_equal(len(decoder.feed(List[UInt8]())), 0)


def test_an_endless_sequence_is_dropped() raises:
    var decoder = InputDecoder()
    var noise = String("\x1b[")
    for _ in range(70):
        noise += "1"
    assert_equal(len(_decode(decoder, noise)), 0)
    assert_equal(len(decoder.pending), 0)


def test_the_terminals_size_report_is_a_resize() raises:
    var size = _one("\x1b[8;24;80t")
    assert_true(size.kind == RESIZE)
    assert_equal(size.x, 80)
    assert_equal(size.y, 24)
    var decoder = InputDecoder()
    # Another report, and one of the wrong shape, are dropped.
    assert_equal(len(_decode(decoder, "\x1b[4;480;640t")), 0)
    assert_equal(len(_decode(decoder, "\x1b[8;24t")), 0)
    assert_true(RESIZE.is_valid())
    assert_false(InputKind(6).is_valid())


def test_an_event_holds_what_it_is_given() raises:
    var event = InputEvent(
        POINTER_UP,
        key=Key(1),
        button=MIDDLE,
        x=3,
        y=4,
        wheel=2,
        shift=True,
        alt=True,
        ctrl=True,
    )
    assert_true(event.kind == POINTER_UP)
    assert_true(event.key == Key(1))
    assert_equal(event.x + event.y + event.wheel, 9)
    assert_true(event.shift and event.alt and event.ctrl)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
