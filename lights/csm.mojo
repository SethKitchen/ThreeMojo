# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cascaded shadow maps, from three.js `examples/jsm/csm/CSM.js`,
`CSMFrustum.js` and `CSMShader.js`.

**What a cascade is for.** One directional shadow map spread over a whole
view is coarse near the camera, where a texel covers much of the screen,
and wasted far away. A `CSM` cuts the camera's depth into slices and gives
each slice a directional light of its own, with a shadow camera fitted
around that slice alone. The near slice is small, so its map is sharp; the
far slices are large and coarse, where coarse is enough.

**How the slices are cut.** `CsmMode` picks where the breaks between
slices go, as fractions of the depth from the camera to its far plane or
to `max_far`, whichever is nearer. `UNIFORM_SPLIT` spaces them evenly,
`LOGARITHMIC_SPLIT` spaces them by ratio, `PRACTICAL_SPLIT` averages the
two, and `CUSTOM_SPLIT` takes them from the caller.

**How a fragment picks its slice.** Each light carries its slice as a
`lights.shadow.ShadowCascade`, and both rasterizers weigh the light by
where the fragment's depth falls: see `lights.shadow.cascade_reach`.

**Where this differs from three.js.** three.js marks each material that
reads the cascades with `setupMaterial`, and every other material sees
the cascade lights as plain directional lights. Here the slices live on
the lights, so every surface reads them and there is no `setupMaterial`.
A custom split is the list of breaks, not a callback that fills it. An
argument of zero is kept, where three.js's `data.x || default` replaces
it with the default. `update` also updates the scene's world matrices,
as the renderer needs them fresh. The node material `CSMShadowNode` is
not ported; `CSMHelper` is `helpers.csm`.
"""

from cameras.camera import Camera
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import directional_light
from lights.shadow import ShadowCascade
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import floor, isfinite, max, min
from units.si import Length, METER


@fieldwise_init
struct CsmMode(Equatable, ImplicitlyCopyable, Writable):
    """How a `CSM` cuts the camera's depth into slices, three.js's
    `CSM.mode`, as a type rather than a string.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `CsmMode(9)`, which `CSM` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of three.js's four split modes.

        Returns:
            Whether it is `UNIFORM_SPLIT`, `LOGARITHMIC_SPLIT`,
            `PRACTICAL_SPLIT` or `CUSTOM_SPLIT`.
        """
        return (
            self == UNIFORM_SPLIT
            or self == LOGARITHMIC_SPLIT
            or self == PRACTICAL_SPLIT
            or self == CUSTOM_SPLIT
        )


# three.js's `'uniform'`: breaks spaced evenly from the near plane.
comptime UNIFORM_SPLIT = CsmMode(0)
# three.js's `'logarithmic'`: each break a fixed ratio past the one before.
comptime LOGARITHMIC_SPLIT = CsmMode(1)
# three.js's `'practical'`, its default: halfway between the two above.
comptime PRACTICAL_SPLIT = CsmMode(2)
# three.js's `'custom'`: the breaks the caller gives.
comptime CUSTOM_SPLIT = CsmMode(3)
# three.js's `lerp` weight between the uniform and the logarithmic breaks
# in a practical split.
comptime PRACTICAL_LAMBDA = Float32(0.5)


def uniform_split(amount: Int, near: Float32, far: Float32) -> List[Float32]:
    """Return breaks spaced evenly between the planes, three.js's
    `uniformSplit`.

    Args:
        amount: How many slices.
        near: The camera's near plane, in meters.
        far: The furthest depth the slices reach, in meters.

    Returns:
        `amount` breaks as fractions of `far`, the last one.
    """
    var breaks = List[Float32]()
    for index in range(1, amount):
        breaks.append(
            (near + (far - near) * Float32(index) / Float32(amount)) / far
        )
    breaks.append(1)
    return breaks^


def logarithmic_split(
    amount: Int, near: Float32, far: Float32
) -> List[Float32]:
    """Return breaks spaced by ratio between the planes, three.js's
    `logarithmicSplit`.

    Args:
        amount: How many slices.
        near: The camera's near plane, in meters.
        far: The furthest depth the slices reach, in meters.

    Returns:
        `amount` breaks as fractions of `far`, the last one.
    """
    var breaks = List[Float32]()
    for index in range(1, amount):
        breaks.append(
            (near * (far / near) ** (Float32(index) / Float32(amount))) / far
        )
    breaks.append(1)
    return breaks^


def practical_split(
    amount: Int, near: Float32, far: Float32, weight: Float32
) -> List[Float32]:
    """Return breaks between the uniform and the logarithmic ones,
    three.js's `practicalSplit`.

    Args:
        amount: How many slices.
        near: The camera's near plane, in meters.
        far: The furthest depth the slices reach, in meters.
        weight: How far toward the logarithmic breaks, three.js's
            `lambda`; `CSM` passes `PRACTICAL_LAMBDA`.

    Returns:
        `amount` breaks as fractions of `far`, the last one.
    """
    var even = uniform_split(amount, near, far)
    var ratio = logarithmic_split(amount, near, far)
    var breaks = List[Float32]()
    for index in range(1, amount):
        var low = even[index - 1]
        breaks.append(low + (ratio[index - 1] - low) * weight)
    breaks.append(1)
    return breaks^


@fieldwise_init
struct CsmFrustum(Copyable, Movable):
    """The corners of a view volume, three.js's `CSMFrustum`: four on the
    near plane and four on the far, in the order top right, bottom right,
    bottom left, top left."""

    var near: List[Vector3]
    var far: List[Vector3]

    @staticmethod
    def empty() -> CsmFrustum:
        """Return a frustum with every corner at the origin.

        Returns:
            The frustum.
        """
        var near = List[Vector3](length=4, fill=Vector3(0, 0, 0))
        var far = List[Vector3](length=4, fill=Vector3(0, 0, 0))
        return CsmFrustum(near^, far^)

    @staticmethod
    def from_projection(projection: Matrix4, max_far: Float32) -> CsmFrustum:
        """Return a camera's view volume in its own space, cut at
        `max_far`: three.js's `setFromProjectionMatrix`.

        The corners of normalized device space go back through the
        inverse projection. A far corner past `max_far` is pulled in to
        it: along its ray for a perspective camera, and along the axis
        alone for an orthographic one.

        Args:
            projection: The camera's projection matrix.
            max_far: The furthest depth to keep, in meters.

        Returns:
            The frustum.
        """
        var orthographic = projection.elements[11] == 0
        var inverse = projection
        inverse.invert()
        var frustum = CsmFrustum.empty()
        # Four corners, always.
        for corner in range(4):  # pragma: no branch
            var x = Float32(1) if corner < 2 else Float32(-1)
            var y = Float32(1) if corner == 0 or corner == 3 else Float32(-1)
            frustum.near[corner] = inverse.transform_point(Vector3(x, y, -1))
            var far = inverse.transform_point(Vector3(x, y, 1))
            var shrink = min(max_far / abs(far.z), Float32(1))
            if orthographic:
                far.z *= shrink
            else:
                far = far * shrink
            frustum.far[corner] = far
        return frustum^

    def split(self, breaks: List[Float32]) -> List[CsmFrustum]:
        """Return one frustum per slice, cut at `breaks`: three.js's
        `split`.

        Args:
            breaks: Where each slice ends, as fractions from the near
                plane to the far.

        Returns:
            As many frustums as breaks.
        """
        var slices = List[CsmFrustum]()
        var last = len(breaks) - 1
        for index in range(len(breaks)):
            var cut = CsmFrustum.empty()
            # Four corners, always.
            for corner in range(4):  # pragma: no branch
                var near = self.near[corner]
                if index > 0:
                    near.lerp_vectors(
                        self.near[corner], self.far[corner], breaks[index - 1]
                    )
                var far = self.far[corner]
                if index < last:
                    far.lerp_vectors(
                        self.near[corner], self.far[corner], breaks[index]
                    )
                cut.near[corner] = near
                cut.far[corner] = far
            slices.append(cut^)
        return slices^

    def to_space(self, matrix: Matrix4) -> CsmFrustum:
        """Return this frustum's corners carried through `matrix`,
        three.js's `toSpace`.

        Args:
            matrix: The transform to apply.

        Returns:
            The moved frustum.
        """
        var moved = CsmFrustum.empty()
        # Four corners, always.
        for corner in range(4):  # pragma: no branch
            moved.near[corner] = matrix.transform_point(self.near[corner])
            moved.far[corner] = matrix.transform_point(self.far[corner])
        return moved^


struct CSM(Movable):
    """Directional lights that share one sun, each shadowing one slice of
    a camera's depth: three.js's `CSM`.

    Built into a scene: it adds one directional light per cascade, with a
    node and a target node under `parent`. Call `update` each frame, after
    the camera moves, and `update_frustums` after the camera's projection
    or the split changes.
    """

    var cascades: Int
    var max_far: Length
    var mode: CsmMode
    var shadow_map_size: Int
    var shadow_bias: Float32
    # Which way the sun shines, unit length.
    var light_direction: Vector3
    var light_intensity: Float32
    var light_near: Length
    var light_far: Length
    # How far behind each slice its light stands, along the direction.
    var light_margin: Length
    # The breaks `CUSTOM_SPLIT` uses, three.js's `customSplitsCallback`
    # already called.
    var custom_breaks: List[Float32]
    # Whether neighboring slices blend, three.js's `fade`. Set it, then
    # call `update_frustums`.
    var fade: Bool
    var parent: NodeId
    # Where each slice ends, as fractions of the depth.
    var breaks: List[Float32]
    var main_frustum: CsmFrustum
    var frustums: List[CsmFrustum]
    # Each cascade's light, as its index in `Scene.lights`, and its node
    # and its target's node.
    var lights: List[Int]
    var nodes: List[NodeId]
    var targets: List[NodeId]

    def __init__[
        C: Camera
    ](
        out self,
        mut scene: Scene,
        camera: C,
        parent: NodeId = NO_PARENT,
        cascades: Int = 3,
        max_far: Length = Length(100000.0, METER),
        mode: CsmMode = PRACTICAL_SPLIT,
        shadow_map_size: Int = 2048,
        shadow_bias: Float32 = 0.000001,
        light_direction: Vector3 = Vector3(1, -1, 1),
        light_intensity: Float32 = 3,
        light_near: Length = Length(1.0, METER),
        light_far: Length = Length(2000.0, METER),
        light_margin: Length = Length(200.0, METER),
        var custom_breaks: List[Float32] = List[Float32](),
    ) raises:
        """Add the cascades' lights to a scene and fit them to a camera,
        with three.js's defaults.

        Args:
            scene: The scene to add the lights and their targets to.
            camera: The camera whose depth is sliced.
            parent: The node the lights hang from, or `NO_PARENT` for the
                scene itself.
            cascades: How many slices.
            max_far: The furthest depth the slices reach.
            mode: How the depth is cut.
            shadow_map_size: Each light's map, texels a side.
            shadow_bias: Each light's `shadow.bias`.
            light_direction: Which way the sun shines; normalized here.
            light_intensity: Each light's intensity.
            light_near: Each shadow camera's near plane.
            light_far: Each shadow camera's far plane.
            light_margin: How far behind its slice each light stands.
            custom_breaks: The breaks for `CUSTOM_SPLIT`, one per slice,
                rising, from zero to one.

        Raises:
            Error: If there is no cascade; the mode is none of the four;
                the direction is zero or not finite; the furthest depth is
                not a positive length or the margin not finite; the custom
                breaks do not fit `CUSTOM_SPLIT`; or a light is refused by
                `Light.validate`.
        """
        if cascades < 1:
            raise Error("A CSM needs at least one cascade")
        if not mode.is_valid():
            raise Error("A CSM split mode that is none of the four")
        var direction = light_direction
        var length = direction.length()
        if not isfinite(length) or length == 0:
            raise Error("A CSM's light direction must be finite and not zero")
        direction.normalize()
        var reach = max_far.to(METER)
        if not isfinite(reach) or reach <= 0:
            raise Error("A CSM's furthest depth must be a positive length")
        if not isfinite(light_margin.to(METER)):
            raise Error("A CSM's light margin must be finite")
        if mode == CUSTOM_SPLIT:
            _check_breaks(custom_breaks, cascades)
        self.cascades = cascades
        self.max_far = max_far
        self.mode = mode
        self.shadow_map_size = shadow_map_size
        self.shadow_bias = shadow_bias
        self.light_direction = direction
        self.light_intensity = light_intensity
        self.light_near = light_near
        self.light_far = light_far
        self.light_margin = light_margin
        self.custom_breaks = custom_breaks^
        self.fade = False
        self.parent = parent
        self.breaks = List[Float32]()
        self.main_frustum = CsmFrustum.empty()
        self.frustums = List[CsmFrustum]()
        self.lights = List[Int]()
        self.nodes = List[NodeId]()
        self.targets = List[NodeId]()
        self._create_lights(scene)
        self.update_frustums(scene, camera)

    def _hung(self, mut scene: Scene) raises -> NodeId:
        """Add an empty node under `parent` and return it."""
        var node = scene.add(Object3D())
        if self.parent != NO_PARENT:
            scene.add(node, parent=self.parent)
        return node

    def _create_lights(mut self, mut scene: Scene) raises:
        """Add one casting directional light per cascade, three.js's
        `_createLights`."""
        # At least one cascade, as the constructor checks first.
        for _ in range(self.cascades):  # pragma: no branch
            var node = self._hung(scene)
            var target = self._hung(scene)
            var light = directional_light(
                Color(255, 255, 255), node, self.light_intensity, target
            )
            light.cast_shadow = True
            light.shadow.map_size = self.shadow_map_size
            light.shadow.near = self.light_near
            light.shadow.far = self.light_far
            light.shadow.bias = self.shadow_bias
            light.validate()
            self.lights.append(len(scene.lights))
            self.nodes.append(node)
            self.targets.append(target)
            scene.add_light(light)
        scene.update()

    def _furthest[C: Camera](self, camera: C) -> Float32:
        """Return the depth the slices reach: the camera's far plane or
        `max_far`, whichever is nearer."""
        return min(camera.far_distance(), self.max_far.to(METER))

    def _get_breaks[C: Camera](mut self, camera: C) raises:
        """Work out the breaks for the mode, three.js's `_getBreaks`."""
        var near = camera.near_distance()
        var far = self._furthest(camera)
        if self.mode == UNIFORM_SPLIT:
            self.breaks = uniform_split(self.cascades, near, far)
        elif self.mode == LOGARITHMIC_SPLIT:
            self.breaks = logarithmic_split(self.cascades, near, far)
        elif self.mode == PRACTICAL_SPLIT:
            self.breaks = practical_split(
                self.cascades, near, far, PRACTICAL_LAMBDA
            )
        elif self.mode == CUSTOM_SPLIT:
            _check_breaks(self.custom_breaks, self.cascades)
            self.breaks = self.custom_breaks.copy()
        else:
            raise Error("A CSM split mode that is none of the four")

    def _update_shadow_bounds[C: Camera](self, mut scene: Scene, camera: C):
        """Size each light's shadow camera to its slice, three.js's
        `_updateShadowBounds`."""
        # One frustum per cascade, and at least one cascade.
        for index in range(len(self.frustums)):  # pragma: no branch
            ref frustum = self.frustums[index]
            var first = frustum.far[0]
            var second = frustum.near[2]
            if first.distance_to(frustum.far[2]) > first.distance_to(
                frustum.near[2]
            ):
                second = frustum.far[2]
            var width = first.distance_to(second)
            if self.fade:
                var near = camera.near_distance()
                var far = max(camera.far_distance(), self.max_far.to(METER))
                var depth = frustum.far[0].z / (far - near)
                width += 0.25 * depth * depth * (far - near)
            ref shadow = scene.lights[self.lights[index]].shadow
            shadow.set_extent(Length(width / 2, METER))

    def _update_cascades[C: Camera](self, mut scene: Scene, camera: C):
        """Give each light its slice, three.js's `_updateUniforms` and
        `_getExtendedBreaks`."""
        var span = self._furthest(camera) - camera.near_distance()
        # At least one cascade.
        for index in range(self.cascades):  # pragma: no branch
            var start = Float32(0)
            if index > 0:
                start = self.breaks[index - 1]
            scene.lights[self.lights[index]].cascade = ShadowCascade(
                start,
                self.breaks[index],
                Length(span, METER),
                index == self.cascades - 1,
                self.fade,
            )

    def update_frustums[
        C: Camera
    ](mut self, mut scene: Scene, camera: C) raises:
        """Work out the breaks, slice the camera's frustum, and size and
        gate each light for it: three.js's `updateFrustums`.

        Args:
            scene: The scene holding the cascades' lights.
            camera: The camera whose depth is sliced.

        Raises:
            Error: If the custom breaks no longer fit, the camera's
                projection is refused, or the lights the CSM added are
                gone from the scene.
        """
        self._check_lights(scene)
        self._get_breaks(camera)
        self.main_frustum = CsmFrustum.from_projection(
            camera.projection_matrix(), self.max_far.to(METER)
        )
        self.frustums = self.main_frustum.split(self.breaks)
        self._update_shadow_bounds(scene, camera)
        self._update_cascades(scene, camera)

    def update[C: Camera](self, mut scene: Scene, camera: C) raises:
        """Move each light to stand behind its slice as the camera sees it
        now, three.js's `update`, and update the scene.

        Each slice's corners are turned into the light's frame, boxed, and
        the light placed at the box's middle, `light_margin` beyond its
        near face, snapped to whole texels of its map so the shadow does
        not crawl as the camera moves.

        Args:
            scene: The scene holding the cascades' lights, updated.
            camera: The camera whose depth is sliced.

        Raises:
            Error: If the lights the CSM added are gone from the scene, or
                the camera's view is refused.
        """
        self._check_lights(scene)
        var orientation = Matrix4()
        orientation.look_at(
            Vector3(0, 0, 0), self.light_direction, Vector3(0, 1, 0)
        )
        var inverse = orientation
        inverse.invert()
        var placed = camera.view_matrix_in(scene)
        placed.invert()
        var to_light = inverse
        to_light.multiply(placed)
        var size = Float32(self.shadow_map_size)
        # One frustum per cascade, and at least one cascade.
        for index in range(len(self.frustums)):  # pragma: no branch
            ref shadow = scene.lights[self.lights[index]].shadow
            var texel_width = (
                shadow.right.to(METER) - shadow.left.to(METER)
            ) / size
            var texel_height = (
                shadow.top.to(METER) - shadow.bottom.to(METER)
            ) / size
            var seen = self.frustums[index].to_space(to_light)
            var low = seen.near[0]
            var high = seen.near[0]
            # Four corners, always.
            for corner in range(4):  # pragma: no branch
                low = _lowest(_lowest(low, seen.near[corner]), seen.far[corner])
                high = _highest(
                    _highest(high, seen.near[corner]), seen.far[corner]
                )
            var center = Vector3(
                (low.x + high.x) * 0.5,
                (low.y + high.y) * 0.5,
                high.z + self.light_margin.to(METER),
            )
            center.x = floor(center.x / texel_width) * texel_width
            center.y = floor(center.y / texel_height) * texel_height
            center = orientation.transform_point(center)
            scene.node(self.nodes[index]).set_position(
                center.x, center.y, center.z
            )
            var aim = center + self.light_direction
            scene.node(self.targets[index]).set_position(aim.x, aim.y, aim.z)
        scene.update()

    def remove(self, mut scene: Scene) raises:
        """Take the lights and their targets off their parent, three.js's
        `remove`. A light whose node is off the scene no longer shines.

        Args:
            scene: The scene holding the cascades' lights.

        Raises:
            Error: If a node the CSM added is gone from the scene.
        """
        # One node per cascade, and at least one cascade.
        for index in range(len(self.nodes)):  # pragma: no branch
            scene.remove_from_parent(self.targets[index])
            scene.remove_from_parent(self.nodes[index])
        scene.update()

    def dispose(self, mut scene: Scene) raises:
        """Stop the lights gating by depth, three.js's `dispose`: each
        becomes a plain directional light.

        Args:
            scene: The scene holding the cascades' lights.

        Raises:
            Error: If the lights the CSM added are gone from the scene.
        """
        self._check_lights(scene)
        # One light per cascade, and at least one cascade.
        for index in range(len(self.lights)):  # pragma: no branch
            scene.lights[self.lights[index]].cascade = ShadowCascade.none()

    def _check_lights(self, scene: Scene) raises:
        """Refuse a scene that no longer holds the lights this added."""
        # One light per cascade, and at least one cascade.
        for index in range(len(self.lights)):  # pragma: no branch
            var at = self.lights[index]
            if at >= len(scene.lights) or scene.lights[at].node != (
                self.nodes[index]
            ):
                raise Error("A CSM's lights are not in this scene")


def _check_breaks(breaks: List[Float32], cascades: Int) raises:
    """Refuse custom breaks that are not one per slice, rising, from zero
    to one."""
    if len(breaks) != cascades:
        raise Error("A custom CSM split needs one break per cascade")
    var before = Float32(0)
    # As many breaks as cascades, and at least one cascade.
    for index in range(len(breaks)):  # pragma: no branch
        var at = breaks[index]
        if not isfinite(at) or at < before or at > 1:
            raise Error(
                "A custom CSM split's breaks must rise from zero to one"
            )
        before = at


def _lowest(a: Vector3, b: Vector3) -> Vector3:
    """Return the smaller of each component."""
    return Vector3(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))


def _highest(a: Vector3, b: Vector3) -> Vector3:
    """Return the larger of each component."""
    return Vector3(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
