# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Input events, and a decoder that reads them from a terminal's bytes.

three.js takes its input from the browser: `pointerdown`, `pointermove`,
`pointerup`, `wheel` and `keydown` events on a canvas. A terminal sends
bytes instead. A key is its own byte, an arrow is an escape sequence, and
a mouse, once asked to report, sends xterm's SGR sequences:

    ESC [ < button ; column ; row M     a press, a drag or a wheel notch
    ESC [ < button ; column ; row m     a release

`InputDecoder` turns those bytes into `InputEvent`s, five of the kinds the
browser has and a resize. The sixth browser kind, `KEY_UP`, is one a
terminal never sends. A terminal asked `ESC [ 18 t` answers
`ESC [ 8 ; rows ; columns t`, which is the resize. A sequence split across two reads is kept until the rest
arrives. A sequence this decoder does not know is consumed and dropped.

A position is a terminal cell: its column and its row, from zero. The
window that reads the bytes converts a cell to the pixels it shows.
"""

comptime ESCAPE_BYTE = 27
# '[' opens a control sequence after an escape.
comptime BRACKET_BYTE = 91
# '<' opens the parameters of an SGR mouse report.
comptime LESS_BYTE = 60
comptime SEMICOLON_BYTE = 59
comptime ZERO_BYTE = 48
comptime NINE_BYTE = 57
# 'M' ends a mouse press, a drag or a wheel notch; 'm' ends a release.
comptime PRESS_BYTE = 77
comptime RELEASE_BYTE = 109
# 'A', 'B', 'C' and 'D' end the four arrows.
comptime UP_BYTE = 65
comptime DOWN_BYTE = 66
comptime RIGHT_BYTE = 67
comptime LEFT_BYTE = 68
# 't' ends the terminal's report of its size.
comptime SIZE_BYTE = 116
# A control sequence ends at the first byte in this range.
comptime FINAL_LOW = 64
comptime FINAL_HIGH = 126
# An unfinished control sequence longer than this is not one a terminal
# sends. It is dropped, so that noise cannot grow the pending bytes forever.
comptime MAX_SEQUENCE = 64

# The SGR button number, bit by bit.
comptime BUTTON_BITS = 3
comptime SHIFT_BIT = 4
comptime ALT_BIT = 8
comptime CTRL_BIT = 16
comptime MOTION_BIT = 32
comptime WHEEL_BIT = 64


@fieldwise_init
struct InputKind(Equatable, ImplicitlyCopyable, Writable):
    """What an input event is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven kinds there are.

        Returns:
            Whether the value names a kind.
        """
        return self.value >= 0 and self.value <= 6


# A key went down. three.js: `keydown`.
comptime KEY_DOWN = InputKind(0)
# A pointer button went down. three.js: `pointerdown`.
comptime POINTER_DOWN = InputKind(1)
# The pointer moved, with a button held or none. three.js: `pointermove`.
comptime POINTER_MOVE = InputKind(2)
# A pointer button went up. three.js: `pointerup`.
comptime POINTER_UP = InputKind(3)
# A wheel turned by one notch. three.js: `wheel`.
comptime WHEEL = InputKind(4)
# The view's size, in `x` and `y`: the window's `resize` event. The
# decoder gives columns and rows; the window gives the pixels of the
# largest frame that fits.
comptime RESIZE = InputKind(5)
# A key went up. three.js: `keyup`. A terminal sends no such thing, so the
# decoder never gives one; a source that knows when a key is let go can.
# The controls that move while a key is held also let it go by itself a
# while after its last repeat. See `controls.held_keys`.
comptime KEY_UP = InputKind(6)


@fieldwise_init
struct PointerButton(Equatable, ImplicitlyCopyable, Writable):
    """Which pointer button an event is about, as a type rather than a bare
    int. The values are the browser's `MouseEvent.button`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three buttons, or none.

        Returns:
            Whether the value names a button.
        """
        return self.value >= -1 and self.value <= 2


# The left button. three.js: `MOUSE.LEFT`.
comptime PRIMARY = PointerButton(0)
# The middle button, or a pressed wheel. three.js: `MOUSE.MIDDLE`.
comptime MIDDLE = PointerButton(1)
# The right button. three.js: `MOUSE.RIGHT`.
comptime SECONDARY = PointerButton(2)
# No button: a move with nothing held, a key or a wheel notch.
comptime NO_BUTTON = PointerButton(-1)


@fieldwise_init
struct Key(Equatable, ImplicitlyCopyable, Writable):
    """A key, as a type rather than a bare int.

    A key that types a character is its ASCII code, from 0 to 127: `Key(113)`
    is `q`, and `Key(3)` is Ctrl+C, which a raw terminal sends as a byte and
    not as a signal. The four arrows have codes of their own, above 255.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is an ASCII code, one of the arrows, or no
        key.

        Returns:
            Whether the value names a key.
        """
        return (self.value >= -1 and self.value <= 127) or (
            self.value >= ARROW_UP.value and self.value <= ARROW_RIGHT.value
        )


comptime ARROW_UP = Key(256)
comptime ARROW_DOWN = Key(257)
comptime ARROW_LEFT = Key(258)
comptime ARROW_RIGHT = Key(259)
comptime ESCAPE = Key(27)
comptime CTRL_C = Key(3)
# No key: a pointer or a wheel event.
comptime NO_KEY = Key(-1)


struct InputEvent(ImplicitlyCopyable):
    """One event: a key, a pointer button, a move or a wheel notch.

    Every field is set on every event. A field the kind does not use holds
    its empty value: `NO_KEY`, `NO_BUTTON`, zero.
    """

    var kind: InputKind
    # The key, for `KEY_DOWN` and `KEY_UP`.
    var key: Key
    # The button, for `POINTER_DOWN` and `POINTER_UP`, and the button held
    # for `POINTER_MOVE`.
    var button: PointerButton
    # Where the pointer is. A column and a row from the decoder; the window
    # converts them to pixels.
    var x: Int
    var y: Int
    # One notch toward the user, as the browser's positive `deltaY`, is 1.
    # One notch away is -1.
    var wheel: Int
    # The modifier keys held.
    var shift: Bool
    var alt: Bool
    var ctrl: Bool

    def __init__(
        out self,
        kind: InputKind,
        *,
        key: Key = NO_KEY,
        button: PointerButton = NO_BUTTON,
        x: Int = 0,
        y: Int = 0,
        wheel: Int = 0,
        shift: Bool = False,
        alt: Bool = False,
        ctrl: Bool = False,
    ):
        """Create an event.

        Args:
            kind: What happened.
            key: The key, for a key event.
            button: The button, for a pointer event.
            x: The pointer's column, or pixel.
            y: The pointer's row, or pixel.
            wheel: The wheel's notches, positive toward the user.
            shift: Whether Shift is held.
            alt: Whether Alt is held.
            ctrl: Whether Ctrl is held.
        """
        self.kind = kind
        self.key = key
        self.button = button
        self.x = x
        self.y = y
        self.wheel = wheel
        self.shift = shift
        self.alt = alt
        self.ctrl = ctrl


def _is_digit(byte: UInt8) -> Bool:
    """Return True if `byte` is an ASCII digit."""
    return byte >= ZERO_BYTE and byte <= NINE_BYTE


def _is_final(byte: UInt8) -> Bool:
    """Return True if `byte` ends a control sequence."""
    return byte >= FINAL_LOW and byte <= FINAL_HIGH


def _parameters(bytes: List[UInt8], first: Int, end: Int) -> List[Int]:
    """Read the numbers of a control sequence, split at semicolons.

    Args:
        bytes: The bytes.
        first: The index of the first parameter byte.
        end: The index one past the last.

    Returns:
        One number per field. An empty field is zero. Empty when a byte is
        neither a digit nor a semicolon, which is no sequence this decoder
        knows.
    """
    var numbers = List[Int]()
    var current = 0
    for index in range(first, end):
        var byte = bytes[index]
        if byte == SEMICOLON_BYTE:
            numbers.append(current)
            current = 0
        elif _is_digit(byte):
            current = current * 10 + Int(byte - ZERO_BYTE)
        else:
            return List[Int]()
    numbers.append(current)
    return numbers^


def _mouse_event(
    button_code: Int, column: Int, row: Int, press: Bool
) -> InputEvent:
    """Build the event an SGR mouse report describes.

    Args:
        button_code: The report's first number: the button in its low two
            bits, then Shift, Alt, Ctrl, motion and wheel.
        column: The report's column, from one.
        row: The report's row, from one.
        press: True for a report ending in `M`, False for one in `m`.

    Returns:
        The event, at a column and a row from zero.
    """
    var low = button_code & BUTTON_BITS
    var event = InputEvent(
        POINTER_DOWN,
        x=column - 1,
        y=row - 1,
        shift=(button_code & SHIFT_BIT) != 0,
        alt=(button_code & ALT_BIT) != 0,
        ctrl=(button_code & CTRL_BIT) != 0,
    )
    if (button_code & WHEEL_BIT) != 0:
        # Button 64 is a notch up, away from the user; 65 is toward.
        event.kind = WHEEL
        event.wheel = 1 if low == 1 else -1
        return event
    # Low bits of three mean no button: a move with nothing held.
    event.button = NO_BUTTON if low == 3 else PointerButton(low)
    if (button_code & MOTION_BIT) != 0:
        event.kind = POINTER_MOVE
    elif not press:
        event.kind = POINTER_UP
    return event


def _arrow(final: UInt8) -> Key:
    """Return the arrow a control sequence's final byte names.

    Args:
        final: `A`, `B`, `C` or `D`, or anything else.

    Returns:
        The arrow, or `NO_KEY`.
    """
    if final == UP_BYTE:
        return ARROW_UP
    if final == DOWN_BYTE:
        return ARROW_DOWN
    if final == RIGHT_BYTE:
        return ARROW_RIGHT
    if final == LEFT_BYTE:
        return ARROW_LEFT
    return NO_KEY


def _control_sequence(
    bytes: List[UInt8], start: Int, final_at: Int, mut events: List[InputEvent]
):
    """Decode one complete control sequence.

    Args:
        bytes: The bytes.
        start: The index of its escape.
        final_at: The index of its final byte.
        events: Where the event it describes, if any, is appended.
    """
    var final = bytes[final_at]
    var first = start + 2
    var mouse = first < final_at and bytes[first] == LESS_BYTE
    if mouse:
        var numbers = _parameters(bytes, first + 1, final_at)
        var is_report = final == PRESS_BYTE or final == RELEASE_BYTE
        if is_report and len(numbers) == 3:
            events.append(
                _mouse_event(
                    numbers[0], numbers[1], numbers[2], final == PRESS_BYTE
                )
            )
        return
    if final == SIZE_BYTE:
        # `ESC [ 8 ; rows ; columns t`: the terminal's answer to
        # `ESC [ 18 t`, its text area in cells.
        var size = _parameters(bytes, first, final_at)
        if len(size) == 3 and size[0] == 8:
            events.append(InputEvent(RESIZE, x=size[2], y=size[1]))
        return
    var key = _arrow(final)
    if key == NO_KEY:
        return
    var numbers = _parameters(bytes, first, final_at)
    # `ESC [ 1 ; m A` carries modifiers: m less one, Shift in bit zero,
    # Alt in bit one, Ctrl in bit two.
    var modifiers = numbers[1] - 1 if len(numbers) == 2 else 0
    events.append(
        InputEvent(
            KEY_DOWN,
            key=key,
            shift=(modifiers & 1) != 0,
            alt=(modifiers & 2) != 0,
            ctrl=(modifiers & 4) != 0,
        )
    )


struct InputDecoder(Movable):
    """Turns the bytes a terminal sends into input events.

    It keeps the bytes of a sequence that has not arrived whole, and
    decodes them with the next bytes it is fed.
    """

    var pending: List[UInt8]

    def __init__(out self):
        """Create a decoder with nothing pending."""
        self.pending = List[UInt8]()

    def feed(mut self, bytes: List[UInt8]) -> List[InputEvent]:
        """Decode as many events as the bytes so far hold.

        An escape that ends the bytes is the Escape key: a terminal writes
        a whole sequence at once, so nothing follows it. A control sequence
        cut off before its final byte is kept for the next call.

        Args:
            bytes: The bytes just read.

        Returns:
            The events, in the order they were sent.
        """
        for byte in bytes:
            self.pending.append(byte)
        var events = List[InputEvent]()
        var index = 0
        var count = len(self.pending)
        while index < count:
            var used = self._decode_one(index, events)
            if used == 0:
                break
            index += used
        var rest = List[UInt8]()
        for kept in range(index, count):
            rest.append(self.pending[kept])
        self.pending = rest^
        return events^

    def _decode_one(self, start: Int, mut events: List[InputEvent]) -> Int:
        """Decode the event that starts at `start`.

        Args:
            start: The index of its first byte in the pending bytes.
            events: Where the event, if any, is appended.

        Returns:
            How many bytes it took, or zero for a sequence not yet whole.
        """
        var count = len(self.pending)
        var byte = self.pending[start]
        if byte != ESCAPE_BYTE:
            # A byte past ASCII is part of a character this decoder does
            # not name as a key. It is consumed and dropped.
            if byte < 128:
                events.append(InputEvent(KEY_DOWN, key=Key(Int(byte))))
            return 1
        var sequence = start + 1 < count and self.pending[start + 1] == (
            BRACKET_BYTE
        )
        if not sequence:
            events.append(InputEvent(KEY_DOWN, key=ESCAPE))
            return 1
        for index in range(start + 2, count):
            if _is_final(self.pending[index]):
                _control_sequence(self.pending, start, index, events)
                return index - start + 1
        if count - start > MAX_SEQUENCE:
            return count - start
        return 0
