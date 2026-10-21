// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// The splats of window/capi_splat.mojo, drawn by a WebGPU device.
//
// The module keeps the scan, the camera and the controls, and it sorts the
// splats back to front when the view has turned far enough (tm_splat_prepare).
// This file puts the scan on the device once, and each frame writes the draw
// order, when it changed, and the view. The passes of splat.wgsl project and
// shade every splat, blend the quads in the draw order, and show the picture on
// a canvas or keep it for a test.
//
//   const gpu = await requestGpu();                 // null if the browser has none
//   const splats = await GpuSplat.create(gpu.device, app, shader, { canvas });
//   await splats.frame(16667);                      // step, draw, show
//
// The page that holds this file must serve splat.wgsl next to it, and give the
// text to `GpuSplat.create`.

import { address } from "./threemojo.js";

/** The parts of a scan, as window/capi_abi.mojo numbers them. */
export const Part = { CENTERS: 0, COVARIANCES: 1, COLORS: 2, SH1: 3, SH2: 4, SH3: 5, ORDER: 6, VIEW: 7 };

/** The numbers about a scan. */
export const Info = { COUNT: 0, DEGREE: 1, SCAN: 2, ORDER: 3 };

/** The floats of the view part, and where its background is. */
export const View = { FLOATS: 48, BACKGROUND: 40 };

const GROUP = 64;
const PICTURE_FORMAT = "rgba16float";
const SHOWN_FORMAT = "rgba8unorm";
// The background before there is a view to read it from: the example's 0x07080f.
const BACKGROUND = [7 / 255, 8 / 255, 15 / 255];
// Source-over with straight alpha, which keeps the picture opaque.
const BLEND = {
  color: { srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha", operation: "add" },
  alpha: { srcFactor: "zero", dstFactor: "one", operation: "add" },
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

export class GpuSplat {
  /**
   * Make the passes for an app.
   *
   * @param device  a GPUDevice from requestGpu
   * @param app     an App (threemojo.js) of the splat module
   * @param shader  the text of splat.wgsl
   * @param options `canvas`: a canvas to show the picture on. Without one, the
   *                picture can only be read back. `reuse`: a GpuSplat of the
   *                same device and canvas, whose compiled passes this one
   *                takes, so that a new size does not compile them again.
   */
  static async create(device, app, shader, { canvas = null, reuse = null } = {}) {
    const splats = new GpuSplat(device, app, canvas);
    await splats.build(shader, reuse);
    return splats;
  }

  constructor(device, app, canvas) {
    this.device = device;
    this.app = app;
    this.exports = app.library.exports;
    this.width = app.width;
    this.height = app.height;
    this.canvas = canvas;
    this.buffers = {};
    this.scan = 0;
    this.sorted = 0;
    this.count = 0;
    this.errors = [];
  }

  async build(shader, reuse) {
    const { device } = this;
    device.pushErrorScope("validation");
    if (reuse) {
      this.module = reuse.module;
      this.errors = reuse.errors;
      this.pipelines = { project: reuse.pipelines.project, draw: reuse.pipelines.draw };
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
          "splat.wgsl does not compile:\n" +
            problems.map((message) => `${message.lineNum}:${message.linePos} ${message.message}`).join("\n"),
        );
      }
      this.module = module;
      this.pipelines = {
        project: await device.createComputePipelineAsync({
          layout: "auto",
          compute: { module, entryPoint: "project" },
        }),
        draw: await device.createRenderPipelineAsync({
          layout: "auto",
          vertex: { module, entryPoint: "splat_vertex" },
          fragment: { module, entryPoint: "splat_fragment", targets: [{ format: PICTURE_FORMAT, blend: BLEND }] },
          primitive: { topology: "triangle-strip" },
        }),
      };
    }
    // The last pass writes to a canvas, or to a picture that a test reads. A
    // device that was used for one cannot take the other's pass.
    if (reuse && Boolean(reuse.context) === Boolean(this.canvas)) {
      this.context = reuse.context;
      this.format = reuse.format;
      this.pipelines.resolve = reuse.pipelines.resolve;
    } else {
      this.format = this.canvas ? navigator.gpu.getPreferredCanvasFormat() : SHOWN_FORMAT;
      if (this.canvas) {
        this.context = this.canvas.getContext("webgpu");
        // The picture is opaque, so the page need not blend it with anything.
        this.context.configure({ device, format: this.format, alphaMode: "opaque" });
      }
      this.pipelines.resolve = await device.createRenderPipelineAsync({
        layout: "auto",
        vertex: { module: this.module, entryPoint: "resolve_vertex" },
        fragment: { module: this.module, entryPoint: "resolve_fragment", targets: [{ format: this.format }] },
        primitive: { topology: "triangle-list" },
      });
    }
    this.buildTargets();
    this.buffer("view", View.FLOATS * 4, GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST);
    const failure = await device.popErrorScope();
    if (failure) throw new Error(`WebGPU rejected the splat passes: ${failure.message}`);
  }

  /** The pictures for the size: the blended one, and the one that is read back. */
  buildTargets() {
    const { device, width, height } = this;
    this.picture?.destroy();
    this.shown?.destroy();
    this.picture = device.createTexture({
      size: [width, height],
      format: PICTURE_FORMAT,
      usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    });
    this.shown = this.canvas
      ? null
      : device.createTexture({
          size: [width, height],
          format: SHOWN_FORMAT,
          usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC,
        });
    this.resolveGroup = device.createBindGroup({
      layout: this.pipelines.resolve.getBindGroupLayout(0),
      entries: [{ binding: 10, resource: this.picture.createView() }],
    });
  }

  /** A buffer that is made again when its size changes. */
  buffer(name, bytes, usage) {
    const size = Math.max(16, Math.ceil(bytes / 4) * 4);
    const have = this.buffers[name];
    if (have && have.size === size) return have;
    have?.destroy();
    const made = this.device.createBuffer({ size, usage, label: name });
    this.buffers[name] = made;
    this.groups = null;
    return made;
  }

  /** The words of a part of the scan, in the module's memory now. */
  words(part, Type = Float32Array) {
    const { exports, app } = this;
    const count = exports.tm_splat_words(app.handle, part);
    if (count === 0) return new Type(0);
    // A view must be taken after the call: the memory may have grown.
    const at = address(exports.tm_splat_part(app.handle, part));
    return new Type(app.library.memory.buffer, at, count);
  }

  /** Write a part to a buffer. A band that the scan lacks leaves a buffer that no thread reads. */
  upload(name, part, Type = Float32Array) {
    const data = this.words(part, Type);
    const usage = GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST;
    const buffer = this.buffer(name, data.byteLength, usage);
    if (data.byteLength > 0) this.device.queue.writeBuffer(buffer, 0, data);
  }

  /** Put a new scan on the device: its arrays, and room for what the passes make. */
  loadScan() {
    const { exports, app, device } = this;
    this.count = exports.tm_splat_info(app.handle, Info.COUNT);
    const projected = this.count * 3 * 16;
    const limit = device.limits.maxStorageBufferBindingSize;
    if (projected > limit) {
      throw new Error(`${this.count} splats need ${projected} bytes of projected splats, and the device allows ${limit}`);
    }
    this.upload("centers", Part.CENTERS);
    this.upload("covariances", Part.COVARIANCES);
    this.upload("colors", Part.COLORS, Uint32Array);
    this.upload("sh1", Part.SH1, Uint32Array);
    this.upload("sh2", Part.SH2, Uint32Array);
    this.upload("sh3", Part.SH3, Uint32Array);
    this.buffer("order", this.count * 4, GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST);
    this.buffer("projected", projected, GPUBufferUsage.STORAGE);
    this.scan = exports.tm_splat_info(app.handle, Info.SCAN);
    // A new scan has no order on the device yet.
    this.sorted = 0;
  }

  /** The bind groups of the passes, made again when a buffer was. */
  bindGroups() {
    if (this.groups) return this.groups;
    const { device, pipelines, buffers } = this;
    const entry = (binding, buffer) => ({ binding, resource: { buffer } });
    this.groups = {
      project: device.createBindGroup({
        layout: pipelines.project.getBindGroupLayout(0),
        entries: [
          entry(0, buffers.view),
          entry(1, buffers.centers),
          entry(2, buffers.covariances),
          entry(3, buffers.colors),
          entry(4, buffers.sh1),
          entry(5, buffers.sh2),
          entry(6, buffers.sh3),
          entry(7, buffers.order),
          entry(8, buffers.projected),
        ],
      }),
      draw: device.createBindGroup({
        layout: pipelines.draw.getBindGroupLayout(0),
        entries: [entry(0, buffers.view), entry(9, buffers.projected)],
      }),
    };
    return this.groups;
  }

  /**
   * Move the app on by a time, and draw it: the whole frame, on the device.
   * Returns the milliseconds that the module and the device took.
   */
  async frame(microseconds) {
    const { device, exports, app } = this;
    const start = performance.now();
    app.step(microseconds);
    const ready = exports.tm_splat_prepare(app.handle) === 0;
    let background = BACKGROUND;
    if (ready) {
      if (exports.tm_splat_info(app.handle, Info.SCAN) !== this.scan) this.loadScan();
      const order = exports.tm_splat_info(app.handle, Info.ORDER);
      if (order !== this.sorted) {
        const indices = this.words(Part.ORDER, Uint32Array);
        // A missed copy must stay stale, so the next frame tries again.
        if (indices.byteLength === this.buffers.order.size) {
          device.queue.writeBuffer(this.buffers.order, 0, indices);
          this.sorted = order;
        }
      }
      const view = this.words(Part.VIEW);
      device.queue.writeBuffer(this.buffers.view, 0, view);
      background = Array.from(view.subarray(View.BACKGROUND, View.BACKGROUND + 3));
    }

    const encoder = device.createCommandEncoder();
    if (ready) {
      const project = encoder.beginComputePass();
      project.setPipeline(this.pipelines.project);
      project.setBindGroup(0, this.bindGroups().project);
      project.dispatchWorkgroups(Math.ceil(this.count / GROUP));
      project.end();
    }
    const blend = encoder.beginRenderPass({
      colorAttachments: [
        {
          view: this.picture.createView(),
          loadOp: "clear",
          storeOp: "store",
          clearValue: { r: background[0], g: background[1], b: background[2], a: 1 },
        },
      ],
    });
    if (ready) {
      blend.setPipeline(this.pipelines.draw);
      blend.setBindGroup(0, this.bindGroups().draw);
      blend.draw(4, this.count);
    }
    blend.end();
    const target = this.context ? this.context.getCurrentTexture() : this.shown;
    const resolve = encoder.beginRenderPass({
      colorAttachments: [{ view: target.createView(), loadOp: "clear", storeOp: "store", clearValue: { r: 0, g: 0, b: 0, a: 1 } }],
    });
    resolve.setPipeline(this.pipelines.resolve);
    resolve.setBindGroup(0, this.resolveGroup);
    resolve.draw(3);
    resolve.end();
    device.queue.submit([encoder.finish()]);
    // The time of the frame is the time of the work, not of the queue.
    await device.queue.onSubmittedWorkDone();
    return performance.now() - start;
  }

  /** Change the size of the frame. The scan and the view stay. */
  resize(width, height) {
    if (!this.app.resize(width, height)) throw new Error(`The module refused a ${width}x${height} frame`);
    this.width = width;
    this.height = height;
    this.buildTargets();
  }

  /** Wait for the device to finish, so that a time is the time of the work. */
  async idle() {
    await this.device.queue.onSubmittedWorkDone();
  }

  /** The picture of the last frame as RGBA bytes, row by row from the top. Not with a canvas. */
  async readPixels() {
    const { device, width, height } = this;
    if (!this.shown) throw new Error("A picture on a canvas cannot be read back");
    const bytesPerRow = Math.ceil((width * 4) / 256) * 256;
    const copy = device.createBuffer({ size: bytesPerRow * height, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
    const encoder = device.createCommandEncoder();
    encoder.copyTextureToBuffer({ texture: this.shown }, { buffer: copy, bytesPerRow }, [width, height]);
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
    this.picture?.destroy();
    this.shown?.destroy();
    this.buffers = {};
  }
}

/** The class that a page makes for a GPU: the same name in every driver. */
export { GpuSplat as GpuApp };
