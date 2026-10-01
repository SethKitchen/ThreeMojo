# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a face shows: expressions, and the mouth's shapes in speech.

A rigged head carries one morph target per shape of the face model: the
ARKit blend shapes, as `jawOpen`, `mouthSmile_L` or `browDown_R`. A
`FacialExpression` and a `Viseme` are each a recipe of those shapes.

- An expression follows the Facial Action Coding System (Ekman and
  Friesen 1978): a smile raises the mouth's corners (action unit 12) and
  the cheeks (6), a frown lowers the brows (4) and the corners (15).
- A viseme is the shape the mouth takes for a group of sounds that
  look alike, after the fifteen of the Oculus Lipsync set: the lips
  pressed for p, b and m, the lower lip under the teeth for f and v,
  and the jaw and the lips' rounding for each vowel.

`FaceWeights` sums any of them and puts the sum on a mesh. Expressions
and speech add, so a face can smile while it talks.

This is not a three.js port. See Extensions.

    var face = FaceWeights()
    face.add_expression(SMILE, 0.8)
    face.add_viseme(OH, 1.0)
    face.apply(scene.meshes[skin])
"""

from objects.mesh import Mesh


@fieldwise_init
struct FacialExpression(Equatable, ImplicitlyCopyable, Writable):
    """An emotion the face shows.

    The type stops a bare integer at compile time. A value that is not a
    named expression is still constructible, and the boundary that reads
    it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named expression."""
        return self.value >= 0 and self.value <= FEAR.value


comptime NEUTRAL = FacialExpression(0)
comptime SMILE = FacialExpression(1)
comptime FROWN = FacialExpression(2)
comptime SADNESS = FacialExpression(3)
comptime SURPRISE = FacialExpression(4)
comptime ANGER = FacialExpression(5)
comptime DISGUST = FacialExpression(6)
comptime FEAR = FacialExpression(7)


@fieldwise_init
struct Viseme(Equatable, ImplicitlyCopyable, Writable):
    """The shape of the mouth for a group of sounds that look alike.

    The type stops a bare integer at compile time. A value that is not a
    named viseme is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named viseme."""
        return self.value >= 0 and self.value <= OU.value


# Silence: the mouth at rest.
comptime SILENT = Viseme(0)
# p, b, m: the lips pressed together.
comptime PP = Viseme(1)
# f, v: the lower lip under the upper teeth.
comptime FF = Viseme(2)
# th: the tongue between the teeth, the jaw a little open.
comptime TH = Viseme(3)
# t, d: the tongue on the ridge behind the teeth.
comptime DD = Viseme(4)
# k, g: the back of the tongue raised, the jaw open.
comptime KK = Viseme(5)
# ch, j, sh: the lips pushed forward.
comptime CH = Viseme(6)
# s, z: the teeth near together, the lips drawn back.
comptime SS = Viseme(7)
# n, l: the tongue up, the jaw a little open.
comptime NN = Viseme(8)
# r: the lips a little rounded.
comptime RR = Viseme(9)
# a, as in "father": the jaw wide open.
comptime AA = Viseme(10)
# e, as in "bed": the jaw half open, the lips drawn back.
comptime E = Viseme(11)
# i, as in "see": the lips spread, the jaw nearly closed.
comptime IH = Viseme(12)
# o, as in "go": the lips rounded, the jaw open.
comptime OH = Viseme(13)
# u and w, as in "you": the lips rounded and pushed forward.
comptime OU = Viseme(14)


def facial_expression_label(expression: FacialExpression) -> String:
    """Return the name of `expression` for error text and tables.

    Args:
        expression: An expression, named or not.

    Returns:
        Its name in lower case, or `"facial expression"` when it is not
        named.
    """
    var names: List[String] = [
        "neutral",
        "smile",
        "frown",
        "sadness",
        "surprise",
        "anger",
        "disgust",
        "fear",
    ]
    if not expression.is_valid():
        return "facial expression"
    return names[expression.value]


def named_facial_expressions() -> List[FacialExpression]:
    """Return every named expression in a stable order.

    Returns:
        `NEUTRAL` through `FEAR`.
    """
    var all = List[FacialExpression]()
    for value in range(FEAR.value + 1):  # pragma: no branch
        all.append(FacialExpression(value))
    return all^


def viseme_label(viseme: Viseme) -> String:
    """Return the name of `viseme` for error text and tables.

    Args:
        viseme: A viseme, named or not.

    Returns:
        Its Oculus name, as `"PP"` or `"aa"`, or `"viseme"` when it is
        not named.
    """
    var names: List[String] = [
        "sil",
        "PP",
        "FF",
        "TH",
        "DD",
        "kk",
        "CH",
        "SS",
        "nn",
        "RR",
        "aa",
        "E",
        "ih",
        "oh",
        "ou",
    ]
    if not viseme.is_valid():
        return "viseme"
    return names[viseme.value]


def named_visemes() -> List[Viseme]:
    """Return every named viseme in a stable order.

    Returns:
        `SILENT` through `OU`.
    """
    var all = List[Viseme]()
    for value in range(OU.value + 1):  # pragma: no branch
        all.append(Viseme(value))
    return all^


@fieldwise_init
struct ShapeWeight(Copyable, Movable):
    """One blend shape of the face model and how much of it."""

    var shape: String
    var weight: Float32


def _both(mut recipe: List[ShapeWeight], shape: String, weight: Float32):
    """Add a shape on both sides of the face: `shape` with `_L` and
    `_R`."""
    recipe.append(ShapeWeight(shape + "_L", weight))
    recipe.append(ShapeWeight(shape + "_R", weight))


def expression_recipe(
    expression: FacialExpression,
) raises -> List[ShapeWeight]:
    """Return the blend shapes that make an expression, at full strength.

    Args:
        expression: A named expression.

    Returns:
        The shapes and their weights. `NEUTRAL` has none.

    Raises:
        Error: If `expression` is not named.
    """
    if not expression.is_valid():
        raise Error("A facial expression must be a named expression")
    var r = List[ShapeWeight]()
    if expression == SMILE:
        # Action units 6 and 12: the cheeks raised and the corners of
        # the mouth drawn up, which narrows the eyes a little.
        _both(r, "mouthSmile", 0.85)
        _both(r, "cheekSquint", 0.45)
        _both(r, "cheekRaiser", 0.5)
        _both(r, "eyeSquint", 0.25)
        _both(r, "mouthDimple", 0.2)
    elif expression == FROWN:
        # Action units 4 and 15: the brows drawn down and together, the
        # corners of the mouth pulled down, the lips pressed.
        _both(r, "browDown", 0.75)
        _both(r, "mouthFrown", 0.8)
        _both(r, "mouthPress", 0.35)
        r.append(ShapeWeight("mouthShrugLower", 0.25))
    elif expression == SADNESS:
        # Action units 1, 4 and 15: the inner brows raised, the corners
        # of the mouth down, the chin pushed up.
        _both(r, "browInnerUp", 0.85)
        _both(r, "mouthFrown", 0.6)
        r.append(ShapeWeight("mouthShrugLower", 0.45))
        _both(r, "eyeBlink", 0.15)
    elif expression == SURPRISE:
        # Action units 1, 2, 5 and 26: the brows up, the eyes wide, the
        # jaw dropped.
        _both(r, "browInnerUp", 0.8)
        _both(r, "browOuterUp", 0.8)
        _both(r, "eyeWide", 0.6)
        r.append(ShapeWeight("jawOpen", 0.35))
        r.append(ShapeWeight("mouthFunnel", 0.15))
    elif expression == ANGER:
        # Action units 4, 5, 7 and 23: the brows down, the eyes narrowed
        # and staring, the lips pressed hard.
        _both(r, "browDown", 0.9)
        _both(r, "eyeSquint", 0.45)
        _both(r, "noseSneer", 0.3)
        _both(r, "mouthPress", 0.6)
        r.append(ShapeWeight("jawForward", 0.1))
    elif expression == DISGUST:
        # Action units 9 and 10: the nose wrinkled and the upper lip
        # raised.
        _both(r, "noseSneer", 0.8)
        _both(r, "mouthUpperUp", 0.55)
        _both(r, "browDown", 0.4)
        _both(r, "cheekSquint", 0.3)
        _both(r, "mouthFrown", 0.3)
    elif expression == FEAR:
        # Action units 1, 2, 4, 5 and 20: the brows up and drawn
        # together, the eyes wide, the lips stretched sideways.
        _both(r, "browInnerUp", 0.85)
        _both(r, "browOuterUp", 0.4)
        _both(r, "eyeWide", 0.8)
        _both(r, "mouthStretch", 0.6)
        r.append(ShapeWeight("jawOpen", 0.15))
    return r^


def viseme_recipe(viseme: Viseme) raises -> List[ShapeWeight]:
    """Return the blend shapes that make a viseme, at full strength.

    The face model has no tongue shapes, so the visemes the tongue makes
    show as the jaw and the lips do.

    Args:
        viseme: A named viseme.

    Returns:
        The shapes and their weights. `SILENT` has none.

    Raises:
        Error: If `viseme` is not named.
    """
    if not viseme.is_valid():
        raise Error("A viseme must be a named viseme")
    var r = List[ShapeWeight]()
    if viseme == PP:
        _both(r, "mouthPress", 0.7)
        r.append(ShapeWeight("mouthRollLower", 0.3))
        r.append(ShapeWeight("mouthRollUpper", 0.2))
    elif viseme == FF:
        r.append(ShapeWeight("mouthRollLower", 0.65))
        _both(r, "mouthUpperUp", 0.3)
        r.append(ShapeWeight("jawOpen", 0.08))
    elif viseme == TH:
        r.append(ShapeWeight("jawOpen", 0.16))
        _both(r, "mouthStretch", 0.1)
    elif viseme == DD:
        r.append(ShapeWeight("jawOpen", 0.2))
        _both(r, "mouthStretch", 0.15)
    elif viseme == KK:
        r.append(ShapeWeight("jawOpen", 0.26))
        _both(r, "mouthStretch", 0.15)
    elif viseme == CH:
        r.append(ShapeWeight("mouthFunnel", 0.5))
        r.append(ShapeWeight("mouthPucker", 0.25))
        r.append(ShapeWeight("jawOpen", 0.15))
    elif viseme == SS:
        r.append(ShapeWeight("jawOpen", 0.08))
        _both(r, "mouthStretch", 0.35)
        _both(r, "mouthSmile", 0.15)
    elif viseme == NN:
        r.append(ShapeWeight("jawOpen", 0.18))
        _both(r, "mouthStretch", 0.1)
    elif viseme == RR:
        r.append(ShapeWeight("mouthFunnel", 0.35))
        r.append(ShapeWeight("mouthPucker", 0.25))
        r.append(ShapeWeight("jawOpen", 0.12))
    elif viseme == AA:
        r.append(ShapeWeight("jawOpen", 0.55))
        _both(r, "mouthLowerDown", 0.25)
    elif viseme == E:
        r.append(ShapeWeight("jawOpen", 0.3))
        _both(r, "mouthStretch", 0.4)
        _both(r, "mouthSmile", 0.2)
    elif viseme == IH:
        r.append(ShapeWeight("jawOpen", 0.18))
        _both(r, "mouthStretch", 0.45)
        _both(r, "mouthSmile", 0.25)
    elif viseme == OH:
        r.append(ShapeWeight("jawOpen", 0.4))
        r.append(ShapeWeight("mouthFunnel", 0.55))
    elif viseme == OU:
        r.append(ShapeWeight("mouthPucker", 0.8))
        r.append(ShapeWeight("mouthFunnel", 0.3))
        r.append(ShapeWeight("jawOpen", 0.12))
    return r^


def face_rig_shapes() raises -> List[String]:
    """Return every blend shape the expressions, the visemes and a blink
    use: the shapes a head must be rigged with to show them all.

    Returns:
        Each shape's name once, in the order it is first used.

    Raises:
        Error: Never, for the named expressions and visemes.
    """
    var shapes: List[String] = ["eyeBlink_L", "eyeBlink_R"]
    var recipes = List[List[ShapeWeight]]()
    for expression in named_facial_expressions():  # pragma: no branch
        recipes.append(expression_recipe(expression))
    for viseme in named_visemes():  # pragma: no branch
        recipes.append(viseme_recipe(viseme))
    for recipe in recipes:  # pragma: no branch
        for item in recipe:  # pragma: no branch
            if item.shape not in shapes:
                shapes.append(item.shape)
    return shapes^


struct FaceWeights(Copyable, Movable):
    """How much of each rigged blend shape a face wears."""

    var shapes: List[String]
    var weights: List[Float32]

    def __init__(out self) raises:
        """Start a face at rest, over every shape `face_rig_shapes`
        names.

        Raises:
            Error: Never, for the named expressions and visemes.
        """
        self.shapes = face_rig_shapes()
        self.weights = List[Float32](length=len(self.shapes), fill=0)

    def get(self, shape: String) -> Float32:
        """Return how much of one shape the face wears.

        Args:
            shape: The shape's name.

        Returns:
            Its weight, zero for a shape the face does not carry.
        """
        for k in range(len(self.shapes)):  # pragma: no branch
            if self.shapes[k] == shape:
                return self.weights[k]
        return 0

    def add(mut self, shape: String, weight: Float32) raises:
        """Add some of one shape.

        Args:
            shape: The shape's name.
            weight: How much more of it.

        Raises:
            Error: If the face does not carry the shape.
        """
        for k in range(len(self.shapes)):  # pragma: no branch
            if self.shapes[k] == shape:
                self.weights[k] += weight
                return
        raise Error("The face carries no shape named " + shape)

    def add_expression(
        mut self, expression: FacialExpression, amount: Float32 = 1
    ) raises:
        """Add an expression.

        Args:
            expression: A named expression.
            amount: How strongly, one for its full strength.

        Raises:
            Error: If `expression` is not named.
        """
        for item in expression_recipe(expression):  # pragma: no branch
            self.add(item.shape, item.weight * amount)

    def add_viseme(mut self, viseme: Viseme, amount: Float32 = 1) raises:
        """Add the mouth's shape for a sound.

        Args:
            viseme: A named viseme.
            amount: How strongly, one for its full strength.

        Raises:
            Error: If `viseme` is not named.
        """
        for item in viseme_recipe(viseme):  # pragma: no branch
            self.add(item.shape, item.weight * amount)

    def blink(mut self, amount: Float32) raises:
        """Close both eyes by `amount`: one shut, zero as at rest.

        Args:
            amount: How far.

        Raises:
            Error: Never, since the face carries the blinks.
        """
        self.add("eyeBlink_L", amount)
        self.add("eyeBlink_R", amount)

    def clear(mut self):
        """Put the face back at rest."""
        for k in range(len(self.weights)):  # pragma: no branch
            self.weights[k] = 0

    def apply(self, mut mesh: Mesh) raises:
        """Put the face's weights on a rigged mesh, one morph influence
        per shape. Each weight is held to zero through one, so shapes
        that add never overshoot.

        Args:
            mesh: A mesh whose geometry is rigged with every shape this
                face carries; see `add_head`'s `face_shapes`.

        Raises:
            Error: If the mesh has no target of one of the shapes.
        """
        for k in range(len(self.shapes)):  # pragma: no branch
            mesh.set_morph_influence(
                self.shapes[k],
                min(Float32(1), max(Float32(0), self.weights[k])),
            )
