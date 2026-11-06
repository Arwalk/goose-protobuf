#!/usr/bin/env python3
"""Runs a guide: every code block in the Markdown files named must say what it is.

  ```proto file=x  or  ```goose file=x   appended to file x
  ```sh run                              run with bash, in order
  ```text output                         what the last `sh run` block must print

The blocks run in a new directory `app`, next to a link `goose-protobuf` to this
repository, so a guide's paths work as they read. Each guide has a new home with
~/.local/bin on PATH, so what it installs goes nowhere else and it starts with no
Goose packages. A block with no such label is a failure, and so is a guide with
snippets and no command, so none goes unchecked.

Usage: scripts/check_docs.py [file.md...]   (default docs/quickstart.md docs/usage.md)
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FENCE = re.compile(r"^```(.*)$")


def blocks(text):
    """Yields (line number, info string, body) for each fenced block."""
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = FENCE.match(lines[i])
        if not m:
            i += 1
            continue
        start = i + 1
        i += 1
        body = []
        while i < len(lines) and not FENCE.match(lines[i]):
            body.append(lines[i])
            i += 1
        i += 1
        yield start, m.group(1).strip(), "\n".join(body) + "\n"


def check(path):
    """Returns a list of problems."""
    env = dict(os.environ)
    tools = ROOT / ".tools/bin"
    if tools.is_dir():
        env["PATH"] = f"{tools}{os.pathsep}{env['PATH']}"
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        home.mkdir()
        env["HOME"] = str(home)
        env.pop("GOOSE_HOME", None)
        env["PATH"] = f"{home}/.local/bin{os.pathsep}{env['PATH']}"
        (Path(tmp) / "goose-protobuf").symlink_to(ROOT)
        app = Path(tmp) / "app"
        app.mkdir()
        written = {}
        last = None
        for line, info, body in blocks(path.read_text()):
            where = f"{path}:{line}"
            m = re.fullmatch(r"(proto|goose) file=(\S+)", info)
            if m:
                written[m.group(2)] = written.get(m.group(2), "") + body
                (app / m.group(2)).write_text(written[m.group(2)])
            elif info == "sh run":
                p = subprocess.run(["bash", "-euo", "pipefail", "-c", body], cwd=app, env=env,
                                   capture_output=True, text=True, timeout=600)
                if p.returncode != 0:
                    return [f"{where}: exit {p.returncode}\n{p.stdout}{p.stderr}"]
                last = p.stdout
            elif info == "text output":
                # Goose's build prints its own progress: the program's output ends it.
                if last is None or not last.endswith(body):
                    return [f"{where}: output differs; the command printed:\n{last}"]
            else:
                return [f"{where}: a block needs a label, not '{info}'; see scripts/check_docs.py"]
        if last is None and written:
            return [f"{path}: blocks wrote {sorted(written)} but no command ran"]
    return []


def main():
    files = [Path(a) for a in sys.argv[1:]] or [ROOT / "docs/quickstart.md", ROOT / "docs/usage.md"]
    bad = 0
    for path in files:
        problems = check(path)
        for problem in problems:
            print(f"FAIL {problem}")
            bad = 1
        if not problems:
            print(f"ok   {path}")
    return bad


if __name__ == "__main__":
    sys.exit(main())
