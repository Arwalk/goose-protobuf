#!/usr/bin/env python3
"""Encode and decode times of generated code, against protobuf C++ on the same bytes.

Usage: scripts/bench_codec.py [--check] [--seconds S] [--rounds N] [message...]
Prints a Markdown table for docs/benchmarks.md, then the versions it ran with. With
--check it takes a moment, and exits 1 if the two differ on what a message encodes to in
size or either fails, so that CI keeps the script working. Its figures then mean nothing.
Needs the C++ library that scripts/build_runner.sh leaves in build/pb. Linux only, as it
links with --start-group.
Env: PLUGIN (default build/protoc-gen-goose, from scripts/build_plugin.sh),
     PROTOC, GOOSE, CXX (default protoc, goose, c++; .tools/bin first)
"""
import argparse
import glob
import os
import platform
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tests", "bench", "codec")
PB = os.path.join(ROOT, "build", "pb")
WORDS = ("request served cache miss retry timeout upstream connection closed "
         "user session token expired payload accepted queue drained").split()
LEVELS = ("info", "warning", "error")


def sentence(rng, words):
    return " ".join(rng.choice(WORDS) for _ in range(words))


def fill_record(rng, r):
    r.timestamp = 1_700_000_000_000 + rng.randrange(10**9)
    r.level = rng.randrange(4)
    r.service = "service-" + str(rng.randrange(100))
    r.message = sentence(rng, 12)
    r.duration = rng.random() * 100
    for key in ("host", "region", "version"):
        label = r.labels.add()
        label.key = key
        label.value = rng.choice(WORDS)
    r.trace = rng.getrandbits(62)


def inputs(pb):
    """Each message's bytes. The seed fixes them, and the values are of no one's data."""
    rng = random.Random(20261106)
    out = {}
    m = pb.Small(name="Ada Lovelace", id=1815, email="ada@example.org", active=True)
    out["Small"] = m
    m = pb.Record()
    fill_record(rng, m)
    out["Record"] = m
    m = pb.Batch()
    for _ in range(1000):
        fill_record(rng, m.records.add())
    out["Batch"] = m
    # Varints of mixed lengths, as values usually are.
    m = pb.Ints(values=[rng.getrandbits(rng.randrange(1, 40)) for _ in range(10000)])
    out["Ints"] = m
    m = pb.Strings(values=[sentence(rng, rng.randrange(1, 5)) for _ in range(1000)])
    out["Strings"] = m
    m = pb.Blob(data=rng.randbytes(1 << 20))
    out["Blob"] = m
    m = pb.Table()
    for i in range(1000):
        m.counts[f"{rng.choice(WORDS)}-{i}"] = rng.randrange(10**6)
    out["Table"] = m
    return {name: msg.SerializeToString(deterministic=True) for name, msg in out.items()}


def run(*cmd, **kw):
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)
    if p.returncode != 0:
        sys.exit(f"error: {' '.join(cmd)}:\n{p.stdout}")
    return p.stdout


def build_cpp(tmp, protoc, cxx):
    libs = glob.glob(os.path.join(PB, "_deps/absl-build/absl/**/*.a"), recursive=True)
    libs += glob.glob(os.path.join(PB, "third_party/utf8_range/*.a"))
    run(protoc, f"--cpp_out={tmp}", "-I", SRC, "codec.proto")
    run(cxx, "-std=c++17", "-O2", "-DNDEBUG", "-w",
        "-I", tmp, "-I", os.path.join(ROOT, "third_party/protobuf/src"),
        "-I", os.path.join(PB, "_deps/absl-src"),
        "-I", os.path.join(ROOT, "third_party/protobuf/third_party/utf8_range"),
        os.path.join(SRC, "bench.cc"), os.path.join(tmp, "codec.pb.cc"),
        os.path.join(PB, "libprotobuf.a"),
        "-Wl,--start-group", *libs, "-Wl,--end-group", "-lpthread", "-o", os.path.join(tmp, "bench_cc"))


def build_goose(tmp, protoc, goose, plugin):
    work = os.path.join(tmp, "goose")
    os.mkdir(work)
    run(os.path.join(ROOT, "scripts/vendor_runtime.sh"), work)
    run(protoc, f"--plugin=protoc-gen-goose={plugin}", f"--goose_out={work}", "-I", SRC, "codec.proto")
    run("cp", os.path.join(SRC, "bench.goose"), work)
    run(goose, "build", "bench.goose", "-o", os.path.join(tmp, "bench_goose"), cwd=work)


def python_bindings(tmp, protoc):
    run(protoc, f"--python_out={tmp}", "-I", SRC, "codec.proto")
    sys.path[:0] = [tmp, os.path.join(ROOT, ".tools", "python")]
    import codec_pb2
    return codec_pb2


def per_op(ns):
    return f"{ns / 1000:,.2f} µs" if ns < 10**6 else f"{ns / 10**6:,.2f} ms"


def speed(size, ns):
    return f"{size * 1000 / ns:,.0f} MB/s"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--seconds", type=float, default=1.0)
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("messages", nargs="*")
    args = ap.parse_args()
    if args.check:
        args.seconds, args.rounds = 0.01, 1

    tools = os.path.join(ROOT, ".tools", "bin")
    if os.path.isdir(tools):
        os.environ["PATH"] = tools + os.pathsep + os.environ["PATH"]
    protoc = os.environ.get("PROTOC", "protoc")
    goose = os.environ.get("GOOSE", "goose")
    cxx = os.environ.get("CXX", "c++")
    plugin = os.environ.get("PLUGIN")
    if not plugin:
        run(os.path.join(ROOT, "scripts/build_plugin.sh"))
        plugin = os.path.join(ROOT, "build", "protoc-gen-goose")
    if not os.path.exists(os.path.join(PB, "libprotobuf.a")):
        sys.exit("error: no build/pb/libprotobuf.a; run scripts/build_runner.sh")

    with tempfile.TemporaryDirectory() as tmp:
        data = inputs(python_bindings(tmp, protoc))
        build_goose(tmp, protoc, goose, plugin)
        build_cpp(tmp, protoc, cxx)
        print("| Message | Bytes | Decode: Goose | C++ | Encode: Goose | C++ |")
        print("|---|---:|---:|---:|---:|---:|")
        bad = False
        for name, payload in data.items():
            if args.messages and name not in args.messages:
                continue
            path = os.path.join(tmp, name + ".bin")
            with open(path, "wb") as f:
                f.write(payload)
            a = [name, path, str(args.seconds), str(args.rounds)]
            gs = run(os.path.join(tmp, "bench_goose"), *a).split()
            cc = run(os.path.join(tmp, "bench_cc"), *a).split()
            size = int(gs[1])
            if gs[2] != cc[2] or int(cc[2]) != size:
                print(f"error: {name}: {size} bytes in, Goose wrote {gs[2]}, C++ wrote {cc[2]}", file=sys.stderr)
                bad = True
            gd, ge, cd, ce = int(gs[3]), int(gs[4]), int(cc[3]), int(cc[4])
            print(f"| {name} | {size:,} | {per_op(gd)} ({speed(size, gd)}) | {per_op(cd)} ({speed(size, cd)}) "
                  f"| {per_op(ge)} ({speed(size, ge)}) | {per_op(ce)} ({speed(size, ce)}) |")
        print()
        print(f"goose: {run(goose, 'version').strip()}; toolchain: "
              + run(goose, "toolchain").splitlines()[0].split(":", 1)[1].strip())
        print(f"c++: {run(cxx, '--version').splitlines()[0]}; {run(protoc, '--version').strip()}")
        print(f"machine: {platform.machine()}, {platform.system()} {platform.release()}")
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
