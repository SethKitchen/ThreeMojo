// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// ThreeMojo's C ABI (window/threemojo.h) from JavaScript.
//
//   const library = await load("threemojo_core.wasm");  // or bytes
//   const app = library.create(480, 320);                // null if refused
//   app.event(Kind.POINTER_MOVE, x, y, -1);
//   app.step(16667);                                     // microseconds
//   context.putImageData(new ImageData(app.frame(), app.width, app.height), 0, 0);
//
// A module made for one thread imports nothing. It owns its memory, so a view
// of a frame is valid only until the next call: take a new one each time.
//
// A module made for many threads (threemojo_APP_threads.wasm) imports shared
// memory, and a pool of Web Workers runs the same module on that memory:
//
//   const library = await loadThreads("threemojo_water_threads.wasm", { threads: 7 });
//
// A page can make shared memory only when it is cross-origin isolated, which
// needs the headers that examples/capi/serve.py sends. Test `crossOriginIsolated`
// and fall back to `load` without it. A frame from a threaded module is a copy,
// because ImageData does not take a view of shared memory.

export const ABI_VERSION = 1;

/**
 * The shared memory of a threaded module, in 64 KiB pages: 128 MiB to start
 * and 1 GiB at most. build.sh links the module with the same two sizes
 * (INITIAL_MEMORY and MAX_MEMORY), and the module refuses other memory.
 */
export const MEMORY_PAGES = { initial: 2048, maximum: 16384 };

/** The stack of one worker, in bytes. The main thread has the 2 MiB that the link gives. */
export const WORKER_STACK = 2 * 1024 * 1024;

/** The event kinds, as threemojo.h numbers them. */
export const Kind = {
  KEY_DOWN: 0,
  POINTER_DOWN: 1,
  POINTER_MOVE: 2,
  POINTER_UP: 3,
  WHEEL: 4,
  KEY_UP: 6,
};

/** The key codes that are not ASCII. Printable keys are their ASCII codes. */
export const Key = {
  SPACE: 32,
  ESCAPE: 27,
  ARROW_UP: 256,
  ARROW_DOWN: 257,
  ARROW_LEFT: 258,
  ARROW_RIGHT: 259,
};

/** The buttons of a pointer event. */
export const Button = { PRIMARY: 0, MIDDLE: 1, SECONDARY: 2, NONE: -1 };

/**
 * A memory address that a function returned. A pointer is 32 bits here, but
 * Mojo returns an optional pointer in an i64 (a BigInt), so take the low 32
 * bits, which hold the address, and nothing else.
 */
export function address(value) {
  return Number(BigInt.asUintN(32, BigInt(value)));
}

export class App {
  constructor(library, handle, width, height) {
    this.library = library;
    this.handle = handle;
    this.width = width;
    this.height = height;
  }

  event(kind, x, y, detail) {
    this.library.exports.tm_event(this.handle, kind, x, y, detail);
  }

  step(microseconds) {
    this.library.exports.tm_step(this.handle, microseconds);
  }

  /** Draw, and return the frame as RGBA bytes, a view of the module's memory. */
  frame() {
    const { exports, memory, shared } = this.library;
    const pointer = address(exports.tm_frame(this.handle));
    const view = new Uint8ClampedArray(memory.buffer, pointer, this.width * this.height * 4);
    // ImageData refuses a view of shared memory, and the next frame would
    // overwrite it, so a threaded module hands out a copy.
    return shared ? view.slice() : view;
  }

  /**
   * Give the app a file that it asked for, such as the water's pebble
   * photograph or the splat scan. Returns false if the app does not take
   * files, or refuses these bytes. A module that takes files exports tm_alloc, tm_free and
   * tm_asset, and the bytes cross in its memory.
   */
  asset(bytes) {
    const { exports } = this.library;
    if (!exports.tm_asset) return false;
    const room = address(exports.tm_alloc(bytes.length));
    if (room === 0) return false;
    // A view must be taken after the allocation, which can grow the memory.
    new Uint8Array(this.library.memory.buffer, room, bytes.length).set(bytes);
    const status = exports.tm_asset(this.handle, room, bytes.length);
    exports.tm_free(room);
    return status === 0;
  }

  /**
   * Change the size of the frame, and keep the rest of the app. Returns false
   * if the app does not take a new size, or refuses this one. A module that
   * takes a new size exports tm_resize.
   */
  resize(width, height) {
    const { exports } = this.library;
    if (!exports.tm_resize) return false;
    if (exports.tm_resize(this.handle, width, height) !== 0) return false;
    this.width = width;
    this.height = height;
    return true;
  }

  destroy() {
    this.library.exports.tm_destroy(this.handle);
    this.handle = 0;
  }
}

export class Library {
  /**
   * @param exports  the exports of the instance
   * @param memory   the memory it uses: its own export, or the shared memory it imported
   * @param workers  the workers that run its tasks, if it is threaded
   */
  constructor(exports, memory = exports.memory, workers = []) {
    this.exports = exports;
    this.memory = memory;
    this.workers = workers;
    // A page that is not cross-origin isolated has no SharedArrayBuffer at all.
    this.shared =
      typeof SharedArrayBuffer !== "undefined" && memory instanceof WebAssembly.Memory && memory.buffer instanceof SharedArrayBuffer;
    const version = exports.tm_abi_version();
    if (version !== ABI_VERSION) {
      throw new Error(`The module has ABI ${version}, this page needs ${ABI_VERSION}`);
    }
    exports.tm_init();
  }

  /** Stop the workers of a threaded module. The library is unusable after this. */
  close() {
    for (const worker of this.workers) worker.terminate();
    this.workers = [];
  }

  /** Make an app, or return null if a side is outside 1 to 4096. */
  create(width, height) {
    // tm_create returns its handle as an i64 (a BigInt), and every other
    // function takes it as a 32-bit address, so convert it once.
    const handle = address(this.exports.tm_create(width, height));
    return handle === 0 ? null : new App(this, handle, width, height);
  }
}

async function fetchBytes(source) {
  return typeof source === "string" ? await (await fetch(source)).arrayBuffer() : source;
}

/** Load a module from a URL, or from bytes that are already in hand. */
export async function load(source) {
  const { instance } = await WebAssembly.instantiate(await fetchBytes(source), {});
  return new Library(instance.exports);
}

/** Make a worker from the file next to this one. A page uses this by default. */
function spawnWorker() {
  return new Worker(new URL("./threemojo_worker.js", import.meta.url), { type: "module" });
}

/**
 * What a worker does: run the module on the shared memory, on a stack of its
 * own, and take tasks for as long as the page lives. It never returns.
 */
export function runWorker({ module, memory, stack }) {
  const instance = new WebAssembly.Instance(module, { env: { memory } });
  instance.exports.__stack_pointer.value = stack;
  instance.exports.mw_worker_main();
}

/**
 * Load a module made for many threads. `threads` counts the workers, and the
 * page's own thread works too, so a page that wants every core of an 8-core
 * machine asks for 7. `spawn` makes one worker and is for a host that is not
 * a page, such as Node. It returns an object with postMessage and terminate.
 */
export async function loadThreads(source, { threads, spawn = spawnWorker } = {}) {
  if (!(threads >= 1)) throw new Error("loadThreads needs threads of at least 1");
  const module = await WebAssembly.compile(await fetchBytes(source));
  const memory = new WebAssembly.Memory({ ...MEMORY_PAGES, shared: true });
  const instance = new WebAssembly.Instance(module, { env: { memory } });
  const { exports } = instance;
  const workers = [];
  // The count includes the page's thread, which runs tasks while it waits.
  // Set it before the runtime starts, which asks for the number of cores.
  exports.mw_set_threads(threads + 1);
  try {
    for (let index = 0; index < threads; index++) {
      // mw_stack returns the top of a block, where a stack starts.
      const stack = exports.mw_stack(WORKER_STACK);
      if (stack === 0) throw new Error("The module has no room for the stack of a worker");
      const worker = spawn();
      // Keep it before posting, so a failed post also terminates this worker.
      workers.push(worker);
      worker.postMessage({ module, memory, stack });
    }
    return new Library(exports, memory, workers);
  } catch (error) {
    // A page can fall back to one thread. Do not leave a partial pool holding
    // the shared memory alive after its library failed to start.
    for (const worker of workers) worker.terminate();
    throw error;
  }
}
