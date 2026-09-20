# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a scene shows where nothing is drawn, from three.js `Scene.background`.

three.js's `background` is one field that holds one of three things: a
`Color`, a `Texture` or a `CubeTexture`, or nothing at all. A renderer
clears to the color, draws the texture stretched over the whole view, or
draws the cube texture as a sky the camera looks out into. Here the three
are one struct with a kind, for the reason `Fog` is: a scene has to hold
one type, and Mojo has no field that is one thing or another.

**A background is behind everything and claims no depth.** three.js draws
its texture and cube backgrounds as meshes with the depth test off, before
the scene, and clears to its color background. So here: `Renderer.render`
clears to the color, then paints the image where the camera looks, then
draws the scene over it. A surface at any depth covers the background, and
a translucent surface blends over it. Fog does not reach it, and nor does
it in three.js.

**A texture background is stretched over the viewport.** three.js draws a
`Texture` background on a plane that fills the view, whatever the aspect,
and so does this: the texture's own filter reads it, its full-size level,
and its transform is not applied. A cube background is looked up by the
direction each pixel's ray leaves the camera along, so it turns as the
camera turns and holds still as the camera moves. That is what a sky does.

The renderer's own `background` color remains: it is what a scene with no
background of its own is cleared to, three.js's `setClearColor`.

`environment` is the scene's other field of this family, and it is a plain
`CubeTextureId` on the scene rather than a kind here: a material naming
`SCENE_ENVIRONMENT` reflects it. See `core.scene`.
"""

from render.cube_texture_store import NO_CUBE_TEXTURE, CubeTextureId
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureId


@fieldwise_init
struct BackgroundKind(Equatable, ImplicitlyCopyable, Writable):
    """Which of the four things a background is, as a type rather than a
    bare int.

    See `core.fog.FogKind` for why. The type does not stop
    `BackgroundKind(9)`, so `Background.validate` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four kinds there are."""
        return (
            self == NO_BACKGROUND
            or self == COLOR_BACKGROUND
            or self == TEXTURE_BACKGROUND
            or self == CUBE_BACKGROUND
        )


# The scene says nothing: the renderer clears to its own color. What a
# scene starts with, and three.js's `background = null`.
comptime NO_BACKGROUND = BackgroundKind(0)
# A color the frame is cleared to, in place of the renderer's.
comptime COLOR_BACKGROUND = BackgroundKind(1)
# A texture stretched over the viewport, behind everything.
comptime TEXTURE_BACKGROUND = BackgroundKind(2)
# A cube texture the camera looks out into: a sky.
comptime CUBE_BACKGROUND = BackgroundKind(3)


struct Background(ImplicitlyCopyable):
    """What a scene shows where nothing is drawn: nothing, a color, a
    texture or a cube texture."""

    var kind: BackgroundKind
    # The clear color, read under `COLOR_BACKGROUND`. Its alpha is kept,
    # as the renderer's own clear color's is.
    var color: Color
    # The image, read under `TEXTURE_BACKGROUND`; `NO_TEXTURE` otherwise.
    var texture: TextureId
    # The sky, read under `CUBE_BACKGROUND`; `NO_CUBE_TEXTURE` otherwise.
    var cube: CubeTextureId

    def __init__(
        out self,
        kind: BackgroundKind,
        color: Color = Color(0, 0, 0),
        texture: TextureId = NO_TEXTURE,
        cube: CubeTextureId = NO_CUBE_TEXTURE,
    ):
        """Hold one of the four. Build one with `no_background`,
        `color_background`, `texture_background` or `cube_background`,
        which fill in the fields the kind does not read.

        Args:
            kind: Which of the four this is.
            color: The clear color, for `COLOR_BACKGROUND`.
            texture: The image, for `TEXTURE_BACKGROUND`.
            cube: The sky, for `CUBE_BACKGROUND`.
        """
        self.kind = kind
        self.color = color
        self.texture = texture
        self.cube = cube

    def is_set(self) -> Bool:
        """Return True if the scene says what to show behind everything."""
        return self.kind != NO_BACKGROUND

    def is_image(self) -> Bool:
        """Return True if the background is sampled from a texture or a
        cube texture rather than cleared to a color."""
        return self.kind == TEXTURE_BACKGROUND or self.kind == CUBE_BACKGROUND

    def validate(self) raises:
        """Refuse a background the renderer could not draw.

        The fields are open, so this is asked every frame, as `Fog.validate`
        is. Whether the id names something in the assets is the renderer's
        question, since only it holds them.

        Raises:
            Error: If the kind is none of the four, a texture background
                names `NO_TEXTURE` or a negative id, or a cube background
                names `NO_CUBE_TEXTURE` or a negative id.
        """
        if not self.kind.is_valid():
            raise Error("A background's kind is none of the four")
        if self.kind == TEXTURE_BACKGROUND and self.texture.value < 0:
            raise Error("A texture background must name a texture")
        if self.kind == CUBE_BACKGROUND and self.cube.value < 0:
            raise Error("A cube background must name a cube texture")


def no_background() -> Background:
    """Return the background a scene starts with: none, so the renderer
    clears to its own color.

    Returns:
        A `NO_BACKGROUND` background.
    """
    return Background(NO_BACKGROUND)


def color_background(color: Color) -> Background:
    """Return a background that clears the frame to a color, three.js's
    `scene.background = new Color(...)`.

    Args:
        color: The clear color, as authored in sRGB. Its alpha is kept.

    Returns:
        A `COLOR_BACKGROUND` background.
    """
    return Background(COLOR_BACKGROUND, color=color)


def texture_background(texture: TextureId) raises -> Background:
    """Return a background that stretches a texture over the viewport,
    three.js's `scene.background = texture`.

    Args:
        texture: Id of the image in the assets.

    Returns:
        A `TEXTURE_BACKGROUND` background.

    Raises:
        Error: If the id is `NO_TEXTURE` or negative: a texture background
            with no texture is `no_background`, and says so.
    """
    if texture.value < 0:
        raise Error("A texture background must name a texture")
    return Background(TEXTURE_BACKGROUND, texture=texture)


def cube_background(cube: CubeTextureId) raises -> Background:
    """Return a background that the camera looks out into, three.js's
    `scene.background = cubeTexture`: a sky.

    Args:
        cube: Id of the cube texture in the assets.

    Returns:
        A `CUBE_BACKGROUND` background.

    Raises:
        Error: If the id is `NO_CUBE_TEXTURE`, `SCENE_ENVIRONMENT` or
            otherwise negative: a sky must name six images of its own.
    """
    if cube.value < 0:
        raise Error("A cube background must name a cube texture")
    return Background(CUBE_BACKGROUND, cube=cube)
