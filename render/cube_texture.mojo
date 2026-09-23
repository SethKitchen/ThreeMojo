# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Six images sampled by direction, from three.js `src/textures/CubeTexture.js`.

A `Texture` answers "what color is at this place on a surface". A cube
texture answers a different question: "what color is in this direction".
Six square images stand for the six faces of a box around the viewer, and a
direction picks the face it leaves through and the place on that face. That
is what an environment looks like from one point, which is why a cube
texture is what a mirror ball reflects and what a sky is made of.

**One convention, and it is the camera's.** Every face is what a camera
standing at the center of the box sees looking straight out along one axis,
with the up axis `face_up` gives: the six views a `CubeCamera` renders, and
the six views three.js's `CubeCamera` renders. Sampling reads them back the
same way, so a cube texture rendered by this project reflects the scene it
was rendered from without any flip.

Six image files for three.js are laid out the other way. They are an
OpenGL cube map, a convention from a left-handed coordinate system, and
three.js reads them through a sign, `flipEnvMap`, that turns the x axis of
the lookup over for a cube loaded from images. The two mirrors cancel
inside each image and not between the images: each is the camera's own
view, unmirrored, but the px image lies toward -x and the nx image toward
+x. three.js's `LightProbeGenerator.fromCubeTexture` walks the texels the
same way. Here the difference is settled when the images arrive:
`cube_texture_from` takes a `CubeLayout`, and `SEEN_FROM_OUTSIDE` swaps the
px and nx images on the way in, so a sampler has one convention to read.
See `face_uv` for the arithmetic, which both rasterizers share.

**A face is read at its full size, not down a mip chain.** A reflection's
direction changes across a surface at a rate that has nothing to do with
the surface's own texture coordinates, and the footprint `mip_level`
measures is theirs. The same reasoning keeps a matcap out of its chain. A
face can still hold a chain, since it is a `Texture`, and one reader asks
for it: a physical surface reads the chain by its *roughness* rather than
by any footprint, through `sample_level`, because a rough surface reflects
a blurred environment and a blurred face is what a coarser level holds.
A box-filtered chain is coarser than three.js's PMREM, and a cube built
with `mipmapped=False` reflects sharply at every roughness.

**A prefiltered cube reads its PMREM instead.** `render.pmrem` builds one:
the same six faces, and beside them `cube_uv`, the environment blurred once
per roughness in three.js's cube UV layout. A physical surface reads that
image through `sample_rough`, as three.js's `textureCubeUV` reads it, and
every other reader still reads the faces. See `render.cube_uv`.

**A face is clamped.** A coordinate past a face's edge belongs to the next
face, and a flat image has no next face to read. `REPEAT` would read the
far edge of the same face and `MIRROR` would read the near edge twice, so
a face built with either is refused: the bilinear filter's neighbors at an
edge must hold that edge, and that is `CLAMP`.

**An equirectangular image becomes a cube before it is read.** three.js
takes a panorama, one image whose columns are longitude and whose rows are
latitude, as a background or an environment by rendering it into a cube
first: `WebGLCubeRenderTarget.fromEquirectangularTexture`, which every
face texel reads at `equirectUv` of its direction. `cube_from_equirectangular`
is that conversion, on the host, once; the cube it returns is read like
any other, so neither rasterizer learns a second way to look a direction
up. A float panorama gives float faces, which is how an HDR sky lights a
mirror with light above one.
"""

from math.vector2 import Vector2
from math.vector3 import Vector3
from render.cube_uv import (
    CUBE_UV_EXTRA_COPIES,
    CUBE_UV_MIN_MIP,
    CUBE_UV_MIN_TILE,
    cube_uv_lod_max,
    sample_cube_uv,
)
from render.framebuffer import FloatColor, Framebuffer
from render.png import DecodedImage
from render.srgb import SRGB, UNKNOWN_SPACE, ColorSpace
from render.texture import (
    BILINEAR,
    CLAMP,
    COVERAGE,
    FLOAT_TYPE,
    Alpha,
    Filter,
    Texture,
    float_texture,
)
from std.math import asin, atan2, pi

# How many faces a cube has, and the order they are held in: positive x,
# negative x, positive y, negative y, positive z, negative z. three.js's
# order, and OpenGL's.
comptime FACE_COUNT = 6
comptime POSITIVE_X = 0
comptime NEGATIVE_X = 1
comptime POSITIVE_Y = 2
comptime NEGATIVE_Y = 3
comptime POSITIVE_Z = 4
comptime NEGATIVE_Z = 5


@fieldwise_init
struct CubeLayout(Equatable, ImplicitlyCopyable, Writable):
    """Which way round six images are, as a type rather than a bare int.

    See `core.object3d.NodeId` for why these are wrapped. The type does
    not stop `CubeLayout(9)`, so `cube_texture_from` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `SEEN_FROM_INSIDE` or `SEEN_FROM_OUTSIDE`."""
        return self == SEEN_FROM_INSIDE or self == SEEN_FROM_OUTSIDE


# Each face is what a camera at the center sees looking out: what a
# `CubeCamera` renders, and what a sampler reads. The default.
comptime SEEN_FROM_INSIDE = CubeLayout(0)
# three.js's layout for six image files, the OpenGL cube map read through
# `flipEnvMap`: each image is the camera's view, but the px image is the
# view along -x and the nx image the view along +x. The two trade places
# on the way in, and nothing is mirrored.
comptime SEEN_FROM_OUTSIDE = CubeLayout(1)


def face_forward(face: Int) -> Vector3:
    """Return the direction a cube's face looks out along.

    The axis the face is named for. Pure and unchecked, because the GPU
    kernel calls it with a face `face_of` chose; a caller with an index of
    its own asks `CubeTexture.face`, which checks.

    Args:
        face: `POSITIVE_X` through `NEGATIVE_Z`.

    Returns:
        The unit axis, or the negative z axis for any other number.
    """
    if face == POSITIVE_X:
        return Vector3(1, 0, 0)
    if face == NEGATIVE_X:
        return Vector3(-1, 0, 0)
    if face == POSITIVE_Y:
        return Vector3(0, 1, 0)
    if face == NEGATIVE_Y:
        return Vector3(0, -1, 0)
    if face == POSITIVE_Z:
        return Vector3(0, 0, 1)
    return Vector3(0, 0, -1)


def face_up(face: Int) -> Vector3:
    """Return which way is up in a cube's face.

    Positive y for the four faces around the sides, and for the two faces
    on the y axis, where y itself is the view direction, the z axis: away
    from the viewer for the top face and toward the viewer for the bottom
    one. three.js's `CubeCamera` sets each of its six cameras up this way
    under the WebGL coordinate system, and this is that table.

    Args:
        face: `POSITIVE_X` through `NEGATIVE_Z`.

    Returns:
        The unit up axis, or positive y for any other number.
    """
    if face == POSITIVE_Y:
        return Vector3(0, 0, -1)
    if face == NEGATIVE_Y:
        return Vector3(0, 0, 1)
    return Vector3(0, 1, 0)


def face_of(direction: Vector3) -> Int:
    """Return which face a direction leaves the cube through.

    The face on the axis the direction leans along most, signed by which
    way it leans. A tie goes to x before y before z, as OpenGL's own
    selection does, so a direction along a cube's edge reads one face on
    both backends rather than whichever each happened to prefer. The zero
    vector leans along nothing and is given positive x.

    Shared by both rasterizers, as `wrap_index` is, so neither can read a
    direction off a face the other does not.

    Args:
        direction: Any vector; it need not be unit length.

    Returns:
        `POSITIVE_X` through `NEGATIVE_Z`.
    """
    var ax = direction.x
    if ax < 0:
        ax = -ax
    var ay = direction.y
    if ay < 0:
        ay = -ay
    var az = direction.z
    if az < 0:
        az = -az
    if ax >= ay and ax >= az:
        if direction.x < 0:
            return NEGATIVE_X
        return POSITIVE_X
    if ay >= az:
        if direction.y < 0:
            return NEGATIVE_Y
        return POSITIVE_Y
    if direction.z < 0:
        return NEGATIVE_Z
    return POSITIVE_Z


def face_uv(face: Int, direction: Vector3) -> Vector2:
    """Return where a direction lands on one face of the cube.

    The face is a camera's view: the direction is projected onto the plane
    one unit out along `face_forward`, and how far it lands across and up
    that plane, in the camera's own right and up axes, is the coordinate.
    Right is `face_forward` crossed with `face_up`, as a camera's right is
    its forward crossed with its up, so a face rendered by a camera and
    a face read by this agree about which side is which.

        u = 0.5 + 0.5 * dot(direction, right) / dot(direction, forward)
        v = 0.5 + 0.5 * dot(direction, up) / dot(direction, forward)

    `v` counts up, as every texture coordinate here does, so the top row
    of a rendered face is what the camera saw at the top of its view.

    Pure and shared by both rasterizers, as `face_of` is. The face is
    taken as given rather than chosen here, because the kernel picks a
    face and then a descriptor and then samples, and the two steps read
    better apart.

    Args:
        face: The face `face_of` chose for this direction.
        direction: Any vector; it need not be unit length.

    Returns:
        The coordinate, inside the unit square for the face `face_of`
        chose. The middle of the face for the zero vector, which reaches
        no face at all.
    """
    var forward = face_forward(face)
    var up = face_up(face)
    var right = forward
    right.cross(up)
    var out = direction.dot(forward)
    if out == 0:
        return Vector2(0.5, 0.5)
    return Vector2(
        0.5 + 0.5 * direction.dot(right) / out,
        0.5 + 0.5 * direction.dot(up) / out,
    )


def reflected(toward_eye: Vector3, normal: Vector3) -> Vector3:
    """Return the direction a mirror surface sends the camera's view.

    GLSL's `reflect(-toward_eye, normal)`, which three.js's
    `envmap_fragment` evaluates on the vector from the camera to the
    fragment: the view direction turned back through the surface,

        reflected = 2 * dot(normal, toward_eye) * normal - toward_eye

    so a surface square-on to the camera reflects the camera and one seen
    at a grazing angle reflects what is beyond it. Shared by both
    rasterizers, as `matcap_uv` is.

    Args:
        toward_eye: Unit direction from the surface toward the camera.
        normal: The surface's unit normal.

    Returns:
        The reflected direction, unit length for unit inputs.
    """
    var along = normal.dot(toward_eye)
    return Vector3(
        2 * along * normal.x - toward_eye.x,
        2 * along * normal.y - toward_eye.y,
        2 * along * normal.z - toward_eye.z,
    )


struct CubeTexture(Movable):
    """Six square textures, one per face of a cube, sampled by direction."""

    # In `POSITIVE_X` through `NEGATIVE_Z` order, each what a camera at the
    # center sees looking out along that axis.
    var faces: List[Texture]
    # The width and height of every face, in texels.
    var size: Int
    # The environment prefiltered per roughness in three.js's cube UV
    # layout, or the blank texture for a cube that has none. Only
    # `render.pmrem` fills it; see `sample_rough`.
    var cube_uv: Texture

    def __init__(out self, var faces: List[Texture]) raises:
        """Adopt six faces.

        Args:
            faces: Six textures in `POSITIVE_X` through `NEGATIVE_Z` order,
                each what a camera at the center sees looking out along
                that axis. `cube_texture_from` builds them from images and
                `cube_texture_of` from renders.

        Raises:
            Error: If there are not six, any is blank, any is not square,
                they are not all one size, or any is wrapped other than
                `CLAMP` -- see `validate`.
        """
        self.faces = faces^
        self.size = 0
        self.cube_uv = Texture()
        self.validate()
        self.size = self.faces[0].width

    def __init__(out self, *, copy: Self):
        """Copy another cube texture, faces included."""
        self.faces = List[Texture]()
        # A built cube holds six faces, so this never runs zero times.
        for index in range(len(copy.faces)):  # pragma: no branch
            self.faces.append(Texture(copy=copy.faces[index]))
        self.size = copy.size
        self.cube_uv = Texture(copy=copy.cube_uv)

    def validate(self) raises:
        """Refuse faces that a sampler could not read as one cube.

        Asked by the constructor, and again by `render.gpu.flatten_textures`
        on the way to the device, because the faces are open and can have
        been edited since.

        Raises:
            Error: If there are not six faces, any face is blank, any is not
                square, the faces are not all one size, any is wrapped
                other than `CLAMP`, or any face's own `Texture.validate`
                refuses it; or the cube has a `cube_uv` image that is
                refused by `validate_cube_uv`.
        """
        if len(self.faces) != FACE_COUNT:
            raise Error("A cube texture holds exactly six faces")
        var size = self.faces[0].width
        # Six faces, always, so the loop never runs zero times.
        for index in range(FACE_COUNT):  # pragma: no branch
            ref face = self.faces[index]
            face.validate()
            if face.is_blank():
                raise Error("A cube texture's faces must hold texels")
            if face.width != face.height:
                raise Error("A cube texture's faces must be square")
            if face.width != size:
                raise Error("A cube texture's faces must all be one size")
            if face.wrap != CLAMP:
                raise Error(
                    "A cube texture's faces must be wrapped CLAMP: a"
                    " coordinate past a face's edge belongs to the next face,"
                    " and a flat image has no next face to read"
                )
        if not self.cube_uv.is_blank():
            validate_cube_uv(self.cube_uv)

    def is_prefiltered(self) -> Bool:
        """Return True if the cube holds a PMREM, a `cube_uv` image."""
        return not self.cube_uv.is_blank()

    def face(self, index: Int) raises -> ref[origin_of(self.faces[0])] Texture:
        """Return one face, borrowed.

        Args:
            index: `POSITIVE_X` through `NEGATIVE_Z`.

        Returns:
            A reference to the face, valid as long as the cube texture is.

        Raises:
            Error: If the index names no face.
        """
        if index < 0 or index >= FACE_COUNT:
            raise Error("A cube has six faces")
        return self.faces[index]

    def sample(self, direction: Vector3) -> FloatColor:
        """Return the color in a direction.

        `face_of` picks the face and `face_uv` the place on it, and the
        face is sampled there at its full size through its own filter,
        never down a mip chain; see the module docstring. Does not raise,
        for the reason `Texture.sample` does not: every direction has an
        answer, the zero vector included.

        Args:
            direction: Any vector; it need not be unit length.

        Returns:
            The color found there.
        """
        var face = face_of(direction)
        var place = face_uv(face, direction)
        return self.faces[face].sample(place.x, place.y)

    def sample_level(self, direction: Vector3, level: Float32) -> FloatColor:
        """Return the color in a direction, read `level` down the chain.

        `sample` with the face read through `Texture.sample_level` rather
        than at its full size: what a physical surface asks, by its
        roughness. A face with no chain reads its one image whatever the
        level, so a cube built with `mipmapped=False` reflects sharply.

        Args:
            direction: Any vector; it need not be unit length.
            level: How far down the chain, fractional; see
                `reflection_level`.

        Returns:
            The color found there.
        """
        var face = face_of(direction)
        var place = face_uv(face, direction)
        return self.faces[face].sample_level(place.x, place.y, level)

    def sample_rough(
        self, direction: Vector3, roughness: Float32
    ) -> FloatColor:
        """Return the environment a surface of some roughness reflects in a
        direction.

        A prefiltered cube reads its PMREM, `sample_cube_uv`, as three.js's
        `textureCubeUV` does. Any other cube reads down its faces' chain at
        `reflection_level`, the box-filtered stand-in. Both rasterizers ask
        this question the same way; see `render.gpu._sample_cube_rough`.

        Args:
            direction: Any vector; it need not be unit length.
            roughness: From zero to one. Roughness one is what three.js
                reads for the irradiance around a normal.

        Returns:
            The color found there.
        """
        if self.is_prefiltered():
            return sample_cube_uv(self.cube_uv, direction, roughness)
        return self.sample_level(
            direction, reflection_level(roughness, self.levels())
        )

    def levels(self) -> Int:
        """Return how many mip levels each face holds, one for a cube built
        without a chain."""
        return self.faces[0].levels


def rough_reflection(
    toward_eye: Vector3, normal: Vector3, roughness: Float32
) -> Vector3:
    """Return the direction a rough surface reflects the camera's view:
    three.js's `getIBLRadiance`, which bends `reflected` toward the normal
    by the square of the roughness.

    Mixing the reflection with the normal keeps a rough surface from
    gathering light from behind its own tangent plane, as three.js's
    comment says. Shared by both rasterizers.

    Args:
        toward_eye: Unit direction from the surface toward the camera.
        normal: The surface's unit normal.
        roughness: How rough the surface is, from zero to one.

    Returns:
        The unit direction to read the environment in.
    """
    var bounce = reflected(toward_eye, normal)
    var bend = roughness * roughness
    var bent = Vector3(
        bounce.x + (normal.x - bounce.x) * bend,
        bounce.y + (normal.y - bounce.y) * bend,
        bounce.z + (normal.z - bounce.z) * bend,
    )
    if bent.length() != 0:
        bent.normalize()
    return bent


def reflection_level(roughness: Float32, levels: Int) -> Float32:
    """Return how far down a cube's chain a roughness reads.

    Linear in the roughness, from the full size at zero to the coarsest
    level at one, where each face is one texel: the average of everything
    that face sees, which is what a chalky surface reflects. Shared by
    both rasterizers.

    An approximation, and the contract it keeps is monotonic: the same
    direction read at a rising roughness moves steadily from the texel
    it lands on toward its face's average. What three.js's PMREM holds
    at each roughness is the environment weighted by the GGX lobe of that
    roughness, which a mip chain's box average is not. A prefiltered
    chain can replace the mip chain here without the callers changing.

    Args:
        roughness: How rough the surface is, from zero to one.
        levels: How many levels the cube's faces hold.

    Returns:
        The fractional level, zero for a chain of one.
    """
    return roughness * Float32(levels - 1)


def equirect_uv(direction: Vector3) -> Vector2:
    """Return where a direction lands on an equirectangular image:
    three.js's `equirectUv`.

    Longitude across and latitude up. `u` is the angle around the y axis,
    measured from positive x toward positive z, a half at positive x; `v`
    is the height above the horizon, zero straight down and one straight
    up, counting up as every texture coordinate here does, so the top row
    of a panorama is the sky.

        u = atan2(z, x) / (2 pi) + 0.5
        v = asin(y) / pi + 0.5

    Args:
        direction: Any vector; it is normalized first, as three.js's
            caller normalizes it. The zero vector reads the middle.

    Returns:
        The coordinate, inside the unit square.
    """
    var length = direction.length()
    if length == 0:
        return Vector2(0.5, 0.5)
    # Clamped as three.js clamps, with `min` and `max`: a unit vector's y
    # is within one bar a rounding, and `asin` of a hair past one is NaN.
    var up = max(Float32(-1), min(Float32(1), direction.y / length))
    return Vector2(
        atan2(direction.z / length, direction.x / length) / (2 * Float32(pi))
        + 0.5,
        asin(up) / Float32(pi) + 0.5,
    )


def face_direction(face: Int, x: Int, y: Int, size: Int) -> Vector3:
    """Return the direction through the center of one texel of a face.

    The inverse of `face_uv`: the texel's center as a coordinate, `v`
    counting up from the bottom row, then the point that coordinate names
    on the plane one unit out along `face_forward`.

    Args:
        face: `POSITIVE_X` through `NEGATIVE_Z`.
        x: Column, from the left.
        y: Row, from the top.
        size: The face's width and height in texels.

    Returns:
        The direction, not normalized; `face_uv` of it is the texel's
        center.
    """
    var forward = face_forward(face)
    var up = face_up(face)
    var right = forward
    right.cross(up)
    var across = (Float32(x) + 0.5) / Float32(size) * 2 - 1
    var upward = 1 - (Float32(y) + 0.5) / Float32(size) * 2
    return Vector3(
        forward.x + right.x * across + up.x * upward,
        forward.y + right.y * across + up.y * upward,
        forward.z + right.z * across + up.z * upward,
    )


def cube_from_equirectangular(
    image: Texture,
    size: Optional[Int] = None,
    mipmapped: Optional[Bool] = None,
) raises -> CubeTexture:
    """Return the cube texture an equirectangular image makes: three.js's
    `WebGLCubeRenderTarget.fromEquirectangularTexture`.

    What three.js does behind `texture.mapping =
    EquirectangularReflectionMapping` when the texture becomes a
    background or an environment, done here once and handed back: add the
    cube to the assets and name it as `cube_background` or `env_map`, as
    any cube is named.

    Each face texel reads the panorama at `equirect_uv` of the direction
    through its center, through the panorama's own filter at its full
    size, as three.js reads it with the chain switched off to keep the
    poles sharp. The faces keep the panorama's texel type, color space,
    filter and alpha mode, as three.js's target copies them: a float
    panorama gives float faces with its light above one intact, and a
    byte one gives bytes encoded back in its own color space.

    Args:
        image: The panorama, twice as wide as it is tall by convention;
            any size is read.
        size: Each face's width and height in texels. The panorama's
            height by default, as three.js sizes the cube.
        mipmapped: Build each face's chain, which a rough surface reads.
            Whether the panorama has one by default, as three.js copies
            `generateMipmaps`.

    Returns:
        The cube texture, its faces wrapped `CLAMP`.

    Raises:
        Error: If the panorama is blank or refused by `Texture.validate`,
            or the size is not positive.
    """
    image.validate()
    if image.is_blank():
        raise Error("An equirectangular image must hold texels")
    var edge = size.or_else(image.height)
    if edge <= 0:
        raise Error("A cube's faces must be at least one texel across")
    var chained = mipmapped.or_else(image.levels > 1)
    var faces = List[Texture]()
    for face in range(FACE_COUNT):  # pragma: no branch
        var floats = List[Float32]()
        var bytes = List[UInt8]()
        for y in range(edge):  # pragma: no branch
            for x in range(edge):  # pragma: no branch
                var place = equirect_uv(face_direction(face, x, y, edge))
                var color = image.sample(place.x, place.y)
                if image.texel_type == FLOAT_TYPE:
                    floats.append(color.r)
                    floats.append(color.g)
                    floats.append(color.b)
                    floats.append(color.a)
                    continue
                var stored = color.quantize()
                if image.color_space == SRGB:
                    stored = color.encode()
                bytes.append(stored.r)
                bytes.append(stored.g)
                bytes.append(stored.b)
                bytes.append(stored.a)
        if image.texel_type == FLOAT_TYPE:
            faces.append(
                float_texture(
                    edge,
                    edge,
                    floats^,
                    CLAMP,
                    image.filter,
                    chained,
                    image.alpha,
                )
            )
        else:
            faces.append(
                Texture(
                    edge,
                    edge,
                    bytes^,
                    CLAMP,
                    image.filter,
                    image.color_space,
                    chained,
                    image.alpha,
                )
            )
    return CubeTexture(faces^)


def cube_uv_width(lod_max: Int) -> Int:
    """Return how wide a PMREM's layout image is, from its sharpest mip.

    Three tiles across the sharpest copy, or across the seven sixteen-texel
    copies side by side when those are wider: three.js's
    `3 * max(cubeSize, 16 * 7)`.

    Args:
        lod_max: The sharpest copy's mip, at least four.

    Returns:
        The width in texels.
    """
    return 3 * max(1 << lod_max, CUBE_UV_MIN_TILE * (CUBE_UV_EXTRA_COPIES + 1))


def validate_cube_uv(image: Texture) raises:
    """Refuse an image a PMREM sampler could not read as a cube UV layout.

    Asked by `CubeTexture.validate`, and so again on the way to the device.

    Raises:
        Error: If `Texture.validate` refuses the image; it does not hold
            floats, is not `CLAMP` and `BILINEAR`, or holds a mip chain; or
            its height is not four times a power of two of at least sixteen,
            or its width is not `cube_uv_width` of that.
    """
    image.validate()
    if image.texel_type != FLOAT_TYPE:
        raise Error("A PMREM's cube UV image holds floats")
    if image.wrap != CLAMP or image.filter != BILINEAR or image.levels != 1:
        raise Error(
            "A PMREM's cube UV image is CLAMP and BILINEAR, with no mip chain"
        )
    var lod_max = cube_uv_lod_max(image.height)
    if lod_max < CUBE_UV_MIN_MIP or image.height != 4 << lod_max:
        raise Error(
            "A PMREM's cube UV image is four tiles of a power of two, at"
            " least sixteen, tall"
        )
    if image.width != cube_uv_width(lod_max):
        raise Error("A PMREM's cube UV image is three tiles wide")


def cube_texture_from(
    images: List[DecodedImage],
    layout: CubeLayout = SEEN_FROM_INSIDE,
    filter: Filter = BILINEAR,
    color_space: Optional[ColorSpace] = None,
    mipmapped: Bool = False,
    alpha: Alpha = COVERAGE,
) raises -> CubeTexture:
    """Return a cube texture holding six decoded images, three.js's
    `CubeTextureLoader.load` of six files.

    Each image becomes one face, wrapped `CLAMP`, in `POSITIVE_X` through
    `NEGATIVE_Z` order. Under `SEEN_FROM_OUTSIDE` the first two images
    trade places on the way in, which turns three.js's layout for six
    image files into the camera's own; see the module docstring.

    The color space comes from each file unless one is given, as
    `texture_from` reads it, and a file whose space cannot be interpreted
    is refused for the same reason.

    Args:
        images: Six decoded images, all square and all one size.
        layout: `SEEN_FROM_INSIDE` if each image is what a camera at the
            center sees along its own axis, `SEEN_FROM_OUTSIDE` if the px
            image is the view along -x and the nx image the view along +x,
            as three.js's `CubeTextureLoader` reads them.
        filter: `NEAREST` or `BILINEAR`, for every face.
        color_space: `SRGB` or `LINEAR` to override what the files declare,
            or nothing to use it.
        mipmapped: Build each face's chain of halved copies. Off by
            default: a cube is read at its full size, so a chain costs a
            third more memory and is never read.
        alpha: `COVERAGE` or `IGNORED`, for every face; see `render.texture`.

    Returns:
        The cube texture.

    Raises:
        Error: If there are not six images, the layout is neither named
            value, a file's declared color space could not be interpreted
            and none was given, or the faces are refused by
            `CubeTexture.validate`.
    """
    if len(images) != FACE_COUNT:
        raise Error("A cube texture is built from exactly six images")
    if not layout.is_valid():
        raise Error(
            "A cube layout must be SEEN_FROM_INSIDE or SEEN_FROM_OUTSIDE"
        )
    var faces = List[Texture]()
    for index in range(FACE_COUNT):  # pragma: no branch
        var source = index
        if layout == SEEN_FROM_OUTSIDE and index < NEGATIVE_X + 1:
            # POSITIVE_X reads the nx image and NEGATIVE_X the px one.
            source = NEGATIVE_X - index
        ref image = images[source]
        var space = color_space.or_else(image.color_space)
        if space == UNKNOWN_SPACE:
            raise Error(
                "This image declares a color space that cannot be interpreted;"
                " pass SRGB or LINEAR to say how to read it"
            )
        faces.append(
            Texture(
                image.width,
                image.height,
                image.pixels.copy(),
                CLAMP,
                filter,
                space,
                mipmapped,
                alpha,
            )
        )
    return CubeTexture(faces^)


def cube_texture_of(
    images: List[Framebuffer],
    filter: Filter = BILINEAR,
    mipmapped: Bool = False,
    alpha: Alpha = COVERAGE,
) raises -> CubeTexture:
    """Return a cube texture holding six rendered images, three.js's
    `WebGLCubeRenderTarget.texture`.

    What `Renderer.render_cube` returns: each image is one face, as a
    `CubeCamera` rendered it, stored `SRGB` as `texture_of` stores a render
    and wrapped `CLAMP`. Nothing is swapped: a render is already the
    camera's own view along each axis.

    Args:
        images: Six rendered images, all square and all one size, in
            `POSITIVE_X` through `NEGATIVE_Z` order.
        filter: `NEAREST` or `BILINEAR`, for every face.
        mipmapped: Build each face's chain of halved copies. Off by
            default, as `cube_texture_from` leaves it.
        alpha: `COVERAGE` or `IGNORED`, for every face; see `texture_of`.

    Returns:
        The cube texture.

    Raises:
        Error: If there are not six images, or the faces are refused by
            `CubeTexture.validate`.
    """
    if len(images) != FACE_COUNT:
        raise Error("A cube texture is built from exactly six images")
    var faces = List[Texture]()
    for index in range(FACE_COUNT):  # pragma: no branch
        ref image = images[index]
        faces.append(
            Texture(
                image.width,
                image.height,
                image.pixels.copy(),
                CLAMP,
                filter,
                SRGB,
                mipmapped,
                alpha,
            )
        )
    return CubeTexture(faces^)
