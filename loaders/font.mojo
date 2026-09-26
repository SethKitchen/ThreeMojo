# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fonts in the typeface.js JSON format, and text laid out as shapes, from
three.js `examples/jsm/loaders/FontLoader.js`.

A typeface.js font is a JSON object. `resolution` is how many font units
make one em. `boundingBox` and `underlineThickness` set the distance from
one line to the next. `glyphs` maps each character to its advance, `ha`,
and its outline, `o`: a string of commands with their numbers, in font
units.

| Command | Numbers | Draws |
|---|---|---|
| `m x y` | 2 | A new outline, starting at the point. |
| `l x y` | 2 | A straight run to the point. |
| `q x y cx cy` | 4 | A Bezier curve to `x y`, pulled toward `cx cy`. |
| `b x y c1x c1y c2x c2y` | 6 | A Bezier curve to `x y` with two control points. |

The end point comes first and the control points after it. That is the
order the file holds them in, and three.js's `createPath` reads them so.
An `OutlineStep` holds them in drawing order, the end point last.

## Layout

`Font.generate_shapes(text, size)` is three.js's `generateShapes`. One
font unit is `size / resolution` meters. The glyphs run left to right
from the origin, each moved on by the advance of the glyph before it. A
line break, `\\n`, moves back to x zero and down by the line height:

    (boundingBox.yMax - boundingBox.yMin + underlineThickness) * scale

A character the font has no glyph for takes the glyph for `?`, as in
three.js. Each glyph's outlines go into one `ShapePath`, and
`ShapePath.to_shapes` sorts them into shapes with holes.

## What is refused

The file is checked when it is read, and not when the text is laid out.
three.js reads it lazily and skips what it does not understand, which
turns a bad command into a letter drawn from the wrong numbers. So these
are refused, each with the glyph it is in:

- A missing or non-positive `resolution`. A missing `boundingBox.yMin`,
  `boundingBox.yMax` or `underlineThickness`. No `glyphs` object.
- A glyph key that is not one character. A glyph with no `ha`.
- An outline command other than `m`, `l`, `q` and `b`. A command with too
  few numbers after it. A number that is not a finite `Float32`.
- An outline that draws before its first `m`, or moves and draws nothing
  before the next `m` or the end.
- A text with a character that has no glyph, in a font with no `?`.

A step that draws nothing, such as a line to where the pen already is,
is skipped. three.js keeps it, and its `getPoints` then drops the repeated
point, so the shape is the same.
"""

from loaders.json import NO_NODE, OBJECT, STRING, JsonDocument, parse_json
from math.path import Shape
from math.shape_path import ShapePath
from math.vector2 import Vector2
from std.collections import Dict
from std.math import isfinite
from std.pathlib import Path
from units.si import Length, METER


@fieldwise_init
struct OutlineVerb(Equatable, ImplicitlyCopyable, Writable):
    """Which command an outline step is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four commands there are."""
        return (
            self == MOVE_TO
            or self == LINE_TO
            or self == QUADRATIC_TO
            or self == CUBIC_TO
        )

    def point_count(self) -> Int:
        """Return how many points the command carries: its control points
        and its end.

        Returns:
            One for a move or a line, two for a quadratic curve, three for a
            cubic one, and zero for a verb that is not valid.
        """
        if self == MOVE_TO or self == LINE_TO:
            return 1
        if self == QUADRATIC_TO:
            return 2
        if self == CUBIC_TO:
            return 3
        return 0


comptime MOVE_TO = OutlineVerb(0)
comptime LINE_TO = OutlineVerb(1)
comptime QUADRATIC_TO = OutlineVerb(2)
comptime CUBIC_TO = OutlineVerb(3)


struct OutlineStep(Copyable, Movable):
    """One command of a glyph's outline, its points in font units."""

    var verb: OutlineVerb
    # The control points, then the end: x, y, x, y, in font units.
    var coordinates: List[Float32]

    def __init__(
        out self, verb: OutlineVerb, var coordinates: List[Float32]
    ) raises:
        """Create a step.

        Args:
            verb: The command.
            coordinates: The control points first and the end point last,
                two numbers each, in font units.

        Raises:
            Error: If the verb is not one of the four, or the count of
                numbers does not match it.
        """
        if not verb.is_valid():
            raise Error("Font: an outline step has an unknown command")
        if len(coordinates) != verb.point_count() * 2:
            raise Error("Font: an outline step has the wrong count of numbers")
        self.verb = verb
        self.coordinates = coordinates^

    def __init__(out self, *, copy: Self):
        """Copy another step."""
        self.verb = copy.verb
        self.coordinates = copy.coordinates.copy()

    def point(self, index: Int) -> Vector2:
        """Return one of the step's points, in font units.

        Args:
            index: Which point, from zero; the last is the end.

        Returns:
            The point.
        """
        return Vector2(
            self.coordinates[index * 2], self.coordinates[index * 2 + 1]
        )


struct Glyph(Copyable, Movable):
    """One character of a font: how far it moves the pen on, and its
    outline."""

    var advance: Float32
    var steps: List[OutlineStep]

    def __init__(
        out self, advance: Float32, var steps: List[OutlineStep]
    ) raises:
        """Create a glyph.

        Args:
            advance: How far the next glyph starts to the right, in font
                units. three.js's `ha`.
            steps: The outline, command by command. No steps is a glyph
                that draws nothing, such as a space.

        Raises:
            Error: If the advance is not finite, the outline draws before
                it moves, or a move draws nothing before the next move or
                the end.
        """
        if not isfinite(advance):
            raise Error("its advance is not finite")
        var drawn = True
        for index in range(len(steps)):
            if steps[index].verb == MOVE_TO:
                if not drawn:
                    raise Error("an outline moves and draws nothing")
                drawn = False
            elif index == 0:
                raise Error("an outline draws before it moves")
            else:
                drawn = True
        if not drawn:
            raise Error("an outline moves and draws nothing")
        self.advance = advance
        self.steps = steps^

    def __init__(out self, *, copy: Self):
        """Copy another glyph."""
        self.advance = copy.advance
        self.steps = copy.steps.copy()


def _token_number(tokens: List[String], at: Int) raises -> Float32:
    """Return one number of an outline as a finite `Float32`.

    Raises:
        Error: If there is no token at `at`, or it is not a number, or it
            is not finite as a `Float32`.
    """
    if at >= len(tokens):
        raise Error("a command has too few numbers")
    var wide: Float64
    try:
        wide = Float64(tokens[at])
    except:
        raise Error("'" + tokens[at] + "' is not a number")
    var narrow = Float32(wide)
    if not isfinite(narrow):
        raise Error("'" + tokens[at] + "' is not finite")
    return narrow


def parse_outline(outline: String) raises -> List[OutlineStep]:
    """Read a glyph's `o` string into steps.

    The commands are read and their numbers counted. Whether the steps
    make outlines is checked by `Glyph`.

    Args:
        outline: The commands and their numbers, separated by white space.
            An empty outline, a space's, is no steps.

    Returns:
        The steps, each with its points in drawing order.

    Raises:
        Error: If a command is not `m`, `l`, `q`, `b` or `z`, has too few
            numbers, or has a number that is not a finite `Float32`. A
            `z`, which three.js's `TTFLoader` writes to close a contour,
            is stepped over, as three.js's `Font` steps over it.
    """
    var tokens = List[String]()
    for token in outline.split():
        tokens.append(String(token))
    var steps = List[OutlineStep]()
    var at = 0
    while at < len(tokens):
        var command = tokens[at]
        if command == "z":
            at += 1
            continue
        var verb: OutlineVerb
        if command == "m":
            verb = MOVE_TO
        elif command == "l":
            verb = LINE_TO
        elif command == "q":
            verb = QUADRATIC_TO
        elif command == "b":
            verb = CUBIC_TO
        else:
            raise Error("unknown command '" + command + "'")
        var numbers = List[Float32]()
        for index in range(verb.point_count() * 2):  # pragma: no branch
            numbers.append(_token_number(tokens, at + 1 + index))
        at += 1 + len(numbers)
        # The file puts the end first; a step keeps it last.
        var ordered = List[Float32]()
        for index in range(2, len(numbers)):
            ordered.append(numbers[index])
        ordered.append(numbers[0])
        ordered.append(numbers[1])
        steps.append(OutlineStep(verb, ordered^))
    return steps^


def _field(
    document: JsonDocument, node: Int, key: String, owner: String
) raises -> Float64:
    """Return a number an object must have.

    Raises:
        Error: If the key is missing or does not hold a number.
    """
    var child = document.get(node, key)
    if child == NO_NODE:
        raise Error("Font: " + owner + " has no '" + key + "'")
    return document.number(child)


def _object(
    document: JsonDocument, node: Int, key: String, owner: String
) raises -> Int:
    """Return the object an object must hold under a key.

    Raises:
        Error: If the key is missing or does not hold an object.
    """
    var child = document.get(node, key)
    if child == NO_NODE:
        raise Error("Font: " + owner + " has no '" + key + "'")
    if document.kind(child) != OBJECT:
        raise Error("Font: '" + key + "' must be an object")
    return child


def _one_character(key: String) -> Bool:
    """Return True if a string is exactly one code point."""
    var count = 0
    for _ in key.codepoints():
        count += 1
    return count == 1


struct Font(Movable):
    """A typeface.js font: its metrics and its glyphs, three.js's `Font`."""

    var family_name: String
    var resolution: Float32
    var y_min: Float32
    var y_max: Float32
    var underline_thickness: Float32
    var glyphs: Dict[String, Glyph]

    def __init__(
        out self,
        family_name: String,
        resolution: Float32,
        y_min: Float32,
        y_max: Float32,
        underline_thickness: Float32,
        var glyphs: Dict[String, Glyph],
    ) raises:
        """Create a font from its parts.

        Args:
            family_name: The font's name, for error messages.
            resolution: How many font units make one em; positive.
            y_min: The lowest point of any glyph, in font units.
            y_max: The highest point of any glyph, in font units.
            underline_thickness: The underline's thickness, in font units.
            glyphs: Every glyph, keyed by its one character.

        Raises:
            Error: If the resolution is not positive and finite, a metric
                is not finite, or a key is not one character.
        """
        if not isfinite(resolution) or resolution <= 0:
            raise Error("Font: the resolution must be positive")
        if not isfinite(y_min) or not isfinite(y_max):
            raise Error("Font: the bounding box must be finite")
        if not isfinite(underline_thickness):
            raise Error("Font: the underline thickness must be finite")
        for key in glyphs.keys():
            if not _one_character(key):
                raise Error(
                    "Font: the glyph key '" + key + "' is not one character"
                )
        self.family_name = family_name
        self.resolution = resolution
        self.y_min = y_min
        self.y_max = y_max
        self.underline_thickness = underline_thickness
        self.glyphs = glyphs^

    def glyph_count(self) -> Int:
        """Return how many glyphs the font has."""
        return len(self.glyphs)

    def has_glyph(self, character: String) -> Bool:
        """Return True if the font draws `character` itself.

        Args:
            character: One character.

        Returns:
            Whether the font has a glyph for it, not counting `?`.
        """
        return character in self.glyphs

    def glyph(self, character: String) raises -> Glyph:
        """Return the glyph that draws `character`, or `?` when the font
        has none for it, as three.js's `createPath` does.

        Args:
            character: One character.

        Returns:
            A copy of the glyph.

        Raises:
            Error: If the font has neither the character nor `?`.
        """
        if character in self.glyphs:
            return self.glyphs[character].copy()
        if "?" in self.glyphs:
            return self.glyphs["?"].copy()
        raise Error(
            "Font: the character '"
            + character
            + "' does not exist in font family "
            + self.family_name
        )

    def line_height(self, size: Length) -> Length:
        """Return how far a line break moves down, three.js's
        `line_height`.

        Args:
            size: The size the text is laid out at: one em.

        Returns:
            `(y_max - y_min + underline_thickness) * size / resolution`.
        """
        var scale = size.to(METER) / self.resolution
        return Length(
            (self.y_max - self.y_min + self.underline_thickness) * scale, METER
        )

    def generate_paths(
        self, text: String, size: Length
    ) raises -> List[ShapePath]:
        """Return one `ShapePath` per character of `text` that is not a
        line break, laid out as three.js's `createPaths` lays them.

        The layout is worked in `Float64`, as three.js works it, and each
        point is narrowed to `Float32` once it is placed. A long line then
        drifts no more than one glyph does.

        Args:
            text: The text. `\\n` starts a new line.
            size: One em; positive.

        Returns:
            The paths, in meters, in the order of the characters.

        Raises:
            Error: If the size is not positive and finite, or a character
                has no glyph and the font has no `?`.
        """
        var em = Float64(size.to(METER))
        if not isfinite(em) or em <= 0:
            raise Error("Font: a text size must be positive")
        var scale = em / Float64(self.resolution)
        var line = (
            Float64(self.y_max)
            - Float64(self.y_min)
            + Float64(self.underline_thickness)
        ) * scale
        var paths = List[ShapePath]()
        var offset_x = Float64(0)
        var offset_y = Float64(0)
        for piece in text.codepoint_slices():
            var character = String(piece)
            if character == "\n":
                offset_x = 0
                offset_y -= line
                continue
            var glyph = self.glyph(character)
            paths.append(_glyph_path(glyph, scale, offset_x, offset_y))
            offset_x += Float64(glyph.advance) * scale
        return paths^

    def generate_shapes(
        self, text: String, size: Length = Length(100, METER)
    ) raises -> List[Shape]:
        """Return `text` as shapes with holes, three.js's
        `generateShapes`.

        Args:
            text: The text. `\\n` starts a new line.
            size: One em; positive. three.js's default is 100.

        Returns:
            Every glyph's shapes, glyph after glyph, in meters. A space
            has an advance and no shapes.

        Raises:
            Error: If `generate_paths` raises, or an outline cannot be made
                a shape; see `ShapePath.to_shapes`.
        """
        var paths = self.generate_paths(text, size)
        var shapes = List[Shape]()
        for index in range(len(paths)):
            shapes.extend(paths[index].to_shapes())
        return shapes^


def _same(first: Vector2, second: Vector2) -> Bool:
    """Return True if two points are the same point."""
    return first.x == second.x and first.y == second.y


def _glyph_path(
    glyph: Glyph, scale: Float64, offset_x: Float64, offset_y: Float64
) raises -> ShapePath:
    """Return a glyph's outline scaled to meters and moved to its place,
    three.js's `createPath`.

    A step that draws nothing -- a line to where the pen is, a curve whose
    points are all there -- is skipped. three.js keeps it, and its
    `getPoints` drops the repeated point, so the shape is the same. A
    `Glyph` starts with a move, so the pen is down before it is compared.

    Raises:
        Error: Never; a `Glyph` has already checked its outline.
    """
    var path = ShapePath()
    var pen = Vector2(0, 0)
    for index in range(len(glyph.steps)):
        ref step = glyph.steps[index]
        var points = List[Vector2]()
        var still = True
        for which in range(step.verb.point_count()):  # pragma: no branch
            var raw = step.point(which)
            var placed = Vector2(
                Float32(Float64(raw.x) * scale + offset_x),
                Float32(Float64(raw.y) * scale + offset_y),
            )
            if not _same(placed, pen):
                still = False
            points.append(placed)
        if step.verb == MOVE_TO:
            path.move_to(points[0])
        elif still:
            continue
        elif step.verb == LINE_TO:
            path.line_to(points[0])
        elif step.verb == QUADRATIC_TO:
            path.quadratic_curve_to(points[0], points[1])
        else:
            path.bezier_curve_to(points[0], points[1], points[2])
        pen = points[len(points) - 1]
    return path^


def parse_font(text: String) raises -> Font:
    """Read the text of a typeface.js font, three.js's `FontLoader.parse`.

    Args:
        text: The whole JSON text.

    Returns:
        The font, every outline read and checked.

    Raises:
        Error: If the text is not JSON, the root is not an object, a
            metric or `glyphs` is missing or of the wrong kind, the
            resolution is not positive, a glyph key is not one character,
            a glyph has no `ha`, or an outline is refused by
            `parse_outline`.
    """
    var document = parse_json(text)
    var root = document.root()
    if document.kind(root) != OBJECT:
        raise Error("Font: the file must hold a JSON object")
    var family = String()
    var named = document.get(root, "familyName")
    if named != NO_NODE:
        family = document.string(named)
    var resolution = _field(document, root, "resolution", "the font")
    var box = _object(document, root, "boundingBox", "the font")
    var y_min = _field(document, box, "yMin", "the bounding box")
    var y_max = _field(document, box, "yMax", "the bounding box")
    var underline = _field(document, root, "underlineThickness", "the font")
    var table = _object(document, root, "glyphs", "the font")

    var glyphs = Dict[String, Glyph]()
    for index in range(document.length(table)):
        var key = document.key(table, index)
        var entry = document.at(table, index)
        if document.kind(entry) != OBJECT:
            raise Error("Font: glyph '" + key + "' must be an object")
        var advance = _field(document, entry, "ha", "glyph '" + key + "'")
        var outline = document.get(entry, "o")
        try:
            var steps = List[OutlineStep]()
            if outline != NO_NODE:
                if document.kind(outline) != STRING:
                    raise Error("'o' must be a string")
                steps = parse_outline(document.string(outline))
            glyphs[key] = Glyph(Float32(advance), steps^)
        except reason:
            raise Error("Font: glyph '" + key + "': " + String(reason))
    return Font(
        family,
        Float32(resolution),
        Float32(y_min),
        Float32(y_max),
        Float32(underline),
        glyphs^,
    )


def read_font(path: String) raises -> Font:
    """Read a typeface.js font file, three.js's `FontLoader.load`.

    Args:
        path: The file to read.

    Returns:
        The font; see `parse_font`.

    Raises:
        Error: If the file cannot be read, or for anything `parse_font`
            refuses.
    """
    return parse_font(Path(path).read_text())
