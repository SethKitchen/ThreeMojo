/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 *
 * Mojo has no mutable globals, so a coverage probe cannot remember what it
 * has already reported. This buffer is that memory. coverage/fast.mojo
 * reads it through cov_state. The layout lives in coverage/dedup.mojo.
 * Sixteen megabytes is larger than that layout, so the two can change
 * independently as long as the Mojo side stays inside this block.
 */

#include <stdint.h>

enum { COV_STATE_BYTES = 16 * 1024 * 1024 };

static unsigned char cov_bytes[COV_STATE_BYTES];

uint64_t cov_state(void) { return (uint64_t)(uintptr_t)cov_bytes; }
