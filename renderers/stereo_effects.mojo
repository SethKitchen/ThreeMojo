# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stereo effects: three.js's `AnaglyphEffect`, `StereoEffect` and
`ParallaxBarrierEffect` from `examples/jsm/effects/`.

Each effect wraps a renderer and draws the scene twice, once for each eye
of a `cameras.stereo_camera.StereoCamera` made from the camera it is
given. They differ in how the two views become one image.

- `StereoEffect` puts them side by side, each in half the width, through
  an `ArrayCamera`.
- `AnaglyphEffect` mixes them into one color image through two Dubois
  matrices, for red and cyan glasses.
- `ParallaxBarrierEffect` interleaves them row by row, for a parallax
  barrier screen.

The two views are drawn as a render pass draws a frame, through the
renderer's antialias when that is on, and the image is resolved once
through the renderer's curve.
"""

from cameras.array_camera import ArrayCamera
from cameras.perspective_camera import PerspectiveCamera
from cameras.stereo_camera import StereoCamera
from core.assets import Assets
from core.scene import Scene
from math.matrix3 import Matrix3
from postprocessing.composer import draw_scene
from render.framebuffer import FloatColor, Framebuffer
from render.rect import Rect
from render.target import RenderTarget
from renderers.renderer import Renderer
from units.si import Length


def dubois_left() -> Matrix3:
    """Return `AnaglyphEffect.colorMatrixLeft`: the Dubois matrix for the
    left eye's red lens, column-major as three.js's `fromArray` reads it.

    Returns:
        The matrix.
    """
    var m = Matrix3()
    m.elements = [
        0.456100,
        -0.0400822,
        -0.0152161,
        0.500484,
        -0.0378246,
        -0.0205971,
        0.176381,
        -0.0157589,
        -0.00546856,
    ]
    return m


def dubois_right() -> Matrix3:
    """Return `AnaglyphEffect.colorMatrixRight`: the Dubois matrix for the
    right eye's cyan lens.

    Returns:
        The matrix.
    """
    var m = Matrix3()
    m.elements = [
        -0.0434706,
        0.378476,
        -0.0721527,
        -0.0879388,
        0.73364,
        -0.112961,
        -0.00155529,
        -0.0184503,
        1.2264,
    ]
    return m


def _clamp01(value: Float32) -> Float32:
    """Return a value clamped to zero through one."""
    return min(max(value, Float32(0)), Float32(1))


def anaglyph_pixel(
    left: FloatColor,
    right: FloatColor,
    left_matrix: Matrix3,
    right_matrix: Matrix3,
) -> FloatColor:
    """Return one pixel of `AnaglyphEffect`'s shader, before its curve.

    Args:
        left: The left eye's light, premultiplied.
        right: The right eye's light, premultiplied.
        left_matrix: `colorMatrixLeft`.
        right_matrix: `colorMatrixRight`.

    Returns:
        The two straight colors through their matrices, summed and clamped
        to zero through one, with the larger alpha: premultiplied.
    """
    var l = left.unpremultiplied()
    var r = right.unpremultiplied()
    ref a = left_matrix.elements
    ref b = right_matrix.elements
    var red = (a[0] * l.r + a[3] * l.g + a[6] * l.b) + (
        b[0] * r.r + b[3] * r.g + b[6] * r.b
    )
    var green = (a[1] * l.r + a[4] * l.g + a[7] * l.b) + (
        b[1] * r.r + b[4] * r.g + b[7] * r.b
    )
    var blue = (a[2] * l.r + a[5] * l.g + a[8] * l.b) + (
        b[2] * r.r + b[5] * r.g + b[8] * r.b
    )
    return FloatColor(
        _clamp01(red), _clamp01(green), _clamp01(blue), max(l.a, r.a)
    ).premultiplied()


def barrier_row_is_left(y: Int, height: Int) -> Bool:
    """Return True if a row of `ParallaxBarrierEffect`'s image shows the
    left eye: where its shader's `mod( gl_FragCoord.y, 2.0 ) > 1.0`.

    Args:
        y: The row, down from the top.
        height: The image's height.

    Returns:
        Whether the row, counted up from the bottom, is odd.
    """
    return (height - 1 - y) % 2 == 1


def _views(
    mut stereo: StereoCamera,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: PerspectiveCamera,
) raises -> Tuple[RenderTarget, RenderTarget]:
    """Place the eyes and draw the scene through each."""
    stereo.update(camera, scene)
    var left = RenderTarget(
        renderer.width, renderer.height, renderer.background
    )
    draw_scene(left, renderer, scene, assets, stereo.left)
    var right = RenderTarget(
        renderer.width, renderer.height, renderer.background
    )
    draw_scene(right, renderer, scene, assets, stereo.right)
    return (left^, right^)


struct AnaglyphEffect(Movable):
    """Red and cyan stereo in one image: three.js's `AnaglyphEffect`."""

    # `colorMatrixLeft` and `colorMatrixRight`: what each eye's color
    # becomes. The Dubois matrices by default.
    var color_matrix_left: Matrix3
    var color_matrix_right: Matrix3
    # The two eyes.
    var stereo: StereoCamera

    def __init__(out self) raises:
        """Start with the Dubois matrices and three.js's stereo camera.

        Raises:
            Error: Never; the stereo camera's defaults are valid.
        """
        self.color_matrix_left = dubois_left()
        self.color_matrix_right = dubois_right()
        self.stereo = StereoCamera()

    def render(
        mut self,
        renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
    ) raises -> Framebuffer:
        """Draw the scene once per eye and mix the two: three.js's
        `render`.

        Each eye is drawn into its own target, as three.js draws
        `_renderTargetL` and `_renderTargetR`, and each pixel is
        `anaglyph_pixel` of the two. The image is resolved through the
        renderer's curve, as the shader's `tonemapping_fragment` applies
        it.

        Args:
            renderer: What the scene is drawn with.
            scene: The scene.
            assets: The geometry, materials and textures it names.
            camera: The camera the eyes are made from.

        Returns:
            The image.

        Raises:
            Error: Everything `StereoCamera.update` and
                `Renderer.render_into` raise.
        """
        var views = _views(self.stereo, renderer, scene, assets, camera)
        var frame = RenderTarget(
            renderer.width, renderer.height, renderer.background
        )
        for slot in range(len(frame.colors)):  # pragma: no branch
            frame.colors[slot] = anaglyph_pixel(
                views[0].light_at(slot),
                views[1].light_at(slot),
                self.color_matrix_left,
                self.color_matrix_right,
            )
            frame.data[slot] = False
        return frame.resolve(
            renderer.workers,
            renderer.tone_curve(),
            renderer.tone_mapping_exposure,
        )


struct ParallaxBarrierEffect(Movable):
    """The two eyes on alternate rows: three.js's
    `ParallaxBarrierEffect`."""

    # The two eyes.
    var stereo: StereoCamera

    def __init__(out self) raises:
        """Start with three.js's stereo camera.

        Raises:
            Error: Never; the stereo camera's defaults are valid.
        """
        self.stereo = StereoCamera()

    def render(
        mut self,
        renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
    ) raises -> Framebuffer:
        """Draw the scene once per eye and interleave the rows: three.js's
        `render`.

        Args:
            renderer: What the scene is drawn with.
            scene: The scene.
            assets: The geometry, materials and textures it names.
            camera: The camera the eyes are made from.

        Returns:
            The image, through the renderer's curve.

        Raises:
            Error: Everything `StereoCamera.update` and
                `Renderer.render_into` raise.
        """
        var views = _views(self.stereo, renderer, scene, assets, camera)
        var frame = RenderTarget(
            renderer.width, renderer.height, renderer.background
        )
        for y in range(renderer.height):  # pragma: no branch
            for x in range(renderer.width):  # pragma: no branch
                var slot = y * renderer.width + x
                if barrier_row_is_left(y, renderer.height):
                    frame.colors[slot] = views[0].colors[slot]
                    frame.data[slot] = views[0].data[slot]
                else:
                    frame.colors[slot] = views[1].colors[slot]
                    frame.data[slot] = views[1].data[slot]
        return frame.resolve(
            renderer.workers,
            renderer.tone_curve(),
            renderer.tone_mapping_exposure,
        )


struct StereoEffect(Movable):
    """The two eyes side by side: three.js's `StereoEffect`."""

    # The two eyes, each at half the camera's aspect, as three.js sets
    # `_stereo.aspect = 0.5`.
    var stereo: StereoCamera

    def __init__(out self) raises:
        """Start with three.js's stereo camera at half the aspect.

        Raises:
            Error: Never; the defaults are valid.
        """
        self.stereo = StereoCamera(aspect=0.5)

    def set_eye_separation(mut self, separation: Length) raises:
        """Change how far apart the eyes are: three.js's
        `setEyeSeparation`.

        Args:
            separation: The distance.

        Raises:
            Error: If the separation is negative or not finite.
        """
        var kept = self.stereo.eye_separation
        self.stereo.eye_separation = separation
        try:
            self.stereo.validate()
        except failure:
            self.stereo.eye_separation = kept
            raise failure

    def render(
        mut self,
        mut renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: PerspectiveCamera,
    ) raises -> Framebuffer:
        """Draw the left eye in the left half and the right eye in the
        right half: three.js's `render`.

        three.js sets a viewport and a scissor of half the width for each
        eye, rounded as WebGL rounds them. The left half is the width over
        two, rounded up, as three.js's is. The right half is the rest; for
        an odd width three.js's right viewport hangs one pixel off the
        image, and this one does not. The renderer's viewport and scissor
        are put back.

        Args:
            renderer: What the scene is drawn with.
            scene: The scene.
            assets: The geometry, materials and textures it names.
            camera: The camera the eyes are made from.

        Returns:
            The image.

        Raises:
            Error: If the renderer is narrower than two pixels, and
                everything `StereoCamera.update` and
                `Renderer.render_array` raise.
        """
        if renderer.width < 2:
            raise Error("A stereo image needs at least two columns")
        self.stereo.update(camera, scene)
        var half = (renderer.width + 1) // 2
        var array = ArrayCamera()
        array.add(self.stereo.left, Rect(0, 0, half, renderer.height))
        array.add(
            self.stereo.right,
            Rect(half, 0, renderer.width - half, renderer.height),
        )
        return renderer.render_array(scene, assets, array)
