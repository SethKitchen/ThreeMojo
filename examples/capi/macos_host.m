/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * A macOS window for ThreeMojo's C ABI.
 *
 * This program loads a ThreeMojo library with dlopen, makes an app, and
 * shows its frames in a window. It owns everything that Mojo 1.1 cannot do
 * yet: the window, the loop, the clock and the input. It follows the shape
 * of a Flutter embedder. The library draws pixels. This thin host, in
 * AppKit, supplies a surface, the events and the time.
 *
 *   threemojo_host LIBRARY [WIDTH HEIGHT] [--frames N] [--dump FILE.ppm]
 *                          [--chdir DIR] [--headless] [--crisp] [--cpu]
 *
 * Start a window with run.sh, which launches ThreeMojo.app through Launch
 * Services. Since macOS 14 an app that a shell starts cannot take focus: its
 * window opens behind the terminal. --headless has no window, so it can run
 * from a shell.
 *
 * The app runs on its own thread and steps again at once when a frame is done,
 * so the display's pace does not leave the GPU idle between frames. The window
 * shows the newest frame at each refresh, and it shows the frame rate in its
 * title and in a label. --frames N quits after N frames. --dump writes the last frame as a PPM file.
 * --chdir changes the folder first, for a library that reads files from it:
 * Launch Services starts an app in the root folder. --headless opens no
 * window: it steps the app with a fixed 1/60 s, as fast as it can, and
 * prints the same numbers. A run with 60 frames is deterministic, so its
 * hash can be checked.
 *
 * The window is WIDTH by HEIGHT points, so a Retina display scales the frame
 * up. The scaling is smooth. --crisp shows the pixels as blocks instead.
 *
 * A library with the splat functions (libthreemojo_splat) is drawn on Metal:
 * the library sorts the splats, and macos_splat.m draws them on the GPU at the
 * window's size in pixels, so a Retina display gets a sharp frame. --cpu draws
 * on the CPU with tm_frame instead, at WIDTH by HEIGHT pixels. A window with
 * Metal shows the frames on a layer, so --dump and the frame hash work only
 * with --headless.
 *
 * Keys: the arrow keys and the space bar go to the app. Escape quits.
 */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "macos_splat.h"
#include "threemojo.h"

#define DEFAULT_WIDTH 480
#define DEFAULT_HEIGHT 320
#define FIXED_STEP_US 16667
#define LONGEST_STEP_US 100000
#define FPS_WINDOW_NS 1000000000ull
#define NOTCH_POINTS 10.0
#define EVENT_QUEUE 256
#define APP_STACK_BYTES (64u << 20)

typedef struct {
  int32_t (*abi_version)(void);
  void (*init)(void);
  tm_app *(*create)(int32_t, int32_t);
  void (*destroy)(tm_app *);
  void (*event)(tm_app *, int32_t, int32_t, int32_t, int32_t);
  void (*step)(tm_app *, int32_t);
  const uint8_t *(*frame)(tm_app *);
  int32_t (*width)(const tm_app *);
  int32_t (*height)(const tm_app *);
} Api;

typedef struct {
  int32_t kind, x, y, detail;
} Event;

typedef struct {
  Api api;
  tm_app *app;
  const char *name;
  const char *dump;
  int width;
  int height;
  uint64_t limit;  /* frames to run, or 0 for no limit */
  bool crisp;      /* scale the frame with blocks, not smoothly */
  bool cpu;        /* --cpu: draw on the CPU even where Metal could */
  SplatApi splat;  /* the library's splat functions, if it has them all */
  bool has_splat;
  bool use_metal;  /* the app is drawn on Metal */
  SplatMetal *metal; /* the GPU that draws it, once the window has a layer */
  int want_width, want_height; /* the window's size in pixels, under the lock */
  uint64_t window_gpu_ns;      /* the GPU's time at the start of the current second */
  double gpu_ms;               /* GPU milliseconds a frame, the last whole second */
  uint64_t frames; /* frames run */
  uint64_t started_ns;
  uint64_t library_ns;       /* time in tm_step and tm_frame, in all */
  uint64_t window_start_ns;  /* the start of the current second */
  uint64_t window_frames;    /* frames in the current second */
  uint64_t window_library_ns;
  double fps;       /* the last whole second */
  double ms;        /* library milliseconds a frame, the last whole second */
  const uint8_t *last; /* the last frame; valid until the next call */
  bool finished;
  /* A window runs the app on its own thread, so that the display's pace does
   * not leave it idle between frames: an idle GPU clocks down, and the next
   * frame then takes longer. The lock guards the fields below, and the display
   * thread and the app thread share them. */
  pthread_mutex_t lock;
  pthread_cond_t taken;   /* the display took the pending frame */
  pthread_t thread;
  bool running;           /* the app thread is started */
  Event events[EVENT_QUEUE];
  int event_count;
  CGImageRef pending;     /* the newest frame that the display has not taken */
  bool label_due;         /* a second ended: the label and the focus need a look */
  bool done;              /* the app ran its frames */
  bool stop;              /* the window is closing */
} Host;

static uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW); }

static uint64_t fnv1a(const uint8_t *bytes, size_t count) {
  uint64_t hash = 14695981039346656037ULL;
  for (size_t index = 0; index < count; index++) {
    hash ^= bytes[index];
    hash *= 1099511628211ULL;
  }
  return hash;
}

static void write_ppm(const char *path, const uint8_t *rgba, int width, int height) {
  FILE *file = fopen(path, "wb");
  if (!file) {
    fprintf(stderr, "threemojo_host: cannot write %s\n", path);
    return;
  }
  fprintf(file, "P6\n%d %d\n255\n", width, height);
  for (int pixel = 0; pixel < width * height; pixel++) fwrite(rgba + pixel * 4, 1, 3, file);
  fclose(file);
}

/* Move the app on, draw it, and count the time that the library took. */
static const uint8_t *advance(Host *host, int32_t microseconds) {
  uint64_t start = now_ns();
  host->api.step(host->app, microseconds);
  host->last = host->api.frame(host->app);
  uint64_t took = now_ns() - start;
  host->library_ns += took;
  host->window_library_ns += took;
  host->frames++;
  host->window_frames++;
  return host->last;
}

/* The window's size, in the pixels of the frame, if it is not the app's: the
 * app and the picture follow it. The window's thread writes the size. */
static void follow_window(Host *host) {
  pthread_mutex_lock(&host->lock);
  int width = host->want_width;
  int height = host->want_height;
  pthread_mutex_unlock(&host->lock);
  if (width <= 0 || height <= 0 || (width == host->width && height == host->height)) return;
  if (host->splat.resize(host->app, width, height) != 0) return;
  splat_metal_resize(host->metal, width, height);
  pthread_mutex_lock(&host->lock);
  host->width = width;
  host->height = height;
  pthread_mutex_unlock(&host->lock);
}

/* Move the app on, and draw it on the GPU. Only the library's part of it counts
 * as the library's time: the sort and the camera. */
static void advance_metal(Host *host, int32_t microseconds) {
  follow_window(host);
  uint64_t start = now_ns();
  host->api.step(host->app, microseconds);
  int32_t ready = host->splat.prepare(host->app);
  uint64_t took = now_ns() - start;
  host->library_ns += took;
  host->window_library_ns += took;
  splat_metal_draw(host->metal, ready);
  host->frames++;
  host->window_frames++;
}

/* Close the current second when it is over. Returns whether it was. */
static bool roll_window(Host *host) {
  uint64_t now = now_ns();
  if (now - host->window_start_ns < FPS_WINDOW_NS) return false;
  double seconds = (double)(now - host->window_start_ns) / 1e9;
  host->fps = (double)host->window_frames / seconds;
  host->ms = (double)host->window_library_ns / 1e6 / (double)host->window_frames;
  double library_ms = host->ms;
  if (host->metal) {
    /* The CPU and the GPU work on different frames at once, so the slower of
     * the two sets the pace. */
    uint64_t gpu_ns = splat_metal_gpu_ns(host->metal);
    host->gpu_ms = (double)(gpu_ns - host->window_gpu_ns) / 1e6 / (double)host->window_frames;
    host->window_gpu_ns = gpu_ns;
    if (host->gpu_ms > host->ms) host->ms = host->gpu_ms;
  }
  host->window_start_ns = now;
  host->window_frames = 0;
  host->window_library_ns = 0;
  if (host->metal) {
    printf("%.1f fps, %.2f ms a frame (library %.2f, GPU %.2f; up to %.0f fps)\n", host->fps,
           host->ms, library_ms, host->gpu_ms, host->ms > 0 ? 1000.0 / host->ms : 0.0);
  } else {
    printf("%.1f fps, %.2f ms a frame in the library (up to %.0f fps)\n", host->fps, host->ms,
           host->ms > 0 ? 1000.0 / host->ms : 0.0);
  }
  return true;
}

/* Print the totals, and write the last frame if asked. */
static void finish(Host *host) {
  if (host->finished) return;
  host->finished = true;
  /* The last frame of a picture without a window comes back from the GPU, and
   * the GPU is done when it does. A window has no picture to read. */
  if (host->metal) host->last = splat_metal_read(host->metal);
  double seconds = (double)(now_ns() - host->started_ns) / 1e9;
  if (host->frames > 0) {
    printf("%llu frames in %.2f s: %.1f fps, %.2f ms a frame in the library",
           (unsigned long long)host->frames, seconds, (double)host->frames / seconds,
           (double)host->library_ns / 1e6 / (double)host->frames);
    if (host->metal) {
      printf(", %.2f ms a frame on the GPU",
             (double)splat_metal_gpu_ns(host->metal) / 1e6 / (double)host->frames);
    }
    if (host->last) {
      printf(", frame hash %llu",
             (unsigned long long)fnv1a(host->last, (size_t)host->width * host->height * 4));
      if (host->dump) write_ppm(host->dump, host->last, host->width, host->height);
    }
    printf("\n");
  }
  fflush(stdout);
}

static CGImageRef make_image(const uint8_t *rgba, int width, int height) {
  /* The frame is copied, because the library may draw into it again. */
  CFDataRef data = CFDataCreate(NULL, rgba, (CFIndex)width * height * 4);
  CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
  CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGImageRef image = CGImageCreate(width, height, 8, 32, (size_t)width * 4, space,
                                   kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast,
                                   provider, NULL, false, kCGRenderingIntentDefault);
  CGColorSpaceRelease(space);
  CGDataProviderRelease(provider);
  CFRelease(data);
  return image;
}

/* The frame's size. The app thread changes it when the window does. */
static void frame_size(Host *host, int *width, int *height) {
  pthread_mutex_lock(&host->lock);
  *width = host->width;
  *height = host->height;
  pthread_mutex_unlock(&host->lock);
}

/* Queue an event for the app thread. A full queue drops it. */
static void post(Host *host, int32_t kind, int32_t x, int32_t y, int32_t detail) {
  pthread_mutex_lock(&host->lock);
  if (host->event_count < EVENT_QUEUE) {
    host->events[host->event_count++] = (Event){kind, x, y, detail};
  }
  pthread_mutex_unlock(&host->lock);
}

/* Give the app the events that wait, in the order they came. */
static void deliver(Host *host) {
  Event batch[EVENT_QUEUE];
  pthread_mutex_lock(&host->lock);
  int count = host->event_count;
  memcpy(batch, host->events, (size_t)count * sizeof(Event));
  host->event_count = 0;
  pthread_mutex_unlock(&host->lock);
  for (int index = 0; index < count; index++) {
    host->api.event(host->app, batch[index].kind, batch[index].x, batch[index].y,
                    batch[index].detail);
  }
}

/* The app thread: step, draw and hand the frame to the display, again and
 * again. The next step starts at once, so a slow app never waits for the
 * display. A fast app waits only when the display has not taken the last frame,
 * and that holds it to the display's pace. */
static void *run_app(void *argument) {
  Host *host = argument;
  uint64_t last = 0;
  while (true) {
    uint64_t start = now_ns();
    int32_t microseconds = FIXED_STEP_US;
    if (last > 0) {
      uint64_t elapsed = (start - last) / 1000;
      microseconds = (int32_t)(elapsed > LONGEST_STEP_US ? LONGEST_STEP_US : elapsed);
    }
    last = start;
    deliver(host);
    /* A frame on the GPU goes to the window by itself, and the layer's
     * drawables hold the app to the display's pace. A frame on the CPU is a
     * picture that the display takes. */
    CGImageRef image = NULL;
    if (host->metal) advance_metal(host, microseconds);
    else image = make_image(advance(host, microseconds), host->width, host->height);
    pthread_mutex_lock(&host->lock);
    bool second = roll_window(host);
    while (image && host->pending && !host->stop) pthread_cond_wait(&host->taken, &host->lock);
    if (host->stop) {
      pthread_mutex_unlock(&host->lock);
      if (image) CGImageRelease(image);
      return NULL;
    }
    if (image) host->pending = image;
    host->label_due |= second;
    bool finished = host->limit > 0 && host->frames >= host->limit;
    host->done = finished;
    pthread_mutex_unlock(&host->lock);
    if (finished) return NULL;
  }
}

static int key_code(NSEvent *event) {
  NSString *characters = event.charactersIgnoringModifiers;
  if (characters.length == 0) return -1;
  unichar character = [characters characterAtIndex:0];
  switch (character) {
    case NSUpArrowFunctionKey: return TM_KEY_ARROW_UP;
    case NSDownArrowFunctionKey: return TM_KEY_ARROW_DOWN;
    case NSLeftArrowFunctionKey: return TM_KEY_ARROW_LEFT;
    case NSRightArrowFunctionKey: return TM_KEY_ARROW_RIGHT;
    default: break;
  }
  if (character >= 'A' && character <= 'Z') return character + 32;
  return character < 128 ? character : -1;
}

/* The frame, and the events that go to the app. */
@interface TMView : NSView {
  Host *_host;
  int _held; /* the button that is down, or -1 */
  double _wheel;
}
- (instancetype)initWithHost:(Host *)host;
@end

@implementation TMView
- (instancetype)initWithHost:(Host *)host {
  self = [super initWithFrame:NSMakeRect(0, 0, host->width, host->height)];
  if (self) {
    _host = host;
    _held = -1;
    self.wantsLayer = YES;
    self.layer.contentsGravity = kCAGravityResize;
    self.layer.magnificationFilter = host->crisp ? kCAFilterNearest : kCAFilterLinear;
    self.layer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
  }
  return self;
}
/* A frame on the GPU goes to a Metal layer. */
- (CALayer *)makeBackingLayer {
  return _host->use_metal ? [CAMetalLayer layer] : [super makeBackingLayer];
}

/* Tell the app thread the window's size in pixels, and size the layer's
 * drawables to it, so that a Retina display gets a frame of its own size. */
- (void)syncSize {
  if (!_host->use_metal) return;
  NSSize pixels = [self convertSizeToBacking:self.bounds.size];
  int width = (int)lround(pixels.width);
  int height = (int)lround(pixels.height);
  width = width < 1 ? 1 : (width > TM_MAX_SIDE ? TM_MAX_SIDE : width);
  height = height < 1 ? 1 : (height > TM_MAX_SIDE ? TM_MAX_SIDE : height);
  ((CAMetalLayer *)self.layer).drawableSize = CGSizeMake(width, height);
  pthread_mutex_lock(&_host->lock);
  _host->want_width = width;
  _host->want_height = height;
  pthread_mutex_unlock(&_host->lock);
}
- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  [self syncSize];
}
- (void)viewDidChangeBackingProperties {
  [super viewDidChangeBackingProperties];
  [self syncSize];
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)isFlipped { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }
- (void)updateLayer { /* The display link sets the contents. */ }

- (void)show:(CGImageRef)image {
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.layer.contents = (__bridge id)image;
  [CATransaction commit];
}

- (void)send:(int)kind from:(NSEvent *)event detail:(int)detail {
  NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
  NSSize size = self.bounds.size;
  int width, height;
  frame_size(_host, &width, &height);
  int x = (int)(point.x * width / size.width);
  int y = (int)(point.y * height / size.height);
  x = x < 0 ? 0 : (x >= width ? width - 1 : x);
  y = y < 0 ? 0 : (y >= height ? height - 1 : y);
  post(_host, kind, x, y, detail);
}

- (void)press:(NSEvent *)event button:(int)button {
  _held = button;
  [self send:TM_POINTER_DOWN from:event detail:button];
}
- (void)release:(NSEvent *)event {
  [self send:TM_POINTER_UP from:event detail:_held < 0 ? 0 : _held];
  _held = -1;
}
- (void)mouseDown:(NSEvent *)event { [self press:event button:0]; }
- (void)rightMouseDown:(NSEvent *)event { [self press:event button:2]; }
- (void)otherMouseDown:(NSEvent *)event { [self press:event button:1]; }
- (void)mouseUp:(NSEvent *)event { [self release:event]; }
- (void)rightMouseUp:(NSEvent *)event { [self release:event]; }
- (void)otherMouseUp:(NSEvent *)event { [self release:event]; }
- (void)mouseDragged:(NSEvent *)event { [self send:TM_POINTER_MOVE from:event detail:_held]; }
- (void)rightMouseDragged:(NSEvent *)event { [self mouseDragged:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self mouseDragged:event]; }
- (void)mouseMoved:(NSEvent *)event { [self send:TM_POINTER_MOVE from:event detail:-1]; }

- (void)scrollWheel:(NSEvent *)event {
  /* A trackpad sends many small deltas. The app takes whole notches, and
   * positive toward the user, as a browser counts them. */
  double delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / NOTCH_POINTS
                                                 : event.scrollingDeltaY;
  _wheel -= delta;
  while (_wheel >= 1) {
    [self send:TM_WHEEL from:event detail:1];
    _wheel -= 1;
  }
  while (_wheel <= -1) {
    [self send:TM_WHEEL from:event detail:-1];
    _wheel += 1;
  }
}

- (void)keyDown:(NSEvent *)event {
  int code = key_code(event);
  if (code == TM_KEY_ESCAPE) {
    [NSApp terminate:nil];
    return;
  }
  /* The space bar toggles, so a held key must not repeat. */
  if (code < 0 || (code == TM_KEY_SPACE && event.isARepeat)) return;
  post(_host, TM_KEY_DOWN, 0, 0, code);
}
- (void)keyUp:(NSEvent *)event {
  int code = key_code(event);
  if (code >= 0) post(_host, TM_KEY_UP, 0, 0, code);
}
@end

/* The application: a window, a label, a display link and the app thread. */
@interface TMApp : NSObject <NSApplicationDelegate>
- (instancetype)initWithHost:(Host *)host;
@end

@implementation TMApp {
  Host *_host;
  NSWindow *_window;
  TMView *_view;
  NSTextField *_label;
  CADisplayLink *_link;
  int _inactive_seconds; /* seconds that the app was not the active one */
}

- (instancetype)initWithHost:(Host *)host {
  self = [super init];
  if (self) _host = host;
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
  NSMenu *bar = [NSMenu new];
  NSMenuItem *item = [NSMenuItem new];
  [bar addItem:item];
  NSMenu *menu = [NSMenu new];
  [menu addItemWithTitle:@"Quit ThreeMojo" action:@selector(terminate:) keyEquivalent:@"q"];
  item.submenu = menu;
  NSApp.mainMenu = bar;

  _view = [[TMView alloc] initWithHost:_host];
  _label = [NSTextField labelWithString:@""];
  _label.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightMedium];
  _label.textColor = NSColor.whiteColor;
  _label.drawsBackground = YES;
  _label.backgroundColor = [NSColor colorWithWhite:0 alpha:0.6];
  [_view addSubview:_label];

  NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
  _window = [[NSWindow alloc] initWithContentRect:_view.frame
                                        styleMask:style
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  _window.releasedWhenClosed = NO;
  _window.contentAspectRatio = NSMakeSize(_host->width, _host->height);
  _window.acceptsMouseMovedEvents = YES;
  _window.contentView = _view;
  _window.title = [NSString stringWithFormat:@"ThreeMojo %s", _host->name];
  [_window center];
  [_window makeKeyAndOrderFront:nil];
  [_window orderFrontRegardless];
  [_window makeFirstResponder:_view];
  if (_host->use_metal) {
    char reason[512] = "";
    _host->metal = splat_metal_create(&_host->splat, _host->app, (__bridge void *)_view.layer,
                                      _host->width, _host->height, reason, sizeof reason);
    if (!_host->metal) {
      fprintf(stderr, "threemojo_host: no Metal: %s. Run with --cpu.\n", reason);
      [NSApp terminate:nil];
      return;
    }
    [_view syncSize];
  }
  [self updateLabelWithFps:0 ms:0];
  [NSApp activate];

  _host->started_ns = _host->window_start_ns = now_ns();
  pthread_attr_t attributes;
  pthread_attr_init(&attributes);
  pthread_attr_setstacksize(&attributes, APP_STACK_BYTES);
  _host->running = pthread_create(&_host->thread, &attributes, run_app, _host) == 0;
  pthread_attr_destroy(&attributes);
  if (!_host->running) {
    fprintf(stderr, "threemojo_host: cannot start the app thread\n");
    [NSApp terminate:nil];
    return;
  }
  _link = [_view displayLinkWithTarget:self selector:@selector(tick:)];
  [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

- (void)updateLabelWithFps:(double)fps ms:(double)ms {
  double up_to = ms > 0 ? 1000.0 / ms : 0.0;
  int width, height;
  frame_size(_host, &width, &height);
  NSString *where = _host->metal
                        ? [NSString stringWithFormat:@"Metal, %s", splat_metal_name(_host->metal)]
                        : @"CPU";
  _label.stringValue =
      [NSString stringWithFormat:@"%.1f fps\n%.2f ms a frame, up to %.0f fps\n%s  %dx%d  %@",
                                 fps, ms, up_to, _host->name, width, height, where];
  [_label sizeToFit];
  _label.frame = NSMakeRect(8, 8, _label.frame.size.width, _label.frame.size.height);
  if (fps > 0) {
    _window.title =
        [NSString stringWithFormat:@"ThreeMojo %s  %.1f fps  %.2f ms", _host->name, fps, ms];
  }
}

/* macOS decides whether a new app takes the focus, and it can say no. Try
 * once more, and then tell the user where the window is. */
- (void)checkFocus {
  if (NSApp.isActive) {
    _inactive_seconds = 0;
    return;
  }
  if (++_inactive_seconds == 1) {
    [NSApp activate];
  } else if (_inactive_seconds == 2) {
    fprintf(stderr,
            "threemojo_host: the window is open, but another app has the focus. "
            "Click the ThreeMojo icon in the Dock to bring it forward.\n");
  }
}

/* Show the newest frame, if the app thread made one since the last tick. */
- (void)tick:(CADisplayLink *)link {
  pthread_mutex_lock(&_host->lock);
  CGImageRef image = _host->pending;
  _host->pending = NULL;
  bool label = _host->label_due;
  _host->label_due = false;
  bool done = _host->done;
  double fps = _host->fps;
  double ms = _host->ms;
  if (image) pthread_cond_signal(&_host->taken);
  pthread_mutex_unlock(&_host->lock);
  if (image) {
    [_view show:image];
    CGImageRelease(image);
  }
  if (label) {
    [self updateLabelWithFps:fps ms:ms];
    [self checkFocus];
  }
  if (done) [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app { return YES; }

- (void)applicationWillTerminate:(NSNotification *)note {
  [_link invalidate];
  if (_host->running) {
    pthread_mutex_lock(&_host->lock);
    _host->stop = true;
    pthread_cond_broadcast(&_host->taken);
    pthread_mutex_unlock(&_host->lock);
    pthread_join(_host->thread, NULL);
    if (_host->pending) CGImageRelease(_host->pending);
  }
  finish(_host);
  splat_metal_destroy(_host->metal);
  _host->api.destroy(_host->app);
}
@end

static void usage(void) {
  fprintf(stderr,
          "usage: threemojo_host LIBRARY [WIDTH HEIGHT] [--frames N] [--dump FILE.ppm] "
          "[--chdir DIR] [--headless] [--crisp] [--cpu]\n");
}

static bool load_symbols(Host *host, void *library) {
#define BIND(field, symbol)                                     \
  host->api.field = dlsym(library, symbol);                     \
  if (!host->api.field) {                                       \
    fprintf(stderr, "threemojo_host: missing %s\n", symbol);    \
    return false;                                               \
  }
  BIND(abi_version, "tm_abi_version")
  BIND(init, "tm_init")
  BIND(create, "tm_create")
  BIND(destroy, "tm_destroy")
  BIND(event, "tm_event")
  BIND(step, "tm_step")
  BIND(frame, "tm_frame")
  BIND(width, "tm_width")
  BIND(height, "tm_height")
#undef BIND
  /* The splat functions are in some libraries only, so they are not required. */
  host->splat.prepare = dlsym(library, "tm_splat_prepare");
  host->splat.part = dlsym(library, "tm_splat_part");
  host->splat.words = dlsym(library, "tm_splat_words");
  host->splat.info = dlsym(library, "tm_splat_info");
  host->splat.resize = dlsym(library, "tm_resize");
  host->has_splat = host->splat.prepare && host->splat.part && host->splat.words &&
                    host->splat.info && host->splat.resize;
  return true;
}

static TMApp *delegate; /* The application holds its delegate weakly. */

int main(int argc, char **argv) {
  @autoreleasepool {
    setvbuf(stdout, NULL, _IOLBF, 0);
    Host host;
    memset(&host, 0, sizeof host);
    host.width = DEFAULT_WIDTH;
    host.height = DEFAULT_HEIGHT;
    const char *path = NULL;
    bool headless = false;
    int sizes = 0;
    for (int index = 1; index < argc; index++) {
      const char *argument = argv[index];
      if (!strcmp(argument, "--headless")) {
        headless = true;
      } else if (!strcmp(argument, "--crisp")) {
        host.crisp = true;
      } else if (!strcmp(argument, "--cpu")) {
        host.cpu = true;
      } else if (!strcmp(argument, "--frames") && index + 1 < argc) {
        host.limit = strtoull(argv[++index], NULL, 10);
      } else if (!strcmp(argument, "--dump") && index + 1 < argc) {
        host.dump = argv[++index];
      } else if (!strcmp(argument, "--chdir") && index + 1 < argc) {
        if (chdir(argv[++index]) != 0) {
          fprintf(stderr, "threemojo_host: cannot enter %s\n", argv[index]);
          return 1;
        }
      } else if (argument[0] == '-') {
        usage();
        return 2;
      } else if (!path) {
        path = argument;
      } else if (sizes < 2) {
        if (sizes++ == 0) host.width = atoi(argument);
        else host.height = atoi(argument);
      } else {
        usage();
        return 2;
      }
    }
    if (!path || sizes == 1) {
      usage();
      return 2;
    }
    void *library = dlopen(path, RTLD_NOW);
    if (!library) {
      fprintf(stderr, "threemojo_host: %s\n", dlerror());
      return 1;
    }
    if (!load_symbols(&host, library)) return 1;
    if (host.api.abi_version() != TM_ABI_VERSION) {
      fprintf(stderr, "threemojo_host: the library has ABI %d, this host needs %d\n",
              host.api.abi_version(), TM_ABI_VERSION);
      return 1;
    }
    host.api.init();
    host.app = host.api.create(host.width, host.height);
    if (!host.app) {
      fprintf(stderr, "threemojo_host: no app for a %dx%d frame (sides run 1 to %d)\n", host.width,
              host.height, TM_MAX_SIDE);
      return 1;
    }
    const char *slash = strrchr(path, '/');
    host.name = slash ? slash + 1 : path;
    pthread_mutex_init(&host.lock, NULL);
    pthread_cond_init(&host.taken, NULL);

    if (host.has_splat && !host.cpu) {
      /* Try the passes without a window first: a window that cannot draw is
       * worse than a message, and the CPU can always draw the frame. */
      char reason[512] = "";
      SplatMetal *probe = splat_metal_create(&host.splat, host.app, NULL, host.width, host.height,
                                             reason, sizeof reason);
      if (probe) {
        host.use_metal = true;
        printf("threemojo_host: drawing on Metal, %s\n", splat_metal_name(probe));
        if (headless) host.metal = probe;
        else splat_metal_destroy(probe);
      } else {
        fprintf(stderr, "threemojo_host: drawing on the CPU, no Metal: %s\n", reason);
      }
    }

    if (headless) {
      if (host.limit == 0) host.limit = 60;
      host.started_ns = host.window_start_ns = now_ns();
      while (host.frames < host.limit) {
        if (host.metal) advance_metal(&host, FIXED_STEP_US);
        else advance(&host, FIXED_STEP_US);
        roll_window(&host);
      }
      finish(&host);
      splat_metal_destroy(host.metal);
      host.api.destroy(host.app);
      return 0;
    }

    NSApplication *application = [NSApplication sharedApplication];
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    delegate = [[TMApp alloc] initWithHost:&host];
    application.delegate = delegate;
    [application run];
  }
  return 0;
}
