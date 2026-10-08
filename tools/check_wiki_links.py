"""Check that wiki links name pages and headings that exist.

    python3 tools/check_wiki_links.py README.md CONTRIBUTING.md docs/wiki/*.md

A wiki page links another as `[text](Page)` or `[text](Page#anchor)`, and the
README links `https://github.com/SethKitchen/ThreeMojo/wiki/Page#anchor`. A
same-page link is `[text](#anchor)`. Each named page must be a file in
`docs/wiki/`, and each anchor must be the slug of a heading on that page.

Slugs follow GitHub: lower case, punctuation removed except `-` and `_`, and
each space becomes `-`. A repeated heading gets `-1`, `-2` and so on.
Fenced code and inline code are not read. Links with a scheme, a path or a
file extension are not wiki links and are not checked.
"""

import re
import sys
from pathlib import Path

WIKI = Path('docs/wiki')
WIKI_URL = 'https://github.com/SethKitchen/ThreeMojo/wiki/'
_LINK = re.compile(r'\]\(([^)\s]+)\)')
_PAGE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_-]*$')
_CODE = re.compile(r'(`+).*?\1')


def _prose_lines(text, strip_code=True):
    """Yield (line number, line) outside fenced code.

    Inline code is removed unless `strip_code` is False.
    """
    fence = None
    for number, line in enumerate(text.split('\n'), 1):
        stripped = line.strip()
        marker = re.match(r'(`{3,}|~{3,})', stripped)
        if marker:
            if fence is None:
                fence = marker[1][0]
            elif marker[1][0] == fence:
                fence = None
            continue
        if fence is None:
            yield number, _CODE.sub('', line) if strip_code else line


def slug(heading):
    """Return GitHub's anchor for a heading's text."""
    text = _CODE.sub(lambda m: m[0].strip('`'), heading)
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    text = text.strip().lower()
    text = re.sub(r'[^\w\- ]', '', text)
    return text.replace(' ', '-')


def anchors(text):
    """Return the set of heading anchors on a page, with repeat suffixes."""
    found = set()
    counts = {}
    for _, line in _prose_lines(text, strip_code=False):
        heading = re.match(r'^#{1,6}\s+(.*?)\s*#*\s*$', line)
        if not heading:
            continue
        base = slug(heading[1])
        count = counts.get(base, 0)
        counts[base] = count + 1
        found.add(base if count == 0 else base + '-' + str(count))
    return found


def check(paths, wiki=None):
    """Return one problem line per broken wiki link in the given files."""
    wiki = WIKI if wiki is None else wiki
    pages = {path.stem: path for path in wiki.glob('*.md')}
    cache = {}

    def page_anchors(name):
        if name not in cache:
            cache[name] = anchors(pages[name].read_text(encoding='utf-8'))
        return cache[name]

    problems = []
    for path in paths:
        path = Path(path)
        text = path.read_text(encoding='utf-8')
        in_wiki = path.parent.resolve() == wiki.resolve()
        for number, line in _prose_lines(text):
            for match in _LINK.finditer(line):
                target = match[1]
                if target.startswith(WIKI_URL):
                    target = target[len(WIKI_URL):]
                elif not in_wiki and not target.startswith('#'):
                    continue
                page, _, anchor = target.partition('#')
                if page == '':
                    if not in_wiki and path.name != 'README.md':
                        continue
                    if anchor and anchor not in anchors(text):
                        problems.append(f'{path}:{number}: no heading for #{anchor}')
                    continue
                if not _PAGE.match(page):
                    continue
                if page not in pages:
                    problems.append(f'{path}:{number}: no wiki page "{page}"')
                elif anchor and anchor not in page_anchors(page):
                    problems.append(f'{path}:{number}: no heading for {page}#{anchor}')
    return problems


def main(argv):
    if len(argv) < 2:
        print('usage: check_wiki_links.py <file.md>...', file=sys.stderr)
        return 2
    problems = check(argv[1:])
    for problem in problems:
        print(problem)
    if problems:
        print(f'{len(problems)} broken wiki links', file=sys.stderr)
        return 1
    print('Wiki links resolve:', len(argv) - 1, 'files.')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
