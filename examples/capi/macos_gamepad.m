/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * Gamepads on macOS, through the GameController framework. See
 * macos_gamepad.h.
 *
 * Each frame, each controller with an extended gamepad profile is read in
 * the browser's standard layout:
 *
 *   buttons  0 A  1 B  2 X  3 Y  4 left shoulder  5 right shoulder
 *            6 left trigger  7 right trigger  8 options  9 menu
 *            10 left stick  11 right stick  12-15 d-pad up, down, left,
 *            right  16 home
 *   axes     0 left x  1 left y  2 right x  3 right y, down positive
 *
 * GameController names the face buttons by position on every controller,
 * so A is the bottom button of a Switch Pro controller too. The library
 * maps the layout with SDL's Standard Gamepad mapping.
 */
#import <CoreHaptics/CoreHaptics.h>
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#include <dlfcn.h>

#include "macos_gamepad.h"

#define STANDARD_BUTTONS 17
#define STANDARD_AXES 4
/* SDL plays each rumble of the browser driver for 3 seconds, and sends it
 * again every 2 seconds while it lasts. */
#define RUMBLE_SECONDS 3.0

/* One controller that the app knows, and its haptics. */
@interface TMPad : NSObject
@property(nonatomic, strong) GCController *controller;
@property(nonatomic) int32_t index;
@property(nonatomic, strong) CHHapticEngine *engine;
@property(nonatomic, strong) id<CHHapticPatternPlayer> player;
@end

@implementation TMPad
@end

@interface TMGamepadFeed : NSObject {
 @public
  GamepadApi api;
}
@property(nonatomic, strong) NSMutableArray<TMPad *> *pads;
@property(nonatomic) int32_t nextIndex;
@end

@implementation TMGamepadFeed
@end

bool gamepad_api_bind(GamepadApi *api, void *library) {
  api->connect = dlsym(library, "tm_gamepad_connect");
  api->disconnect = dlsym(library, "tm_gamepad_disconnect");
  api->set_axis = dlsym(library, "tm_gamepad_set_axis");
  api->set_button = dlsym(library, "tm_gamepad_set_button");
  api->sample = dlsym(library, "tm_gamepad_sample");
  api->button = dlsym(library, "tm_gamepad_button");
  api->rumble = dlsym(library, "tm_gamepad_rumble");
  api->take_rumble = dlsym(library, "tm_gamepad_take_rumble");
  api->rumble_strength = dlsym(library, "tm_gamepad_rumble_strength");
  return api->connect && api->disconnect && api->set_axis && api->set_button && api->sample &&
         api->button && api->rumble && api->take_rumble && api->rumble_strength;
}

GamepadFeed *gamepad_feed_create(const GamepadApi *api) {
  TMGamepadFeed *feed = [[TMGamepadFeed alloc] init];
  feed->api = *api;
  feed.pads = [NSMutableArray array];
  /* The window may not be in front: read the controllers anyway. */
  GCController.shouldMonitorBackgroundEvents = YES;
  [GCController startWirelessControllerDiscoveryWithCompletionHandler:nil];
  return (GamepadFeed *)CFBridgingRetain(feed);
}

/* The id the browser would give: the maker and the kind of controller. */
static NSString *pad_id(GCController *controller) {
  NSString *name = controller.vendorName ?: @"Controller";
  return [NSString stringWithFormat:@"%@ (%@)", name, controller.productCategory];
}

static void connect_pad(TMGamepadFeed *feed, tm_app *app, GCController *controller) {
  NSData *bytes = [pad_id(controller) dataUsingEncoding:NSUTF8StringEncoding];
  TMPad *pad = [[TMPad alloc] init];
  pad.controller = controller;
  pad.index = feed.nextIndex++;
  pad.engine = [controller.haptics createEngineWithLocality:GCHapticsLocalityDefault];
  int32_t rumble = pad.engine ? 1 : 0;
  if (feed->api.connect(app, pad.index, bytes.bytes, (int32_t)bytes.length, STANDARD_AXES,
                        STANDARD_BUTTONS, rumble)) {
    [feed.pads addObject:pad];
  }
}

static void stop_rumble(TMPad *pad) {
  [pad.player stopAtTime:CHHapticTimeImmediate error:nil];
  pad.player = nil;
}

static void set_button(TMGamepadFeed *feed, tm_app *app, int32_t index, int32_t button,
                       GCControllerButtonInput *input) {
  float value = input ? input.value : 0.0f;
  int32_t pressed = input && input.isPressed ? 1 : 0;
  feed->api.set_button(app, index, button, pressed, value);
}

/* Give the app one controller's state in the standard layout. */
static void sample(TMGamepadFeed *feed, tm_app *app, TMPad *pad) {
  GCExtendedGamepad *gamepad = pad.controller.extendedGamepad;
  int32_t index = pad.index;
  set_button(feed, app, index, 0, gamepad.buttonA);
  set_button(feed, app, index, 1, gamepad.buttonB);
  set_button(feed, app, index, 2, gamepad.buttonX);
  set_button(feed, app, index, 3, gamepad.buttonY);
  set_button(feed, app, index, 4, gamepad.leftShoulder);
  set_button(feed, app, index, 5, gamepad.rightShoulder);
  set_button(feed, app, index, 6, gamepad.leftTrigger);
  set_button(feed, app, index, 7, gamepad.rightTrigger);
  set_button(feed, app, index, 8, gamepad.buttonOptions);
  set_button(feed, app, index, 9, gamepad.buttonMenu);
  set_button(feed, app, index, 10, gamepad.leftThumbstickButton);
  set_button(feed, app, index, 11, gamepad.rightThumbstickButton);
  set_button(feed, app, index, 12, gamepad.dpad.up);
  set_button(feed, app, index, 13, gamepad.dpad.down);
  set_button(feed, app, index, 14, gamepad.dpad.left);
  set_button(feed, app, index, 15, gamepad.dpad.right);
  set_button(feed, app, index, 16, gamepad.buttonHome);
  /* GameController's y axes point up; the browser's point down. */
  feed->api.set_axis(app, index, 0, gamepad.leftThumbstick.xAxis.value);
  feed->api.set_axis(app, index, 1, -gamepad.leftThumbstick.yAxis.value);
  feed->api.set_axis(app, index, 2, gamepad.rightThumbstick.xAxis.value);
  feed->api.set_axis(app, index, 3, -gamepad.rightThumbstick.yAxis.value);
  /* A timestamp of 0 makes the library compare every value, as SDL does. */
  feed->api.sample(app, index, 0.0);
}

/* Play the stronger motor of a rumble on the controller's haptics. */
static void play_rumble(TMPad *pad, int32_t low, int32_t high) {
  stop_rumble(pad);
  float strength = (float)MAX(low, high) / 65535.0f;
  if (!pad.engine || strength <= 0.0f) return;
  NSError *error = nil;
  if (![pad.engine startAndReturnError:&error]) return;
  CHHapticEventParameter *intensity =
      [[CHHapticEventParameter alloc] initWithParameterID:CHHapticEventParameterIDHapticIntensity
                                                    value:strength];
  CHHapticEvent *event = [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticContinuous
                                                       parameters:@[ intensity ]
                                                     relativeTime:0
                                                         duration:RUMBLE_SECONDS];
  CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:@[ event ]
                                                          parameters:@[]
                                                               error:&error];
  if (!pattern) return;
  pad.player = [pad.engine createPlayerWithPattern:pattern error:&error];
  [pad.player startAtTime:CHHapticTimeImmediate error:&error];
}

void gamepad_feed_poll(GamepadFeed *handle, tm_app *app, bool demo) {
  @autoreleasepool {
    TMGamepadFeed *feed = (__bridge TMGamepadFeed *)handle;
    NSArray<GCController *> *controllers = GCController.controllers;
    for (NSInteger at = (NSInteger)feed.pads.count - 1; at >= 0; at--) {
      TMPad *pad = feed.pads[(NSUInteger)at];
      if ([controllers containsObject:pad.controller]) continue;
      feed->api.disconnect(app, pad.index);
      stop_rumble(pad);
      [pad.engine stopWithCompletionHandler:nil];
      [feed.pads removeObjectAtIndex:(NSUInteger)at];
    }
    for (GCController *controller in controllers) {
      if (!controller.extendedGamepad) continue;
      BOOL known = NO;
      for (TMPad *pad in feed.pads) known = known || pad.controller == controller;
      if (!known) connect_pad(feed, app, controller);
    }
    for (TMPad *pad in feed.pads) {
      sample(feed, app, pad);
      if (demo && feed->api.button(app, pad.index, 0)) {
        feed->api.rumble(app, pad.index, 0xffff, 0x8000, 200);
      }
      if (feed->api.take_rumble(app, pad.index)) {
        play_rumble(pad, feed->api.rumble_strength(app, 0), feed->api.rumble_strength(app, 1));
      }
    }
  }
}

void gamepad_feed_destroy(GamepadFeed *handle) {
  if (!handle) return;
  TMGamepadFeed *feed = CFBridgingRelease(handle);
  for (TMPad *pad in feed.pads) {
    stop_rumble(pad);
    [pad.engine stopWithCompletionHandler:nil];
  }
  [GCController stopWirelessControllerDiscovery];
}
