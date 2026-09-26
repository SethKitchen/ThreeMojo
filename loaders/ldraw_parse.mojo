# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""LDraw text read into parts and colors, from three.js
`examples/jsm/loaders/LDrawLoader.js`: its `LineParser`,
`LDrawParsedCache` and `parseColorMetaDirective`.

`LDrawLoader` holds what three.js's loader holds between files: the color
library, the materials each color makes, the parts it has read, and where
to find more. `LDrawLoader.parse_text` reads one file's lines, three.js's
`LDrawParsedCache.parse`:

- `0` lines are meta commands: the part type, `!COLOUR` definitions,
  `!CATEGORY`, `!KEYWORDS`, `Author:`, `STEP`, `BFC` and `FILE`, which
  starts the files a multi-part file embeds.
- `1` lines place another file, with a color and a matrix.
- `2` and `5` lines are edges and conditional edges; `3` and `4` are
  triangles and quads, wound by the `BFC` state, and doubled when the part
  is not certified or does not cull.

A color is a `MeshStandardMaterial` of its finish, with a
`LineBasicMaterial` for its edges and an `LDrawConditionalLineMaterial`
for its conditional edges, each an `LDrawMaterial`. `0x2RRGGBB` names a
direct color, made anew each time it is asked for.

**Where three.js's reading is kept.** A number where a color directive
expects a keyword sets the luminance, as three.js tries each token as a
luminance first. `parseInt` reads a leading `0x` as hexadecimal. A color
style that is not `#RGB` or `#RRGGBB` leaves the color white. A file is
looked for under `parts/`, `p/` and `models/`, as it is named, beside the
file that names it, and then all of that again in lower case.

**What is refused.** What three.js throws on: a line of an unknown type, a
color with no name, an unknown token, a fill color that is not
hexadecimal, an edge color that names no color, an alpha or luminance
that is not a number, and a file that is not found.
"""

from loaders.js_number import js_parse_float
from std.math import nan
from std.pathlib import Path

comptime Vec = SIMD[DType.float64, 4]
# A color that stands for the part's color, and one for its edge color.
comptime MAIN_COLOUR_CODE = "16"
comptime MAIN_EDGE_COLOUR_CODE = "24"


def js_parse_int(text: String) -> Float64:
    """Return JavaScript's `parseInt( text )` with no radix: white space and
    a sign, then `0x` for hexadecimal, or decimal digits.

    Args:
        text: The text.

    Returns:
        The number, or NaN when there is no digit.
    """
    var b = text.as_bytes()
    var i = 0
    while i < len(b) and (b[i] == 32 or b[i] == 9 or b[i] == 10 or b[i] == 13):
        i += 1
    var negative = False
    if i < len(b) and (b[i] == 43 or b[i] == 45):
        negative = b[i] == 45
        i += 1
    var radix = 10
    if i + 1 < len(b) and b[i] == 48 and (b[i + 1] == 120 or b[i + 1] == 88):
        radix = 16
        i += 2
    var value = Float64(0)
    var digits = 0
    while i < len(b):
        var c = Int(b[i])
        var d = -1
        if c >= 48 and c <= 57:
            d = c - 48
        elif c >= 97 and c <= 102:
            d = c - 87
        elif c >= 65 and c <= 70:
            d = c - 55
        if d < 0 or d >= radix:
            break
        value = value * Float64(radix) + Float64(d)
        digits += 1
        i += 1
    if digits == 0:
        return nan[DType.float64]()
    return -value if negative else value


def _is_nan(v: Float64) -> Bool:
    return v != v


struct LineParser(Movable):
    """Port three.js's `LineParser`: tokens of one line, split at spaces and
    tabs."""

    var line: String
    var at: Int
    var number: Int

    def __init__(out self, var line: String, number: Int = -1):
        """Start at the line's first character.

        Args:
            line: The line.
            number: Its number in the file, or -1.
        """
        self.line = line^
        self.at = 0
        self.number = number

    def _space(self, i: Int) -> Bool:
        var c = self.line.as_bytes()[i]
        return c == 32 or c == 9

    def seek_non_space(mut self):
        """Move to the next character that is not a space or a tab."""
        var n = self.line.byte_length()
        while self.at < n:
            if not self._space(self.at):
                return
            self.at += 1

    def token(mut self) -> String:
        """Return the characters up to the next space, and move past the
        spaces after them: three.js's `getToken`.

        Returns:
            The token, empty at the end.
        """
        var n = self.line.byte_length()
        var start = self.at
        self.at += 1
        while self.at < n:
            if self._space(self.at):
                break
            self.at += 1
        var end = self.at
        self.seek_non_space()
        if start >= n:
            return String()
        return String(self.line[byte = start : min(end, n)])

    def vector(mut self) -> Vec:
        """Return three numbers, `parseFloat` of three tokens.

        Returns:
            The vector.
        """
        var x = js_parse_float(self.token())
        var y = js_parse_float(self.token())
        var z = js_parse_float(self.token())
        return Vec(x, y, z, 0)

    def rest(self) -> String:
        """Return the rest of the line: three.js's `getRemainingString`.

        Returns:
            The text.
        """
        var n = self.line.byte_length()
        if self.at >= n:
            return String()
        return String(self.line[byte = self.at :])

    def at_end(self) -> Bool:
        """Return True past the last character.

        Returns:
            Whether the parser is at the end.
        """
        return self.at >= self.line.byte_length()

    def where(self) -> String:
        """Return ` at line N`, or nothing.

        Returns:
            The text.
        """
        return " at line " + String(self.number) if self.number >= 0 else ""


struct LDrawMaterial(Copyable, Movable):
    """A material three.js's LDraw loader makes: a surface of a color, its
    edge, or its conditional edge. Colors are linear."""

    # `MeshStandardMaterial`, `LineBasicMaterial` or
    # `LDrawConditionalLineMaterial`.
    var type: String
    var name: String
    var code: Optional[String]
    var color: Vec
    var emissive: Vec
    var roughness: Float64
    var metalness: Float64
    var opacity: Float64
    var transparent: Bool
    var depth_write: Bool
    var premultiplied_alpha: Bool
    var polygon_offset: Bool
    var polygon_offset_factor: Float64
    # three.js's `edgeMaterialCache` and `conditionalEdgeMaterialCache`: the
    # edge of a surface, and the conditional edge of an edge, as indices
    # into `LDrawLoader.all`, or -1.
    var edge: Int
    var conditional: Int

    def __init__(out self, var type: String, var name: String):
        """Start a material at three.js's defaults: white, opaque.

        Args:
            type: The three.js class.
            name: The name.
        """
        self.type = type^
        self.name = name^
        self.code = None
        self.color = Vec(1, 1, 1, 0)
        self.emissive = Vec(0)
        self.roughness = 1
        self.metalness = 0
        self.opacity = 1
        self.transparent = False
        self.depth_write = True
        self.premultiplied_alpha = False
        self.polygon_offset = False
        self.polygon_offset_factor = 0
        self.edge = -1
        self.conditional = -1


def _style(style: String) -> Optional[Vec]:
    """Return three.js's `Color.setStyle` of a `#` color in sRGB, made
    linear: three or six hexadecimal digits, or nothing for another."""
    var b = style.as_bytes()
    if len(b) < 2 or b[0] != 35:
        return None
    var digits = List[Int]()
    for k in range(1, len(b)):  # pragma: no branch
        var c = Int(b[k])
        var d = -1
        if c >= 48 and c <= 57:
            d = c - 48
        elif c >= 97 and c <= 102:
            d = c - 87
        elif c >= 65 and c <= 70:
            d = c - 55
        if d < 0:
            return None
        digits.append(d)
    var out = Vec(0)
    if len(digits) == 3:
        for k in range(3):  # pragma: no branch
            out[k] = Float64(digits[k]) / 15
    elif len(digits) == 6:
        for k in range(3):  # pragma: no branch
            out[k] = Float64(digits[2 * k] * 16 + digits[2 * k + 1]) / 255
    else:
        return None
    for k in range(3):  # pragma: no branch
        var c = out[k]
        out[k] = (
            c * 0.0773993808 if c
            < 0.04045 else (c * 0.9478672986 + 0.0521327014) ** 2.4
        )
    return out


struct LDrawFace(Copyable, Movable):
    """A triangle or a quad: its color, its material if its file defines
    it, its corners, and the normals smoothing gives them."""

    var color_code: String
    # An index into `LDrawLoader.all`, or -1.
    var material: Int
    var vertices: List[Vec]
    # A shared normal of `smooth_normals`, as an index, or -1.
    var normals: List[Int]
    var face_normal: Vec
    var has_face_normal: Bool

    def __init__(
        out self, var color_code: String, material: Int, var vertices: List[Vec]
    ):
        """Make a face with no normals yet.

        Args:
            color_code: Its color.
            material: Its material, or -1.
            vertices: Its three or four corners.
        """
        self.color_code = color_code^
        self.material = material
        self.normals = List[Int](length=len(vertices), fill=-1)
        self.vertices = vertices^
        self.face_normal = Vec(0)
        self.has_face_normal = False


struct LDrawSegment(Copyable, Movable):
    """An edge, or a conditional edge with its two control points."""

    var color_code: String
    var material: Int
    var vertices: List[Vec]
    var controls: List[Vec]

    def __init__(
        out self,
        var color_code: String,
        material: Int,
        var vertices: List[Vec],
        var controls: List[Vec],
    ):
        """Make a segment.

        Args:
            color_code: Its color.
            material: Its material, or -1.
            vertices: Its two ends.
            controls: Its two control points, or none.
        """
        self.color_code = color_code^
        self.material = material
        self.vertices = vertices^
        self.controls = controls^


struct LDrawSubobject(Copyable, Movable):
    """A `1` line: another file, placed and colored."""

    var material: Int
    var color_code: String
    # Column-major, as three.js's `Matrix4.elements`.
    var matrix: List[Float64]
    var file_name: String
    var inverted: Bool
    var starting_building_step: Bool

    def __init__(
        out self,
        material: Int,
        var color_code: String,
        var matrix: List[Float64],
        var file_name: String,
        inverted: Bool,
        starting_building_step: Bool,
    ):
        """Hold a placement.

        Args:
            material: Its color's material in the file, or -1.
            color_code: Its color.
            matrix: Its matrix.
            file_name: The file it places.
            inverted: Whether `BFC INVERTNEXT` came before it.
            starting_building_step: Whether a `STEP` came before it.
        """
        self.material = material
        self.color_code = color_code^
        self.matrix = matrix^
        self.file_name = file_name^
        self.inverted = inverted
        self.starting_building_step = starting_building_step


struct LDrawInfo(Copyable, Movable):
    """One file read: three.js's parsed result."""

    var faces: List[LDrawFace]
    var line_segments: List[LDrawSegment]
    var conditional_segments: List[LDrawSegment]
    var type: String
    var category: Optional[String]
    var keywords: Optional[List[String]]
    var author: Optional[String]
    var subobjects: List[LDrawSubobject]
    var total_faces: Int
    var starting_building_step: Bool
    # The colors the file defines, by code: indices into `LDrawLoader.all`.
    var material_codes: List[String]
    var material_ids: List[Int]
    var file_name: Optional[String]

    def __init__(out self):
        """Start an empty model."""
        self.faces = List[LDrawFace]()
        self.line_segments = List[LDrawSegment]()
        self.conditional_segments = List[LDrawSegment]()
        self.type = "Model"
        self.category = None
        self.keywords = None
        self.author = None
        self.subobjects = List[LDrawSubobject]()
        self.total_faces = 0
        self.starting_building_step = False
        self.material_codes = List[String]()
        self.material_ids = List[Int]()
        self.file_name = None

    def local(self, code: String) -> Int:
        """Return a color the file defines, or -1.

        Args:
            code: The color code.

        Returns:
            Its material.
        """
        for k in range(len(self.material_codes)):
            if self.material_codes[k] == code:
                return self.material_ids[k]
        return -1

    def define(mut self, var code: String, material: Int):
        """Define a color, or define it again.

        Args:
            code: The color code.
            material: Its material.
        """
        for k in range(len(self.material_codes)):
            if self.material_codes[k] == code:
                self.material_ids[k] = material
                return
        self.material_codes.append(code^)
        self.material_ids.append(material)


def is_part_type(type: String) -> Bool:
    """Return three.js's `isPartType`.

    Args:
        type: A file's `!LDRAW_ORG` type.

    Returns:
        Whether it is a part, which three.js keeps built.
    """
    return type == "Part" or type == "Unofficial_Part"


def is_primitive_type(type: String) -> Bool:
    """Return three.js's `isPrimitiveType`: its name holds `primitive` in
    any case, or it is `Subpart`.

    Args:
        type: A file's type.

    Returns:
        Whether its faces are merged into the file that places it.
    """
    return "primitive" in type.lower() or type == "Subpart"


struct LDrawLoader(Movable):
    """What three.js's `LDrawLoader` holds: the color library, every
    material made, the files read, and where parts are."""

    # Every material made, in order; `materials` are the library's, as
    # indices into it.
    var all: List[LDrawMaterial]
    var materials: List[Int]
    var library_codes: List[String]
    var library_ids: List[Int]
    # The folder the parts library is in, three.js's `partsLibraryPath`.
    var parts_library_path: String
    # Names a `1` line gives, and the files to read for them.
    var file_map_names: List[String]
    var file_map_files: List[String]
    var smooth_normals: Bool
    # The files read, by name in lower case.
    var cache_names: List[String]
    var cache: List[LDrawInfo]
    # three.js's `missingColorMaterial` and its edges.
    var missing: Int

    def __init__(out self, parts_library_path: String = ""):
        """Start with no colors but three.js's missing ones.

        Args:
            parts_library_path: The folder of the parts library.
        """
        self.all = List[LDrawMaterial]()
        self.materials = List[Int]()
        self.library_codes = List[String]()
        self.library_ids = List[Int]()
        self.parts_library_path = parts_library_path
        self.file_map_names = List[String]()
        self.file_map_files = List[String]()
        self.smooth_normals = True
        self.cache_names = List[String]()
        self.cache = List[LDrawInfo]()
        var missing = LDrawMaterial("MeshStandardMaterial", "__DEFAULT")
        missing.color = _style("#FF00FF").value()
        missing.roughness = 0.3
        var edge = LDrawMaterial("LineBasicMaterial", "__DEFAULT")
        edge.color = missing.color
        var conditional = LDrawMaterial(
            "LDrawConditionalLineMaterial", "__DEFAULT"
        )
        conditional.color = missing.color
        # three.js's constructor caches the missing edge's conditional edge
        # before `setConditionalLineMaterial` makes it, so the cache holds
        # null, and a missing color's conditional edges have no material.
        self.all.append(conditional^)
        self.all.append(edge^)
        missing.edge = 1
        self.all.append(missing^)
        self.missing = 2

    def set_file_map(mut self, names: List[String], files: List[String]):
        """Read some names from other files, three.js's `setFileMap`.

        Args:
            names: Names as `1` lines give them.
            files: The file for each.
        """
        self.file_map_names = names.copy()
        self.file_map_files = files.copy()

    # --- colors ------------------------------------------------------------

    def library(self, code: String) -> Int:
        """Return the library's material of a code, or -1."""
        for k in range(len(self.library_codes)):
            if self.library_codes[k] == code:
                return self.library_ids[k]
        return -1

    def add_material(mut self, material: Int):
        """Port three.js's `addMaterial`: the first material of a code is kept.

        Args:
            material: The material.
        """
        var code = self.all[material].code.value() if Bool(
            self.all[material].code
        ) else String("null")
        if self.library(code) >= 0:
            return
        self.materials.append(material)
        self.library_codes.append(code)
        self.library_ids.append(material)

    def add_default_materials(mut self) raises:
        """Port three.js's `addDefaultMaterials`: the main color and the edge
        color, for a file that defines neither.

        Raises:
            Error: Never, for these two directives.
        """
        var main = LineParser("Main_Colour CODE 16 VALUE #FF8080 EDGE #333333")
        self.add_material(self.parse_color(main))
        var edge = LineParser("Edge_Colour CODE 24 VALUE #A0A0A0 EDGE #333333")
        self.add_material(self.parse_color(edge))

    def get_material(mut self, code: String) raises -> Int:
        """Port three.js's `getMaterial`: a direct color, made anew, or the
        library's.

        Args:
            code: The color code.

        Returns:
            The material, or -1.

        Raises:
            Error: Never, for a direct color's directive.
        """
        if code.startswith("0x2"):
            var color = String(code[byte=3:])
            var line = LineParser(
                "Direct_Color_"
                + color
                + " CODE -1 VALUE #"
                + color
                + " EDGE #"
                + color
            )
            return self.parse_color(line)
        return self.library(code)

    def parse_color(mut self, mut lp: LineParser) raises -> Int:
        """Port three.js's `parseColorMetaDirective`: a surface of its finish,
        and its edge and conditional edge unless it names another color's
        edge. The surface goes into the library.

        Args:
            lp: The directive, after `!COLOUR`.

        Returns:
            The surface.

        Raises:
            Error: For a directive three.js throws on.
        """
        var code: Optional[String] = None
        var fill = String("#FF00FF")
        var edge_color = String("#FF00FF")
        var alpha = Float64(1)
        var transparent = False
        var luminance = Float64(0)
        var finish = String("DEFAULT")
        var edge = -1
        var name = lp.token()
        if name.byte_length() == 0:
            raise Error(
                'LDrawLoader: Material name was expected after "!COLOUR tag'
                + lp.where()
                + "."
            )
        while True:
            var token = lp.token()
            if token.byte_length() == 0:
                break
            var lum = _luminance(token)
            if not _is_nan(lum):
                luminance = lum
                continue
            var upper = token.upper()
            if upper == "CODE":
                code = lp.token()
            elif upper == "VALUE":
                fill = lp.token()
                if fill.startswith("0x"):
                    fill = "#" + String(fill[byte=2:])
                elif not fill.startswith("#"):
                    raise Error(
                        "LDrawLoader: Invalid color while parsing material"
                        + lp.where()
                        + "."
                    )
            elif upper == "EDGE":
                edge_color = lp.token()
                if edge_color.startswith("0x"):
                    edge_color = "#" + String(edge_color[byte=2:])
                elif not edge_color.startswith("#"):
                    var named = self.get_material(edge_color)
                    if named < 0:
                        raise Error(
                            "LDrawLoader: Invalid edge color while parsing"
                            " material"
                            + lp.where()
                            + "."
                        )
                    edge = self.all[named].edge
            elif upper == "ALPHA":
                alpha = js_parse_int(lp.token())
                if _is_nan(alpha):
                    raise Error(
                        "LDrawLoader: Invalid alpha value in material"
                        " definition"
                        + lp.where()
                        + "."
                    )
                alpha = max(0.0, min(1.0, alpha / 255))
                if alpha < 1:
                    transparent = True
            elif upper == "LUMINANCE":
                var value = _luminance(lp.token())
                if _is_nan(value):
                    raise Error(
                        "LDrawLoader: Invalid luminance value in material"
                        " definition"
                        + lp.where()
                        + "."
                    )
                luminance = value
            elif (
                upper == "CHROME"
                or upper == "PEARLESCENT"
                or upper == "RUBBER"
                or upper == "MATTE_METALLIC"
                or upper == "METAL"
            ):
                finish = upper
            elif upper == "MATERIAL":
                lp.at = lp.line.byte_length()
            else:
                raise Error(
                    'LDrawLoader: Unknown token "'
                    + token
                    + '" while parsing material'
                    + lp.where()
                    + "."
                )
        var material = LDrawMaterial("MeshStandardMaterial", name)
        material.roughness = 0.3
        material.metalness = 0
        if finish == "PEARLESCENT":
            material.metalness = 0.25
        elif finish == "CHROME":
            material.roughness = 0
            material.metalness = 1
        elif finish == "RUBBER":
            material.roughness = 0.9
        elif finish == "MATTE_METALLIC":
            material.roughness = 0.8
            material.metalness = 0.4
        elif finish == "METAL":
            material.roughness = 0.2
            material.metalness = 0.85
        var fill_color = _style(fill)
        if Bool(fill_color):
            material.color = fill_color.value()
        material.transparent = transparent
        material.premultiplied_alpha = True
        material.opacity = alpha
        material.depth_write = not transparent
        material.polygon_offset = True
        material.polygon_offset_factor = 1
        if luminance != 0 and Bool(fill_color):
            # three.js sets the emissive from the fill's style, which leaves
            # it black for a style it cannot read.
            material.emissive = fill_color.value() * luminance
        if edge < 0:
            var line = LDrawMaterial("LineBasicMaterial", name + " - Edge")
            var edge_style = _style(edge_color)
            if Bool(edge_style):
                line.color = edge_style.value()
            line.transparent = transparent
            line.opacity = alpha
            line.depth_write = not transparent
            line.code = code
            var conditional = LDrawMaterial(
                "LDrawConditionalLineMaterial", name + " - Conditional Edge"
            )
            conditional.color = line.color
            conditional.transparent = transparent
            conditional.depth_write = not transparent
            conditional.opacity = alpha
            conditional.code = code
            self.all.append(conditional^)
            line.conditional = len(self.all) - 1
            self.all.append(line^)
            edge = len(self.all) - 1
        material.code = code
        material.edge = edge
        self.all.append(material^)
        var made = len(self.all) - 1
        self.add_material(made)
        return made

    # --- files -------------------------------------------------------------

    def cached(self, name: String) -> Int:
        """Return a read file's place in the cache, by name in lower case,
        or -1."""
        var key = name.lower()
        for k in range(len(self.cache_names)):
            if self.cache_names[k] == key:
                return k
        return -1

    def set_data(mut self, name: String, text: String) raises:
        """Port three.js's `setData`: read a file's text into the cache.

        Args:
            name: The file's name.
            text: Its text.

        Raises:
            Error: For what `parse_text` refuses.
        """
        var info = self.parse_text(text, name)
        var at = self.cached(name)
        if at < 0:
            self.cache_names.append(name.lower())
            self.cache.append(info^)
        else:
            self.cache[at] = info^

    def fetch(self, name: String) raises -> String:
        """Port three.js's `fetchData`: look for a file in the parts library,
        under `parts/`, `p/` and `models/`, as named, beside itself, and
        then all of that in lower case.

        Args:
            name: The file's name.

        Returns:
            Its text.

        Raises:
            Error: If no place holds it.
        """
        var file_name = name
        var lowered = False
        var state = 0
        while state != 6:
            var url = file_name
            if state == 3:
                state += 1
            elif state == 0:
                url = "parts/" + url
                state += 1
            elif state == 1:
                url = "p/" + url
                state += 1
            elif state == 2:
                url = "models/" + url
                state += 1
            elif state == 4:
                var slash = file_name.rfind("/")
                url = String(file_name[byte = 0 : slash + 1]) + url
                state += 1
            else:
                if lowered:
                    state = 6
                else:
                    file_name = file_name.lower()
                    url = file_name
                    lowered = True
                    state = 0
            var path = Path(self.parts_library_path + url)
            if path.is_file():
                return path.read_text()
        raise Error(
            'LDrawLoader: Subobject "' + file_name + '" could not be loaded.'
        )

    def ensure_loaded(mut self, name: String) raises:
        """Port three.js's `ensureDataLoaded`: read a file once.

        Args:
            name: The file's name.

        Raises:
            Error: If it is not found, or is refused.
        """
        if self.cached(name) >= 0:
            return
        var text = self.fetch(name)
        self.set_data(name, text)

    def parse_text(
        mut self, text: String, file_name: Optional[String]
    ) raises -> LDrawInfo:
        """Port three.js's `LDrawParsedCache.parse`: read one file's lines.

        Args:
            text: The file.
            file_name: Its name, or none for the file given to `parse`.

        Returns:
            What it holds.

        Raises:
            Error: For a line of an unknown type, and for a color
                directive `parse_color` refuses.
        """
        var info = LDrawInfo()
        info.file_name = file_name
        var lines = text.replace("\r\n", "\n").split("\n")
        var embedded = False
        var embedded_name = String()
        var embedded_text = String()
        var certified = False
        var ccw = True
        var inverted = False
        var cull = True
        var step = False
        for index in range(len(lines)):  # pragma: no branch
            var line = String(lines[index])
            if line.byte_length() == 0:
                continue
            if embedded:
                if line.startswith("0 FILE "):
                    self.set_data(embedded_name, embedded_text)
                    embedded_name = String(line[byte=7:])
                    embedded_text = String()
                else:
                    embedded_text += line + "\n"
                continue
            var lp = LineParser(line, index + 1)
            lp.seek_non_space()
            if lp.at_end():
                continue
            var kind = lp.token()
            if kind == "0":
                var meta = lp.token()
                if meta == "!LDRAW_ORG":
                    info.type = lp.token()
                elif meta == "!COLOUR":
                    var material = self.parse_color(lp)
                    info.define(
                        self.all[material].code.value() if Bool(
                            self.all[material].code
                        ) else String("null"),
                        material,
                    )
                elif meta == "!CATEGORY":
                    info.category = lp.token()
                elif meta == "!KEYWORDS":
                    var words = info.keywords.value().copy() if Bool(
                        info.keywords
                    ) else List[String]()
                    for word in lp.rest().split(","):  # pragma: no branch
                        words.append(String(String(word).strip()))
                    info.keywords = words^
                elif meta == "FILE":
                    if index > 0:
                        embedded = True
                        embedded_name = lp.rest()
                        embedded_text = String()
                        certified = False
                        ccw = True
                elif meta == "BFC":
                    while not lp.at_end():
                        var token = lp.token()
                        if token == "CERTIFY" or token == "NOCERTIFY":
                            certified = token == "CERTIFY"
                            ccw = True
                        elif token == "CW" or token == "CCW":
                            ccw = token == "CCW"
                        elif token == "INVERTNEXT":
                            inverted = True
                        elif token == "CLIP" or token == "NOCLIP":
                            cull = token == "CLIP"
                elif meta == "STEP":
                    step = True
                elif meta == "Author:":
                    info.author = lp.token()
            elif kind == "1":
                var code = lp.token()
                var material = info.local(code)
                var place = List[Float64]()
                for _ in range(12):  # pragma: no branch
                    place.append(js_parse_float(lp.token()))
                # three.js's `set( m0, m1, m2, x, m3, ... )`, row by row,
                # stored by column.
                var matrix: List[Float64] = [
                    place[3],
                    place[6],
                    place[9],
                    0,
                    place[4],
                    place[7],
                    place[10],
                    0,
                    place[5],
                    place[8],
                    place[11],
                    0,
                    place[0],
                    place[1],
                    place[2],
                    1,
                ]
                var name = String(lp.rest().strip()).replace("\\", "/")
                var mapped = False
                for k in range(len(self.file_map_names)):
                    if not mapped and self.file_map_names[k] == name:
                        if self.file_map_files[k].byte_length() > 0:
                            name = self.file_map_files[k]
                            mapped = True
                if not mapped:
                    if name.startswith("s/"):
                        name = "parts/" + name
                    elif name.startswith("48/"):
                        name = "p/" + name
                info.subobjects.append(
                    LDrawSubobject(
                        material, code, matrix^, name, inverted, step
                    )
                )
                step = False
                inverted = False
            elif kind == "2" or kind == "5":
                var code = lp.token()
                var material = info.local(code)
                var v0 = lp.vector()
                var v1 = lp.vector()
                if kind == "2":
                    info.line_segments.append(
                        LDrawSegment(code, material, [v0, v1], List[Vec]())
                    )
                else:
                    var c0 = lp.vector()
                    var c1 = lp.vector()
                    info.conditional_segments.append(
                        LDrawSegment(code, material, [v0, v1], [c0, c1])
                    )
            elif kind == "3" or kind == "4":
                var code = lp.token()
                var material = info.local(code)
                var double_sided = not certified or not cull
                var corners = 3 if kind == "3" else 4
                var vertices = List[Vec]()
                for _ in range(corners):  # pragma: no branch
                    vertices.append(lp.vector())
                if not ccw:
                    vertices.reverse()
                var back = vertices.copy()
                back.reverse()
                info.faces.append(LDrawFace(code, material, vertices^))
                info.total_faces += corners - 2
                if double_sided:
                    info.faces.append(LDrawFace(code, material, back^))
                    info.total_faces += corners - 2
            else:
                raise Error(
                    'LDrawLoader: Unknown line type "'
                    + kind
                    + '"'
                    + lp.where()
                    + "."
                )
        if embedded:
            self.set_data(embedded_name, embedded_text)
        info.starting_building_step = step
        return info^

    def data(self, name: String) -> LDrawInfo:
        """Port three.js's `getData( name )`: a copy of a read file, with its
        normals cleared.

        Args:
            name: The file's name; it must have been read.

        Returns:
            The copy.
        """
        var out = self.cache[self.cached(name)].copy()
        for f in range(len(out.faces)):
            for k in range(len(out.faces[f].normals)):  # pragma: no branch
                out.faces[f].normals[k] = -1
            out.faces[f].has_face_normal = False
        return out^


def _luminance(token: String) -> Float64:
    """Port three.js's `parseLuminance`: a number, after `LUMINANCE` or alone,
    over 255 and clamped; NaN when it is not a number."""
    var value: Float64
    if token.startswith("LUMINANCE"):
        value = js_parse_int(String(token[byte=9:]))
    else:
        value = js_parse_int(token)
    if _is_nan(value):
        return value
    return max(0.0, min(1.0, value / 255))
