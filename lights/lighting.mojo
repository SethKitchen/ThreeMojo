# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene's lights resolved to world space, ready to evaluate per vertex.

Separate from `lights.light` so the import graph stays acyclic: `core.scene`
holds `Light` values, and this holds a `Scene`. Putting both in one module
would make the two import each other.
"""

from core.scene import Scene
from lights.light import AMBIENT, DIRECTIONAL, Light
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from std.math import max


struct Lighting(Movable):
    """Every light in a scene, resolved to world space and ready to evaluate.

    Built once per frame rather than once per vertex: a light's direction
    needs its node's world matrix, and reading one per vertex would be the
    same work thousands of times over for an answer that cannot change
    within a frame.
    """

    # The sum of every ambient light, already decoded and scaled.
    var ambient: FloatColor
    # One entry per directional light, parallel lists.
    var directions: List[Vector3]
    var radiances: List[FloatColor]

    def __init__(out self, scene: Scene) raises:
        """Resolve a scene's lights against the world transforms it holds.

        Args:
            scene: The transform hierarchy, already updated, and the lights
                added to it.

        Raises:
            Error: If a light's kind is not one of the two, a directional
                light names a node the scene does not have, or its node sits
                exactly at the origin — which gives no direction to shine
                from, and is a mistake rather than a dark light.
        """
        self.ambient = FloatColor(0.0, 0.0, 0.0, 1.0)
        self.directions = List[Vector3]()
        self.radiances = List[FloatColor]()
        for light in scene.lights:
            if light.kind == AMBIENT:
                var fill = light.radiance()
                self.ambient = FloatColor(
                    self.ambient.r + fill.r,
                    self.ambient.g + fill.g,
                    self.ambient.b + fill.b,
                    1.0,
                )
            elif light.kind == DIRECTIONAL:
                # Where the node ended up after every transform above it.
                var pointing = scene.world_matrix(light.node).transform_point(
                    Vector3(0, 0, 0)
                )
                if pointing.length() == 0:
                    raise Error("A directional light needs a direction")
                pointing.normalize()
                self.directions.append(pointing)
                self.radiances.append(light.radiance())
            else:
                raise Error("Unknown light kind")

    def count(self) -> Int:
        """Return how many directional lights there are."""
        return len(self.directions)

    def shade(self, base: Color, normal: Vector3) -> FloatColor:
        """Return `base` lit by every light, in linear light.

        Lambert per directional light — how much a surface catches falls off
        with the cosine of the angle it is turned through — summed, plus the
        ambient term, and the total multiplies the surface's own colour.

        The base colour is decoded from sRGB first: an authored byte is not
        proportional to light, and multiplying it by a Lambert term would be
        arithmetic on the wrong numbers. See `render.srgb`.

        Nothing is clamped. A surface under two bright lamps really is over
        one, and `RenderTarget.resolve` is the single place that decides what
        a display can show. Clamping here would do it twice and lose the
        headroom in between.

        Args:
            base: The surface's own colour, as authored.
            normal: Its unit normal, in world space.

        Returns:
            The lit colour, linear, with the base colour's alpha.
        """
        var total = self.ambient
        for index in range(len(self.directions)):
            var lambert = max(Float32(0), normal.dot(self.directions[index]))
            if lambert == 0:
                continue
            ref light = self.radiances[index]
            total = FloatColor(
                total.r + light.r * lambert,
                total.g + light.g * lambert,
                total.b + light.b * lambert,
                1.0,
            )
        var surface = FloatColor(srgb=base)
        return FloatColor(
            surface.r * total.r,
            surface.g * total.g,
            surface.b * total.b,
            surface.a,
        )
