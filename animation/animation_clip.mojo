# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A named set of tracks that play together, from three.js
`src/animation/AnimationClip.js`.

A clip is a walk cycle, a door opening, a wave. It is a name and a list of
tracks, and it lasts as long as its longest track. three.js works the
duration out the same way when none is given, in `resetDuration`.

Nothing in a clip says which node it drives. Every track says that for
itself, so one clip can move a whole rig, and two tracks of one clip can
name two nodes.

## What is refused

A clip with no tracks, and a clip whose tracks all hold one key. Both last
no time at all, and a thing that lasts no time cannot be played: an action
looping over it would divide by its length.
"""

from animation.keyframe_track import KeyframeTrack
from units.si import Duration, SECOND


struct AnimationClip(Copyable, Movable):
    """A named set of tracks, played as one."""

    var name: String
    var tracks: List[KeyframeTrack]

    def __init__(
        out self, name: String, var tracks: List[KeyframeTrack]
    ) raises:
        """Create a clip from its tracks.

        Args:
            name: What the clip is called, as three.js's clips are named.
            tracks: The tracks it plays, at least one, and at least one of
                them lasting longer than no time.

        Raises:
            Error: If there are no tracks, or every track holds a single
                key, which is a clip of no length.
        """
        if len(tracks) == 0:
            raise Error("A clip needs at least one track")
        var longest = Float32(0)
        for index in range(len(tracks)):  # pragma: no branch
            var runs = tracks[index].duration().to(SECOND)
            if runs > longest:
                longest = runs
        if longest <= 0:
            raise Error("A clip must last longer than no time")
        self.name = name
        self.tracks = tracks^

    def __init__(out self, *, copy: Self):
        """Copy another clip, its tracks included."""
        self.name = copy.name
        self.tracks = copy.tracks.copy()

    def track_count(self) -> Int:
        """Return how many tracks the clip plays."""
        return len(self.tracks)

    def duration(self) -> Duration:
        """Return how long the clip runs, which is its longest track."""
        var longest = Float32(0)
        for index in range(len(self.tracks)):  # pragma: no branch
            var runs = self.tracks[index].duration().to(SECOND)
            if runs > longest:
                longest = runs
        return Duration(longest, SECOND)
