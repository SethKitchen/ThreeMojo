// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// A smoke test of the WebAssembly build, for Node:
//
//   node examples/capi/web/check.mjs [out/capi/web]
//
// The core module runs the scenario of tests/test_capi_core.mojo and must
// give the same frame hashes, so the native and the WebAssembly builds are
// one program. The water module cannot match the native build bit for bit,
// because WebAssembly has no fused multiply-add and its sine is another
// implementation, so it is checked for what it must do: take its photograph,
// draw, move, and give back the memory that it takes. The threaded water
// module, when it is built, must give the same frames as the one thread
// module, bit for bit, whatever the number of workers: each task writes its
// own rows, so no sum depends on the order of the tasks.
import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";
import { Key, Kind, load, loadThreads } from "./threemojo.js";

const WIDTH = 96;
const HEIGHT = 64;
const TICK = 16667;
const GOLDEN = [1275981141803364349n, 658073559776311977n, 17593184181753337403n];

const folder = process.argv[2] ?? fileURLToPath(new URL("../../../out/capi/web/", import.meta.url));
const read = (name) => readFileSync(`${folder}/${name}`);

function fnv1a(bytes) {
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) hash = ((hash ^ BigInt(byte)) * 0x100000001b3n) & 0xffffffffffffffffn;
  return hash;
}

let failures = 0;
function expect(name, got, want) {
  const ok = got === want;
  if (!ok) failures++;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `: got ${got}, want ${want}`}`);
}

const library = await load(read("threemojo_core.wasm"));
expect("a side of 0 makes no app", library.create(0, 10), null);
expect("a side of 5000 makes no app", library.create(5000, 5), null);

const app = library.create(WIDTH, HEIGHT);
expect("a 96x64 app is made", app !== null, true);
expect("its size", `${app.width}x${app.height}`, "96x64");
expect("the first frame", fnv1a(app.frame()), GOLDEN[0]);

for (let tick = 0; tick < 60; tick++) app.step(TICK);
expect("the frame after 60 ticks", fnv1a(app.frame()), GOLDEN[1]);

app.event(Kind.POINTER_MOVE, 30, 20, -1);
expect("the frame after a pointer move", fnv1a(app.frame()), GOLDEN[2]);

app.event(Kind.KEY_DOWN, 0, 0, Key.SPACE);
for (let tick = 0; tick < 30; tick++) app.step(TICK);
expect("a paused app does not move", fnv1a(app.frame()), GOLDEN[2]);

app.destroy();

// The water.
const WATER = { width: 48, height: 27 };
const water = await load(read("threemojo_water.wasm"));
expect("water: a side of 0 makes no app", water.create(0, 10), null);
const pond = water.create(WATER.width, WATER.height);
expect("water: an app is made without its photograph", pond !== null, true);
expect("water: bytes that are not a photograph are refused", pond.asset(new Uint8Array(16)), false);
expect("water: the photograph is taken", pond.asset(read("pebbles.jpg")), true);
const brightest = (pixels) => pixels.reduce((most, value, at) => (at % 4 === 3 ? most : Math.max(most, value)), 0);
const first = pond.frame().slice();
expect("water: the frame is opaque", first.every((value, at) => at % 4 !== 3 || value === 255), true);
expect("water: the frame is not dark", brightest(first) > 100, true);
pond.step(33333);
expect("water: a step changes the picture", fnv1a(pond.frame()) !== fnv1a(first), true);
for (let frame = 0; frame < 5; frame++) {
  pond.step(33333);
  pond.frame();
}
const memory = water.exports.memory.buffer.byteLength;
for (let frame = 0; frame < 20; frame++) {
  pond.step(33333);
  pond.frame();
}
expect("water: twenty more frames take no more memory", water.exports.memory.buffer.byteLength, memory);

// Mojo returns a pointer that it wraps in a struct through a 64-bit slot, and
// retarget.py must clear the upper half of that slot. After a step it held
// stack garbage, so an address was 0x2000000000...
const wide = (value) => BigInt.asUintN(64, BigInt(value));
const room = water.exports.tm_alloc(1000);
expect("water: an address from tm_alloc has no upper half", wide(room) < 2n ** 32n, true);
water.exports.tm_free(Number(room));
expect("water: no part before the first prepare", wide(water.exports.tm_gpu_part(pond.handle, 0)), 0n);
expect("water: the first prepare packs the photograph once", water.exports.tm_gpu_prepare(pond.handle), 1);
const bytes = water.exports.memory.buffer.byteLength;
for (let part = 0; part < 10; part++) {
  const at = wide(water.exports.tm_gpu_part(pond.handle, part));
  const words = water.exports.tm_gpu_words(pond.handle, part);
  const inside = at > 0n && at < 2n ** 32n && Number(at) % 4 === 0 && Number(at) + words * 4 <= bytes;
  // The glare grid is empty until the host asks for the glare.
  expect(`water: part ${part} lies inside the memory`, inside || (part === 9 && at === 0n), true);
}
expect("water: the glare of a frame with no glints is made", water.exports.tm_gpu_glare(pond.handle), 0);
expect("water: a part that does not exist has no address", wide(water.exports.tm_gpu_part(pond.handle, 99)), 0n);
pond.destroy();

// The threaded water.
const THREADED = "threemojo_water_threads.wasm";
if (existsSync(`${folder}/${THREADED}`)) {
  // The same moves for every module: a photograph, a pebble, a drag, a pause.
  const hashes = async (library) => {
    const app = library.create(96, 54);
    app.asset(read("pebbles.jpg"));
    const seen = [fnv1a(app.frame())];
    app.event(Kind.POINTER_DOWN, 40, 20, 0);
    for (const tilt of [20, 30, 25]) {
      app.event(Kind.POINTER_MOVE, 40, tilt, 0);
      app.step(33333);
      seen.push(fnv1a(app.frame()));
    }
    app.event(Kind.POINTER_UP, 40, 25, 0);
    for (let frame = 0; frame < 6; frame++) {
      app.step(33333);
      seen.push(fnv1a(app.frame()));
    }
    app.destroy();
    return seen;
  };
  const single = await hashes(await load(read("threemojo_water.wasm")));
  expect("threads: the frames of one thread differ from each other", new Set(single).size, single.length);
  for (const threads of [1, 3, 7]) {
    const spawn = () => new Worker(new URL("./check_worker.mjs", import.meta.url));
    const many = await loadThreads(read(THREADED), { threads, spawn });
    expect(`threads: ${threads} workers, memory is shared`, many.shared, true);
    expect(`threads: ${threads} workers give the frames of one thread`, (await hashes(many)).join(), single.join());
    const settled = many.memory.buffer.byteLength;
    const app = many.create(96, 54);
    for (let frame = 0; frame < 30; frame++) {
      app.step(33333);
      app.frame();
    }
    expect(`threads: ${threads} workers, thirty more frames take no more memory`, many.memory.buffer.byteLength, settled);
    app.destroy();
    many.close();
  }
} else {
  console.log(`skip ${THREADED} is not built`);
}

console.log(failures === 0 ? "PASS" : `${failures} FAILED`);
process.exit(failures === 0 ? 0 : 1);
