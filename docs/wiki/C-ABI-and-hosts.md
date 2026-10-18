# C ABI and hosts

`window/capi_*.mojo` export nine C functions. A host program calls them to run a ThreeMojo app and show its frames. The host can be a macOS window, a web page, or any program that can call C. A library can export more functions: for files, for a host's GPU, for a new frame size and for splats.

`examples/capi/` has two hosts. One is a macOS window. The other is a web page that runs a WebAssembly build. Both show the frame rate.

The web page draws the water and the splats on the GPU through WebGPU. Where it has no WebGPU, it draws on the CPU. The window draws the splats on the GPU through Metal.

three.js: a canvas in a page, and a `requestAnimationFrame` loop. Here the host owns the loop, and the library draws one frame for each call.

## Run it

On macOS 14 or later, open a window:

```bash
examples/capi/run.sh native water
```

The title bar and a label in the corner show the frame rate. They also show the time that the library took for one frame. Press Escape or Command+Q to quit. Control-C in the terminal quits too.

The window scales the frame to its size with smoothing. `--crisp` keeps hard pixels. The library runs on a thread of its own and draws one frame after another. The display shows the newest frame. The loop must not wait for the display. A GPU that idles between frames lowers its clock, and a frame then takes about 50 percent longer.

The script starts `out/capi/ThreeMojo.app` through Launch Services. A program that a shell starts cannot take focus on macOS 14 and later, so its window would open behind the terminal. macOS can still refuse the focus to a new app. Then the host says so, and a click on the ThreeMojo icon in the Dock brings the window forward.

The splats are Gaussian splats, a scan of three tomatoes. The window draws them on the GPU, at the size of the window in pixels:

```bash
examples/capi/run.sh native splat
```

`--cpu` draws on the CPU instead. The CPU draws at the size that you give, and it takes about 200 milliseconds for a frame at 640 by 360.

Run the web build in a browser:

```bash
examples/capi/run.sh web water
examples/capi/run.sh web splat
```

The script serves `out/capi/web` on `localhost` and opens the page. The label in the corner shows the same numbers. It also shows `WebGPU`, or the number of threads.

A browser that has WebGPU draws the water and the splats on its GPU, at 1280 by 720 pixels. Add `?gpu=0` to the address to draw on the CPU instead. The page also draws on the CPU when the browser has no WebGPU adapter, or when its device does not take the shader. The label then says why. See [The WebGPU path](#the-webgpu-path).

On the CPU, the water uses one thread for each core. It draws about ten times faster than on one thread. A page can share memory between threads only when it is cross-origin isolated. The script `examples/capi/serve.py` sends the two headers that make it so. Any other server gets the module for one thread, and the label says why.

On the CPU, the page picks the size of the water frame. It chooses the largest size that draws in about 33 milliseconds. On WebGPU, every size in the list takes less than that, so there is no automatic choice. The list goes up to 1920 by 1080.

You can choose another size from the list below the frame. The check box "Smooth" turns the smoothing of the scaled frame off. Three query parameters change the start: `?gpu=0` forces the CPU, `?threads=N` sets the number of workers on the CPU, and `?threads=0` forces one thread. `?w=W&h=H` fixes the size.

Each script builds first when a source is newer than its output. Run `examples/capi/run.sh check` to test both builds without a window.

| Tool | Needed for |
|---|---|
| The Mojo toolchain in `.venv` | Every build. |
| Xcode command line tools | The macOS window. |
| `brew install llvm lld` | The WebAssembly build. |
| MAX and a GPU | `water-gpu` only. |
| Node | `run.sh check` only. |
| Chrome or Chromium | The WebGPU check in `run.sh check`. Without one, the check is skipped. Set `CHROME` to name one. |

## The five apps

Give `run.sh` one of five names. Each name is a library that exports the same functions.

| App | Library | What it draws | Browser |
|---|---|---|---|
| `core` | `window/capi_core.mojo` | A gradient and a triangle. The pointer moves a corner. | Yes |
| `scene` | `window/capi_scene.mojo` | Two cubes, with `OrbitControls`. The whole renderer runs. | No |
| `water` | `window/capi_water.mojo` | The Clearwater [Water](Water) over a pebble bed. | Yes, on the CPU or on WebGPU |
| `water-gpu` | `window/capi_water_gpu.mojo` | The same water. A GPU shades the pixels. | No. Use `water`. |
| `splat` | `window/capi_splat.mojo` | Three tomatoes, 445,409 [Gaussian splats](Gaussian-splats#three-tomatoes). | Yes, on WebGPU or on the CPU |

Options follow the app name, as in `run.sh native water 640 360 --frames 300`. The width and the height come first. `--frames N` quits after N frames. `--dump file.ppm` writes the last frame. `--headless` opens no window and steps with a fixed 1/60 second.

`--cpu` draws the splats on the CPU. A window that draws on Metal shows its frames on a layer. So `--dump` and the frame hash work only with `--headless`.

Controls of `core`: move the pointer, and press the space bar to pause.

Controls of `scene`: drag to orbit, drag with the right button to pan, turn the wheel to dolly, and use the arrow keys to pan.

Controls of `water` and `water-gpu`: press to drop a pebble in, and drag up or down to tilt the camera. Press the space bar to pause.

Controls of `splat`: drag to orbit, drag with the right button to pan, and turn the wheel to zoom. The camera turns by itself until you press the space bar. The controls are those of the three.js example.

`water-gpu` needs MAX and a GPU, and it runs in the macOS window only. `run.sh native water-gpu` builds it. The first build on Apple Metal can take many minutes. Later builds use the cache. The default size is 1280 by 720.

### Speed

These numbers come from one Apple Silicon Mac with 16 logical cores. The native numbers are the time that the library takes for one frame in a headless run. The window caps the rate at the refresh rate of the display, so it cannot give them. The browser numbers come from Chrome. The WebGPU numbers are the time of the whole frame, with the device idle at the end of each.

| App and size | Native | Browser, one thread | Browser, 16 threads | Browser, WebGPU |
|---|---|---|---|---|
| `core`, 480 by 320 | 0.6 ms a frame | 0.7 ms a frame | Not built | Not built |
| `scene`, 480 by 320 | 2.3 ms a frame | Not built | Not built | Not built |
| `water`, 320 by 180 | 17.5 ms a frame | 277 ms a frame | 32 ms a frame | Not measured |
| `water`, 640 by 360 | 55 ms a frame | Not measured | 99 ms a frame | 9.6 ms a frame |
| `water`, 1280 by 720 | 205 ms a frame | Not measured | Not measured | 10.8 ms a frame |
| `water`, 1920 by 1080 | Not measured | Not measured | Not measured | 12.9 ms a frame |
| `water-gpu`, 640 by 360 | 9.3 ms a frame | Not built | Not built | Not built |
| `water-gpu`, 1280 by 720 | 16.4 ms a frame | Not built | Not built | Not built |
| `water-gpu`, 1920 by 1080 | 28.9 ms a frame | Not built | Not built | Not built |
| `splat`, 640 by 360 | 2.9 ms a frame on Metal, 201 on the CPU | 861 ms a frame | Not built | Not measured |
| `splat`, 1280 by 720 | 1.5 ms a frame on Metal | Not measured | Not built | 3.6 ms a frame |
| `splat`, 1920 by 1080 | 1.4 ms a frame on Metal | Not measured | Not built | Not measured |
| `splat`, 3840 by 2160 | 1.4 ms a frame on Metal | Not measured | Not built | Not measured |

In the macOS window, `water-gpu` ran at 116, 63 and 25 frames a second at 640 by 360, 1280 by 720 and 1920 by 1080. At 1920 by 1080 the window is slower than the headless run, which gives 35 frames a second. The cause is not known. In a browser page the frame rate is the refresh rate of the display, 60 frames a second here, at every size.

The `splat` rows on Metal are the time of a whole headless run divided by its frames. The CPU sorts the splats for one frame while the GPU draws earlier frames. So the slower of the two sets the rate.

The smaller frames are not faster on this GPU: 640 by 360 gives 345 frames a second and 3840 by 2160 gives 738. The cause is not known.

The `splat` row on WebGPU is the mean of 120 frames in a headless Chrome, with the device idle at the end of each. Its median is 2.6 milliseconds. The CPU rows use one thread.

In the macOS window, `splat` ran at 118 frames a second at 1920 by 1080 pixels, which is the 120 Hz refresh of this display. The GPU took 3.7 to 5.3 milliseconds for a frame, and the library took 0.8. In a browser page the rate is the refresh rate of the display, 60 frames a second here.

The CPU water spreads each pass over every thread. On one thread the browser is about fifteen times slower than the native build. With threads it is about two times slower. Part of that is WebAssembly itself: one WebAssembly thread is about twice as slow as one native thread.

On WebGPU, the module still does part of each frame. The step takes 0.6 milliseconds, packing the arrays takes 2.9 and the glare's FFT takes 4.0. These times do not depend on the size of the frame. They set the limit: about 130 frames a second at any size, which is more than a display shows.

In `water-gpu`, the GPU shades the pixels, cuts and blurs the bloom, and grades the frame. Only the glare's small FFT runs on the CPU, and only the final bytes come back. See [Shade it on a GPU](Water#shade-it-on-a-gpu).

## The functions

Only integers and one opaque handle cross the boundary. The header is `window/threemojo.h`.

| Function | Meaning |
|---|---|
| `tm_abi_version()` | The version of the ABI. A host must check it. |
| `tm_init()` | Start the Mojo runtime. Call it once, first. |
| `tm_create(width, height)` | Make an app. It returns `NULL` if a side is outside 1 to 4096. |
| `tm_destroy(app)` | Free the app. |
| `tm_event(app, kind, x, y, detail)` | Send one input event. |
| `tm_step(app, microseconds)` | Move the app on by the time since the last step. |
| `tm_frame(app)` | Draw, and return the frame. |
| `tm_width(app)`, `tm_height(app)` | The size of the frame. |

The frame is RGBA, eight bits for each channel, row by row from the top. It has `width * height * 4` bytes. It stays valid until the next call on the same app.

### Events

| Kind | Number | Detail |
|---|---|---|
| Key down | 0 | The key code. |
| Pointer down | 1 | The button: 0 first, 1 middle, 2 second. |
| Pointer move | 2 | The button that is down, or -1. |
| Pointer up | 3 | The button. |
| Wheel | 4 | The notches. Positive is toward the user. |
| Key up | 6 | The key code. |

A printable key is its ASCII code. The arrow keys are 256 for up, 257 for down, 258 for left and 259 for right. The kinds are the values of `InputKind` in `controls/input.mojo`.

### Files

A library that needs a file has three more functions. A host looks for them and calls them only if they exist. The water library has them.

| Function | Meaning |
|---|---|
| `tm_alloc(size)` | Make room in the memory of the library. It returns `NULL` if the size is outside 1 byte to 64 MiB. |
| `tm_free(room)` | Give the room back. |
| `tm_asset(app, bytes, length)` | Give the app its file, a JPEG. It returns 0 when the app has it. |

The water library reads `assets/pebbles.jpg` when the program runs in the root folder of the repository. A browser has no files. There the bed is plain sand until the page calls `tm_asset` with the photograph.

### A host's GPU

A host that has a GPU, and cannot reach it from Mojo, can draw the water's frame itself. A browser with WebGPU is such a host. The water library has five more functions for it. A host looks for them and calls them only if they exist.

| Function | Meaning |
|---|---|
| `tm_gpu_prepare(app)` | Make the arrays that the frame's shader reads. It returns how many times the photograph has been packed, or -1. |
| `tm_gpu_part(app, which)` | Return where one array is in memory. It returns `NULL` before the first prepare. |
| `tm_gpu_words(app, which)` | Return the size of one array in 32-bit words. A table of 64-bit integers counts two words an entry. |
| `tm_gpu_info(app, which)` | Return one number: the ripple texels on one side, or the width or the height of the glare grid. |
| `tm_gpu_glare(app)` | Spread the glints that the host wrote into the glare. It returns 0 when the glare is ready. |

One frame goes like this. The host calls `tm_step`, then `tm_gpu_prepare`. It copies the surface, the ripple, the caustic and the frame values to the GPU. It copies the photograph again only when the number from `tm_gpu_prepare` changes. The GPU shades the frame and finds the glints.

Then the host writes the glints into the `GPU_SAMPLES` part and calls `tm_gpu_glare`. It reads the `GPU_GRID` part, and the GPU grades the frame and shows it. The header `window/threemojo.h` has the part numbers.

A host must take a new view of the module's memory after every call into the module, because the memory can grow. A number that names no part or no info gives `NULL` or 0.

### A new frame size

A library can take a new frame size. The splat library has this function. A host looks for it and calls it only if it exists.

| Function | Meaning |
|---|---|
| `tm_resize(app, width, height)` | Change the size of the frame. It returns 0 on success, and 1 if a side is outside 1 to 4096. |

The scan, the camera and the controls stay. A host that draws at the size of its window calls it when the window changes size. The camera keeps its field of view, and takes the aspect of the new frame.

### Splats

The splat library keeps the scan, the camera and the controls, and it sorts the splats from back to front. A host with a GPU draws them. It has four more functions, and it looks for them as for the other optional functions.

| Function | Meaning |
|---|---|
| `tm_splat_prepare(app)` | Sort the splats if the view has turned far enough, and write the view. It returns 0 when the order and the view are ready, and 1 when there is no scan. |
| `tm_splat_part(app, which)` | Return where one array is in memory. It returns `NULL` for a band that the scan does not have. |
| `tm_splat_words(app, which)` | Return the size of one array in 32-bit words. |
| `tm_splat_info(app, which)` | Return one number: the splats, the degree, the scan's generation or the order's generation. |

The parts are the centers, the covariances, the colors, the three bands of spherical harmonics, the draw order and the view. The view is 48 floats: the model-view matrix, the projection matrix, the size of the frame, the eye, the degree, the count and the background. The header `window/threemojo.h` has the numbers.

One frame goes like this. The host calls `tm_step`, then `tm_splat_prepare`. When the scan's generation changes, it copies the scan's arrays to the GPU. When the order's generation changes, it copies the order. It copies the view every frame. Then the GPU projects and shades each splat, blends the quads in the draw order and shows the picture.

The generations are numbers that only grow. A host compares them with the numbers that it saw, so it copies the big arrays only when they changed. A scan has 445,409 splats and about 41 megabytes of arrays. The order is 1.8 megabytes.

A host can also give the library a scan: `tm_asset` takes the bytes of an `.spz` file. The library reads `assets/tomatoes/tomatoes.v4.spz` when it runs in the root folder of the repository and the host gives it nothing. The page gives the bytes, because a browser has no files.

## Rules for a host

Call `tm_init` once before any other function. A program that is not written in Mojo needs it. Without it, a library that uses threads crashes in `tm_create`.

Never load two of the libraries into one process. They export the same names.

No function raises. A call that fails does nothing. An event that the app refuses is dropped. A frame that cannot be drawn is the last one that could.

## How it works

Mojo 1.1 has no windows and no WebAssembly output. So the host owns the window, the loop and the clock. The library only draws. This is the shape of a Flutter embedder. A thin host in the platform's own toolkit gives the engine a surface, events and the time.

The macOS host is `examples/capi/macos_host.m`. It loads a library with `dlopen`. It shows each frame as a `CGImage` in the layer of an `NSView`. The library runs on a thread of its own, with a stack of 64 MiB.

That thread steps the app and draws, one frame after another, and keeps the newest frame in a mailbox. A `CADisplayLink` on the main thread shows the frame in the mailbox. Events go from the main thread to the app thread through a queue. The page `examples/capi/web/index.html` drives its loop with a canvas and `requestAnimationFrame`.

### The macOS GPU path

The window draws the splats on Metal. `examples/capi/macos_splat.m` does it. `examples/capi/splat.metal` holds the shaders. They are `splat.wgsl` in the Metal Shading Language. `build.sh` puts the shaders into the host as a C string, and Metal compiles them when the window opens. So the build needs no Metal toolchain.

The host tries the passes before it opens a window. When Metal is not there, or a shader does not compile, the host says why and draws on the CPU.

The layer of the window is a `CAMetalLayer`. Its drawables have the size of the window in pixels, so a Retina display gets a sharp frame. When the window changes size, the view tells the app thread. The app thread calls `tm_resize` and makes new pictures.

The app thread does all the work for a frame: the step, the sort, the commands and the present. It waits for a free drawable, and that holds it to the display's pace. Three frames can be on the GPU at once. Each has its own copy of the draw order, because the CPU writes the order while an earlier frame still reads its own.

The blend goes into a half-float picture, as on the web. A last pass writes the picture to the drawable. The colors are not changed. Use `splat_metal_read` in `macos_splat.m` to read a picture without a window. `run.sh check` draws 12 frames on Metal and on the CPU and compares them. On this Mac the mean difference was 0.056 of 255 at 640 by 360, and the largest was 8.

### The WebAssembly build

`mojo build --emit llvm` writes LLVM IR for the host. `examples/capi/retarget.py` changes its data layout and its triple to those of wasm32. Then clang compiles it, and `wasm-ld` links it with `examples/capi/mwrt.c`.

`mwrt.c` supplies what the Mojo runtime and the C library give on a host:

- An allocator that frees and joins blocks. A water frame allocates several megabytes, so memory must be reused.
- The math functions that WebAssembly lacks: `sinf`, `cosf`, `cos`, `fma` and `fmaf`.
- Files that fail, so that the app falls back to its plain bed.
- A `TaskGroup`. For one thread it runs each task as soon as it is launched. For many threads it puts the tasks in a queue. See [Threads](#threads).

Mojo returns an optional pointer through a slot of 64 bits. A pointer on wasm32 has 4 bytes, so the upper half of the slot held stack garbage. After the first step, `tm_alloc` returned an address like `0x2000000000...`. `retarget.py` clears each such slot before the pointer goes in. The page also keeps the low 32 bits of every address that it reads. `check.mjs` tests that `tm_alloc` and `tm_gpu_part` give addresses with no upper half.

`run.sh check` tests the result. The core module must give the same three frame hashes as `tests/test_capi_core.mojo`. The water module cannot match the native build bit for bit. WebAssembly has no fused multiply-add, and its sine is another implementation. In one test 99.4 percent of the channel values were within one level of the native frame.

### The WebGPU path

The page asks the browser for the fast adapter, with `powerPreference: "high-performance"`, as three.js does. It takes the default limits and the preferred canvas format, and it makes the canvas opaque. It runs the module for one thread, because the GPU does the work that threads do on the CPU. A change of size makes a new `GpuWater`. It takes the compiled passes of the old one.

Each frame goes through these steps. `examples/capi/web/water_gpu.js` runs them.

1. The module steps the app and packs the arrays (`tm_gpu_prepare`).
2. The page writes the arrays to storage buffers. It writes the photograph once, and again only when the photograph changes.
3. The GPU shades the frame, finds the glints on a grid, and blurs the bright part of the picture. These are compute passes of `examples/capi/web/water.wgsl`.
4. The page reads the glints back. The module spreads them into the glare with one small FFT, while the GPU blurs the bloom.
5. The GPU grades the frame into an `rgba8unorm` texture with integer-rounded bytes. A render pass shows it on the canvas with linear filtering.

`water.wgsl` is a port of the Mojo shader. The two agree closely. In `check_gpu.mjs`, a 320 by 180 frame after three steps differs from the CPU frame by 0.0075 of 255 on average. The largest difference is 5.

They cannot agree to the bit. WGSL has no `sin` and `atan2` that match the shared Mojo functions, and it cannot forbid a fused multiply-add. So a few noise cells differ.

The original Clearwater uses WebGL2 and GLSL. It runs the ocean FFT, the ripples, the caustics and the glare on the GPU, and it reads textures with hardware mip maps. Here those four stay in the module. They cost about 7.5 milliseconds a frame, which is less than the 8.3 milliseconds of a frame on a 120 Hz display. The shader reads the surface, the caustics and the pebbles from arrays, and it filters them itself, as the CPU does.

### Splats on WebGPU

The page draws the splats with `examples/capi/web/splat_gpu.js` and `splat.wgsl`. Three passes draw a frame. A compute pass projects and shades each splat, in draw order. A render pass draws one quad for each splat, and blends them into a half-float picture. A last render pass writes the picture to the canvas.

The module runs for one thread, because the sort is small. The module sorts 445,409 splats in about 4 milliseconds. It loads the scan from bytes in about 350 milliseconds.

A WebGPU device has limits that set the design:

- A compute pass can bind 8 storage buffers. The project pass uses 8 and one uniform.
- A vertex shader can only read a storage buffer. The project pass writes the projected splats, so the draw pass binds the same buffer again, read only.
- The projected splats take 48 bytes each. A device that allows 128 MiB for one binding takes up to about 2.79 million splats. `GpuSplat` refuses a larger scan with an error that names the limit.

`check_splat_gpu.mjs` draws a frame of 480 by 270 pixels on the device and on the CPU. The mean difference was 0.078 of 255, and the largest was 14. No value differed by more than 20.

The page changes the size of the frame with `tm_resize`, so the scan stays on the device when the size changes.

### Threads

The module for many threads is `threemojo_water_threads.wasm`. `build.sh` links it with shared memory, and `mwrt.c` compiles with `-DMW_THREADS` for it. The page makes the memory and one Web Worker for each thread. Each worker runs the same module on the same memory. It gets a stack of its own, and then it takes tasks from the queue until the page closes.

The thread of the page works too. When it waits for a `TaskGroup`, it runs tasks from the queue. A page must not block its main thread, so it cannot sleep there.

The allocator and the queue each use a lock. The frames do not depend on the number of threads: each task writes its own rows. `run.sh check` draws the same frames with one thread and with 1, 3 and 7 workers, and it compares them bit for bit.

The page gets a copy of each frame from the threaded module. `ImageData` does not take a view of shared memory.

### What is not done

- The `scene` app needs the whole renderer. Its threads and its strings are not in the WebAssembly build yet.
- The window host is macOS only. On Linux, `X11Window` in `window/x11.mojo` opens a window from Mojo itself. A Linux host can also load these libraries.
- The ocean FFT, the ripples, the caustics and the glare's FFT run on the CPU in both GPU paths. The original Clearwater runs them on the GPU. They cost about 7.5 milliseconds a frame in a browser. A frame on a 120 Hz display lasts 8.3 milliseconds, so they stay.
- The page does not return to the CPU when a frame fails. It shows a message, and the message names `?gpu=0`. It does return before the first frame, if the browser has no adapter or the shader does not compile.
- The window copies each frame from the library's buffer to the display. The copy takes 0.47 of 16 milliseconds. A kernel that wrote into the host's buffer read back wrong on Metal, so the copy stays.
- At 1920 by 1080 the macOS window is slower than the headless run. The cause is not known.
- The water in the browser restarts when the page changes the size of the frame. Only the splat library has `tm_resize`.
- The splats have no GPU path on Linux. The Metal code is macOS only, and `window/x11.mojo` has no splat host. A Linux host can use the CPU.
- A window that draws the splats on Metal has no frame hash and no `--dump`. Use `--headless` for them.
- The CPU splat is slow: about 200 milliseconds for a frame natively at 640 by 360, and 861 in a browser. The sort is small, and the draw takes the time.
- The Metal splats and the WebGPU splats are ports of the Mojo shader. They agree closely and not to the bit.
- Mojo is pinned at 1.1.0. A later Mojo with WebAssembly output can replace `retarget.py` and `mwrt.c`. The C functions then stay as they are.

See also [Windowing and controls](Windowing-and-controls) and [Water](Water).
