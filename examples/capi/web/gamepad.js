// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// The page's half of the gamepad module (window/capi_gamepad.mojo).
//
//   const pads = new Gamepads(library, app);   // app from library.create
//   // each frame, before app.step:
//   pads.poll();
//   pads.axis(index, Axis.LEFTX);              // -32768 to 32767
//   pads.button(index, Button.SOUTH);          // true while down
//   pads.rumble(index, 0xffff, 0x8000, 250);   // low, high, milliseconds
//
// Mojo cannot reach the browser's Gamepad API, so this reads
// navigator.getGamepads() each frame and gives the module each pad's
// state. The module runs SDL's browser joystick driver and SDL's Standard
// Gamepad mapping, and asks the page to play each rumble.

/** SDL's gamepad axes, as tm_gamepad_axis numbers them. */
export const Axis = { LEFTX: 0, LEFTY: 1, RIGHTX: 2, RIGHTY: 3, LEFT_TRIGGER: 4, RIGHT_TRIGGER: 5 };

/** SDL's gamepad buttons, by position, as tm_gamepad_button numbers them. */
export const Button = {
  SOUTH: 0,
  EAST: 1,
  WEST: 2,
  NORTH: 3,
  BACK: 4,
  GUIDE: 5,
  START: 6,
  LEFT_STICK: 7,
  RIGHT_STICK: 8,
  LEFT_SHOULDER: 9,
  RIGHT_SHOULDER: 10,
  DPAD_UP: 11,
  DPAD_DOWN: 12,
  DPAD_LEFT: 13,
  DPAD_RIGHT: 14,
};

/** SDL plays each rumble for 3 seconds and sends it again every 2 seconds. */
const RUMBLE_MS = 3000;

export class Gamepads {
  /**
   * @param library  a Library from threemojo.js, of threemojo_gamepad.wasm
   * @param app      an App that the library made
   * @param source   what has getGamepads(): navigator, or a test's stand-in
   */
  constructor(library, app, source = globalThis.navigator) {
    this.exports = library.exports;
    this.memory = library.memory;
    this.handle = app.handle;
    this.source = source;
    this.connected = new Map();
    this.encoder = new TextEncoder();
  }

  /** Connect a pad, copying its id into the module's memory. */
  connect(pad) {
    const { exports } = this;
    const id = this.encoder.encode(pad.id).subarray(0, 1024);
    const room = id.length > 0 ? exports.tm_alloc(id.length) : 0;
    const address = Number(BigInt.asUintN(32, BigInt(room)));
    if (id.length > 0) new Uint8Array(this.memory.buffer, address, id.length).set(id);
    const rumble = pad.vibrationActuator ? 1 : 0;
    const added = exports.tm_gamepad_connect(this.handle, pad.index, address, id.length, pad.axes.length, pad.buttons.length, rumble);
    if (id.length > 0) exports.tm_free(address);
    if (added) this.connected.set(pad.index, pad);
  }

  /** Read every pad, and play the rumble the module asks for. */
  poll() {
    const { exports, handle } = this;
    const pads = this.source?.getGamepads?.() ?? [];
    const seen = new Set();
    for (const pad of pads) {
      if (!pad || !pad.connected) continue;
      seen.add(pad.index);
      if (!this.connected.has(pad.index)) this.connect(pad);
      if (!this.connected.has(pad.index)) continue;
      this.connected.set(pad.index, pad);
      pad.axes.forEach((value, axis) => exports.tm_gamepad_set_axis(handle, pad.index, axis, value));
      pad.buttons.forEach((button, index) =>
        exports.tm_gamepad_set_button(handle, pad.index, index, button.pressed ? 1 : 0, button.value),
      );
      exports.tm_gamepad_sample(handle, pad.index, pad.timestamp ?? 0);
      if (exports.tm_gamepad_take_rumble(handle, pad.index)) {
        // SDL's effect: the low motor is the weak magnitude, as SDL sends it.
        pad.vibrationActuator?.playEffect("dual-rumble", {
          startDelay: 0,
          duration: RUMBLE_MS,
          weakMagnitude: exports.tm_gamepad_rumble_strength(handle, 0) / 0xffff,
          strongMagnitude: exports.tm_gamepad_rumble_strength(handle, 1) / 0xffff,
        });
      }
    }
    for (const index of [...this.connected.keys()]) {
      if (seen.has(index)) continue;
      exports.tm_gamepad_disconnect(handle, index);
      this.connected.delete(index);
    }
  }

  /** The pads connected now, by their Gamepad.index. */
  indices() {
    return [...this.connected.keys()];
  }

  axis(index, axis) {
    return this.exports.tm_gamepad_axis(this.handle, index, axis);
  }

  button(index, button) {
    return this.exports.tm_gamepad_button(this.handle, index, button) !== 0;
  }

  rumble(index, low, high, milliseconds) {
    return this.exports.tm_gamepad_rumble(this.handle, index, low, high, milliseconds) !== 0;
  }
}
