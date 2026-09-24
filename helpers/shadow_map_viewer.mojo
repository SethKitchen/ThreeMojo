# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A light's shadow map, shown in a rectangle over the image, from three.js
`examples/jsm/utils/ShadowMapViewer.js`.

The map is drawn as a gray square: white where the caster is at the light's
near plane, black at the far plane and where nothing was drawn. That is
three.js's `UnpackDepthRGBAShader`, `1 - depth`, with the map's depth from
zero at the near plane to one at the far, as `lights.shadow.ShadowMap`
holds it. It works for a directional light and a spot light, as three.js's
does.

**Where it is drawn.** `x` and `y` are the pixels from the image's top left
corner to the rectangle's, three.js's `position`, and `width` and `height`
its size, three.js's `size`. three.js draws a 256 pixel plane, scaled to
the size, through an orthographic camera one pixel a unit across the whole
window, after it clears the depth. Here `hud` builds that plane and camera
for the renderer's size, and `render` draws them inside the rectangle with
the scissor test on. The plane covers the rectangle, so the clear the
scissor makes first is never seen.

**The gray.** three.js's shader writes `1 - depth` to the canvas as it is,
without the conversion to sRGB, as it includes no `colorspace_fragment`.
Here a fragment is linear light and the frame is converted once when it is
resolved. So the map is kept as sRGB bytes, `1 - depth` rounded to a byte,
and a byte comes back from the resolve as it went in. The map is read with
the nearest texel, as three.js's shadow map is.

**Both backends.** The plane is a `BASIC` map, which both rasterizers
draw. To draw on the GPU, prepare `hud`'s scene with `Renderer.prepare_frame`,
upload its textures, and pass `rect` as the draw's scissor.

**Not ported.** The label with the light's name, which three.js writes
with a 2D canvas: this port has no canvas text. `update` and
`updateForWindowResize` have no counterpart, because `hud` reads the
renderer's size each time. A point light's six faces and a variance map's
moments are refused: three.js's shader reads neither.
"""

from animation.keyframe_track import LightIndex
from cameras.orthographic_camera import OrthographicCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import DIRECTIONAL, SPOT
from lights.shadow import VSM_SHADOW_MAP
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.rect import Rect
from render.srgb import SRGB
from render.target import RenderTarget
from render.texture import CLAMP, NEAREST, Texture
from renderers.renderer import Renderer
from std.math import max, min
from units.si import Length, METER

# three.js's `frame`: where the viewer starts and the size of its plane.
comptime SHADOW_VIEWER_X = 10
comptime SHADOW_VIEWER_Y = 10
comptime SHADOW_VIEWER_FRAME = 256


struct ShadowMapHud(Movable):
    """What a shadow map viewer draws: its scene, the assets the scene
    names, and the camera it is drawn through."""

    var scene: Scene
    var assets: Assets
    var camera: OrthographicCamera

    def __init__(
        out self,
        var scene: Scene,
        var assets: Assets,
        var camera: OrthographicCamera,
    ):
        """Hold a built viewer.

        Args:
            scene: The plane, on its node.
            assets: The plane's geometry, material and map.
            camera: The camera one pixel a unit across the image.
        """
        self.scene = scene^
        self.assets = assets^
        self.camera = camera^


def shadow_gray(depth: Float32) -> UInt8:
    """Return the byte three.js's `UnpackDepthRGBAShader` shows for a
    depth.

    Args:
        depth: A shadow map's depth, from zero at the near plane to one at
            the far, or infinity where nothing was drawn.

    Returns:
        `1 - depth`, the depth held between zero and one, as a byte.
    """
    var held = max(Float32(0), min(Float32(1), depth))
    return UInt8(Int((1 - held) * 255 + 0.5))


struct ShadowMapViewer(Copyable, Movable):
    """Shows one light's shadow map over the image. three.js:
    `ShadowMapViewer`."""

    # Which of the scene's lights, three.js's `light`.
    var light: LightIndex
    # Whether `render` draws anything, three.js's `enabled`.
    var enabled: Bool
    # The pixels from the image's top left corner to the viewer's,
    # three.js's `position`.
    var x: Int
    var y: Int
    # The viewer's size in pixels, three.js's `size`.
    var width: Int
    var height: Int

    def __init__(out self, light: LightIndex) raises:
        """Create a viewer at three.js's place and size: ten pixels from
        the top left corner, 256 pixels a side.

        Args:
            light: Which of the scene's lights to show.

        Raises:
            Error: If the index is negative.
        """
        if not light.is_valid():
            raise Error("A shadow map viewer needs a light index")
        self.light = light
        self.enabled = True
        self.x = SHADOW_VIEWER_X
        self.y = SHADOW_VIEWER_Y
        self.width = SHADOW_VIEWER_FRAME
        self.height = SHADOW_VIEWER_FRAME

    def rect(self, width: Int, height: Int) -> Optional[Rect]:
        """Return the pixels the viewer covers on an image of a size.

        Args:
            width: The image's width in pixels.
            height: The image's height in pixels.

        Returns:
            The part of the viewer inside the image, its corner counted up
            from the bottom as `render.rect` counts it, or none if no part
            is inside.
        """
        var left = max(self.x, 0)
        var right = min(self.x + self.width, width)
        var top = max(self.y, 0)
        var bottom = min(self.y + self.height, height)
        if left >= right or top >= bottom:
            return None
        return Rect(left, height - bottom, right - left, bottom - top)

    def hud(
        self, renderer: Renderer, scene: Scene, assets: Assets
    ) raises -> ShadowMapHud:
        """Draw the light's shadow map and build what shows it.

        Args:
            renderer: The renderer the image is drawn with. Its size places
                the plane, and its shadow settings draw the map.
            scene: The scene, updated, with the light.
            assets: The geometry and materials the casters name.

        Returns:
            The plane on its node, and the camera.

        Raises:
            Error: If the light index is negative or past the scene's
                lights, the light is not a directional or a spot light,
                it has no shadow map, the renderer's shadow maps are
                variance maps, the size is not positive, or anything
                `Renderer.shadow_maps` raises.
        """
        if not self.light.is_valid() or self.light.value >= len(scene.lights):
            raise Error("A shadow map viewer needs a light of the scene")
        if self.width <= 0 or self.height <= 0:
            raise Error("A shadow map viewer needs a positive size")
        ref light = scene.lights[self.light.value]
        if light.kind != DIRECTIONAL and light.kind != SPOT:
            raise Error(
                "A shadow map viewer shows a directional or a spot light"
            )
        if renderer.shadow_map_type == VSM_SHADOW_MAP:
            raise Error("A shadow map viewer cannot show a variance map")
        var pixels = List[UInt8]()
        var size = 0
        for map in renderer.shadow_maps(scene, assets):
            if map.light != self.light.value:
                continue
            size = map.size
            for depth in map.depths:  # pragma: no branch
                var gray = shadow_gray(depth)
                pixels.append(gray)
                pixels.append(gray)
                pixels.append(gray)
                pixels.append(255)
        if size == 0:
            raise Error("A shadow map viewer needs a light that casts")
        var hud_assets = Assets()
        var map = hud_assets.textures.add(
            Texture(size, size, pixels^, CLAMP, NEAREST, SRGB, False)
        )
        var half_width = Float32(renderer.width) / 2
        var half_height = Float32(renderer.height) / 2
        var hud_scene = Scene()
        var quad = Object3D()
        quad.set_position(
            -half_width + Float32(self.width) / 2 + Float32(self.x),
            half_height - Float32(self.height) / 2 - Float32(self.y),
            0,
        )
        quad.set_scale(
            Float32(self.width) / Float32(SHADOW_VIEWER_FRAME),
            Float32(self.height) / Float32(SHADOW_VIEWER_FRAME),
            1,
        )
        var node = hud_scene.add(quad^)
        var side = Length(Float32(SHADOW_VIEWER_FRAME), METER)
        hud_scene.add_mesh(
            Mesh(
                hud_assets.geometries.add(plane(side, side)),
                hud_assets.materials.add(
                    Material(
                        Color(255, 255, 255), map=map, kind=BASIC, fog=False
                    )
                ),
                node,
            )
        )
        hud_scene.update()
        var camera = OrthographicCamera(
            Length(-half_width, METER),
            Length(half_width, METER),
            Length(half_height, METER),
            Length(-half_height, METER),
            Length(1.0, METER),
            Length(10.0, METER),
        )
        camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
        return ShadowMapHud(hud_scene^, hud_assets^, camera^)

    def render(
        self,
        mut renderer: Renderer,
        mut target: RenderTarget,
        scene: Scene,
        assets: Assets,
    ) raises:
        """Draw the viewer over a target, as three.js's `render` does.

        Nothing is drawn when `enabled` is off or no part of the viewer is
        inside the target. The renderer's scissor and scissor test are
        put back afterward.

        Args:
            renderer: The renderer the target was drawn with.
            target: The image to draw over. It must be the renderer's size.
            scene: The scene, updated, with the light.
            assets: The geometry and materials the casters name.

        Raises:
            Error: Everything `hud` and `Renderer.render_into` raise.
        """
        if not self.enabled:
            return
        var inside = self.rect(renderer.width, renderer.height)
        if not Bool(inside):
            return
        var hud = self.hud(renderer, scene, assets)
        var scissor = renderer.scissor
        var scissor_test = renderer.scissor_test
        renderer.scissor = inside.value()
        renderer.scissor_test = True
        try:
            renderer.render_into(target, hud.scene, hud.assets, hud.camera)
        except failure:
            renderer.scissor = scissor
            renderer.scissor_test = scissor_test
            raise failure
        renderer.scissor = scissor
        renderer.scissor_test = scissor_test
