# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Download every Mixamo animation to a folder of FBX files.

`tools/mixamo.mojo` is the command line. This file holds what it does.

Mixamo has no public API and no download link per animation. Its web page
talks to a JSON API, and this file makes the same requests with your own
Adobe sign-in, as a browser does:

1. `GET /products` lists the animations, one page at a time.
2. `GET /products/ID` gives one animation's `gms_hash`: the settings the
   export needs, with a default for each parameter.
3. `POST /animations/export` starts an export for one character.
4. `GET /characters/CHARACTER/monitor` says when the export is ready, and
   where to fetch it.
5. A plain GET of that address gives the FBX file.

The sign-in is a bearer token. The tool reads it from the environment
variable `MIXAMO_TOKEN` or from a file, and puts it only in a header file
that `curl` reads. A request never carries it on a command line. The token
goes to `mixamo.com` and nowhere else: the download address is a signed link
that needs no token.

A file is written to its place only after it is complete and starts as an
FBX file does. A name that is already in the folder is not fetched again, so
a run that stops can start again where it was. `animations.json` in the
folder lists each file with its animation's id and name.

The tool is slow on purpose. It waits between animations, waits longer after
an HTTP 429, and stops at once when Mixamo refuses the token. Mixamo's terms
of use apply to what you download. Keep the files out of the repository.
"""

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NO_NODE,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
    parse_json,
    quote_json,
)
from std.os import listdir, remove, rmdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.time import sleep
from tools._carla_files import make_dirs, replace_file, write_file
from tools._process import run_program

comptime API = "https://www.mixamo.com/api/v1"
comptime API_KEY = "mixamo2"
# How many animations the list gives a page. Mixamo's own page asks for
# this many.
comptime PAGE_SIZE = 100
"""The most animations a page can hold. Mixamo cuts a larger request to this."""

comptime MAX_PASSES = 12
"""The most times a run reads the whole list."""
# The start of an error that must end the run, not only skip one animation.
comptime STOP = "Mixamo stopped: "
# The longest a file name can be, before its suffix.
comptime NAME_LENGTH = 100
comptime INDEX = "animations.json"


struct Product(Copyable, Movable):
    """One animation of the list."""

    var id: String
    """Mixamo's id for it."""
    var name: String
    """What Mixamo calls it."""
    var kind: String
    """`Motion` for one animation, `MotionPack` for a bundle."""

    def __init__(out self, id: String, name: String, kind: String):
        """Hold an entry of the list.

        Args:
            id: The id.
            name: The name.
            kind: The kind.
        """
        self.id = id
        self.name = name
        self.kind = kind


struct Entry(Copyable, Movable):
    """One file of the folder, as `animations.json` lists it."""

    var id: String
    """Mixamo's id for the animation."""
    var name: String
    """What Mixamo calls it."""
    var file: String
    """The file's name in the folder."""

    def __init__(out self, id: String, name: String, file: String):
        """Hold an entry of the index.

        Args:
            id: The id.
            name: The name.
            file: The file name.
        """
        self.id = id
        self.name = name
        self.file = file


struct Listing(Movable):
    """One page of the list."""

    var products: List[Product]
    """The page's animations, in Mixamo's order."""
    var pages: Int
    """How many pages the list has in all."""
    var total: Int
    """How many animations the list has in all, or zero when Mixamo does not
    say."""

    def __init__(out self):
        """Start with an empty page."""
        self.products = List[Product]()
        self.pages = 0
        self.total = 0


struct Job(Movable):
    """What the monitor says of the last export."""

    var status: String
    """`processing`, `completed` or `failed`."""
    var url: String
    """Where to fetch the file, once the status is `completed`."""

    def __init__(out self, status: String, url: String):
        """Hold an answer of the monitor.

        Args:
            status: The status.
            url: The address of the result, or empty.
        """
        self.status = status
        self.url = url


def _text(document: JsonDocument, node: Int, place: String) raises -> String:
    """Return a string of the answer, or say where it was missing."""
    if node == NO_NODE or document.kind(node) != STRING:
        raise Error("Mixamo's answer has no text at " + place)
    return document.string(node)


def parse_listing(text: String) raises -> Listing:
    """Read a page of `GET /products`.

    Args:
        text: The answer's JSON.

    Returns:
        The page's animations and the number of pages.

    Raises:
        Error: If the text is not JSON, or lacks `results`,
            `pagination.num_pages`, or an animation's `id` or `name`.
    """
    var document = parse_json(text)
    var root = document.root()
    var results = document.get(root, "results")
    var pagination = document.get(root, "pagination")
    if results == NO_NODE or document.kind(results) != ARRAY:
        raise Error("Mixamo's list has no results")
    if pagination == NO_NODE:
        raise Error("Mixamo's list has no pagination")
    var listing = Listing()
    listing.pages = document.integer(document.get(pagination, "num_pages"))
    if document.has(pagination, "num_results"):
        listing.total = document.integer(
            document.get(pagination, "num_results")
        )
    for index in range(document.length(results)):  # pragma: no branch
        var item = document.at(results, index)
        var kind = String("Motion")
        if document.has(item, "type"):
            kind = _text(document, document.get(item, "type"), "type")
        listing.products.append(
            Product(
                _text(document, document.get(item, "id"), "id"),
                _text(document, document.get(item, "name"), "name"),
                kind,
            )
        )
    return listing^


def _number_text(value: Float64) -> String:
    """Return a number as JavaScript prints it: a whole number without a
    point."""
    var whole = Int(value)
    if Float64(whole) == value:
        return String(whole)
    return String(value)


def _json_of(document: JsonDocument, node: Int) raises -> String:
    """Return a node as JSON text, keeping the order of the keys."""
    var kind = document.kind(node)
    if kind == OBJECT:
        var text = String("{")
        for index in range(document.length(node)):  # pragma: no branch
            if index > 0:
                text += ","
            text += quote_json(document.key(node, index)) + ":"
            text += _json_of(document, document.at(node, index))
        return text + "}"
    if kind == ARRAY:
        var text = String("[")
        for index in range(document.length(node)):  # pragma: no branch
            if index > 0:
                text += ","
            text += _json_of(document, document.at(node, index))
        return text + "]"
    if kind == STRING:
        return quote_json(document.string(node))
    if kind == NUMBER:
        return _number_text(document.number(node))
    if kind == BOOLEAN:
        return "true" if document.boolean(node) else "false"
    return "null"


def _parameters(document: JsonDocument, node: Int) raises -> String:
    """Return the default of each parameter, joined by commas.

    A parameter is a list: its name, then its default, then its limits.
    """
    var values = List[String]()
    for index in range(document.length(node)):  # pragma: no branch
        var parameter = document.at(node, index)
        var value = document.at(parameter, 1)
        if document.kind(value) == NUMBER:
            values.append(_number_text(document.number(value)))
        elif document.kind(value) == STRING:
            values.append(document.string(value))
        else:
            values.append(_json_of(document, value))
    return ",".join(values)


def export_entry(details: String, in_place: Bool) raises -> String:
    """Return the `gms_hash` an export asks for.

    The animation's answer holds `details.gms_hash`. The export wants it back
    with each parameter at its default and `params` as one string. Every
    other field passes through as Mixamo wrote it.

    Args:
        details: The JSON of `GET /products/ID`.
        in_place: True to ask Mixamo to keep the hips in place.

    Returns:
        The JSON of the `gms_hash` object.

    Raises:
        Error: If the text is not JSON or holds no `details.gms_hash`.
    """
    var document = parse_json(details)
    var hidden = document.get(document.root(), "details")
    if hidden == NO_NODE or not document.has(hidden, "gms_hash"):
        raise Error("Mixamo's answer has no gms_hash")
    var hash = document.get(hidden, "gms_hash")
    var text = String("{")
    var in_place_seen = False
    for index in range(document.length(hash)):  # pragma: no branch
        if index > 0:
            text += ","
        var key = document.key(hash, index)
        text += quote_json(key) + ":"
        var value = document.at(hash, index)
        if key == "params":
            text += quote_json(_parameters(document, value))
        elif key == "inplace" and in_place:
            text += "true"
            in_place_seen = True
        else:
            text += _json_of(document, value)
    if in_place and not in_place_seen:
        text += ',"inplace":true'
    return text + "}"


def export_body(
    character: String,
    entry: String,
    name: String,
    format: String,
    fps: Int,
) -> String:
    """Return the body of `POST /animations/export`.

    Args:
        character: The id of the character to export for.
        entry: The JSON object `export_entry` returned.
        name: The animation's name.
        format: The file format, as `fbx7`.
        fps: Frames a second.

    Returns:
        The JSON.
    """
    return (
        '{"character_id":'
        + quote_json(character)
        + ',"gms_hash":['
        + entry
        + '],"preferences":{"format":'
        + quote_json(format)
        + ',"skin":"false","fps":"'
        + String(fps)
        + '","reducekf":"0"},"product_name":'
        + quote_json(name)
        + ',"type":"Motion"}'
    )


def parse_job(text: String) raises -> Job:
    """Read an answer of the monitor.

    Args:
        text: The JSON.

    Returns:
        The status, and the address of the result when there is one.

    Raises:
        Error: If the text is not JSON or has no status.
    """
    var document = parse_json(text)
    var root = document.root()
    var status = _text(document, document.get(root, "status"), "status")
    var url = String()
    if document.has(root, "job_result"):
        var result = document.get(root, "job_result")
        if document.kind(result) == STRING:
            url = document.string(result)
    return Job(status, url)


def safe_name(name: String) -> String:
    """Return a name that is safe as a file name on every system.

    Letters, digits, spaces and `-_().,'` stay. Every other byte becomes an
    underscore. A name cannot start with a dot or a space, and holds at most
    `NAME_LENGTH` bytes.

    Args:
        name: What Mixamo calls the animation.

    Returns:
        The name, or `animation` when nothing is left.
    """
    var kept = List[UInt8]()
    for byte in name.as_bytes():
        var letter = (
            (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or (byte >= 48 and byte <= 57)
            or byte == 32
            or byte == 45
            or byte == 95
            or byte == 40
            or byte == 41
            or byte == 46
            or byte == 44
            or byte == 39
        )
        # A byte of a longer character is not a letter. Each becomes one
        # underscore, which is safe.
        kept.append(byte if letter else 95)
    var start = 0
    while start < len(kept) and (kept[start] == 46 or kept[start] == 32):
        start += 1
    var stop = min(len(kept), start + NAME_LENGTH)
    while stop > start and kept[stop - 1] == 32:
        stop -= 1
    if stop == start:
        return "animation"
    return String(unsafe_from_utf8=kept[start:stop])


def url_encode(text: String) -> String:
    """Return text as a part of a URL query.

    Letters, digits and `-_.~` stay. Every other byte becomes `%` and two
    hexadecimal digits.

    Args:
        text: The text.

    Returns:
        The encoded text.
    """
    var digits = "0123456789ABCDEF"
    var out = List[UInt8]()
    for byte in text.as_bytes():
        var plain = (
            (byte >= 65 and byte <= 90)
            or (byte >= 97 and byte <= 122)
            or (byte >= 48 and byte <= 57)
            or byte == 45
            or byte == 95
            or byte == 46
            or byte == 126
        )
        if plain:
            out.append(byte)
        else:
            out.append(37)
            out.append(digits.as_bytes()[Int(byte >> 4)])
            out.append(digits.as_bytes()[Int(byte & 15)])
    return String(unsafe_from_utf8=out)


def require_token(token: String) raises -> String:
    """Return a token that can go in a header, or refuse it.

    A leading `Bearer ` is taken off. Whitespace around the token goes too.
    A token with a space or a control character inside is refused, so a
    wrong paste cannot add a header.

    Args:
        token: What the user gave.

    Returns:
        The token.

    Raises:
        Error: If it is empty or holds a space or a control character.
    """
    var text = String(token.strip())
    if text.startswith("Bearer "):
        text = String(String(text[byte=7:]).strip())
    if text.byte_length() == 0:
        raise Error("The Mixamo token is empty")
    for byte in text.as_bytes():
        if byte <= 32 or byte == 127:
            raise Error(
                "The Mixamo token has a space or a control character inside"
            )
    return text^


struct Reply(Movable):
    """One answer of the web server."""

    var status: Int
    """The HTTP status."""
    var body: String
    """The body, or empty when it went to a file."""

    def __init__(out self, status: Int, var body: String):
        """Hold an answer.

        Args:
            status: The HTTP status.
            body: The body.
        """
        self.status = status
        self.body = body^


struct Transport(Copyable, Movable):
    """How the requests go out: through `curl`, with the token."""

    var token: String
    """The bearer token."""
    var curl: String
    """The `curl` program, found on `PATH` when it has no slash."""
    var api: String
    """The API's address, without a final slash."""
    var wait: Float64
    """Seconds to wait after the first HTTP 429. Each try waits twice as
    long."""
    var tries: Int
    """How many times a request runs at most when Mixamo answers 429."""

    def __init__(
        out self,
        token: String,
        curl: String = "curl",
        api: String = API,
        wait: Float64 = 5.0,
        tries: Int = 5,
    ):
        """Make a transport.

        Args:
            token: The bearer token, as `require_token` returns it.
            curl: The `curl` program.
            api: The API's address.
            wait: Seconds to wait after the first 429.
            tries: How many runs of a request at most.
        """
        self.token = token
        self.curl = curl
        self.api = api
        self.wait = wait
        self.tries = tries

    def _run(
        self, method: String, url: String, body: String, signed: Bool
    ) raises -> Reply:
        """Run `curl` once and return the status and the body."""
        var scratch = mkdtemp(prefix="mixamo-")
        try:
            var command: List[String] = [
                self.curl,
                "--silent",
                "--show-error",
                "--location",
                "--connect-timeout",
                "30",
                "--max-time",
                "300",
                "--output",
                scratch + "/body",
                "--write-out",
                "%{http_code}",
            ]
            if signed:
                # The token goes into a file in a private directory. It
                # never shows in the list of processes.
                Path(scratch + "/headers").write_text(
                    "Accept: application/json\n"
                    + "Content-Type: application/json\n"
                    + "Authorization: Bearer "
                    + self.token
                    + "\n"
                    + "X-Api-Key: "
                    + API_KEY
                    + "\n"
                    + "X-Requested-With: XMLHttpRequest\n"
                )
                command.append("--header")
                command.append("@" + scratch + "/headers")
            if method == "POST":
                Path(scratch + "/request").write_text(body)
                command.append("--request")
                command.append("POST")
                command.append("--data-binary")
                command.append("@" + scratch + "/request")
            command.append("--url")
            command.append(url)
            var result = run_program(command, 330.0, merge_errors=False)
            if result.status != 0:
                raise Error(
                    "curl failed with status "
                    + String(result.status)
                    + ": "
                    + String(result.errors.strip())
                )
            var code = Int(String(result.output.strip()))
            # `curl` writes no file for an empty body.
            var answer = String()
            if Path(scratch + "/body").exists():
                answer = String(
                    from_utf8_lossy=Path(scratch + "/body").read_bytes()
                )
            return Reply(code, answer^)
        finally:
            for name in listdir(scratch):
                remove(Path(scratch) / name)
            rmdir(scratch)

    def send(
        self, method: String, url: String, body: String = ""
    ) raises -> Reply:
        """Send a request with the token, and try again after a 429.

        Args:
            method: `GET` or `POST`.
            url: The address.
            body: The JSON body of a POST.

        Returns:
            The last answer. A 429 that outlasts every try is returned too.

        Raises:
            Error: If `curl` fails or prints no status.
        """
        var pause = self.wait
        var reply = self._run(method, url, body, True)
        var again = 1
        while reply.status == 429 and again < self.tries:
            sleep(pause)
            pause *= 2
            reply = self._run(method, url, body, True)
            again += 1
        return reply^

    def get(self, path: String) raises -> Reply:
        """Send a GET to a path of the API.

        Args:
            path: The path with its query, as `/products?page=1`.

        Returns:
            The answer.

        Raises:
            Error: As `send` does.
        """
        return self.send("GET", self.api + path)

    def post(self, path: String, body: String) raises -> Reply:
        """Send a POST to a path of the API.

        Args:
            path: The path.
            body: The JSON body.

        Returns:
            The answer.

        Raises:
            Error: As `send` does.
        """
        return self.send("POST", self.api + path, body)

    def fetch(self, url: String) raises -> List[UInt8]:
        """Fetch a signed address, with no token.

        Args:
            url: The address of an export's result.

        Returns:
            The bytes.

        Raises:
            Error: If `curl` fails or the server does not answer 200.
        """
        var scratch = mkdtemp(prefix="mixamo-")
        try:
            var command: List[String] = [
                self.curl,
                "--silent",
                "--show-error",
                "--location",
                "--connect-timeout",
                "30",
                "--max-time",
                "600",
                "--output",
                scratch + "/body",
                "--write-out",
                "%{http_code}",
                "--url",
                url,
            ]
            var result = run_program(command, 630.0, merge_errors=False)
            if result.status != 0:
                raise Error(
                    "curl failed with status "
                    + String(result.status)
                    + ": "
                    + String(result.errors.strip())
                )
            var code = Int(String(result.output.strip()))
            if code != 200:
                raise Error("the file's address answered HTTP " + String(code))
            if not Path(scratch + "/body").exists():
                return List[UInt8]()
            return Path(scratch + "/body").read_bytes()
        finally:
            for name in listdir(scratch):
                remove(Path(scratch) / name)
            rmdir(scratch)


def _checked(reply: Reply, what: String) raises -> String:
    """Return a body, or raise: a refused token stops the run."""
    if reply.status == 401 or reply.status == 403:
        raise Error(
            STOP
            + what
            + " answered HTTP "
            + String(reply.status)
            + ". The token is wrong or has expired. Sign in on mixamo.com,"
            " and copy a new access_token."
        )
    if reply.status < 200 or reply.status >= 300:
        raise Error(what + " answered HTTP " + String(reply.status))
    return reply.body


@fieldwise_init
struct Options(Copyable, Movable):
    """What a run downloads, and how."""

    var character: String
    """The id of the character to export for, as `primary_character` finds
    it."""
    var output: String
    """The folder for the files."""
    var query: String
    """Only animations whose name has this text, or empty for all."""
    var limit: Int
    """Stop after this many new files, or zero for no limit."""
    var format: String
    """The file format, `fbx7` unless the page offers another."""
    var fps: Int
    """Frames a second."""
    var in_place: Bool
    """True to ask Mixamo to keep the hips in place."""
    var pause: Float64
    """Seconds between two animations."""
    var polls: Int
    """How many times to ask about an export before giving up on it."""
    var list_only: Bool
    """True to print the names and download nothing."""


struct Report(Movable):
    """What a run did."""

    var saved: Int
    """Files written."""
    var kept: Int
    """Files that were already there."""
    var packs: Int
    """Bundles skipped: their animations are in the list on their own."""
    var failed: List[String]
    """One line for each animation that failed, with the reason."""

    def __init__(out self):
        """Start with nothing done."""
        self.saved = 0
        self.kept = 0
        self.packs = 0
        self.failed = List[String]()


def _file_exists(path: String) -> Bool:
    """Return True if a file is there."""
    return Path(path).exists()


def read_index(folder: String) raises -> List[Entry]:
    """Read `animations.json` of a folder.

    Args:
        folder: The folder.

    Returns:
        An entry for each file listed. Empty when there is no index.

    Raises:
        Error: If the index is not what `write_index` writes.
    """
    var entries = List[Entry]()
    var path = folder + "/" + INDEX
    if not _file_exists(path):
        return entries^
    var document = parse_json(Path(path).read_text())
    var root = document.root()
    if document.kind(root) != ARRAY:
        raise Error(path + " is not a list")
    for index in range(document.length(root)):  # pragma: no branch
        var item = document.at(root, index)
        entries.append(
            Entry(
                _text(document, document.get(item, "id"), "id"),
                _text(document, document.get(item, "name"), "name"),
                _text(document, document.get(item, "file"), "file"),
            )
        )
    return entries^


def write_index(folder: String, entries: List[Entry]) raises:
    """Write `animations.json`: the id, name and file of each animation.

    Args:
        folder: The folder.
        entries: One entry for each file.

    Raises:
        Error: If the file cannot be written.
    """
    var text = String("[")
    for index in range(len(entries)):  # pragma: no branch
        if index > 0:
            text += ","
        text += (
            "\n  "
            + '{"id":'
            + quote_json(entries[index].id)
            + ',"name":'
            + quote_json(entries[index].name)
            + ',"file":'
            + quote_json(entries[index].file)
            + "}"
        )
    Path(folder + "/" + INDEX).write_text(text + "\n]\n")


def file_name(product: Product, entries: List[Entry]) -> String:
    """Return the file name for an animation.

    The name is `safe_name` and `.fbx`. If another animation already has
    that file, the animation's id comes before the suffix.

    Args:
        product: The animation.
        entries: The index so far: each file's animation and its name.

    Returns:
        The file name, without a folder.
    """
    var plain = safe_name(product.name) + ".fbx"
    for entry in entries:  # pragma: no branch
        if entry.file == plain and entry.id != product.id:
            var tag = String(
                product.id[byte = : min(8, product.id.byte_length())]
            )
            return safe_name(product.name) + " " + tag + ".fbx"
    return plain^


def looks_like_fbx(data: List[UInt8]) -> Bool:
    """Return True if the bytes start as a binary or an ASCII FBX file.

    Args:
        data: The file's bytes.

    Returns:
        True for `Kaydara FBX Binary` and for a first line `; FBX`.
    """
    var binary = "Kaydara FBX Binary"
    var ascii = "; FBX"
    var head = String(from_utf8_lossy=data[: min(len(data), 32)])
    return head.startswith(binary) or head.startswith(ascii)


def _wait_for_export(
    transport: Transport, character: String, before: String, options: Options
) raises -> String:
    """Poll the monitor until the export is ready; return the address.

    An answer that is complete but names the address of the export before
    this one is the old one, so the poll goes on.
    """
    for _ in range(options.polls):  # pragma: no branch
        var reply = transport.get("/characters/" + character + "/monitor")
        if reply.status == 404:
            raise Error("Mixamo has no export for the character")
        var job = parse_job(_checked(reply, "the monitor"))
        if job.status == "failed":
            raise Error("Mixamo could not export the animation")
        if job.status == "completed" and job.url != before and job.url:
            return job.url
        sleep(options.pause)
    raise Error("the export did not finish in time")


def primary_character(transport: Transport) raises -> String:
    """Return the id of the account's primary character.

    Mixamo exports every animation for one character. The account's primary
    character is the one the site has selected, a system character at first.

    Args:
        transport: How the request goes out.

    Returns:
        The character's id.

    Raises:
        Error: If Mixamo refuses the token, or the answer has no id.
    """
    var text = _checked(
        transport.get("/characters/primary"), "the primary character"
    )
    var document = parse_json(text)
    return _text(
        document,
        document.get(document.root(), "primary_character_id"),
        "primary_character_id",
    )


def _download_one(
    transport: Transport,
    options: Options,
    product: Product,
    path: String,
    mut before: String,
) raises -> Int:
    """Export one animation and write its file; return the file's size."""
    var details = _checked(
        transport.get(
            "/products/"
            + product.id
            + "?similar=0&character_id="
            + options.character
        ),
        "the animation",
    )
    var entry = export_entry(details, options.in_place)
    var body = export_body(
        options.character, entry, product.name, options.format, options.fps
    )
    _ = _checked(transport.post("/animations/export", body), "the export")
    var address = _wait_for_export(
        transport, options.character, before, options
    )
    before = address
    var data = transport.fetch(address)
    if not looks_like_fbx(data):
        raise Error("the file is not an FBX file")
    # The file is whole before it has its name.
    write_file(path + ".part", Span(data))
    replace_file(path + ".part", path)
    return len(data)


def download_all(transport: Transport, options: Options) raises -> Report:
    """Download every animation that the list holds.

    Args:
        transport: How the requests go out.
        options: What to download, and where to put it.

    Returns:
        What happened. An animation that fails is listed in `failed` and the
        run goes on to the next.

    Raises:
        Error: If Mixamo refuses the token, the list cannot be read, or the
            folder cannot be written.
    """
    var report = Report()
    var entries = read_index(options.output)
    make_dirs(options.output)
    var before = String()
    var baseline = transport.get(
        "/characters/" + options.character + "/monitor"
    )
    if baseline.status == 401 or baseline.status == 403:
        _ = _checked(baseline, "the monitor")
    if baseline.status == 200 or baseline.status == 202:
        try:
            before = parse_job(baseline.body).url
        except:
            before = String()
    # Mixamo's list has no stable order, whatever `order` says. A page can
    # repeat an animation that an earlier page held, and leave another out.
    # So the run reads the list again until it has seen every animation
    # that the list counts, or a whole pass shows nothing new.
    var seen = Dict[String, Bool]()
    var pass_count = 0
    var more = True
    while more:
        pass_count += 1
        var fresh = 0
        var total = 0
        var page = 1
        var pages = 1
        while page <= pages:
            var listing = parse_listing(
                _checked(
                    transport.get(
                        "/products?page="
                        + String(page)
                        + "&limit="
                        + String(PAGE_SIZE)
                        + "&order=&type=Motion%2CMotionPack&query="
                        + url_encode(options.query)
                    ),
                    "the list",
                )
            )
            pages = listing.pages
            total = listing.total
            for product in listing.products:  # pragma: no branch
                if product.id in seen:
                    continue
                seen[product.id] = True
                fresh += 1
                if product.kind != "Motion":
                    report.packs += 1
                    continue
                if options.list_only:
                    print(product.name)
                    continue
                var file = file_name(product, entries)
                var path = options.output + "/" + file
                if _file_exists(path):
                    report.kept += 1
                    continue
                if options.limit > 0 and report.saved >= options.limit:
                    return report^
                try:
                    var size = _download_one(
                        transport, options, product, path, before
                    )
                    entries.append(Entry(product.id, product.name, file))
                    write_index(options.output, entries)
                    report.saved += 1
                    print("saved", file, "(", size, "bytes )")
                except failure:
                    var message = String(failure)
                    if message.startswith(STOP):
                        raise Error(message)
                    report.failed.append(product.name + ": " + message)
                    print("failed", product.name, ":", message)
                sleep(options.pause)
            page += 1
        var complete = total > 0 and len(seen) >= total
        more = fresh > 0 and not complete and pass_count < MAX_PASSES
    return report^
