# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Render targets with layers and levels, from three.js's
`src/core/RenderTarget3D.js`, `src/renderers/WebGL3DRenderTarget.js`,
`src/renderers/WebGLArrayRenderTarget.js` and
`src/renderers/WebGLCubeRenderTarget.js`.

**One image per layer and level.** three.js binds one layer of a 3D or
array texture, or one face and one mip level of a cube, as the
framebuffer: `setRenderTarget(target, activeCubeFace, activeMipmapLevel)`.
A `LayeredRenderTarget` holds a `RenderTarget` for each of those pairs,
and `image(layer, level)` is the one a draw goes into. So every feature a
`RenderTarget` has -- its type, its samples, its depth and stencil -- works
in a layer as it works in a plain target.

**The textures are built when they are asked for.** `texture_3d`,
`array_texture`, `cube_texture` and `texture` read each image's
`attachment(0)`, the light as the target's type stores it, and lay the
images out as three.js's `Data3DTexture`, `DataArrayTexture`,
`CubeTexture` or a mipmapped `Texture` holds them.

**Rows.** A volume's rows run up, as three.js stores a 3D texture and as
`render.volume_texture` reads one, so the rendered image's bottom row is
row zero of its layer. A cube face and a 2D level keep the rendered
image's rows, top first, as `render.texture.Texture` stores any image.

**Levels.** A cube or a 2D target can hold a mip chain. Each level is its
own image, half the size of the one before, and a draw can go into any of
them. `generate_mipmaps` fills every level from the one above it, the box
average of `RenderTarget.downsampled`. A chain needs a square target whose
side is a power of two, so that every level halves exactly. three.js keeps
no chain on a 3D or an array target, and neither does this.
"""

from render.cube_texture import (
    FACE_COUNT,
    CubeTexture,
    equirect_uv,
    face_direction,
)
from render.framebuffer import Color
from render.rect import Rect
from render.srgb import LINEAR
from render.target import (
    UNSIGNED_BYTE_TARGET,
    RenderTarget,
    TargetType,
)
from render.texture import (
    BILINEAR,
    CLAMP,
    Filter,
    Texture,
    float_texture,
    minifying,
)
from render.volume_texture import Data3DTexture, DataArrayTexture, VolumeImage
from std.math import max


@fieldwise_init
struct TargetKind(Equatable, ImplicitlyCopyable, Writable):
    """What a layered render target's layers are, as a type rather than a
    bare int: three.js's four render target classes.

    The type stops a bare integer at compile time; it does not stop
    `TargetKind(4)`, which `LayeredRenderTarget.validate` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four kinds there are.

        Returns:
            True for `TARGET_2D`, `TARGET_3D`, `TARGET_ARRAY` and
            `TARGET_CUBE`.
        """
        return (
            self == TARGET_2D
            or self == TARGET_3D
            or self == TARGET_ARRAY
            or self == TARGET_CUBE
        )


# One layer, and a mip chain: three.js's `WebGLRenderTarget` whose texture
# has levels a draw can go into.
comptime TARGET_2D = TargetKind(0)
# Layers of a volume: three.js's `RenderTarget3D` and `WebGL3DRenderTarget`.
comptime TARGET_3D = TargetKind(1)
# A stack of images: three.js's `WebGLArrayRenderTarget`.
comptime TARGET_ARRAY = TargetKind(2)
# Six square faces: three.js's `WebGLCubeRenderTarget`.
comptime TARGET_CUBE = TargetKind(3)


def full_chain(width: Int, height: Int) -> Int:
    """Return how many levels a full mip chain of that size holds, down to
    one texel.

    Args:
        width: The first level's width.
        height: The first level's height.

    Returns:
        One more than how many times the longer side halves to one.
    """
    var levels = 1
    var side = max(width, height)
    while side > 1:
        side = side >> 1
        levels += 1
    return levels


def level_extent(extent: Int, level: Int) -> Int:
    """Return how many pixels one side of a level holds, never below one,
    as `Texture.level_width` counts them.

    Args:
        extent: The side of the first level.
        level: Which level, zero being the first.

    Returns:
        The side of that level.
    """
    return max(1, extent >> level)


def _byte(value: Float32) -> UInt8:
    """Return the byte a byte target's stored fraction stands for."""
    return UInt8(Int(value * 255 + 0.5))


struct LayeredRenderTarget(Movable):
    """A render target of several layers, or of several levels, or both:
    three.js's 3D, array and cube render targets, and a 2D one with a
    chain. Build one with `render_target_3d`, `array_render_target`,
    `cube_render_target` or `mipmapped_render_target`."""

    var kind: TargetKind
    # The first level's size.
    var width: Int
    var height: Int
    # How many layers: three.js's `depth`, one for a 2D target and six
    # for a cube.
    var depth: Int
    # How many levels each layer holds, one for no chain.
    var levels: Int
    # One target per layer and level, layer by layer, each layer's levels
    # from the largest: the image of `(layer, level)` is at
    # `layer * levels + level`.
    var images: List[RenderTarget]

    def __init__(
        out self,
        kind: TargetKind,
        width: Int,
        height: Int,
        depth: Int,
        clear: Color = Color(0, 0, 0, 0),
        type: TargetType = UNSIGNED_BYTE_TARGET,
        samples: Int = 0,
        levels: Int = 1,
    ) raises:
        """Create a layered target, every image cleared to `clear`.

        Args:
            kind: What the layers are.
            width: The first level's width in pixels.
            height: The first level's height in pixels.
            depth: How many layers: one for `TARGET_2D`, six for
                `TARGET_CUBE`.
            clear: The color every image starts at, decoded from sRGB.
            type: What every image stores; see `render.target.TargetType`.
            samples: How many samples every image takes when drawn into;
                see `RenderTarget.samples`.
            levels: How many levels each layer holds. One, the default,
                is no chain.

        Raises:
            Error: If the kind is none of the four, a dimension is not
                positive, a 2D target has more than one layer, a cube is
                not six square faces, the level count is below one or
                above the full chain, a 3D or array target asks for a
                chain, a chain is not square with a power of two side, or
                `RenderTarget` refuses the type or the samples.
        """
        if not kind.is_valid():
            raise Error("A layered target's kind must be one of the four")
        if width <= 0 or height <= 0 or depth <= 0:
            raise Error("A layered target's dimensions must be positive")
        if kind == TARGET_2D and depth != 1:
            raise Error("A 2D target has one layer")
        if kind == TARGET_CUBE and (depth != FACE_COUNT or width != height):
            raise Error("A cube target has six square faces")
        if levels < 1 or levels > full_chain(width, height):
            raise Error("A layered target holds one level up to a full chain")
        var chained = levels > 1
        if chained and (kind == TARGET_3D or kind == TARGET_ARRAY):
            raise Error("A 3D or array target keeps no mip chain")
        if chained and (width != height or (width & (width - 1)) != 0):
            raise Error(
                "A target with a mip chain must be square, its side a"
                " power of two"
            )
        self.kind = kind
        self.width = width
        self.height = height
        self.depth = depth
        self.levels = levels
        self.images = List[RenderTarget]()
        # Both counts are positive, so neither loop runs zero times.
        for _layer in range(depth):  # pragma: no branch
            for level in range(levels):  # pragma: no branch
                self.images.append(
                    RenderTarget(
                        level_extent(width, level),
                        level_extent(height, level),
                        clear,
                        type,
                        samples=samples,
                    )
                )

    def validate(self) raises:
        """Refuse a target whose open fields were edited into nonsense.

        Raises:
            Error: If the kind is none of the four, or the images do not
                number one per layer and level.
        """
        if not self.kind.is_valid():
            raise Error("A layered target's kind must be one of the four")
        if len(self.images) != self.depth * self.levels:
            raise Error("A layered target holds one image per layer and level")

    def _index(self, layer: Int, level: Int) raises -> Int:
        """Return where the image of `(layer, level)` is, checking both."""
        self.validate()
        if layer < 0 or layer >= self.depth:
            raise Error("A layered target has no such layer")
        if level < 0 or level >= self.levels:
            raise Error("A layered target has no such level")
        return layer * self.levels + level

    def image(
        mut self, layer: Int, level: Int = 0
    ) raises -> ref[origin_of(self.images[0])] RenderTarget:
        """Return the image one layer and one level of the target hold:
        what three.js draws into after `setRenderTarget(target, layer,
        level)`.

        Args:
            layer: The layer, the face of a cube, or zero for a 2D target:
                three.js's `activeCubeFace`.
            level: The mip level, zero for the largest: three.js's
                `activeMipmapLevel`.

        Returns:
            A reference to the image, valid as long as the target is.

        Raises:
            Error: If the target fails `validate`, or it has no such layer
                or level.
        """
        return self.images[self._index(layer, level)]

    def set_image(
        mut self, layer: Int, level: Int, var image: RenderTarget
    ) raises:
        """Replace the image of one layer and one level, as a GPU read
        back fills it.

        Args:
            layer: The layer.
            level: The mip level.
            image: The new image. It must be the level's size and hold the
                type, the outputs and the samples of the image it
                replaces.

        Raises:
            Error: If the target has no such layer or level, or the image
                does not match the one it replaces.
        """
        var index = self._index(layer, level)
        ref held = self.images[index]
        if image.width != held.width or image.height != held.height:
            raise Error("An image must be its level's size")
        if (
            image.type != held.type
            or image.count() != held.count()
            or image.samples != held.samples
        ):
            raise Error(
                "An image must hold the type, outputs and samples of its level"
            )
        self.images[index] = image^

    def clear(mut self, color: Color) raises:
        """Clear every image of every layer and level: three.js's
        `WebGLCubeRenderTarget.clear`.

        Args:
            color: The color to fill with, decoded from sRGB.

        Raises:
            Error: If the target fails `validate`.
        """
        self.validate()
        for index in range(len(self.images)):  # pragma: no branch
            ref held = self.images[index]
            held.set_scissor(Rect.whole(held.width, held.height))
            held.clear_inside(Rect.whole(held.width, held.height), color)

    def generate_mipmaps(mut self) raises:
        """Fill every level below the first from the level above it, in
        every layer: three.js's `generateMipmap` after a draw into the
        first level.

        Each level is `RenderTarget.downsampled(2)` of the one above: the
        box average of each two by two block in linear light, the nearest
        depth, and the data flag only where the whole block holds data.

        Raises:
            Error: If the target fails `validate`.
        """
        self.validate()
        for layer in range(self.depth):  # pragma: no branch
            for level in range(1, self.levels):
                var at = layer * self.levels + level
                self.images[at] = self.images[at - 1].downsampled(2)

    def from_equirectangular_texture(mut self, panorama: Texture) raises:
        """Fill every face of a cube target from an equirectangular image:
        three.js's `WebGLCubeRenderTarget.fromEquirectangularTexture`.

        Each pixel of each face and level reads the panorama at
        `equirect_uv` of the direction through its center, through the
        panorama's own filter at its full size. That is what three.js's
        box, drawn from the cube's center with the chain switched off to
        keep the poles sharp, reads. `render.cube_texture.
        cube_from_equirectangular` samples the same way. Each level is
        sampled at its own size, not averaged from the level above.

        Args:
            panorama: The equirectangular image.

        Raises:
            Error: If the target is not a cube or fails `validate`, or the
                panorama is blank or refused by `Texture.validate`.
        """
        self.validate()
        if self.kind != TARGET_CUBE:
            raise Error("Only a cube target is filled from a panorama")
        panorama.validate()
        if panorama.is_blank():
            raise Error("An equirectangular image must hold texels")
        for face in range(FACE_COUNT):  # pragma: no branch
            for level in range(self.levels):  # pragma: no branch
                ref held = self.images[face * self.levels + level]
                var whole = Rect.whole(held.width, held.height)
                held.set_scissor(whole)
                held.clear_inside(whole, Color(0, 0, 0, 0))
                var edge = held.width
                for y in range(edge):  # pragma: no branch
                    for x in range(edge):  # pragma: no branch
                        var place = equirect_uv(
                            face_direction(face, x, y, edge)
                        )
                        held.write(x, y, panorama.sample(place.x, place.y))

    def _layer_texture(self, layer: Int, filter: Filter) raises -> Texture:
        """Return one layer's levels as one texture, rows from the top, in
        the layer's type: bytes for a byte target, floats otherwise."""
        var first = layer * self.levels
        ref base = self.images[first]
        var image = base.attachment(0)
        var bytes = base.type == UNSIGNED_BYTE_TARGET
        var texture: Texture
        if bytes:
            var pixels = List[UInt8](capacity=len(image.pixels))
            for at in range(len(image.pixels)):  # pragma: no branch
                pixels.append(_byte(image.pixels[at]))
            texture = Texture(
                base.width,
                base.height,
                pixels^,
                CLAMP,
                filter,
                LINEAR,
                False,
            )
        else:
            texture = float_texture(
                base.width, base.height, image.pixels.copy(), CLAMP, filter
            )
        for level in range(1, self.levels):
            var below = self.images[first + level].attachment(0)
            if bytes:
                texture.offsets.append(len(texture.pixels))
                for at in range(len(below.pixels)):  # pragma: no branch
                    texture.pixels.append(_byte(below.pixels[at]))
            else:
                texture.offsets.append(len(texture.data))
                for at in range(len(below.pixels)):  # pragma: no branch
                    texture.data.append(below.pixels[at])
        texture.levels = self.levels
        texture.min_filter = minifying(filter, self.levels > 1)
        texture.validate()
        return texture^

    def texture(self, filter: Filter = BILINEAR) raises -> Texture:
        """Return a 2D target's levels as one texture a later draw can
        sample: three.js's `WebGLRenderTarget.texture` with its chain.

        Args:
            filter: `NEAREST` or `BILINEAR`. With a chain, the minifying
                filter mixes the levels, as `minifying` says.

        Returns:
            The texture: bytes stored `LINEAR` for a byte target, floats
            for a half float or float one. Every level is the one drawn,
            or the one `generate_mipmaps` filled.

        Raises:
            Error: If the target is not 2D or fails `validate`, or the
                filter is none of the named values.
        """
        self.validate()
        if self.kind != TARGET_2D:
            raise Error("Only a 2D target reads back as one texture")
        return self._layer_texture(0, filter)

    def cube_texture(self, filter: Filter = BILINEAR) raises -> CubeTexture:
        """Return a cube target's six faces as a cube texture: three.js's
        `WebGLCubeRenderTarget.texture`.

        Args:
            filter: `NEAREST` or `BILINEAR`, for every face.

        Returns:
            The cube texture, each face with the target's levels.

        Raises:
            Error: If the target is not a cube or fails `validate`, or the
                filter is none of the named values.
        """
        self.validate()
        if self.kind != TARGET_CUBE:
            raise Error("Only a cube target reads back as a cube texture")
        var faces = List[Texture]()
        for face in range(FACE_COUNT):  # pragma: no branch
            faces.append(self._layer_texture(face, filter))
        return CubeTexture(faces^)

    def _volume(self) raises -> VolumeImage:
        """Return the first level of every layer as one volume image, its
        rows running up."""
        ref base = self.images[0]
        var bytes = base.type == UNSIGNED_BYTE_TARGET
        var pixels = List[UInt8]()
        var data = List[Float32]()
        for layer in range(self.depth):  # pragma: no branch
            var image = self.images[layer * self.levels].attachment(0)
            for row in range(self.height):  # pragma: no branch
                # A volume's first row is the rendered image's last.
                var start = (self.height - 1 - row) * self.width * 4
                for at in range(
                    start, start + self.width * 4
                ):  # pragma: no branch
                    if bytes:
                        pixels.append(_byte(image.pixels[at]))
                    else:
                        data.append(image.pixels[at])
        if bytes:
            return VolumeImage.of_bytes(
                self.width, self.height, self.depth, pixels
            )
        return VolumeImage.of_floats(self.width, self.height, self.depth, data)

    def texture_3d(self, filter: Filter = BILINEAR) raises -> Data3DTexture:
        """Return a 3D target's layers as a volume: three.js's
        `RenderTarget3D.texture`.

        Args:
            filter: `NEAREST` or `BILINEAR`.

        Returns:
            The texture: bytes for a byte target, floats otherwise, both
            `LINEAR`. Layer `z` is the volume's depth `z`.

        Raises:
            Error: If the target is not 3D or fails `validate`, or the
                filter is none of the named values.
        """
        self.validate()
        if self.kind != TARGET_3D:
            raise Error("Only a 3D target reads back as a 3D texture")
        return Data3DTexture(self._volume(), CLAMP, filter, LINEAR)

    def array_texture(
        self, filter: Filter = BILINEAR
    ) raises -> DataArrayTexture:
        """Return an array target's layers as an array texture: three.js's
        `WebGLArrayRenderTarget.texture`.

        Args:
            filter: `NEAREST` or `BILINEAR`, within a layer.

        Returns:
            The texture: bytes for a byte target, floats otherwise, both
            `LINEAR`.

        Raises:
            Error: If the target is not an array or fails `validate`, or
                the filter is none of the named values.
        """
        self.validate()
        if self.kind != TARGET_ARRAY:
            raise Error("Only an array target reads back as an array texture")
        return DataArrayTexture(self._volume(), CLAMP, filter, LINEAR)


def render_target_3d(
    width: Int,
    height: Int,
    depth: Int,
    clear: Color = Color(0, 0, 0, 0),
    type: TargetType = UNSIGNED_BYTE_TARGET,
    samples: Int = 0,
) raises -> LayeredRenderTarget:
    """Return a target whose layers are the slices of a volume: three.js's
    `new WebGL3DRenderTarget(width, height, depth)`.

    Args:
        width: Each layer's width in pixels.
        height: Each layer's height in pixels.
        depth: How many layers.
        clear: The color every layer starts at, decoded from sRGB.
        type: What every layer stores.
        samples: How many samples each pixel takes when drawn into.

    Returns:
        The target.

    Raises:
        Error: Everything `LayeredRenderTarget` raises.
    """
    return LayeredRenderTarget(
        TARGET_3D, width, height, depth, clear, type, samples
    )


def array_render_target(
    width: Int,
    height: Int,
    depth: Int,
    clear: Color = Color(0, 0, 0, 0),
    type: TargetType = UNSIGNED_BYTE_TARGET,
    samples: Int = 0,
) raises -> LayeredRenderTarget:
    """Return a target whose layers are a stack of images: three.js's
    `new WebGLArrayRenderTarget(width, height, depth)`.

    Args:
        width: Each layer's width in pixels.
        height: Each layer's height in pixels.
        depth: How many layers.
        clear: The color every layer starts at, decoded from sRGB.
        type: What every layer stores.
        samples: How many samples each pixel takes when drawn into.

    Returns:
        The target.

    Raises:
        Error: Everything `LayeredRenderTarget` raises.
    """
    return LayeredRenderTarget(
        TARGET_ARRAY, width, height, depth, clear, type, samples
    )


def cube_render_target(
    size: Int,
    clear: Color = Color(0, 0, 0, 0),
    type: TargetType = UNSIGNED_BYTE_TARGET,
    samples: Int = 0,
    levels: Int = 1,
) raises -> LayeredRenderTarget:
    """Return a target of six square faces: three.js's
    `new WebGLCubeRenderTarget(size)`.

    Args:
        size: Each face's width and height in pixels.
        clear: The color every face starts at, decoded from sRGB.
        type: What every face stores.
        samples: How many samples each pixel takes when drawn into.
        levels: How many mip levels each face holds. One, the default,
            is no chain.

    Returns:
        The target, its layers in `POSITIVE_X` through `NEGATIVE_Z` order.

    Raises:
        Error: Everything `LayeredRenderTarget` raises.
    """
    return LayeredRenderTarget(
        TARGET_CUBE, size, size, FACE_COUNT, clear, type, samples, levels
    )


def mipmapped_render_target(
    size: Int,
    levels: Int,
    clear: Color = Color(0, 0, 0, 0),
    type: TargetType = UNSIGNED_BYTE_TARGET,
    samples: Int = 0,
) raises -> LayeredRenderTarget:
    """Return a square 2D target with a mip chain a draw can go into:
    three.js's `WebGLRenderTarget` whose texture has levels, drawn with
    `activeMipmapLevel`.

    Args:
        size: The first level's width and height in pixels, a power of
            two.
        levels: How many levels, up to `full_chain(size, size)`.
        clear: The color every level starts at, decoded from sRGB.
        type: What every level stores.
        samples: How many samples each pixel takes when drawn into.

    Returns:
        The target.

    Raises:
        Error: Everything `LayeredRenderTarget` raises.
    """
    return LayeredRenderTarget(
        TARGET_2D, size, size, 1, clear, type, samples, levels
    )
