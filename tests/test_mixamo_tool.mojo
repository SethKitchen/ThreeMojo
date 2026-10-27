# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the Mixamo downloader and the bake of its files.

No test opens a network connection. A stub `curl` answers each request as
Mixamo's server does: a list of two pages, an animation's details, an
export, a monitor that first shows the last export's result and then
finishes, and a file. The stub logs each run, so a test can show that the
token is in no command line.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.humanoid.rig.mixamo import MixamoOptions
from extensions.humanoid.sex import MALE
from loaders.gltf import read_gltf
from std.os import remove
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from tests._carla_tool_files import (
    get_text,
    put,
    remove_tree,
    scratch,
    stub_program,
)
from tests._mixamo_fixture import Motion, mixamo_text
from tools._carla_files import path_exists
from tools._mixamo import (
    Entry,
    Options,
    Product,
    Transport,
    download_all,
    export_body,
    export_entry,
    file_name,
    looks_like_fbx,
    parse_job,
    parse_listing,
    read_index,
    require_token,
    safe_name,
    url_encode,
    write_index,
)
from tools._mixamo_bake import _unique, bake_mixamo, fbx_files
from tools.mixamo import run
from units.si import FOOT, Length

comptime FBX = "; FBX 7.4.0 project file"


def _listing(pages: Int, items: List[String], total: Int = -1) -> String:
    """Return a page of the list: each item is `id|name|type`.

    A total above zero is `num_results`, and zero leaves it out. The default
    counts the items, which is right for a list of one page.
    """
    var count = len(items) if total < 0 else total
    var text = String('{"pagination":{"page":1,"num_pages":') + String(pages)
    if count > 0:
        text += ',"num_results":' + String(count)
    text += '},"results":['
    for index in range(len(items)):
        var parts = items[index].split("|")
        if index > 0:
            text += ","
        text += (
            '{"id":"'
            + String(parts[0])
            + '","name":"'
            + String(parts[1])
            + '","type":"'
            + String(parts[2])
            + '"}'
        )
    return text + "]}"


def _details() -> String:
    """Return an animation's details."""
    return (
        '{"id":"x","details":{"gms_hash":{"model-id":103120902,'
        '"mirror":false,"trim":[0,100],"overdrive":0,'
        '"params":[["Overdrive",0,0,100,1],["Arm Space",37.5,0,100,1]],'
        '"arm-space":0,"inplace":false}}}'
    )


def _fake(
    folder: String,
    pages: List[String],
    status: Int = 200,
    refuse_first: Int = 0,
    later: List[String] = List[String](),
) raises -> String:
    """Write a stub `curl`, and the state it keeps, into a folder.

    The stub starts no program but the shell. A request that starts `cp`,
    `sed` and `cat` takes ten times as long, and a test that makes a dozen
    requests would take longer than the time limit under load.

    Args:
        folder: Where the stub and its state go.
        pages: The JSON of each page of the list.
        status: The status of every answer of `/products`.
        refuse_first: How many answers of `/products` are HTTP 429 first.
        later: The pages that the second and later reads of the list get,
            as Mixamo's list shifts between reads. Empty for the same pages.

    Returns:
        The stub's path.
    """
    for stale in ["last.body", "polls", "refused", "lists"]:
        if path_exists(folder + "/" + String(stale)):
            remove(folder + "/" + String(stale))
    put(folder + "/lasturl", "https://files.example/old.fbx")
    var pages_case = String()
    for index in range(len(pages)):
        pages_case += (
            "      0-"
            + String(index + 1)
            + ") printf %s '"
            + pages[index]
            + '\' > "$out";;\n'
        )
        var again = pages[index]
        if len(later) > index:
            again = later[index]
        pages_case += (
            "      1-"
            + String(index + 1)
            + ") printf %s '"
            + again
            + '\' > "$out";;\n'
        )
    var files_case = (
        "  old.fbx) printf %s '"
        + FBX
        + ' old\' > "$out";;\n'
        + "  Junk.fbx) printf %s 'this is a web page' > \"$out\";;\n"
    )
    for name in ["Walk Forward", "Idle", "Run"]:
        files_case += (
            '  "'
            + String(name)
            + ".fbx\") printf %s '"
            + FBX
            + " "
            + String(name)
            + '\' > "$out";;\n'
        )
    var program = folder + "/curl"
    stub_program(
        program,
        "dir='"
        + folder
        + "'\n"
        + "out=; url=; data=; method=GET; hdr=\n"
        + "while [ $# -gt 0 ]; do\n"
        + '  case "$1" in\n'
        + "    --output) out=$2; shift;;\n"
        + "    --url) url=$2; shift;;\n"
        + "    --data-binary) data=${2#@}; shift;;\n"
        + "    --request) method=$2; shift;;\n"
        + "    --header) hdr=${2#@}; shift;;\n"
        + "    --write-out|--connect-timeout|--max-time) shift;;\n"
        + "  esac\n"
        + "  shift\n"
        + "done\n"
        + 'echo "$method $url $*" >> "$dir/curl.log"\n'
        + 'if [ -n "$hdr" ]; then\n'
        + '  while read -r line; do echo "$line"; done < "$hdr"'
        + ' > "$dir/headers.seen"\n'
        + "fi\n"
        + "code="
        + String(status)
        + "\n"
        + 'case "$url" in\n'
        + '  *"/products?page="*)\n'
        + "    n=0\n"
        + '    [ -f "$dir/refused" ] && read n < "$dir/refused"\n'
        + "    if [ $n -lt "
        + String(refuse_first)
        + " ]; then\n"
        + '      echo $((n+1)) > "$dir/refused"; code=429\n'
        + "    else\n"
        + "      c=0\n"
        + '      [ -f "$dir/lists" ] && read c < "$dir/lists"\n'
        + '      c=$((c+1)); echo $c > "$dir/lists"\n'
        + "      pass=$(( (c-1) / "
        + String(len(pages))
        + " )); [ $pass -gt 1 ] && pass=1\n"
        + "      page=${url#*page=}; page=${page%%&*}\n"
        + '      case "$pass-$page" in\n'
        + pages_case
        + "      esac\n"
        + "    fi;;\n"
        + "  */characters/primary) printf %s '"
        + '{"primary_character_id":"primary-9","primary_character_name":"X'
        ' Bot"}'
        + '\' > "$out";;\n'
        + "  */products/*) printf %s '"
        + _details()
        + '\' > "$out";;\n'
        + "  */animations/export)\n"
        + '    read -r line < "$data"; printf %s "$line" > "$dir/last.body"\n'
        + '    echo "{}" > "$out"; code=202; echo 0 > "$dir/polls";;\n'
        + "  */monitor)\n"
        + '    if [ ! -f "$dir/last.body" ]; then\n'
        + '      printf %s \'{"status":"completed",'
        + '"job_result":"https://files.example/old.fbx"}\' > "$out"\n'
        + "    else\n"
        + '      read n < "$dir/polls"; n=$((n+1)); echo $n > "$dir/polls"\n'
        + '      read -r line < "$dir/last.body"\n'
        + '      name=${line#*\\"product_name\\":\\"}; name=${name%%\\"*}\n'
        + '      new="https://files.example/$name.fbx"\n'
        + '      read last < "$dir/lasturl"\n'
        + '      if [ "$name" = Crash ] && [ $n -eq 2 ]; then\n'
        + '        printf %s \'{"status":"failed"}\' > "$out"\n'
        + "      elif [ $n -eq 1 ]; then\n"
        + '        printf %s "{\\"status\\":\\"completed\\",\\"job_result\\":'
        + '\\"$last\\"}" > "$out"\n'
        + '      elif [ "$name" = Run ] && [ $n -eq 2 ]; then\n'
        + '        printf %s \'{"status":"processing"}\' > "$out"\n'
        + "      else\n"
        + '        printf %s "{\\"status\\":\\"completed\\",\\"job_result\\":'
        + '\\"$new\\"}" > "$out"\n'
        + '        printf %s "$new" > "$dir/lasturl"\n'
        + "      fi\n"
        + "    fi;;\n"
        + "  https://files.example/*)\n"
        + '    case "${url##*/}" in\n'
        + files_case
        + "    esac;;\n"
        + "esac\n"
        + 'printf %s "$code"\n',
    )
    return program^


def _options(folder: String) -> Options:
    """Return options that download into `folder`, with no waits."""
    return Options(
        "character-1", folder + "/out", "", 0, "fbx7", 30, False, 0.0, 6, False
    )


def _transport(program: String) -> Transport:
    """Return a transport for the stub, with no waits."""
    return Transport("secret-token", program, "https://api.example/v1", 0.0, 3)


def test_a_list_page_is_read() raises:
    var page = parse_listing(
        _listing(3, ["a|Walk|Motion", "b|Pack|MotionPack"], 0)
    )
    assert_equal(page.pages, 3)
    assert_equal(page.total, 0)
    assert_equal(len(page.products), 2)
    assert_equal(
        parse_listing(_listing(3, ["a|Walk|Motion"], 2484)).total, 2484
    )
    assert_equal(page.products[0].id, "a")
    assert_equal(page.products[0].name, "Walk")
    assert_equal(page.products[1].kind, "MotionPack")
    # An item with no type is a motion.
    var plain = parse_listing(
        '{"pagination":{"num_pages":1},"results":[{"id":"c","name":"Run"}]}'
    )
    assert_equal(plain.products[0].kind, "Motion")
    with assert_raises(contains="no results"):
        _ = parse_listing('{"pagination":{"num_pages":1}}')
    with assert_raises(contains="no pagination"):
        _ = parse_listing('{"results":[]}')
    with assert_raises(contains="no text at name"):
        _ = parse_listing(
            '{"pagination":{"num_pages":1},"results":[{"id":"c"}]}'
        )


def test_an_export_asks_for_the_defaults_as_one_string() raises:
    var entry = export_entry(_details(), False)
    assert_equal(
        entry,
        (
            '{"model-id":103120902,"mirror":false,"trim":[0,100],"overdrive":0,'
            '"params":"0,37.5","arm-space":0,"inplace":false}'
        ),
    )
    # In place sets the flag that is there, or adds one that is not.
    assert_true(export_entry(_details(), True).endswith('"inplace":true}'))
    var bare = (
        '{"details":{"gms_hash":{"model-id":1,"params":[["Speed","fast"]]}}}'
    )
    assert_equal(
        export_entry(bare, True),
        '{"model-id":1,"params":"fast","inplace":true}',
    )
    with assert_raises(contains="no gms_hash"):
        _ = export_entry('{"details":{}}', False)
    with assert_raises(contains="no gms_hash"):
        _ = export_entry("{}", False)
    assert_equal(
        export_body("c-1", "{}", 'Walk "A"', "fbx7", 24),
        (
            '{"character_id":"c-1","gms_hash":[{}],"preferences":{"format":"fbx7","skin":"false","fps":"24","reducekf":"0"},"product_name":"Walk'
            ' \\"A\\"","type":"Motion"}'
        ),
    )


def test_a_list_that_shifts_between_reads_is_read_until_it_is_whole() raises:
    var folder = scratch()
    # The first read shows a twice and never b. The second shows b.
    var program = _fake(
        folder,
        [_listing(1, ["a|Walk Forward|Motion", "a|Walk Forward|Motion"], 2)],
        later=[_listing(1, ["c|Idle|Motion", "a|Walk Forward|Motion"], 2)],
    )
    var report = download_all(_transport(program), _options(folder))
    assert_equal(report.saved, 2)
    assert_equal(len(report.failed), 0)
    assert_true(path_exists(folder + "/out/Idle.fbx"))
    # Two reads of one page, and the second ends the run: both are in.
    assert_equal(get_text(folder + "/curl.log").count("products?page="), 2)
    remove_tree(folder)


def test_a_list_that_never_shows_an_animation_ends_after_a_pass_with_none_new() raises:
    var folder = scratch()
    var program = _fake(folder, [_listing(1, ["a|Walk Forward|Motion"], 2)])
    var report = download_all(_transport(program), _options(folder))
    assert_equal(report.saved, 1)
    # The second read finds nothing new, so there is no third.
    assert_equal(get_text(folder + "/curl.log").count("products?page="), 2)
    remove_tree(folder)


def test_a_monitor_answer_is_read() raises:
    var done = parse_job(
        '{"status":"completed","job_result":"https://x/y.fbx"}'
    )
    assert_equal(done.status, "completed")
    assert_equal(done.url, "https://x/y.fbx")
    var waiting = parse_job('{"status":"processing","job_result":null}')
    assert_equal(waiting.status, "processing")
    assert_equal(waiting.url, "")
    with assert_raises(contains="no text at status"):
        _ = parse_job("{}")


def test_names_tokens_and_addresses_are_made_safe() raises:
    assert_equal(safe_name("Walking (Forward)"), "Walking (Forward)")
    assert_equal(safe_name("a/b\\c:d*e?f"), "a_b_c_d_e_f")
    assert_equal(safe_name("  .hidden  "), "hidden")
    assert_equal(safe_name("..."), "animation")
    assert_equal(safe_name(""), "animation")
    assert_equal(safe_name("Zoë"), "Zo__")
    assert_equal(safe_name("x" * 300).byte_length(), 100)
    assert_equal(
        url_encode("Walk & run/é~-_."), "Walk%20%26%20run%2F%C3%A9~-_."
    )
    assert_equal(require_token("  abc.def  \n"), "abc.def")
    assert_equal(require_token("Bearer abc"), "abc")
    with assert_raises(contains="empty"):
        _ = require_token("  \n")
    with assert_raises(contains="inside"):
        _ = require_token("abc def")
    with assert_raises(contains="inside"):
        _ = require_token("abc\ndef")
    assert_true(looks_like_fbx(List[UInt8](FBX.as_bytes())))
    assert_true(looks_like_fbx(List[UInt8]("Kaydara FBX Binary  ".as_bytes())))
    assert_false(looks_like_fbx(List[UInt8]("<html>".as_bytes())))
    assert_false(looks_like_fbx(List[UInt8]()))


def test_two_animations_with_one_name_get_two_files() raises:
    var entries = List[Entry]()
    entries.append(Entry("11111111-aaaa", "Walk", "Walk.fbx"))
    assert_equal(
        file_name(Product("11111111-aaaa", "Walk", "Motion"), entries),
        "Walk.fbx",
    )
    assert_equal(
        file_name(Product("22222222-bbbb", "Walk", "Motion"), entries),
        "Walk 22222222.fbx",
    )
    assert_equal(file_name(Product("3", "Run", "Motion"), entries), "Run.fbx")


def test_the_index_is_written_and_read_back() raises:
    var folder = scratch()
    assert_equal(len(read_index(folder)), 0)
    var entries = List[Entry]()
    entries.append(Entry("id-1", 'A "quoted" name', "A _quoted_ name.fbx"))
    entries.append(Entry("id-2", "Run", "Run.fbx"))
    write_index(folder, entries)
    var back = read_index(folder)
    assert_equal(len(back), 2)
    assert_equal(back[0].name, 'A "quoted" name')
    assert_equal(back[1].file, "Run.fbx")
    put(folder + "/animations.json", "{}")
    with assert_raises(contains="is not a list"):
        _ = read_index(folder)
    remove_tree(folder)


def test_every_animation_is_downloaded_and_a_second_run_resumes() raises:
    var folder = scratch()
    var program = _fake(
        folder,
        [
            _listing(2, ["b|Pack One|MotionPack"], 2),
            _listing(2, ["a|Walk Forward|Motion"], 2),
        ],
    )
    var report = download_all(_transport(program), _options(folder))
    assert_equal(report.saved, 1)
    assert_equal(report.packs, 1)
    assert_equal(report.kept, 0)
    assert_equal(len(report.failed), 0)
    assert_true(path_exists(folder + "/out/Walk Forward.fbx"))
    assert_false(path_exists(folder + "/out/Walk Forward.fbx.part"))
    assert_true(get_text(folder + "/out/Walk Forward.fbx").startswith("; FBX"))
    var index = read_index(folder + "/out")
    assert_equal(len(index), 1)
    assert_equal(index[0].id, "a")
    assert_equal(index[0].file, "Walk Forward.fbx")
    # The export asked for the character, the defaults and the format.
    var body = get_text(folder + "/last.body")
    assert_true(body.find('"character_id":"character-1"') >= 0)
    assert_true(body.find('"params":"0,37.5"') >= 0)
    assert_true(body.find('"format":"fbx7"') >= 0)
    # A run that starts again fetches nothing it has.
    var before = get_text(folder + "/curl.log").count("\n")
    var again = download_all(_transport(program), _options(folder))
    assert_equal(again.saved, 0)
    assert_equal(again.kept, 1)
    var after = get_text(folder + "/curl.log").count("\n")
    # The monitor's baseline and the two pages, and nothing more.
    assert_equal(after - before, 3)
    remove_tree(folder)


def test_the_token_is_in_a_header_file_and_in_no_command_line() raises:
    var folder = scratch()
    var program = _fake(folder, [_listing(1, ["a|Walk Forward|Motion"])])
    _ = download_all(_transport(program), _options(folder))
    var seen = get_text(folder + "/headers.seen")
    assert_true(seen.find("Authorization: Bearer secret-token") >= 0)
    assert_true(seen.find("X-Api-Key: mixamo2") >= 0)
    assert_equal(get_text(folder + "/curl.log").find("secret-token"), -1)
    # The file's address needs no token, and the stub saw none for it.
    assert_true(get_text(folder + "/curl.log").find("files.example") >= 0)
    remove_tree(folder)


def test_an_animation_that_fails_is_listed_and_the_run_goes_on() raises:
    var folder = scratch()
    # The export of Crash fails, and the one after it is still fetched.
    var program = _fake(
        folder, [_listing(1, ["k|Crash|Motion", "c|Idle|Motion"])]
    )
    var report = download_all(_transport(program), _options(folder))
    assert_equal(report.saved, 1)
    assert_equal(len(report.failed), 1)
    assert_true(report.failed[0].startswith("Crash: "))
    assert_true(report.failed[0].find("could not export") >= 0)
    assert_true(path_exists(folder + "/out/Idle.fbx"))
    remove_tree(folder)


def test_an_export_that_is_still_running_is_asked_about_again() raises:
    var folder = scratch()
    # Run takes a poll longer than the others.
    var program = _fake(folder, [_listing(1, ["r|Run|Motion"])])
    var report = download_all(_transport(program), _options(folder))
    assert_equal(report.saved, 1)
    assert_equal(get_text(folder + "/polls"), "3\n")
    assert_true(path_exists(folder + "/out/Run.fbx"))
    remove_tree(folder)


def test_a_file_that_is_not_an_fbx_is_refused() raises:
    var folder = scratch()
    var program = _fake(folder, [_listing(1, ["j|Junk|Motion"])])
    var report = download_all(_transport(program), _options(folder))
    assert_equal(report.saved, 0)
    assert_equal(len(report.failed), 1)
    assert_true(report.failed[0].find("not an FBX") >= 0)
    assert_false(path_exists(folder + "/out/Junk.fbx"))
    assert_false(path_exists(folder + "/out/Junk.fbx.part"))
    remove_tree(folder)


def test_a_limit_and_a_listing_stop_the_downloads() raises:
    var folder = scratch()
    var program = _fake(
        folder,
        [_listing(1, ["a|Walk Forward|Motion", "c|Idle|Motion"])],
    )
    var limited = _options(folder)
    limited.limit = 1
    var report = download_all(_transport(program), limited)
    assert_equal(report.saved, 1)
    assert_false(path_exists(folder + "/out/Idle.fbx"))
    var names = _options(folder + "/names")
    names.list_only = True
    var listed = download_all(_transport(program), names)
    assert_equal(listed.saved, 0)
    assert_false(path_exists(folder + "/names/out/Idle.fbx"))
    remove_tree(folder)


def test_a_refused_token_stops_the_run() raises:
    var folder = scratch()
    var program = _fake(folder, [_listing(1, ["a|Walk|Motion"])], status=401)
    with assert_raises(contains="Mixamo stopped"):
        _ = download_all(_transport(program), _options(folder))
    var forbidden = _fake(folder, [_listing(1, ["a|Walk|Motion"])], status=403)
    with assert_raises(contains="expired"):
        _ = download_all(_transport(forbidden), _options(folder))
    remove_tree(folder)


def test_a_busy_server_is_asked_again() raises:
    var folder = scratch()
    var program = _fake(
        folder, [_listing(1, ["a|Walk Forward|Motion"])], refuse_first=2
    )
    var report = download_all(_transport(program), _options(folder))
    assert_equal(report.saved, 1)
    remove_tree(folder)


def test_a_server_that_stays_busy_is_an_error() raises:
    var folder = scratch()
    var busy = _fake(
        folder, [_listing(1, ["a|Walk Forward|Motion"])], refuse_first=5
    )
    with assert_raises(contains="HTTP 429"):
        _ = download_all(_transport(busy), _options(folder))
    remove_tree(folder)


def test_a_missing_curl_is_an_error() raises:
    var folder = scratch()
    with assert_raises(contains="curl"):
        _ = download_all(
            Transport("t", folder + "/no-such-curl"), _options(folder)
        )
    remove_tree(folder)


def test_the_command_line_checks_its_options() raises:
    var folder = scratch()
    var program = _fake(folder, [_listing(1, ["a|Walk Forward|Motion"])])
    var transport = _transport(program)
    assert_equal(run(List[String](), "", transport).status, 2)
    assert_equal(run(["--help"], "", transport).status, 0)
    assert_true(run(["--help"], "", transport).out.find("download") >= 0)
    var unknown = run(["fetch"], "", transport)
    assert_equal(unknown.status, 2)
    assert_true(unknown.err.find("no command fetch") >= 0)
    var help = run(["download", "--help"], "", transport)
    assert_equal(help.status, 0)
    assert_true(help.out.find("--character") >= 0)
    var wrong = run(["download", "--nothing"], "", transport)
    assert_equal(wrong.status, 2)
    assert_equal(
        run(
            ["download", "--character", "c", "--format", "dae"], "t", transport
        ).status,
        2,
    )
    assert_equal(
        run(
            ["download", "--character", "c", "--delay", "-1"], "t", transport
        ).status,
        2,
    )
    with assert_raises(contains="--delay must be a number"):
        _ = run(
            ["download", "--character", "c", "--delay", "x"], "t", transport
        )
    with assert_raises(contains="whole number"):
        _ = run(
            ["download", "--character", "c", "--limit", "1.5"], "t", transport
        )
    with assert_raises(contains="environment variable MIXAMO_TOKEN"):
        _ = run(["download", "--character", "c"], "", transport)
    with assert_raises(contains="no token file"):
        _ = run(
            ["download", "--character", "c", "--token-file", folder + "/none"],
            "",
            transport,
        )
    remove_tree(folder)


def test_the_command_line_downloads_with_a_token_from_a_file() raises:
    var folder = scratch()
    var program = _fake(folder, [_listing(1, ["a|Walk Forward|Motion"])])
    put(folder + "/token", "Bearer file-token\n")
    var outcome = run(
        [
            "download",
            "--character",
            "c-9",
            "--output",
            folder + "/files",
            "--token-file",
            folder + "/token",
            "--delay",
            "0",
            "--polls",
            "6",
            "--in-place",
            "--api",
            "https://other.example/v2",
        ],
        "",
        _transport(program),
    )
    assert_equal(outcome.status, 0)
    assert_true(
        get_text(folder + "/curl.log").find("https://other.example/v2/products")
        >= 0
    )
    assert_true(outcome.out.find("saved 1 new files") >= 0)
    assert_true(
        get_text(folder + "/headers.seen").find("Bearer file-token") >= 0
    )
    assert_true(get_text(folder + "/last.body").find('"inplace":true') >= 0)
    assert_true(path_exists(folder + "/files/Walk Forward.fbx"))
    remove_tree(folder)


def test_the_primary_character_is_used_when_none_is_named() raises:
    var folder = scratch()
    var program = _fake(folder, [_listing(1, ["a|Walk Forward|Motion"])])
    var outcome = run(
        [
            "download",
            "--output",
            folder + "/files",
            "--delay",
            "0",
            "--polls",
            "6",
        ],
        "token",
        _transport(program),
    )
    assert_equal(outcome.status, 0)
    assert_true(
        get_text(folder + "/last.body").find('"character_id":"primary-9"') >= 0
    )
    remove_tree(folder)


def test_a_failed_animation_makes_the_status_one() raises:
    var folder = scratch()
    var crash = _fake(folder, [_listing(1, ["k|Crash|Motion"])])
    var failed = run(
        [
            "download",
            "--character",
            "c-9",
            "--output",
            folder + "/more",
            "--delay",
            "0",
            "--polls",
            "6",
        ],
        "token",
        _transport(crash),
    )
    assert_equal(failed.status, 1)
    assert_true(failed.out.find("Crash: ") >= 0)
    remove_tree(folder)


def test_inspect_names_the_bones_and_the_animations() raises:
    var folder = scratch()
    var motions = List[Motion]()
    motions.append(
        Motion("Hips", "T", [0.0, 2.0], [0.0, 0.0], [100.0, 100.0], [0.0, 0.0])
    )
    put(folder + "/Walk.fbx", mixamo_text(motions))
    put(folder + "/Still.fbx", mixamo_text(List[Motion]()))
    var outcome = run(["inspect", folder + "/Walk.fbx"], "", Transport(""))
    assert_equal(outcome.status, 0)
    assert_true(
        outcome.out.find("bones: 27, used by the humanoid: 23 of 23") >= 0
    )
    assert_true(outcome.out.find("animation mixamo.com, 2.0 s, 1 tracks") >= 0)
    var still = run(["inspect", folder + "/Still.fbx"], "", Transport(""))
    assert_equal(still.status, 1)
    assert_true(still.out.find("no animation") >= 0)
    assert_equal(run(["inspect"], "", Transport("")).status, 2)
    assert_equal(run(["inspect", "--help"], "", Transport("")).status, 0)
    remove_tree(folder)


def test_the_bake_options_are_checked() raises:
    var transport = Transport("")
    assert_equal(run(["bake", "--sex", "x"], "", transport).status, 2)
    assert_equal(run(["bake", "--height-feet", "0"], "", transport).status, 2)
    assert_equal(run(["bake", "--fps", "0"], "", transport).status, 2)
    assert_equal(run(["bake", "--help"], "", transport).status, 0)
    assert_equal(run(["bake", "--nothing"], "", transport).status, 2)


def test_the_files_of_a_folder_are_found_in_order() raises:
    var folder = scratch()
    for name in ["b.fbx", "A.FBX", "notes.txt", "c walk.fbx"]:
        put(folder + "/" + String(name), "x")
    var all = fbx_files(folder)
    assert_equal(len(all), 3)
    assert_true(all[0].endswith("/A.FBX"))
    assert_true(all[1].endswith("/b.fbx"))
    var some = fbx_files(folder, "WALK")
    assert_equal(len(some), 1)
    assert_true(some[0].endswith("/c walk.fbx"))
    remove_tree(folder)


def test_a_taken_clip_name_gets_the_first_free_number() raises:
    var taken = List[String]()
    assert_equal(_unique("Walk", taken), "Walk")
    taken.append("Walk")
    taken.append("Walk 3")
    assert_equal(_unique("Walk", taken), "Walk 2")
    taken.append("Walk 2")
    assert_equal(_unique("Walk", taken), "Walk 4")


def test_a_folder_of_files_is_baked_onto_the_humanoid() raises:
    var folder = scratch()
    var motions = List[Motion]()
    motions.append(
        Motion("Hips", "T", [0.0, 1.0], [0.0, 0.0], [100.0, 100.0], [0.0, 0.0])
    )
    motions.append(
        Motion("LeftArm", "R", [0.0, 1.0], [0.0, 0.0], [0.0, 0.0], [0.0, -80.0])
    )
    put(folder + "/Idle.fbx", mixamo_text(motions))
    put(folder + "/Walk.fbx", mixamo_text(motions))
    put(folder + "/Broken.fbx", "not an fbx file")
    var output = folder + "/humanoid.glb"
    var report = bake_mixamo(
        folder,
        output,
        Length(6.0, FOOT),
        MALE,
        3000,
        MixamoOptions(),
        detail=12,
        hand_detail=8,
        hair_detail=8,
    )
    assert_equal(report.clips, 2)
    assert_equal(len(report.skipped), 1)
    assert_true(report.skipped[0].find("Broken.fbx") >= 0)
    var scene = Scene()
    var assets = Assets()
    var model = read_gltf(output, scene, assets)
    assert_equal(len(model.animations), 2)
    assert_equal(model.animations[0].name, "Idle")
    assert_equal(model.animations[1].name, "Walk")
    # Nineteen bones turn, and the hips move.
    assert_equal(model.animations[0].track_count(), 20)
    # The limit keeps the first files only.
    var one = bake_mixamo(
        folder,
        folder + "/one.glb",
        Length(6.0, FOOT),
        MALE,
        3000,
        MixamoOptions(),
        only="idle",
        limit=1,
        detail=12,
        hand_detail=8,
        hair_detail=8,
    )
    assert_equal(one.clips, 1)
    var none_left = scratch()
    put(none_left + "/Broken.fbx", "not an fbx file")
    with assert_raises(contains="No Mixamo animation could be baked"):
        _ = bake_mixamo(
            none_left,
            none_left + "/none.glb",
            Length(6.0, FOOT),
            MALE,
            3000,
            MixamoOptions(),
            detail=12,
            hand_detail=8,
            hair_detail=8,
        )
    remove_tree(none_left)
    remove_tree(folder)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
