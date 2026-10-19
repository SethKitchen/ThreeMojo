// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// A Web Worker for a threaded module. loadThreads in threemojo.js starts it
// and posts the module, the shared memory and the stack.
import { runWorker } from "./threemojo.js";

self.onmessage = (event) => runWorker(event.data);
