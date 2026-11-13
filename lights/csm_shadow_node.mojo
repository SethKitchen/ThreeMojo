# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cascaded shadow for one directional light, from three.js
`examples/jsm/csm/CSMShadowNode.js`.

**What it is for.** `lights.csm.CSM` builds its own suns. A
`CSMShadowNode` takes one directional light the caller made, with its
color, its intensity and its shadow settings, and gives that light a
shadow in cascades. three.js sets it as the light's
`shadow.shadowNode`.

**How it lights.** three.js lights a surface once, and the node works out
one shadow value from the cascade that holds the surface's depth. Here a
cascade is a light: the node adds one casting directional light for each
cascade, and each carries a `lights.shadow.ShadowCascade` of
`NODE_BLEND`. `lights.shadow.csm_node_reach` splits three.js's one value
into the shares of those lights. The shares add up to one light, so the
surface is still lit once.

**The light.** The node keeps the light in `light` and reads it at each
`update`: the cascade lights take its color, its intensity and its
layers, and shine the way its node looks at its target. Each cascade's
shadow is a copy of the light's shadow whose bias is multiplied by the
cascade's number, counted from one, as three.js multiplies it.

**Where this differs from three.js.** three.js sets the node on a light
that is in the scene. Here the node holds the light and the scene holds
only its cascades, so do not add `light` to the scene as well. The
camera is an argument of `update` and `update_frustums`, where three.js
keeps the one it was first drawn with. A custom split is the list of
breaks, not a callback that fills it. An argument of zero is kept, where
three.js's `data.x || default` replaces it with the default. A light that
does not cast a shadow is refused, where three.js never sets the node up.
`update` also updates the scene's world matrices, as the renderer needs
them fresh. With `fade`, the split into shares is exact where at most
two slices overlap; see `csm_node_reach`.
"""

from cameras.camera import Camera
from core.object3d import NO_PARENT, NodeId, Object3D
from core.ordinal import require_positive, require_valid
from core.scene import Scene
from lights.csm import (
    CUSTOM_SPLIT,
    PRACTICAL_SPLIT,
    CsmFrustum,
    CsmMode,
    cascade_center,
    cascade_extent,
    csm_breaks,
    require_cascade_lights,
    require_csm_cascades,
    require_custom_breaks,
)
from lights.light import DIRECTIONAL, Light
from lights.shadow import NODE_BLEND, ShadowCascade
from math.finite import require_finite, require_positive_finite
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.math import max, min
from units.si import Length, METER


struct CSMShadowNode(Movable):
    """The cascades that shadow one directional light: three.js's
    `CSMShadowNode`.

    Built into a scene: it adds one casting directional light per
    cascade, each with a node and a target node beside the light's own
    node. Call `update` each frame, after the camera or the light moves,
    and `update_frustums` after the camera's projection, `mode` or
    `fade` changes.
    """

    # The light the cascades shadow, three.js's `light`. Its color, its
    # intensity and its layers are read at each `update`, and its node
    # and its target give the direction. It is not in the scene.
    var light: Light
    var cascades: Int
    var max_far: Length
    var mode: CsmMode
    # How far behind each slice its light stands, along the direction.
    var light_margin: Length
    # The breaks `CUSTOM_SPLIT` uses, three.js's `customSplitsCallback`
    # already called.
    var custom_breaks: List[Float32]
    # Whether neighboring slices blend, three.js's `fade`. Set it, then
    # call `update_frustums`.
    var fade: Bool
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
        light: Light,
        cascades: Int = 3,
        max_far: Length = Length(100000.0, METER),
        mode: CsmMode = PRACTICAL_SPLIT,
        light_margin: Length = Length(200.0, METER),
        var custom_breaks: List[Float32] = List[Float32](),
    ) raises:
        """Add a light's cascades to a scene and fit them to a camera,
        with three.js's defaults.

        Args:
            scene: The scene to add the cascade lights and their targets
                to. It holds the light's node, and its target when it
                names one.
            camera: The camera whose depth is sliced.
            light: The directional light to shadow. It must cast a
                shadow, and it must not be in the scene.
            cascades: How many slices.
            max_far: The furthest depth the slices reach.
            mode: How the depth is cut.
            light_margin: How far behind its slice each cascade light
                stands.
            custom_breaks: The breaks for `CUSTOM_SPLIT`, one per slice,
                rising, from zero to one.

        Raises:
            Error: If there is no cascade or the count is above 16777216;
                the mode is none of the four; the light is not
                directional, casts no shadow, is a cascade already or is
                refused by `Light.validate`; its node or its target is
                not in the scene; the furthest depth is not a positive
                length or the margin not finite; or the custom breaks do
                not fit `CUSTOM_SPLIT`.
        """
        require_positive(
            cascades, "A CSM shadow node needs at least one cascade"
        )
        require_csm_cascades(cascades)
        require_valid(
            mode.is_valid(), "A CSM split mode that is none of the four"
        )
        if light.kind != DIRECTIONAL:
            raise Error("A CSM shadow node shadows a directional light")
        if not light.cast_shadow:
            raise Error("A CSM shadow node's light must cast a shadow")
        if light.cascade.is_cascade():
            raise Error("A CSM shadow node's light is a cascade already")
        light.validate()
        _ = scene.get(light.node)
        if light.target != NO_PARENT:
            _ = scene.get(light.target)
        require_positive_finite(
            Float64(max_far.to(METER)),
            "A CSM shadow node's furthest depth must be a positive length",
        )
        require_finite(
            Float64(light_margin.to(METER)),
            "A CSM shadow node's light margin must be finite",
        )
        if mode == CUSTOM_SPLIT:
            require_custom_breaks(custom_breaks, cascades)
        self.light = light
        self.cascades = cascades
        self.max_far = max_far
        self.mode = mode
        self.light_margin = light_margin
        self.custom_breaks = custom_breaks^
        self.fade = False
        self.breaks = List[Float32]()
        self.main_frustum = CsmFrustum.empty()
        self.frustums = List[CsmFrustum]()
        self.lights = List[Int]()
        self.nodes = List[NodeId]()
        self.targets = List[NodeId]()
        self._create_lights(scene)
        self.update_frustums(scene, camera)

    def _hung(self, mut scene: Scene, parent: NodeId) raises -> NodeId:
        """Add an empty node under `parent` and return it."""
        var node = scene.add(Object3D())
        if parent != NO_PARENT:
            scene.add(node, parent=parent)
        return node

    def _create_lights(mut self, mut scene: Scene) raises:
        """Add one casting directional light per cascade beside the
        light's own node, three.js's `_init`."""
        var parent = scene.get(self.light.node).parent
        # At least one cascade, as the constructor checks first.
        for index in range(self.cascades):  # pragma: no branch
            var node = self._hung(scene, parent)
            var target = self._hung(scene, parent)
            var lamp = self.light
            lamp.node = node
            lamp.target = target
            lamp.shadow.bias = self.light.shadow.bias * Float32(index + 1)
            self.lights.append(len(scene.lights))
            self.nodes.append(node)
            self.targets.append(target)
            scene.add_light(lamp)
        scene.update()

    def _check_lights(self, scene: Scene) raises:
        """Refuse missing or malformed cascade mappings before indexing."""
        require_cascade_lights(
            scene, self.cascades, self.lights, self.nodes, self.targets
        )

    def direction(self, scene: Scene) raises -> Vector3:
        """Return which way the light shines, from its node toward its
        target: three.js's `_lightDirection`.

        Both positions are the nodes' own, relative to their parents, as
        three.js reads `light.position` and `light.target.position`. A
        light with no target shines toward the origin.

        Args:
            scene: The scene that holds the light's node and target.

        Returns:
            The direction, unit length.

        Raises:
            Error: If the node or the target is not in the scene, or the
                light stands on its target or a position is not finite.
        """
        var toward = Vector3(0, 0, 0)
        if self.light.target != NO_PARENT:
            toward = scene.get(self.light.target).position
        var way = toward - scene.get(self.light.node).position
        if not way.is_finite() or way == Vector3(0, 0, 0):
            raise Error(
                "A CSM shadow node's light must stand off its target, at a"
                " finite position"
            )
        way.normalize()
        return way

    def update_frustums[
        C: Camera
    ](mut self, mut scene: Scene, camera: C) raises:
        """Work out the breaks, slice the camera's frustum, and size and
        gate each cascade light for it: three.js's `updateFrustums`.

        Args:
            scene: The scene holding the cascades' lights.
            camera: The camera whose depth is sliced.

        Raises:
            Error: If the mode is none of the four, the custom breaks no
                longer fit, the camera's projection is refused, or the
                lights the node added are gone from the scene.
        """
        self._check_lights(scene)
        var near = camera.near_distance()
        var reach = min(camera.far_distance(), self.max_far.to(METER))
        self.breaks = csm_breaks(
            self.mode, self.cascades, near, reach, self.custom_breaks
        )
        self.main_frustum = CsmFrustum.from_projection(
            camera.projection_matrix(), self.max_far.to(METER)
        )
        self.frustums = self.main_frustum.split(self.breaks)
        var far = max(camera.far_distance(), self.max_far.to(METER))
        var span = reach - near
        # At least one cascade, and one frustum per break.
        for index in range(self.cascades):  # pragma: no branch
            var width = cascade_extent(
                self.frustums[index], self.fade, near, far
            )
            ref lamp = scene.lights[self.lights[index]]
            lamp.shadow.set_extent(Length(width / 2, METER))
            var start = Float32(0)
            if index > 0:
                start = self.breaks[index - 1]
            lamp.cascade = ShadowCascade(
                start,
                self.breaks[index],
                Length(span, METER),
                index == self.cascades - 1,
                self.fade,
                NODE_BLEND,
                near=near / span,
            )

    def update[C: Camera](self, mut scene: Scene, camera: C) raises:
        """Move each cascade light to stand behind its slice as the
        camera sees it now, and give it the light's color, intensity and
        layers: three.js's `updateBefore`. The scene is updated.

        Each slice's corners are turned into the light's frame and
        boxed. The cascade light stands at the box's middle,
        `light_margin` beyond its near face, snapped to whole texels of
        its map so the shadow does not crawl as the camera moves.

        Args:
            scene: The scene holding the cascades' lights, updated.
            camera: The camera whose depth is sliced.

        Raises:
            Error: If the lights the node added are gone from the scene,
                there is not one frustum of four corners per cascade, a
                cascade's shadow map has no texel, the light stands on
                its target, or the camera's view is refused.
        """
        self._check_lights(scene)
        if len(self.frustums) != self.cascades:
            raise Error("A CSM shadow node needs one frustum per cascade")
        # `_check_lights` requires a cascade; lengths match above.
        for frustum in self.frustums:  # pragma: no branch
            if len(frustum.near) != 4 or len(frustum.far) != 4:
                raise Error(
                    "A CSM shadow node's frustum needs four corners per plane"
                )
        var way = self.direction(scene)
        var orientation = Matrix4()
        orientation.look_at(Vector3(0, 0, 0), way, Vector3(0, 1, 0))
        var inverse = orientation
        inverse.invert()
        var placed = camera.view_matrix_in(scene)
        placed.invert()
        var to_light = inverse
        to_light.multiply(placed)
        # One frustum per cascade, and at least one cascade.
        for index in range(self.cascades):  # pragma: no branch
            ref lamp = scene.lights[self.lights[index]]
            lamp.color = self.light.color
            lamp.intensity = self.light.intensity
            lamp.layers = self.light.layers
            require_positive(
                lamp.shadow.map_size,
                "A CSM shadow node's shadow map size must be positive",
            )
            var size = Float32(lamp.shadow.map_size)
            var center = cascade_center(
                self.frustums[index],
                to_light,
                orientation,
                (lamp.shadow.right.to(METER) - lamp.shadow.left.to(METER))
                / size,
                (lamp.shadow.top.to(METER) - lamp.shadow.bottom.to(METER))
                / size,
                self.light_margin.to(METER),
            )
            scene.node(self.nodes[index]).set_position(
                center.x, center.y, center.z
            )
            var aim = center + way
            scene.node(self.targets[index]).set_position(aim.x, aim.y, aim.z)
        scene.update()

    def dispose(self, mut scene: Scene) raises:
        """Take the cascade lights and their targets off their parent,
        three.js's `dispose`. A light whose node is off the scene no
        longer shines.

        Add `light` to the scene to keep the light with a plain shadow.

        Args:
            scene: The scene holding the cascades' lights.

        Raises:
            Error: If a node the shadow node added is gone from the
                scene.
        """
        self._check_lights(scene)
        # One node per cascade, and at least one cascade.
        for index in range(self.cascades):  # pragma: no branch
            scene.remove_from_parent(self.targets[index])
            scene.remove_from_parent(self.nodes[index])
        scene.update()
