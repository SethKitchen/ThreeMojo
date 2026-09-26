# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Point cache files, from three.js `examples/jsm/loaders/MDDLoader.js`.

An MDD file is big-endian. It starts with two 32-bit unsigned values: the
number of frames and the number of points. Then comes one 32-bit float
for each frame, its time in seconds. Then comes each frame's positions,
three 32-bit floats for each point. `parse_mdd` reads it as three.js's
`parse` does.

**The morph targets.** Each frame is one morph target, named `morph_`
and the frame's index. A target holds each point's position, not how
far it moves. Add them to a geometry with `add_morph_target` and clear
`morph_relative`.

**The clip.** `mdd_clip` returns three.js's clip: named `default`, as
long as the last frame's time, and with each frame's target at full
weight at its own time and at zero weight at the other frames' times.
three.js holds this as one track of every influence. This port holds it
as one track for each target, which gives the same weights.

**What is refused.** A file that ends inside a value, which three.js's
`DataView` throws on. `mdd_clip` refuses a file with no frames, and
times that are negative, do not rise, or end at zero. three.js makes a
clip of such a file, but the clip has no length or plays keys out of
order.
Bytes after the last frame are stepped over, as three.js steps over them.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import KeyframeTrack, MeshIndex, morph_target
from core.buffer_attribute import BufferAttribute
from std.memory import bitcast
from std.pathlib import Path
from units.si import SECOND, Duration


struct MddModel(Movable):
    """What `parse_mdd` gives: each frame's time, and its positions as a
    morph target."""

    # Each frame's time, in seconds, as the file gives it.
    var times: List[Float32]
    # Each frame's positions, three numbers a point.
    var morph_targets: List[BufferAttribute]
    # Each target's name, three.js's attribute `name`: `morph_0` onward.
    var names: List[String]

    def __init__(
        out self,
        var times: List[Float32],
        var morph_targets: List[BufferAttribute],
        var names: List[String],
    ):
        """Hold what a file gave.

        Args:
            times: Each frame's time.
            morph_targets: Each frame's positions.
            names: Each target's name.
        """
        self.times = times^
        self.morph_targets = morph_targets^
        self.names = names^


def _word(bytes: List[UInt8], at: Int) raises -> UInt32:
    """Return the big-endian 32-bit value at a byte.

    Args:
        bytes: The file.
        at: Where the value starts.

    Returns:
        The value.

    Raises:
        Error: If the value runs past the end of the file.
    """
    if at + 4 > len(bytes):
        raise Error("MDD: the file ends inside a value, at byte " + String(at))
    var value: UInt32 = 0
    for k in range(4):  # pragma: no branch
        value = (value << 8) | UInt32(bytes[at + k])
    return value


def parse_mdd(bytes: List[UInt8]) raises -> MddModel:
    """Read an MDD file's bytes, three.js's `MDDLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        Each frame's time and positions.

    Raises:
        Error: If the file ends inside a value.
    """
    var frames = Int(_word(bytes, 0))
    var points = Int(_word(bytes, 4))
    var offset = 8
    var times = List[Float32]()
    for _ in range(frames):
        times.append(bitcast[DType.float32](_word(bytes, offset)))
        offset += 4
    var targets = List[BufferAttribute]()
    var names = List[String]()
    for frame in range(frames):
        var positions = List[Float32](capacity=points * 3)
        for _ in range(points * 3):
            positions.append(bitcast[DType.float32](_word(bytes, offset)))
            offset += 4
        targets.append(BufferAttribute(positions^, 3))
        names.append("morph_" + String(frame))
    return MddModel(times^, targets^, names^)


def mdd_clip(model: MddModel, mesh: MeshIndex) raises -> AnimationClip:
    """Return the file's clip, three.js's `clip`.

    Args:
        model: The model.
        mesh: The mesh the tracks drive, which wears the model's morph
            targets in their order.

    Returns:
        The clip `default`, with one track for each target.

    Raises:
        Error: If the model has no frames, or its times are negative, do
            not rise, or end at zero.
    """
    var frames = len(model.times)
    if frames == 0:
        raise Error("MDD: a clip needs at least one frame")
    var times = List[Duration]()
    # At least one frame: the loop always runs.
    for time in model.times:  # pragma: no branch
        times.append(Duration(time, SECOND))
    var tracks = List[KeyframeTrack]()
    for target in range(frames):  # pragma: no branch
        var values = List[Float32](length=frames, fill=0)
        values[target] = 1
        tracks.append(KeyframeTrack(morph_target(mesh, target), times, values^))
    return AnimationClip(
        "default", tracks^, duration=Duration(model.times[frames - 1], SECOND)
    )


def read_mdd(path: String) raises -> MddModel:
    """Read an MDD file.

    Args:
        path: The file.

    Returns:
        What `parse_mdd` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_mdd`
            refuses.
    """
    return parse_mdd(Path(path).read_bytes())
