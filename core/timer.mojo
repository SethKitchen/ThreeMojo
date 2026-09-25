# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A frame timer with a time scale, from three.js `src/core/Timer.js`.

`Timer` is what three.js recommends over `Clock` for an animation loop.
The loop calls `update` once a frame, and every question after it in the
same frame gets the same answer: `delta` is the time from the last frame
to this one and `elapsed` the sum of every delta. Asking twice does not
change anything, which `Clock.delta` cannot say.

The time scale multiplies each delta. Two runs the animation at double
speed, a half at half speed, and zero pauses it. A negative scale runs the
elapsed time back, as three.js lets it.

three.js reads `performance.now()` in milliseconds. This reads the same
monotonic counter `core.clock` reads, `perf_counter_ns`, in nanoseconds,
and answers in `Duration`s. Each public method has an `_at` form that takes
the counter's reading, which is three.js's `update( timestamp )` and how
the arithmetic is tested.

A page that is hidden stops three.js's timer when it is connected to the
document: `update` gives a delta of zero, and showing the page again calls
`reset` so the first frame back does not jump. There is no document here.
`set_hidden` is what the document's `visibilitychange` event would do, for
a window system that reports the same thing.
"""

from std.math import isfinite
from std.time import perf_counter_ns
from units.si import Duration, SECOND

comptime _NANOSECONDS_PER_SECOND = Float64(1e9)


def _seconds(nanoseconds: Float64) -> Duration:
    """Return nanoseconds as a `Duration`, rounded to a `Float32` once."""
    return Duration(Float32(nanoseconds / _NANOSECONDS_PER_SECOND), SECOND)


struct Timer(ImplicitlyCopyable):
    """A frame timer: the time between the last two updates, scaled, and
    the sum of those times."""

    # The counter's reading when the timer was made, three.js's
    # `_startTime`. The two readings below are measured from it.
    var started_at: Int
    # The readings at the last two updates, less `started_at`: three.js's
    # `_previousTime` and `_currentTime`.
    var previous: Int
    var current: Int
    # The last delta and the sum of every delta, in nanoseconds, scaled.
    var delta_ns: Float64
    var elapsed_ns: Float64
    # What each delta is multiplied by, three.js's `_timescale`.
    var timescale: Float64
    # True while the page is hidden, which zeroes each delta.
    var hidden: Bool

    def __init__(out self):
        """Create a timer that starts now, with a time scale of one."""
        self = Timer(start=perf_counter_ns())

    def __init__(out self, *, start: Int):
        """Create a timer that started at a counter reading.

        Args:
            start: The reading, in nanoseconds.
        """
        self.started_at = start
        self.previous = 0
        self.current = 0
        self.delta_ns = 0
        self.elapsed_ns = 0
        self.timescale = 1
        self.hidden = False

    def delta(self) -> Duration:
        """Return the time between the last two updates, scaled, three.js's
        `getDelta`.

        Returns:
            The delta. Zero before the first update and while hidden.
        """
        return _seconds(self.delta_ns)

    def elapsed(self) -> Duration:
        """Return the sum of every delta, three.js's `getElapsed`.

        Returns:
            The sum. Each delta was scaled by the time scale of its frame.
        """
        return _seconds(self.elapsed_ns)

    def set_timescale(mut self, timescale: Float64) raises:
        """Set what each later delta is multiplied by, three.js's
        `setTimescale`.

        Args:
            timescale: One for real time, two for double speed, zero to
                pause. A negative scale runs the elapsed time back.

        Raises:
            Error: If `timescale` is not finite. The scale is left as it
                was.
        """
        if not isfinite(timescale):
            raise Error("A timer's time scale must be finite")
        self.timescale = timescale

    def update(mut self):
        """Take this frame's delta, three.js's `update`: call it once a
        frame, before any question."""
        self.update_at(perf_counter_ns())

    def update_at(mut self, now: Int):
        """Take this frame's delta at a given counter reading, three.js's
        `update( timestamp )`.

        Args:
            now: The reading, in nanoseconds.
        """
        if self.hidden:
            self.delta_ns = 0
            return
        self.previous = self.current
        self.current = now - self.started_at
        self.delta_ns = Float64(self.current - self.previous) * self.timescale
        self.elapsed_ns += self.delta_ns

    def reset(mut self):
        """Measure the next delta from now, three.js's `reset`. The elapsed
        time is kept."""
        self.reset_at(perf_counter_ns())

    def reset_at(mut self, now: Int):
        """Measure the next delta from a given counter reading.

        Args:
            now: The reading, in nanoseconds.
        """
        self.current = now - self.started_at

    def set_hidden(mut self, hidden: Bool):
        """Say whether the page is hidden, as three.js's `visibilitychange`
        handler hears it.

        Args:
            hidden: True to zero every delta until the page is shown; False
                to show it, which resets the timer so that the next delta
                does not span the time it was hidden.
        """
        self.set_hidden_at(hidden, perf_counter_ns())

    def set_hidden_at(mut self, hidden: Bool, now: Int):
        """Say whether the page is hidden, at a given counter reading.

        Args:
            hidden: Whether the page is hidden.
            now: The reading, in nanoseconds.
        """
        self.hidden = hidden
        if not hidden:
            self.reset_at(now)
