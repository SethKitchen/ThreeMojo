# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A stopwatch for animation loops, from three.js `src/core/Clock.js`.

An animation wants two numbers each frame: how long since it began, to
place things, and how long since the last frame, to move them by. Both
come from one monotonic counter, `perf_counter_ns`, which is what a clock
that measures intervals needs -- a wall clock can jump. They come back as
`Duration`s, so a speed in meters per second multiplies a delta without a
factor of a thousand hiding in the code.

The behavior is three.js's. A clock starts itself on its first question
unless told not to; `stop` freezes the elapsed time and the next delta is
zero; `start` again resets everything.

Every question is also answerable at a given time, in nanoseconds. That is
how the arithmetic is tested without waiting, and it is what the public
methods call with the counter's reading.

The state is whole nanoseconds, the counter's own unit, and the elapsed
time is the reading less the start: one subtraction, exact, however many
frames have gone by. three.js sums its deltas in floating point instead,
and a clock asked sixty times a second for an hour is a long sum of
numbers that each rounded, drifting from the counter by the frame rate.
Seconds are made from the nanoseconds only on the way out.
"""

from std.time import perf_counter_ns
from units.si import Duration, SECOND

comptime NANOSECONDS_PER_SECOND = Float64(1e9)


def _seconds(nanoseconds: Int) -> Duration:
    """Return a count of nanoseconds as a `Duration` in seconds.

    Divided in Float64 and rounded to Float32 once: converting the count
    to Float32 first would round it to the nearest quarter millisecond
    after an hour, before the divide rounded it again.
    """
    return Duration(
        Float32(Float64(nanoseconds) / NANOSECONDS_PER_SECOND), SECOND
    )


struct Clock(ImplicitlyCopyable):
    """A stopwatch that answers in seconds since it started, and since it
    was last asked."""

    # Whether the clock is counting. Starts False; the first question starts
    # it when `auto_start` is set.
    var running: Bool
    # Whether the first question starts the clock. three.js's `autoStart`,
    # which `stop` clears so that a stopped clock stays stopped.
    var auto_start: Bool
    # The counter's reading when the clock last started.
    var started_at: Int
    # The counter's reading at the last question, which the next delta is
    # measured from.
    var previous: Int
    # Nanoseconds from the start to the last question. While the clock
    # runs it is brought up to date by every question; when it stops it
    # keeps the value it had, which is what a stopped clock answers.
    var elapsed_ns: Int

    def __init__(out self, auto_start: Bool = True):
        """Create a clock that is not yet running.

        Args:
            auto_start: True, the default, to start on the first `delta` or
                `elapsed`; False to wait for `start`.
        """
        self.running = False
        self.auto_start = auto_start
        self.started_at = 0
        self.previous = 0
        self.elapsed_ns = 0

    def start(mut self):
        """Start, or restart, counting from now."""
        self.start_at(perf_counter_ns())

    def stop(mut self):
        """Stop counting. The elapsed time keeps its value; a later `delta`
        is zero; only `start` sets it going again."""
        self.stop_at(perf_counter_ns())

    def delta(mut self) -> Duration:
        """Return how long since the last question, and note the time.

        Returns:
            The interval, or zero for a clock that is not running.
        """
        return self.delta_at(perf_counter_ns())

    def elapsed(mut self) -> Duration:
        """Return how long the clock has run since it started.

        Returns:
            The total, or zero for a clock that never started.
        """
        return self.elapsed_at(perf_counter_ns())

    def start_at(mut self, now: Int):
        """Start, or restart, counting from a given counter reading.

        Args:
            now: The reading, in nanoseconds.
        """
        self.started_at = now
        self.previous = now
        self.elapsed_ns = 0
        self.running = True

    def stop_at(mut self, now: Int):
        """Stop counting at a given counter reading, taking in the time up
        to it first.

        Args:
            now: The reading, in nanoseconds.
        """
        _ = self.elapsed_at(now)
        self.running = False
        self.auto_start = False

    def delta_at(mut self, now: Int) -> Duration:
        """Return how long since the last question, at a given reading.

        The first question starts a clock built to start itself, and
        answers zero: there is no earlier question to measure from.

        Args:
            now: The reading, in nanoseconds.

        Returns:
            The interval, or zero for a clock that is not running.
        """
        if self.auto_start and not self.running:
            self.start_at(now)
            return _seconds(0)
        if not self.running:
            return _seconds(0)
        var interval = now - self.previous
        self.previous = now
        self.elapsed_ns = now - self.started_at
        return _seconds(interval)

    def elapsed_at(mut self, now: Int) -> Duration:
        """Return how long the clock has run, at a given reading.

        The reading less the start, not the sum of the deltas: exact
        whatever the frame rate.

        Args:
            now: The reading, in nanoseconds.

        Returns:
            The total, brought up to `now`.
        """
        _ = self.delta_at(now)
        return _seconds(self.elapsed_ns)
