# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Serve a folder with the headers that let a page share memory.

A page can make shared memory, and so can run WebAssembly on many Web
Workers, only when it is cross-origin isolated. Two headers make it so:
Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy. `run.sh web`
runs it:

    tools/capi_serve.mojo [FOLDER] [PORT]

The folder is the current one by default, and the port is 8000. The server
listens on 127.0.0.1 only, and it tells the browser not to cache, so that a
rebuilt module is the one that loads. A directory request serves
`index.html`. A directory with no `index.html` is a 404. The server does
not list directories.
"""

from std.ffi import c_int, external_call
from std.os.path import realpath
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr

from tools._owned_process import EINTR, close_fd, errno, strerror

comptime _LIMIT = 65536
"""The most header bytes one request may send."""


def _pointer(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer. Zero is `NULL`."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


struct ListeningSocket(Movable):
    """A socket bound to 127.0.0.1."""

    var fd: Int
    """The listening descriptor."""
    var port: Int
    """The port the kernel bound."""

    def __init__(out self, fd: Int, port: Int):
        """Store a listening socket.

        Args:
            fd: The descriptor.
            port: The bound port.
        """
        self.fd = fd
        self.port = port

    def close(self):
        """Close the descriptor."""
        close_fd(self.fd)


def _parse_port(text: String) raises -> Int:
    """Return a TCP port, as a decimal integer from 0 to 65535.

    Args:
        text: The command-line text.

    Returns:
        The port.

    Raises:
        Error: If `text` is not a port in that range.
    """
    var body = text
    if body.startswith("+"):
        var rest = String(body[byte=1:])
        body = rest
    if body.byte_length() == 0:
        raise Error("the port must be a number, not " + text)
    var value = 0
    for byte in body.as_bytes():
        if byte < 48 or byte > 57:
            raise Error("the port must be a number, not " + text)
        value = value * 10 + Int(byte) - 48
        if value > 65535:
            raise Error("the port is out of range: " + text)
    return value


def _inet_address(port: Int) -> List[UInt8]:
    """Return a `sockaddr_in` for 127.0.0.1 and `port`.

    Args:
        port: The port, in host order.

    Returns:
        Sixteen bytes. Linux and macOS differ in the first two.
    """
    var addr = List[UInt8](length=16, fill=0)
    if CompilationTarget.is_linux():
        addr[0] = 2
        addr[1] = 0
    else:
        addr[0] = 16
        addr[1] = 2
    addr[2] = UInt8((port >> 8) & 255)
    addr[3] = UInt8(port & 255)
    addr[4] = 127
    addr[7] = 1
    return addr^


def _reuse_level() -> Int:
    """Return `SOL_SOCKET` for this platform."""
    return 1 if CompilationTarget.is_linux() else 0xFFFF


def _reuse_option() -> Int:
    """Return `SO_REUSEADDR` for this platform."""
    return 2 if CompilationTarget.is_linux() else 4


def listen_local(port: Int) raises -> ListeningSocket:
    """Listen on 127.0.0.1.

    Args:
        port: The port, or 0 to let the kernel choose.

    Returns:
        The socket and the port that was bound.

    Raises:
        Error: If the socket cannot be created or bound.
    """
    if port < 0 or port > 65535:
        raise Error("the port is out of range: " + String(port))
    var fd = Int(external_call["socket", c_int](c_int(2), c_int(1), c_int(0)))
    if fd < 0:
        raise Error("socket failed: " + strerror(errno()))
    var one = List[Int32](length=1, fill=1)
    var level = _reuse_level()
    var option = _reuse_option()
    _ = external_call["setsockopt", c_int](
        c_int(fd),
        c_int(level),
        c_int(option),
        _pointer(Int(one.unsafe_ptr())),
        c_int(4),
    )
    var addr = _inet_address(port)
    if (
        external_call["bind", c_int](
            c_int(fd), _pointer(Int(addr.unsafe_ptr())), c_int(16)
        )
        != 0
    ):
        var number = errno()
        close_fd(fd)
        raise Error("bind failed: " + strerror(number))
    if external_call["listen", c_int](c_int(fd), c_int(128)) != 0:
        var number = errno()
        close_fd(fd)
        raise Error("listen failed: " + strerror(number))
    var bound = List[UInt8](length=16, fill=0)
    var length = List[UInt32](length=1, fill=16)
    if (
        external_call["getsockname", c_int](
            c_int(fd),
            _pointer(Int(bound.unsafe_ptr())),
            _pointer(Int(length.unsafe_ptr())),
        )
        != 0
    ):
        var number = errno()
        close_fd(fd)
        raise Error("getsockname failed: " + strerror(number))
    var actual = (Int(bound[2]) << 8) | Int(bound[3])
    return ListeningSocket(fd, actual)


def _accept(fd: Int) raises -> Int:
    """Accept one connection.

    Args:
        fd: The listening descriptor.

    Returns:
        The client descriptor.

    Raises:
        Error: If `accept` fails for a reason other than `EINTR`.
    """
    while True:
        var client = Int(
            external_call["accept", c_int](c_int(fd), _pointer(0), _pointer(0))
        )
        if client >= 0:
            return client
        var number = errno()
        if number != EINTR:
            raise Error("accept failed: " + strerror(number))


def _header_end(data: List[UInt8]) -> Int:
    """Return the index of the first body byte, or -1.

    Args:
        data: The bytes read so far.

    Returns:
        The index after `\\r\\n\\r\\n` or `\\n\\n`.
    """
    var last = len(data)
    var index = 0
    while index + 3 < last:
        if (
            data[index] == 13
            and data[index + 1] == 10
            and data[index + 2] == 13
            and data[index + 3] == 10
        ):
            return index + 4
        index += 1
    index = 0
    while index + 1 < last:
        if data[index] == 10 and data[index + 1] == 10:
            return index + 2
        index += 1
    return -1


def _read_headers(fd: Int) raises -> List[UInt8]:
    """Read one request header.

    Args:
        fd: The client.

    Returns:
        The bytes through the header, or everything if the peer closed
        first. At most 64 KiB.

    Raises:
        Error: If `read` fails.
    """
    var data = List[UInt8]()
    var chunk = List[UInt8](length=4096, fill=0)
    while len(data) < _LIMIT:
        var count = external_call["read", Int](
            Int32(fd), _pointer(Int(chunk.unsafe_ptr())), len(chunk)
        )
        if count < 0:
            if errno() == EINTR:
                continue
            raise Error("read failed: " + strerror(errno()))
        if count == 0:
            break
        var index = 0
        while index < count and len(data) < _LIMIT:
            data.append(chunk[index])
            index += 1
        if _header_end(data) >= 0:
            break
    return data^


def _write_all(fd: Int, data: List[UInt8]) raises:
    """Write every byte.

    Args:
        fd: The client.
        data: The response.

    Raises:
        Error: If `write` fails or writes nothing.
    """
    var sent = 0
    while sent < len(data):
        var count = external_call["write", Int](
            Int32(fd),
            _pointer(Int(data.unsafe_ptr()) + sent),
            len(data) - sent,
        )
        if count < 0:
            if errno() == EINTR:
                continue
            raise Error("write failed: " + strerror(errno()))
        if count == 0:
            raise Error("short write")
        sent += count


def _extend(mut data: List[UInt8], text: String):
    """Append the bytes of `text`."""
    for byte in text.as_bytes():
        data.append(byte)


def _response(
    status: Int,
    reason: String,
    content_type: String,
    body: List[UInt8],
    send_body: Bool,
    extra: String = "",
) -> List[UInt8]:
    """Build one HTTP/1.1 response with the isolation headers.

    Args:
        status: The status code.
        reason: The reason phrase.
        content_type: The `Content-Type` value.
        body: The body. `Content-Length` is its length even for `HEAD`.
        send_body: False for `HEAD`.
        extra: More header lines, each ending in `\\r\\n`.

    Returns:
        The response bytes.
    """
    var head = (
        "HTTP/1.1 "
        + String(status)
        + " "
        + reason
        + "\r\nContent-Type: "
        + content_type
        + "\r\nContent-Length: "
        + String(len(body))
        + "\r\nCross-Origin-Opener-Policy: same-origin\r\n"
        + "Cross-Origin-Embedder-Policy: require-corp\r\n"
        + "Cache-Control: no-store\r\nConnection: close\r\n"
        + extra
        + "\r\n"
    )
    var out = List[UInt8]()
    _extend(out, head)
    if send_body:
        for byte in body:
            out.append(byte)
    return out^


def _text_response(
    status: Int,
    reason: String,
    message: String,
    send_body: Bool,
    extra: String = "",
) -> List[UInt8]:
    """Build a `text/plain` response."""
    var body = List[UInt8]()
    _extend(body, message)
    return _response(status, reason, "text/plain", body, send_body, extra)


def _hex_value(byte: UInt8) -> Int:
    """Return the value of one hex digit, or -1."""
    if byte >= 48 and byte <= 57:
        return Int(byte) - 48
    if byte >= 65 and byte <= 70:
        return Int(byte) - 55
    if byte >= 97 and byte <= 102:
        return Int(byte) - 87
    return -1


def _decode_percent(text: String) -> String:
    """Decode `%HH` escapes. An incomplete escape stays as it is.

    Args:
        text: A URL path.

    Returns:
        The decoded path.
    """
    var out = List[UInt8]()
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        if bytes[index] == 37 and index + 2 < len(bytes):
            var high = _hex_value(bytes[index + 1])
            var low = _hex_value(bytes[index + 2])
            if high >= 0 and low >= 0:
                out.append(UInt8(high * 16 + low))
                index += 3
                continue
        out.append(bytes[index])
        index += 1
    return String(from_utf8_lossy=out)


def _normalize(path: String) -> String:
    """Return `path` with `.` and `..` removed, relative to the root.

    Args:
        path: A decoded URL path.

    Returns:
        A relative path that cannot leave the root. The root is empty.
    """
    var stack = List[String]()
    for part in path.split("/"):
        if part.byte_length() == 0 or part == ".":
            continue
        if part == "..":
            if len(stack) > 0:
                _ = stack.pop()
            continue
        stack.append(String(part))
    return "/".join(stack)


def _extension(path: String) -> String:
    """Return the lower-case extension, including the dot."""
    var slash = path.rfind("/")
    var name = path if slash < 0 else String(path[byte = slash + 1 :])
    var dot = name.rfind(".")
    if dot <= 0:
        return String()
    return String(name[byte=dot:]).lower()


def _content_type(path: String) -> String:
    """Return the media type for a file path."""
    var ext = _extension(path)
    if ext == ".wasm":
        return "application/wasm"
    if ext == ".js" or ext == ".mjs":
        return "text/javascript"
    if ext == ".html" or ext == ".htm":
        return "text/html"
    if ext == ".css":
        return "text/css"
    if ext == ".json":
        return "application/json"
    if ext == ".png":
        return "image/png"
    if ext == ".jpg" or ext == ".jpeg":
        return "image/jpeg"
    if ext == ".svg":
        return "image/svg+xml"
    if ext == ".txt" or ext == ".wgsl":
        return "text/plain"
    return "application/octet-stream"


def _inside(root: String, path: String) -> Bool:
    """Return whether `path` is `root` or a file inside it."""
    return path == root or path.startswith(root + "/")


def _request_line(request: List[UInt8]) -> String:
    """Return the first line of a request, without the terminator."""
    var end = _header_end(request)
    var limit = len(request) if end < 0 else end
    var line = List[UInt8]()
    var index = 0
    while index < limit:
        var byte = request[index]
        if byte == 13 or byte == 10:
            break
        line.append(byte)
        index += 1
    return String(from_utf8_lossy=line)


def http_response(root: String, request: List[UInt8]) raises -> List[UInt8]:
    """Answer one HTTP request for files under `root`.

    Args:
        root: The folder to serve.
        request: The request bytes. Only the first line is read.

    Returns:
        A complete HTTP/1.1 response. `GET` and `HEAD` are served. Every
        response carries the isolation and `Cache-Control: no-store` headers.

    Raises:
        Error: If a file that was present cannot be read.
    """
    var line = _request_line(request)
    var words = line.split(" ")
    if len(words) < 3 or not words[2].startswith("HTTP/"):
        return _text_response(400, "Bad Request", "400 Bad Request\n", True)
    var method = String(words[0])
    var send_body = True
    if method == "HEAD":
        send_body = False
    elif method != "GET":
        return _text_response(
            405,
            "Method Not Allowed",
            "405 Method Not Allowed\n",
            True,
            "Allow: GET, HEAD\r\n",
        )
    var raw = String(words[1])
    var suffix = String()
    var query = raw.find("?")
    var fragment = raw.find("#")
    var cut = -1
    if query >= 0 and (fragment < 0 or query < fragment):
        cut = query
    elif fragment >= 0:
        cut = fragment
    if cut >= 0:
        var tail = String(raw[byte=cut:])
        var head = String(raw[byte=:cut])
        suffix = tail
        raw = head
    if raw.byte_length() == 0 or raw.as_bytes()[0] != 47:
        return _text_response(400, "Bad Request", "400 Bad Request\n", True)
    if not Path(root).is_dir():
        return _text_response(404, "Not Found", "404 Not Found\n", send_body)
    var base = realpath(root)
    var relative = _normalize(_decode_percent(raw))
    var location = (
        base if relative.byte_length() == 0 else base + "/" + relative
    )
    if Path(location).is_dir():
        if not raw.endswith("/"):
            var target = raw + "/" + suffix
            return _text_response(
                301,
                "Moved Permanently",
                "",
                send_body,
                "Location: " + target + "\r\n",
            )
        var index = location + "/index.html"
        if not Path(index).is_file():
            return _text_response(
                404, "Not Found", "404 Not Found\n", send_body
            )
        location = index
    elif not Path(location).is_file():
        return _text_response(404, "Not Found", "404 Not Found\n", send_body)
    var real = realpath(location)
    if not _inside(base, real):
        return _text_response(404, "Not Found", "404 Not Found\n", send_body)
    var body = Path(real).read_bytes()
    return _response(200, "OK", _content_type(real), body, send_body)


def answer(root: String, fd: Int) raises:
    """Read one request from `fd` and write its response.

    Args:
        root: The folder to serve.
        fd: The client socket.

    Raises:
        Error: If the socket read or write fails.
    """
    var request = _read_headers(fd)
    _write_all(fd, http_response(root, request))


def serve_once(server: Int, root: String) raises:
    """Accept one client and answer it.

    Args:
        server: The listening descriptor.
        root: The folder to serve.

    Raises:
        Error: If `accept` fails, or the socket read or write fails.
    """
    var client = _accept(server)
    try:
        answer(root, client)
    finally:
        close_fd(client)


def serve_forever(root: String, port: Int) raises:
    """Serve until the process is stopped.

    A client that sends a bad request does not stop the server. An `accept`
    failure does.

    Args:
        root: The folder.
        port: The port.

    Raises:
        Error: If the socket cannot listen or `accept` fails.
    """
    var server = listen_local(port)
    try:
        while True:
            var client = _accept(server.fd)
            try:
                answer(root, client)
            except error:
                print("serve.mojo:", error, file=stderr)
            finally:
                close_fd(client)
    finally:
        server.close()


def serve_command(arguments: List[String]) raises -> Int:
    """Serve a folder until interrupted.

    Args:
        arguments: An optional folder and an optional port.

    Returns:
        The exit status. A bad port is 2, as the Python server returned.

    Raises:
        Error: If the server cannot listen.
    """
    var folder = "."
    if len(arguments) > 0:
        folder = arguments[0]
    var port = 8000
    if len(arguments) > 1:
        try:
            port = _parse_port(arguments[1])
        except error:
            print("serve.mojo:", error, file=stderr)
            return 2
    serve_forever(folder, port)
    return 0


def main() raises:
    """Serve a folder from the command line."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        exit(serve_command(arguments))
    except error:
        print("serve.mojo:", error, file=stderr)
        exit(1)
