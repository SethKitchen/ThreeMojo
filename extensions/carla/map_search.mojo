# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite spatial map policies, separate from navigation graph search.

Limits count logical entries and operations. They do not measure allocator
bytes. Exhaustion raises an Error and never returns a partial map or winner.
"""


struct MapBuildBudget(ImplicitlyCopyable):
    """Nonnegative finite limits for spatial index construction."""

    var max_segments: Int
    var max_steps: Int
    var max_terms: Int
    var max_records: Int

    def __init__(out self):
        """Create the default finite policy.

        Returns:
            The documented default limits.
        """
        self.max_segments = 262144
        self.max_steps = 4194304
        self.max_terms = 67108864
        self.max_records = 1048576

    def __init__(
        out self,
        max_segments: Int,
        max_steps: Int = 4194304,
        max_terms: Int = 67108864,
        max_records: Int = 1048576,
    ) raises:
        """Create a policy; zero forbids the corresponding operation.

        Args:
            max_segments: Maximum emitted lane segments.
            max_steps: Maximum sampling, boundary, and subdivision steps.
            max_terms: Maximum logical quadrature and optional proof-work units.
            max_records: Maximum source lane, section, and geometry records.

        Returns:
            The checked policy.

        Raises:
            Error: If any limit is negative.
        """
        self.max_segments = max_segments
        self.max_steps = max_steps
        self.max_terms = max_terms
        self.max_records = max_records
        self.validate()

    def validate(self) raises:
        """Check limits again to detect direct mutation.

        Raises:
            Error: If any limit is negative.
        """
        if (
            self.max_segments < 0
            or self.max_steps < 0
            or self.max_terms < 0
            or self.max_records < 0
        ):
            raise Error("Spatial index construction limits must be nonnegative")


struct MapQueryBudget(ImplicitlyCopyable):
    """Nonnegative finite limits for one continuous lane query."""

    var max_candidates: Int
    var max_nodes: Int
    var max_terms: Int
    var max_index_pops: Int
    var max_queue_entries: Int
    var max_steps: Int

    def __init__(out self):
        """Create the default finite policy.

        Returns:
            The documented default limits.
        """
        self.max_candidates = 4096
        self.max_nodes = 1048576
        self.max_terms = 67108864
        self.max_index_pops = 1048576
        self.max_queue_entries = 262144
        self.max_steps = 4194304

    def __init__(
        out self,
        max_candidates: Int,
        max_nodes: Int = 1048576,
        max_terms: Int = 67108864,
        max_index_pops: Int = 1048576,
        max_queue_entries: Int = 262144,
        max_steps: Int = 4194304,
    ) raises:
        """Create a policy; zero forbids the corresponding operation.

        Args:
            max_candidates: Maximum retained lane candidates.
            max_nodes: Maximum cumulative refinement and classification nodes.
            max_terms: Maximum cumulative quadrature and optional proof-work units.
            max_index_pops: Maximum spatial index heap pops.
            max_queue_entries: Maximum resident spatial index heap entries.
            max_steps: Maximum lookup, profile, heap and bookkeeping units.

        Returns:
            The checked policy.

        Raises:
            Error: If any limit is negative.
        """
        self.max_candidates = max_candidates
        self.max_nodes = max_nodes
        self.max_terms = max_terms
        self.max_index_pops = max_index_pops
        self.max_queue_entries = max_queue_entries
        self.max_steps = max_steps
        self.validate()

    def validate(self) raises:
        """Check limits again to detect direct mutation.

        Raises:
            Error: If any limit is negative.
        """
        if (
            self.max_candidates < 0
            or self.max_nodes < 0
            or self.max_terms < 0
            or self.max_index_pops < 0
            or self.max_queue_entries < 0
            or self.max_steps < 0
        ):
            raise Error("One continuous lane query limits must be nonnegative")


struct _MapBuildWork(ImplicitlyCopyable):
    # Operation-scoped counters. A refused reservation permanently poisons
    # this ledger, so an optional optimization cannot hide exhaustion.
    var policy: MapBuildBudget
    var segments: Int
    var steps: Int
    var terms: Int
    var records: Int
    var exhausted: Bool

    def __init__(out self, policy: MapBuildBudget):
        self.policy = policy
        self.segments = 0
        self.steps = 0
        self.terms = 0
        self.records = 0
        self.exhausted = False

    def validate(self) raises:
        self.policy.validate()
        if self.exhausted:
            raise Error("Map construction already exhausted its global budget")
        if (
            self.segments < 0
            or self.segments > self.policy.max_segments
            or self.steps < 0
            or self.steps > self.policy.max_steps
            or self.terms < 0
            or self.terms > self.policy.max_terms
            or self.records < 0
            or self.records > self.policy.max_records
        ):
            raise Error("Map construction has invalid consumed work")

    def segment(mut self) raises:
        self.validate()
        if self.segments >= self.policy.max_segments:
            self.exhausted = True
            raise Error("Map construction exhausted its global segment budget")
        self.segments += 1

    def step(mut self, count: Int = 1) raises:
        self.validate()
        if count < 0 or count > self.policy.max_steps - self.steps:
            self.exhausted = True
            raise Error("Map construction exhausted its global step budget")
        self.steps += count

    def record(mut self, count: Int) raises:
        self.validate()
        if count < 0 or count > self.policy.max_records - self.records:
            self.exhausted = True
            raise Error("Map construction exhausted its source record budget")
        self.records += count

    def term(mut self, count: Int) raises:
        self.validate()
        if count < 0 or count > self.policy.max_terms - self.terms:
            self.exhausted = True
            raise Error("Map construction exhausted its global term budget")
        self.terms += count

    def step_product(mut self, one: Int, two: Int) raises:
        self.validate()
        if one < 0 or two < 0:
            self.exhausted = True
            raise Error("Map construction needs nonnegative work factors")
        if two > 0 and one > (self.policy.max_steps - self.steps) // two:
            self.exhausted = True
            raise Error("Map construction exhausted its global step budget")
        self.step(one * two)

    def sort_work(mut self, count: Int) raises:
        # Worst-case insertion/selection comparisons, checked before sorting.
        self.step(count)
        if count > 1:
            if count % 2 == 0:
                self.step_product(count // 2, count - 1)
            else:
                self.step_product(count, (count - 1) // 2)

    def proof_headroom(mut self) raises:
        self.validate()
        # Retain each original per-segment proof allowance; reserve headroom
        # before starting, and charge actual terms after the complete attempt.
        if self.policy.max_terms - self.terms < 2000000:
            self.exhausted = True
            raise Error("Map construction exhausted its global term budget")


struct _MapQueryWork(ImplicitlyCopyable):
    var policy: MapQueryBudget
    var candidates: Int
    var nodes: Int
    var terms: Int
    var index_pops: Int
    var peak_queue_entries: Int
    var exhausted: Bool
    var steps: Int
    var max_total_steps: Int

    def __init__(
        out self,
        policy: MapQueryBudget,
        max_total_steps: Int = 9223372036854775807,
    ):
        self.policy = policy
        self.candidates = 0
        self.nodes = 0
        self.terms = 0
        self.index_pops = 0
        self.peak_queue_entries = 0
        self.exhausted = False
        self.steps = 0
        self.max_total_steps = min(max_total_steps, policy.max_steps)

    def validate(self) raises:
        self.policy.validate()
        if self.exhausted:
            raise Error("Map query already exhausted its global budget")
        if (
            self.max_total_steps < 0
            or self.steps < 0
            or self.steps > self.max_total_steps
            or self.steps > self.policy.max_steps
            or self.candidates < 0
            or self.candidates > self.policy.max_candidates
            or self.nodes < 0
            or self.nodes > self.policy.max_nodes
            or self.terms < 0
            or self.terms > self.policy.max_terms
            or self.index_pops < 0
            or self.index_pops > self.policy.max_index_pops
            or self.peak_queue_entries < 0
            or self.peak_queue_entries > self.policy.max_queue_entries
        ):
            raise Error("Map query has invalid consumed work")

    def _step(mut self, count: Int = 1) raises:
        self.validate()
        if (
            count < 0
            or count
            > min(self.max_total_steps, self.policy.max_steps) - self.steps
        ):
            self.exhausted = True
            raise Error("Map query exhausted its global step budget")
        self.steps += count

    def _step_product(mut self, one: Int, two: Int) raises:
        self.validate()
        var remaining = (
            min(self.max_total_steps, self.policy.max_steps) - self.steps
        )
        if one < 0 or two < 0 or (two > 0 and one > remaining // two):
            self.exhausted = True
            raise Error("Map query exhausted its global step budget")
        self._step(one * two)

    def candidate(mut self) raises:
        self.validate()
        if self.candidates >= self.policy.max_candidates:
            self.exhausted = True
            raise Error("Map query exhausted its global candidate budget")
        self._step()
        self.candidates += 1

    def index_pop(mut self) raises:
        self.validate()
        if self.index_pops >= self.policy.max_index_pops:
            self.exhausted = True
            raise Error("Map query exhausted its spatial index pop budget")
        self._step()
        self.index_pops += 1

    def queue_push(mut self, resident: Int) raises:
        self.validate()
        if resident < 0 or resident >= self.policy.max_queue_entries:
            self.exhausted = True
            raise Error("Map query exhausted its spatial index queue budget")
        self._step()
        self.peak_queue_entries = max(self.peak_queue_entries, resident + 1)

    def node_cap(self, existing: Int = 0, step_cost: Int = 1) raises -> Int:
        self.validate()
        if existing < 0 or existing > 16384 or step_cost < 1:
            raise Error("Lane certificate has invalid consumed node work")
        return existing + min(
            16384 - existing,
            min(
                self.policy.max_nodes - self.nodes,
                (min(self.max_total_steps, self.policy.max_steps) - self.steps)
                // step_cost,
            ),
        )

    def term_cap(self, existing: Int = 0) raises -> Int:
        self.validate()
        if existing < 0 or existing > 2000000:
            raise Error("Lane certificate has invalid consumed term work")
        return existing + min(
            2000000 - existing, self.policy.max_terms - self.terms
        )

    def charge(mut self, nodes: Int, terms: Int, step_cost: Int = 1) raises:
        self.validate()
        if nodes < 0 or nodes > self.policy.max_nodes - self.nodes:
            self.exhausted = True
            raise Error("Map query exhausted its global node budget")
        if terms < 0 or terms > self.policy.max_terms - self.terms:
            self.exhausted = True
            raise Error("Map query exhausted its global term budget")
        if step_cost < 1:
            self.exhausted = True
            raise Error("Map query node step cost must be positive")
        self._step_product(nodes, step_cost)
        self.nodes += nodes
        self.terms += terms
