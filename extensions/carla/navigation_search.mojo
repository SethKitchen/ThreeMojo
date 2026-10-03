# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite work and storage policies shared by CARLA graph searches.

These limits cover search, not graph construction or map localization.
Counts are logical entries and operations, not allocator byte limits.
"""


@fieldwise_init
struct NavigationSearchStatus(Equatable, ImplicitlyCopyable, Writable):
    """The terminal result of a navigation search.

    Args:
        value: The status value.

    Returns:
        A status. Consumers must check `is_valid`.

    """

    var value: Int

    def is_valid(self) -> Bool:
        """Check the status.

        Returns:
            True for one of the four search statuses.

        """
        return self.value >= 0 and self.value <= 3


comptime SEARCH_SUCCESS = NavigationSearchStatus(0)
comptime SEARCH_UNREACHABLE = NavigationSearchStatus(1)
comptime SEARCH_EXHAUSTED = NavigationSearchStatus(2)
comptime SEARCH_TRUNCATED = NavigationSearchStatus(3)


@fieldwise_init
struct NavigationSearchLimit(Equatable, ImplicitlyCopyable, Writable):
    """The first search resource that could not admit an operation.

    Args:
        value: The limit value.

    Returns:
        A limit. Consumers must check `is_valid`.

    """

    var value: Int

    def is_valid(self) -> Bool:
        """Check the limit.

        Returns:
            True for no limit or one of the five search resources.

        """
        return self.value >= 0 and self.value <= 5


comptime SEARCH_LIMIT_NONE = NavigationSearchLimit(0)
comptime SEARCH_LIMIT_NODES = NavigationSearchLimit(1)
comptime SEARCH_LIMIT_EXPANSIONS = NavigationSearchLimit(2)
comptime SEARCH_LIMIT_QUEUE = NavigationSearchLimit(3)
comptime SEARCH_LIMIT_POPS = NavigationSearchLimit(4)
comptime SEARCH_LIMIT_EDGES = NavigationSearchLimit(5)


struct NavigationSearchBudget(ImplicitlyCopyable):
    """A finite policy for one search, with independent nonnegative limits.

    Args:
        max_nodes: The maximum number of discovered node records.
        max_expansions: The maximum number of non-goal expansions.
        max_queue_entries: The maximum number of resident heap entries.
        max_pops: The maximum number of heap pops, including stale entries.
        max_edges: The maximum number of examined adjacency entries.

    Returns:
        A policy. Each search validates it again to detect direct mutation.

    Raises:
        Error: If any limit is negative.
    """

    var max_nodes: Int
    var max_expansions: Int
    var max_queue_entries: Int
    var max_pops: Int
    var max_edges: Int

    def __init__(out self):
        """Create the default finite resource policy.

        Returns:
            Limits of 4096 nodes, 8192 expansions and queue entries,
            32768 pops, and 65536 edges.

        """
        self.max_nodes = 4096
        self.max_expansions = 8192
        self.max_queue_entries = 8192
        self.max_pops = 32768
        self.max_edges = 65536

    def __init__(
        out self,
        max_nodes: Int,
        max_expansions: Int = 8192,
        max_queue_entries: Int = 8192,
        max_pops: Int = 32768,
        max_edges: Int = 65536,
    ) raises:
        """Create a policy; zero forbids the corresponding operation.

        Args:
            max_nodes: The node record limit.
            max_expansions: The expansion limit.
            max_queue_entries: The resident heap entry limit.
            max_pops: The total heap pop limit.
            max_edges: The adjacency inspection limit.

        Returns:
            A finite policy.

        Raises:
            Error: If a limit is negative.
        """
        self.max_nodes = max_nodes
        self.max_expansions = max_expansions
        self.max_queue_entries = max_queue_entries
        self.max_pops = max_pops
        self.max_edges = max_edges
        self.validate()

    def validate(self) raises:
        """Reject invalid limits, including direct field mutation.


        Raises:
            Error: If any limit is negative.
        """
        if (
            self.max_nodes < 0
            or self.max_expansions < 0
            or self.max_queue_entries < 0
            or self.max_pops < 0
            or self.max_edges < 0
        ):
            raise Error("Navigation search limits must be nonnegative")


struct NavigationSearchReport(ImplicitlyCopyable):
    """Search termination and exact operation counts.

    `expanded` excludes goal and stale pops, but includes a node whose
    adjacency scan stops at a limit. Reopened nodes count again.
    `examined` includes filtered edges and non-improving candidates.
    `output_truncated` preserves output loss on exhausted/unreachable paths.

    Args:
        None.

    Returns:
        An empty unreachable report.

    """

    var status: NavigationSearchStatus
    var limit: NavigationSearchLimit
    var discovered: Int
    var expanded: Int
    var queue_peak: Int
    var popped: Int
    var examined: Int
    var stale: Int
    var reopened: Int
    var output_truncated: Bool

    def __init__(out self):
        """Create zero counts with no exhausted resource.

        Returns:
            An empty report.

        """
        self.status = SEARCH_UNREACHABLE
        self.limit = SEARCH_LIMIT_NONE
        self.discovered = 0
        self.expanded = 0
        self.queue_peak = 0
        self.popped = 0
        self.examined = 0
        self.stale = 0
        self.reopened = 0
        self.output_truncated = False

    def _exhaust(mut self, limit: NavigationSearchLimit) raises -> Bool:
        if not limit.is_valid() or limit == SEARCH_LIMIT_NONE:
            raise Error("Navigation search limit is not valid")
        self.status = SEARCH_EXHAUSTED
        self.limit = limit
        return False

    def _admit(
        mut self, budget: NavigationSearchBudget, queued: Int, discover: Bool
    ) raises -> Bool:
        # Check both capacities before growing either storage structure.
        if discover and self.discovered == budget.max_nodes:
            return self._exhaust(SEARCH_LIMIT_NODES)
        if queued == budget.max_queue_entries:
            return self._exhaust(SEARCH_LIMIT_QUEUE)
        self.discovered += Int(discover)
        self.queue_peak = max(self.queue_peak, queued + 1)
        return True

    def _pop(mut self, budget: NavigationSearchBudget) raises -> Bool:
        if self.popped == budget.max_pops:
            return self._exhaust(SEARCH_LIMIT_POPS)
        self.popped += 1
        return True

    def _expand(mut self, budget: NavigationSearchBudget) raises -> Bool:
        if self.expanded == budget.max_expansions:
            return self._exhaust(SEARCH_LIMIT_EXPANSIONS)
        self.expanded += 1
        return True

    def _edge(mut self, budget: NavigationSearchBudget) raises -> Bool:
        if self.examined == budget.max_edges:
            return self._exhaust(SEARCH_LIMIT_EDGES)
        self.examined += 1
        return True

    def _truncate(mut self, truncated: Bool) raises:
        if not self.status.is_valid():
            raise Error("Navigation search status is not valid")
        self.output_truncated = truncated
        if truncated and self.status == SEARCH_SUCCESS:
            self.status = SEARCH_TRUNCATED
