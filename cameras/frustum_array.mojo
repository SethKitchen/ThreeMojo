# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The views of an array camera, from three.js `src/math/FrustumArray.js`.

Something is in view of an `ArrayCamera` when it is in view of any one of
its cameras. Each test builds each camera's frustum from its projection
times its view, and asks it in turn. An array with no cameras sees
nothing.

three.js keeps this beside `Frustum` in `src/math`. It is here because it
reads cameras and a scene, and the math package reads neither.
"""

from cameras.array_camera import ArrayCamera
from core.assets import Assets
from core.object_bounds import intersects_object, intersects_sprite
from core.scene import Scene
from math.bounds import Box3, Sphere
from math.frustum import CoordinateSystem, Frustum, WEBGL_COORDINATES
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite


@fieldwise_init
struct FrustumArray(ImplicitlyCopyable):
    """The frustums of an array camera's cameras, asked together."""

    # The coordinate system each camera's frustum is read in. three.js
    # keeps the field and reads each camera's own; every camera here
    # projects for WebGL, so it is WebGL unless set.
    var coordinate_system: CoordinateSystem

    def __init__(out self):
        """Create one that reads WebGL projections, as three.js's does."""
        self.coordinate_system = WEBGL_COORDINATES

    def frustums(
        self, cameras: ArrayCamera, scene: Scene
    ) raises -> List[Frustum]:
        """Return each camera's frustum in world space.

        Args:
            cameras: The array camera.
            scene: The scene, updated, whose nodes a camera can ride.

        Returns:
            One frustum per camera, in the array's order.

        Raises:
            Error: If a camera's projection is degenerate, it rides a node
                the scene does not have, the scene is stale, or the
                coordinate system is neither of the two.
        """
        var out = List[Frustum]()
        for index in range(len(cameras.cameras)):
            ref camera = cameras.cameras[index]
            var clip = camera.projection_matrix()
            clip.multiply(camera.view_matrix_in(scene))
            out.append(
                Frustum.from_projection_matrix(clip, self.coordinate_system)
            )
        return out^

    def intersects_object(
        self, cameras: ArrayCamera, scene: Scene, assets: Assets, mesh: Mesh
    ) raises -> Bool:
        """Return True if any camera sees some of a mesh's bound, three.js's
        `intersectsObject`.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            assets: Where the geometry lives.
            mesh: The mesh.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` or
                `core.object_bounds.intersects_object` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if intersects_object(views[index], scene, assets, mesh):
                return True
        return False

    def intersects_object(
        self, cameras: ArrayCamera, scene: Scene, assets: Assets, line: Line
    ) raises -> Bool:
        """Return True if any camera sees some of a line's bound.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            assets: Where the geometry lives.
            line: The line.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` or
                `core.object_bounds.intersects_object` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if intersects_object(views[index], scene, assets, line):
                return True
        return False

    def intersects_object(
        self,
        cameras: ArrayCamera,
        scene: Scene,
        assets: Assets,
        points: Points,
    ) raises -> Bool:
        """Return True if any camera sees some of a set of points' bound.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            assets: Where the geometry lives.
            points: The points.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` or
                `core.object_bounds.intersects_object` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if intersects_object(views[index], scene, assets, points):
                return True
        return False

    def intersects_object(
        self,
        cameras: ArrayCamera,
        scene: Scene,
        assets: Assets,
        mesh: InstancedMesh,
    ) raises -> Bool:
        """Return True if any camera sees some of an instanced mesh's
        bound.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            assets: Where the geometry lives.
            mesh: The instanced mesh.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` or
                `core.object_bounds.intersects_object` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if intersects_object(views[index], scene, assets, mesh):
                return True
        return False

    def intersects_sprite(
        self, cameras: ArrayCamera, scene: Scene, sprite: Sprite
    ) raises -> Bool:
        """Return True if any camera sees some of a sprite's bound,
        three.js's `intersectsSprite`.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            sprite: The sprite.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` or
                `core.object_bounds.intersects_sprite` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if intersects_sprite(views[index], scene, sprite):
                return True
        return False

    def intersects_sphere(
        self, cameras: ArrayCamera, scene: Scene, sphere: Sphere
    ) raises -> Bool:
        """Return True if any camera sees some of a sphere, three.js's
        `intersectsSphere`.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            sphere: The sphere, in world space.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if views[index].intersects_sphere(sphere):
                return True
        return False

    def intersects_box(
        self, cameras: ArrayCamera, scene: Scene, box: Box3
    ) raises -> Bool:
        """Return True if any camera sees some of a box, three.js's
        `intersectsBox`.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            box: The box, in world space.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if views[index].intersects_box(box):
                return True
        return False

    def contains_point(
        self, cameras: ArrayCamera, scene: Scene, point: Vector3
    ) raises -> Bool:
        """Return True if any camera sees a point, three.js's
        `containsPoint`.

        Args:
            cameras: The array camera.
            scene: The scene, updated.
            point: The point, in world space.

        Returns:
            Whether some camera sees it. False for no cameras.

        Raises:
            Error: For anything `frustums` raises for.
        """
        var views = self.frustums(cameras, scene)
        for index in range(len(views)):
            if views[index].contains_point(point):
                return True
        return False
