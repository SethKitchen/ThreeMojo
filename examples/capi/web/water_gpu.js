// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// The water of window/capi_water.mojo, drawn by a WebGPU device.
//
// The module keeps the simulation, the ocean surface, the caustics and the
// glare's small FFT. Each frame it packs the arrays that the shader reads
// (tm_gpu_prepare). This file writes them to the device and runs the passes of
// water.wgsl: shade, bloom and grade. It shows the picture on a canvas, or
// reads it back for a test.
//
//   const gpu = await requestGpu();                 // null if the browser has none
//   const water = await GpuWater.create(gpu.device, app, shader, { canvas });
//   await water.frame(16667);                       // step, draw, show
//
// The page that holds this file must serve water.wgsl next to it, and give the
// text to `GpuWater.create`.

import { address } from "./threemojo.js";

/** The parts of a prepared frame, as window/capi_abi.mojo numbers them. */
export const Part = {
  SURFACE: 0,
  SURFACE_TABLE: 1,
  RIPPLE: 2,
  CAUSTIC: 3,
  CAUSTIC_TABLE: 4,
  PEBBLE: 5,
  PEBBLE_TABLE: 6,
  VALUES: 7,
  SAMPLES: 8,
  GRID: 9,
};

/** The numbers about a prepared frame. */
export const Info = { RIPPLE_SIDE: 0, GRID_WIDTH: 1, GRID_HEIGHT: 2 };

/**
 * The words of the `meta` buffer, which water.wgsl reads as `frame_words`: the frame
 * values from word 0, the sizes, then the three level tables, each in room that
 * is enough for its levels.
 */
export const Meta = {
  WIDTH: 24,
  HEIGHT: 25,
  RIPPLE_SIDE: 26,
  GRID_WIDTH: 27,
  GRID_HEIGHT: 28,
  SURFACE_TABLE: 32,
  CAUSTIC_TABLE: 96,
  PEBBLE_TABLE: 160,
  WORDS: 256,
  VALUES: 23,
};

const GROUP = 8;

// The bindings that each pass uses. The pipelines have automatic layouts, which
// hold only these, so that no pass counts a buffer that it never reads: a device
// allows eight storage buffers to a pass unless it is asked for more.
const BINDINGS = {
  shade: [0, 1, 2, 3, 4, 5],
  sparks: [4, 5, 8],
  bright: [4, 5, 6],
  blur_h: [4, 6, 7],
  blur_v: [4, 6, 7],
  grade: [4, 5, 6, 9, 10],
};

/**
 * Ask for a device, or return null where the browser has no WebGPU or no
 * adapter. The adapter is the fast one on a machine that has two, as three.js
 * asks for with powerPreference.
 */
export async function requestGpu() {
  if (typeof navigator === "undefined" || !navigator.gpu) return null;
  const adapter = await navigator.gpu.requestAdapter({ powerPreference: "high-performance" });
  if (!adapter) return null;
  const device = await adapter.requestDevice();
  return { adapter, device };
}

export class GpuWater {
  /**
   * Make the passes and the buffers for an app.
   *
   * @param device  a GPUDevice from requestGpu
   * @param app     an App (threemojo.js) of the water module
   * @param shader  the text of water.wgsl
   * @param options `canvas`: a canvas to show the picture on. Without one, the
   *                picture can only be read back. `reuse`: a GpuWater of the
   *                same device and canvas, whose compiled passes this one
   *                takes, so that a new size does not compile them again.
   */
  static async create(device, app, shader, { canvas = null, reuse = null } = {}) {
    const water = new GpuWater(device, app, canvas);
    await water.build(shader, reuse);
    return water;
  }

  constructor(device, app, canvas) {
    this.device = device;
    this.app = app;
    this.exports = app.library.exports;
    this.width = app.width;
    this.height = app.height;
    this.canvas = canvas;
    this.buffers = {};
    this.bed = 0;
    this.errors = [];
  }

  async build(shader, reuse) {
    const { device } = this;
    device.pushErrorScope("validation");
    if (reuse) {
      this.module = reuse.module;
      this.pipelines = reuse.pipelines;
      this.errors = reuse.errors;
    } else {
      device.addEventListener("uncapturederror", (event) => {
        this.errors.push(event.error.message);
        console.error(event.error.message);
      });
      const module = device.createShaderModule({ code: shader });
      const info = await module.getCompilationInfo();
      const problems = info.messages.filter((message) => message.type === "error");
      if (problems.length > 0) {
        await device.popErrorScope();
        throw new Error(
          "water.wgsl does not compile:\n" +
            problems.map((message) => `${message.lineNum}:${message.linePos} ${message.message}`).join("\n"),
        );
      }
      this.module = module;
      this.pipelines = {};
      for (const entry of Object.keys(BINDINGS)) {
        this.pipelines[entry] = await device.createComputePipelineAsync({
          layout: "auto",
          compute: { module, entryPoint: entry },
        });
      }
    }
    this.picture = device.createTexture({
      size: [this.width, this.height],
      format: "rgba8unorm",
      usage: GPUTextureUsage.STORAGE_BINDING | GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_SRC,
    });
    this.meta = new Uint32Array(Meta.WORDS);
    this.metaFloats = new Float32Array(this.meta.buffer);
    this.buffer("meta", Meta.WORDS * 4, GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST);
    const pixels = this.width * this.height * 3 * 4;
    const scratch = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST | GPUBufferUsage.COPY_SRC;
    this.buffer("radiance", pixels, scratch);
    this.buffer("bloom_a", pixels, scratch);
    this.buffer("bloom_b", pixels, scratch);
    if (this.canvas) await this.buildPresentation(reuse);
    const failure = await device.popErrorScope();
    if (failure) throw new Error(`WebGPU rejected the water passes: ${failure.message}`);
  }

  async buildPresentation(reuse) {
    const { device, canvas, module } = this;
    if (reuse?.blit) {
      ({ context: this.context, blit: this.blit, sampler: this.sampler } = reuse);
    } else {
      this.context = canvas.getContext("webgpu");
      const format = navigator.gpu.getPreferredCanvasFormat();
      // The frames are opaque, so the page need not blend them with anything.
      this.context.configure({ device, format, alphaMode: "opaque" });
      this.blit = await device.createRenderPipelineAsync({
        layout: "auto",
        vertex: { module, entryPoint: "blit_vertex" },
        fragment: { module, entryPoint: "blit_fragment", targets: [{ format }] },
        primitive: { topology: "triangle-list" },
      });
      this.sampler = device.createSampler({ magFilter: "linear", minFilter: "linear" });
    }
    this.blitGroup = device.createBindGroup({
      layout: this.blit.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: this.picture.createView() },
        { binding: 1, resource: this.sampler },
      ],
    });
  }

  /** A buffer that is made again when more room is wanted, never less. */
  buffer(name, bytes, usage) {
    const have = this.buffers[name];
    if (have && have.size >= bytes) return have;
    if (have) have.destroy();
    const made = this.device.createBuffer({ size: Math.max(16, Math.ceil(bytes / 4) * 4), usage, label: name });
    this.buffers[name] = made;
    this.groups = null;
    return made;
  }

  /** The words of a part of the prepared frame, in the module's memory now. */
  words(part, Type = Float32Array) {
    const { exports, app } = this;
    const count = exports.tm_gpu_words(app.handle, part);
    if (count === 0) return new Type(0);
    // A view must be taken after the call: the memory may have grown.
    const at = address(exports.tm_gpu_part(app.handle, part));
    return new Type(app.library.memory.buffer, at, count);
  }

  /** Write a part to a buffer, making the buffer if it is new or too small. */
  upload(name, part, usage = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST) {
    const data = this.words(part);
    const buffer = this.buffer(name, data.byteLength, usage);
    this.device.queue.writeBuffer(buffer, 0, data);
  }

  fillMeta() {
    const { exports, app, meta } = this;
    meta.fill(0);
    this.metaFloats.set(this.words(Part.VALUES).subarray(0, Meta.VALUES), 0);
    meta[Meta.WIDTH] = this.width;
    meta[Meta.HEIGHT] = this.height;
    meta[Meta.RIPPLE_SIDE] = exports.tm_gpu_info(app.handle, Info.RIPPLE_SIDE);
    meta[Meta.GRID_WIDTH] = this.gridWidth;
    meta[Meta.GRID_HEIGHT] = this.gridHeight;
    for (const [part, base, room] of [
      [Part.SURFACE_TABLE, Meta.SURFACE_TABLE, 64],
      [Part.CAUSTIC_TABLE, Meta.CAUSTIC_TABLE, 64],
      [Part.PEBBLE_TABLE, Meta.PEBBLE_TABLE, 96],
    ]) {
      const table = this.words(part, Uint32Array);
      if (table.length > room) throw new Error(`The level table of part ${part} has ${table.length} words, room for ${room}`);
      meta.set(table, base);
    }
    this.device.queue.writeBuffer(this.buffers.meta, 0, meta);
  }

  /** The bind groups of the passes, made again when a buffer was. */
  bindGroups() {
    if (this.groups) return this.groups;
    const sources = {
      0: this.buffers.surface,
      1: this.buffers.ripple,
      2: this.buffers.caustic,
      3: this.buffers.pebble,
      4: this.buffers.meta,
      5: this.buffers.radiance,
      6: this.buffers.bloom_a,
      7: this.buffers.bloom_b,
      8: this.buffers.samples,
      9: this.buffers.grid,
    };
    this.groups = {};
    for (const [entry, bindings] of Object.entries(BINDINGS)) {
      this.groups[entry] = this.device.createBindGroup({
        layout: this.pipelines[entry].getBindGroupLayout(0),
        entries: bindings.map((binding) => ({
          binding,
          resource: binding === 10 ? this.picture.createView() : { buffer: sources[binding] },
        })),
      });
    }
    return this.groups;
  }

  pass(encoder, entry, x, y) {
    const pass = encoder.beginComputePass();
    pass.setPipeline(this.pipelines[entry]);
    pass.setBindGroup(0, this.bindGroups()[entry]);
    pass.dispatchWorkgroups(Math.ceil(x / GROUP), Math.ceil(y / GROUP));
    pass.end();
  }

  /**
   * Move the app on by a time, and draw it: the whole frame, on the device.
   * Returns the milliseconds that the module and the device took.
   */
  async frame(microseconds) {
    const { device, exports, app } = this;
    const start = performance.now();
    app.step(microseconds);
    const bed = exports.tm_gpu_prepare(app.handle);
    // A frame that cannot be prepared is drawn again from the arrays of the last.
    if (bed < 0 && this.bed === 0) throw new Error("The water cannot be prepared");
    if (bed >= 0) {
      this.upload("surface", Part.SURFACE);
      this.upload("ripple", Part.RIPPLE);
      this.upload("caustic", Part.CAUSTIC);
      if (bed !== this.bed) {
        this.upload("pebble", Part.PEBBLE);
        this.bed = bed;
      }
      this.gridWidth = exports.tm_gpu_info(app.handle, Info.GRID_WIDTH);
      this.gridHeight = exports.tm_gpu_info(app.handle, Info.GRID_HEIGHT);
      const grid = this.gridWidth * this.gridHeight * 3 * 4;
      this.buffer("samples", grid, GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC);
      this.buffer("grid", grid, GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST);
      this.readback ??= device.createBuffer({ size: Math.max(16, grid), usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
      if (this.readback.size < grid) {
        this.readback.destroy();
        this.readback = device.createBuffer({ size: grid, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST });
      }
      this.fillMeta();
    }
    const grid = this.gridWidth * this.gridHeight * 3 * 4;

    // The shading, the glints for the glare, and the bloom.
    const first = device.createCommandEncoder();
    this.pass(first, "shade", this.width, this.height);
    this.pass(first, "sparks", this.gridWidth, this.gridHeight);
    first.copyBufferToBuffer(this.buffers.samples, 0, this.readback, 0, grid);
    this.pass(first, "bright", this.width, this.height);
    this.pass(first, "blur_h", this.width, this.height);
    this.pass(first, "blur_v", this.width, this.height);
    device.queue.submit([first.finish()]);

    // The glare is one small FFT, in the module. The device blurs the bloom
    // meanwhile.
    await this.readback.mapAsync(GPUMapMode.READ, 0, grid);
    this.words(Part.SAMPLES).set(new Float32Array(this.readback.getMappedRange(0, grid)));
    this.readback.unmap();
    if (exports.tm_gpu_glare(app.handle) !== 0) throw new Error("The glare cannot be made");
    device.queue.writeBuffer(this.buffers.grid, 0, this.words(Part.GRID));

    const second = device.createCommandEncoder();
    this.pass(second, "grade", this.width, this.height);
    if (this.context) {
      const view = this.context.getCurrentTexture().createView();
      const draw = second.beginRenderPass({
        colorAttachments: [{ view, loadOp: "clear", storeOp: "store", clearValue: { r: 0, g: 0, b: 0, a: 1 } }],
      });
      draw.setPipeline(this.blit);
      draw.setBindGroup(0, this.blitGroup);
      draw.draw(3);
      draw.end();
    }
    device.queue.submit([second.finish()]);
    return performance.now() - start;
  }

  /** Wait for the device to finish, so that a time is the time of the work. */
  async idle() {
    await this.device.queue.onSubmittedWorkDone();
  }

  /** The picture of the last frame as RGBA bytes, row by row from the top. */
  async readPixels() {
    const { device, width, height } = this;
    const bytesPerRow = Math.ceil((width * 4) / 256) * 256;
    const copy = device.createBuffer({ size: bytesPerRow * height, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
    const encoder = device.createCommandEncoder();
    encoder.copyTextureToBuffer({ texture: this.picture }, { buffer: copy, bytesPerRow }, [width, height]);
    device.queue.submit([encoder.finish()]);
    await copy.mapAsync(GPUMapMode.READ);
    const rows = new Uint8Array(copy.getMappedRange());
    const pixels = new Uint8ClampedArray(width * height * 4);
    for (let row = 0; row < height; row++) {
      pixels.set(rows.subarray(row * bytesPerRow, row * bytesPerRow + width * 4), row * width * 4);
    }
    copy.unmap();
    copy.destroy();
    return pixels;
  }

  /** Free the device's memory. The app belongs to the caller. */
  destroy() {
    for (const buffer of Object.values(this.buffers)) buffer.destroy();
    this.readback?.destroy();
    this.picture.destroy();
    this.buffers = {};
  }
}

/** The class that a page makes for a GPU: the same name in every driver. */
export { GpuWater as GpuApp };
