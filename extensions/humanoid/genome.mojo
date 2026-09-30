# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The heritable traits of a humanoid: skin, hair, eyes, face and frame.

A `Genome` holds one `Expression` for each `Gene`. An expression is a
dimensionless value from -1 through 1. Zero is the template: a genome
of zeros makes the same body as a spec without a genome. The sign says
which way the trait moves. `MELANIN` at -1 is very fair skin, and at
1 it is very dark skin. `NOSE_LENGTH` at 1 is a long nose.

    var genome = Genome().with_gene(MELANIN, Expression(0.6))
    var person = HumanoidSpec(Length(6.0, FOOT), FEMALE, UNTONED, genome)

The genes are authored controls. They are not a model of the loci that
set the traits in people. Many small genes set each of these traits,
and development and environment change them too.
"""

from std.math import isfinite

# How many genes a genome holds.
comptime GENE_COUNT = 34


@fieldwise_init
struct Gene(Equatable, ImplicitlyCopyable, Writable):
    """Which trait an expression sets.

    The type stops a bare integer at compile time. A value that is not a
    named gene is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is a named gene."""
        return self.value >= 0 and self.value < GENE_COUNT


# Skin. Eumelanin in the epidermis: -1 is very fair, 1 is very dark.
comptime MELANIN = Gene(0)
# The skin's undertone: -1 is cool and pink, 1 is warm and olive.
comptime UNDERTONE = Gene(1)
# How many freckles and moles the skin has: -1 is none, 1 is many.
comptime FRECKLES = Gene(2)
# Hair. Eumelanin in the shaft: -1 is blond, 1 is black.
comptime HAIR_MELANIN = Gene(3)
# Pheomelanin in the shaft: 1 is red or auburn.
comptime HAIR_REDNESS = Gene(4)
# Eyes. Melanin in the iris stroma: -1 is blue, 0 is hazel, 1 is brown.
comptime IRIS_MELANIN = Gene(5)
# The size of the eyeball and the eye opening.
comptime EYE_SIZE = Gene(6)
# How far apart the eyes are.
comptime EYE_SPACING = Gene(7)
# The canthal tilt: 1 lifts the outer corners.
comptime EYE_TILT = Gene(8)
# How deep the eyes sit: 1 is deep-set, -1 is prominent.
comptime EYE_DEPTH = Gene(9)
# Eyebrows. How high the brows sit over the eyes.
comptime BROW_HEIGHT = Gene(10)
# How thick and full the eyebrows are.
comptime BROW_THICKNESS = Gene(11)
# How much the eyebrows arch.
comptime BROW_ARCH = Gene(12)
# Nose. From the root to the tip.
comptime NOSE_LENGTH = Gene(13)
# Across the wings.
comptime NOSE_WIDTH = Gene(14)
# How far the tip stands out from the face.
comptime NOSE_PROJECTION = Gene(15)
# How high the bridge stands between the eyes.
comptime NOSE_BRIDGE = Gene(16)
# Mouth. From corner to corner.
comptime MOUTH_WIDTH = Gene(17)
# How full the lips are.
comptime LIP_FULLNESS = Gene(18)
# Ears. The size of the auricle.
comptime EAR_SIZE = Gene(19)
# How far the ears stand out from the head.
comptime EAR_PROTRUSION = Gene(20)
# The lobe: -1 is attached, 1 is large and free.
comptime EAR_LOBE = Gene(21)
# Head shape. The breadth of the cranium.
comptime HEAD_WIDTH = Gene(22)
# The length of the cranium, front to back.
comptime HEAD_LENGTH = Gene(23)
# The height of the vault above the ears.
comptime HEAD_HEIGHT = Gene(24)
# The breadth of the mandible at its angles.
comptime JAW_WIDTH = Gene(25)
# How far the chin stands forward and down.
comptime CHIN = Gene(26)
# How far the cheekbones stand out.
comptime CHEEKBONES = Gene(27)
# How far the brow ridge stands out over the eyes.
comptime BROW_RIDGE = Gene(28)
# Frame. The length of the neck.
comptime NECK_LENGTH = Gene(29)
# The breadth of the shoulders and the rib cage.
comptime SHOULDER_BREADTH = Gene(30)
# The depth of the chest, front to back.
comptime CHEST_DEPTH = Gene(31)
# The length of the arms against the stature.
comptime ARM_LENGTH = Gene(32)
# How long the scalp's hair is: -1 is cropped close, 0 is short, 1 falls
# to the jaw in a bob. Hair is cut, not only grown, so this is a look
# more than a trait.
comptime HAIR_LENGTH = Gene(33)


@fieldwise_init
struct Expression(ImplicitlyCopyable, Writable):
    """How strongly a gene is expressed: a dimensionless -1 through 1.

    The type stops a bare float at compile time. A value outside the
    interval is still constructible, and the boundary that reads it
    refuses it.
    """

    var value: Float32

    def is_valid(self) -> Bool:
        """Return True if the value is finite and lies in -1 through 1."""
        return isfinite(self.value) and self.value >= -1 and self.value <= 1


def gene_label(gene: Gene) -> String:
    """Return the name of `gene` for error text and tables.

    Args:
        gene: A gene, named or not.

    Returns:
        A lowercase name such as `"melanin"`, or `"gene"` when `gene` is
        not named.
    """
    if not gene.is_valid():
        return "gene"
    var names: List[String] = [
        "melanin",
        "undertone",
        "freckles",
        "hair melanin",
        "hair redness",
        "iris melanin",
        "eye size",
        "eye spacing",
        "eye tilt",
        "eye depth",
        "brow height",
        "brow thickness",
        "brow arch",
        "nose length",
        "nose width",
        "nose projection",
        "nose bridge",
        "mouth width",
        "lip fullness",
        "ear size",
        "ear protrusion",
        "ear lobe",
        "head width",
        "head length",
        "head height",
        "jaw width",
        "chin",
        "cheekbones",
        "brow ridge",
        "neck length",
        "shoulder breadth",
        "chest depth",
        "arm length",
        "hair length",
    ]
    return names[gene.value]


def named_genes() -> List[Gene]:
    """Return every named gene in a stable order.

    Returns:
        `MELANIN` through `HAIR_LENGTH`.
    """
    var genes = List[Gene]()
    for index in range(GENE_COUNT):  # pragma: no branch
        genes.append(Gene(index))
    return genes^


struct Genome(Equatable, ImplicitlyCopyable, Writable):
    """One expression for each gene. Zero everywhere is the template."""

    var expressions: SIMD[DType.float32, 64]

    def __init__(out self):
        """Make the template genome: every gene at zero."""
        self.expressions = SIMD[DType.float32, 64](0)

    def is_valid(self) -> Bool:
        """Return True if every expression is finite and in -1 through 1.

        Returns:
            Whether a body can read this genome.
        """
        for index in range(GENE_COUNT):  # pragma: no branch
            if not Expression(self.expressions[index]).is_valid():
                return False
        return True

    def get(self, gene: Gene) raises -> Float32:
        """Return how strongly `gene` is expressed.

        Args:
            gene: A named gene.

        Returns:
            The expression, -1 through 1.

        Raises:
            Error: If `gene` is not named.
        """
        if not gene.is_valid():
            raise Error("A genome has no " + gene_label(gene))
        return self.expressions[gene.value]

    def with_gene(self, gene: Gene, expression: Expression) raises -> Genome:
        """Return a copy of this genome with one gene changed.

        Args:
            gene: A named gene.
            expression: Its new expression, -1 through 1.

        Returns:
            The changed copy.

        Raises:
            Error: If `gene` is not named, or `expression` is not finite
                or lies outside -1 through 1.
        """
        if not gene.is_valid():
            raise Error("A genome has no " + gene_label(gene))
        if not expression.is_valid():
            raise Error(
                "The " + gene_label(gene) + " expression must lie in -1 to 1"
            )
        var copy = self
        copy.expressions[gene.value] = expression.value
        return copy

    def __eq__(self, other: Self) -> Bool:
        """Return True if every expression matches.

        Args:
            other: The genome to compare.

        Returns:
            Whether the two genomes are the same.
        """
        return self.expressions == other.expressions


def check_genome(genome: Genome, part: String) raises:
    """Refuse a genome a body part cannot read.

    Args:
        genome: The genome to check.
        part: Name used in the error text.

    Raises:
        Error: If an expression is not finite or lies outside -1 to 1.
    """
    if not genome.is_valid():
        raise Error("A " + part + " needs gene expressions in -1 to 1")


def _mix(state: UInt64) -> UInt64:
    """Return the SplitMix64 finalizer of `state`."""
    var z = state
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    return z ^ (z >> 31)


def _unit(seed: Int, index: Int) -> Float32:
    """Return a hashed value in 0 through 1 for `seed` and `index`."""
    var bits = _mix(UInt64(seed) * 0x9E3779B97F4A7C15 + UInt64(index))
    return Float32(Float64(bits >> 40) / Float64(1 << 24))


def _normal(seed: Int, index: Int) -> Float32:
    """Return a hashed value near a standard normal, held to -1 to 1.

    The sum of four uniforms is scaled to a spread of about 0.45, so
    most traits sit near the template and a few are strong.
    """
    var total = Float32(0)
    for k in range(4):  # pragma: no branch
        total += _unit(seed, index * 4 + k)
    var value = (total - 2) * Float32(0.78)
    return max(Float32(-1), min(Float32(1), value))


def random_genome(seed: Int) -> Genome:
    """Return a plausible genome drawn from `seed`.

    The same seed always gives the same genome. Most traits land near
    the template. Pigment genes are linked the way they are in people:
    dark skin rarely comes with blond hair, freckles or blue eyes.

    Args:
        seed: Any integer.

    Returns:
        A valid genome.
    """
    var genome = Genome()
    for index in range(GENE_COUNT):  # pragma: no branch
        genome.expressions[index] = _normal(seed, index)
    # Skin tone spreads over the whole range.
    var melanin = _unit(seed, 1000) * 2 - 1
    genome.expressions[MELANIN.value] = melanin
    var dark = max(Float32(0), melanin)
    # Darker skin pulls the hair and the iris dark, and the freckles
    # away.
    var hair = genome.expressions[HAIR_MELANIN.value]
    genome.expressions[HAIR_MELANIN.value] = hair + (1 - hair) * dark
    var iris = genome.expressions[IRIS_MELANIN.value]
    genome.expressions[IRIS_MELANIN.value] = iris + (1 - iris) * dark
    var freckles = genome.expressions[FRECKLES.value]
    genome.expressions[FRECKLES.value] = freckles - (1 + freckles) * dark
    var red = genome.expressions[HAIR_REDNESS.value]
    genome.expressions[HAIR_REDNESS.value] = red - (1 + red) * dark
    return genome


def offspring(mother: Genome, father: Genome, seed: Int) raises -> Genome:
    """Return a child of two genomes.

    Each gene comes from a blend of the two parents, drawn from `seed`,
    with a small mutation. The child of two equal genomes is close to
    them.

    Args:
        mother: One parent.
        father: The other parent.
        seed: Any integer. The same seed gives the same child.

    Returns:
        A valid genome.

    Raises:
        Error: If either parent is not valid.
    """
    check_genome(mother, "parent")
    check_genome(father, "parent")
    var child = Genome()
    for index in range(GENE_COUNT):  # pragma: no branch
        var t = _unit(seed, index)
        var mutation = (_unit(seed, index + 500) - Float32(0.5)) * Float32(0.2)
        var value = (
            mother.expressions[index] * (1 - t)
            + father.expressions[index] * t
            + mutation
        )
        child.expressions[index] = max(Float32(-1), min(Float32(1), value))
    return child
