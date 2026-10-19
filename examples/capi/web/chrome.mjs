// Copyright (c) 2026 Seth Kitchen, PE
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Noncommercial use is free; commercial use requires a paid license.
// See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

// Run a script in a headless Chrome, for the checks of the WebGPU drawers:
//
//   const result = await inChrome("out/capi/web", `(async () => { ... })()`);
//
// It starts Chrome (CHROME names it, or it looks in the usual places) and a
// server for the folder, opens a blank page from that server, evaluates the
// expression there, and returns its value. The expression can import the
// folder's modules with absolute paths, such as "/splat_gpu.js". It returns
// null, and the caller skips, where there is no Chrome.
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { createServer as createSocket } from "node:net";
import { tmpdir } from "node:os";
import { extname, join, normalize } from "node:path";

const TYPES = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".wasm": "application/wasm",
  ".wgsl": "text/plain",
  ".jpg": "image/jpeg",
};

export function findChrome() {
  const named = [
    process.env.CHROME,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ];
  for (const path of named) if (path && existsSync(path)) return path;
  for (const name of ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"]) {
    const found = spawnSync("which", [name], { encoding: "utf8" });
    if (found.status === 0) return found.stdout.trim();
  }
  return null;
}

function freePort() {
  return new Promise((resolve) => {
    const socket = createSocket();
    socket.listen(0, "127.0.0.1", () => {
      const { port } = socket.address();
      socket.close(() => resolve(port));
    });
  });
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function evaluate(chrome, url, directory, expression, flags) {
  const port = await freePort();
  const browser = spawn(
    chrome,
    ["--headless=new", "--no-sandbox", "--enable-unsafe-webgpu", ...flags, `--remote-debugging-port=${port}`, `--user-data-dir=${directory}`, "about:blank"],
    { stdio: "ignore" },
  );
  try {
    let tab = null;
    for (let attempt = 0; attempt < 80 && !tab; attempt++) {
      try {
        tab = await (await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, { method: "PUT" })).json();
      } catch {
        await sleep(250);
      }
    }
    if (!tab) throw new Error("Chrome did not start");
    const socket = new WebSocket(tab.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      socket.onopen = resolve;
      socket.onerror = () => reject(new Error("no connection to Chrome"));
    });
    let last = 0;
    const waiting = new Map();
    socket.onmessage = (message) => {
      const reply = JSON.parse(message.data);
      if (reply.id) waiting.get(reply.id)?.(reply);
    };
    const call = (method, params) =>
      new Promise((resolve) => {
        waiting.set(++last, resolve);
        socket.send(JSON.stringify({ id: last, method, params }));
      });
    await sleep(500);
    const reply = await call("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    socket.close();
    if (reply.result.exceptionDetails) throw new Error(JSON.stringify(reply.result.exceptionDetails));
    return reply.result.result.value;
  } finally {
    // Chrome writes to its profile until it has gone.
    if (browser.exitCode === null) {
      browser.kill();
      await once(browser, "exit");
    }
  }
}

/**
 * Evaluate an expression in a page that a server for `folder` serves.
 *
 * @param folder      the folder to serve
 * @param expression  JavaScript that evaluates to a promise of a JSON value
 * @param options     `timeout`: milliseconds before the run is abandoned.
 *                    `flags`: more command line flags for Chrome.
 * @returns the value, or null where there is no Chrome
 */
export async function inChrome(folder, expression, { timeout = 120000, flags = [] } = {}) {
  const chrome = findChrome();
  if (!chrome) return null;
  const server = createServer((request, response) => {
    const path = normalize(decodeURIComponent(new URL(request.url, "http://x").pathname)).replace(/^(\.\.[/\\])+/, "");
    const file = join(folder, path);
    if (path === "/blank.html") {
      response.writeHead(200, { "Content-Type": "text/html" }).end("<!doctype html><title>check</title>");
    } else if (existsSync(file) && statSync(file).isFile()) {
      response.writeHead(200, { "Content-Type": TYPES[extname(file)] ?? "application/octet-stream" }).end(readFileSync(file));
    } else {
      response.writeHead(404).end();
    }
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const directory = mkdtempSync(join(tmpdir(), "threemojo-chrome-"));
  const timer = setTimeout(() => {
    console.log("FAIL timed out");
    process.exit(1);
  }, timeout);
  try {
    return await evaluate(chrome, `http://127.0.0.1:${server.address().port}/blank.html`, directory, expression, flags);
  } finally {
    clearTimeout(timer);
    server.close();
    rmSync(directory, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
}
