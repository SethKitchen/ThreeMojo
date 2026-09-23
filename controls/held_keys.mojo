# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which keys are held, for a source that never says a key went up.

three.js moves a camera while a key is held: `keydown` starts the move and
`keyup` ends it. A terminal sends a key again and again while it is held,
at the keyboard's repeat rate, and sends nothing when it is let go. So a
key here counts as held from its last `KEY_DOWN` until `timeout` has gone
by with no repeat. A `KEY_UP`, from a source that has one, lets it go at
once.

The timeout is a trade. Too short, and a held key stutters between
repeats. Too long, and the camera coasts after the key is let go. The
default of 0.3 seconds is longer than the gap between two repeats, about
0.03 seconds. Most keyboards wait about half a second before the first
repeat, so a held key moves, pauses for a moment, then moves steadily. A
timeout of 0.6 seconds fills that pause.

A letter and its capital are one key, as three.js's `event.code` names the
physical key: `W` with Shift held is `w`.
"""

from controls.input import Key
from units.si import Duration, SECOND

# How long a key counts as held after its last repeat, by default.
comptime HOLD_TIMEOUT = Duration(0.3, SECOND)
# 'A' and 'Z', and how far a capital is below its small letter.
comptime CAPITAL_A = 65
comptime CAPITAL_Z = 90
comptime CASE_OFFSET = 32


def physical_key(key: Key) -> Key:
    """Return the key that types a character, as three.js's `event.code`
    names it: a capital letter is its small letter.

    Args:
        key: The key.

    Returns:
        The same key, or its small letter.
    """
    var capital = key.value >= CAPITAL_A and key.value <= CAPITAL_Z
    return Key(key.value + CASE_OFFSET) if capital else key


struct HeldKeys(Copyable, Movable):
    """The keys held now, each with the time since its last repeat."""

    # How long a key counts as held after its last `KEY_DOWN`.
    var timeout: Duration
    var _keys: List[Int]
    var _ages: List[Float32]

    def __init__(out self, timeout: Duration = HOLD_TIMEOUT):
        """Create a set with no key held.

        Args:
            timeout: How long a key counts as held after its last repeat.
        """
        self.timeout = timeout
        self._keys = List[Int]()
        self._ages = List[Float32]()

    def press(mut self, key: Key):
        """Hold a key, or restart the time since its last repeat.

        Args:
            key: The key. A capital letter holds its small letter.
        """
        var code = physical_key(key).value
        for index in range(len(self._keys)):
            if self._keys[index] == code:
                self._ages[index] = 0
                return
        self._keys.append(code)
        self._ages.append(0)

    def release(mut self, key: Key) -> Bool:
        """Let a key go.

        Args:
            key: The key. A capital letter lets its small letter go.

        Returns:
            True if it was held.
        """
        var code = physical_key(key).value
        for index in range(len(self._keys)):
            if self._keys[index] == code:
                _ = self._keys.pop(index)
                _ = self._ages.pop(index)
                return True
        return False

    def is_held(self, key: Key) -> Bool:
        """Return True if a key is held.

        Args:
            key: The key. A capital letter asks about its small letter.

        Returns:
            Whether it is held.
        """
        var code = physical_key(key).value
        for held in self._keys:
            if held == code:
                return True
        return False

    def count(self) -> Int:
        """Return how many keys are held.

        Returns:
            The number of keys.
        """
        return len(self._keys)

    def advance(mut self, delta: Duration) raises -> List[Key]:
        """Let time pass, and let go of each key not repeated within the
        timeout.

        Args:
            delta: The time since the last call.

        Returns:
            The keys let go, as if each had sent a `KEY_UP`.

        Raises:
            Error: If the time is negative, or the timeout is not positive.
        """
        if delta.value < 0:
            raise Error(
                "A frame's time must not be negative, got ", delta.value
            )
        if not (self.timeout.value > 0):
            raise Error("A key's hold timeout must be positive")
        var gone = List[Key]()
        var keys = List[Int]()
        var ages = List[Float32]()
        for index in range(len(self._keys)):
            var age = self._ages[index] + delta.value
            if age > self.timeout.value:
                gone.append(Key(self._keys[index]))
            else:
                keys.append(self._keys[index])
                ages.append(age)
        self._keys = keys^
        self._ages = ages^
        return gone^
