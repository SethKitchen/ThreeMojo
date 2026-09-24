# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wavefront material libraries, from three.js
`examples/jsm/loaders/MTLLoader.js`, and `OBJLoader.setMaterials`.

An OBJ file names its surfaces by `usemtl` and leaves what they look like
to a `.mtl` file it names by `mtllib`. `parse_mtl` reads one into an
`MtlLibrary`, building a `PHONG` material per `newmtl` in an `Assets`
store, as three.js's `MTLLoader.MaterialCreator` builds a
`MeshPhongMaterial`, and `read_mtl` reads a file first.
`read_obj_with_materials` reads an OBJ file, every library it names, and
gives each object its `MaterialId`s, one for each of its materials.
`obj_mesh` builds the mesh three.js builds from them: a material list for
an object with several.

**What is read.** A keyword is read in any case, as three.js lowercases
it. Each key keeps the last value a material gives it, at the place it
first appeared, as three.js's object of keys keeps it, and the keys are
then applied in that order:

- `Kd`, `Ks` and `Ke`, three numbers from zero to one, as authored in
  sRGB: the color, the specular color and the emissive color.
- `Ns`: the shininess, not negative.
- `d`: the opacity. Below one it sets it and makes the surface
  transparent. `Tr`: the transparency, one minus the opacity. Above zero it
  sets the opacity to one minus it and makes the surface transparent.
  Either is refused outside zero to one.
- `illum`: an illumination model, a whole number from zero to ten. It is
  checked and changes nothing, as three.js ignores it.
- `map_Kd`: the color map, read as sRGB. `map_Ke`: the emissive map, read
  as sRGB. `map_d`: the alpha map, read as data, and it makes the surface
  transparent. `map_bump` or `bump`: the bump map, and `norm`: the normal
  map, each read as data. The first of each kind is kept, as three.js
  keeps it. A material with both keeps the normal map and drops the bump
  map, as three.js ignores it.

A texture line is options, then a file name relative to the library's
own directory. `-s u v w` sets the texture's `repeat` and `-o u v w` its
`offset`; `w` is ignored, and a missing `v` is one for `-s` and zero for
`-o`. `-bm scale` sets the material's bump scale, from whichever texture
line carries it, as three.js sets it. `-mm base gain` is read and ignored,
since it scales a displacement map, which is not ported. `-clamp on`
clamps the texture where three.js takes its `wrap` option anyway; `-clamp
off` takes the `wrap` option, a repeat by default.
Any other option is refused, where three.js would take it for part of the
file name and fail to load it. The image is decoded as a PNG, a JPEG or a
TGA, told by its first bytes; see `loaders.gltf.decode_image`. One image
read the same way twice is one texture.

The defaults are three.js's `MeshPhongMaterial` defaults: a white color, a
specular of `0x111111`, a shininess of thirty, no emissive, opaque, on the
front side, textures repeating.

**Not ported.** `Ka` and `map_Ka`, which three.js reads and ignores, are
skipped, as is every keyword three.js ignores. `map_Ks`, three.js's
`specularMap`, is skipped, since `Material` has no specular map. `disp` is
skipped, since no material displaces its vertices. Each map keeps its
own `-s` and `-o`, as in three.js.

**Options.** `MtlOptions` holds three.js's `setMaterialOptions`. `side`
is every material's side, a default material's too. `wrap` is every
texture's wrap, where a `-clamp on` still clamps. `normalize_rgb` reads
`Kd` and `Ks` from zero to 255, as three.js divides them by 255.
`ignore_zero_rgbs` skips a `Kd` or `Ks` of three zeros, so the default
stays. `invert_tr_property` reads `Tr` as the opacity, one minus the
transparency three.js otherwise takes it for. Neither changes `Ke`, as
three.js changes it with neither.

A value that is not a number, a color outside zero to one, an option that
is not known or lacks its numbers, a texture line with no file, and an
image that cannot be read or decoded are refused, with the line they were
found on. Text before the first `newmtl` is skipped, as three.js skips it.
"""

from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId
from loaders.gltf import decode_image
from loaders.obj import ObjModel, read_obj
from materials.material import FRONT_SIDE, Material, MaterialId, PHONG, Side
from math.vector2 import Vector2
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.srgb import LINEAR, SRGB
from render.texture import (
    CLAMP,
    COVERAGE,
    IGNORED,
    REPEAT,
    Wrap,
    texture_from,
)
from render.texture_store import NO_TEXTURE, TextureId
from std.math import isfinite
from std.pathlib import Path

# What three.js's `MeshPhongMaterial` starts from.
comptime _WHITE = Color(255, 255, 255)
comptime _DEFAULT_SPECULAR = Color(17, 17, 17)
comptime _BLACK = Color(0, 0, 0)
comptime _DEFAULT_SHININESS = Float32(30)
# The illumination models the format defines, zero to ten.
comptime _LAST_ILLUMINATION = 10

# How a texture is read, by what the material uses it for: a color map
# whose alpha is coverage, an emissive map whose alpha means nothing, and a
# data map, which is linear and whose alpha means nothing.
comptime _COLOR_ROLE = 0
comptime _GLOW_ROLE = 1
comptime _DATA_ROLE = 2


struct MtlOptions(ImplicitlyCopyable):
    """The options of three.js's `MTLLoader.setMaterialOptions`."""

    # The side every material draws, three.js's `side`.
    var side: Side
    # The wrap of every texture, three.js's `wrap`.
    var wrap: Wrap
    # Read `Kd` and `Ks` from zero to 255, three.js's `normalizeRGB`.
    var normalize_rgb: Bool
    # Skip a `Kd` or `Ks` of three zeros, three.js's `ignoreZeroRGBs`.
    var ignore_zero_rgbs: Bool
    # Read `Tr` as an opacity, three.js's `invertTrProperty`.
    var invert_tr_property: Bool

    def __init__(
        out self,
        *,
        side: Side = FRONT_SIDE,
        wrap: Wrap = REPEAT,
        normalize_rgb: Bool = False,
        ignore_zero_rgbs: Bool = False,
        invert_tr_property: Bool = False,
    ):
        """Take the options, at three.js's defaults.

        Args:
            side: The side every material draws.
            wrap: The wrap of every texture.
            normalize_rgb: Read `Kd` and `Ks` from zero to 255.
            ignore_zero_rgbs: Skip a `Kd` or `Ks` of three zeros.
            invert_tr_property: Read `Tr` as an opacity.
        """
        self.side = side
        self.wrap = wrap
        self.normalize_rgb = normalize_rgb
        self.ignore_zero_rgbs = ignore_zero_rgbs
        self.invert_tr_property = invert_tr_property

    def validate(self) raises:
        """Refuse a side or a wrap that is none of the named.

        Raises:
            Error: If `side` or `wrap` is not valid.
        """
        if not self.side.is_valid():
            raise Error("MTL: a side that is none of the three")
        if not self.wrap.is_valid():
            raise Error("MTL: a wrap that is none of the three")


struct MtlLibrary(Movable):
    """A material library: each material's name and the `MaterialId` it
    was built as, three.js's `MaterialCreator`."""

    var names: List[String]
    var materials: List[MaterialId]
    # The side a default material draws, from the library's options.
    var side: Side

    def __init__(out self, side: Side = FRONT_SIDE):
        """Start an empty library.

        Args:
            side: The side a default material draws; see `create`.
        """
        self.names = List[String]()
        self.materials = List[MaterialId]()
        self.side = side

    def count(self) -> Int:
        """Return how many materials the library names.

        Returns:
            The count.
        """
        return len(self.names)

    def find(self, name: String) -> Int:
        """Return where a name is in the library.

        Args:
            name: The material's name, as `newmtl` wrote it.

        Returns:
            Its index in `names` and `materials`, or -1 if it is not there.
        """
        for index in range(len(self.names)):
            if self.names[index] == name:
                return index
        return -1

    def get(self, name: String) raises -> MaterialId:
        """Return the material a name was built as.

        Args:
            name: The material's name.

        Returns:
            Its id.

        Raises:
            Error: If the library has no material of that name.
        """
        var index = self.find(name)
        if index < 0:
            raise Error("MTL: no material is named " + name)
        return self.materials[index]

    def add(mut self, name: String, material: MaterialId):
        """Name a material, in place of any material of the same name, as
        a later `newmtl` of one name replaces the earlier in three.js.

        Args:
            name: The material's name.
            material: Its id.
        """
        var index = self.find(name)
        if index >= 0:
            self.materials[index] = material
            return
        self.names.append(name)
        self.materials.append(material)

    def merge(mut self, other: MtlLibrary):
        """Add every material of another library, each in place of any of
        the same name here.

        Args:
            other: The library to add.
        """
        for index in range(other.count()):
            self.add(other.names[index], other.materials[index])

    def create(mut self, name: String, mut assets: Assets) raises -> MaterialId:
        """Return the material a name asks for, three.js's
        `MaterialCreator.create`.

        A name the library does not have gets a default `PHONG` material,
        built once and then kept under that name, as three.js builds one
        from no parameters. The empty name, of an OBJ object before any
        `usemtl`, is such a name.

        Args:
            name: The material's name.
            assets: Where a default material is added.

        Returns:
            Its id.

        Raises:
            Error: Never for a store that takes a default material, which
                every store does.
        """
        var index = self.find(name)
        if index >= 0:
            return self.materials[index]
        var surface = _Surface()
        surface.side = self.side
        var built = assets.materials.add(_phong(surface))
        self.add(name, built)
        return built


@fieldwise_init
struct _Entry(Copyable, Movable):
    """One keyword of a material, its value, and the line it came from."""

    var key: String
    var value: String
    var line: Int


struct _Info(Copyable, Movable):
    """One `newmtl` block: its name and its keys, in first-seen order."""

    var name: String
    var entries: List[_Entry]

    def __init__(out self, var name: String):
        """Start a material with no keys.

        Args:
            name: Its name.
        """
        self.name = name^
        self.entries = List[_Entry]()

    def set(mut self, key: String, value: String, line: Int):
        """Give a key a value, replacing an earlier one in its place.

        Args:
            key: The keyword, lowercased.
            value: The rest of the line.
            line: Which line it is on.
        """
        for index in range(len(self.entries)):
            if self.entries[index].key == key:
                self.entries[index].value = value
                self.entries[index].line = line
                return
        self.entries.append(_Entry(key, value, line))


struct _Surface(Copyable, Movable):
    """What a material is built from, at three.js's defaults until a key
    says otherwise."""

    var color: Color
    var specular: Color
    var emissive: Color
    var shininess: Float32
    var opacity: Float32
    var transparent: Bool
    var map: TextureId
    var emissive_map: TextureId
    var alpha_map: TextureId
    var normal_map: TextureId
    var bump_map: TextureId
    var bump_scale: Float32
    var side: Side

    def __init__(out self):
        """Start from three.js's `MeshPhongMaterial` defaults."""
        self.color = _WHITE
        self.specular = _DEFAULT_SPECULAR
        self.emissive = _BLACK
        self.shininess = _DEFAULT_SHININESS
        self.opacity = 1
        self.transparent = False
        self.map = NO_TEXTURE
        self.emissive_map = NO_TEXTURE
        self.alpha_map = NO_TEXTURE
        self.normal_map = NO_TEXTURE
        self.bump_map = NO_TEXTURE
        self.bump_scale = 1
        self.side = FRONT_SIDE


def _phong(surface: _Surface) raises -> Material:
    """Return the `PHONG` material a surface describes.

    Args:
        surface: What the keys said.

    Returns:
        The material.

    Raises:
        Error: If `Material` refuses it, which the checks made while the
            keys were read leave no way to do. A bump map beside a normal
            map is dropped rather than refused.
    """
    return Material(
        surface.color,
        kind=PHONG,
        map=surface.map,
        specular=surface.specular,
        shininess=surface.shininess,
        emissive=surface.emissive,
        emissive_map=surface.emissive_map,
        alpha_map=surface.alpha_map,
        normal_map=surface.normal_map,
        # three.js reads the normal map of a material with both and ignores
        # the bump map; `Material` refuses both, so the bump map is dropped.
        bump_map=NO_TEXTURE if surface.normal_map
        != NO_TEXTURE else surface.bump_map,
        bump_scale=surface.bump_scale,
        opacity=surface.opacity,
        transparent=surface.transparent,
        side=surface.side,
    )


struct _Textures(Movable):
    """The textures one library has read so far, so an image read the same
    way twice is decoded once."""

    var keys: List[String]
    var ids: List[TextureId]

    def __init__(out self):
        """Start with none."""
        self.keys = List[String]()
        self.ids = List[TextureId]()


@fieldwise_init
struct _TextureLine(Copyable, Movable):
    """What a texture line says: the file, its transform and wrap, and the
    bump scale if it gives one."""

    var file: String
    var repeat: Vector2
    var offset: Vector2
    var clamp: Bool
    var has_bump_scale: Bool
    var bump_scale: Float32


def _where(line: Int) -> String:
    """Return the prefix an error names its line with."""
    return "MTL line " + String(line) + ": "


def _number(field: String, line: Int) raises -> Float32:
    """Return a number read from a field, refused unless finite as a
    `Float32`.

    Args:
        field: The text.
        line: Which line it is on, for the error.

    Returns:
        The number.

    Raises:
        Error: If the field is not a number, or is not finite once it is a
            `Float32`.
    """
    var wide: Float64
    try:
        wide = Float64(field)
    except reason:
        raise Error(
            _where(line)
            + "not a number: "
            + field
            + " ("
            + String(reason)
            + ")"
        )
    var value = Float32(wide)
    if not isfinite(value):
        raise Error(_where(line) + "a number must be finite: " + field)
    return value


def _fraction(field: String, line: Int) raises -> Float32:
    """Return a number from zero to one read from a field.

    Args:
        field: The text.
        line: Which line it is on, for the error.

    Returns:
        The number.

    Raises:
        Error: If the field is not a finite number, or is outside zero to
            one.
    """
    var value = _number(field, line)
    if value < 0 or value > 1:
        raise Error(_where(line) + "must be from zero to one: " + field)
    return value


def _channels(
    value: String, line: Int, normalize: Bool
) raises -> List[Float32]:
    """Return the three numbers of a `Kd`, `Ks` or `Ke` line, divided by
    255 when `normalize` is on, as three.js's `normalizeRGB` divides them.

    Args:
        value: The three numbers.
        line: Which line it is on, for the error.
        normalize: Divide each by 255.

    Returns:
        The three channels, each from zero to one.

    Raises:
        Error: If there are not exactly three numbers, or one is not a
            number or is outside zero to one once divided.
    """
    var fields = List[String]()
    for piece in value.split():  # pragma: no branch
        fields.append(String(piece))
    if len(fields) != 3:
        raise Error(_where(line) + "a color needs three numbers: " + value)
    var out = List[Float32]()
    for field in fields:  # pragma: no branch
        var channel = _number(field, line)
        if normalize:
            channel /= 255
        if channel < 0 or channel > 1:
            raise Error(_where(line) + "must be from zero to one: " + field)
        out.append(channel)
    return out^


def _is_black(channels: List[Float32]) -> Bool:
    """Return True if all three channels are zero."""
    return channels[0] == 0 and channels[1] == 0 and channels[2] == 0


def _color(channels: List[Float32]) -> Color:
    """Return the color three channels give, as authored in sRGB, as
    three.js reads it.

    Args:
        channels: The three channels, from zero to one.

    Returns:
        The eight-bit color nearest them.
    """
    return FloatColor(channels[0], channels[1], channels[2], 1).quantize()


def _illumination(value: String, line: Int) raises:
    """Check an `illum` line: a whole number from zero to ten.

    Args:
        value: The text.
        line: Which line it is on, for the error.

    Raises:
        Error: If the text is not a whole number, or is outside zero to
            ten.
    """
    var model: Int
    try:
        model = Int(value)
    except reason:
        raise Error(
            _where(line)
            + "illum must be a whole number: "
            + value
            + " ("
            + String(reason)
            + ")"
        )
    if model < 0 or model > _LAST_ILLUMINATION:
        raise Error(_where(line) + "illum must be from 0 to 10: " + value)


def _option_numbers(
    tokens: List[String], start: Int, least: Int, most: Int, line: Int
) raises -> List[Float32]:
    """Return the numbers after a texture option: as many as follow, from
    `least` up to `most`.

    Args:
        tokens: The texture line, split on whitespace.
        start: Where the first number would be.
        least: How many the option needs.
        most: How many it can take.
        line: Which line it is on, for the error.

    Returns:
        The numbers.

    Raises:
        Error: If fewer than `least` follow, or one is not finite.
    """
    var values = List[Float32]()
    var at = start
    while at < len(tokens) and len(values) < most:
        try:
            _ = Float64(tokens[at])
        except:
            break
        values.append(_number(tokens[at], line))
        at += 1
    if len(values) < least:
        raise Error(
            _where(line)
            + tokens[start - 1]
            + " needs "
            + String(least)
            + " numbers"
        )
    return values^


def _texture_line(value: String, line: Int) raises -> _TextureLine:
    """Return what a texture line says, three.js's `getTextureParams`.

    Args:
        value: The options and the file name.
        line: Which line it is on, for the error.

    Returns:
        The file, the repeat and offset, whether it clamps, and the bump
        scale if the line gives one.

    Raises:
        Error: If an option is not known or lacks its values, or no file
            is named.
    """
    var tokens = List[String]()
    for piece in value.split():  # pragma: no branch
        tokens.append(String(piece))
    var file = String()
    var repeat = Vector2(1, 1)
    var offset = Vector2(0, 0)
    var clamp = False
    var has_bump_scale = False
    var bump_scale = Float32(1)
    var at = 0
    while at < len(tokens):
        var token = tokens[at]
        at += 1
        if token == "-s" or token == "-o":
            var values = _option_numbers(tokens, at, 1, 3, line)
            at += len(values)
            var second = values[1] if len(values) > 1 else Float32(
                1 if token == "-s" else 0
            )
            if token == "-s":
                repeat = Vector2(values[0], second)
            else:
                offset = Vector2(values[0], second)
        elif token == "-bm":
            bump_scale = _option_numbers(tokens, at, 1, 1, line)[0]
            has_bump_scale = True
            at += 1
        elif token == "-mm":
            at += len(_option_numbers(tokens, at, 2, 2, line))
        elif token == "-clamp":
            var setting = tokens[at] if at < len(tokens) else String()
            if setting != "on" and setting != "off":
                raise Error(_where(line) + "-clamp needs on or off")
            clamp = setting == "on"
            at += 1
        elif token.startswith("-"):
            raise Error(
                _where(line)
                + "a texture option this reader does not know: "
                + token
            )
        else:
            if file != "":
                file += " "
            file += token
    if file == "":
        raise Error(_where(line) + "a texture line names no file")
    return _TextureLine(
        file^, repeat, offset, clamp, has_bump_scale, bump_scale
    )


def _texture(
    current: TextureId,
    entry: _Entry,
    role: Int,
    directory: String,
    mut bump_scale: Float32,
    mut assets: Assets,
    mut textures: _Textures,
    wrap: Wrap,
) raises -> TextureId:
    """Return the texture a texture line names, three.js's
    `setMapForType`: the one already set, if any, since the first is kept.

    Args:
        current: The texture the material has for this use so far, or
            `NO_TEXTURE`.
        entry: The texture line.
        role: `_COLOR_ROLE`, `_GLOW_ROLE` or `_DATA_ROLE`.
        directory: Where the file names are relative to.
        bump_scale: The material's bump scale, set by a `-bm` option.
        assets: Where the texture is added.
        textures: What this library has read, to read an image once.
        wrap: The wrap of a texture that does not clamp.

    Returns:
        The texture's id.

    Raises:
        Error: If the line is refused, or the image cannot be read or
            decoded.
    """
    if current != NO_TEXTURE:
        return current
    var said = _texture_line(entry.value, entry.line)
    if said.has_bump_scale:
        bump_scale = said.bump_scale
    var path = directory + said.file
    var key = (
        path
        + "|"
        + String(role)
        + "|"
        + String(said.repeat.x)
        + ","
        + String(said.repeat.y)
        + "|"
        + String(said.offset.x)
        + ","
        + String(said.offset.y)
        + "|"
        + String(said.clamp)
    )
    for index in range(len(textures.keys)):
        if textures.keys[index] == key:
            return textures.ids[index]
    var image = decode_image(_image_bytes(path, entry.line))
    var built = texture_from(
        image,
        CLAMP if said.clamp else wrap,
        color_space=LINEAR if role == _DATA_ROLE else SRGB,
        alpha=COVERAGE if role == _COLOR_ROLE else IGNORED,
    )
    built.repeat = said.repeat
    built.offset = said.offset
    var id = assets.textures.add(built^)
    textures.keys.append(key^)
    textures.ids.append(id)
    return id


def _image_bytes(path: String, line: Int) raises -> List[UInt8]:
    """Return an image file's bytes.

    Args:
        path: The file.
        line: Which line named it, for the error.

    Returns:
        The bytes.

    Raises:
        Error: If the file cannot be read.
    """
    try:
        return Path(path).read_bytes()
    except reason:
        raise Error(
            _where(line)
            + "cannot read the texture "
            + path
            + ": "
            + String(reason)
        )


def _build(
    info: _Info,
    directory: String,
    mut assets: Assets,
    mut textures: _Textures,
    options: MtlOptions,
) raises -> MaterialId:
    """Build one material from its keys, three.js's `createMaterial_`.

    Args:
        info: The material's keys.
        directory: Where texture file names are relative to.
        assets: Where the material and its textures are added.
        textures: What this library has read, to read an image once.
        options: The side, the wrap, and how colors and `Tr` are read.

    Returns:
        The material's id.

    Raises:
        Error: If a value is refused; see `parse_mtl`.
    """
    var surface = _Surface()
    surface.side = options.side
    for entry in info.entries:
        # An empty value is skipped, as three.js skips it.
        if entry.value == "":
            continue
        var key = entry.key
        if key == "kd" or key == "ks":
            var channels = _channels(
                entry.value, entry.line, options.normalize_rgb
            )
            # three.js's `ignoreZeroRGBs` drops the key, and the default
            # stays.
            if options.ignore_zero_rgbs and _is_black(channels):
                continue
            if key == "kd":
                surface.color = _color(channels)
            else:
                surface.specular = _color(channels)
        elif key == "ke":
            surface.emissive = _color(_channels(entry.value, entry.line, False))
        elif key == "ns":
            var shininess = _number(entry.value, entry.line)
            if shininess < 0:
                raise Error(
                    _where(entry.line)
                    + "Ns must not be negative: "
                    + entry.value
                )
            surface.shininess = shininess
        elif key == "d":
            var opacity = _fraction(entry.value, entry.line)
            if opacity < 1:
                surface.opacity = opacity
                surface.transparent = True
        elif key == "tr":
            var clear = _fraction(entry.value, entry.line)
            if options.invert_tr_property:
                clear = 1 - clear
            if clear > 0:
                surface.opacity = 1 - clear
                surface.transparent = True
        elif key == "illum":
            _illumination(entry.value, entry.line)
        elif key == "map_kd":
            surface.map = _texture(
                surface.map,
                entry,
                _COLOR_ROLE,
                directory,
                surface.bump_scale,
                assets,
                textures,
                options.wrap,
            )
        elif key == "map_ke":
            surface.emissive_map = _texture(
                surface.emissive_map,
                entry,
                _GLOW_ROLE,
                directory,
                surface.bump_scale,
                assets,
                textures,
                options.wrap,
            )
        elif key == "map_d":
            surface.alpha_map = _texture(
                surface.alpha_map,
                entry,
                _DATA_ROLE,
                directory,
                surface.bump_scale,
                assets,
                textures,
                options.wrap,
            )
            surface.transparent = True
        elif key == "norm":
            surface.normal_map = _texture(
                surface.normal_map,
                entry,
                _DATA_ROLE,
                directory,
                surface.bump_scale,
                assets,
                textures,
                options.wrap,
            )
        elif key == "map_bump" or key == "bump":
            surface.bump_map = _texture(
                surface.bump_map,
                entry,
                _DATA_ROLE,
                directory,
                surface.bump_scale,
                assets,
                textures,
                options.wrap,
            )
    return assets.materials.add(_phong(surface))


def _read_infos(text: String) raises -> List[_Info]:
    """Read a library's text into one block of keys per material, three.js's
    `MTLLoader.parse`.

    Args:
        text: The whole file.

    Returns:
        The materials, in the order their names first appear.

    Raises:
        Error: If a `newmtl` line names nothing.
    """
    var infos = List[_Info]()
    # Which block the lines go to; none before the first `newmtl`.
    var current = -1
    var line = 0
    # A split yields at least one piece: the loop always runs.
    for raw in text.split("\n"):  # pragma: no branch
        line += 1
        var stripped = String(String(raw).strip())
        var comment = stripped.find("#")
        if comment >= 0:
            var data = String(stripped[byte=0:comment].strip())
            stripped = data^
        if stripped == "":
            continue
        var first = String()
        # The line is not empty, so it has a first field.
        for piece in stripped.split():  # pragma: no branch
            first = String(piece)
            break
        var key = first.lower()
        var value = String(stripped[byte = first.byte_length() :].strip())
        if key == "newmtl":
            if value == "":
                raise Error(_where(line) + "newmtl names no material")
            current = -1
            for index in range(len(infos)):
                if infos[index].name == value:
                    current = index
            if current < 0:
                current = len(infos)
                infos.append(_Info(value))
            else:
                # A second block of one name replaces the first, in its
                # place, as three.js replaces it.
                infos[current] = _Info(value)
        elif current >= 0:
            infos[current].set(key, value, line)
    return infos^


def parse_mtl(
    text: String,
    directory: String,
    mut assets: Assets,
    options: MtlOptions = MtlOptions(),
) raises -> MtlLibrary:
    """Read a material library's text, building a `PHONG` material per
    `newmtl` and a texture per image it names.

    Args:
        text: The whole file.
        directory: Where texture file names are relative to, ending in `/`,
            or empty for the working directory.
        assets: Where the materials and textures are added.
        options: The options of three.js's `setMaterialOptions`.

    Returns:
        The library: each material's name and id, in the order the names
        first appear.

    Raises:
        Error: If a `newmtl` names nothing; a color is not three numbers
            from zero to one; `Ns` is not a number or is negative; `d` or
            `Tr` is not from zero to one; `illum` is not a whole number
            from zero to ten; a texture line has an option that is not
            known or lacks its numbers, or names no file; or an image
            cannot be read or decoded. Also if the options' side or wrap
            is none of the named.
    """
    options.validate()
    var infos = _read_infos(text)
    var library = MtlLibrary(options.side)
    var textures = _Textures()
    for index in range(len(infos)):
        library.add(
            infos[index].name,
            _build(infos[index], directory, assets, textures, options),
        )
    return library^


def _directory_of(path: String) -> String:
    """Return a path's directory, ending in `/`, or empty for none.

    Args:
        path: A file's path.

    Returns:
        The directory.
    """
    return String(path[byte = 0 : path.rfind("/") + 1])


def read_mtl(
    path: String, mut assets: Assets, options: MtlOptions = MtlOptions()
) raises -> MtlLibrary:
    """Read a material library file; see `parse_mtl`.

    Texture file names are relative to the library's own directory.

    Args:
        path: The file.
        assets: Where the materials and textures are added.
        options: The options of three.js's `setMaterialOptions`.

    Returns:
        The library.

    Raises:
        Error: If the file cannot be read, or for anything `parse_mtl`
            refuses.
    """
    return parse_mtl(
        Path(path).read_text(), _directory_of(path), assets, options
    )


def set_materials(
    model: ObjModel, mut library: MtlLibrary, mut assets: Assets
) raises -> List[List[MaterialId]]:
    """Return the materials each object of an OBJ model draws with,
    three.js's `OBJLoader.setMaterials`.

    A `usemtl` name the library does not have, or no name, gets a default
    `PHONG` material, one per name; see `MtlLibrary.create`.

    Args:
        model: The OBJ model.
        library: Its materials. A default material is added to it.
        assets: Where a default material is added.

    Returns:
        One list per object, in the model's order, with one id per entry
        of the object's `materials`: group `i` of its geometry wears
        entry `i`. See `obj_mesh`.

    Raises:
        Error: Never for a store that takes a default material; see
            `MtlLibrary.create`.
    """
    var ids = List[List[MaterialId]]()
    for index in range(model.count()):
        var own = List[MaterialId]()
        ref names = model.objects[index].materials
        for entry in range(len(names)):  # pragma: no branch
            own.append(library.create(names[entry], assets))
        ids.append(own^)
    return ids^


def obj_mesh(
    materials: List[MaterialId], geometry: GeometryId, node: NodeId
) raises -> Mesh:
    """Return the mesh three.js's `OBJLoader.parse` builds for an object:
    one material, or a material list for an object with several.

    Args:
        materials: The object's materials, from `set_materials`.
        geometry: Its geometry, in a store.
        node: Where it is drawn.

    Returns:
        A mesh with one material when the list has one entry, and with
        the list otherwise.

    Raises:
        Error: If the list is empty or an id is negative.
    """
    if len(materials) == 1:
        return Mesh(geometry, materials[0], node)
    return Mesh(geometry, materials, node)


struct ObjWithMaterials(Movable):
    """An OBJ model, the materials its libraries built, and the material
    each object draws with."""

    var model: ObjModel
    var library: MtlLibrary
    # One list per object of `model`, in its order; see `set_materials`.
    var materials: List[List[MaterialId]]

    def __init__(
        out self,
        var model: ObjModel,
        var library: MtlLibrary,
        var materials: List[List[MaterialId]],
    ):
        """Bundle a model with its materials.

        Args:
            model: The OBJ model.
            library: Its materials.
            materials: One list of ids per object.
        """
        self.model = model^
        self.library = library^
        self.materials = materials^


def read_obj_with_materials(
    path: String, mut assets: Assets, options: MtlOptions = MtlOptions()
) raises -> ObjWithMaterials:
    """Read an OBJ file and every material library it names, and give each
    object its material.

    Each `mtllib` is read relative to the OBJ file's directory, in file
    order. A later library's material replaces an earlier one's of the
    same name. The geometries stay in the model, to go into a store with
    `ObjObject.take_geometry`.

    Args:
        path: The OBJ file.
        assets: Where the materials and textures are added.
        options: The options every library is read with; see
            `parse_mtl`.

    Returns:
        The model, the combined library, and one list of `MaterialId`s
        per object.

    Raises:
        Error: If the OBJ file or a library cannot be read, or for anything
            `parse_obj` or `parse_mtl` refuses, the options included.
    """
    options.validate()
    var model = read_obj(path)
    var directory = _directory_of(path)
    var library = MtlLibrary(options.side)
    for index in range(len(model.material_libraries)):
        library.merge(
            read_mtl(
                directory + model.material_libraries[index], assets, options
            )
        )
    var ids = set_materials(model, library, assets)
    return ObjWithMaterials(model^, library^, ids^)
