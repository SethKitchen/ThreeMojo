// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// Check the WebGPU splats against the CPU splats, in a headless Chrome, and
// time them:
//
//   node examples/capi/web/check_splat_gpu.mjs [out/capi/web]
//
// The page's WebGPU path and the module's own CPU path draw the same view of
// the same scan, so they must agree. They cannot agree bit for bit: the shader
// has its own exponential, sine and arctangent, WGSL cannot forbid a fused
// multiply-add, and a half-float picture rounds each blend where the CPU rounds
// once. This script allows a small mean difference and a few outlying pixels.
// It then draws frames at 1280 by 720 pixels with the camera turning, and
// reports how long a frame takes, from the module's sort to the device's last
// pass. It also checks that a frame of another size is drawn from the same scan.
//
// It skips, and passes, where there is no Chrome, or Chrome has no WebGPU
// adapter, as on a machine with no GPU.
import { fileURLToPath } from "node:url";
import { inChrome } from "./chrome.mjs";

const folder = process.argv[2] ?? fileURLToPath(new URL("../../../out/capi/web/", import.meta.url));
const MEAN_LIMIT = 0.25;
const OUTLIER = 20;
const OUTLIER_LIMIT = 0.001;
const TIMEOUT_MS = 300000;

// What runs in the page: two apps with the same events, the CPU frame of one
// and the device's frame of the other, then a timed run and a second size.
const EXPRESSION = `(async () => {
  const { load, Kind, Button } = await import("/threemojo.js");
  const { GpuSplat, requestGpu } = await import("/splat_gpu.js");
  const gpu = await requestGpu();
  if (!gpu) return { skip: "Chrome has no WebGPU adapter" };
  const shader = await (await fetch("/splat.wgsl")).text();
  const scan = new Uint8Array(await (await fetch("/tomatoes.v4.spz")).arrayBuffer());
  const library = await load("/threemojo_splat.wasm");
  const make = (width, height) => {
    const app = library.create(width, height);
    if (!app.asset(scan)) throw new Error("the module refused the scan");
    return app;
  };
  const WIDTH = 480, HEIGHT = 270, TICK = 16667;
  const cpu = make(WIDTH, HEIGHT);
  const app = make(WIDTH, HEIGHT);
  const splats = await GpuSplat.create(gpu.device, app, shader);
  // Both apps turn the same way: a drag, then steps.
  for (const each of [cpu, app]) {
    each.event(Kind.POINTER_DOWN, 240, 135, Button.PRIMARY);
    each.event(Kind.POINTER_MOVE, 300, 150, Button.PRIMARY);
    each.event(Kind.POINTER_UP, 300, 150, Button.PRIMARY);
  }
  for (let frame = 0; frame < 4; frame++) {
    cpu.step(TICK);
    await splats.frame(TICK);
  }
  const want = cpu.frame().slice();
  const got = await splats.readPixels();
  let sum = 0, big = 0, worst = 0, lit = 0;
  for (let at = 0; at < WIDTH * HEIGHT * 4; at++) {
    if (at % 4 === 3) continue;
    const difference = Math.abs(want[at] - got[at]);
    sum += difference;
    if (difference > ${OUTLIER}) big++;
    worst = Math.max(worst, difference);
    if (got[at] > 60) lit++;
  }
  const channels = WIDTH * HEIGHT * 3;

  // The same scan at another size, with nothing read again.
  const scans = library.exports.tm_splat_info(app.handle, 2);
  splats.resize(240, 135);
  await splats.frame(0);
  const small = await splats.readPixels();
  let smallLit = 0;
  for (let at = 0; at < small.length; at++) if (at % 4 !== 3 && small[at] > 60) smallLit++;
  const sameScan = library.exports.tm_splat_info(app.handle, 2) === scans;

  // A timed run at 1280 by 720, with the camera turning by itself.
  splats.resize(1280, 720);
  for (let frame = 0; frame < 20; frame++) await splats.frame(TICK);
  const times = [];
  for (let frame = 0; frame < 120; frame++) times.push(await splats.frame(TICK));
  times.sort((a, b) => a - b);
  const mean = times.reduce((total, value) => total + value, 0) / times.length;
  return {
    mean: sum / channels, outliers: big / channels, worst, lit,
    reused: smallLit > 500 && sameScan && splats.width === 1280,
    timing: { mean, median: times[Math.floor(times.length / 2)], p95: times[Math.floor(times.length * 0.95)], best: times[0] },
    errors: splats.errors,
  };
})()`;

const result = await inChrome(folder, EXPRESSION, { timeout: TIMEOUT_MS });
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
  console.log(`mean ${result.mean.toFixed(4)}, worst ${result.worst}, outliers ${(result.outliers * 100).toFixed(4)} %, lit ${result.lit}`);
  const t = result.timing;
  console.log(
    `1280x720: ${t.mean.toFixed(2)} ms a frame on average (${(1000 / t.mean).toFixed(0)} fps), ` +
      `median ${t.median.toFixed(2)}, 95th ${t.p95.toFixed(2)}, best ${t.best.toFixed(2)}`,
  );
  check("gpu: the picture has the tomatoes in it", result.lit > 2000);
  check(`gpu: the mean difference from the CPU frame is at most ${MEAN_LIMIT}`, result.mean <= MEAN_LIMIT);
  check(`gpu: at most ${OUTLIER_LIMIT * 100} % of the values differ by more than ${OUTLIER}`, result.outliers <= OUTLIER_LIMIT);
  check("gpu: a frame of another size is drawn from the same scan", result.reused);
  check(`gpu: the device reports no error${result.errors.length ? `: ${result.errors[0]}` : ""}`, result.errors.length === 0);
}
console.log(failures === 0 ? "PASS" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
