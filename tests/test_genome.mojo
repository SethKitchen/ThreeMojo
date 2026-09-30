# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the humanoid genome: genes, expressions and inheritance."""

from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.genome import (
    EAR_SIZE,
    Expression,
    FRECKLES,
    GENE_COUNT,
    Gene,
    Genome,
    HAIR_MELANIN,
    HIP_BREADTH,
    IRIS_MELANIN,
    MELANIN,
    NOSE_LENGTH,
    check_genome,
    gene_label,
    named_genes,
    offspring,
    random_genome,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def test_genes_are_named() raises:
    var genes = named_genes()
    assert_equal(len(genes), GENE_COUNT)
    assert_true(genes[0] == MELANIN)
    assert_true(genes[GENE_COUNT - 1] == HIP_BREADTH)
    assert_equal(gene_label(MELANIN), "melanin")
    assert_equal(gene_label(HIP_BREADTH), "hip breadth")
    assert_equal(gene_label(Gene(GENE_COUNT)), "gene")
    assert_false(Gene(-1).is_valid())
    for index in range(len(genes)):  # pragma: no branch
        assert_true(genes[index].is_valid())
        assert_true(gene_label(genes[index]) != "gene")


def test_expressions_are_bounded() raises:
    assert_true(Expression(1).is_valid())
    assert_true(Expression(-1).is_valid())
    assert_false(Expression(1.01).is_valid())
    assert_false(Expression(-1.5).is_valid())
    assert_false(Expression(Float32.MAX * 2).is_valid())


def test_template_genome() raises:
    var genome = Genome()
    assert_true(genome.is_valid())
    assert_equal(genome.get(NOSE_LENGTH), 0)
    var changed = genome.with_gene(NOSE_LENGTH, Expression(0.5))
    assert_equal(changed.get(NOSE_LENGTH), 0.5)
    assert_equal(genome.get(NOSE_LENGTH), 0)
    assert_false(changed == genome)
    assert_true(Genome() == genome)
    with assert_raises(contains="gene"):
        _ = genome.get(Gene(99))
    with assert_raises(contains="gene"):
        _ = genome.with_gene(Gene(99), Expression(0))
    with assert_raises(contains="nose length"):
        _ = genome.with_gene(NOSE_LENGTH, Expression(2))
    var broken = Genome()
    broken.expressions[EAR_SIZE.value] = 3
    assert_false(broken.is_valid())
    with assert_raises(contains="head"):
        check_genome(broken, "head")
    check_genome(changed, "head")


def test_spec_carries_a_genome() raises:
    var plain = HumanoidSpec(Length(6.0, FOOT), MALE)
    assert_true(plain.genome == Genome())
    assert_true(plain.athleticism == UNTONED)
    var genome = Genome().with_gene(MELANIN, Expression(0.8))
    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED, genome)
    assert_equal(person.genome.get(MELANIN), Float32(0.8))


def test_random_genomes_are_plausible() raises:
    var a = random_genome(1)
    var b = random_genome(1)
    assert_true(a == b)
    assert_false(a == random_genome(2))
    var dark_blond = 0
    for seed in range(200):  # pragma: no branch
        var genome = random_genome(seed)
        assert_true(genome.is_valid())
        var skin = genome.get(MELANIN)
        if skin > 0.6 and genome.get(HAIR_MELANIN) < -0.3:
            dark_blond += 1
        if skin > 0.9:
            assert_true(genome.get(IRIS_MELANIN) > 0.5)
            assert_true(genome.get(FRECKLES) < -0.5)
    assert_equal(dark_blond, 0)


def test_offspring_blends_the_parents() raises:
    var mother = Genome().with_gene(MELANIN, Expression(-1))
    var father = Genome().with_gene(MELANIN, Expression(1))
    var child = offspring(mother, father, 3)
    assert_true(child.is_valid())
    assert_true(abs(child.get(MELANIN)) < 1.0)
    var twin = offspring(mother, mother, 9)
    assert_true(twin.get(MELANIN) < -0.85)
    assert_true(abs(twin.get(NOSE_LENGTH)) <= 0.1)
    var broken = Genome()
    broken.expressions[0] = 5
    with assert_raises(contains="parent"):
        _ = offspring(broken, father, 1)
    with assert_raises(contains="parent"):
        _ = offspring(mother, broken, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
