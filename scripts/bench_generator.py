#!/usr/bin/env python3
"""Time and peak memory of the plugin on large requests, each in a process of its own.

Usage: scripts/bench_generator.py [--check] [shape[=size]...]
Prints: shape size seconds peak_mb. With --check, exits 1 if a run passes its limit.
Env: PLUGIN (default build/protoc-gen-goose, from scripts/build_plugin.sh),
     PROTOC (default protoc; .tools/bin first)
Shapes are what made the generator quadratic: a closure walked per message, a name
looked up per field, a oneof counted per member.
"""
import os
import resource
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CPU_LIMIT = 300


def chain(n):
    # Each message holds the next: the closure of each is all that follow.
    head = 'syntax = "proto2";\npackage scale;\n'
    return {"chain.proto": head + "".join(
        f"message M{i} {{ {f'optional M{i + 1} next = 1; ' if i + 1 < n else ''}optional int32 v = 2; }}\n"
        for i in range(n))}


def ring(n):
    # One cycle through every message: all recursive, and a required field at its end.
    head = 'syntax = "proto2";\npackage scale;\n'
    return {"ring.proto": head + "".join(
        f"message M{i} {{ optional M{(i + 1) % n} next = 1; "
        + ("required int32 r = 2; " if i == n - 1 else "") + "}\n"
        for i in range(n))}


def enums(n):
    head = 'syntax = "proto2";\npackage scale;\n'
    decls = "".join(f"enum E{i} {{ E{i}_A = 0; E{i}_B = 1; }}\n" for i in range(n))
    fields = "".join(f"  optional E{i} f{i} = {i + 1};\n" for i in range(n))
    return {"enums.proto": head + decls + "message All {\n" + fields + "}\n"}


def oneofs(n):
    head = 'syntax = "proto3";\npackage scale;\nmessage All {\n'
    return {"oneofs.proto": head + "".join(
        f"  oneof o{i} {{ int32 f{i} = {i + 1}; }}\n" for i in range(n)) + "}\n"}


def files(n):
    # A file per message, each importing the next, and all of them generated.
    out = {}
    for i in range(n):
        imp = f'import "f{i + 1}.proto";\n' if i + 1 < n else ""
        field = f"M{i + 1} next = 1; " if i + 1 < n else ""
        out[f"f{i}.proto"] = f'syntax = "proto3";\npackage scale;\n{imp}message M{i} {{ {field}int32 v = 2; }}\n'
    return out


# name: (generator, size, seconds limit, MB limit). Well above what the shapes take,
# so that only a change of shape fails, not a slow machine.
SHAPES = {
    "chain": (chain, 8000, 10, 500),
    "ring": (ring, 8000, 10, 500),
    "enums": (enums, 8000, 10, 200),
    "oneofs": (oneofs, 4000, 10, 500),
    "files": (files, 1000, 10, 200),
}


def capture(tmp, protoc, sources):
    for name, text in sources.items():
        with open(os.path.join(tmp, name), "w") as f:
            f.write(text)
    dump = os.path.join(tmp, "dump.sh")
    req = os.path.join(tmp, "req.bin")
    with open(dump, "w") as f:
        f.write(f'#!/bin/sh\ncat >"{req}"\n')
    os.chmod(dump, 0o755)
    # The dump's empty reply says nothing of editions: protoc's status means nothing.
    subprocess.run([protoc, f"--plugin=protoc-gen-dump={dump}", f"--dump_out={tmp}", "-I", tmp, *sources],
                   capture_output=True, check=False)
    if not os.path.exists(req):
        sys.exit("error: no request captured")
    return req


def measure(plugin, req):
    pid = os.fork()
    if pid == 0:
        resource.setrlimit(resource.RLIMIT_CPU, (CPU_LIMIT, CPU_LIMIT))
        os.dup2(os.open(req, os.O_RDONLY), 0)
        os.dup2(os.open(os.devnull, os.O_WRONLY), 1)
        os.execv(plugin, [plugin])
    start = time.monotonic()
    _, status, usage = os.wait4(pid, 0)
    return time.monotonic() - start, usage.ru_maxrss / 1024, status


def main():
    args = sys.argv[1:]
    check = "--check" in args
    args = [a for a in args if a != "--check"]
    tools = os.path.join(ROOT, ".tools", "bin")
    protoc = os.environ.get("PROTOC") or (os.path.join(tools, "protoc") if os.path.isdir(tools) else "protoc")
    plugin = os.environ.get("PLUGIN")
    if not plugin:
        subprocess.run([os.path.join(ROOT, "scripts", "build_plugin.sh")], check=True)
        plugin = os.path.join(ROOT, "build", "protoc-gen-goose")
    bad = 0
    for arg in args or list(SHAPES):
        name, _, size = arg.partition("=")
        make, default, max_s, max_mb = SHAPES[name]
        n = int(size) if size else default
        with tempfile.TemporaryDirectory() as tmp:
            seconds, mb, status = measure(plugin, capture(tmp, protoc, make(n)))
        over = status != 0 or seconds > max_s or mb > max_mb
        note = "" if status == 0 else f" status={status}"
        if check and over:
            note += f" OVER (limit {max_s} s, {max_mb} MB)"
            bad += 1
        print(f"{name} {n} {seconds:.2f} {mb:.0f}{note}", flush=True)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
