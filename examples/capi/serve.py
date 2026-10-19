# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
"""Serve a folder with the headers that let a page share memory.

A page can make shared memory, and so can run WebAssembly on many Web
Workers, only when it is cross-origin isolated. Two headers make it so:
Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy. Use it like this:

    serve.py [FOLDER] [PORT]

The folder is the current one by default, and the port is 8000. The server
listens on 127.0.0.1 only, and it tells the browser not to cache, so that a
rebuilt module is the one that loads.
"""
import functools
import http.server
import sys


class Handler(http.server.SimpleHTTPRequestHandler):
    """A file server that isolates the page it serves."""

    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".mjs": "text/javascript",
    }

    def end_headers(self) -> None:
        """Add the isolation headers to every response."""
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main(argv: list[str]) -> int:
    """Serve until interrupted.

    Args:
        argv: The folder, then the port. Both are optional.

    Returns:
        The exit status: 0 after Control-C, 2 for a port that is not a number.
    """
    folder = argv[1] if len(argv) > 1 else "."
    try:
        port = int(argv[2]) if len(argv) > 2 else 8000
    except ValueError:
        print(f"serve.py: the port must be a number, not {argv[2]}", file=sys.stderr)
        return 2
    handler = functools.partial(Handler, directory=folder)
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as server:
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
