# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Depth and semantic cameras, cast against a ThreeMojo scene.

CARLA reads these images back from its renderer's G-buffer. This port casts one
ray through the center of each pixel instead, with the scene's
`Raycaster`, so the same scene gives the RGB, depth and semantic images.
`tags` names one `SemanticTag` per mesh in `scene.meshes`.
"""

from core.assets import Assets
from core.raycaster import Raycaster
from core.scene import Scene
from extensions.carla.sensor import (
    CameraIntrinsics,
    DEPTH_FAR,
    SemanticTag,
    cityscapes_color,
    encode_depth,
)
from extensions.carla.transform import CarlaTransform, carla_to_three
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import inf
from units.si import Length, METER


@fieldwise_init
struct SceneHit(ImplicitlyCopyable):
    """The nearest mesh a ray meets."""

    # Distance along the ray, in lengths of its direction. Infinity if
    # the ray meets nothing.
    var distance: Float32
    # The mesh's index in `scene.meshes`, or -1 if the ray meets nothing.
    var mesh: Int


def nearest_hit(
    scene: Scene,
    assets: Assets,
    origin: Vector3,
    direction: Vector3,
    far: Length,
) raises -> SceneHit:
    """Return the nearest mesh along a ray in CARLA's frame.

    Args:
        scene: The scene, updated.
        assets: Its geometry and materials.
        origin: Where the ray starts, in CARLA's world frame.
        direction: Which way it goes. Its length is the unit of distance.
        far: How far the ray reaches, in lengths of `direction`.

    Returns:
        The nearest hit, or a miss.

    Raises:
        Error: If the direction has no length, `far` is negative, or a
            mesh cannot be tested.
    """
    var scale = direction.length()
    var caster = Raycaster(
        carla_to_three(origin),
        carla_to_three(direction),
        far=Length(far.value * scale, METER),
    )
    var best = SceneHit(inf[DType.float32](), -1)
    for i in range(len(scene.meshes)):
        var hits = caster.intersect_mesh(scene, assets, i)
        if len(hits) > 0 and hits[0].distance / scale < best.distance:
            best = SceneHit(hits[0].distance / scale, i)
    return best


def depth_frame(
    scene: Scene,
    assets: Assets,
    camera: CarlaTransform,
    intrinsics: CameraIntrinsics,
) raises -> Framebuffer:
    """Return a CARLA depth image: planar depth packed into RGB.

    Args:
        scene: The scene, updated.
        assets: Its geometry and materials.
        camera: Where the camera is and where it looks, in CARLA's frame.
        intrinsics: The image size and focal length.

    Returns:
        One pixel per ray. A miss is `DEPTH_FAR`.

    Raises:
        Error: If a mesh cannot be tested.
    """
    var out = Framebuffer(intrinsics.width, intrinsics.height, Color(0, 0, 0))
    for y in range(intrinsics.height):  # pragma: no branch
        for x in range(intrinsics.width):  # pragma: no branch
            var hit = nearest_hit(
                scene,
                assets,
                camera.location,
                intrinsics.ray(camera, Float32(x) + 0.5, Float32(y) + 0.5),
                DEPTH_FAR,
            )
            out.set_pixel(
                x, y, encode_depth(Length(min(hit.distance, 1000.0), METER))
            )
    return out^


def semantic_frame(
    scene: Scene,
    assets: Assets,
    tags: List[SemanticTag],
    miss: SemanticTag,
    camera: CarlaTransform,
    intrinsics: CameraIntrinsics,
) raises -> Framebuffer:
    """Return a CARLA semantic image in the CityScapes palette.

    Args:
        scene: The scene, updated.
        assets: Its geometry and materials.
        tags: One tag per mesh in `scene.meshes`.
        miss: The tag of a ray that meets nothing, such as `SKY`.
        camera: Where the camera is and where it looks, in CARLA's frame.
        intrinsics: The image size and focal length.

    Returns:
        One palette color per ray.

    Raises:
        Error: If `tags` does not name one tag per mesh, a tag is not
            valid, or a mesh cannot be tested.
    """
    if len(tags) != len(scene.meshes):
        raise Error("A semantic camera needs one tag per mesh")
    var out = Framebuffer(intrinsics.width, intrinsics.height, Color(0, 0, 0))
    for y in range(intrinsics.height):  # pragma: no branch
        for x in range(intrinsics.width):  # pragma: no branch
            var hit = nearest_hit(
                scene,
                assets,
                camera.location,
                intrinsics.ray(camera, Float32(x) + 0.5, Float32(y) + 0.5),
                DEPTH_FAR,
            )
            var tag = miss
            if hit.mesh >= 0:
                tag = tags[hit.mesh]
            out.set_pixel(x, y, cityscapes_color(tag))
    return out^
