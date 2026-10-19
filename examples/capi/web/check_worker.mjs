// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// The worker that check.mjs starts in Node, in place of a Web Worker.
import { parentPort } from "node:worker_threads";
import { runWorker } from "./threemojo.js";

parentPort.once("message", runWorker);
