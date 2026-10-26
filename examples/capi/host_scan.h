/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * Give a library's app a file, with tm_alloc, tm_asset and tm_free: the
 * --scan of the macOS host. It is plain C, so that a host on any system can
 * include it.
 */
#ifndef THREEMOJO_HOST_SCAN_H
#define THREEMOJO_HOST_SCAN_H

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#include "threemojo.h"

/* Read the file at path and give it to the app. Print why and return false
 * if the library has no asset functions, the file cannot be read, it is too
 * large for the library, or the app refuses it. */
static bool give_file(void *library, tm_app *app, const char *path) {
  uint8_t *(*make)(int32_t) = (uint8_t * (*)(int32_t)) dlsym(library, "tm_alloc");
  void (*release)(uint8_t *) = (void (*)(uint8_t *))dlsym(library, "tm_free");
  int32_t (*give)(tm_app *, const uint8_t *, int32_t) =
      (int32_t(*)(tm_app *, const uint8_t *, int32_t))dlsym(library, "tm_asset");
  if (!make || !release || !give) {
    fprintf(stderr, "threemojo_host: the library takes no file\n");
    return false;
  }
  FILE *file = fopen(path, "rb");
  if (!file) {
    fprintf(stderr, "threemojo_host: cannot open %s\n", path);
    return false;
  }
  long size = fseek(file, 0, SEEK_END) == 0 ? ftell(file) : -1;
  if (size <= 0 || size > INT32_MAX || fseek(file, 0, SEEK_SET) != 0) {
    fprintf(stderr, "threemojo_host: cannot read %s\n", path);
    fclose(file);
    return false;
  }
  uint8_t *room = make((int32_t)size);
  if (!room) {
    fprintf(stderr, "threemojo_host: %s is too large for the library: %ld bytes\n", path, size);
    fclose(file);
    return false;
  }
  size_t got = fread(room, 1, (size_t)size, file);
  fclose(file);
  int32_t status = got == (size_t)size ? give(app, room, (int32_t)size) : 1;
  release(room);
  if (status != 0) {
    fprintf(stderr, "threemojo_host: the library refused %s\n", path);
    return false;
  }
  return true;
}

#endif
