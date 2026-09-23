# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bones of a skeleton, from three.js `src/helpers/SkeletonHelper.js`.

One segment for each bone whose parent is also a bone: from the bone's
world position to its parent's. The bone's end is blue and the parent's
end is green, three.js's two colors, so the direction of each bone reads.
A bone whose parent is not a bone, the root of the rig, has no segment.

three.js finds the bones by walking an object's children for `isBone`.
Here a bone is a node that a `Skeleton` names, and a parent is a bone if
the same skeleton names it. The points are world positions, read from
the scene's world matrices, so the `Line` belongs on a node at the
origin, as three.js's helper takes the identity when its root does.
"""

from core.buffer_geometry import BufferGeometry
from core.scene import Scene
from helpers.segments import Segments
from objects.skeleton import Skeleton
from render.framebuffer import Color, FloatColor

# three.js's two colors, `Color(0, 0, 1)` and `Color(0, 1, 0)`, which
# decode from these bytes to exactly those floats.
comptime DEFAULT_BONE_COLOR = Color(0x00, 0x00, 0xFF)
comptime DEFAULT_PARENT_COLOR = Color(0x00, 0xFF, 0x00)


def skeleton_helper(
    skeleton: Skeleton,
    scene: Scene,
    bone_color: Color = DEFAULT_BONE_COLOR,
    parent_color: Color = DEFAULT_PARENT_COLOR,
) raises -> BufferGeometry:
    """Return the bones of `skeleton` where they stand, for a `Line` in
    `SEGMENTS` mode on a node at the origin.

    Args:
        skeleton: The bones to draw.
        scene: The scene the bones are nodes of. It must be up to date:
            call `update` after the last change to a node.
        bone_color: The color at each bone's own end, as authored in sRGB.
            three.js's `color1`.
        parent_color: The color at its parent's end. three.js's `color2`.

    Returns:
        Two points for every bone whose parent is a bone of the same
        skeleton, in the skeleton's order, with a `color` attribute in
        linear light. No points when no bone has a bone for a parent.

    Raises:
        Error: If a bone's node is not in the scene, or the scene has
            changed since its last `update`.
    """
    var own = FloatColor(srgb=bone_color)
    var parents = FloatColor(srgb=parent_color)
    var segments = Segments()
    # Both loops run at least once: `Skeleton` refuses to be built with
    # no bones.
    for index in range(skeleton.bone_count()):  # pragma: no branch
        var node = skeleton.node(index)
        var parent = scene.get(node).parent
        var is_bone = False
        for other in range(skeleton.bone_count()):  # pragma: no branch
            if skeleton.node(other) == parent:
                is_bone = True
        if is_bone:
            segments.add_blend(
                scene.world_position(node),
                scene.world_position(parent),
                own,
                parents,
            )
    return segments.geometry()
