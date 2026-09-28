# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The path an animated node moves along, from three.js
`examples/jsm/helpers/AnimationPathHelper.js`.

The helper finds the clip's position track of one node. A line follows
the track, sampled `divisions + 1` times from the start of the clip to its
end. A point marks the value of each key. three.js's colors are green for
the line and red for the markers, and a marker is five pixels across at
any distance.

A position track moves a node in its parent's space, so the path belongs
in that space too. three.js copies the parent's world matrix into the
helper every frame. Here `add_animation_path_helper` puts the helper's
node under the same parent, with no transform of its own, and the scene
carries it the same way.

three.js finds the track by the name `<uuid>.position`. Here a track names
its target by a `TrackTarget`, so the helper takes the first track that
drives the node's `POSITION`.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import POSITION
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION as POSITION_ATTRIBUTE
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import BASIC, Material, PointSize, points_material
from objects.line import Line
from objects.points import Points
from render.framebuffer import Color
from units.si import Duration, SECOND

# three.js's defaults: `0x00ff00`, `0xff0000`, 100 samples and five pixels.
comptime DEFAULT_PATH_COLOR = Color(0x00, 0xFF, 0x00)
comptime DEFAULT_MARKER_COLOR = Color(0xFF, 0x00, 0x00)
comptime DEFAULT_PATH_DIVISIONS = 100
comptime DEFAULT_MARKER_SIZE = PointSize(5.0)


def position_track(clip: AnimationClip, object: NodeId) -> Int:
    """Return which track of a clip moves a node, three.js's
    `_findTrackForObject`.

    Args:
        clip: The clip.
        object: The node.

    Returns:
        The index of the first track that drives the node's `POSITION`, or
        -1 for none.
    """
    # A clip holds one track at least, so this runs.
    for index in range(len(clip.tracks)):  # pragma: no branch
        ref target = clip.tracks[index].target
        if target.kind == POSITION and target.index == object.value:
            return index
    return -1


def animation_path(
    clip: AnimationClip, object: NodeId, divisions: Int = DEFAULT_PATH_DIVISIONS
) raises -> BufferGeometry:
    """Return the path a node moves along in a clip, three.js's
    `_sampleTrack`.

    Args:
        clip: The clip.
        object: The node it moves.
        divisions: How many steps the clip's length is cut into, one or
            more. There is one point more than steps.

    Returns:
        The points, in the parent's space, for a `Line` in `STRIP` mode.

    Raises:
        Error: If `divisions` is below one, the clip has no position track
            for the node, or the track cannot be read.
    """
    if divisions < 1:
        raise Error("An animation path needs one division at least")
    var track = position_track(clip, object)
    if track < 0:
        raise Error("The clip has no position track for the node")
    var numbers = List[Float32]()
    for step in range(divisions + 1):  # pragma: no branch
        var at = Float32(step) / Float32(divisions) * clip.length
        var point = clip.tracks[track].sample_vector3(Duration(at, SECOND))
        numbers.append(point.x)
        numbers.append(point.y)
        numbers.append(point.z)
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION_ATTRIBUTE), BufferAttribute(numbers^, 3)
    )
    return geometry^


def animation_path_markers(
    clip: AnimationClip, object: NodeId
) raises -> BufferGeometry:
    """Return a point at each key of a node's position track, three.js's
    keyframe markers.

    Args:
        clip: The clip.
        object: The node it moves.

    Returns:
        The track's values, one point a key, for `Points`.

    Raises:
        Error: If the clip has no position track for the node.
    """
    var track = position_track(clip, object)
    if track < 0:
        raise Error("The clip has no position track for the node")
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION_ATTRIBUTE),
        BufferAttribute(clip.tracks[track].values.copy(), 3),
    )
    return geometry^


struct AnimationPathHelper(Copyable, Movable):
    """What `add_animation_path_helper` added to a scene."""

    # The helper's node, under the moved node's parent.
    var node: NodeId
    # The line along the path.
    var line: Line
    # The markers at the keys, or None when they are not shown.
    var points: Optional[Points]

    def __init__(out self, node: NodeId, line: Line, points: Optional[Points]):
        """Hold what was added.

        Args:
            node: The helper's node.
            line: The line along the path.
            points: The markers, or None.
        """
        self.node = node
        self.line = line
        self.points = points


def add_animation_path_helper(
    mut scene: Scene,
    mut assets: Assets,
    clip: AnimationClip,
    object: NodeId,
    color: Color = DEFAULT_PATH_COLOR,
    marker_color: Color = DEFAULT_MARKER_COLOR,
    divisions: Int = DEFAULT_PATH_DIVISIONS,
    show_markers: Bool = True,
    marker_size: PointSize = DEFAULT_MARKER_SIZE,
) raises -> AnimationPathHelper:
    """Add the path a node moves along to a scene, three.js's
    `new AnimationPathHelper( root, clip, object, options )`.

    Args:
        scene: The scene the node is in.
        assets: Where the geometries and materials are stored.
        clip: The clip that moves the node.
        object: The node.
        color: The line's color, as authored in sRGB.
        marker_color: The markers' color, as authored in sRGB.
        divisions: How many steps the path is sampled in.
        show_markers: Whether to mark each key with a point.
        marker_size: How big a marker is, in pixels, at any distance.

    Returns:
        The helper's node, its line, and its points.

    Raises:
        Error: If the node is not in the scene, or for anything
            `animation_path` or `points_material` refuses.
    """
    var path = animation_path(clip, object, divisions)
    var parent = scene.get(object).parent
    var holder = Object3D()
    holder.parent = parent
    holder.name = "AnimationPathHelper"
    var node = scene.add(holder^)
    var line_look = Material(color, kind=BASIC)
    line_look.tone_mapped = False
    var line = Line(
        assets.geometries.add(path^), assets.materials.add(line_look), node
    )
    scene.add_line(line)
    var points: Optional[Points] = None
    if show_markers:
        var marker_look = points_material(
            marker_color, marker_size, size_attenuation=False
        )
        marker_look.tone_mapped = False
        var markers = Points(
            assets.geometries.add(animation_path_markers(clip, object)),
            assets.materials.add(marker_look),
            node,
        )
        scene.add_points(markers)
        points = markers
    return AnimationPathHelper(node, line, points)
