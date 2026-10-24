/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * Gamepads on macOS for the gamepad library (window/capi_gamepad.mojo).
 *
 * macOS gives a program its controllers through the GameController
 * framework: Xbox, PlayStation, Switch Pro and MFi controllers, on USB and
 * Bluetooth. macos_gamepad.m reads each one in the browser's standard
 * layout, 17 buttons and 4 axes, and gives the library its state each frame,
 * as examples/capi/web/gamepad.js does in a browser. The library maps the
 * pads with SDL's Standard Gamepad mapping, and asks for rumble, which this
 * code plays with Core Haptics.
 */
#ifndef THREEMOJO_MACOS_GAMEPAD_H
#define THREEMOJO_MACOS_GAMEPAD_H

#include <stdbool.h>
#include <stdint.h>

#include "threemojo.h"

#ifdef __cplusplus
extern "C" {
#endif

/* The gamepad functions of the library. A library without all of them gets
 * no gamepads. */
typedef struct {
  int32_t (*connect)(tm_app *, int32_t, const uint8_t *, int32_t, int32_t, int32_t, int32_t);
  int32_t (*disconnect)(tm_app *, int32_t);
  void (*set_axis)(tm_app *, int32_t, int32_t, double);
  void (*set_button)(tm_app *, int32_t, int32_t, int32_t, double);
  int32_t (*sample)(tm_app *, int32_t, double);
  int32_t (*button)(tm_app *, int32_t, int32_t);
  int32_t (*rumble)(tm_app *, int32_t, int32_t, int32_t, int32_t);
  int32_t (*take_rumble)(tm_app *, int32_t);
  int32_t (*rumble_strength)(tm_app *, int32_t);
} GamepadApi;

typedef struct GamepadFeed GamepadFeed;

/* Look up the gamepad functions in a library. Returns false when one is
 * missing. */
bool gamepad_api_bind(GamepadApi *api, void *library);

/* Start watching the controllers. */
GamepadFeed *gamepad_feed_create(const GamepadApi *api);

/* Give the app each controller's state, connect and disconnect them, and
 * play the rumble the app asks for. Call it before each tm_step. With demo
 * set, a held south button rumbles its pad, as the web page does. */
void gamepad_feed_poll(GamepadFeed *feed, tm_app *app, bool demo);

/* Stop the rumble and free the feed. */
void gamepad_feed_destroy(GamepadFeed *feed);

#ifdef __cplusplus
}
#endif

#endif
