/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Extend the existing pinned-runtime meter with retained requested bytes.
 * Keep the allocation interposer and its self-test in one implementation.
 */
#include "navigation_allocations.c"

uint64_t physics_snapshot_allocations_live(void) { return live; }
