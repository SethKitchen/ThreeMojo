// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// Check the WebGPU water against the CPU water, in a headless Chrome:
//
//   node examples/capi/web/check_gpu.mjs [out/capi/web]
//
// The page's WebGPU path and the module's own CPU path draw the same frames
// from the same water, so they must agree. They cannot agree bit for bit: the
// shader uses the device's sine and arctangent, and WGSL cannot forbid a fused
// multiply-add. This script allows a mean difference of 0.05 of 255 and a few
// pixels that differ by more than 8. A frame at another size must also come
// from the passes of the first, which the page does when its size changes.
//
// It starts Chrome (CHROME names it, or it looks in the usual places), a
// server for the folder, and nothing else. It skips, and passes, where there
// is no Chrome, or Chrome has no WebGPU adapter, as on a machine with no GPU.
import { fileURLToPath } from "node:url";
import { inChrome } from "./chrome.mjs";

const folder = process.argv[2] ?? fileURLToPath(new URL("../../../out/capi/web/", import.meta.url));
const MEAN_LIMIT = 0.05;
const OUTLIER_LIMIT = 0.001;
const OUTLIER = 8;

// What runs in the page: the two ways to draw 3 frames, and a second size.
const EXPRESSION = `(async () => {
  const { load } = await import("/threemojo.js");
  const { GpuWater, requestGpu } = await import("/water_gpu.js");
  const gpu = await requestGpu();
  if (!gpu) return { skip: "Chrome has no WebGPU adapter" };
  const shader = await (await fetch("/water.wgsl")).text();
  const photograph = new Uint8Array(await (await fetch("/pebbles.jpg")).arrayBuffer());
  const library = await load("/threemojo_water.wasm");
  const make = (width, height) => {
    const app = library.create(width, height);
    app.asset(photograph);
    return app;
  };
  const WIDTH = 320, HEIGHT = 180, FRAMES = 3, TICK = 33333;
  const cpu = make(WIDTH, HEIGHT);
  const app = make(WIDTH, HEIGHT);
  const water = await GpuWater.create(gpu.device, app, shader);
  for (let frame = 0; frame < FRAMES; frame++) {
    cpu.step(TICK);
    await water.frame(TICK);
  }
  const want = cpu.frame().slice();
  const got = await water.readPixels();
  let sum = 0, big = 0, worst = 0;
  const channels = WIDTH * HEIGHT * 3;
  for (let at = 0; at < WIDTH * HEIGHT * 4; at++) {
    if (at % 4 === 3) continue;
    const difference = Math.abs(want[at] - got[at]);
    sum += difference;
    if (difference > ${OUTLIER}) big++;
    worst = Math.max(worst, difference);
  }
  // A second size, from the passes of the first.
  const other = make(160, 90);
  const again = await GpuWater.create(gpu.device, other, shader, { reuse: water });
  await again.frame(TICK);
  const small = await again.readPixels();
  let lit = 0;
  for (let at = 0; at < small.length; at++) if (at % 4 !== 3 && small[at] > 40) lit++;
  return {
    mean: sum / channels, outliers: big / channels, worst,
    reused: lit > 1000, errors: water.errors.concat(again.errors),
  };
})()`;

const result = await inChrome(folder, EXPRESSION);
let failures = 0;
if (result === null) {
  console.log("skip no Chrome (set CHROME to one)");
} else if (result.skip) {
  console.log(`skip ${result.skip}`);
} else {
  const check = (name, ok) => {
    if (!ok) failures++;
    console.log(`${ok ? "ok  " : "FAIL"} ${name}`);
  };
  console.log(`mean ${result.mean.toFixed(4)}, worst ${result.worst}, outliers ${(result.outliers * 100).toFixed(4)} %`);
  check(`gpu: the mean difference from the CPU frame is at most ${MEAN_LIMIT}`, result.mean <= MEAN_LIMIT);
  check(`gpu: at most ${OUTLIER_LIMIT * 100} % of the values differ by more than ${OUTLIER}`, result.outliers <= OUTLIER_LIMIT);
  check("gpu: a frame of another size is drawn from the same passes", result.reused);
  check(`gpu: the device reports no error${result.errors.length ? `: ${result.errors[0]}` : ""}`, result.errors.length === 0);
}
console.log(failures === 0 ? "PASS" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
