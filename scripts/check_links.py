#!/usr/bin/env python3
"""Fails on a relative link in a tracked Markdown file whose target does not exist,
or whose #anchor names no heading of the Markdown file it points to. Links to other
sites are not checked, nor is anything in third_party/ or in code.

Usage: scripts/check_links.py [repository]   (default: this one)
"""
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

FENCE = re.compile(r"^\s*(```|~~~)")
INLINE_CODE = re.compile(r"(`+).*?\1")
# [text](target "title") and ![alt](target), where the text may hold one level of [].
INLINE_LINK = re.compile(r"\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^\s)>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REFERENCE_LINK = re.compile(r"^\s*\[[^\]]+\]:\s*<?([^\s>]+)>?")
HTML_LINK = re.compile(r"<(?:a|img)\s[^>]*?(?:href|src)=\"([^\"]+)\"")
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
HTML_ANCHOR = re.compile(r"<a\s[^>]*?(?:name|id)=\"([^\"]+)\"")
EXTERNAL = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:|^//")


def prose_lines(text, keep_code=False):
    """Yields (line number, line) outside code fences, with inline code removed unless
    keep_code: a heading's inline code is part of its anchor."""
    fence = None
    for number, line in enumerate(text.split("\n"), 1):
        m = FENCE.match(line)
        if m:
            if fence is None:
                fence = m.group(1)
            elif m.group(1) == fence:
                fence = None
            continue
        if fence is None:
            yield number, line if keep_code else INLINE_CODE.sub("", line)


def anchor_of(heading):
    """GitHub's anchor of a heading: links keep their text, then lowercase, no
    punctuation, spaces to hyphens."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading)
    text = re.sub(r"[^\w\- ]", "", text.lower())
    return text.replace(" ", "-")


def anchors_of(path):
    """Every anchor of a Markdown file. GitHub numbers a repeated heading."""
    found = set()
    seen = {}
    for _, line in prose_lines(path.read_text(encoding="utf-8"), keep_code=True):
        found.update(HTML_ANCHOR.findall(line))
        m = HEADING.match(line)
        if m:
            base = anchor_of(m.group(1))
            count = seen.get(base, 0)
            seen[base] = count + 1
            found.add(f"{base}-{count}" if count else base)
    return found


def links_of(text):
    for number, line in prose_lines(text):
        for pattern in (INLINE_LINK, REFERENCE_LINK, HTML_LINK):
            for target in pattern.findall(line):
                yield number, target


def check(root, name):
    """Yields what is wrong with the links of the tracked file `name`."""
    path = root / name
    for number, target in links_of(path.read_text(encoding="utf-8")):
        if EXTERNAL.match(target):
            continue
        file_part, _, anchor = target.partition("#")
        dest = (path.parent / unquote(file_part)).resolve() if file_part else path.resolve()
        if not dest.exists():
            yield f"{name}:{number}: no such file: {target}"
        elif anchor and dest.suffix == ".md" and anchor.lower() not in anchors_of(dest):
            yield f"{name}:{number}: no such heading: {target}"


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).parent.parent).resolve()
    tracked = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.md", ":!third_party/"],
        cwd=root, check=True, capture_output=True, text=True,
    ).stdout.split("\0")
    names = [name for name in tracked if name and (root / name).is_file()]
    problems = [p for name in names for p in check(root, name)]
    for problem in problems:
        print(f"FAIL {problem}")
    if problems:
        print(f"links: {len(problems)} broken, in {len(names)} files")
        return 1
    print(f"links: {len(names)} files ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
